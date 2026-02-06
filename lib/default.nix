{ pkgs, lib }:

lib.makeScope pkgs.newScope (
  self: with self; {
    buildRisc0Guest = callPackage ./buildRisc0Guest.nix {
      inherit (pkgs) r0vm risc0-rust;
    };
    buildRisc0Host = callPackage ./buildRisc0Host.nix {
      inherit (pkgs) r0vm;
    };
  }
)
