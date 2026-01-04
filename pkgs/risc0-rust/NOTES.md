# risc0-rust Build Notes

## How rzup Builds the Toolchain

Reference: https://github.com/risc0/risc0/blob/v3.0.4/rzup/src/build.rs

### Build Stages

rzup executes three sequential build stages:

```rust
for stage in [None, Some(2), Some(3)] {
    // ./x build
    // ./x build --stage 2
    // ./x build --stage 3
}
```

1. **Initial `./x build`** - Bootstrap build
2. **`./x build --stage 2`** - Builds full compiler with **HOST libs**
3. **`./x build --stage 3`** - Builds libs for **riscv target**

### The Merge Trick

After building, rzup merges the stages:

```rust
// Take stage2 as base (has host compiler + host libs)
std::fs::rename(stage2, &dest_dir)?;

// Copy ONLY riscv libs from stage3 into the stage2 directory
let riscv_libs = "lib/rustlib/riscv32im-risc0-zkvm-elf";
std::fs::rename(stage3.join(riscv_libs), dest_dir.join(riscv_libs))?;

// Copy tools from stage2-tools-bin
for tool in std::fs::read_dir(stage2_tools)? {
    std::fs::rename(tool.path(), dest_dir.join("bin").join(tool.file_name()))?;
}
```

### Key Insight

The `config.toml` specifies only:
```toml
target = ["riscv32im-risc0-zkvm-elf"]
```

But this doesn't mean "only build riscv". The **host is always built implicitly**
because you need a working compiler. The target list means "additional targets
beyond host".

- **Stage 2**: Always builds host libs (implicit default)
- **Stage 3**: Builds the explicit target (riscv)
- **Final**: Merge stage2 base + riscv libs from stage3

## Our Approach (from-source.nix)

Instead of separate stages + merge, we use Rust's multi-target build:

```nix
"--target=${hostTarget},riscv32im-risc0-zkvm-elf"
```

This builds both targets in one pass. The Rust build system handles multiple
targets correctly - it builds libs for each specified target.

NOTE: Previously we were building riscv libs only, with dynamic wrapper swiching between native rustc and risc0 one. Toolchain was faster to (re)build - it was taking 22 instead of 28 minutes - but the environment was much more complex. You can see the old code at 03cc060f84e374b517f7772cbf11908db766716c commit.

Both approaches result in the same outcome: a toolchain with host libs
(for build scripts, proc-macros) and riscv libs (for guest code).
