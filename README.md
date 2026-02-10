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

## Troubleshooting

### Rust compiler version mismatch

If you get errors about different Rust compilers being used (e.g. "found crate compiled by an incompatible version of rustc"), the `~/.risc0/settings.toml` file may be pointing to a stale or mismatched toolchain version.

Check the current default:

```sh
cat ~/.risc0/settings.toml
```

List installed toolchains:

```sh
ls ~/.risc0/toolchains/
```

Make sure `settings.toml` references a version that matches one of the installed toolchains. If not, either update the version in `settings.toml` or re-enter `nix develop` to reconfigure it.

### "RISC Zero zkVM feature bigint2 is not available"

If your guest code depends on `risc0-bigint2`, you need to set the `RISC0_FEATURE_bigint2` environment variable. Add it to both your `buildRisc0Guest` derivation and your `devShells.default`:

```nix
# In buildRisc0Guest:
RISC0_FEATURE_bigint2 = "";

# In devShells.default mkShell:
RISC0_FEATURE_bigint2 = "";
```

### Building from source on platforms without prebuilts

Prebuilt binaries are available for `x86_64-linux` and `aarch64-darwin`. On other platforms (e.g. `aarch64-linux`, `x86_64-darwin`), the Rust toolchain is compiled from source, which can take 1+ hours on the first build. Subsequent builds will use the cached result from the Nix store.

---

## Experiments

At https://github.com/malda-protocol/risc0pkgs/commit/f1c8522a786fea9c3adae826a886a3a1fbf73d11 we were using combined vendor for Risc0 guest and host. Overall it works great, unless host methods is a workspace member and root's Cargo.lock introduces too many conflicting dependencies. Especially guest patches could easilly collide with host dependencies, and fixing that was not possible using single vendor directory.

At branch `feature/experimental-vendor-split` we have experimental work on having two vendor directories, but it does not seem to be a good solution. **Update:** probably it just requires cherry-picking 'submodule clone fix', same as the master branch - see commit ceb955bc0aa50a6dc6eec78f74492c293f9c0c4f.

Currently we use a dedicated Risc0 guest build, and Risc0 host build. Quite a lot of shenanigans are used to mimic Risc0 build process... over time we will see if this is a good and maintainable approach.
