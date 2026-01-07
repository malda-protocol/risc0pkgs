# LD_LIBRARY_PATH Causes Wrong Sysroot Detection in Nix Builds

## Problem

When building RISC Zero guest code inside a nix sandbox using `rustPlatform.buildRustPackage`, the risc0-rust toolchain's `rustc --print sysroot` returns the **wrong** sysroot path (nixpkgs rustc instead of risc0-rust).

This causes the error:
```
error[E0463]: can't find crate for `core`
  = note: the `riscv32im-risc0-zkvm-elf` target may not be installed
```

## Root Cause

nixpkgs' `rustPlatform.buildRustPackage` sets `LD_LIBRARY_PATH` to include the nixpkgs rustc library path:

```
LD_LIBRARY_PATH=...:/nix/store/<hash>-rustc-1.91.1/lib/rustlib/aarch64-unknown-linux-gnu/lib
```

When risc0-rust's rustc binary runs and tries to determine its sysroot, it inspects `LD_LIBRARY_PATH`, finds the nixpkgs rustlib path, and **infers the wrong sysroot** from it.

### Demonstration

```rust
// With LD_LIBRARY_PATH set (wrong):
let output = Command::new(&risc0_rustc).arg("--print").arg("sysroot").output();
// Returns: /nix/store/<hash>-rustc-1.91.1  (nixpkgs rustc!)

// Without LD_LIBRARY_PATH (correct):
let output = Command::new(&risc0_rustc)
    .env_remove("LD_LIBRARY_PATH")
    .arg("--print").arg("sysroot").output();
// Returns: /nix/store/<hash>-rustc-risc0-1.91.1  (correct!)
```

## Why This Happens

1. `buildRustPackage` compiles the host code using nixpkgs' cargo/rustc
2. nixpkgs sets `LD_LIBRARY_PATH` so rustc can find its runtime libraries
3. During the build, `risc0-build` (a build.rs dependency) spawns a **nested** cargo process to compile guest code
4. This nested cargo uses risc0-rust toolchain (via rzup/RUSTC env var)
5. But the `LD_LIBRARY_PATH` from the parent build pollutes the environment
6. risc0-rust's rustc uses `LD_LIBRARY_PATH` to infer sysroot, gets the wrong answer
7. Guest compilation fails because risc0-rust looks in nixpkgs sysroot (which lacks riscv32im target)

## Solutions

### Option 1: Wrapper with explicit `--sysroot` (removed in 5f17556c0a364ab96ea402c9aedae0f8fd8163bd)

Create a wrapper script that explicitly passes `--sysroot`:

```bash
#!/bin/sh
exec /nix/store/<hash>-rustc-risc0-1.91.1/bin/rustc --sysroot /nix/store/<hash>-rustc-risc0-1.91.1 "$@"
```

This bypasses sysroot detection entirely.

### Option 2: Unset `LD_LIBRARY_PATH` in risc0-build

Modify risc0-build's `cargo_command_internal` to remove `LD_LIBRARY_PATH`:

```rust
cmd.env_remove("LD_LIBRARY_PATH");
```

This allows rustc to correctly detect its sysroot from its binary location.

### Option 3: Wrapper that unsets `LD_LIBRARY_PATH` (CURRENT SOLUTION)

Create a rustc wrapper script that unsets `LD_LIBRARY_PATH` before executing the real rustc.
This ensures the host build still has access to `LD_LIBRARY_PATH` while the guest build
(which uses the wrapper via rzup) runs in a clean environment.

```nix
preBuild = ''
  # Create wrapper that unsets LD_LIBRARY_PATH
  mkdir -p $HOME/.risc0/toolchains/${toolchainName}/bin
  printf '%s\n' '#!/bin/sh' 'unset LD_LIBRARY_PATH' 'exec ${risc0-rust}/bin/rustc "$@"' \
    > $HOME/.risc0/toolchains/${toolchainName}/bin/rustc
  chmod +x $HOME/.risc0/toolchains/${toolchainName}/bin/rustc
'';
```

This is the cleanest solution because:
- Host build retains `LD_LIBRARY_PATH` for nixpkgs rustc
- Only the guest rustc (risc0-rust) runs without the polluted environment
- Fixes the root cause rather than working around it with `--sysroot`

## Affected Components

- `lib/buildRisc0Package.nix` - needs workaround
- Any nix build using `rustPlatform.buildRustPackage` with risc0-build

## Related Files

- `pkgs/risc0-rust/from-source.nix` - builds rustc with dual targets (host + riscv32im)
- `pkgs/risc0-rust/prebuilt.nix` - prebuilt toolchain (same issue applies)

---

## Upstream Issue for risc0-build

**Title:** Guest build fails when `LD_LIBRARY_PATH` points to a different Rust toolchain

**Labels:** bug

### Description

When `LD_LIBRARY_PATH` is set in the environment and points to a different Rust toolchain's libraries, `risc0-build` fails to compile guest code with:

```
error[E0463]: can't find crate for `core`
  = note: the `riscv32im-risc0-zkvm-elf` target may not be installed
```

### Root Cause

`cargo_command_internal` in `src/lib.rs` spawns cargo for guest compilation and correctly sets `RUSTC` to the risc0 toolchain. However, it inherits `LD_LIBRARY_PATH` from the parent environment.

When rustc runs `--print sysroot`, it uses `LD_LIBRARY_PATH` to infer its sysroot location. If `LD_LIBRARY_PATH` contains paths from a different rustc installation, the risc0 rustc returns the wrong sysroot and fails to find the `riscv32im-risc0-zkvm-elf` target libraries.

### Reproduction

```bash
# Set LD_LIBRARY_PATH to a standard rustc (simulating build systems like Nix, Bazel, etc.)
export LD_LIBRARY_PATH="/path/to/other/rustc/lib/rustlib/x86_64-unknown-linux-gnu/lib:$LD_LIBRARY_PATH"

# Run any risc0 build - guest compilation will fail
cargo build
```

### Verification

```rust
// With LD_LIBRARY_PATH pointing to another rustc:
Command::new(&risc0_rustc).arg("--print").arg("sysroot").output()
// Returns: /path/to/other/rustc  (WRONG)

// Without LD_LIBRARY_PATH:
Command::new(&risc0_rustc).env_remove("LD_LIBRARY_PATH").arg("--print").arg("sysroot").output()
// Returns: /path/to/risc0-rust  (CORRECT)
```

### Affected Environments

Any build system that sets `LD_LIBRARY_PATH` for the host toolchain:
- Nix (`rustPlatform.buildRustPackage`)
- Potentially Bazel, Buck, or other hermetic build systems
- Custom CI environments with multiple Rust installations

### Proposed Fix

Clear `LD_LIBRARY_PATH` when spawning cargo for guest builds in `cargo_command_internal`:

```rust
fn cargo_command_internal(subcmd: &str, guest_info: &GuestInfo) -> Command {
    let rustc = rust_toolchain().join("bin/rustc");

    let mut cmd = sanitized_cmd("cargo");
    cmd.env_remove("LD_LIBRARY_PATH");  // Prevent sysroot detection pollution
    // ... rest of function
}
```

This is consistent with the existing `sanitized_cmd` approach which already removes `CARGO_*` and `RUSTUP_TOOLCHAIN` environment variables to prevent interference.
