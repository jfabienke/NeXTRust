# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NeXTRust is a Rust cross-compilation project targeting the historic NeXTSTEP operating system on m68k architecture. The project enables Rust development for the NeXT platform through custom LLVM toolchain modifications and Mach-O format support.

## Key Commands

### Development Environment Setup
```bash
# Install Rust nightly for -Z build-std support
rustup toolchain install nightly

# Set up Python dependencies (LangGraph, etc.)
pip install -r requirements.txt

# Initialize git submodules for LLVM/Rust forks
git submodule init && git submodule update
```

### Building the Custom LLVM Toolchain
```bash
# Apply Mach-O patches and build custom LLVM
./ci/scripts/build-custom-llvm.sh

# Test LLVM with simple C program
clang -target m68k-next-nextstep -c test.c -o test.o
```

### Rust Target Compilation
```bash
# Build no_std binary with custom target
cargo +nightly build --target=targets/m68k-next-nextstep.json -Z build-std=core,alloc

# Build specific example
cargo +nightly build --target=targets/m68k-next-nextstep.json -Z build-std=core --example hello-world
```

### Running Tests
```bash
# Run emulator-based tests
./ci/scripts/run-emulator-tests.sh

# Run no-std tests
cargo test --manifest-path tests/suites/no-std-tests.rs

# Run standard library integration tests
cargo test --manifest-path tests/suites/std-integration-tests.rs
```

### Agent Workflow
```bash
# Run the agent feedback loop
./ci/scripts/agent-feedback-loop.sh

# Execute LangGraph workflow
python agents/langgraph-workflow.py

# Query NeXT headers via MCP
python agents/tools/mcp-query.py

# Run CI pipeline
./.github/workflows/build-llvm.yml
./.github/workflows/test-rust-target.yml
./.github/workflows/emulator-harness.yml
```

## Architecture Overview

### Project Structure
- **src/crates/nextstep-sys**: System bindings for NeXTSTEP APIs
- **src/examples**: Example Rust programs targeting NeXTSTEP
- **patches/**: LLVM and Rust patches for NeXTSTEP support
  - LLVM patches: Mach-O support, triple recognition
  - Rust patches: Atomics/spinlocks, libstd sys support
- **targets/**: Custom Rust target specification (m68k-next-nextstep.json)
- **tests/**: Emulation-based test infrastructure
- **agents/**: AI-driven development workflow automation

### Key Technical Components

1. **Custom LLVM Build**: Modified LLVM with NeXTSTEP Mach-O support
   - M68kMachObjectWriter for object emission
   - Scattered relocations for 32-bit symbol differences
   - Large code model for segmented memory layouts
2. **Rust Target Specification**: Custom m68k-next-nextstep target
   - Big-endian 32-bit architecture (E-m:e-p:32:32-i64:64-n8:16:32)
   - CPU support: 68030/68040 with optional FPU
   - Spinlock-based atomics (no native CAS on m68k)
3. **Emulation Testing**: Previous and QEMU for testing
   - Previous for high-fidelity NeXTSTEP emulation
   - Single-user mode boot for automated testing
   - SCSI disk injection for binary transfer
4. **Agent System**: Multi-model AI workflow
   - Grok 4 for orchestration
   - OpenAI o3 for design blueprints
   - Gemini 2.5 Pro for code reviews
   - Claude Opus for implementation tasks

### Development Workflow

1. **Toolchain Setup**: Build custom LLVM first (required for cross-compilation)
2. **Target Configuration**: Ensure m68k-next-nextstep.json is properly configured
3. **System Bindings**: Develop nextstep-sys crate for OS API access
4. **Testing**: Use emulation infrastructure for validation
5. **Agent Assistance**: Leverage AI agents for complex porting tasks

### Important Notes

- All source files are currently empty/placeholder - project is in initial setup phase
- Requires custom toolchain build before any Rust compilation
- Testing relies entirely on emulation due to hardware constraints
- Agent system can help with library porting and API translation tasks
- Target triple: m68k-next-nextstep
- ROM images required: Rev 2.5 v66 (68040) or Rev 1.x (68030)
- Estimated timeline: 10-20 days for minimal viable target

## Working with the Codebase

When implementing features:
1. Start with no_std support first (simpler, fewer dependencies)
2. Use nextstep-sys for all OS interactions via trap #0 syscalls
3. Test thoroughly in emulator before considering hardware
4. Document any NeXTSTEP-specific workarounds or limitations
5. Use the agent system for complex cross-platform API mappings

### Implementation Phases (from docs/project-plan.md)
- **Phase 1**: System setup and MCP configuration (Days 1-2)
- **Phase 2**: LLVM backend Mach-O modifications (Days 3-7)
- **Phase 3**: Rust target specification and no_std (Days 8-10)
- **Phase 4**: Emulation infrastructure setup (Days 11-13)
- **Phase 5**: CI pipeline integration (Days 14-17)
- **Phase 6**: Final review and MCP submission (Days 18-20)

### Key Resources
- **Architecture Design**: docs/architecture-design.md
- **Implementation Plan**: docs/project-plan.md
- **LLVM Enhancements**: docs/llvm-enhancements.md
- **Library Porting Guide**: docs/library-porting.md

Last updated: 2025-07-15 10:00 AM