# Target OS Versions for NeXTRust

**Last Updated**: July 22, 2025, 4:15 AM EEST

## Recommended Target Versions

Based on stability, m68k support, and emulator compatibility, the following OS versions are recommended for NeXTRust development:

### Primary Target: NeXTSTEP 3.3 (February 1995)
- **Why**: Last major version under the NeXTSTEP name
- **Architecture Support**: Fat binaries for m68k, i386, SPARC, and PA-RISC
- **Hardware**: Most popular for NeXTcube and NeXTstation systems
- **Emulation**: Excellent support in Previous emulator
- **Use Case**: Initial no_std and minimal std prototypes

### Secondary Target: OPENSTEP 4.2 (January 1997)
- **Why**: Final NeXT OS release before Apple acquisition
- **Architecture Support**: m68k, x86, and SPARC
- **Kernel**: Mach-based with backward-compatible libraries
- **APIs**: More modern APIs that align with current porting needs
- **Emulation**: Full support in Previous (from 0.8 through 4.2)
- **Use Case**: Extended std library support and advanced features

## Version Selection Rationale

1. **NeXTSTEP 3.3** provides:
   - Maximum stability for m68k systems
   - Widest hardware compatibility
   - Best-documented system calls and APIs
   - Proven emulation reliability

2. **OPENSTEP 4.2** offers:
   - Updated system libraries
   - Enhanced Mach kernel features
   - Better POSIX compatibility layer
   - Final evolution of NeXT APIs

## Other Versions

Earlier versions (1.0 - 3.0) are viable for specific testing scenarios but less practical due to:
- Limited feature sets
- Less stable emulation
- Fewer available resources
- Narrower hardware support

## Implementation Strategy

1. **Phase 1**: Target NeXTSTEP 3.3 for core functionality
   - Basic runtime support (alloc, I/O)
   - System call bindings
   - Initial testing infrastructure

2. **Phase 2**: Extend to OPENSTEP 4.2 if needed
   - Advanced std library features
   - Enhanced API support
   - Performance optimizations

## Emulator Configuration

Previous emulator fully supports both targets:
- NeXTSTEP 3.3: Use Rev 2.5 v66 ROM (68040)
- OPENSTEP 4.2: Same ROM, different disk image
- Both versions tested and confirmed working

## Benefits of Dual Targeting

1. **Risk Mitigation**: Avoids Mach-POSIX compatibility issues
2. **Broad Testing**: Ensures code works across versions
3. **Future-Proofing**: Supports both legacy and "modern" NeXT systems
4. **Community Support**: Both versions have active user bases

This dual-target approach maximizes compatibility while leveraging the most stable and well-supported OS versions for m68k NeXT hardware.