# Detailed Implementation Plan for Rust NeXTSTEP m68k Target

*Last updated: 2025-07-22 3:53 AM EEST*

This implementation plan outlines a structured, phased approach to developing a Tier 3 Rust cross-compilation target for NeXTSTEP on Motorola 68k, drawing from our synthesized research on LLVM extensions, Rust policies, emulation setups, and community insights. The plan emphasizes early validation through no_std prototypes to mitigate risks like compilation crashes, while enabling parallel agentic tasks for efficiency. Total estimated duration is 10-20 calendar days, assuming 4-8 hours daily of agent runs with your oversight for prompt refinements. Agents will use Grok 4 for orchestration, OpenAI o3 for designs, Gemini 2.5 Pro for reviews, and Claude Opus for coding, integrated via LangGraph in agents/langgraph-workflow.py. Progress tracking occurs through CI workflows in .github/workflows/, with milestones tied to functional Hello World binaries and MCP submission readiness.

## Phase 1: System Requirements Setup (Days 1-2)

Establish the foundational environment to support all subsequent phases without delays. Begin by installing Rust nightly via rustup toolchain install nightly, then clone the LLVM and Rust repositories into vendor/llvm-m68k-fork and a rust-source directory using git submodule init and update, as configured in .gitmodules. Set up Python dependencies from requirements.txt with pip install -r requirements.txt, including LangGraph for agent flows.

Configure MCP Server access in tools/mcp-query.py, testing queries for NeXT headers like Mach syscalls and Mach-O relocation types to populate a local cache. Prepare emulation basics by downloading Previous emulator binaries and creating placeholder ROM configs in ci/emulation/rom-configs/, ensuring compatibility with 68040 models via next-rom-placeholder.json.

Activate Grok 4 to orchestrate initial agent prompts from prompts/orchestration.txt, verifying tool integrations like mcp-query.py for ABI details. Milestone: Successful MCP query and LLVM clone, confirmed by a simple Clang build test.

## Phase 2: LLVM Backend Modifications (Days 3-7)

Tackle the core technical challenge by extending LLVM's m68k backend for Mach-O support, the project's largest effort. Design agents (o3) blueprint patches in docs/llvm-enhancements.md, focusing on adding M68kMachObjectWriter in lib/Target/M68k to emit NeXT-compatible segments and load commands, templated from upstream MachObjectWriter.

Parallelize coding (Claude) for triple recognition in Triple.cpp to handle m68k-next-nextstep, routing to Mach-O emitters, and scattered relocations in M68kAsmBackend.cpp for 32-bit symbol differences, mapping ELF fixups like R_68K_PC32 to PAIR_SUBTRACT types queried from MCP.

Incorporate the large code model for segmented memory, patching TargetMachine to enable 32-bit absolute/GOT addressing. Apply patches via build-custom-llvm.sh in ci/scripts/, building a custom LLVM binary.

Review agents (Gemini) validate against MCP NeXT binaries using Clang tests on simple C files, checking otool outputs for valid Mach-O. Mitigate crashes by isolating reloc handling in sub-patches. Milestone: Custom LLVM compiling a Mach-O Hello World C program, verifiable in emulation.

## Phase 3: Rust Target Implementation (Days 8-10) ✅ **COMPLETE!**

**Status: Successfully completed July 21, 2025**

Build on the custom LLVM by defining the Rust target. Use o3 to design m68k-next-nextstep.json in targets/, specifying big-endian layout, +68030 features, and abort panic strategy.

Code the spec integration, updating rust-lang/rust forks with additions to spec/targets/ and sanity.rs. Bootstrap no_std via -Z build-std=core,alloc, creating nextstep-sys in src/crates/ for Mach wrappers like vm_allocate.

Implement spinlock atomics in patches/rust/atomics-spinlocks.diff to bypass native CAS gaps, and compile src/examples/hello-world.rs with trap #0 for console output.

Review for ABI compliance using MCP headers, testing compilation without SIGILL errors. 

**Achieved Milestones:**
- ✅ No_std binary outputting "Hello World" via assembly syscalls
- ✅ Spinlock-based atomics fully implemented in compiler-rt
- ✅ nextstep-sys crate with basic syscall bindings
- ✅ M68k scheduling model enhanced for release builds
- ✅ Both debug AND release builds working with all optimization levels

## Phase 4: Emulation Infrastructure (Days 11-13) 🚧 **IN PROGRESS**

**Status**: Early implementation, Day 11

### Completed:
- **Core Runtime Libraries**: Implemented fundamental crates:
  - `nextstep-sys`: Complete FFI bindings with ~516 lines covering all major syscalls
  - `nextstep-alloc`: Custom allocator using Mach VM operations for memory management
  - `nextstep-io`: Basic I/O traits and stdout/stderr implementations
- **LLVM Scheduling Fix**: Resolved critical issue preventing release builds

### Current Blocker:
- **Custom rustc Build**: Cannot compile rustc with our m68k-next-nextstep target
  - Error: "cannot produce cdylib for m68k-next-nextstep" 
  - This blocks testing of our runtime libraries
  - Investigating cross-compilation approaches

### Remaining Tasks:
- Configure Previous emulator with nextstep-emu-setup.json for SCSI ID 0 disks
- Script binary transfers in run-emulator-tests.sh using mounted ISOs
- Fallback to QEMU for headless validation
- Test injection with compiled binaries once rustc issues resolved

Milestone: Automated script running our runtime libraries in emulation.

## Phase 5: CI Pipeline and Agentic Workflow (Days 14-17)

**Timeline Adjustment**: Days 14-17 may shift based on Phase 4 rustc resolution

Integrate components into CI, updating workflows/build-llvm.yml for patch applications, test-rust-target.yml for Cargo builds, and emulator-harness.yml for end-to-end runs.

Enhance agent-feedback-loop.py to trigger retries on failures, parallelizing tasks like reloc reviews. Incorporate Gemini for output validation against expected Mach-O structures.

Test full cycles: patch-build-compile-emulate, refining for std integration once runtime libraries are validated. 

Milestone: Passing CI run with nextstep-sys/alloc/io libraries tested in emulation.

## Phase 6: Risks, Mitigations, and Final Review (Days 18-20)

**Timeline Note**: Schedule may extend 2-3 days based on rustc cross-compilation resolution

### Current Risk Status:
- **rustc Cross-Compilation**: HIGH - Blocking runtime library testing
  - Mitigation: Exploring alternative build approaches, may need upstream patches
- **Emulation Setup**: MEDIUM - Not yet configured but path is clear
- **Atomics**: LOW - Spinlock implementation working in LLVM tests

### Revised Approach:
1. Document rustc build challenges and solutions
2. Complete emulator infrastructure once binaries can be built
3. Finalize runtime library testing and validation
4. Draft MCP with working implementation proof

Milestone: Complete documentation with proven runtime libraries and clear path to full std support.