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
    # Homebrew lives in the nix store, but taps stay mutable: `autoUpdate` and any
    # manual `brew` write need a writable tap directory, which a store symlink
    # (mutableTaps = false) cannot offer.
    mutableTaps = true;
    taps = {
      "automic-vault/isotopes" = automic-vault-tap-src;
    };
  };

  homebrew = {
    enable = true;
    onActivation = {
      # Additive, not exclusive. `zap` would delete every cask and formula this
      # file does not list, preferences included, which is wrong on a machine that
      # also holds apps this repo has no business pinning. Declared entries are
      # still installed and upgraded; an entry REMOVED here has to be uninstalled
      # by hand, because activation no longer prunes. See ADR-0006.
      cleanup = "none";
      autoUpdate = true;
      extraFlags = [ "--force" ];
    };

    taps = [
      "automic-vault/isotopes"
    ];
    brews = [
      "herdr"
      # Node comes from nixpkgs (home.nix) so the crew's CLIs and their runtime
      # are pinned together. An entry removed here is NOT uninstalled by
      # activation (see cleanup above): `brew uninstall node` once by hand.
      # `av harden gh` needs the signed isotope, and it conflicts with upstream gh
      "automic-vault/isotopes/gh-cli"
    ];
    casks = [
      "wezterm"
      # `av`: secrets custody, and the `mate` alias injects through it. Homebrew only
      # loads a third-party cask that is trusted, so trust this cask, not the tap.
      {
        name = "automic-vault/isotopes/automic-vault";
        trusted = true;
      }
    ];
  };
}
