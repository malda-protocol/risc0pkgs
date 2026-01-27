{
  lib,
  stdenv,
  rustPlatform,
  makeRustPlatform,
  cargo,
  r0vm,
  risc0-rust,
  lld,
  riscv32-cc,
  fetchurl,
}:

let
  # Create a Rust platform that uses risc0-rust as the compiler.
  # This avoids the LD_LIBRARY_PATH sysroot issue entirely — risc0-rust
  # is the only rustc in the build, so its sysroot is always correct.
  risc0RustPlatform = makeRustPlatform {
    rustc = risc0-rust;
    inherit cargo;
  };

  # Pre-built kernel ELF from risc0 v3.0.4 (V1COMPAT_ELF).
  # Every guest program is combined with this kernel into a ProgramBinary.
  kernelElf = fetchurl {
    url = "https://raw.githubusercontent.com/risc0/risc0/v3.0.4/risc0/zkos/v1compat/elfs/v1compat.elf";
    hash = "sha256-f/2ULk6Lq9dxCU9UmtCAz+qOyywFyYbidcAR9Bl52SE=";
  };

  rustVersion = lib.removePrefix "r0." risc0-rust.version;
in

{
  pname,
  version ? "0.1.0",
  src,
  cargoLock, # path or { lockFile, outputHashes? }
  nativeBuildInputs ? [ ],
  preBuild ? "",
  ...
}@args:

let
  # Normalize cargoLock to { lockFile, outputHashes? }
  normalizedLock = if builtins.isAttrs cargoLock then cargoLock else { lockFile = cargoLock; };

  vendor = risc0RustPlatform.importCargoLock {
    lockFile = normalizedLock.lockFile;
    outputHashes = normalizedLock.outputHashes or { };
  };

  # Git source config is NOT needed here: since we use a single vendor from
  # importCargoLock (not a combinedVendor), the configureCargoVendoredDepsHook
  # automatically generates git source entries from .cargo-checksum.json metadata.

  cleanedArgs = builtins.removeAttrs args [
    "cargoLock"
    "nativeBuildInputs"
    "preBuild"
  ];
in

risc0RustPlatform.buildRustPackage (
  cleanedArgs
  // {
    inherit pname version src;

    auditable = false;
    cargoDeps = vendor;

    nativeBuildInputs = [
      lld
      riscv32-cc
      r0vm
    ]
    ++ nativeBuildInputs;

    # Rustc flags matching risc0-build's guest compilation:
    #   -C passes=lower-atomic     (single-threaded guest, no real atomics)
    #   -C link-arg=-Ttext=0x00200800  (user-mode text start address)
    #   -C link-arg=--fatal-warnings
    #   -C panic=abort
    #   --cfg getrandom_backend="custom"
    CARGO_TARGET_RISCV32IM_RISC0_ZKVM_ELF_RUSTFLAGS = lib.concatStringsSep " " [
      "-Cpasses=lower-atomic"
      "-Clink-arg=-Ttext=0x00200800"
      "-Clink-arg=--fatal-warnings"
      "-Cpanic=abort"
      "--cfg"
      "getrandom_backend=\"custom\""
    ];

    # Override buildPhase: the cargoBuildHook hardcodes --target from
    # stdenv.hostPlatform via template substitution, so we bypass it
    # and call cargo directly with our riscv32im target.
    buildPhase = ''
      runHook preBuild

      cargo build \
        --target riscv32im-risc0-zkvm-elf \
        --frozen \
        --release \
        -j $NIX_BUILD_CORES

      runHook postBuild
    '';

    preBuild = ''
      # Set C/C++ cross-compiler for guest code (used by cc-rs in build.rs)
      export CC_riscv32im_risc0_zkvm_elf=${riscv32-cc}/bin/${riscv32-cc.targetPrefix}gcc
      export CXX_riscv32im_risc0_zkvm_elf=${riscv32-cc}/bin/${riscv32-cc.targetPrefix}g++
      export AR_riscv32im_risc0_zkvm_elf=${riscv32-cc}/bin/${riscv32-cc.targetPrefix}ar

      export PATH=${lld}/bin:$PATH

      # Create dummy README.md for crates that use include_str!("../../../README.md")
      echo "# Vendored crate" > /build/README.md
    ''
    + preBuild;

    # Custom install: cross-compiled ELF is in target/riscv32im-risc0-zkvm-elf/release/,
    # and we also construct ProgramBinary and compute image ID.
    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin

      # Install raw ELF binaries from the cross-compilation target directory
      for f in target/riscv32im-risc0-zkvm-elf/release/*; do
        [ -f "$f" ] || continue
        case "$f" in
          *.d|*.rlib|*.rmeta) continue ;;
        esac
        # Skip files that are not ELF binaries
        if ! head -c4 "$f" | grep -q $'\x7fELF'; then
          continue
        fi
        name=$(basename "$f")
        cp "$f" "$out/bin/$name"

        # Construct ProgramBinary (R0BF format):
        #   [28-byte fixed header] [user_elf_len:u32 LE] [user_elf] [kernel_elf]
        # The fixed header encodes: magic "R0BF", format version 1,
        # and a postcard-serialized AbiVersion(V1Compat, "1.0.0").
        USER_SIZE=$(stat -c%s "$out/bin/$name")
        {
          printf '\x52\x30\x42\x46'
          printf '\x01\x00\x00\x00'
          printf '\x10\x00\x00\x00'
          printf '\x01\x00\x00\x00'
          printf '\x08\x00\x00\x00'
          printf '\x00\x00\x05\x31\x2e\x30\x2e\x30'
          printf "\\x$(printf '%02x' $((USER_SIZE & 0xFF)))\\x$(printf '%02x' $(((USER_SIZE>>8) & 0xFF)))\\x$(printf '%02x' $(((USER_SIZE>>16) & 0xFF)))\\x$(printf '%02x' $(((USER_SIZE>>24) & 0xFF)))"
          cat "$out/bin/$name"
          cat "${kernelElf}"
        } > "$out/bin/$name.bin"

        # Compute image ID using r0vm
        r0vm --elf "$out/bin/$name.bin" --id > "$out/bin/$name.id"
      done

      runHook postInstall
    '';

    doCheck = false;

    passthru = {
      inherit
        risc0-rust
        r0vm
        rustVersion
        kernelElf
        ;
    };
  }
)
