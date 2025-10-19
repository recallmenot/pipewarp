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

## volume control
Since pipewarp relies on creating a sink, this sink will capture your system volume control.
I recommend you leave this sink volume at 100% as this will make it losseless.
Pipewarp allows you to control the volume of the output device using the arrow keys.

## quitting
Pipewarp restores the pior audio output and volume when it is quit or Carla is closed.
I'd advise agains killing pipewarp by closing the terminal window while it's running as it won't be able to restore the audio configuration this way.

## installation
 * install Carla from your package manager
 * install xdotool if you're on X11 (a quick `echo $XDG_SESSION_TYPE` should tell you)
 * plugins can be installed to the usual locations where Carla can find them (e.g. `~/.vst3/`)
 * `git clone https://github.com/recallmenot/pipewarp.git`
 * launch Carla
 * settings -> configure -> engine: audio driver JACK, process mode continuous rack
 * restart Carla
 * load your plugins
 * save the profile as `systemdsp.carxp`, in this repo's root dir
 * close Carla
 * optionally make pipewarp executable (it should already be): `chmod +x pipewarp.sh`
 * run: `./pipewarp.sh`

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
 * The NixOS filesystem doesn't follow the Filesystem Hierarchy Standard and Carla won't even be able to locate VSTs in such an environment.
   LDD only reveals Carla's immediate dependencies and the package doesn't care to provide any beyond those.
   Solution: To start both carla and pipewarp from within an environment that provides the right libraries, start them from within the included flake with `nix run`.
   You could also use musnix or `steam-run bash` for this.
 * pipewarp needs `pactl` from `pulseaudio`, so add it to `environment.systemPackages = with pkgs; []` if you don't use the included flake. Your system will still use pipewire since that is what was enabled.

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
 * [Cans](https://www.airwindows.com/cans/) in [Airwindows Consolidated](https://github.com/baconpaul/airwin2rack/releases/tag/DAWPlugin): awesome on studio E, diffuse 0.07, damping 0.1, crossfeed 0.3, drywet 0.35
 * [Valhalla Room](https://valhalladsp.com/shop/reverb/valhalla-room/) awesome on "Large Chamber" preset with 0.46s, drywet 14%, 3.2ms

## Windows VSTs
To run the Windows VSTs, use [yabridge](https://github.com/robbert-vdh/yabridge).

## performance
To tune your system for performance, use [rtcqs](https://github.com/autostatic/rtcqs) and follow [yabridge's performance tuning section](https://github.com/robbert-vdh/yabridge?tab=readme-ov-file#performance-tuning).
