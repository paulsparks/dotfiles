{
  pkgs,
  inputs,
  ...
}:

{
  imports = [ inputs.home-manager.nixosModules.default ];

  home-manager.users.psparks =
    { pkgs, config, ... }:
    let
      remoteName = "psparks-google-drive";
      remote = "${remoteName}:Encrypted";
      localDir = "${config.home.homeDirectory}/Encrypted";
      rcloneConf = "${config.xdg.configHome}/rclone/rclone.conf";

      # Shared guard: exit 0 (no-op) unless rclone is actually set up.
      guard = ''
        [ -f "${rcloneConf}" ] || exit 0
        grep -q '^\[${remoteName}\]' "${rcloneConf}" || exit 0
        [ -d "${localDir}" ] || exit 0
      '';

      syncScript = pkgs.writeShellScript "rclone-bisync-run" ''
        ${guard}
        exec ${pkgs.util-linux}/bin/flock -n "$XDG_RUNTIME_DIR/rclone-bisync.lock" \
          ${pkgs.rclone}/bin/rclone bisync "${remote}" "${localDir}" \
          --resilient --recover --drive-skip-gdocs --max-delete 25 \
          --log-file "$HOME/rclone-bisync.log"
      '';

      watchScript = pkgs.writeShellScript "rclone-bisync-watch" ''
        ${guard}
        while ${pkgs.inotify-tools}/bin/inotifywait -r \
            -e modify,create,delete,move "${localDir}"; do
          sleep 5
          ${pkgs.systemd}/bin/systemctl --user start rclone-bisync.service
        done
      '';
    in
    {
      nixpkgs.config.allowUnfree = true;

      home.packages = with pkgs; [
        gnomeExtensions.dash-to-dock
        gnome-tweaks
        trash-cli
        vim
        ghostty
        starship
        vscode
        nixfmt
        discord
        spotify
        devenv
        nixd
        dbeaver-bin
        nodejs
        pnpm
        bun
        bruno
        obsidian
        imagemagick
        dig
        obs-studio
        godot
        blender
        rustup
        gcc
        inkscape
        nerd-fonts.jetbrains-mono
        cryptomator
        rclone
      ];

      fonts.fontconfig.enable = true;

      programs.bash = {
        enable = true;
        initExtra = ''
          eval "$(starship init bash)"
          eval "$(devenv hook bash)"
        '';
      };

      programs.git = {
        enable = true;
        settings = {
          user.name = "psparks";
          user.email = "psparks1225@gmail.com";
        };
      };

      dconf.settings = {
        "org/gnome/desktop/sound" = {
          event-sounds = false;
        };
      };

      xsession = {
        enable = true;
        windowManager.command = "gnome-shell";
      };

      # Needed so home-manager starts/reloads user units on switch.
      systemd.user.startServices = "sd-switch";

      # One bisync pass.
      systemd.user.services.rclone-bisync = {
        Unit = {
          Description = "rclone bisync Google Drive";
          ConditionPathExists = rcloneConf;
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${syncScript}";
        };
      };

      # Poll every 5 minutes to pick up remote changes.
      systemd.user.timers.rclone-bisync = {
        Unit.Description = "Periodic rclone bisync";
        Timer = {
          OnBootSec = "1min";
          OnUnitActiveSec = "5min";
        };
        Install.WantedBy = [ "timers.target" ];
      };

      # Trigger a sync shortly after local edits.
      systemd.user.services.rclone-bisync-watch = {
        Unit = {
          Description = "Trigger bisync on local changes";
          ConditionPathExists = rcloneConf;
          ConditionPathIsDirectory = localDir;
        };
        Service = {
          ExecStart = "${watchScript}";
          Restart = "on-failure";
          RestartSec = 30;
        };
        Install.WantedBy = [ "default.target" ];
      };

      home.stateVersion = "26.05";
    };

  home-manager.backupCommand = "${pkgs.trash-cli}/bin/trash-put";
}
