# The crew-sandbox host services, shared by every machine that runs a crew.
#
# The proxy holds the model key and the broker holds the GitHub App key; both read
# them from the vault at start-up. They are launchd user agents, so they start with
# a GUI login rather than at boot. See docs/host-split-plan.md for what that means
# on a headless host.
#
# The services are gated on `crew.targets` because they are only meaningful where a
# crew runs. A machine with no crew target at all - a plain workstation - should not
# hold a model key in a launchd agent.
{
  config,
  lib,
  crew-sandbox,
  personal,
  ...
}:
let
  cfg = config.services.crew-sandbox;

  # The `user` target's token. The proxy reads the guest's token from the guest, but
  # a dedicated macOS account has no guest to read from, so its token comes from a
  # file the operator owns. The file lives in a directory the `crew` group can read
  # and nobody else can: the token is a bearer credential for the model gateway.
  userTokenDirectory = "/etc/crew-sandbox";
  userTokenFile = "${userTokenDirectory}/model-token";

  runsUser = builtins.elem "user" config.crew.targets;
in
{
  # The services are needed by both the `user` and the `vm` target: the guest reaches
  # the gateway through the host proxy, and the dedicated account reaches it on
  # loopback. `host` needs them too, because that is where the crew runs today.
  services.crew-sandbox = lib.mkIf (config.crew.targets != [ ]) {
    enable = true;
    package = crew-sandbox.packages.aarch64-darwin.default;
    # The upstream the host proxy forwards model traffic to, and the vault secret
    # holding that upstream's API key. Both come from personal.nix, so no provider
    # is named in a tracked file. Save the key first (`av save <keySecret>`): the
    # proxy agent reads it from the vault at start-up.
    proxy = {
      upstream = personal.model.upstream;
      keySecret = personal.model.keySecret;
      # With a `user` target the gateway serves two clients - the guest and the
      # dedicated account - and each has its own token. The proxy accepts both.
      extraArgs = lib.optionals runsUser [
        "--model-token-file"
        userTokenFile
      ];
    };
    broker.appID = personal.githubApp.id;
  };

  # The module's wrapper prepends its own packages to PATH and inherits the rest.
  # launchd hands an agent /usr/bin:/bin:/usr/sbin:/sbin, which does not contain
  # /usr/local/bin, so `av` - the vault CLI both services shell out to - is not
  # found and the model gateway and broker both fail to start.
  launchd.user.agents = lib.mkIf cfg.enable {
    crew-sandbox-proxy.serviceConfig.EnvironmentVariables.PATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    crew-sandbox-broker.serviceConfig.EnvironmentVariables.PATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  };

  # The token file is created by the operator, not by activation: a secret written
  # by a world-readable Nix store path is not a secret. Activation creates only the
  # directory, with the group and mode that let the `crew` account read the token
  # and nobody else.
  #
  # This hangs off `postActivation` rather than being its own activation script.
  # nix-darwin runs a fixed list of scripts and silently ignores any other name, so
  # a script called `crewModelTokenDirectory` would never run at all. postActivation
  # is the last step and runs after `users` and `groups`, so the `crew` group exists
  # by the time the directory is chowned to it.
  #
  # `vm` alone needs no file: the guest's token is created inside the VM.
  system.activationScripts.postActivation.text = lib.mkIf runsUser ''
    echo "crew: preparing ${userTokenDirectory}..." >&2
    install -d -m 0750 -o root -g crew ${userTokenDirectory}
    if [ ! -e ${userTokenFile} ]; then
      echo "crew: ${userTokenFile} is missing; the model gateway will refuse the crew account" >&2
      echo "crew: create it with: sudo sh -c 'umask 077; openssl rand -hex 32 > ${userTokenFile}'" >&2
    fi
  '';
}
