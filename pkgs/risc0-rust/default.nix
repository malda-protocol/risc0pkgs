{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, zlib
}:

stdenv.mkDerivation rec {
  pname = "risc0-rust";
  # NOTE: You can find the latest version at https://github.com/risc0/rust/releases/latest.
  # Version format: r0.X.Y.Z where X.Y.Z is the Rust toolchain version
  version = "r0.1.91.1";

  src = fetchurl (
    {
      x86_64-linux = {
        url = "https://github.com/risc0/rust/releases/download/${version}/rust-toolchain-x86_64-unknown-linux-gnu.tar.gz";
        hash = "sha256-4IKh3ESr3vHZVGApWnAhjrKUq5mbg0Vw7JMtBWQczl0=";
      };
      aarch64-darwin = {
        url = "https://github.com/risc0/rust/releases/download/${version}/rust-toolchain-aarch64-apple-darwin.tar.gz";
        hash = "sha256-U8t7yy5awhooOtTf/JRCIIBq0V4RQdoYHRNfrB7ypOQ=";
      };
    }.${stdenv.hostPlatform.system} or (throw "Unsupported platform: ${stdenv.hostPlatform.system}")
  );

  sourceRoot = ".";

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.isLinux [
    stdenv.cc.cc.lib
    zlib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r bin $out/bin
    cp -r lib $out/lib

    runHook postInstall
  '';

  doInstallCheck = true;

  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/rustc --version

    runHook postInstallCheck
  '';
}
