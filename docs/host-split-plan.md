# Splitting the repo into two machines

Status: Phase 1 implemented. Phases 2 and 3 are open.

## Why

The flake describes exactly one machine:

```nix
darwinConfigurations.${identity.host} = nix-darwin.lib.darwinSystem { ... };
```

`identity.host` comes from `AGENTIC_DEV_ENV_HOST`, or the login name when that is
unset. That works while there is one Mac. It cannot describe a second one, and it
gives the two no place to differ.

The target is two named configurations — `primary` (this Mac) and `mini` (the
headless Mac mini) — each with its own file.

## Target shape

```
primary.nix          this machine: imports the shared base, holds what is only true here
mini.nix             the mini: imports the shared base, holds what is only true there
home-manager.nix     shared: which user gets which home configuration
crew-sandbox.nix     shared: the proxy and broker services, and their PATH
configuration.nix    shared: system base (macOS defaults, Homebrew, fonts, Tailscale)
home.nix             shared: user base (packages, links, shell, launchd)
home/.agents/skills-primary   skills only the primary Mac gets
home/.agents/skills-mini      skills only the mini gets
identity.nix         username and home directory, from the environment
```

`flake.nix` builds both from one helper:

```nix
mkDarwin = hostName: hostModule: nix-darwin.lib.darwinSystem {
  specialArgs = { inherit identity piPackage crew-sandbox automic-vault-tap hostName; };
  modules = [
    nix-homebrew.darwinModules.nix-homebrew
    home-manager.darwinModules.home-manager
    hostModule
  ];
};

darwinConfigurations = {
  primary = mkDarwin "primary" ./primary.nix;
  mini = mkDarwin "mini" ./mini.nix;
};
```

The home-manager wiring moved out of `flake.nix` into `home-manager.nix` so a host
file can override it (a different username on the mini, say) without editing the
flake.

## What each file owns

| File           | Owns                                                                                                          |
| -------------- | ------------------------------------------------------------------------------------------------------------- |
| `primary.nix`  | anything only this Mac needs: GUI casks, Swift tooling, editor configs, the `mate` alias, the firstmate clone |
| `mini.nix`     | headless-only settings: never sleep, key-only sshd, Screen Sharing recovery, Tailscale as a system daemon     |
| shared modules | everything both machines need today                                                                           |

The rule: if both machines need it, it goes in the shared base. If only one does,
it goes in that host file. A host file that only imports is correct while the
machines are identical — it is the seam, not a stub.

## Known divergences to move (Phase 2)

These are the items that are true of `primary` and not of a headless mini. They
stay in the shared base for now so Phase 1 changes no behaviour.

| Item                                            | Where it lives now  | Belongs in    |
| ----------------------------------------------- | ------------------- | ------------- |
| `swiftlint`, `swift-format`                     | `home.nix` packages | `primary.nix` |
| `nerd-fonts.hack`, `fonts.fontconfig`           | `home.nix`          | `primary.nix` |
| wezterm, nvim config links                      | `home.nix` symlinks | `primary.nix` |
| `mate` alias, `pi` wrapper link                 | `home.nix` programs | `primary.nix` |
| firstmate dispatch links                        | `home.nix` symlinks | `primary.nix` |
| no-mistakes launchd daemon                      | `home.nix`          | `primary.nix` |
| Homebrew casks (wezterm, Automic Vault)         | `configuration.nix` | `primary.nix` |
| macOS desktop defaults (dock, finder, trackpad) | `configuration.nix` | `primary.nix` |
| never sleep, restart after power failure        | not set             | `mini.nix`    |
| key-only sshd, Screen Sharing recovery          | not set             | `mini.nix`    |
| Tailscale as a system daemon                    | `tailscale.nix`     | `mini.nix`    |

### Done: per-host skills

A skill that belongs to one machine only has a home now, without a host file:

- `home/.agents/skills` is linked on every machine, as before.
- `home/.agents/skills-primary` is linked on `primary` only, and
  `home/.agents/skills-mini` on `mini` only.
- `flake.nix` passes the configuration name to the modules as `hostName`, so
  `home.nix` picks the directory from the configuration, not from the environment.
  CI therefore evaluates both directories on every run.

### Done: VS Code

VS Code is the first item moved. It is on `primary` only:

- the `visual-studio-code` cask moved from `configuration.nix` to `primary.nix`
- the settings render and activation moved from `home.nix` to `home-vscode.nix`,
  imported by `primary.nix` alone

`home-manager.nix` now takes `users.<name>.imports` as a list rather than a bare
import, so a host file can add its own home modules. The tracked template
`home/.config/vscode/settings.json` stays in the repo; it is data, not a machine
setting.

## Phases

**Phase 1 — structural (done).** Both host files import the same base. No
behaviour change. Proven by evaluating both configurations. Also fixes the
`av` PATH bug in `crew-sandbox.nix`, because both machines need it.

**Phase 2 — move primary-only items.** Move the rows above out of the shared base
into `primary.nix`. Each move is one commit that still evaluates both hosts.

**Phase 3 — headless work on `mini.nix`.** The unresolved part. The crew-sandbox
proxy and broker are launchd **user agents**: they start with a GUI login, and the
vault answers an unattended read with "human approval required". On a headless mini
with FileVault on, nobody logs in after a reboot, so neither service starts. The
options are in `crew-sandbox/docs/run-crew-on-headless-mac.md`: auto-login with
FileVault off, or a non-vault secret path such as a root-only encrypted file. That
is a design decision, not a bug fix.

## Verification

```console
# both configurations still evaluate
$ nix eval --impure --raw .#darwinConfigurations.primary.config.system.build.toplevel.drvPath
$ nix eval --impure --raw .#darwinConfigurations.mini.config.system.build.toplevel.drvPath

# the launchd agents still get their arguments and now get a PATH
$ nix eval --impure --json .#darwinConfigurations.primary.config.launchd.user.agents.crew-sandbox-proxy.serviceConfig

# the repo's own gate, which now evaluates every host
$ ./.githooks/check --all
```

## Open questions

- **Identity is shared.** `identity.nix` reads one username and home directory from
  the environment. If the mini's account differs, identity has to become per-host.
- **`builtins.currentSystem` sets `nixpkgs.hostPlatform`.** Fine while both machines
  are Apple Silicon. An Intel host would need an explicit platform per file.
- **`AGENTIC_DEV_ENV_HOST` changed meaning.** It now names a configuration
  (`primary` or `mini`), not the macOS hostname. `rebuild.sh` takes the host as a
  `--primary`/`--mini` flag and defaults to `primary` when neither is given, still
  honours the variable for automation, and rejects a flag that disagrees with it.
- **CI evaluates both hosts.** That is deliberate: a host file that stops
  evaluating should fail in CI, not on the machine it describes.
