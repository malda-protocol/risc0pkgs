{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    risc0pkgs.url = "github:malda-protocol/risc0pkgs";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      risc0pkgs,
      treefmt-nix,
      advisory-db,
      ...
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          programs.rustfmt.enable = true;
        }
      );
    in
    {
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      checks = forAllSystems (system: {
        formatting = treefmtEval.${system}.config.build.check self;
        audit =
          nixpkgs.legacyPackages.${system}.runCommand "cargo-audit"
            {
              buildInputs = [ nixpkgs.legacyPackages.${system}.cargo-audit ];
            }
            ''
              # NOTE: RUSTSEC-2023-0071 (rsa) and RUSTSEC-2025-0055 (tracing-subscriber)
              # are transitive dependencies from risc0-zkvm/risc0-build packages
              # that cannot be fixed from the template side.
              IGNORE="--ignore RUSTSEC-2023-0071 --ignore RUSTSEC-2025-0055"
              cargo-audit audit --no-fetch $IGNORE --db ${advisory-db} --file ${./Cargo.lock}
              cargo-audit audit --no-fetch $IGNORE --db ${advisory-db} --file ${./methods/Cargo.lock}
              cargo-audit audit --no-fetch $IGNORE --db ${advisory-db} --file ${./methods/guest/Cargo.lock}
              touch $out
            '';
      });
      packages = forAllSystems (
        system:
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
            ];
            guestCargoLocks = [
              {
                lockFile = ./methods/guest/Cargo.lock;
                configDir = "methods";
                outputHashes = {
                  "base64-0.10.0" = "sha256-0NSljIX/yIt1dS+bq6i3DyeW82SosrScnH+/yTCMLII=";
                  "risc0-steel-2.4.1" = "sha256-fFsds95M8u2jjfFZ+M3AuX3CzwKG3XYsLgk0Bk32ras=";
                  "c-kzg-2.1.5" = "sha256-wlmTH0kGGYlVqlFetAMTkI0wQ/8n8uTx8baYgbQuAN4=";
                };
              }
            ];
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ risc0pkgs.overlays.default ];
          };

          rustVersion = pkgs.lib.removePrefix "r0." pkgs.risc0-rust.version;
          arch =
            {
              x86_64-linux = "x86_64-unknown-linux-gnu";
              aarch64-linux = "aarch64-unknown-linux-gnu";
              aarch64-darwin = "aarch64-apple-darwin";
              x86_64-darwin = "x86_64-apple-darwin";
            }
            .${system};
          toolchainName = "v${rustVersion}-rust-${arch}";
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs = [
              pkgs.cargo
              pkgs.r0vm
              pkgs.riscv32-cc
            ];

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
