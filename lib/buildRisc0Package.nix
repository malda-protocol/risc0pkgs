{ lib
, stdenv
, rustPlatform
, makeWrapper
, r0vm
, risc0-rust
}:

{
  pname,
  version ? "0.1.0",
  src,
  cargoLockFiles ? [ ],
  nativeBuildInputs ? [ ],
  preBuild ? "",
  postInstall ? "",
  wrapBinaries ? true,
  ...
}@args:

let
  # Extract rust version from risc0-rust version (e.g., "r0.1.91.1" -> "1.91.1")
  rustVersion = lib.removePrefix "r0." risc0-rust.version;

  arch = {
    x86_64-linux = "x86_64-unknown-linux-gnu";
    aarch64-linux = "aarch64-unknown-linux-gnu";
    aarch64-darwin = "aarch64-apple-darwin";
    x86_64-darwin = "x86_64-apple-darwin";
  }.${stdenv.hostPlatform.system};

  toolchainName = "v${rustVersion}-rust-${arch}";

  # Create combined vendor from all lock files
  vendors = map (lockFile: rustPlatform.importCargoLock { inherit lockFile; }) cargoLockFiles;
  vendorPaths = lib.concatStringsSep " " (map (v: "${v}") vendors);

  combinedVendor = stdenv.mkDerivation {
    name = "${pname}-combined-cargo-vendor";
    phases = [ "installPhase" ];

    installPhase = ''
      mkdir -p $out
      for vendor in ${vendorPaths}; do
        for crate in $vendor/*; do
          name=$(basename $crate)
          if [ ! -e "$out/$name" ]; then
            cp -r $crate $out/
          fi
        done
      done
    '';
  };

  # Remove custom args that shouldn't be passed to buildRustPackage
  cleanedArgs = builtins.removeAttrs args [
    "cargoLockFiles"
    "nativeBuildInputs"
    "preBuild"
    "postInstall"
    "wrapBinaries"
  ];
in

rustPlatform.buildRustPackage (cleanedArgs // {
  inherit pname version src;

  cargoDeps = combinedVendor;

  nativeBuildInputs = [ r0vm makeWrapper ] ++ nativeBuildInputs;

  preBuild = ''
    export HOME=$TMPDIR

    # Set up risc0 toolchain in expected location
    mkdir -p $HOME/.risc0/toolchains/${toolchainName}
    cp -r ${risc0-rust}/bin $HOME/.risc0/toolchains/${toolchainName}/
    cp -r ${risc0-rust}/lib $HOME/.risc0/toolchains/${toolchainName}/

    # Create settings.toml with default rust version
    cat > $HOME/.risc0/settings.toml << EOF
    [default_versions]
    rust = "${rustVersion}"
    EOF

    export PATH=${r0vm}/bin:$PATH
    export RISC0_BUILD_LOCKED=1

    # Set sysroot for the riscv32im target so cargo/rustc can find core libs
    export CARGO_TARGET_RISCV32IM_RISC0_ZKVM_ELF_RUSTFLAGS="--sysroot=$HOME/.risc0/toolchains/${toolchainName}"
  '' + preBuild;

  postInstall = lib.optionalString wrapBinaries ''
    for exe in $out/bin/*; do
      wrapProgram "$exe" --prefix PATH : ${r0vm}/bin
    done
  '' + postInstall;

  doCheck = false;

  passthru = {
    inherit r0vm risc0-rust rustVersion toolchainName;
  };
})
