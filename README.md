# pipewarp

Pipewarp dynamically re-configures pipewire to send audio through Carla for processing in audio plugins (LADSPA, LV2, VST2 and VST3).
This enables a superior audio experience:
 * room correction
 * headphone correction
 * headphne room simulation

## architecture
Pipewarp creates an audio sink that becomes the default audio output device for all applications.
The sink passes the audio to Carla, which processes it using the plugins you specify and then sends it to your previously-selected audio outputs.
It expects that there is no running Carla instance so that it can launch it on its own.
Carla is minimized at launch using xdotool if you're on X11, in wayland I'm not certain how to do that.

## installation

### linux
 * install Carla from your package manager
 * install xdotool if you're on X11 (a quick `echo $XDG_SESSION_TYPE` should tell you)
 * plugins can be installed to the usual locations where Carla can find them (e.g. `~/.vst3/`)
 * `git clone https://github.com/recallmenot/pipewarp.git`
 * launch Carla
 * settings -> configure -> engine: audio driver JACK, process mode continuous rack
 * close Carla
 * optionally make pipewarp.sh executable (it should already be): `chmod +x pipewarp.sh`

### nixos
 * pipewarp relies on pipewire and pipewire-jack, so in configuration.nix:
   ```
     services.pipewire = {
       enable = true;
       alsa.enable = true;
       alsa.support32Bit = true;
       pulse.enable = true;
       # If you want to use JACK applications, uncomment this
       jack.enable = true;

       # use the example session manager (no others are packaged yet so this is enabled by default,
       # no need to redefine it in your config for now)
       #media-session.enable = true;
     };
   ```
   Then at least log out and back in again.
 * pipewarp needs `pactl` from `pulseaudio`, so add it to `environment.systemPackages = with pkgs; []` if you don't use the included flake. Your system will still use pipewire since that is what was enabled.

## usage

### profile creation
 * run Carla
 * load your plugins
 * save the profile as `name.carxp`, in this repo's root dir
 * close Carla

### running

#### linux
 * run: `./pipewarp.sh -p name.carxp`. If you leave `-p name.carxp` away, `systemdsp.carxp` is loaded automatically. You can overwrite that file if you only use one output device.

#### nixOS
The NixOS filesystem doesn't follow the Filesystem Hierarchy Standard and Carla won't even be able to locate VSTs in such an environment.
LDD only reveals Carla's immediate dependencies and the package doesn't care to provide any beyond those.

Solution: To start both carla and pipewarp from within an environment that provides the right libraries, start them from within an environment that provides the dependencies of the plugins.

The same applies to profile creation.

Options:
 * use the included flake with `nix run`, then run as if on regular linux (see above)
 * use musnix
 * use steam-run `steam-run bash`

## volume control
Since pipewarp relies on creating a sink, this sink will capture your system volume control.
I recommend you leave this sink volume at 100% as this will make it near-lossless.
Pipewarp allows you to control the volume of the output device using the arrow keys.
On most devices, this is hardware volume control, conserving your precious bit-depth, as opposed to reducing volume before sending it to the output device.

## quitting
Just press `q` in the terminal running pipewarp.
Pipewarp restores the pior audio output and volume when it is quit or Carla is closed.
I'd advise agains killing pipewarp by closing the terminal window while it's running as it won't be able to restore the audio configuration this way.



# Plugins

## room correction EQ
 * [MathAudio RoomEQ](https://mathaudio.com/room-eq.htm) 
 * Haven't tried Sonarworks in wine yet.
Of cource you'll have to create the correction profile using Carla without pipewarp or in a DAW.

## (headphone) EQ
 * [ZLEquializer](https://github.com/ZL-Audio/ZLEqualizer)
You can look up headphone frequnecy response graphs and even generate EQ profiles on [squiglink](https://squig.link/).
Some of their partners offer the neutral Etymotic target for reference, sounds pretty neutral to me on in-ears.

## headphone room simulator
 * [Cans](https://www.airwindows.com/cans/) in [Airwindows Consolidated](https://github.com/baconpaul/airwin2rack/releases/tag/DAWPlugin): awesome on studio C, diffuse 0.07, damping 0.1, crossfeed 0.31, drywet 0.35
 * [Valhalla Room](https://valhalladsp.com/shop/reverb/valhalla-room/) awesome on "Large Chamber" preset with 0.46s, drywet 14%, 3.2ms

## Windows VSTs
To run the Windows VSTs, use [yabridge](https://github.com/robbert-vdh/yabridge).

## performance
To tune your system for performance, use [rtcqs](https://github.com/autostatic/rtcqs) and follow [yabridge's performance tuning section](https://github.com/robbert-vdh/yabridge?tab=readme-ov-file#performance-tuning).

# Troubleshooting
In case you encounter issues, you can monitor the pipewire routing via qpwgraph.
