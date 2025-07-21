#!/usr/bin/env bash
# Test building LLVM with CompleteModel=1
# This ensures all instructions have scheduling information

set -euo pipefail

echo "=== Testing M68k CompleteModel=1 Build ==="

# Build LLVM - this will fail if any instructions lack scheduling info
./ci/scripts/build-custom-llvm.sh

if [ $? -eq 0 ]; then
  echo "✅ CompleteModel=1 build succeeded!"
  echo "All M68k instructions have scheduling information"
  
  # Run a quick smoke test
  cd src/examples
  cargo +nightly build --target=../../targets/m68k-next-nextstep.json -Z build-std=core --release
  
  if [ $? -eq 0 ]; then
    echo "✅ Release mode Rust compilation works!"
  else
    echo "❌ Release mode compilation failed"
    exit 1
  fi
else
  echo "❌ CompleteModel=1 build failed"
  echo "Some instructions still lack scheduling information"
  exit 1
fi