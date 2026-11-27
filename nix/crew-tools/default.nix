# The package set consumed by home.nix and exposed as .#crew-tools for CI.
{ pkgs, ... }:
let
  pins = import ./pins.nix;
  builders = import ./builders.nix {
    inherit (pkgs)
      lib
      stdenv
      fetchurl
      buildNpmPackage
      nodejs_24
      makeWrapper
      ;
  };

  npmPackages = builtins.mapAttrs (name: pin: builders.npmCli ({ inherit name; } // pin)) pins.npm;

  releasePackages = builtins.mapAttrs (
    name: pin: builders.releaseBinary ({ inherit name; } // pin)
  ) pins.release;

  plainPackages = builtins.mapAttrs (
    name: pin: builders.plainBinary ({ inherit name; } // pin)
  ) pins.plain;
in
npmPackages // releasePackages // plainPackages
