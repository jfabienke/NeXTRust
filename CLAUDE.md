# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NeXTRust is a Rust cross-compilation project targeting the historic NeXTSTEP operating system on m68k architecture. The project enables Rust development for the NeXT platform through custom LLVM toolchain modifications and Mach-O format support.

<!-- PEER REVIEW: Inserted 'Assistant persona' section for tighter grounding as per latest Claude Code best practices. -->
### Assistant persona
You are Claude Code (Opus) acting as a senior Rust+LLVM build engineer. Your primary responsibilities are code implementation, scripting, and ensuring builds conform to the project's unique cross-compilation requirements.

## Environment Configuration

### Working Directory Management
Set this environment variable to ensure Claude Code always executes commands from the project root:
```bash
export CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1
```
This prevents accidental directory changes and eliminates the need for manual `cd` commands in scripts.

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

# <!-- PEER REVIEW: Added link to slash command help to make Claude aware of human-facing tools. -->
# List available CI slash commands
./ci/scripts/slash/ci-help.sh
```

## CI/CD Pipeline Architecture (v2.2)

### **CRITICAL: Understanding the Hook System**
NeXTRust uses Claude Code's native hook system with a sophisticated v2.2 dispatcher architecture. **Every bash command you run will trigger hooks automatically** - this is how the CI pipeline works.

#### **Hook Flow Overview**
```
You run: ./ci/scripts/build-custom-llvm.sh
    ↓
1. PreToolUse Hook → hooks/dispatcher.sh pre
   - Validates phase alignment
   - Checks environment
   - Logs command start
    ↓
2. Command Executes → build-custom-llvm.sh runs
    ↓
3. PostToolUse Hook → hooks/dispatcher.sh post
   - Analyzes failures if exit_code != 0
   - Updates pipeline status
   - Triggers AI escalation if needed
    ↓
4. Stop Hook → hooks/dispatcher.sh stop (session end)
   - Captures token usage via ccusage
   - Triggers code reviews
   - Updates metrics
```

#### **Key Hook Configuration** (`.claude/settings.json`)
```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "command": "./hooks/dispatcher.sh pre",
      "timeout": 90
    }],
    "PostToolUse": [{
      "matcher": "Bash", 
      "command": "./hooks/dispatcher.sh post",
      "timeout": 300
    }],
    "Stop": [{
      "command": "./hooks/dispatcher.sh stop",
      "timeout": 60
    }],
    "UserPromptSubmit": [{
      "command": "./hooks/dispatcher.sh user-prompt-submit",
      "timeout": 30
    }]
  }
}
```

### **Modular Dispatcher Architecture**
The v2.2 dispatcher (`hooks/dispatcher.sh`) routes to specialized modules:

```
hooks/
├── dispatcher.sh              # ← Main entry point (v2.2 unified)
└── dispatcher.d/
    ├── common/
    │   ├── setup.sh              # Environment initialization
    │   ├── cleanup.sh            # Post-execution cleanup
    │   ├── failure-analysis.sh   # Pattern recognition
    │   ├── failure-tracking.sh   # Persistent failure management
    │   ├── idempotency.sh        # Duplicate operation prevention
    │   └── metrics.sh            # Token usage tracking
    ├── pre-tool-use/
    │   ├── validate-cwd.sh       # Working directory validation
    │   ├── validate-file-creation.sh # File operation safety
    │   ├── validate-git-commit.sh # Git operation validation
    │   ├── validate-llvm.sh      # LLVM build environment
    │   └── check-phase-alignment.sh # Phase progression validation
    ├── post-tool-use/
    │   ├── analyze-failure.sh    # Intelligent failure analysis
    │   ├── capture-error-snapshot.sh # Error state preservation
    │   ├── update-status.sh      # Status artifact management
    │   └── generate-success-artifacts.sh # Success handling
    ├── stop/
    │   ├── capture-usage.sh      # Token usage via ccusage
    │   └── trigger-review.sh     # AI service orchestration
    ├── user-prompt-submit/
    │   ├── audit-prompt.sh       # Prompt tracking
    │   ├── phase-banner.sh       # Current phase display
    │   └── security-guard.sh     # Command safety validation
    └── tool-output/
        └── summarize-build-logs.sh # Log analysis
```

### **Pipeline Status Tracking**
The pipeline maintains dual-format status artifacts:

- **Machine-readable**: `docs/ci-status/pipeline-log.json`
- **Human-readable**: `docs/ci-status/pipeline-log.md` 
- **Failure tracking**: `.claude/failure-tracking/failures.json`
- **Session files**: `.claude/sessions/` (idempotency)
- **Hook logs**: `.claude/hook-logs/` (debugging)

### **Project Structure**
- **src/crates/nextstep-sys**: System bindings for NeXTSTEP APIs
- **src/examples**: Example Rust programs targeting NeXTSTEP
- **patches/**: LLVM and Rust patches for NeXTSTEP support
  - LLVM patches: Mach-O support, triple recognition
  - Rust patches: Atomics/spinlocks, libstd sys support
- **targets/**: Custom Rust target specification (m68k-next-nextstep.json)
- **tests/**: Emulation-based test infrastructure
- **agents/**: AI-driven development workflow automation
- **hooks/**: v2.2 CI/CD hook system (dispatcher + modules)
- **ci/scripts/**: Build scripts that work with the hook system

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
   - Gemini 2.5 Pro for code reviews (see `GEMINI.md` for guidelines)
   - Claude Opus for implementation tasks
<!-- PEER REVIEW: Added `ccusage` reminder to integrate cost-tracking into the agent's workflow. -->
   - After completing a session, call `ccusage --session-id ...` and log output via `status-append.py`.

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
<!-- PEER REVIEW: Added token boundary hint as a guard-rail for large context windows. -->
- If an included diff or file exceeds 150k tokens, summarise unchanged code blocks first to conserve context.

## File Management Guidelines

### CRITICAL: File Creation Rules

1. **ALWAYS prefer editing existing files over creating new ones**
   - Search for existing files that serve similar purposes
   - Check if functionality can be added to existing modules
   - Only create new files when they provide clear architectural value

2. **NEVER create files in the root directory** unless explicitly requested:
   - Configuration files (.gitignore, requirements.txt) - only if missing
   - README.md - already exists, always edit instead
   - New scripts belong in appropriate subdirectories

3. **Before creating any new file, verify**:
   - No existing file serves this purpose
   - The file location follows project structure conventions
   - The file is necessary for the requested functionality

4. **Documentation files**:
   - NEVER create new .md files unless explicitly requested
   - Always check docs/ subdirectories for existing documentation to update
   - Prefer updating existing docs over creating new ones

5. **Temporary files**:
   - Use /tmp or designated temp directories
   - Never leave test files in the project root
   - Clean up any temporary files created during testing

### Project Structure for New Files
When new files ARE necessary, follow this structure:
- Scripts: `ci/scripts/` or `ci/scripts/tools/`
- Hooks: `hooks/dispatcher.d/<phase>/`
- Documentation: `docs/<category>/`
- Configuration: Project root ONLY if standard (e.g., .gitignore)
- Tests: `tests/` or alongside the code being tested

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

<!-- PEER REVIEW: Added freshness lint comment to enable automated staleness checks in CI. -->
Last updated: 2025-07-20 8:30 AM <!-- AUTO-UPDATE-HORIZON:90d --> <!-- v2.2 consolidated -->
