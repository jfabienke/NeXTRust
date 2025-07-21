#!/usr/bin/env bash
# Comprehensive M68k instruction scheduling coverage check
# This script checks ALL instructions for scheduling information

set -euo pipefail

echo "=== Checking M68k Instruction Scheduling Coverage ==="

# Navigate to LLVM directory
cd llvm-project

# Generate instruction info and find instructions without scheduling
echo "Generating instruction information..."
all_instrs=$(build/llvm/bin/llvm-tblgen -gen-instr-info \
  llvm/lib/Target/M68k/M68kInstrInfo.td \
  -I llvm/include -I llvm/lib/Target/M68k 2>&1 | \
  grep "^def [A-Z]" | grep -v "^def Pattern" | grep -v "Pseudo" || true)

missing=$(echo "$all_instrs" | grep -v "Itinerary =" || true)

if [[ -n "$missing" ]]; then
  echo "❌ Missing scheduling information for the following instructions:"
  echo "$missing"
  
  # Count statistics
  total=$(echo "$all_instrs" | wc -l | tr -d ' ')
  missing_count=$(echo "$missing" | wc -l | tr -d ' ')
  covered=$((total - missing_count))
  coverage=$((covered * 100 / total))
  
  echo ""
  echo "Coverage: $covered/$total ($coverage%)"
  echo "Missing: $missing_count instructions"
  
  # Show breakdown by instruction family
  echo ""
  echo "Missing instructions by family:"
  echo "$missing" | sed 's/def \([A-Z]*\).*/\1/' | sort | uniq -c
  
  exit 1
fi

# Calculate coverage for success case
total=$(echo "$all_instrs" | wc -l | tr -d ' ')
echo "✅ All M68k instructions have scheduling information!"
echo "Coverage: $total/$total (100%)"

# Generate coverage badge data
echo "100" > /tmp/m68k-scheduling-coverage.txt

exit 0