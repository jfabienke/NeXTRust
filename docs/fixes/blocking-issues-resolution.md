# Blocking Issues Resolution

*Last Updated: 2025-07-23 20:15 EEST*

## Summary

This document tracks the resolution of two critical blocking issues that prevent Rust compilation for the m68k-next-nextstep target.

## Issue 1: LLVM Scheduler SIGSEGV ❌ (In Progress)

### Symptoms
- rustc crashes with SIGSEGV when compiling Rust code
- Error occurs in ScheduleDAGRRList::ListScheduleBottomUp
- Affects both xargo and cargo +nightly -Z build-std approaches

### Root Cause
- M68k backend has incomplete scheduling information for pseudo-instructions
- Atomic operations lack proper scheduling definitions
- CompleteModel = 1 exposes missing itineraries

### Attempted Fixes
1. **Quick Fix**: Set NoModel = 1 in M68kSchedule.td
   - Status: ❌ Failed - still crashes
   - The scheduler is still invoked despite NoModel setting

2. **Temporary Workaround**: Set CompleteModel = 0
   - Status: ❌ Failed - doesn't prevent scheduler invocation
   - Need deeper fix in LLVM or custom Rust build

3. **Disable Machine Scheduler**: Override in M68kTargetMachine.cpp
   - Added `disablePass(&MachineSchedulerID)` in M68kPassConfig
   - Status: ❌ Failed - crash happens in SelectionDAG scheduler, not machine scheduler
   - The crash is in ScheduleDAGRRList which is part of instruction selection

### Root Cause Analysis
- The crash occurs in ScheduleDAGRRList::ListScheduleBottomUp
- This is the SelectionDAG scheduler, not the machine scheduler
- It runs during instruction selection phase, before machine scheduling
- The issue is likely with atomic operations or pseudo-instructions lacking proper scheduling dependencies

### Next Steps
- Build custom Rust with our patched LLVM
- Add proper scheduling dependencies for atomic operations
- Investigate disabling SelectionDAG scheduling (more invasive)
- Consider patching ScheduleDAGRRList directly to handle missing info

## Issue 2: M68k Mach-O Writer Crash ✅ (FIXED)

### Symptoms
- LLVM crashes when generating complex Mach-O files
- Error occurs at M68kMachObjectWriter.cpp:125
- Crash when calling getSymbolAddress on undefined symbols

### Root Cause
- getSymbolAddress() was called on undefined/external symbols
- These symbols don't have addresses, only symbol indices
- Missing check for symbol type before address lookup

### Fix Applied
```cpp
// Check if symbol has a valid address before calling getSymbolAddress
if (A->isUndefined() || (A->isExternal() && !A->isDefined())) {
  // For external/undefined symbols, use symbol index instead
  uint32_t SymbolNum = A->getIndex();
  MRE.r_word1 = (SymbolNum << 8) |
                (IsPCRel << 7) |
                (Log2Size << 5) |
                (true << 4) | // External = true for undefined symbols
                (Type << 0);
} else {
  // For defined symbols, use address
  MRE.r_word1 = (Writer->getSymbolAddress(*A, Layout) << 8) |
                (IsPCRel << 7) |
                (Log2Size << 5) |
                (false << 4) | // External = false for defined symbols
                (Type << 0);
}
```

### Verification
- ✅ LLVM rebuilt successfully with fix
- ✅ test-rust-mach-o-pipeline.sh now passes all Mach-O generation tests
- ✅ Relocations are properly generated
- ✅ C code compiles to M68k Mach-O without crashes

## Current Status

| Issue | Status | Impact |
|-------|--------|--------|
| LLVM Scheduler SIGSEGV | ❌ Blocked | Cannot compile Rust code |
| M68k Mach-O Writer crash | ✅ Fixed | Can generate M68k Mach-O files |

## Final Resolution Strategy

After extensive investigation, the recommended approach is:

1. **Build Custom Rust Compiler** (Immediate)
   ```bash
   ./ci/scripts/build-custom-rustc.sh --stage2 --release
   ```
   - This will use our patched LLVM with the Mach-O writer fix
   - May bypass the scheduler issue by using a different code path
   - Provides full control over the compilation pipeline

2. **Alternative Approaches** (If custom build fails)
   - Patch ScheduleDAGRRList to handle missing scheduling info gracefully
   - Add scheduling dependencies for all atomic pseudo-instructions
   - Use Rust 1.77 which may have different LLVM integration

## Lessons Learned

1. **Scheduler Architecture**: LLVM has multiple schedulers:
   - SelectionDAG scheduler (where crash occurs)
   - Machine scheduler (post-ISel)
   - Post-RA scheduler
   
2. **M68k Atomics**: The target specification shows:
   - `atomic-cas: false` - No native compare-and-swap
   - Requires software emulation via spinlocks
   - These pseudo-instructions need proper scheduling info

3. **Debugging Strategy**: 
   - NoModel/CompleteModel only affect instruction descriptions
   - Pass disabling requires understanding the full pipeline
   - Custom toolchain builds provide the most control

## Files Modified

1. `/Users/johnfabienke/Development/NeXTRust/llvm-project/llvm/lib/Target/M68k/M68kSchedule.td`
   - Set NoModel = 1 (didn't help)
   - Set CompleteModel = 0 (temporary)

2. `/Users/johnfabienke/Development/NeXTRust/llvm-project/llvm/lib/Target/M68k/MCTargetDesc/M68kMachObjectWriter.cpp`
   - Added symbol type check before getSymbolAddress
   - Fixed external symbol handling

## Test Results

```bash
# Pipeline test results after Mach-O fix:
✅ LLVM IR → M68k Mach-O compilation: Working
✅ M68k assembly generation: Working
✅ C → M68k Mach-O compilation: Working
✅ Custom target specification: Available
✅ Symbol relocations: Working
⚠️  Linking: Needs investigation (expected - no linker script)
```