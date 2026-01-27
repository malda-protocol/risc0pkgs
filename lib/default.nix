{ pkgs, lib }:

lib.makeScope pkgs.newScope (
  self: with self; {
    buildRisc0Package = callPackage ./buildRisc0Package.nix {
      inherit (pkgs) r0vm risc0-rust;
    };
    buildRisc0Guest = callPackage ./buildRisc0Guest.nix {
      inherit (pkgs) r0vm risc0-rust;
    };
    buildRisc0Host = callPackage ./buildRisc0Host.nix {
      inherit (pkgs) r0vm;
    };
  }
)
