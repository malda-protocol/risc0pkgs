{
  lib,
  stdenv,
  rustc-unwrapped,
  llvmPackages,
}:

let
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

# Use nixpkgs' rustc source and patches as-is, just add the risc0 zkVM target.
# The risc0-specific changes (previously patched for 1.91.1) are upstream since Rust 1.92.
rustc-unwrapped.overrideAttrs (oldAttrs: {
  pname = "rustc-risc0";

  # Override configure flags to build both host and Risc0 zkVM targets.
  # This ensures we have libs for both host (build scripts) and riscv (guest code).
  configureFlags =
    (lib.filter (
      flag:
      !(lib.hasPrefix "--target=" flag)
      && !(lib.hasPrefix "--tools=" flag)
      && flag != "--enable-profiler" # profiler needs libc
    ) (oldAttrs.configureFlags or [ ]))
    ++ [
      "--target=${hostTarget},riscv32im-risc0-zkvm-elf"
      "--tools=rustc,rustdoc,clippy,rustfmt,rust-analyzer-proc-macro-srv"
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
