# One data surface for every pinned crew artifact. Bump through update.sh, not
# by hand: it checks the publish age, cross-checks upstream checksums, audits npm
# signatures, regenerates the lock and prints the lock diff for review.
{
  node = "24.22.1";

  npm = {
    gh-axi = {
      version = "0.1.51";
      tarballHash = "sha256-/umDcRd02PpQ7OyQpRqoAyU4ZIxod/yxxE172XFtVMI=";
      npmDepsHash = "sha256-QIQ8CYxgGKFyZUU53cOqKLNNxzdFVz8t7BSpLThsJ9A=";
      bin = "gh-axi";
    };
    chrome-devtools-axi = {
      version = "0.1.46";
      tarballHash = "sha256-YhP9z87gIt3J13LGJNPAMShzELeFXdg9K9rfoOm5DfE=";
      npmDepsHash = "sha256-25JycSQC6dH0Jvz/8xzAU8PANv6ynP3GWR8duN282fo=";
      bin = "chrome-devtools-axi";
    };
    tasks-axi = {
      version = "0.2.6";
      tarballHash = "sha256-kzQv5sga9RZpvYonP56ImjY0KISHc8yQe64fcak5Cdk=";
      npmDepsHash = "sha256-ONBx4ngwUyyQjoizSssK7fPTw9pCujTMP5dpmIhWH+w=";
      bin = "tasks-axi";
    };
    quota-axi = {
      version = "0.1.69";
      tarballHash = "sha256-1pSKI20ggK811yHtFGBViHpZDj3yP/a7lmVO6zyiaPU=";
      npmDepsHash = "sha256-WzRYz5dtwHseMRrs1qLQlFWujKHt3QIqktn7XcYGZZY=";
      bin = "quota-axi";
    };
    lavish-axi = {
      version = "0.1.97";
      tarballHash = "sha256-hOTZHBc+kblmxQbadwpknVM3Ztk5hXOdJrhZIUMSdmI=";
      npmDepsHash = "sha256-iAzCIxO2XT0HaL+5yZENDWLl/cxOgLYQ63Vfazd+QNI=";
      bin = "lavish-axi";
    };
    chrome-devtools-mcp = {
      version = "1.13.0";
      tarballHash = "sha256-kVjEtKh5LLUirkb3buqpSRzgRhajrpcimhYnfgKkrqQ=";
      # No runtime dependencies; the lock exists only to record the published
      # tarball. buildNpmPackage still needs a hash for the empty cache.
      npmDepsHash = "sha256-UO0pS71RvkbHl8YKfVij3IDh1G3xTjVQ6uoH6/aFfuw=";
      bin = "chrome-devtools-mcp";
    };
  };

  # SHA-256 from each release's checksums.txt, not from the installer.
  release = {
    treehouse = {
      version = "3.1.8";
      hash = {
        "aarch64-darwin" = "sha256-AHxVwm4L2LZysakXRl8Gw/idk6Zs0XE2T/tldD0mhgE=";
        "x86_64-darwin" = "sha256-a+f3HMjGofv0AxGvjuPEVFnHKvurLJPcL4Chg0J7y+s=";
        "aarch64-linux" = "sha256-PRwCyKsTBJcJrOZr5R2Zty/nttC3PQ0O/ZDyJuGqh9E=";
        "x86_64-linux" = "sha256-vWIn2Qm6gEYmOuXU4HLMvPQwEMrJ1yibEmISZRDt/u0=";
      };
    };
    no-mistakes = {
      version = "1.106.1";
      hash = {
        "aarch64-darwin" = "sha256-MQWuP/2fX23CdnQwLc0Saom6nCPUPsuL5eJmrFLxRyw=";
        "x86_64-darwin" = "sha256-od+aHkVuJlyYndsXloMX89Ib+AsjuYKMvUJnd/J5v7E=";
        "aarch64-linux" = "sha256-hSnzfTsRohOr6RYoUehCCOnBLp2Ov4MOA38F4AVYplY=";
        "x86_64-linux" = "sha256-+/ExNWonhiOlCba1Dss5xTdbGoLn3PxI5C0Q52FBbR4=";
      };
    };
  };

  # A bare binary per platform, from its own org. Not in nixpkgs, so it is pinned
  # here rather than taken from Homebrew: the guest has no Homebrew, and the crew
  # account should not depend on one either.
  plain = {
    herdr = {
      version = "0.9.5";
      owner = "kunchenguid";
      hash = {
        "aarch64-darwin" = "sha256-+3fCIyoFqANUITgsiUOS9BdOTjihjkivPdApAVfDp+I=";
        "x86_64-darwin" = "sha256-X7CpCOx/Z0Xj4kVziwa/rVbEY5HDkas8CVX76tAfE2k=";
        "aarch64-linux" = "sha256-F9dTby2lCFlSNoDvJ53/ysjkojX05G/o2mwuxEFBiXw=";
        "x86_64-linux" = "sha256-FNnovItKngEY13wyJm921GHwm0A0LrI3UpYL2J9Zkp0=";
      };
    };
  };
}
