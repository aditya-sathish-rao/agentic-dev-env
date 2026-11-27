# Two builders cover all eight artifacts. The npm tarballs ship dist/, so no
# build script runs; the release archives contain one static Go binary each.
{
  lib,
  stdenv,
  fetchurl,
  buildNpmPackage,
  nodejs_24,
  makeWrapper,
  ...
}:
let
  systems = [
    "aarch64-darwin"
    "x86_64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  npmCli =
    {
      name,
      version,
      tarballHash,
      npmDepsHash,
      bin,
      ...
    }:
    buildNpmPackage {
      pname = name;
      inherit version;
      src = fetchurl {
        url = "https://registry.npmjs.org/${name}/-/${name}-${version}.tgz";
        hash = tarballHash;
      };
      inherit npmDepsHash;
      npmBuildScript = "";
      dontNpmBuild = true;
      postPatch = ''
        cp ${./locks/${name}/package-lock.json} package-lock.json
      '';
      nativeBuildInputs = [ makeWrapper ];
      installPhase = ''
        runHook preInstall

        mkdir -p $out/lib/node_modules/${name}
        cp -R . $out/lib/node_modules/${name}/
        chmod +x $out/lib/node_modules/${name}/package.json 2>/dev/null || true

        packageBin=$(node -p 'Object.values(require("./package.json").bin)[0]')
        chmod +x "$out/lib/node_modules/${name}/$packageBin"
        makeWrapper ${nodejs_24}/bin/node $out/bin/${bin} \
          --add-flags "$out/lib/node_modules/${name}/$packageBin" \
          --set NODE_PATH "$out/lib/node_modules/${name}/node_modules"

        runHook postInstall
      '';
      meta = {
        mainProgram = bin;
        platforms = systems;
      };
    };

  releaseBinary =
    {
      name,
      version,
      hash,
      ...
    }:
    let
      system = stdenv.hostPlatform.system;
      os = if lib.strings.hasSuffix "darwin" system then "darwin" else "linux";
      arch = if lib.strings.hasPrefix "aarch64" system then "arm64" else "amd64";
      asset = "${name}-v${version}-${os}-${arch}.tar.gz";
    in
    stdenv.mkDerivation {
      pname = name;
      inherit version;
      src = fetchurl {
        url = "https://github.com/kunchenguid/${name}/releases/download/v${version}/${asset}";
        hash = hash.${system};
      };
      sourceRoot = ".";
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        install -m 0755 ${name} $out/bin/${name}
        runHook postInstall
      '';
      meta = {
        mainProgram = name;
        platforms = systems;
      };
    };
  # herdr publishes a bare binary per platform, not an archive, and from its own
  # org rather than kunchenguid's. It is not in nixpkgs, so it is pinned here like
  # the rest of the crew tooling (ADR-0009).
  #
  # The macOS asset is adhoc-signed, and the store copy loses the executable bit
  # that the download carried, so install sets it explicitly.
  plainBinary =
    {
      name,
      version,
      owner,
      hash,
      ...
    }:
    let
      system = stdenv.hostPlatform.system;
      os = if lib.strings.hasSuffix "darwin" system then "macos" else "linux";
      arch = if lib.strings.hasPrefix "aarch64" system then "aarch64" else "x86_64";
      asset = "${name}-${os}-${arch}";
    in
    stdenv.mkDerivation {
      pname = name;
      inherit version;
      src = fetchurl {
        url = "https://github.com/${owner}/${name}/releases/download/v${version}/${asset}";
        hash = hash.${system};
      };
      dontUnpack = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        install -m 0755 $src $out/bin/${name}
        runHook postInstall
      '';
      meta = {
        mainProgram = name;
        platforms = systems;
      };
    };
in
{
  inherit npmCli releaseBinary plainBinary;
}
