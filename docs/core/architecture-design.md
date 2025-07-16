# NeXTRust Architecture Design Document

*Last updated: 2025-07-15 09:50 AM*

## 1. Executive Summary

This architecture document outlines the design for creating a Rust Tier 3 cross-compilation target tailored to NeXTSTEP on Motorola 68k hardware, leveraging insights from extensive research into LLVM backend capabilities, Rust ecosystem precedents, and NeXT-specific emulation needs. The project aims to enable Rust developers to build and run applications on vintage NeXT systems, starting with no_std environments to demonstrate basic feasibility before advancing to partial std support. Key innovations include custom LLVM patches for Mach-O object emission, a dedicated target JSON specification, and an automated CI pipeline integrating the Previous emulator for authentic testing. By addressing gaps like scattered relocations and atomic implementations via spinlocks, this design positions the target as a pioneering contribution to retro computing, filling the notable absence of NeXT ports in community discussions. The overall approach emphasizes modularity for agentic development, with a projected timeline of 10-20 days to achieve a minimal viable target suitable for MCP submission to rust-lang/rust.

## 2. System Requirements

The system requires a modern host environment, preferably macOS or Linux, capable of building custom LLVM and Rust toolchains, with access to nightly Rust via rustup for features like -Z build-std. Essential dependencies include Git for cloning repositories, CMake and Ninja for LLVM compilation, and Python 3 with libraries like LangGraph for agent orchestration—as specified in requirements.txt. For NeXT-specific elements, the MCP Server provides canonical headers, SDKs, and documentation for Mach syscalls, ABI conventions, and Mach-O formats, queried via tools/mcp-query.py. Hardware emulation demands Previous or QEMU binaries, along with legally obtained NeXT ROM images (e.g., Rev 2.5 v66 for 68040) and bootable NeXTSTEP disk images, configured for SCSI ID 0 booting. The target triple m68k-next-nextstep assumes a 32-bit big-endian architecture with pointer width 32, supporting CPU models from 68030 to 68040 and optional FPU via +68882 features. No internet access is needed beyond initial setup, ensuring reproducibility in isolated environments.

## 3. LLVM Backend Modifications

Modifications to the LLVM m68k backend focus on enabling Mach-O output for NeXTSTEP compatibility, extending the ELF-centric upstream with patches for object emission and relocation handling. The core addition is a M68kMachObjectWriter class in lib/Target/M68k, adapted from existing MachObjectWriter to generate NeXT-compatible headers, segments (__TEXT, __DATA), and load commands. Relocation support introduces scattered types for 32-bit symbol differences, mapping upstream ELF fixups like R_68K_PC32 to Mach-O equivalents such as PAIR_SUBTRACT for label arithmetic, ensuring resolution at link time without assembler errors. Triple recognition patches Triple.cpp to parse m68k-next-nextstep, routing to Mach-O emitters while enabling the large code model for programs exceeding 64KB offsets—vital for NeXT's separated ROM/RAM layouts. Integration with the MC layer leverages 2025 refinements in expression resolving, allowing constant folding for Mach-O symbol ops where previously limited. Patches are stored in patches/llvm, applied via build-custom-llvm.sh, with testing through Clang compilations of simple C files to verify Mach-O validity using otool equivalents from MCP tools.

## 4. Rust Target Implementation

Rust target implementation centers on defining m68k-next-nextstep.json in targets/, specifying architecture as m68k, OS as nextstep, and vendor as next, with a data layout of "E-m:e-p:32:32-i64:64-n8:16:32" for big-endian 32-bit alignment. Features enable +68030 by default, with optional +68040 and +fpu for integrated floating-point, while panic-strategy defaults to abort for no_std simplicity. Registration occurs via PR to rust-lang/rust's compiler/rustc_target/src/spec/targets/, updating supported_targets macro and sanity.rs for stage0 awareness. Library porting begins with core and alloc crates, using -Z build-std to compile without host dependencies, then extends to std through nextstep-sys in src/crates/, wrapping Mach syscalls (e.g., vm_allocate for heaps) and BSD I/O via inline assembly traps. Atomics employ spinlocks for single-core m68k, patching library/std/src/sys/unix/ with fallbacks to avoid native CAS limitations on 68000 variants. Initial focus on no_std mitigates SIGILL crashes from core builds, enabling Hello World examples in src/examples/ that output via direct console traps, progressively incorporating std for threads and networking once ABI stabilizes.

## 5. Emulation Infrastructure

Emulation infrastructure relies on Previous for high-fidelity NeXTSTEP reproduction, configured in ci/emulation/ with rom-configs/ placeholders for Rev 2.5 v66 (68040) or Rev 1.x (68030) images, ensuring boot compatibility via ROM monitor tweaks like setting Boot: sd for SCSI priority. Disk templates in disk-templates/ provide pre-installed NeXTSTEP images attached as SCSI ID 0, with automation scripts in ci/scripts/ handling ISO mounting for binary injection or network transfers via SLiRP-emulated Ethernet. Boot parameters enforce single-user mode (-s flag) for root shell access without GUI overhead, capturing output through serial consoles routed to host logs. QEMU serves as a secondary option for headless runs, using -M next-cube with -drive for SCSI and -serial mon:stdio for command injection, though its experimental status limits it to validation checks. The harness in tests/harness/ dockerizes Previous via Dockerfile.previous-emulator, with configs/nextstep-emu-setup.json defining RAM (up to 128MB) and resolution for efficient testing of no_std binaries, verifying execution via exit codes and console echoes.

## 6. CI Pipeline and Agentic Workflow

The CI pipeline, defined in .github/workflows/, orchestrates builds and tests through build-llvm.yml for applying Mach-O patches, test-rust-target.yml for compiling with custom JSON, and emulator-harness.yml for running binaries in Previous. Scripts like run-emulator-tests.sh automate the loop: inject via mounted disks, execute in single-user mode, and parse serial outputs for pass/fail. Agentic workflow in agents/langgraph-workflow.py uses Grok 4 for orchestration, delegating to OpenAI o3 for design blueprints (e.g., relocation mappings), Gemini 2.5 Pro for reviews of patch correctness, and Claude Opus for coding tasks like spinlock implementations. Prompts in prompts/ guide specifics, such as "Adapt ELF relocs to Mach-O scattered for symbol diffs," with tools/mcp-query.py fetching NeXT headers for validation. Feedback loops trigger retries on failures, parallelizing independent paths like ABI tweaks and test suites via multiple Claude instances, ensuring convergence within the 10-20 day estimate.

## 7. Risks and Mitigations

Primary risks include LLVM patch instability leading to codegen crashes, mitigated by starting with upstream ELF templates and incremental testing via Clang on simple Mach-O outputs, cross-verified against MCP NeXT binaries. Incomplete atomics and TLS on m68k pose threading issues, addressed through spinlock fallbacks and no_std restrictions initially, with community PRs like #134329 for target features providing upstream fixes. Emulation flakiness from ROM mismatches or SCSI boot failures is countered by standardized configs and QEMU fallbacks, with scripts incorporating retries for network transfers. The absence of NeXT community support risks maintenance burdens, alleviated by designating agents as virtual maintainers and submitting MCPs early for rust-lang/rust feedback. Legal concerns around proprietary ROMs are handled via placeholders and user-supplied images, while overall timeline slips from agent hallucinations are minimized through Gemini's structured reviews and focused prompts.

## 8. Appendices

### 8.1 Sample Code Snippets

A basic no_std Hello World for m68k-next-nextstep might look like this in Rust:

```rust
#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

#[no_mangle]
pub extern "C" fn main() -> ! {
    // Inline assembly for NeXT console output via trap
    unsafe {
        asm!(
            "move.l #0x48656C6C, -(sp)",  // "Hell"
            "move.l #0x6F20576F, -(sp)",  // "o Wo"
            "move.l #0x726C640A, -(sp)",  // "rld\n"
            "move.w #12, -(sp)",          // Length
            "trap #0",                    // Syscall for write
            "add.l #14, sp"               // Clean stack
        );
    }
    loop {}
}
```

This demonstrates direct syscall usage, compilable with `cargo build --target=m68k-next-nextstep.json -Z build-std=core`.

For atomics spinlock patch excerpt:

```rust
// In libstd-sys-nextstep.diff
impl AtomicBool {
    fn store(&self, val: bool, order: Ordering) {
        unsafe {
            loop {
                let old = asm!("move.b (a0), d0" : "=d"(old) : "a"(self.ptr) : "d0" : "volatile");
                if old == val as u8 { break; }
                asm!("move.b d1, (a0)" : : "d"(val as u8), "a"(self.ptr) : "memory" : "volatile");
            }
        }
    }
}
```

### 8.2 Glossary of NeXT-Specific Terms

**Mach-O**: NeXT's object format for executables, featuring segments like __TEXT and scattered relocations for 32-bit symbol handling.

**ROM Monitor**: NeXT's boot firmware interface, accessed via Cmd-Cmd-~, for setting boot devices like sd for SCSI.

**SCSI ID 0**: Primary boot disk slot in NeXT hardware, emulated for system images.

**Single-User Mode**: Boot flag (-s) providing root shell without multi-user services, ideal for automated testing.

**Trap #0**: Instruction for invoking Mach/BSD syscalls in NeXTSTEP, used in no_std for I/O and memory ops.

**Spinlock**: Software atomic fallback for m68k's lack of native CAS, implementing mutual exclusion via busy-wait loops.