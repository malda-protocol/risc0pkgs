final: prev: {
  r0vm = final.callPackage ./pkgs/r0vm { };
  risc0-rust = final.callPackage ./pkgs/risc0-rust { };

  # Cross-compiler for guest C/C++ code (riscv32im target)
  riscv32-cc = final.pkgsCross.riscv32-embedded.stdenv.cc;

  buildRisc0Package = final.callPackage ./lib/buildRisc0Package.nix { };
  buildRisc0Guest = final.callPackage ./lib/buildRisc0Guest.nix { };
  buildRisc0Host = final.callPackage ./lib/buildRisc0Host.nix { };
}
