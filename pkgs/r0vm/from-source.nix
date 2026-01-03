{ rustPlatform
, stdenv
, fetchFromGitHub
, pkg-config
, perl
, openssl
, lib
, darwin
}:

rustPlatform.buildRustPackage rec {
  pname = "r0vm";
  version = "3.0.4";
  src = fetchFromGitHub {
    owner = "risc0";
    repo = "risc0";
    rev = "v${version}";
    hash = "sha256-nUYLv9pgzve+mNuxwlRyF+V46604PFFRl0PKwNmXq4Q=";
  };
  meta = with lib; {
    homepage = "https://github.com/risc0/risc0";
    description = "risc0's zkVM";
  };

  buildAndTestSubdir = "risc0/r0vm";

  nativeBuildInputs = [
    pkg-config
    perl
  ];

  buildInputs = [
    openssl.dev
  ] ++ lib.optionals stdenv.isDarwin [
    darwin.apple_sdk.frameworks.SystemConfiguration
  ];

  doCheck = false;

  cargoHash = "sha256-Q2bLe7auGApX9Nb78trgf7xVwYe4imu31QkyiLlhCjY=";

  postPatch =
    let
      # see https://github.com/risc0/risc0/blob/v3.0.4/risc0/circuit/recursion/build.rs
      sha256Hash = "744b999f0a35b3c86753311c7efb2a0054be21727095cf105af6ee7d3f4d8849";
      recursionZkr = builtins.fetchurl {
        name = "recursion_zkr.zip";
        url = "https://risc0-artifacts.s3.us-west-2.amazonaws.com/zkr/${sha256Hash}.zip";
        sha256 = "sha256:0jc89lzpvvpnb88cz5bhf8hvwm005bxpw71iadkwicrm1agrjjvl";
      };
    in
    ''
      cp ${recursionZkr} ./risc0/circuit/recursion/src/recursion_zkr.zip
    '';
}
