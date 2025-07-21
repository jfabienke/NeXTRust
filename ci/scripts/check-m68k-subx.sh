#!/usr/bin/env bash
# Check M68k SUBX instruction scheduling coverage
# Part of the parallel CI coverage checks for M68k scheduling model

set -euo pipefail

echo "=== Checking M68k SUBX Instruction Scheduling Coverage ==="

# Navigate to LLVM directory
cd llvm-project

# Generate instruction info and check for SUBX variants without scheduling
missing=$(build/llvm/bin/llvm-tblgen -gen-instr-info \
  llvm/lib/Target/M68k/M68kInstrInfo.td \
  -I llvm/include -I llvm/lib/Target/M68k 2>&1 | \
  grep -E "^def SUBX[0-9]+dd" | \
  grep -v "Itinerary =" || true)

if [[ -n "$missing" ]]; then
  echo "❌ Missing scheduling info for SUBX instructions:"
  echo "$missing"
  
  # Count missing instructions
  count=$(echo "$missing" | wc -l | tr -d ' ')
  echo ""
  echo "Total missing: $count SUBX instructions"
  exit 1
fi

echo "✅ All SUBX instructions have scheduling information"
exit 0