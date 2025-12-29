{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    risc0pkgs.url = "github:malda-protocol/risc0pkgs";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, crane, risc0pkgs, rust-overlay, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" ];
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };

          r0vm = risc0pkgs.packages.${system}.r0vm;
          risc0-rust = risc0pkgs.packages.${system}.risc0-rust;

          toolchainName = "v1.91.1-rust-x86_64-unknown-linux-gnu";

          # Rust toolchain with RISCV target
          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            targets = [ "riscv64gc-unknown-none-elf" ];
          };

          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

          # Vendor dependencies from ALL lock files
          vendoredDeps = craneLib.vendorMultipleCargoDeps {
            cargoLockList = [
              ./Cargo.lock
              ./methods/Cargo.lock
              ./methods/guest/Cargo.lock
            ];

            overrideVendorCargoPackage = p: drv:
              # For example, patch a specific crate, in this case byteorder-1.5.0
              if p.name == "risc0-build" then #  && p.version == "3.0.4"
                drv.overrideAttrs (_old: {
                  # Specifying an arbitrary patch to apply
                  patches = [
                    ./0001-do-not-sanitize-cargo-home.patch
                  ];

                  # Similarly we can also run additional hooks to make changes
                  postPatch = ''
                    echo running some arbitrary command to make modifications
                  '';
                })
              else
                # Nothing to change, leave the derivations as is
                drv;
          };

          # cleanCargoSource preserves guest (it has Cargo.toml)
          src = craneLib.cleanCargoSource ./.;

          commonArgs = {
            inherit src;
            strictDeps = true;
            cargoVendorDir = vendoredDeps;

            RISC0_BUILD_LOCKED = "1";
            nativeBuildInputs = [ r0vm ];
            preBuild = ''
              export HOME=$TMPDIR
              mkdir -p $HOME/.risc0/toolchains/${toolchainName}
              cp -r ${risc0-rust}/bin $HOME/.risc0/toolchains/${toolchainName}/
              cp -r ${risc0-rust}/lib $HOME/.risc0/toolchains/${toolchainName}/
              export PATH=${r0vm}/bin:$PATH
            '';
          };

          # Build everything in one pass to avoid stale artifacts
          mainPackage = craneLib.mkCargoDerivation (commonArgs // {
            cargoArtifacts = null;
            doCheck = false;
            buildPhaseCargoCommand = "cargo build --release";
            installPhaseCommand = "mkdir -p $out/bin && cp target/release/hello-world $out/bin/";

            postInstall = ''
              mkdir -p $out/share
              cp target/release/build/hello-world-methods-*/out/methods.rs $out/share/ || true
              cp -r target/riscv-guest $out/share/ || true

              # Generate image ID from guest ELF
              for elf in target/riscv-guest/hello-world-methods/*/riscv32im-risc0-zkvm-elf/release/*.bin; do
                if [ -f "$elf" ]; then
                  ${r0vm}/bin/r0vm --elf "$elf" --id > $out/share/$(basename "$elf" .bin).id
                fi
              done
            '';
          });
        in
        {
          default = mainPackage;
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };
          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            targets = [ "riscv64gc-unknown-none-elf" ];
          };
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs = [ rustToolchain ];
          };
        }
      );
    };
}
