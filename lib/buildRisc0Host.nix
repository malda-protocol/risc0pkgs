{
  lib,
  rustPlatform,
  r0vm,
  makeWrapper,
  writeText,
}:

{
  pname,
  version ? "0.1.0",
  src,
  cargoLock, # path or { lockFile, outputHashes? }
  guests, # buildRisc0Guest output(s) — single drv or list
  methodsDir ? "methods", # path to methods crate relative to src root
  wrapBinaries ? true, # wrap output binaries with r0vm in PATH
  nativeBuildInputs ? [ ],
  preBuild ? "",
  postInstall ? "",
  ...
}@args:

let
  guests' = lib.toList guests;

  normalizedLock = if builtins.isAttrs cargoLock then cargoLock else { lockFile = cargoLock; };

  vendor = rustPlatform.importCargoLock {
    lockFile = normalizedLock.lockFile;
    outputHashes = normalizedLock.outputHashes or { };
  };

  # Generate methods.rs from pre-built guest derivations.
  # Each guest drv has $out/bin/<name>.bin (ProgramBinary) and $out/bin/<name>.id (hex image ID).
  hexToDecimal =
    hex:
    let
      hexChars = {
        "0" = 0;
        "1" = 1;
        "2" = 2;
        "3" = 3;
        "4" = 4;
        "5" = 5;
        "6" = 6;
        "7" = 7;
        "8" = 8;
        "9" = 9;
        "a" = 10;
        "b" = 11;
        "c" = 12;
        "d" = 13;
        "e" = 14;
        "f" = 15;
        "A" = 10;
        "B" = 11;
        "C" = 12;
        "D" = 13;
        "E" = 14;
        "F" = 15;
      };
      chars = lib.genList (i: builtins.substring i 1 hex) (builtins.stringLength hex);
    in
    lib.foldl (acc: c: acc * 16 + hexChars.${c}) 0 chars;

  guestConstants =
    guest:
    let
      bins = builtins.attrNames (
        lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".bin" name) (
          builtins.readDir "${guest}/bin"
        )
      );
    in
    map (
      binFile:
      let
        baseName = lib.removeSuffix ".bin" binFile;
        upper = lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] baseName);
        binPath = "${guest}/bin/${binFile}";
        idHex = lib.removeSuffix "\n" (builtins.readFile "${guest}/bin/${baseName}.id");
        chunks = lib.genList (i: builtins.substring (i * 8) 8 idHex) 8;
        idArray = lib.concatStringsSep ", " (map (c: toString (hexToDecimal c)) chunks);
      in
      ''
        pub const ${upper}_ELF: &[u8] = include_bytes!("${binPath}");
        pub const ${upper}_PATH: &str = "${binPath}";
        pub const ${upper}_ID: [u32; 8] = [${idArray}];
      ''
    ) bins;

  generatedMethodsRs = writeText "methods.rs" (
    lib.concatStringsSep "\n" (lib.flatten (map guestConstants guests'))
  );

  cleanedArgs = builtins.removeAttrs args [
    "cargoLock"
    "guests"
    "methodsDir"
    "wrapBinaries"
    "nativeBuildInputs"
    "preBuild"
    "postInstall"
  ];
in

rustPlatform.buildRustPackage (
  cleanedArgs
  // {
    inherit pname version src;

    auditable = false;
    cargoDeps = vendor;

    nativeBuildInputs = [
      makeWrapper
    ]
    ++ nativeBuildInputs;

    preBuild = ''
      # Replace methods/build.rs to copy our pre-generated methods.rs
      # instead of invoking risc0_build::embed_methods().
      cat > ${methodsDir}/build.rs << 'BUILDRS'
      fn main() {
          let out_dir = std::env::var("OUT_DIR").unwrap();
          std::fs::copy(
              "${generatedMethodsRs}",
              format!("{out_dir}/methods.rs"),
          ).unwrap();
      }
      BUILDRS
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
      inherit r0vm guests';
    };
  }
)
