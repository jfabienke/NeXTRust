#!/usr/bin/env bash
# ci/scripts/agent-ci-task.sh - Generate task for Claude Code in CI
#
# Purpose: Create specific build task based on CI matrix
# Usage: ./ci/scripts/agent-ci-task.sh
#
set -uo pipefail

# Get matrix variables
CPU_VARIANT="${CPU_VARIANT:-m68030}"
RUST_PROFILE="${RUST_PROFILE:-debug}"
OS_NAME="${OS_NAME:-ubuntu-latest}"

# Generate task based on current CI state
echo "Build LLVM and Rust for NeXTSTEP with the following configuration:
- CPU variant: $CPU_VARIANT
- Rust profile: $RUST_PROFILE  
- Operating system: $OS_NAME

Steps to complete:
1. Run ci/scripts/build-custom-llvm.sh --cpu-variant $CPU_VARIANT to build LLVM with M68k Mach-O support
2. If LLVM build succeeds, run ci/scripts/build-rust-target.sh --target m68k-next-nextstep --profile $RUST_PROFILE --features $CPU_VARIANT
3. Handle any build failures by analyzing the error and attempting fixes
4. Ensure all artifacts are created in the expected locations

The hooks system will track your progress and handle failures automatically."