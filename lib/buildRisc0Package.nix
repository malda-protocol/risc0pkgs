{
  lib,
  stdenv,
  rustPlatform,
  makeWrapper,
  r0vm,
  risc0-rust,
  lld,
  riscv32-cc,
  fetchgit,
}:

{
  pname,
  version ? "0.1.0",
  src,
  cargoLocks ? [ ], # List of { lockFile, outputHashes? } or just paths
  guestCargoLocks ? [ ], # List of { lockFile, outputHashes?, configDir } for guest builds
  nativeBuildInputs ? [ ],
  preBuild ? "",
  postInstall ? "",
  wrapBinaries ? true,
  ...
}@args:

let
  # Extract rust version from risc0-rust version (e.g., "r0.1.91.1" -> "1.91.1")
  rustVersion = lib.removePrefix "r0." risc0-rust.version;

  arch =
    {
      x86_64-linux = "x86_64-unknown-linux-gnu";
      aarch64-linux = "aarch64-unknown-linux-gnu";
      aarch64-darwin = "aarch64-apple-darwin";
      x86_64-darwin = "x86_64-apple-darwin";
    }
    .${stdenv.hostPlatform.system};

  toolchainName = "v${rustVersion}-rust-${arch}";

  # Create combined vendor from all lock files
  # Each entry can be a path or { lockFile, outputHashes? }
  normalizeCargoLock = entry: if builtins.isAttrs entry then entry else { lockFile = entry; };

  # Override importCargoLock to fetch git submodules, matching cargo's behavior.
  importCargoLock = rustPlatform.importCargoLock.override {
    fetchgit = args: fetchgit (args // { fetchSubmodules = true; });
  };

  vendors = map (
    entry:
    let
      normalized = normalizeCargoLock entry;
    in
    importCargoLock {
      lockFile = normalized.lockFile;
      outputHashes = normalized.outputHashes or { };
    }
  ) cargoLocks;
  vendorPaths = lib.concatStringsSep " " (map (v: "${v}") vendors);

  # Guest vendors (from guestCargoLocks)
  guestVendors = map (
    entry:
    let
      normalized = normalizeCargoLock entry;
    in
    rustPlatform.importCargoLock {
      lockFile = normalized.lockFile;
      outputHashes = normalized.outputHashes or { };
    }
  ) guestCargoLocks;
  guestVendorPaths = lib.concatStringsSep " " (map (v: "${v}") guestVendors);

  # Extract git sources from all Cargo.lock files
  extractGitSources =
    lockFile:
    let
      lock = builtins.fromTOML (builtins.readFile lockFile);
      packages = lock.package or [ ];
      gitPackages = builtins.filter (p: p ? source && lib.hasPrefix "git+" (p.source or "")) packages;
    in
    map (p: p.source) gitPackages;

  allGitSources = lib.unique (
    lib.flatten (map (entry: extractGitSources (normalizeCargoLock entry).lockFile) cargoLocks)
  );

  guestGitSources = lib.unique (
    lib.flatten (map (entry: extractGitSources (normalizeCargoLock entry).lockFile) guestCargoLocks)
  );

  # URL decode common percent-encoded characters
  urlDecode =
    s: builtins.replaceStrings [ "%2F" "%2f" "%3A" "%3a" "%40" "%20" ] [ "/" "/" ":" ":" "@" " " ] s;

  # Generate cargo config entries for git sources
  # source = "git+https://github.com/foo/bar?tag=v1.0#commit"
  # -> [source."git+https://github.com/foo/bar?tag=v1.0"]
  gitSourceToConfig =
    source:
    let
      # Remove the #commit suffix for the source key
      sourceKey = builtins.head (lib.splitString "#" source);
      # Extract base URL (without query params) for git field
      baseUrl = builtins.head (lib.splitString "?" (lib.removePrefix "git+" source));
      # Extract query params
      queryPart =
        let
          parts = lib.splitString "?" (lib.removePrefix "git+" source);
        in
        if builtins.length parts > 1 then
          builtins.head (lib.splitString "#" (builtins.elemAt parts 1))
        else
          "";
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
  guestGitSourcesConfig = lib.concatStringsSep "\n" (map gitSourceToConfig guestGitSources);

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

  guestVendor = stdenv.mkDerivation {
    name = "${pname}-guest-cargo-vendor";
    phases = [ "installPhase" ];

    installPhase = ''
      mkdir -p $out
      for vendor in ${guestVendorPaths}; do
        for crate in $vendor/*; do
          name=$(basename $crate)
          if [ ! -e "$out/$name" ]; then
            cp -r $crate $out/
          fi
        done
      done
    '';
  };

  guestConfigDirs = lib.filter (d: d != null) (
    map (entry: (normalizeCargoLock entry).configDir or null) guestCargoLocks
  );

  guestCargoConfigContent =
    "[source.crates-io]\n"
    + "replace-with = \"vendored-sources\"\n"
    + "\n"
    + "[source.vendored-sources]\n"
    + "directory = \"/build/guest-vendor\"\n"
    + lib.optionalString (guestGitSourcesConfig != "") "\n${guestGitSourcesConfig}";

  # Copy guest vendor into /build/ with dereferenced symlinks so that
  # relative include_str! paths (e.g., "../../../README.md") resolve
  # within /build/ where README.md already exists.
  guestCargoConfigScript =
    lib.optionalString (guestConfigDirs != [ ]) (
      "cp -rL ${guestVendor} /build/guest-vendor\n"
    )
    + lib.concatMapStrings (
      configDir:
      "mkdir -p ${configDir}/.cargo\n"
      + "cat > ${configDir}/.cargo/config.toml << 'GUESTCARGOCONFIG'\n"
      + guestCargoConfigContent
      + "GUESTCARGOCONFIG\n"
    ) guestConfigDirs;

  # Remove custom args that shouldn't be passed to buildRustPackage
  cleanedArgs = builtins.removeAttrs args [
    "cargoLocks"
    "guestCargoLocks"
    "nativeBuildInputs"
    "preBuild"
    "postInstall"
    "wrapBinaries"
  ];
in

rustPlatform.buildRustPackage (
  cleanedArgs
  // {
    inherit pname version src;

    # Disable cargo-auditable wrapping. It sets RUSTC=cargo-auditable, which
    # breaks risc0's guest build: the inner cargo invokes it directly as
    # `cargo-auditable rustc -vV` and cargo-auditable rejects that usage.
    auditable = false;

    cargoDeps = combinedVendor;

    nativeBuildInputs = [
      r0vm
      makeWrapper
    ]
    ++ nativeBuildInputs;

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

      ${guestCargoConfigScript}
          export PATH=${r0vm}/bin:${lld}/bin:$PATH
          export RISC0_BUILD_LOCKED=1

          # Set C/C++ cross-compiler for guest code (used by cc-rs in build.rs)
          export CC_riscv32im_risc0_zkvm_elf=${riscv32-cc}/bin/${riscv32-cc.targetPrefix}gcc
          export CXX_riscv32im_risc0_zkvm_elf=${riscv32-cc}/bin/${riscv32-cc.targetPrefix}g++
          export AR_riscv32im_risc0_zkvm_elf=${riscv32-cc}/bin/${riscv32-cc.targetPrefix}ar

          # Create dummy README.md for crates that use include_str!("../../../README.md")
          # (e.g., risc0-steel references workspace root README from within crates/steel/src)
          echo "# Vendored crate" > /build/README.md
    ''
    + preBuild;

    postInstall =
      lib.optionalString wrapBinaries ''
        for exe in $out/bin/*; do
          wrapProgram "$exe" --prefix PATH : ${r0vm}/bin
        done
      ''
      + postInstall;

    doCheck = false;

    passthru = {
      inherit
        r0vm
        risc0-rust
        rustVersion
        toolchainName
        ;
    };
  }
)
