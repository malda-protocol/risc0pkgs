final: prev: {
  r0vm = final.callPackage ./pkgs/r0vm { };
  risc0-rust = final.callPackage ./pkgs/risc0-rust { };
  buildRisc0Package = final.callPackage ./lib/buildRisc0Package.nix { };
}
