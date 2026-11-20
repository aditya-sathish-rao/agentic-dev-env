# 0010. The crew runs in one VM, and nothing from the host is mounted

- Status: Accepted
- Date: 2026-11-21

## Context

Worktrees isolate git state and nothing else. A crewmate ran as the login user, so it could
read every file in `$HOME`, use the hardened `gh` token, and open any connection the host
could. One prompt injection in issue text was enough to turn a task into an exfiltration or a
push.

Two ways to bound that were on the table. Put only the crewmates in a VM and leave the first
mate on the host, or move the whole fleet in. The first is what the fleet's own structure
suggests: the first mate is the trusted thing, the crewmates are the untrusted ones.

The first mate's upstream documentation rules it out. It states that firstmate does not place
an individual worker on a remote machine, and does not fail a remote route over to a local
replacement. The herdr backend picks a local client, and treehouse returns host-absolute paths
that firstmate then reads and writes. Splitting the fleet would mean a shim in front of
herdr, a shared worktree mount at the same absolute path on both sides, and credentials handed
over at spawn: three new seams to hold a boundary that a single VM gives for free. The shared
writable mount would also reintroduce the exact class of bug the boundary exists to remove,
because a guest can plant a git hook or a symlink that the host later acts on.

## Decision

**One Lima VM holds herdr, the first mate, the crewmates and the worktree pool. The host keeps
the credentials, and the guest gets none of them directly.**

- `nix/crew-sandbox/lima.yaml` is the guest's whole definition: `vz` driver, 4 CPU, 6 GiB,
  sparse 30 GiB, Ubuntu 26.04 LTS pinned by image digest, `mounts: []`, `portForwards: []`,
  `forwardAgent: false`. A rebuilt guest runs the bytes the file names.
- The administration account (`crew`) keeps sudo, because Lima provisions and re-provisions
  through it. Agents run as `agent`, created without sudo and in no privileged group, so the
  usual escalation paths are closed rather than discouraged.
- Egress is default-deny in one root-owned nftables table: SSH from the host subnet in, and
  one host port out, reserved for the egress proxy. DNS is not excepted, because a resolver
  left reachable is a covert channel and the proxy will do the resolving.
- Bootstrap marks itself done with `/etc/crew-provisioned`. Lima re-runs provision scripts on
  every boot, so without the marker the second boot would try to `apt-get` with no network,
  fail, and take the instance down.
- The VM is replaced, not patched: `lima.yaml` changes mean destroy and create. Patching a
  guest by hand would make the definition a lie and leave no gate able to see the difference.
- `crew-sandbox` is a flake package, not a `home.packages` entry. It is the operator's handle
  on the VM, and an agent's `PATH` must not contain it.

## Consequences

- The first mate now runs inside the boundary. That is a change of trust: it reads untrusted
  issue text too, so it must hold only broker-issued credentials, not the vault.
- The operator attaches over SSH and runs herdr in the guest, so the host's `mate` alias
  becomes a way in rather than the way to work. Screen-level state now lives in the VM.
- Pushing is the only durable output. A destroyed guest loses every worktree, so crewmates
  have to push to agent branches often; the plan's phase 4 makes that explicit.
- Nothing in the guest can install anything until the egress proxy exists, so the toolchain
  (phase 2) waits on the proxy rather than the other way round.
- The 6 GiB reservation leaves 10 GiB for macOS on a 16 GiB machine that is also a daily
  driver. A second, larger VM (the macOS lane for Xcode) cannot run beside it at full size.
- `crew-sandbox check` asserts properties of the running guest, not of the file. It is
  deliberately not part of `.githooks/check --all`, which must pass on a machine that has
  never started the VM.
