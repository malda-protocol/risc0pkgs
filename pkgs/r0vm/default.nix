{ lib
, stdenv
, fetchurl
, autoPatchelfHook
}:

stdenv.mkDerivation rec {
  pname = "r0vm";
  # NOTE: You can find the latest version at https://github.com/risc0/risc0/releases/latest.
  version = "3.0.4";

  src = fetchurl (
    {
      x86_64-linux = {
        url = "https://github.com/risc0/risc0/releases/download/v${version}/cargo-risczero-x86_64-unknown-linux-gnu.tgz";
        hash = "sha256-Oyn7XrE8/yVbL/4PbnlirEqq9q9ZcFYn4oUfHbH6eC8=";
      };
      aarch64-darwin = {
        url = "https://github.com/risc0/risc0/releases/download/v${version}/cargo-risczero-aarch64-apple-darwin.tgz";
        hash = "sha256-9tSEbVzWouUWUFm1ZvmjH4eVgrwlNLlQFan0BNObGHU=";
      };
    }.${stdenv.hostPlatform.system} or (throw "Unsupported platform: ${stdenv.hostPlatform.system}")
  );

  sourceRoot = ".";

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.isLinux [
    # Required for ELF-patching libstdc++.so (C++ standard library) and libgcc_s.so (GCC runtime library).
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -m755 r0vm $out/bin/r0vm

    runHook postInstall
  '';

  doInstallCheck = true;

  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/r0vm --version

    runHook postInstallCheck
  '';
}
