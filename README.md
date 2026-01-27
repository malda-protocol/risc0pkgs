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

---

## Experiments

At https://github.com/malda-protocol/risc0pkgs/commit/f1c8522a786fea9c3adae826a886a3a1fbf73d11 we were using combined vendor for Risc0 guest and host. Overall it works great, unless host methods is a workspace member and root's Cargo.lock introduces too many conflicting dependencies. Especially guest patches could easilly collide with host dependencies, and fixing that was not possible using single vendor directory.

At branch `feature/experimental-vendor-split` we have experimental work on having two vendor directories, but it does not seem to be a good solution.

Currently we use a dedicated Risc0 guest build, and Risc0 host build. Quite a lot of shenanigans are used to mimic Risc0 build process... over time we will see if this is a good and maintainable approach.
