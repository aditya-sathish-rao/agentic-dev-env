# VS Code's settings, for the machine that runs VS Code.
#
# VS Code saves settings with an atomic temp-file rename and refuses to unlock a
# symlink into the read-only store, so settings.json can be neither linked nor
# store-rendered. It is seeded once as a real file and then owned by VS Code;
# delete it and run ./rebuild.sh to restore these defaults. The formatter paths
# depend on the logged-in user, hence the render. See ADR-0008.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  vscodeSettings = pkgs.writeText "vscode-settings.json" (
    builtins.replaceStrings [ "@PROFILE_DIRECTORY@" ] [ config.home.profileDirectory ] (
      builtins.readFile ./home/.config/vscode/settings.json
    )
  );
in
{
  # VS Code owns its settings once seeded, so a rebuild must not overwrite the
  # user's own edits. Only a missing file, or the old read-only store link, is
  # replaced.
  home.activation.vscode-settings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    settings="$HOME/Library/Application Support/Code/User/settings.json"
    if [[ ! -e "$settings" || -L "$settings" ]]; then
      run mkdir -p "$(dirname "$settings")"
      run rm -f "$settings"
      run install -m 0644 ${vscodeSettings} "$settings"
    fi
  '';
}
