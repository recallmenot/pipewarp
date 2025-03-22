# PipeDream

PipeDream dynamically re-configures pipewire to send audio through Carla for processing in audio plugins (LADSPA, LV2, VST2 and VST3).
This enables a superior audio experience:
 * room correction
 * headphone correction
 * headphne room simulation

## architecture
PipeDream creates an audio sink that becomes the default audio output device for all applications.
The sink passes the audio to Carla, which processes it using the plugins you specify and then sends it to your previously-selected audio outputs.
It expects that there is no running Carla instance so that it can launch it on its own.
Carla is minimized at launch using xdotool if you're on X11, in wayland I'm not certain how to do that.

## volume control
Since PipeDream relies on creating a sink, this sink will capture your system volume control.
I recommend you leave this sink volume at 100% as this will make it losseless.
PipeDream allows you to control the volume of the output device using the arrow keys.

## quitting
PipeDream restores the pior audio output and volume when it is quit or Carla is closed.
I'd advise agains killing PipeDream by closing the terminal window while it's running as it won't be able to restore the audio configuration this way.

## installation
 * install Carla from your package manager
 * install xdotool if you're on X11 (a quick `echo $XDG_SESSION_TYPE` should tell you)
 * plugins can be installed to the usual locations where Carla can find them (e.g. `~/.vst3/`)
 * `git clone https://github.com/recallmenot/pipedream.git`
 * launch Carla
 * settings -> configure -> engine: audio driver JACK, process mode continuous rack
 * restart Carla
 * load your plugins
 * save the profile as `systemdsp.carxp`, in this repo's root dir
 * optionally make pipedream executable (it should already be): `chmod +x pipedream.sh`
 * run: `./pipedream.sh`


# Plugins
## room correction EQ
 * [MathAudio RoomEQ](https://mathaudio.com/room-eq.htm) 
 * Haven't tried Sonarworks in wine yet.
Of cource you'll have to create the correction profile using Carla without PipeDream or in a DAW.

## (headphone) EQ
 * [ZLEquializer](https://github.com/ZL-Audio/ZLEqualizer)
You can look up headphone frequnecy response graphs and even generate EQ profiles on [squiglink](https://squig.link/).
Some of their partners offer the neutral Etymotic target for reference, sounds pretty neutral to me on in-ears.

## headphone room simulator
 * [Cans](https://www.airwindows.com/cans/) in [Airwindows Consolidated](https://github.com/baconpaul/airwin2rack/releases/tag/DAWPlugin): awesome on studio E, diffuse 0.07, damping 0.1, crossfeed 0.3, drywet 0.35
 * [Valhalla Room](https://valhalladsp.com/shop/reverb/valhalla-room/) awesome on "Large Chamber" preset with 0.46s, drywet 14%, 3.2ms

## Windows VSTs
To run the Windows VSTs, use [yabridge](https://github.com/robbert-vdh/yabridge).

## performance
To tune your system for performance, use [rtcqs](https://github.com/autostatic/rtcqs) and follow [yabridge's performance tuning section](https://github.com/robbert-vdh/yabridge?tab=readme-ov-file#performance-tuning).
