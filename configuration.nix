{
  pkgs,
  identity,
  automic-vault-tap,
  ...
}:

let
  # nix-homebrew.taps takes derivations; the flake input is a plain source tree.
  automic-vault-tap-src = pkgs.runCommandLocal "homebrew-isotopes" { } ''
    mkdir -p $out
    cp -R ${automic-vault-tap}/. $out
  '';
in
{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs = {
    config.allowUnfree = true;
    # The flake is evaluated impurely (--impure), so this matches the machine it
    # runs on: aarch64-darwin on Apple Silicon, x86_64-darwin on Intel.
    hostPlatform = builtins.currentSystem;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.hack
  ];

  users.users.${identity.username} = {
    home = identity.homeDirectory;
  };

  # `av scan` flags sudo without Touch ID. nix-darwin writes /etc/pam.d/sudo_local.
  security.pam.services.sudo_local.touchIdAuth = true;

  system = {
    primaryUser = identity.username;
    stateVersion = 6;
    defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        KeyRepeat = 2; # fast key repeat
        InitialKeyRepeat = 15; # short delay before repeat
        _HIHideMenuBar = true; # auto-hide the menu bar
        AppleShowAllExtensions = true;
      };
      dock.autohide = true;
      finder.FXPreferredViewStyle = "Nlsv"; # list view by default
      finder.CreateDesktop = false; # clean desktop
      trackpad.Clicking = true;
    };
  };

  nix-homebrew = {
    enable = true;
    user = identity.username;
    autoMigrate = true;
    # Homebrew lives in the nix store, but taps stay mutable: `cleanup = "zap"`
    # un-taps whatever is missing from homebrew.taps, which a store symlink
    # (mutableTaps = false) cannot do.
    mutableTaps = true;
    taps = {
      "automic-vault/isotopes" = automic-vault-tap-src;
    };
  };

  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "zap"; # remove anything not listed here
      autoUpdate = true;
      extraFlags = [ "--force" ];
    };

    taps = [
      "automic-vault/isotopes"
    ];
    brews = [
      "herdr"
      "node" # replaces the stale standalone Node 22 in /usr/local that `av scan` flags
      # `av harden gh` needs the signed isotope, and it conflicts with upstream gh
      "automic-vault/isotopes/gh-cli"
    ];
    casks = [
      "wezterm"
      "visual-studio-code"
      "claude-code" # the `cc` alias needs it, and cleanup = "zap" would drop it otherwise
      # `av`: secrets custody, and the `cc` alias injects through it. Homebrew only
      # loads a third-party cask that is trusted, so trust this cask, not the tap.
      {
        name = "automic-vault/isotopes/automic-vault";
        trusted = true;
      }
    ];
  };
}
