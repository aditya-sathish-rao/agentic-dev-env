# The host-side seam for the crew sandbox: the pinned VM definition, the egress
# proxy, and the one CLI that drives both. It is the operator's tool. No agent runs
# it, and nothing inside the guest can reach it.
{ pkgs, piPackage, ... }:
let
  limaConfig = pkgs.writeText "crew-lima.yaml" (builtins.readFile ./lima.yaml);
  proxyScript = ./proxy.mjs;
  egressAllow = ./egress-allow;
  brokerScript = ./broker/broker.mjs;

  # The App ID is public config. Which repositories may be asked for is data, in
  # repos-allow, so adding a project never means touching this file. The private
  # key stays in the vault.
  brokerAppId = "5853565";
  reposAllow = ./repos-allow;

  # Paths are injected at the top of each script by interpolation, so the store
  # references stay real and a garbage collection cannot strand them.
  check = pkgs.writeShellApplication {
    name = "crew-sandbox-check";
    runtimeInputs = [
      pkgs.lima
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.nodejs_24
    ];
    text = ''
      agent_checks=${./checks/agent.sh}
      root_checks=${./checks/root.sh}
      proxy_check=${./checks/proxy.sh}
      model_check=${./checks/model.sh}
      toolchain_check=${./checks/toolchain.sh}
      broker_check=${./checks/broker.sh}
      expected_pi=${piPackage.version}
      proxy_script=${proxyScript}
      egress_allow=${egressAllow}
      broker_script=${brokerScript}
      broker_app_id=${brokerAppId}
      broker_repos_file=${reposAllow}
      ${builtins.readFile ./check.sh}
    '';
  };
in
pkgs.writeShellApplication {
  name = "crew-sandbox";
  runtimeInputs = [
    pkgs.lima
    pkgs.coreutils
    pkgs.curl
    pkgs.nodejs_24
  ];
  text = ''
    config=${limaConfig}
    check=${check}/bin/crew-sandbox-check
    proxy_script=${proxyScript}
    egress_allow=${egressAllow}
    broker_script=${brokerScript}
    broker_app_id=${brokerAppId}
    broker_repos_file=${reposAllow}
    ${builtins.readFile ./crew-sandbox.sh}
  '';
}
