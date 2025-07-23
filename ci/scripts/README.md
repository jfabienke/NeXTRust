# NeXTRust CI/CD Scripts

*Last Updated: 2025-07-23 19:00 EEST*

This directory contains all CI/CD automation scripts for the NeXTRust project.

## 🆕 Recently Added Scripts (July 23, 2025)

### Core Build Scripts
- **`setup-xargo-m68k.sh`** - Sets up xargo for building Rust core library
- **`build-core-m68k.sh`** - Builds core library using cargo +nightly -Z build-std
- **`test-rust-mach-o-pipeline.sh`** - Comprehensive pipeline testing

### Emulator Infrastructure
- **`previous-emulator-wrapper.sh`** - Enhanced emulator wrapper with:
  - Retry logic (configurable attempts)
  - Comprehensive logging
  - Session tracking
  - Support for NeXTSTEP 3.3 and OPENSTEP 4.2
  
- **`emulator-test-harness.sh`** - Automated test framework with:
  - Test discovery from multiple sources
  - JSON test configuration support
  - Parallel execution capability
  - Detailed reporting

## Script Categories

### Build Scripts
| Script | Purpose | Status |
|--------|---------|--------|
| `build-custom-llvm.sh` | Build LLVM with M68k patches | ✅ Working |
| `build-core-m68k.sh` | Build Rust core library | ⚠️ Blocked by LLVM |
| `setup-xargo-m68k.sh` | Setup xargo build environment | ✅ Working |
| `test-rust-mach-o-pipeline.sh` | Test compilation pipeline | ✅ Working |

### Test Scripts
| Script | Purpose | Status |
|--------|---------|--------|
| `emulator-test-harness.sh` | Automated test runner | ✅ Working |
| `previous-emulator-wrapper.sh` | Emulator with retry logic | ✅ Working |
| `run-emulator-tests.sh` | Docker-based tests | ✅ Working |
| `test-m68k-compilation.sh` | M68k compilation tests | ✅ Working |

### Utility Scripts
| Script | Purpose | Status |
|--------|---------|--------|
| `slash/` | CI slash commands | ✅ Working |
| `budget-monitor.py` | AI service cost tracking | ✅ Working |
| `metrics-dashboard.py` | Pipeline metrics | ✅ Working |

## Quick Start

### 1. Build LLVM Toolchain
```bash
./build-custom-llvm.sh
```

### 2. Test Pipeline
```bash
./test-rust-mach-o-pipeline.sh
```

### 3. Run Emulator Tests
```bash
# List available tests
./emulator-test-harness.sh --list-tests

# Run all tests
./emulator-test-harness.sh

# Run with retry logic
./previous-emulator-wrapper.sh <binary> --max-retries 5
```

## Known Issues

1. **LLVM Scheduler Bug**
   - Causes SIGSEGV when compiling Rust code
   - Workaround: Build custom Rust with patched LLVM

2. **Symbol Relocation Crash**
   - M68kMachObjectWriter crashes on complex relocations
   - Impact: Some C programs fail to compile

## Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `NEXTSTEP_ROM` | ROM file path | `~/NextStep/ROM/Rev_2.5_v66.BIN` |
| `NEXTSTEP_DISK` | Disk image path | `~/NextStep/Disk/nextstep33.img` |
| `EMULATOR_TIMEOUT` | Test timeout | 120 seconds |
| `MAX_RETRIES` | Retry attempts | 3 |
| `DEBUG` | Debug logging | 0 (off) |

## Contributing

When adding new scripts:
1. Include comprehensive help/usage information
2. Use consistent logging functions
3. Add error handling and retry logic where appropriate
4. Update this README
5. Test on both macOS and Linux

## Related Documentation

- [Pipeline Status](../../docs/ci-status/pipeline-status.md)
- [CLAUDE.md](../../CLAUDE.md) - AI assistant instructions
- [Hook System](../../hooks/dispatcher.d/) - CI/CD hooks