{ pkgs, lib }:

lib.makeScope pkgs.newScope (self: with self; {
  buildRisc0Package = callPackage ./buildRisc0Package.nix {
    inherit (pkgs) r0vm risc0-rust;
  };
})
