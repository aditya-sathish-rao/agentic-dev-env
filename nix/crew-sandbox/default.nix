# The host-side seam for the crew sandbox: the pinned VM definition and the one CLI
# that drives it. It is the operator's tool. No agent runs it, and nothing inside
# the guest can reach it.
{ pkgs, ... }:
let
  limaConfig = pkgs.writeText "crew-lima.yaml" (builtins.readFile ./lima.yaml);

  # Paths are injected at the top of each script by interpolation, so the store
  # references stay real and a garbage collection cannot strand them.
  check = pkgs.writeShellApplication {
    name = "crew-sandbox-check";
    runtimeInputs = [
      pkgs.lima
      pkgs.coreutils
    ];
    text = ''
      agent_checks=${./checks/agent.sh}
      root_checks=${./checks/root.sh}
      ${builtins.readFile ./check.sh}
    '';
  };
in
pkgs.writeShellApplication {
  name = "crew-sandbox";
  runtimeInputs = [
    pkgs.lima
    pkgs.coreutils
  ];
  text = ''
    config=${limaConfig}
    check=${check}/bin/crew-sandbox-check
    ${builtins.readFile ./crew-sandbox.sh}
  '';
}
