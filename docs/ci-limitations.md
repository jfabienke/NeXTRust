# CI Limitations and Workarounds

**Last Updated**: July 21, 2025, 8:30 PM EEST

## Current Limitations

### 1. Rustc LLVM Crash

**Issue**: The nightly rustc from rustup includes its own LLVM which lacks our M68k scheduling patches. When building with `-Z build-std`, rustc crashes with SIGSEGV during SelectionDAG scheduling.

**Root Cause**: Missing scheduling information for M68k instructions in upstream LLVM causes crashes in `FPPassManager::runOnFunction`.

**Workaround**: We're using a simplified no_std example (`hello-simple`) that avoids compiler_builtins to demonstrate our LLVM patches work for basic code generation.

### 2. Custom Rustc Requirement

**Issue**: Full std library support requires a custom-built rustc with our patched LLVM.

**O3 Recommendation**: Pre-build a custom rustc toolchain and vendor it for CI use. This avoids rebuilding rustc on every CI run while enabling full functionality.

## Temporary Workarounds

1. **Simplified Examples**: Using minimal no_std code that avoids complex runtime dependencies
2. **Disabled Optimizations**: Using `-C opt-level=0` to avoid some scheduling paths
3. **Direct Assembly**: Using inline assembly for syscalls to minimize LLVM codegen

## Path Forward

1. **Short Term**: Continue using simplified examples to validate basic functionality
2. **Medium Term**: Build and vendor a custom rustc toolchain as O3 suggests
3. **Long Term**: Upstream our LLVM patches so standard rustc works

## Building Custom Rustc (Future Work)

When we're ready to build custom rustc:

```bash
# Clone rust with submodules
git clone https://github.com/rust-lang/rust
cd rust
git submodule update --init --recursive

# Configure to use our LLVM
./configure --llvm-root=/path/to/our/llvm

# Build
./x.py build
```

## References

- O3's guidance on vendoring custom rustc
- Our LLVM scheduling patches in `patches/llvm/`
- Upstream LLVM issue tracking (to be filed)