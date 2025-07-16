# PostScript Interpreter Options for NeXTdimension Acceleration

*Last updated: 2025-07-15 11:10 AM*

## Overview

The NeXTdimension acceleration project needs a PostScript interpreter that can be adapted to run on the Intel i860. Here are our options:

## Option 1: Ghostscript (Most Practical)

### Overview
Ghostscript is the gold standard open-source PostScript interpreter, with 30+ years of development. For the NeXTdimension project, we can leverage its maturity while adding i860 acceleration.

### Pros
- **Mature and complete** Level 2 PostScript implementation
- **Open source** (AGPL/GPL) with active community
- **Actively maintained** with decades of bug fixes
- **Modular architecture** allows extracting just what we need
- **Already ported** to many architectures
- **Extensive test suite** ensures compatibility

### Cons
- **Large codebase** (~1M lines of C)
- **GPL license** may limit commercial use
- **Not designed for acceleration** - would need significant refactoring
- **Complex build system** requires understanding

### Deep Dive: Ghostscript Architecture

```
Ghostscript Core Components:
├── psi/           # PostScript interpreter
│   ├── interp.c   # Main interpreter loop
│   ├── istack.c   # Operand stack
│   └── igstate.c  # Graphics state
├── base/          # Graphics library
│   ├── gxpath.c   # Path operations
│   ├── gxfill.c   # Path filling
│   └── gxstroke.c # Path stroking
├── devices/       # Output devices
│   ├── gdevx.c    # X11 display
│   └── gdevpdf.c  # PDF output
└── lib/           # PostScript procedures
```

### Strategic Extraction Approach

```c
// 1. Extract path operations for i860 acceleration
// From base/gxpath.c
typedef struct gs_path_s {
    gs_path_segment *first_segment;
    gs_path_segment *current_segment;
    gs_point current_point;
    // ... simplified from original
} gs_path;

// We'd intercept these operations:
int gs_moveto(gs_state *pgs, floatp x, floatp y) {
    // Original Ghostscript implementation
    // ... 
    
    // Our addition: mark for i860 processing
    if (pgs->i860_accelerated) {
        return i860_queue_moveto(pgs->i860_context, x, y);
    }
    
    // Fall back to standard implementation
    return gs_moveto_standard(pgs, x, y);
}

int gs_curveto(gs_state *pgs, floatp x1, floatp y1,
               floatp x2, floatp y2, floatp x3, floatp y3) {
    if (pgs->i860_accelerated) {
        // Queue for i860 tessellation
        i860_bezier_segment seg = {
            .p0 = pgs->current_point,
            .p1 = {x1, y1},
            .p2 = {x2, y2},  
            .p3 = {x3, y3}
        };
        return i860_queue_bezier(pgs->i860_context, &seg);
    }
    
    return gs_curveto_standard(pgs, x1, y1, x2, y2, x3, y3);
}
```

### Integration Points for i860

```c
// 2. Hook into the fill algorithm
// From base/gxfill.c
int gx_fill_path(gx_path *ppath, gx_device_color *pdevc, 
                 gs_state *pgs, int rule) {
    if (pgs->i860_accelerated && i860_can_accelerate_fill(ppath)) {
        // Prepare path data for i860
        i860_path_data *path_data = prepare_path_for_i860(ppath);
        
        // Dispatch to i860 for scan conversion
        i860_fill_result *result = i860_scan_convert(
            pgs->i860_context,
            path_data,
            rule,
            pgs->device->width,
            pgs->device->height
        );
        
        // Blit result to framebuffer
        return blit_i860_result(pgs->device, result);
    }
    
    // Fall back to CPU implementation
    return gx_fill_path_cpu(ppath, pdevc, pgs, rule);
}

// 3. Accelerate anti-aliasing
// New file: i860/gs_i860_aa.c
typedef struct {
    int width, height;
    uint32_t *pixels;  // 32-bit RGBA
} i860_aa_buffer;

int i860_antialias_path(gs_state *pgs, gx_path *path,
                       i860_aa_buffer *output) {
    // Use i860's SIMD for 4x4 supersampling
    i860_command cmd = {
        .type = I860_CMD_ANTIALIAS,
        .data.aa = {
            .path = convert_path_to_i860_format(path),
            .samples_per_pixel = 16,  // 4x4
            .output = output
        }
    };
    
    return i860_execute_command(pgs->i860_context, &cmd);
}
```

### Practical Implementation Plan

#### Phase 1: Minimal Integration (2-3 weeks)
```c
// Start by accelerating just bezier tessellation
// This is self-contained and high-impact

// New file: i860/gs_i860_bezier.c
#include "base/gxpath.h"
#include "i860_accel.h"

int gs_i860_flatten_curve(gs_state *pgs, 
                         floatp x0, floatp y0,  // Start point
                         floatp x1, floatp y1,  // Control 1
                         floatp x2, floatp y2,  // Control 2
                         floatp x3, floatp y3,  // End point
                         floatp flatness) {
    // Convert to i860 format
    i860_bezier bez = {
        .p = {{x0,y0}, {x1,y1}, {x2,y2}, {x3,y3}},
        .flatness = flatness
    };
    
    // Get tessellated points from i860
    i860_point_list *points = i860_tessellate_bezier(&bez);
    
    // Add to Ghostscript path
    for (int i = 0; i < points->count; i++) {
        gs_lineto(pgs, points->pts[i].x, points->pts[i].y);
    }
    
    i860_free_points(points);
    return 0;
}
```

#### Phase 2: Rasterization Pipeline (4-6 weeks)
```c
// Hook deeper into Ghostscript's rendering pipeline
// Modify base/gxdevice.h to add i860 support

struct gx_device_s {
    // ... existing fields ...
    
    // i860 acceleration support
    bool has_i860;
    i860_context *i860_ctx;
    
    // Accelerated operations
    int (*i860_fill_parallelogram)(gx_device *dev,
        fixed px, fixed py, fixed ax, fixed ay,
        fixed bx, fixed by, const gx_device_color *pdevc);
    
    int (*i860_fill_trapezoid)(gx_device *dev,
        const gs_fixed_edge *left, const gs_fixed_edge *right,
        fixed ybot, fixed ytop, const gx_device_color *pdevc);
};

// Implement accelerated device for NeXTdimension
// New file: devices/gdev_nextdim.c
static int nextdim_fill_parallelogram(gx_device *dev, ...) {
    nextdim_device *ndev = (nextdim_device *)dev;
    
    // Convert coordinates to i860 format
    i860_parallelogram para = {
        .origin = {fixed2float(px), fixed2float(py)},
        .vector_a = {fixed2float(ax), fixed2float(ay)},
        .vector_b = {fixed2float(bx), fixed2float(by)},
        .color = convert_gs_color_to_rgba(pdevc)
    };
    
    // Dispatch to i860
    return i860_fill_parallelogram(ndev->i860_ctx, &para);
}
```

#### Phase 3: Color Management (2-3 weeks)
```c
// Ghostscript has sophisticated color management
// We can accelerate color space conversions

// From base/gscspace.c - hook into color space conversions
int gs_color_space_convert(gs_color_space *src_space,
                          const float *src_components,
                          gs_color_space *dst_space,
                          float *dst_components) {
    if (i860_can_accelerate_conversion(src_space, dst_space)) {
        // Use i860 SIMD for parallel color conversion
        return i860_convert_colors(
            src_space->type,
            src_components,
            dst_space->type,
            dst_components,
            1  // Single color for now
        );
    }
    
    return gs_color_space_convert_cpu(src_space, src_components,
                                     dst_space, dst_components);
}

// Bulk color conversion for images
int i860_convert_image_colors(
    gs_color_space_index src_type,
    const byte *src_data,
    gs_color_space_index dst_type,
    byte *dst_data,
    int pixel_count) {
    
    // i860 can process 4 pixels in parallel
    i860_color_convert_cmd cmd = {
        .src_format = map_gs_to_i860_format(src_type),
        .dst_format = map_gs_to_i860_format(dst_type),
        .src_data = src_data,
        .dst_data = dst_data,
        .count = pixel_count
    };
    
    return i860_execute_convert(&cmd);
}
```

### Building Ghostscript with i860 Support

```makefile
# Modify Ghostscript's makefile
# Add i860 acceleration module

I860_CFLAGS = -DHAVE_I860_ACCEL -I./i860
I860_OBJS = \
    i860/gs_i860_init.o \
    i860/gs_i860_bezier.o \
    i860/gs_i860_fill.o \
    i860/gs_i860_color.o \
    i860/gs_i860_image.o

# Link with i860 libraries
EXTRALIBS += -li860_accel -lnextdim_driver

# Add to device list
DEVICE_DEVS20 += $(DD)nextdim.dev

# Device definition
$(DD)nextdim.dev: $(DEVOBJ)gdev_nextdim.$(OBJ) $(I860_OBJS)
    $(SETDEV) $(DD)nextdim $(DEVOBJ)gdev_nextdim.$(OBJ) $(I860_OBJS)
```

### Testing Strategy

```c
// Create comprehensive test suite
// tests/i860_accel_test.c

void test_bezier_tessellation() {
    // Compare i860 vs CPU tessellation
    gs_point cpu_points[MAX_POINTS];
    gs_point i860_points[MAX_POINTS];
    
    int cpu_count = tessellate_bezier_cpu(
        0, 0, 100, 100, 200, 100, 300, 0,
        0.1,  // flatness
        cpu_points
    );
    
    int i860_count = tessellate_bezier_i860(
        0, 0, 100, 100, 200, 100, 300, 0,
        0.1,
        i860_points
    );
    
    // Results should match within tolerance
    assert(cpu_count == i860_count);
    for (int i = 0; i < cpu_count; i++) {
        assert(fabs(cpu_points[i].x - i860_points[i].x) < 0.001);
        assert(fabs(cpu_points[i].y - i860_points[i].y) < 0.001);
    }
}

void benchmark_fill_performance() {
    // Complex path with multiple subpaths
    gs_path *complex_path = create_complex_test_path();
    
    clock_t cpu_start = clock();
    fill_path_cpu(complex_path);
    clock_t cpu_end = clock();
    
    clock_t i860_start = clock();
    fill_path_i860(complex_path);
    clock_t i860_end = clock();
    
    double cpu_time = (cpu_end - cpu_start) / (double)CLOCKS_PER_SEC;
    double i860_time = (i860_end - i860_start) / (double)CLOCKS_PER_SEC;
    
    printf("CPU: %.3f ms, i860: %.3f ms, Speedup: %.1fx\n",
           cpu_time * 1000, i860_time * 1000, cpu_time / i860_time);
}
```

### Real-World Benefits

By leveraging Ghostscript:
1. **Proven compatibility** - Handles all PostScript edge cases
2. **Extensive test suite** - Ensures our acceleration is correct
3. **Active development** - Benefit from ongoing improvements
4. **Industry standard** - Used by CUPS, Linux printing, etc.

The key is to be surgical - accelerate the hot paths while maintaining compatibility with Ghostscript's architecture. This gives us the best of both worlds: mature PostScript handling with i860 acceleration where it matters most.

## Option 2: NeXT's Original Display PostScript (Ideal but Complex)

### The Dream Scenario
NeXT's original DPS was designed for hardware acceleration!

### Challenges
- **Proprietary code** - Would need clean-room implementation
- **Partially documented** - Adobe/NeXT kept internals secret
- **Complex integration** with WindowServer

### Research Approach
```rust
// Study NeXT's DPS behavior and reimplement
pub struct DisplayPostScriptCompat {
    // Implement documented DPS extensions
    context_manager: DPSContextManager,
    // Reverse-engineer acceleration hooks
    acceleration_points: Vec<AccelerationHook>,
}
```

## Option 3: Write a Minimal PostScript Subset (Most Fun)

### Philosophy
We don't need all of PostScript - just the subset commonly used for display!

### Core Features Needed
```rust
// Minimal PS interpreter for display acceleration
pub enum PSCommand {
    // Path construction
    MoveTo(f32, f32),
    LineTo(f32, f32),
    CurveTo(f32, f32, f32, f32, f32, f32),
    ClosePath,
    
    // Path painting
    Stroke,
    Fill,
    Clip,
    
    // Graphics state
    SetGray(f32),
    SetRGBColor(f32, f32, f32),
    SetLineWidth(f32),
    
    // Transformations
    Translate(f32, f32),
    Rotate(f32),
    Scale(f32, f32),
    
    // Text (minimal)
    SelectFont(String, f32),
    Show(String),
}

impl PSInterpreter {
    pub fn new() -> Self {
        // Just 2000 lines of Rust instead of 1M lines of C!
        PSInterpreter {
            graphics_state: GraphicsState::default(),
            path_builder: PathBuilder::new(),
            i860_accelerator: I860Accelerator::new(),
        }
    }
    
    pub fn execute(&mut self, program: &str) -> Result<(), PSError> {
        let commands = self.parse(program)?;
        
        for cmd in commands {
            match cmd {
                PSCommand::MoveTo(x, y) => {
                    self.path_builder.move_to(x, y);
                }
                PSCommand::CurveTo(x1, y1, x2, y2, x3, y3) => {
                    // Tessellate on i860!
                    let points = self.i860_accelerator.tessellate_bezier(
                        self.path_builder.current_point(),
                        (x1, y1), (x2, y2), (x3, y3)
                    )?;
                    self.path_builder.add_points(points);
                }
                PSCommand::Fill => {
                    // Rasterize on i860!
                    let pixels = self.i860_accelerator.fill_path(
                        &self.path_builder.path,
                        &self.graphics_state
                    )?;
                    self.framebuffer.blit(pixels);
                }
                // ... implement other commands
            }
        }
        Ok(())
    }
}
```

### What We Can Skip
- PostScript programming constructs (loops, conditionals)
- Dictionary operations  
- Complex font handling (use NeXT's font system)
- Level 2 features we don't need

## Option 4: Hybrid Approach (Recommended)

### Best of All Worlds
1. **Start with minimal interpreter** for proof of concept
2. **Port Ghostscript components** as needed
3. **Study NeXT DPS behavior** for compatibility
4. **Optimize for i860** from day one

### Architecture
```rust
pub struct HybridPSInterpreter {
    // Our minimal fast path
    fast_path: MinimalPSInterpreter,
    // Ghostscript fallback for complex operations
    ghostscript: Option<GhostscriptInterpreter>,
    // i860 acceleration
    accelerator: I860Accelerator,
    // Compatibility layer
    dps_compat: DPSCompatibility,
}

impl HybridPSInterpreter {
    pub fn interpret(&mut self, ps_code: &str) -> Result<(), PSError> {
        // Try fast path first
        match self.fast_path.can_handle(ps_code) {
            true => {
                // Use our optimized interpreter
                self.fast_path.execute_accelerated(ps_code, &mut self.accelerator)
            }
            false => {
                // Fall back to full interpreter
                if let Some(gs) = &mut self.ghostscript {
                    gs.interpret(ps_code)
                } else {
                    Err(PSError::NotImplemented)
                }
            }
        }
    }
}
```

## i860-Specific Optimizations

### What to Accelerate
```rust
// Operations that benefit from i860 SIMD
pub enum I860PSOperations {
    // Path operations (perfect for parallel processing)
    TessellateBezier,      // Subdivide curves
    StrokePath,            // Expand stroke to filled path
    ClipPath,              // Path intersection
    
    // Rasterization (i860 shines here)
    ScanConvert,           // Path to pixels
    AntiAlias,             // 4x4 supersampling
    Composite,             // Alpha blending
    
    // Image operations
    ColorConvert,          // RGB<->CMYK
    ImageScale,            // Bilinear/bicubic
    ConvolveFilter,        // Blur, sharpen, etc.
}
```

### What to Keep on CPU
- Text layout (needs font metrics)
- Dictionary operations
- Control flow
- Simple coordinate transforms

## Development Strategy

### Phase 1: Minimal Proof of Concept (2 weeks)
```rust
// Just enough PS to draw accelerated graphics
pub fn milestone_1() {
    let ps_code = r#"
        100 100 moveto
        200 200 300 100 400 200 curveto
        stroke
    "#;
    
    // This should use i860 for curve tessellation
    interpreter.execute(ps_code).unwrap();
}
```

### Phase 2: Ghostscript Integration (4 weeks)
- Extract Ghostscript's path operations
- Create i860 acceleration hooks
- Benchmark against pure CPU

### Phase 3: DPS Compatibility (2 weeks)
- Implement NeXT-specific operators
- Test with real NeXT applications
- Ensure WindowServer integration

### Phase 4: Full Acceleration (4 weeks)
- Optimize all beneficial operations
- Create demo applications
- Document performance gains

## Performance Targets

| Operation | CPU Only | i860 Accelerated | Target Speedup |
|-----------|----------|------------------|----------------|
| Bezier tessellation | 50μs | 2.5μs | 20x |
| Path fill | 1ms | 50μs | 20x |
| Anti-aliasing | 4ms | 200μs | 20x |
| Image composite | 10ms | 500μs | 20x |

## Resources

### PostScript References
- [PostScript Language Reference (Red Book)](https://www.adobe.com/content/dam/acom/en/devnet/postscript/pdfs/PLRM.pdf)
- [PostScript Tutorial (Blue Book)](https://www-cdf.fnal.gov/offline/PostScript/BLUEBOOK.PDF)
- [Thinking in PostScript](https://www.rightbrain.com/pages/books.html)

### Open Source Implementations
- [Ghostscript](https://www.ghostscript.com/)
- [XIL (Sun's imaging library)](https://github.com/jib/xil) - Has PS elements
- [GNUstep's DPS implementation](http://www.gnustep.org/) - Studies NeXT behavior

### i860 Optimization Guides
- [i860 Programmer's Reference](http://bitsavers.org/components/intel/i860/)
- [Optimizing for i860](http://bitsavers.org/components/intel/i860/i860_64-Bit_Microprocessor_Optimization_1991.pdf)

## Decision Matrix

| Approach | Development Time | Performance | Compatibility | Maintenance |
|----------|-----------------|-------------|---------------|-------------|
| Ghostscript | Medium | Good | Excellent | Easy |
| Clean-room DPS | Very High | Excellent | Perfect | Hard |
| Minimal subset | Low | Excellent | Limited | Easy |
| Hybrid | Medium | Excellent | Good | Medium |

## Recommendation

**Start with the Hybrid Approach**:
1. Build minimal interpreter for core operations
2. Accelerate the operations that matter most
3. Add Ghostscript for completeness later
4. Study DPS for authentic behavior

This gets us to a working demo fastest while leaving room for growth.

---

*"The best PostScript interpreter is the one that actually ships with i860 acceleration!"*