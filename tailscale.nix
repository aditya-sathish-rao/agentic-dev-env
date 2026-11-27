# Tailscale as a system daemon, so the network is up before anyone logs in.
#
# `mkDefault` because the headless module also sets this option: it defaults to
# false, and a machine that already runs the Tailscale app must not get a second
# copy. A host file that wants the module's behaviour can override this without a
# conflict, and the default here is still "on".
{ lib, ... }:
{
  services.tailscale.enable = lib.mkDefault true;
}
