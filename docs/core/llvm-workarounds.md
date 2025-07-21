# LLVM M68k Backend Workarounds and Fixes

**Last Updated**: July 21, 2025, 10:30 PM EEST

This document details the workarounds and fixes applied to the LLVM M68k backend to enable Rust compilation for the NeXTSTEP target.

## 1. Scheduling Model Implementation

### Problem
The M68k backend had a minimal scheduling model with no instruction itineraries, causing rustc to crash with SIGSEGV during SelectionDAG scheduling when building with optimizations enabled.

### Solution
Implemented a basic but functional scheduling model in `M68kSchedule.td`:

```tablegen
// Define instruction itinerary classes
def IIC_ALU       : InstrItinClass;
def IIC_ALU_MEM   : InstrItinClass;
def IIC_LOAD      : InstrItinClass;
def IIC_STORE     : InstrItinClass;
def IIC_BRANCH    : InstrItinClass;
def IIC_MULTIPLY  : InstrItinClass;
def IIC_DIVIDE    : InstrItinClass;

// Define functional units
def M68kALU : FuncUnit;
def M68kFPU : FuncUnit;
def M68kMem : FuncUnit;

// Basic instruction itineraries
def M68kGenericItineraries : ProcessorItineraries<
  [M68kALU, M68kFPU, M68kMem], [], [
  InstrItinData<IIC_ALU, [InstrStage<1, [M68kALU]>]>,
  InstrItinData<IIC_LOAD, [InstrStage<4, [M68kMem]>]>,
  // ... etc
]>;
```

### Status
- `CompleteModel = 0` - We maintain an incomplete model that covers critical instructions
- This prevents crashes while allowing incremental improvement
- Full `CompleteModel = 1` would require scheduling info for all pseudo-instructions

## 2. Mach-O Object Writer

### Problem
The M68k backend initially only supported ELF output, but NeXTSTEP uses Mach-O format.

### Solution
Added `M68kMachObjectWriter` class in the LLVM patch that:
- Handles M68k-specific relocations for Mach-O
- Implements scattered relocation pairs for 32-bit differences
- Maps M68k relocations to Mach-O relocation types

### Implementation Details
See `patches/llvm/0001-m68k-mach-o-support.patch`

## 3. Custom Rustc Requirement

### Problem
The nightly rustc from rustup includes its own LLVM which lacks our M68k patches, causing crashes when building for our target.

### Solution
Created `ci/scripts/build-custom-rustc.sh` that:
1. Uses our patched LLVM as the backend
2. Adds the `m68k-next-nextstep` target specification
3. Builds a complete rustc toolchain

### Usage
```bash
./ci/scripts/build-custom-rustc.sh --stage2 --release
rustup toolchain link nextrust-m68k custom-rustc/
cargo +nextrust-m68k build --target m68k-next-nextstep
```

## 4. Atomic Operations (Planned)

### Problem
M68k processors before 68020 lack native Compare-And-Swap (CAS) instructions, and even later models have limited atomic support.

### Planned Solution
- Use library calls (`__sync_*` builtins) for pre-68020
- Lower to TAS (Test-And-Set) for simple cases
- Use CAS/CAS2 instructions on 68020+ where available
- Implement spinlock-based fallbacks in `compiler_builtins`

### Status
Not yet implemented - currently using single-threaded model.

## 5. Stack Alignment (Planned)

### Problem
M68k requires even-byte alignment for all memory accesses. Odd addresses cause bus errors.

### Planned Solution
- Force frame pointer alignment to 4-byte boundaries
- Ensure all stack allocations are rounded to even sizes
- Add alignment assertions in debug builds
- Patch LLVM's M68kFrameLowering to enforce alignment

### Status
Not yet implemented - relying on default alignment which mostly works.

## 6. Target Triple Recognition

### Problem
LLVM didn't recognize the `m68k-next-nextstep` triple.

### Solution
Added triple support in LLVM patch:
- Modified `Triple.cpp` to parse the triple correctly
- Added NeXTSTEP as a recognized OS
- Configured appropriate defaults for the platform

## 7. Code Model

### Problem
M68k has limited addressing modes for large programs.

### Solution
- Set `code-model = large` in target specification
- This ensures all addresses can be reached
- Trade-off: slightly larger code size for reliability

## 8. Relocation Model

### Problem
NeXTSTEP doesn't support modern position-independent code (PIC).

### Solution
- Use `relocation-model = static`
- Disable PLT (Procedure Linkage Table)
- Set `position_independent_executables = false`
- All code is statically linked

## Future Improvements

1. **Complete Scheduling Model**: Gradually add scheduling info for all instructions to enable `CompleteModel = 1`

2. **Optimize Cycle Counts**: Current cycle counts are estimates; should be refined based on M68040 manual

3. **FPU Scheduling**: Add proper FPU scheduling for floating-point operations

4. **Processor-Specific Models**: Create optimized models for 68030, 68040, 68060

5. **Upstream Patches**: Work towards getting patches accepted upstream

## Testing

To verify the workarounds:

```bash
# Build LLVM with patches
./ci/scripts/build-custom-llvm.sh

# Test basic compilation
echo 'int main() { return 0; }' > test.c
clang -target m68k-next-nextstep -c test.c -o test.o

# Check scheduling model
llc -mtriple=m68k-next-nextstep -debug-only=machine-scheduler test.ll
```

## References

- [LLVM M68k Backend Development](https://discourse.llvm.org/t/rfc-m68k-llvm-backend/2632)
- [M68040 User's Manual](https://www.nxp.com/docs/en/reference-manual/MC68040UM.pdf) - For accurate timing information
- [Mach-O File Format](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/MachORuntime/index.html)
- O3's guidance on scheduling models and crash resolution