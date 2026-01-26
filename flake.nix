{
  description = "A collection of risc0 related packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      rust-overlay,
      ...
    }:
    let
      eachSystem =
        systems: f:
        let
          # Merge together the outputs for all systems.
          op =
            attrs: system:
            let
              ret = f system;
              op =
                attrs: key:
                attrs
                // {
                  ${key} = (attrs.${key} or { }) // {
                    ${system} = ret.${key};
                  };
                };
            in
            builtins.foldl' op attrs (builtins.attrNames ret);
        in
        builtins.foldl' op { } systems;

      eachDefaultSystem = eachSystem [
        "x86_64-linux"
        "aarch64-darwin"
        "aarch64-linux" # builds from source (no prebuilt binaries available)
        "x86_64-darwin" # builds from source (no prebuilt binaries available)
      ];
    in
    {
      overlays.default = import ./overlay.nix;
      templates.default = {
        path = ./templates/default;
        description = "risc0 project template";
      };
    }
    // eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (import rust-overlay)
            self.overlays.default
          ];
        };
        lib = pkgs.recurseIntoAttrs (pkgs.callPackage ./lib { pkgs = pkgs; });
      in
      {
        inherit (pkgs) lib;
        packages = {
          inherit (pkgs) r0vm risc0-rust;
        };

        formatter = pkgs.nixfmt-tree;

        checks.format = pkgs.runCommand "format-check" { buildInputs = [ pkgs.nixfmt-tree ]; } ''
          cd ${self}
          nixfmt-tree --check
          touch $out
        '';
      }
    );
}
