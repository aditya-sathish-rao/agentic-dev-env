# 0008. VS Code owns its settings.json; a rebuild only seeds it

- Status: Accepted
- Date: 2026-11-19

## Context

`settings.json` used to be a `home.file` entry rendered from
`home/.config/vscode/settings.json`, which made it a symlink into the read-only Nix store.
VS Code saves settings with an atomic temp-file rename and has to unlock the target, so every
save failed with `Unable to unlock file ... because atomic write is enabled`.

Three requirements collide here. The three formatter paths need
`config.home.profileDirectory` rendered in, the settings are edited interactively inside VS
Code, and the store is immutable.

Linking the repo file instead does not work either. The placeholder would reach VS Code
literally, and a Dock-launched VS Code does not inherit the shell `PATH`, so the absolute
formatter paths cannot simply be dropped.

## Decision

- The tracked `home/.config/vscode/settings.json` stays the template, with
  `@PROFILE_DIRECTORY@` rendered from the logged-in user.
- `home.activation.vscode-settings` installs that render as a real, user-owned `0644` file at
  `~/Library/Application Support/Code/User/settings.json`, but only when the file is missing
  or is still the old store symlink. An existing regular file is left alone, so VS Code edits
  survive a rebuild.
- Restoring the defaults is explicit: delete the file and run `./rebuild.sh`.
- `~/.config/git/config` keeps the rendered-link behavior, because no application writes it.

## Consequences

- Saving in VS Code works, including the theme and UI settings that were never meant to live
  in git.
- The repo no longer overwrites the live file, so the repo value and the VS Code value can
  drift. The repo is the seed and the documented defaults, not a live mirror.
- A machine that has not run activation has no settings file, and VS Code starts from its own
  defaults until the next rebuild seeds one.
- The formatter paths stay absolute and correct without relying on `PATH`, which a
  Dock-launched VS Code does not get from the shell.
