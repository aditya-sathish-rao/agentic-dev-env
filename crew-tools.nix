# The crew-tool seam: runtime CLIs installed for the user, beside tools.nix
# (formatters and linters shared with CI). Kept separate so nix develop stays
# small and darwin-independent. The package set is returned rather than a bare
# list, because home.nix also names one binary to run the no-mistakes daemon.
{ pkgs, ... }:
import ./nix/crew-tools/default.nix { inherit pkgs; }
