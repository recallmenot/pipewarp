#!/usr/bin/env bash

# Script to automate audio processing with Carla and PipeWire

CARLA_PROJECT_DEFAULT="./systemdsp.carxp"
PROCESS_SINK="PipeWarpSink"
VOLUME_STEP=1
RESTORE_ON_CLOSE="yes"  # Set to "yes" to restore Carla when closed, "no" to shut down
CHECK_INTERVAL=5        # Seconds between connection checks

# Parse command line options
while getopts "p:" opt; do
    case $opt in
        p) CARLA_PROJECT="$OPTARG" ;;
        ?) echo "Usage: $0 [-p <carla_project_file>]"
           exit 1 ;;
    esac
done

# If no project specified via -p, use default
CARLA_PROJECT="${CARLA_PROJECT:-$CARLA_PROJECT_DEFAULT}"

# Check if specified CARLA_PROJECT file exists
if [ ! -f "$CARLA_PROJECT" ]; then
    echo "Error: Carla profile could not be found at: $CARLA_PROJECT"
    exit 1
fi

# Check if Carla is installed
if ! command -v carla >/dev/null 2>&1; then
    echo "Error: Carla is not installed. Please install Carla first."
    exit 1
fi

# Check if Carla is already running
if pgrep -f "/bin/carla" >/dev/null; then
    echo "Warning: Carla is already running. This script will not proceed with an existing instance."
    exit 1
fi

get_ORIGINAL_DEVICE_SINK() {
    ORIGINAL_DEVICE_SINK=$(pactl info | grep "Default Sink" | awk '{print $3}')
    if [ -z "$ORIGINAL_DEVICE_SINK" ]; then
        echo "Error: Could not determine current output sink."
        exit 1
    fi

    # Use pw-dump to find the node ID for the sink
    NODE_ID=$(pw-dump | jq -r --arg sink "$ORIGINAL_DEVICE_SINK" \
        '.[] | select(.type == "PipeWire:Interface:Node" and .info.props["node.name"] == $sink) | .id' 2>/dev/null)
    if [ -z "$NODE_ID" ]; then
        echo "Error: Could not find node ID for sink $ORIGINAL_DEVICE_SINK in PipeWire dump."
        exit 1
    fi

    # Find the port alias for playback_FL associated with this node
    ORIGINAL_DEVICE_PORT_FL_ALIAS=$(pw-dump | jq -r --argjson node_id "$NODE_ID" \
        '.[] | select(.type == "PipeWire:Interface:Port" and .info.props["node.id"] == $node_id and .info.props["port.name"] == "playback_FL") | .info.props["port.alias"]' 2>/dev/null)
    if [ -z "$ORIGINAL_DEVICE_PORT_FL_ALIAS" ]; then
        echo "Error: Could not determine PipeWire port alias for $ORIGINAL_DEVICE_SINK:playback_FL."
        echo "Ensure the device is connected and recognized by PipeWire."
        exit 1
    fi

    echo "Current output sink: $ORIGINAL_DEVICE_SINK"
    echo "Node ID for the output sink: $NODE_ID"
    echo "Port alias for playback_FL: $ORIGINAL_DEVICE_PORT_FL_ALIAS"
}

print_audio_routing_status() {
    echo "Audio routing status:"
    pw-link -l 2>/dev/null | grep -E "($PROCESS_SINK|Carla|$ORIGINAL_DEVICE_SINK)" || echo "No links detected"
}

print_info() {
    echo "Keyboard shortcuts:"
    echo "q     - kill Carla and restore original routing"
    echo "↑/↓   - adjust volume of $ORIGINAL_DEVICE_SINK (±$VOLUME_STEP%)"
    echo "j/k   - adjust volume of $ORIGINAL_DEVICE_SINK (±$VOLUME_STEP%)"
    echo -ne "\r$(get_volume)"
}

create_virtual_sink() {
    pactl load-module module-null-sink sink_name="$PROCESS_SINK" sink_properties="device.description='$PROCESS_SINK'"
}

route_to_virtual_sink() {
    pactl set-default-sink "$PROCESS_SINK"
    echo "Routing all audio to $PROCESS_SINK"
}

await_carla_node() {
    local await_interval=0.2
    echo "Awaiting Carla node availability..."
    while true; do
        CARLA_NODE_ID=$(pw-dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props["node.name"] == "Carla") | .id')
        if [ -n "$CARLA_NODE_ID" ] && [ "$CARLA_NODE_ID" != "null" ]; then
            echo "Carla node detected (ID: $CARLA_NODE_ID)"
            break
        fi
        echo "Carla node not yet available, checking in $await_interval s..."
        sleep "$await_interval"
    done
}

await_carla_ports() {
    local await_interval=0.2
    echo "Awaiting Carla IO ports availability..."
    while true; do
        if pw-cli ls Port | grep -q "Carla:audio-in1" && pw-cli ls Port | grep -q "Carla:audio-in2" \
        && pw-cli ls Port | grep -q "Carla:audio-out1" && pw-cli ls Port | grep -q "Carla:audio-out2" \
        ; then
            echo "Carla I/O ports detected."
            break
        fi
        echo "Carla IO not yet available, checking in $await_interval s..."
        sleep "$await_interval"
    done
}

check_dependencies() {
    local should_exit=0

    echo "Checking dependencies..."

    if ! command -v pw-cli >/dev/null 2>&1; then
        echo "pw-cli not found. Are you certain you are using pipewire?"
        should_exit=1
    fi

    if ! command -v pw-link >/dev/null 2>&1; then
        echo "pw-link not found. Are you certain you are using pipewire?"
        should_exit=1
    fi

    if ! command -v carla >/dev/null 2>&1; then
        echo "Carla not found."
        should_exit=1
    fi

    if ! command -v pactl >/dev/null 2>&1; then
        echo "pactl not found. Install pulseaudio but don't enable it."
        should_exit=1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "jq not found. Please install jq for JSON parsing."
        should_exit=1
    fi

    if [ "$XDG_SESSION_TYPE" = "x11" ] && ! command -v xdotool >/dev/null 2>&1; then
        echo "xdotool not found. Carla will not be minimized in X11 session."
    fi

    if [ $should_exit -eq 1 ]; then
        exit 1
    fi
}

start_carla() {
    carla "$CARLA_PROJECT" &
    CARLA_PID=$!
}

minimize_carla() {
    local await_interval=0.2
    if [ "$XDG_SESSION_TYPE" = "x11" ] && command -v xdotool >/dev/null 2>&1; then
        echo "Detected X11, attempting to minimize Carla with xdotool..."
        while true; do
            if xdotool search --onlyvisible --name "Carla" windowminimize >/dev/null 2>&1; then
                echo "Carla minimized."
                break
            fi
            echo "Waiting for Carla main window to appear..."
            sleep "$await_interval"
        done
    elif [ "$XDG_SESSION_TYPE" = "x11" ]; then
        echo "X11 detected, but xdotool not installed."
    else
        echo "Session type ($XDG_SESSION_TYPE); Carla will not be minimized."
    fi
}

# Helper to check if a specific link exists
link_exists() {
    local source="$1"
    local target="$2"
    local links
    links=$(pw-link -l 2>/dev/null)
    local node_connections=""
    local in_block=0
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then continue; fi
        local first_char="${line:0:1}"
        if [[ "$first_char" != " " ]]; then
            if echo "$line" | grep -q "$source"; then
                in_block=1
            else
                in_block=0
            fi
        else
            if [ $in_block -eq 1 ]; then
                node_connections+="$line"$'\n'
            fi
        fi
    done <<< "$links"
    if echo "$node_connections" | grep -q "$target"; then
        return 0
    else
        return 1
    fi
}


disable_carla_autoconnect() {
    pw-cli set-param "$CARLA_NODE_ID" Props '{ node.autoconnect = false, node.dont-reconnect = true }'
    echo "Disabled Carla autoconnect."
}

connect_carla_inputs() {
    pw-link "$PROCESS_SINK:monitor_FL" "Carla:audio-in1"
    pw-link "$PROCESS_SINK:monitor_FR" "Carla:audio-in2"

    # verify result
    if ! link_exists "$PROCESS_SINK:monitor_FL" "Carla:audio-in1" \
    || ! link_exists "$PROCESS_SINK:monitor_FR" "Carla:audio-in2" \
    ; then
        echo "failed to connect Carla inputs to $PROCESS_SINK"
    else
        echo "connected Carla inputs to $PROCESS_SINK"
    fi
}

await_carla_feedback_loop() {
    local await_interval=0.2
    while true; do
        echo "Awaiting Carla feedback loop to $PROCESS_SINK, checking in $await_interval..."
        if link_exists "Carla:audio-out1" "$PROCESS_SINK:playback_FL" \
        && link_exists "Carla:audio-out2" "$PROCESS_SINK:playback_FR" \
        ; then
            break
        fi
        sleep "$await_interval"
    done
}

connect_carla_outputs() {
    pw-link "Carla:audio-out1" "$ORIGINAL_DEVICE_SINK:playback_FL" 2>/dev/null || true
    pw-link "Carla:audio-out2" "$ORIGINAL_DEVICE_SINK:playback_FR" 2>/dev/null || true

    # verify result
    if ! link_exists "Carla:audio-out1" "$ORIGINAL_DEVICE_SINK:playback_FL" \
    || ! link_exists "Carla:audio-out2" "$ORIGINAL_DEVICE_SINK:playback_FR" \
    ; then
        echo "failed to connect Carla outputs to $ORIGINAL_DEVICE_SINK"
    else
        echo "connected Carla outputs to $ORIGINAL_DEVICE_SINK"
    fi
}

disconnect_carla_feedback_loop() {
    # Disconnect existing links
    pw-link -d "Carla:audio-out1" "$PROCESS_SINK:playback_FL" 2>/dev/null || true
    pw-link -d "Carla:audio-out2" "$PROCESS_SINK:playback_FR" 2>/dev/null || true

    echo "Disconnected Carla from $PROCESS_SINK feedback links"

    if link_exists "Carla:audio-out1" "$PROCESS_SINK:playback_FL" \
    || link_exists "Carla:audio-out2" "$PROCESS_SINK:playback_FR" \
    ; then
        echo "Failed to disconnect Carla from $PROCESS_SINK. Beware! You may experience heavy feedback!"
    fi
}

await_hardware_port() {
    local await_interval=0.2
    while true; do
        if pw-cli ls Port | grep -q "$ORIGINAL_DEVICE_PORT_FL_ALIAS"; then
            echo "$ORIGINAL_DEVICE_SINK output port ($ORIGINAL_DEVICE_PORT_FL_ALIAS) detected."
            break
        fi
        echo "$ORIGINAL_DEVICE_SINK output port not yet detected, checking again in $await_interval"
        sleep "$await_interval"
    done
}

connect_carla_io() {
    connect_carla_inputs
    connect_carla_outputs
}

setup_carla_routing() {
    start_carla
    await_carla_node
    await_carla_ports
    disable_carla_autoconnect
    minimize_carla
    await_carla_feedback_loop
    disconnect_carla_feedback_loop
    connect_carla_io
}

check_connections() {
    local connections_altered=0

    if ! check_carla_io_exists; then
        echo "\nCarla IO lost, attempting to reconnect..."
        connect_carla_io
        connections_altered=1
    fi

    if ! check_carla_no_feedback_loop; then
        echo "\nCarla feedback loop detected, attempting to disconnect..."
        disconnect_carla_feedback_loop
        connections_altered=1
    fi

    if [ "$connections_altered" -eq 1 ]; then
        print_audio_routing_status
        print_info
    fi
}

check_carla_io_exists() {
    if ! link_exists "$PROCESS_SINK:monitor_FL" "Carla:audio-in1" \
    || ! link_exists "$PROCESS_SINK:monitor_FR" "Carla:audio-in2" \
    || ! link_exists "Carla:audio-out1" "$ORIGINAL_DEVICE_SINK:playback_FL" \
    || ! link_exists "Carla:audio-out2" "$ORIGINAL_DEVICE_SINK:playback_FR" \
    ; then
        return 1
    fi
    return 0
}


check_carla_no_feedback_loop() {
        if link_exists "Carla:audio-out1" "$PROCESS_SINK:playback_FL" \
        || link_exists "Carla:audio-out2" "$PROCESS_SINK:playback_FR" \
        ; then
            return 1
        fi
        return 0
}

get_volume() {
    pactl get-sink-volume "$ORIGINAL_DEVICE_SINK" | grep -o "[0-9]\+%" | head -1
}

increase_volume() {
    pactl set-sink-volume "$ORIGINAL_DEVICE_SINK" +$VOLUME_STEP%
    echo -ne "\r    "
    echo -ne "\r$(get_volume)"
}

decrease_volume() {
    pactl set-sink-volume "$ORIGINAL_DEVICE_SINK" -$VOLUME_STEP%
    echo -ne "\r    "
    echo -ne "\r$(get_volume)"
}

cleanup() {
    echo "Shutting down"
    echo "Disconnecting Carla"
    pw-link -d "$(pw-link -l 2>/dev/null | grep "$PROCESS_SINK" | awk '{print $1}')" 2>/dev/null
    pw-link -d "$(pw-link -l 2>/dev/null | grep "Carla" | awk '{print $1}')" 2>/dev/null
    echo "Killing Carla"
    kill "$CARLA_PID" 2>/dev/null
    wait "$CARLA_PID" 2>/dev/null
    echo "Restoring output to $ORIGINAL_DEVICE_SINK"
    pactl unload-module module-null-sink >/dev/null 2>&1
    pactl set-default-sink "$ORIGINAL_DEVICE_SINK"
    echo "Restoring output volume to $ORIGINAL_VOLUME"
    pactl set-sink-volume "$ORIGINAL_DEVICE_SINK" "$ORIGINAL_VOLUME"
    echo "Cleanup complete."
    exit 0
}

wait_for_session() {
    local await_interval=0.2
    echo "Waiting for user session and PipeWire to be ready..."
    while true; do
        if pw-cli info 0 >/dev/null 2>&1 && \
           pactl list sinks short | grep -q "$ORIGINAL_DEVICE_SINK"; then
            if [ -n "$DISPLAY" ] || [ "$XDG_SESSION_TYPE" = "wayland" ]; then
                echo "Session and PipeWire are ready."
                break
            fi
        fi
        echo "Session or PipeWire not yet ready, checking again in $await_interval s..."
        sleep "$await_interval"
    done
}

check_virtual_sink() {
    if ! pactl list sinks short | grep -q "$PROCESS_SINK"; then
        return 1
    fi
    return 0
}

check_virtual_sink_startup() {
    if pactl list sinks short | grep -q "$PROCESS_SINK"; then
        echo "Error: Sink '$PROCESS_SINK' already exists and has been destroyed."
        pactl unload-module module-null-sink
        echo "Please check that the correct audio output device is selected and re-launch the script."
        exit 1
    fi
}

restore_carla() {
    echo "\nCarla has been closed. Attempting to restore..."
    wait_for_session
    await_hardware_port
    if ! check_virtual_sink; then
        echo "Virtual sink missing, recreating..."
        create_virtual_sink
    fi
    route_to_virtual_sink
    setup_carla_routing
    echo -ne "\r$(get_volume)"
}

check_dependencies

echo "Starting audio processing setup..."
echo "Loading Carla project: $CARLA_PROJECT"
trap cleanup INT TERM

get_ORIGINAL_DEVICE_SINK
ORIGINAL_VOLUME=$(get_volume)

await_hardware_port
check_virtual_sink_startup
create_virtual_sink
route_to_virtual_sink
setup_carla_routing

print_info

last_check=$(date +%s)
while true; do
    if ! ps -p "$CARLA_PID" > /dev/null; then
        if [ "$RESTORE_ON_CLOSE" = "yes" ]; then
            restore_carla
        else
            echo "\nCarla has been closed by the user."
            cleanup
        fi
    fi

    # Periodic connection check
    current_time=$(date +%s)
    if [ $((current_time - last_check)) -ge $CHECK_INTERVAL ]; then
        check_connections
        last_check=$current_time
    fi

    read -rsn1 -t 0.5 key
    if [[ "$key" == $'\033' ]]; then
        read -rsn2 -t 0.1 extra
        case "$extra" in
            "[A") increase_volume ;;
            "[B") decrease_volume ;;
        esac
    else
        case "$key" in
            "q") echo; cleanup ;;
            "k") increase_volume ;;
            "j") decrease_volume ;;
        esac
    fi
done

# vim: set tabstop=4 shiftwidth=4 expandtab:
