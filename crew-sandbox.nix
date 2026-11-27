# The crew-sandbox host services, shared by every machine.
#
# The proxy holds the model key and the broker holds the GitHub App key; both read
# them from the vault at start-up. They are launchd user agents, so they start with
# a GUI login rather than at boot. See docs/host-split-plan.md for what that means
# on a headless host.
{
  identity,
  crew-sandbox,
  personal,
  ...
}:
{
  system.primaryUser = identity.username;

  services.crew-sandbox = {
    enable = true;
    package = crew-sandbox.packages.aarch64-darwin.default;
    # The upstream the host proxy forwards model traffic to, and the vault secret
    # holding that upstream's API key. Both come from personal.nix, so no provider
    # is named in a tracked file. Save the key first (`av save <keySecret>`): the
    # proxy agent reads it from the vault at start-up.
    proxy.upstream = personal.model.upstream;
    proxy.keySecret = personal.model.keySecret;
    broker.appID = personal.githubApp.id;
  };

  # The module's wrapper prepends its own packages to PATH and inherits the rest.
  # launchd hands an agent /usr/bin:/bin:/usr/sbin:/sbin, which does not contain
  # /usr/local/bin, so `av` - the vault CLI both services shell out to - is not
  # found and the model gateway and broker both fail to start.
  launchd.user.agents = {
    crew-sandbox-proxy.serviceConfig.EnvironmentVariables.PATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    crew-sandbox-broker.serviceConfig.EnvironmentVariables.PATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  };
}
