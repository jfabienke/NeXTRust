#!/usr/bin/env bash
# M68k scheduling performance smoke test using llvm-mca
# Verifies that basic instructions have reasonable cycle counts

set -euo pipefail

echo "=== M68k Scheduling Performance Smoke Test ==="

# Navigate to LLVM directory
cd llvm-project

# Test ADD instruction (should be 1-4 cycles for basic ALU op)
echo "Testing ADD.L instruction..."
echo "add.l %d0, %d1" | build/llvm/bin/llvm-mca -march=m68k -mcpu=68040 2>&1 | tee /tmp/mca-add.out

# Extract cycle count
cycles=$(grep "Total Cycles:" /tmp/mca-add.out | awk '{print $3}')

if [[ -z "$cycles" ]]; then
  echo "❌ Failed to get cycle count for ADD instruction"
  exit 1
fi

# Verify reasonable cycle count (1-4 cycles for basic ALU)
if [[ "$cycles" -gt 4 ]]; then
  echo "❌ Unexpected cycle count for ADD: $cycles (expected 1-4)"
  exit 1
fi

echo "✅ ADD instruction: $cycles cycles (reasonable)"

# Test MUL instruction (should be 3+ cycles)
echo ""
echo "Testing MUL.L instruction..."
echo "mulu.l %d0, %d1" | build/llvm/bin/llvm-mca -march=m68k -mcpu=68040 2>&1 | tee /tmp/mca-mul.out

mul_cycles=$(grep "Total Cycles:" /tmp/mca-mul.out | awk '{print $3}')

if [[ -z "$mul_cycles" ]]; then
  echo "❌ Failed to get cycle count for MUL instruction"
  exit 1
fi

# Verify multiply takes more cycles than ADD
if [[ "$mul_cycles" -lt 3 ]]; then
  echo "❌ Unexpected cycle count for MUL: $mul_cycles (expected 3+)"
  exit 1
fi

echo "✅ MUL instruction: $mul_cycles cycles (reasonable)"

# Test LOAD instruction (should be 2+ cycles)
echo ""
echo "Testing MOVE.L (load) instruction..."
echo "move.l (%a0), %d0" | build/llvm/bin/llvm-mca -march=m68k -mcpu=68040 2>&1 | tee /tmp/mca-load.out

load_cycles=$(grep "Total Cycles:" /tmp/mca-load.out | awk '{print $3}')

if [[ -z "$load_cycles" ]]; then
  echo "❌ Failed to get cycle count for LOAD instruction"
  exit 1
fi

if [[ "$load_cycles" -lt 2 ]]; then
  echo "❌ Unexpected cycle count for LOAD: $load_cycles (expected 2+)"
  exit 1
fi

echo "✅ LOAD instruction: $load_cycles cycles (reasonable)"

echo ""
echo "✅ All performance smoke tests passed!"
echo "Scheduling model produces reasonable cycle counts"

exit 0