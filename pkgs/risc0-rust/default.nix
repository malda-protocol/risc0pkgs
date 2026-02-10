{
  lib,
  stdenv,
  callPackage,
  forceFromSource ? false,
}:

let
  # Platforms with prebuilt binaries available
  prebuiltPlatforms = [
    "x86_64-linux"
    "aarch64-darwin"
  ];

  hasPrebuilt = builtins.elem stdenv.hostPlatform.system prebuiltPlatforms;

  usePrebuilt = hasPrebuilt && !forceFromSource;

  prebuilt = callPackage ./prebuilt.nix { };
  fromSource = callPackage ./from-source.nix { };

  selectedPackage =
    if usePrebuilt then
      prebuilt
    else
      fromSource;
in
selectedPackage.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit prebuilt fromSource;
    isPrebuilt = usePrebuilt;
    # Required by nixpkgs' buildRustPackage (rustc.targetPlatforms)
    targetPlatforms = old.meta.platforms or lib.platforms.all;
    badTargetPlatforms = [ ];
  };
})
