{
  description = "FHS environment for Carla with plugin dependencies";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;  # If any plugins require it
    };

    fhsEnv = pkgs.buildFHSEnv {
      name = "pipewarp-fhs";

      targetPkgs = pkgs: with pkgs; [
        carla

        # Core deps from ldd output
        alsa-lib
        fontconfig
        freetype
        gcc.cc.lib  # Provides libatomic.so.1, libstdc++.so.6, libgcc_s.so.1
        zlib
        bzip2
        libpng  # main libpng provides libpng16.so.16 (1.6.x with APNG in recent unstable)
        brotli
        expat

        # Audio/JACK extras for PipeWire compatibility
        pipewire
        libjack2

        # GUI basics (if needed for plugin UIs)
        gtk3
        glib
        cairo
        pango

        # Others that might pop up
        libpulseaudio

        # provide pactl
	pulseaudio

        jq
        bc
        xdotool
      ];

      runScript = "bash";

      profile = ''
        export PS1="pipewarp-fhs:\w \$ "
        export CARLA_VST3_PATH="$HOME/.vst3:${pkgs.carla}/lib/vst3"
        # Add other CARLA_*_PATH if needed for LV2/LADSPA/etc.
        echo "FHS env ready. Run 'carla' to launch. Use 'exit' to quit."
      '';
    };
  in {
    apps.${system}.default = {
      type = "app";
      program = "${fhsEnv}/bin/pipewarp-fhs";
    };

    devShells.${system}.default = fhsEnv;
  };
}
