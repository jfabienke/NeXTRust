# CHANGELOG

All notable changes to the NeXTRust project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.3] - 2025-07-21

### Added
- M68k scheduling model enhancements for release build support
- Scheduling information for critical instructions (SUB, SUBX, TRAP, UMUL, UNLK, XOR)
- Parallel CI coverage check scripts for instruction families
- Performance validation script using llvm-mca
- Comprehensive scheduling documentation and completion report

### Fixed
- Release mode compilation crashes due to missing scheduling information
- SelectionDAG issues when optimizations enabled
- Rust compilation with -O1, -O2, -O3 optimization levels

### Changed
- Enhanced M68k LLVM backend with production-ready scheduling
- Updated CLAUDE.md and README.md to reflect Phase 3 completion
- Improved CI scripts for parallel testing of instruction coverage

### Technical Details
- Added InstrItinClass parameters to TableGen instruction definitions
- Implemented IIC_ALU, IIC_ALU_MEM, IIC_BRANCH scheduling classes
- ~100 pseudo instructions remain unscheduled (not needed for Rust)
- CompleteModel remains 0 (full coverage not required for production)

## [2.2] - 2025-07-20

### Added
- AI-powered CI/CD pipeline with automated code reviews
- OpenAI O3 integration for complex design decisions
- Gemini integration for PR reviews and code feedback
- Budget monitoring and enforcement system
- Slash commands for manual AI assistance triggers
- Comprehensive metrics emission (JSONL format)
- Token usage tracking with ccusage integration
- Phase completion hooks for automated workflows
- Local test environment configuration support
- Developer setup template (local.env.template)

### Fixed
- Created missing `ci/scripts/check-ccusage.sh` script
- Fixed test harness to properly use test credentials
- Corrected dispatcher filename references (dispatcher.sh vs dispatcher-v2.sh)
- Added proper error handling for missing dependencies

### Changed
- Updated CI/CD architecture to v2.2 with full AI activation
- Enhanced hook system with modular dispatcher architecture
- Improved test coverage from 0 to 23 passing tests

### Verified
- Full local test suite: 23/23 tests passing
- O3 integration tested in mock mode
- ccusage integration tested with mock binary
- All critical paths verified with comprehensive logging
- Test artifacts generated in docs/ci-status/

## [2.1] - 2025-07-18

### Added
- Unified modular dispatcher architecture
- Comprehensive hook system for CI/CD pipeline
- Failure analysis and tracking system
- Idempotency controls for duplicate operations
- Pipeline phase management

### Changed
- Consolidated CI/CD infrastructure to v2.1 unified architecture
- Improved error handling and resilience

## [2.0] - 2025-07-15

### Added
- Initial CI/CD pipeline framework
- Basic hook system
- Status tracking and reporting

## [1.0] - 2025-07-01

### Added
- Initial NeXTRust project setup
- M68k target specification for Rust
- Custom LLVM patches for NeXTSTEP Mach-O support
- Basic build infrastructure