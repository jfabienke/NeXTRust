# NeXTRust Documentation

Welcome to the NeXTRust project documentation! This directory contains comprehensive technical documentation organized by topic.

## 📁 Documentation Structure

### [core/](core/) - Core Project Documentation
Essential documentation for the main NeXTRust cross-compilation project.
- **[Architecture Design](core/architecture-design.md)** - System architecture and design decisions
- **[Project Plan](core/project-plan.md)** - Implementation roadmap and milestones
- **[Rust Target Specification](core/rust-target-spec.md)** - m68k-next-nextstep target details
- **[LLVM Enhancements](core/llvm-enhancements.md)** - Required LLVM backend modifications
- **[Library Porting](core/library-porting.md)** - Strategy for porting Rust standard library

### [hardware/](hardware/) - Hardware Acceleration & Integration
Documentation for leveraging NeXT's unique hardware capabilities.
- **[DSP Framework](hardware/dsp-framework.md)** - Motorola 56001 DSP acceleration for crypto/audio
- **[NeXTdimension Acceleration](hardware/nextdimension-acceleration.md)** - Intel i860 coprocessor utilization
- **[i860 GPU Simulations](hardware/i860-gpu-simulations.md)** - Scientific computing on i860
- **[PostScript Interpreter Options](hardware/postscript-interpreter-options.md)** - Display PostScript acceleration

### [gpu/](gpu/) - GPU Support & Initialization
Comprehensive GPU support from vintage to modern cards.
- **[FPGA NeXT GPU](gpu/fpga-next-gpu.md)** - Initial FPGA GPU design
- **[NeXTBus-PCI Bridge GPU](gpu/nextbus-pci-bridge-gpu.md)** - PCI bridge for real GPUs
- **[NeXTGPU WebGPU Implementation](gpu/nextgpu-webgpu-implementation.md)** - WebGPU on i860
- **[GPU ROM Init Pipeline](gpu/gpu-rom-init-pipeline.md)** - ROM initialization extraction
- **[GPU Init Implementation Guide](gpu/gpu-init-implementation-guide.md)** - Production pipeline
- **[GPU Init Hybrid Architecture](gpu/gpu-init-hybrid-architecture.md)** - Python/Rust design
- **[GPU Init JSON Schema](gpu/gpu-init-json-schema.md)** - Init sequence specification

### [storage/](storage/) - Storage Solutions
Modern storage solutions for vintage hardware.
- **[NVMe NeXT Implementation](storage/nvme-next-implementation.md)** - Native NVMe support via FPGA

### [systems/](systems/) - Complete System Designs
Full system integration projects combining multiple technologies.
- **[Apollo-WASM-GPU-NeXT](systems/apollo-wasm-gpu-next.md)** - Apollo 68080 + WASM + GPU
- **[Apollo-WASM-GPU-NVMe-NeXT](systems/apollo-wasm-gpu-nvme-next.md)** - Complete ultimate system
- **[WASM NeXT Support](systems/wasm-next-support.md)** - WebAssembly runtime analysis
- **[Unified Computing ML Timeline](systems/unified-computing-ml-timeline.md)** - ML acceleration vision

### [applications/](applications/) - Application Examples
Example applications demonstrating platform capabilities.
- **[NeXTSTEP Web Browser](applications/nextstep-web-browser.md)** - Revolutionary 1991 web browser

### [infrastructure/](infrastructure/) - Build & CI/CD
Development infrastructure and automation.
- **[CI Pipeline](infrastructure/ci-pipeline.md)** - Continuous integration setup

## 🚀 Quick Start

1. **New to NeXTRust?** Start with [Architecture Design](core/architecture-design.md)
2. **Want to contribute?** Check [Project Plan](core/project-plan.md) for current priorities
3. **Interested in GPU support?** Begin with [GPU ROM Init Pipeline](gpu/gpu-rom-init-pipeline.md)
4. **Hardware acceleration?** Explore [DSP Framework](hardware/dsp-framework.md)

## 📚 Key Documents by Topic

### For Compiler Developers
- [Rust Target Specification](core/rust-target-spec.md)
- [LLVM Enhancements](core/llvm-enhancements.md)
- [Library Porting](core/library-porting.md)

### For Hardware Enthusiasts
- [Apollo-WASM-GPU-NVMe-NeXT](systems/apollo-wasm-gpu-nvme-next.md) - Ultimate system
- [NeXTdimension Acceleration](hardware/nextdimension-acceleration.md) - i860 utilization
- [NVMe Implementation](storage/nvme-next-implementation.md) - Modern storage

### For GPU Developers
- [GPU Init Implementation Guide](gpu/gpu-init-implementation-guide.md) - Complete pipeline
- [WebGPU on i860](gpu/nextgpu-webgpu-implementation.md) - Modern GPU API
- [GPU Simulations](hardware/i860-gpu-simulations.md) - Scientific computing

## 🔄 Document Status

Most documentation is actively maintained and updated as the project evolves. Check individual document headers for last update timestamps.

## 🤝 Contributing

When adding new documentation:
1. Place it in the appropriate subfolder
2. Update this README with a brief description
3. Include "Last updated" timestamp in your document
4. Follow existing formatting conventions

---

*For the main project README, see [../README.md](../README.md)*