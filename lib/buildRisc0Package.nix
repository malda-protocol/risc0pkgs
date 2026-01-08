{ lib
, stdenv
, rustPlatform
, makeWrapper
, r0vm
, risc0-rust
, lld
, riscv32-cc
}:

{ pname
, version ? "0.1.0"
, src
, cargoLocks ? [ ]  # List of { lockFile, outputHashes? } or just paths
, nativeBuildInputs ? [ ]
, preBuild ? ""
, postInstall ? ""
, wrapBinaries ? true
, ...
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
  # Each entry can be a path or { lockFile, outputHashes? }
  normalizeCargoLock = entry:
    if builtins.isAttrs entry
    then entry
    else { lockFile = entry; };

  vendors = map
    (entry:
      let normalized = normalizeCargoLock entry;
      in rustPlatform.importCargoLock {
        lockFile = normalized.lockFile;
        outputHashes = normalized.outputHashes or { };
      }
    )
    cargoLocks;
  vendorPaths = lib.concatStringsSep " " (map (v: "${v}") vendors);

  # Extract git sources from all Cargo.lock files
  extractGitSources = lockFile:
    let
      lock = builtins.fromTOML (builtins.readFile lockFile);
      packages = lock.package or [ ];
      gitPackages = builtins.filter (p: p ? source && lib.hasPrefix "git+" (p.source or "")) packages;
    in
    map (p: p.source) gitPackages;

  allGitSources = lib.unique (lib.flatten (map
    (entry:
      extractGitSources (normalizeCargoLock entry).lockFile
    )
    cargoLocks));

  # URL decode common percent-encoded characters
  urlDecode = s: builtins.replaceStrings
    [ "%2F" "%2f" "%3A" "%3a" "%40" "%20" ]
    [ "/" "/" ":" ":" "@" " " ]
    s;

  # Generate cargo config entries for git sources
  # source = "git+https://github.com/foo/bar?tag=v1.0#commit"
  # -> [source."git+https://github.com/foo/bar?tag=v1.0"]
  gitSourceToConfig = source:
    let
      # Remove the #commit suffix for the source key
      sourceKey = builtins.head (lib.splitString "#" source);
      # Extract base URL (without query params) for git field
      baseUrl = builtins.head (lib.splitString "?" (lib.removePrefix "git+" source));
      # Extract query params
      queryPart =
        let parts = lib.splitString "?" (lib.removePrefix "git+" source);
        in if builtins.length parts > 1
        then builtins.head (lib.splitString "#" (builtins.elemAt parts 1))
        else "";
      # Parse tag/branch/rev from query (URL-decode the values)
      tagMatch = builtins.match ".*tag=([^&#]+).*" "?${queryPart}";
      branchMatch = builtins.match ".*branch=([^&#]+).*" "?${queryPart}";
      revMatch = builtins.match ".*rev=([^&#]+).*" "?${queryPart}";
      tag = if tagMatch != null then urlDecode (builtins.head tagMatch) else null;
      branch = if branchMatch != null then urlDecode (builtins.head branchMatch) else null;
      rev = if revMatch != null then urlDecode (builtins.head revMatch) else null;
    in
    ''
      [source."${sourceKey}"]
      git = "${baseUrl}"
      ${lib.optionalString (tag != null) ''tag = "${tag}"''}
      ${lib.optionalString (branch != null) ''branch = "${branch}"''}
      ${lib.optionalString (rev != null) ''rev = "${rev}"''}
      replace-with = "vendored-sources"
    '';

  gitSourcesConfig = lib.concatStringsSep "\n" (map gitSourceToConfig allGitSources);

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
    "cargoLocks"
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

        # Set up risc0 toolchain in expected location.
        # We need a wrapper that unsets LD_LIBRARY_PATH because nixpkgs'
        # buildRustPackage sets it to include nixpkgs rustc libs, which causes
        # risc0-rust's rustc to detect the wrong sysroot.
        # See docs/LD_LIBRARY_PATH-sysroot-issue.md for details.
        mkdir -p $HOME/.risc0/toolchains/${toolchainName}/bin
        ln -s ${risc0-rust}/lib $HOME/.risc0/toolchains/${toolchainName}/lib

        printf '%s\n' '#!/bin/sh' 'unset LD_LIBRARY_PATH' 'exec ${risc0-rust}/bin/rustc "$@"' \
          > $HOME/.risc0/toolchains/${toolchainName}/bin/rustc
        chmod +x $HOME/.risc0/toolchains/${toolchainName}/bin/rustc

        # Create settings.toml with default rust version
        printf '[default_versions]\nrust = "%s"\n' "${rustVersion}" > $HOME/.risc0/settings.toml

        # Add git source replacements to cargo config.
        # buildRustPackage only sets up crates-io replacement, not git sources.
        cat >> /build/.cargo/config.toml << 'GITCONFIG'
    ${gitSourcesConfig}
    GITCONFIG

        export PATH=${r0vm}/bin:${lld}/bin:$PATH
        export RISC0_BUILD_LOCKED=1

        # Set C/C++ cross-compiler for guest code (used by cc-rs in build.rs)
        export CC_riscv32im_risc0_zkvm_elf=${riscv32-cc}/bin/${riscv32-cc.targetPrefix}gcc
        export CXX_riscv32im_risc0_zkvm_elf=${riscv32-cc}/bin/${riscv32-cc.targetPrefix}g++
        export AR_riscv32im_risc0_zkvm_elf=${riscv32-cc}/bin/${riscv32-cc.targetPrefix}ar
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
