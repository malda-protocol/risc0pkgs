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
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ risc0pkgs.overlays.default ];
          };
        in
        {
          default = pkgs.buildRisc0Package {
            pname = "hello-world";
            version = "0.1.0";
            src = ./.;
            cargoLocks = [
              ./Cargo.lock
              ./methods/Cargo.lock
              {
                lockFile = ./methods/guest/Cargo.lock;
                outputHashes = {
                  "base64-0.10.0" = "sha256-0NSljIX/yIt1dS+bq6i3DyeW82SosrScnH+/yTCMLII=";
                };
              }
            ];
          };
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ risc0pkgs.overlays.default ];
          };

          rustVersion = pkgs.lib.removePrefix "r0." pkgs.risc0-rust.version;
          arch = {
            x86_64-linux = "x86_64-unknown-linux-gnu";
            aarch64-linux = "aarch64-unknown-linux-gnu";
            aarch64-darwin = "aarch64-apple-darwin";
            x86_64-darwin = "x86_64-apple-darwin";
          }.${system};
          toolchainName = "v${rustVersion}-rust-${arch}";
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs = [ pkgs.cargo pkgs.r0vm pkgs.riscv32-cc ];

            shellHook = ''
              # Set up risc0 toolchain in expected location using symlinks.
              mkdir -p $HOME/.risc0/toolchains/${toolchainName}
              ln -s ${pkgs.risc0-rust}/bin $HOME/.risc0/toolchains/${toolchainName}/bin
              ln -s ${pkgs.risc0-rust}/lib $HOME/.risc0/toolchains/${toolchainName}/lib

              # Create settings.toml with default rust version
              printf '[default_versions]\nrust = "%s"\n' "${rustVersion}" > $HOME/.risc0/settings.toml

              # Set C/C++ cross-compiler for guest code (used by cc-rs in build.rs)
              export CC_riscv32im_risc0_zkvm_elf=${pkgs.riscv32-cc}/bin/${pkgs.riscv32-cc.targetPrefix}gcc
              export CXX_riscv32im_risc0_zkvm_elf=${pkgs.riscv32-cc}/bin/${pkgs.riscv32-cc.targetPrefix}g++
              export AR_riscv32im_risc0_zkvm_elf=${pkgs.riscv32-cc}/bin/${pkgs.riscv32-cc.targetPrefix}ar
            '';
          };
        }
      );
    };
}
