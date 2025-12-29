# risc0pkgs - Nixified [RISC Zero](https://www.risczero.com/) Packages

`risc0pkgs` contains risc0 related packages like `r0vm` and risc0's `rustc` fork packaged with Nix. The following section describes how to set up a risc0 project from scratch.

## Getting Started

It's recommended to get started by initializing your project using the default template:

```sh
mkdir risc0-workspace
cd risc0-workspace

nix flake init -t github:malda-protocol/risc0pkgs

git init
git add -A

nix build .
```

If you want to integrate `risc0` into your existing flake, see `./templates/default/flake.nix`.

## Development Shell

To get dropped into a development shell with all the required tooling, run:

```sh
nix develop
```
