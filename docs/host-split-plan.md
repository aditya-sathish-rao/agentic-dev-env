# Splitting the repo into two machines

Status: Phases 1 and 3 implemented. Phase 2 is open.

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
crew-targets.nix     shared: the crew.targets option, which places the crew stack
crew-sandbox.nix     shared: the proxy and broker services, gated on crew.targets
crew-user.nix        the `user` target: the dedicated macOS account and its home
crew-home.nix        the `user` target: that account's trimmed home configuration
nix/guest-fleet.nix  the `vm` target: the guest's firstmate clone, herdr and alias
home-manager.nix     shared: which user gets which home configuration
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

## Where the crew runs

The crew is one stack — herdr, the first mate, the crewmates and the worktree pool —
and it is placed as a unit. `crew.targets` names the places it runs on a machine, and
every module that belongs to one place gates on it:

```nix
# crew-targets.nix
options.crew.targets = lib.mkOption {
  type = lib.types.listOf (lib.types.enum [ "host" "user" "vm" ]);
  default = [ "host" ];
};

# primary.nix:  crew.targets = [ "host" ];
# mini.nix:     crew.targets = [ "user" "vm" ];
```

| Target | Where the stack lives      | Boundary                                     | Apple builds  | Model key                                |
| ------ | -------------------------- | -------------------------------------------- | ------------- | ---------------------------------------- |
| `host` | the operator's account     | none                                         | yes           | `av inject`                              |
| `user` | a dedicated `crew` account | macOS user permissions — secrets, not source | yes, unsigned | the host gateway, from a token file      |
| `vm`   | the Lima guest, as `agent` | the guest kernel, nftables and the proxy     | no            | the host gateway, from the guest's token |

The mini runs `user` and `vm` and not `host`: nobody sits at it, so the operator's
account is not where the crew runs. The primary runs `host` only.

Both mini targets reach the same host gateway, and each client has its own token, so
the proxy accepts both. The guest's token is created inside the VM; the `crew`
account's comes from `/etc/crew-sandbox/model-token`, which activation creates as a
`0750` directory owned by `root:crew` and never writes the secret itself.

`checks.aarch64-darwin.crew-targets` pins the placement and proves the guest's home
configuration still evaluates, so a host file that silently loses a target fails in
CI rather than on the machine it names.

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

**Phase 3 — headless work on `mini.nix` (done).** The crew-sandbox proxy and broker
are launchd **user agents**: they start with a GUI login, and the vault answers an
unattended read with "human approval required". On a headless mini with FileVault on,
nobody logs in after a reboot, so neither service starts.

The decision is **automatic sign-in with FileVault off**. The mini holds no personal
data, so the trade is acceptable, and it is the only option that needs no change to
crew-sandbox's secret chain. The alternative — a root-only encrypted secret with a
non-vault backend — is not built.

`mini.nix` imports `kunchenguid/headless` (pinned to a commit in `flake.nix`) and
sets `headless.autoLogin = true`, `headless.keyOnlySsh = true` with the operator's
key, and `headless.tailscale.enable = false` because `tailscale.nix` already declares
the daemon. The module also turns off sleep, starts the machine after a power cut,
and disables the `/Applications/Nix Apps` activation step that cannot run over SSH.

`tailscale.nix` sets `services.tailscale.enable` with `mkDefault`, because the
headless module also sets it and a plain `true` would conflict.

### Manual steps for the mini

These cannot be done by a rebuild, because each needs a human at the machine or an
admin password:

1. **Turn FileVault off** (`sudo fdesetup disable`). Automatic sign-in cannot work
   with it on, and the module warns at activation when it is.
2. **Store the sign-in password once** with the headless skill's admin step, which
   writes `/etc/kcpassword`. The module warns at activation when it is missing.
3. **Install the operator's public key** in `~/.ssh/authorized_keys` for the admin
   account, or rely on `headless.sshKeys` (already set) and confirm sshd restarted.
4. **Accept the Xcode licence once** (`sudo xcodebuild -license accept`) and install
   the command-line tools, if the `user` target is to build for Apple platforms.
   Builds are unsigned; signing stays on the laptop.
5. **Create the model token** the `crew` account presents:
   `sudo sh -c 'umask 077; openssl rand -hex 32 > /etc/crew-sandbox/model-token'`.
   Activation creates the directory and warns when the file is missing.
6. **Clone firstmate as `crew`** (`sudo -u crew ./rebuild.sh --mini`), so the
   account's clone exists before its home config links into it.
7. **Check the boundary**: `ls -ld ~` on the operator's home. It is `0750`
   owner:staff, so `crew` — which lands in `staff` — can traverse it and read
   `~/projects`. The boundary is secrets, not source. A per-user `pf` rule to force
   the account's egress through the proxy is worth trying but is untested.
8. **A GUI session is needed** for the `crew` account to run UI and simulator tests.
   Over SSH there is none.

## Verification

```console
# both configurations still evaluate
$ nix eval --impure --raw .#darwinConfigurations.primary.config.system.build.toplevel.drvPath
$ nix eval --impure --raw .#darwinConfigurations.mini.config.system.build.toplevel.drvPath

# the launchd agents still get their arguments and now get a PATH
$ nix eval --impure --json .#darwinConfigurations.primary.config.launchd.user.agents.crew-sandbox-proxy.serviceConfig

# each host runs the placement the plan records
$ nix eval --impure --json .#darwinConfigurations.primary.config.crew.targets
$ nix eval --impure --json .#darwinConfigurations.mini.config.crew.targets

# the guest's toolchain gate can pass: pi, git, gh and herdr all resolve in the store
$ nix eval --impure --json .#homeConfigurations.\"agent@aarch64-linux\".config.home.packages --apply 'ps: map (p: p.name) ps'

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
