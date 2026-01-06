#!/usr/bin/env bash
set -euo pipefail

# Create a temporary workspace and test the template
mkdir -p risc0-workspace
cd risc0-workspace

# Initialize from template
nix flake init -t ..#default

# Git is required for flake to work with local files
git init
git add -A

# Override risc0pkgs input to use current branch/commit
nix flake lock --override-input risc0pkgs "github:malda-protocol/risc0pkgs/${GITHUB_REF:-master}"

# Build the template
nix build --accept-flake-config -L --no-link .#default
