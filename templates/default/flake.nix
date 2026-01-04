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
            cargoLockFiles = [
              ./Cargo.lock
              ./methods/Cargo.lock
              ./methods/guest/Cargo.lock
            ];
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
