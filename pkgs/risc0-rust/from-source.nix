{
  lib,
  stdenv,
  rustc-unwrapped,
  fetchurl,
  llvmPackages,
}:

let
  rustVersion = "1.91.1";

  # Map Nix system to Rust target triple
  hostTarget =
    {
      x86_64-linux = "x86_64-unknown-linux-gnu";
      aarch64-linux = "aarch64-unknown-linux-gnu";
      x86_64-darwin = "x86_64-apple-darwin";
      aarch64-darwin = "aarch64-apple-darwin";
    }
    .${stdenv.hostPlatform.system};
in

rustc-unwrapped.overrideAttrs (oldAttrs: {
  pname = "rustc-risc0";
  version = rustVersion;

  src =
    (fetchurl {
      url = "https://static.rust-lang.org/dist/rustc-${rustVersion}-src.tar.gz";
      sha256 = "sha256-ONziBdOfYVcSYfBEQjehzp7+y5cOdg2OxNlXr1tEVyM=";
    })
    // {
      # Mark as release tarball to prevent postPatch from trying to mkdir .cargo
      # (release tarballs already have .cargo directory)
      passthru.isReleaseTarball = true;
    };

  # Apply minor Risc0 patch.
  # This patch is already in upstream Rust 1.92+, but needed for 1.91.1.
  patches = (oldAttrs.patches or [ ]) ++ [
    (fetchurl {
      url = "https://github.com/risc0/rust/commit/235d917b7e34d48f85cacf2bd331e2899c7ee42a.patch";
      sha256 = "sha256-bEh9YTjBrGCXIquwCwFRC3j8W+SU3zOX6gH8yQ8GQYk=";
    })
  ];

  # Override configure flags to build both host and Risc0 zkVM targets.
  # This ensures we have libs for both host (build scripts) and riscv (guest code).
  configureFlags =
    (lib.filter (
      flag: !(lib.hasPrefix "--target=" flag) && flag != "--enable-profiler" # profiler needs libc
    ) (oldAttrs.configureFlags or [ ]))
    ++ [
      "--target=${hostTarget},riscv32im-risc0-zkvm-elf"
      "--disable-docs" # docs fail on bare-metal target
      # Use unwrapped clang for RISC-V cross-compilation
      # (wrapped clang adds hardening flags not supported on RISC-V)
      "--set=target.riscv32im-risc0-zkvm-elf.cc=${llvmPackages.clang-unwrapped}/bin/clang"
      "--set=target.riscv32im-risc0-zkvm-elf.cxx=${llvmPackages.clang-unwrapped}/bin/clang++"
      "--set=target.riscv32im-risc0-zkvm-elf.linker=${llvmPackages.lld}/bin/ld.lld"
    ];

  # Set RUSTFLAGS for RISC-V zkvm target (required by rzup build process)
  # This handles atomic operations for the RISC-V target
  env = (oldAttrs.env or { }) // {
    CARGO_TARGET_RISCV32IM_RISC0_ZKVM_ELF_RUSTFLAGS = "-Cpasses=lower-atomic";
  };
})
