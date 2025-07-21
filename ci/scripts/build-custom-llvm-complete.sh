#!/usr/bin/env bash
# Build custom LLVM with CompleteModel=1 for final validation
# This is a variant of build-custom-llvm.sh that enables complete scheduling model

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Building Custom LLVM with CompleteModel=1 ==="

# First, temporarily set CompleteModel = 1 in M68kSchedule.td
cd "$PROJECT_ROOT/llvm-project"

# Backup original file
cp llvm/lib/Target/M68k/M68kSchedule.td llvm/lib/Target/M68k/M68kSchedule.td.backup

# Set CompleteModel = 1
sed -i.bak 's/let CompleteModel = 0;/let CompleteModel = 1;/' \
  llvm/lib/Target/M68k/M68kSchedule.td

# Build LLVM
echo "Building LLVM with complete scheduling model..."
"$SCRIPT_DIR/build-custom-llvm.sh"

# Restore original file
mv llvm/lib/Target/M68k/M68kSchedule.td.backup llvm/lib/Target/M68k/M68kSchedule.td

echo "✅ LLVM built successfully with CompleteModel=1"