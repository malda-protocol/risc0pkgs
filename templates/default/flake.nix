{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    risc0pkgs.url = "github:malda-protocol/risc0pkgs";
  };

  outputs = { self, nixpkgs, risc0pkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          r0vm = risc0pkgs.packages.${system}.r0vm;
          risc0-rust = risc0pkgs.packages.${system}.risc0-rust;

          # Toolchain version must match what's in risc0-rust
          rustVersion = "1.91.1";
          arch = {
            x86_64-linux = "x86_64-unknown-linux-gnu";
            aarch64-linux = "aarch64-unknown-linux-gnu";
            aarch64-darwin = "aarch64-apple-darwin";
            x86_64-darwin = "x86_64-apple-darwin";
          }.${system};
          toolchainName = "v${rustVersion}-rust-${arch}";

          # Vendor dependencies from all lock files and combine them
          combinedVendor = pkgs.stdenv.mkDerivation {
            name = "combined-cargo-vendor";
            phases = [ "installPhase" ];

            mainVendor = pkgs.rustPlatform.importCargoLock {
              lockFile = ./Cargo.lock;
            };
            methodsVendor = pkgs.rustPlatform.importCargoLock {
              lockFile = ./methods/Cargo.lock;
            };
            guestVendor = pkgs.rustPlatform.importCargoLock {
              lockFile = ./methods/guest/Cargo.lock;
            };

            installPhase = ''
              mkdir -p $out
              # Copy all crates from all vendor directories
              for vendor in $mainVendor $methodsVendor $guestVendor; do
                for crate in $vendor/*; do
                  name=$(basename $crate)
                  if [ ! -e "$out/$name" ]; then
                    cp -r $crate $out/
                  fi
                done
              done
            '';
          };
        in
        {
          default = pkgs.rustPlatform.buildRustPackage {
            pname = "hello-world";
            version = "0.1.0";
            src = ./.;

            cargoDeps = combinedVendor;

            nativeBuildInputs = [ r0vm pkgs.makeWrapper ];

            postInstall = ''
              wrapProgram $out/bin/hello-world \
                --prefix PATH : ${r0vm}/bin
            '';

            preBuild = ''
              export HOME=$TMPDIR

              # Set up risc0 toolchain in expected location
              mkdir -p $HOME/.risc0/toolchains/${toolchainName}
              cp -r ${risc0-rust}/bin $HOME/.risc0/toolchains/${toolchainName}/
              cp -r ${risc0-rust}/lib $HOME/.risc0/toolchains/${toolchainName}/

              # Create settings.toml with default rust version
              cat > $HOME/.risc0/settings.toml << EOF
              [default_versions]
              rust = "${rustVersion}"
              EOF

              export PATH=${r0vm}/bin:$PATH
              export RISC0_BUILD_LOCKED=1
            '';

            doCheck = false;
          };
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [ rustc cargo ];
          };
        }
      );
    };
}
