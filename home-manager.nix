# The user environment, shared by every machine.
#
# darwin specialArgs stop at the darwin modules, so identity, the harness package
# and the configuration name have to be handed to the home-manager modules again.
{
  identity,
  piPackage,
  hostName,
  ...
}:
{
  home-manager = {
    extraSpecialArgs = { inherit identity piPackage hostName; };
    useGlobalPkgs = true;
    useUserPackages = true;
    # A file that exists but is not a home-manager link (an old generated
    # ~/.config/git/config, say) is moved aside instead of aborting the whole
    # activation before any link is written.
    backupFileExtension = "hm-bak";
    # A list rather than a bare import, so a host file can add its own home
    # modules with `home-manager.users.<name>.imports`.
    users.${identity.username} = {
      imports = [ ./home.nix ];
    };
  };
}
