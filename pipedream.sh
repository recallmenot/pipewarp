#!/bin/bash

# Script to automate audio processing with Carla and PipeWire

CARLA_PROJECT="./systemdsp.carxp"
PROCESS_SINK="PipeDreamSink"
VOLUME_STEP=1
RESTORE_ON_CLOSE="yes"  # Set to "yes" to restore Carla when closed, "no" to shut down

# Check if CARLA_PROJECT file exists
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
if pgrep -f "carla" >/dev/null; then
    echo "Warning: Carla is already running. This script will not proceed with an existing instance."
    exit 1
fi

get_ORIGINAL_DEVICE_SINK() {
    ORIGINAL_DEVICE_SINK=$(pactl info | grep "Default Sink" | awk '{print $3}')
    if [ -z "$ORIGINAL_DEVICE_SINK" ]; then
        echo "Error: Could not determine current output sink."
        exit 1
    fi
    echo "Current output sink: $ORIGINAL_DEVICE_SINK"
}

check_existing_sink() {
    if pactl list sinks short | grep -q "$PROCESS_SINK"; then
        echo "Error: Sink '$PROCESS_SINK' already exists and has been destroyed."
        pactl unload-module module-null-sink
        echo "Please check that the correct audio output device is selected and re-launch the script."
        exit 1
    fi
}

create_virtual_sink() {
    pactl load-module module-null-sink sink_name="$PROCESS_SINK" sink_properties="device.description='$PROCESS_SINK'"
    sleep 1
}

route_to_virtual_sink() {
    pactl set-default-sink "$PROCESS_SINK"
    echo "Routing all audio to $PROCESS_SINK"
}

connect_carla_to_output() {
    carla "$CARLA_PROJECT" &
    CARLA_PID=$!
    echo "Waiting for Carla to initialize..."

    # Wait until Carla's audio ports are available
    while true; do
        if pw-cli ls Port | grep -q "Carla:audio-in1" && \
           pw-cli ls Port | grep -q "Carla:audio-out1"; then
            echo "Carla I/O ports detected."
            break
        fi
        echo "Carla I/O not yet available, checking again in 0.2s..."
        sleep 0.2
    done

    # Minimize Carla if on X11 and xdotool is available
    if [ "$XDG_SESSION_TYPE" = "x11" ] && command -v xdotool >/dev/null 2>&1; then
        echo "Detected X11, attempting to minimize Carla with xdotool..."
        TIMEOUT=50  # 50 * 0.2s = 10s
        COUNT=0
        while [ $COUNT -lt $TIMEOUT ]; do
            if xdotool search --onlyvisible --name "Carla" windowminimize >/dev/null 2>&1; then
                echo "Carla minimized."
                break
            fi
            echo "Waiting for Carla main window to appear... ($((COUNT * 2 / 10))s elapsed)"
            sleep 0.2
            COUNT=$((COUNT + 1))
        done
        if [ $COUNT -ge $TIMEOUT ]; then
            echo "Timeout reached; failed to minimize Carla (main window not detected)."
        fi
    elif [ "$XDG_SESSION_TYPE" = "x11" ]; then
        echo "X11 detected, but xdotool is not installed. Carla will not be minimized."
    elif [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        echo "Wayland detected. No universal minimization available; Carla will remain visible."
    else
        echo "Session type ($XDG_SESSION_TYPE); Carla will not be minimized."
    fi

    # Create links with pw-link
    echo "Creating link: $PROCESS_SINK:monitor_FL -> Carla:audio-in1"
    pw-link "$PROCESS_SINK:monitor_FL" "Carla:audio-in1"
    echo "Creating link: $PROCESS_SINK:monitor_FR -> Carla:audio-in2"
    pw-link "$PROCESS_SINK:monitor_FR" "Carla:audio-in2"

    while true; do
        if pw-cli ls Port | grep -q "$ORIGINAL_DEVICE_SINK:playback_FL" && \
           pw-cli ls Port | grep -q "$ORIGINAL_DEVICE_SINK:playback_FR"; then
            echo "$ORIGINAL_DEVICE_SINK output ports detected."
            break
        fi
        echo "$ORIGINAL_DEVICE_SINK output ports not yet available, checking again in 0.2s..."
        sleep 0.2
    done
    echo "Creating link: Carla:audio-out1 -> $ORIGINAL_DEVICE_SINK:playback_FL"
    pw-link "Carla:audio-out1" "$ORIGINAL_DEVICE_SINK:playback_FL"
    echo "Creating link: Carla:audio-out2 -> $ORIGINAL_DEVICE_SINK:playback_FR"
    pw-link "Carla:audio-out2" "$ORIGINAL_DEVICE_SINK:playback_FR"

    echo "Audio routing attempted:"
    pw-link -l | grep -E "($PROCESS_SINK|Carla|$ORIGINAL_DEVICE_SINK)" || echo "No links created"
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
    pw-link -d "$(pw-link -l | grep "$PROCESS_SINK" | awk '{print $1}')" 2>/dev/null
    pw-link -d "$(pw-link -l | grep "Carla" | awk '{print $1}')" 2>/dev/null
    echo "Killing Carla"
    kill "$CARLA_PID" 2>/dev/null
    wait "$CARLA_PID" 2>/dev/null
    echo "Restoring output to $ORIGINAL_DEVICE_SINK"
    pactl unload-module module-null-sink
    pactl set-default-sink "$ORIGINAL_DEVICE_SINK"
    echo "Restoring output volume to $ORIGINAL_VOLUME"
    pactl set-sink-volume "$ORIGINAL_DEVICE_SINK" "$ORIGINAL_VOLUME"
    echo "Cleanup complete."
    exit 0
}

wait_for_session() {
    echo "Waiting for user session and PipeWire to be ready..."
    while true; do
        # Check if PipeWire is running and responsive
        if pw-cli info 0 >/dev/null 2>&1; then
            # Check if the original sink is available
            if pactl list sinks short | grep -q "$ORIGINAL_DEVICE_SINK"; then
                # For graphical session, check if DISPLAY is set (X11) or Wayland is active
                if [ -n "$DISPLAY" ] || [ "$XDG_SESSION_TYPE" = "wayland" ]; then
                    echo "Session and PipeWire are ready."
                    break
                fi
            fi
        fi
        echo "Session or PipeWire not yet ready, checking again in 1s..."
        sleep 1
    done
}

restore_carla() {
    echo "\nCarla has been closed. Attempting to restore..."
    wait_for_session  # Wait until the session and PipeWire are ready
    # Check if sink still exists, recreate if needed
    if ! pactl list sinks short | grep -q "$PROCESS_SINK"; then
        echo "Virtual sink missing, recreating..."
        create_virtual_sink
    fi
    # Ensure sink is default
    route_to_virtual_sink
    # Restart Carla and reconnect
    connect_carla_to_output
    echo -ne "\r$(get_volume)"
}

echo "Starting audio processing setup..."
trap cleanup INT TERM

get_ORIGINAL_DEVICE_SINK
ORIGINAL_VOLUME=$(get_volume)

check_existing_sink
create_virtual_sink
route_to_virtual_sink
connect_carla_to_output

echo "Keyboard shortcuts:"
echo "q     - kill Carla and restore original routing"
echo "↑/↓   - adjust volume of $ORIGINAL_DEVICE_SINK (±$VOLUME_STEP%)"
echo "j/k   - adjust volume of $ORIGINAL_DEVICE_SINK (±$VOLUME_STEP%)"
echo -ne "\r$(get_volume)"

while true; do
    # Check if Carla process is still running
    if ! ps -p "$CARLA_PID" > /dev/null; then
        if [ "$RESTORE_ON_CLOSE" = "yes" ]; then
            restore_carla
        else
            echo "\nCarla has been closed by the user."
            cleanup
        fi
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
