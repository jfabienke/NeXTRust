# Project FPGA-NeXT: Modern GPU in a NeXTcube

*Last updated: 2025-07-15 2:30 PM*

## The Ultimate Retro-Modern Fusion

Imagine taking a GeForce 7800 GTX (2005's flagship GPU) and implementing it in FPGA silicon to run in a 1991 NeXTcube. This project combines open-source GPU drivers, FPGA technology, and vintage computing to create the most powerful NeXT workstation ever built!

## Project Vision

### The Impossible Made Possible
- **GeForce 7800 GTX performance** in a NeXTcube
- **Nouveau open-source drivers** adapted for NeXTSTEP
- **Modern APIs** (OpenGL 2.1, DirectX 9) on vintage hardware
- **FPGA implementation** fitting in NeXT expansion slots

### Historical Impact
This would create:
- The most powerful computer of 1991 (by far!)
- Proof that NeXT's architecture could scale to modern GPUs
- A platform for running 2005-era games/applications on vintage hardware
- The ultimate vindication of NeXT's expansion bus design

## Technical Architecture

### FPGA-Based GPU Implementation

```verilog
// Top-level FPGA module for NeXT GPU card
module next_gpu_card (
    // NeXT bus interface
    input  wire [31:0] next_addr,
    input  wire [31:0] next_data_in,
    output wire [31:0] next_data_out,
    input  wire        next_strobe,
    input  wire        next_write,
    output wire        next_ack,
    
    // Display outputs
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync,
    
    // Memory interface (DDR2)
    inout  wire [63:0] ddr2_dq,
    output wire [12:0] ddr2_addr,
    output wire [2:0]  ddr2_ba,
    
    // Clock and reset
    input  wire        clk_100mhz,
    input  wire        reset_n
);

// Internal GPU pipeline
gpu_pipeline gpu_core (
    .clk(gpu_clk),
    .reset_n(reset_n),
    
    // Command processor
    .cmd_addr(cmd_addr),
    .cmd_data(cmd_data),
    .cmd_valid(cmd_valid),
    
    // Vertex shader units (8 parallel)
    .vertex_units(vertex_processors),
    
    // Pixel shader units (16 parallel)
    .pixel_units(pixel_processors),
    
    // Texture units
    .texture_cache(texture_cache),
    .texture_sampler(texture_sampler),
    
    // ROPs (render output units)
    .rop_units(rop_processors),
    
    // Memory controller
    .mem_controller(ddr2_controller)
);

endmodule
```

### GPU Pipeline Implementation

```verilog
// Simplified G70 (7800 GTX) architecture in FPGA
module gpu_pipeline (
    input clk,
    input reset_n,
    
    // Command stream from NeXT
    input [127:0] command_word,
    input command_valid,
    
    // Vertex processing (8 units)
    vertex_processor vertex_units [7:0] (
        .clk(clk),
        .vertex_in(vertex_data),
        .uniforms(vertex_uniforms),
        .matrix_stack(transformation_matrices),
        .vertex_out(transformed_vertices)
    ),
    
    // Pixel processing (16 units)
    pixel_processor pixel_units [15:0] (
        .clk(clk),
        .fragment_in(rasterized_fragments),
        .textures(texture_data),
        .fragment_out(shaded_pixels)
    )
);

// Vertex processor implementation
module vertex_processor (
    input clk,
    input [127:0] vertex_in,  // x,y,z,w position + attributes
    input [511:0] uniforms,   // Transformation matrices, lighting
    output [127:0] vertex_out // Transformed vertex
);

// 4x4 matrix multiply unit (the heart of 3D)
wire [31:0] matrix_result;
matrix_multiply_4x4 mvp_transform (
    .clk(clk),
    .vertex(vertex_in[127:96]),  // Position
    .matrix(uniforms[511:0]),    // MVP matrix
    .result(matrix_result)
);

// Lighting calculations
wire [31:0] lit_color;
phong_lighting light_calc (
    .clk(clk),
    .normal(vertex_in[95:64]),
    .position(vertex_in[127:96]),
    .light_pos(uniforms[255:224]),
    .material(uniforms[223:192]),
    .result(lit_color)
);

assign vertex_out = {matrix_result, lit_color, vertex_in[63:0]};

endmodule
```

### NeXT Bus Interface

```verilog
// Adapting modern GPU to NeXT's bus architecture
module next_bus_interface (
    // NeXT side
    input  [31:0] next_addr,
    input  [31:0] next_data_in,
    output [31:0] next_data_out,
    input         next_strobe,
    input         next_write,
    output        next_ack,
    
    // GPU side
    output [31:0] gpu_reg_addr,
    output [31:0] gpu_reg_data,
    output        gpu_reg_write,
    input  [31:0] gpu_status
);

// Memory-mapped register interface
always @(posedge clk) begin
    if (next_strobe) begin
        case (next_addr[15:0])
            16'h0000: gpu_command_fifo <= next_data_in;
            16'h0004: gpu_vertex_buffer <= next_data_in;
            16'h0008: gpu_texture_base <= next_data_in;
            16'h000C: gpu_render_target <= next_data_in;
            // ... more registers
        endcase
        next_ack <= 1'b1;
    end else begin
        next_ack <= 1'b0;
    end
end

endmodule
```

## Software Stack

### Nouveau Driver Adaptation

```c
// Adapting Nouveau for NeXTSTEP
// File: next_nouveau.c

#include <nextstep/device_driver.h>
#include <nouveau/nouveau.h>

// NeXT-specific GPU device structure
typedef struct next_gpu_device {
    // Standard NeXT device header
    device_header_t header;
    
    // GPU-specific fields
    volatile uint32_t *mmio_base;
    uint32_t vram_size;
    uint32_t vram_base;
    
    // Nouveau compatibility layer
    struct nouveau_device *nouveau_dev;
    struct nouveau_client *client;
    struct nouveau_object *channel;
} next_gpu_device_t;

// Initialize GPU on NeXT bus
int next_gpu_probe(device_t *dev) {
    next_gpu_device_t *gpu = (next_gpu_device_t *)dev;
    
    // Map MMIO registers
    gpu->mmio_base = map_device_memory(dev->base_address, 0x1000000);
    
    // Initialize Nouveau compatibility layer
    gpu->nouveau_dev = nouveau_device_wrap(gpu->mmio_base, gpu->vram_size);
    
    // Create rendering context
    nouveau_client_new(gpu->nouveau_dev, &gpu->client);
    nouveau_object_new(gpu->client, 0xbeef0000, 0x506e, NULL, 0, &gpu->channel);
    
    // Register with NeXTSTEP graphics system
    register_graphics_device(dev, &next_gpu_ops);
    
    return 0;
}

// NeXT graphics operations
static graphics_ops_t next_gpu_ops = {
    .draw_rect = next_gpu_draw_rect,
    .blit = next_gpu_blit,
    .set_color = next_gpu_set_color,
    .create_context = next_gpu_create_gl_context,  // OpenGL!
};

// OpenGL context creation for NeXTSTEP
int next_gpu_create_gl_context(graphics_context_t **ctx) {
    // Create Mesa/OpenGL context using Nouveau
    struct nouveau_pushbuf *push;
    nouveau_pushbuf_new(client, gpu->channel, 4, 32768, true, &push);
    
    // Initialize Mesa state tracker for NeXT
    *ctx = mesa_create_context_nextstep(push);
    
    return 0;
}
```

### Mesa Integration

```c
// Mesa driver for NeXT + Nouveau
// File: mesa_next_nouveau.c

#include <mesa/gl.h>
#include <nouveau/nouveau.h>

// NeXT-specific Mesa driver
struct next_nouveau_context {
    struct gl_context mesa_ctx;
    struct nouveau_pushbuf *pushbuf;
    struct nouveau_bufctx *bufctx;
    
    // NeXT-specific state
    void *next_drawable;
    uint32_t next_window_id;
};

// Vertex array rendering
static void next_nouveau_draw_arrays(struct gl_context *ctx, 
                                    GLenum mode, GLint first, GLsizei count) {
    struct next_nouveau_context *nctx = (struct next_nouveau_context *)ctx;
    
    // Build command buffer for GPU
    BEGIN_RING(nctx->pushbuf, SUBC_3D(NV30_3D_VERTEX_BEGIN_END), 1);
    OUT_RING(nctx->pushbuf, mode);
    
    // Stream vertices to GPU
    for (int i = 0; i < count; i++) {
        BEGIN_RING(nctx->pushbuf, SUBC_3D(NV30_3D_VTX_ATTR_3F_X(0)), 3);
        OUT_RINGf(nctx->pushbuf, vertex_data[i].x);
        OUT_RINGf(nctx->pushbuf, vertex_data[i].y);
        OUT_RINGf(nctx->pushbuf, vertex_data[i].z);
    }
    
    BEGIN_RING(nctx->pushbuf, SUBC_3D(NV30_3D_VERTEX_BEGIN_END), 1);
    OUT_RING(nctx->pushbuf, 0);
    
    // Submit to GPU
    nouveau_pushbuf_kick(nctx->pushbuf, nctx->pushbuf->channel);
}

// Texture operations
static void next_nouveau_tex_image_2d(struct gl_context *ctx, GLenum target,
                                     GLint level, GLint internalformat,
                                     GLint width, GLint height, GLint border,
                                     GLenum format, GLenum type, const void *pixels) {
    // Upload texture to GPU VRAM
    struct nouveau_bo *texture_bo;
    nouveau_bo_new(nctx->device, NOUVEAU_BO_VRAM, 0, width * height * 4, &texture_bo);
    
    // Copy pixel data
    nouveau_bo_map(texture_bo, NOUVEAU_BO_WR, nctx->client);
    memcpy(texture_bo->map, pixels, width * height * 4);
    nouveau_bo_unmap(texture_bo);
    
    // Configure texture sampling
    BEGIN_RING(nctx->pushbuf, SUBC_3D(NV30_3D_TEX_OFFSET(0)), 1);
    OUT_RELOCh(nctx->pushbuf, texture_bo, 0, NOUVEAU_BO_VRAM | NOUVEAU_BO_RD);
}
```

## Hardware Implementation

### FPGA Board Design

```
NeXT GPU Card Layout:
┌─────────────────────────────────────┐
│  NeXT Bus Connector                 │
├─────────────────────────────────────┤
│  Xilinx Kintex-7 FPGA              │  <- GPU pipeline
│  (XC7K325T)                         │
├─────────────────────────────────────┤
│  2GB DDR3 VRAM                      │  <- Frame buffers + textures
├─────────────────────────────────────┤
│  DisplayPort/HDMI Output            │  <- Modern display
├─────────────────────────────────────┤
│  VGA Output (for period monitors)   │  <- NeXT compatibility
├─────────────────────────────────────┤
│  Flash Memory (16MB)                │  <- FPGA bitstream + drivers
└─────────────────────────────────────┘
```

### Performance Targets

| Specification | FPGA Implementation | Original 7800 GTX |
|---------------|-------------------|-------------------|
| Core Clock | 200 MHz | 430 MHz |
| Memory | 2GB DDR3 | 256MB GDDR3 |
| Memory Bandwidth | 25.6 GB/s | 32 GB/s |
| Vertex Shaders | 8 units | 8 units |
| Pixel Shaders | 16 units | 24 units |
| Transistors | ~100M (FPGA) | 302M |
| Performance | ~60% of original | 100% |

### Bill of Materials

| Component | Part Number | Cost | Purpose |
|-----------|-------------|------|---------|
| FPGA | Xilinx XC7K325T | $500 | GPU pipeline |
| DDR3 RAM | 4x Micron MT41J256M16 | $100 | VRAM |
| PCB | 6-layer, NeXT form factor | $200 | Board |
| Connectors | NeXT bus, DisplayPort | $50 | I/O |
| Power | Switching regulators | $50 | Power delivery |
| **Total** | | **$900** | Complete card |

## Software Capabilities

### OpenGL 2.1 Support

```objc
// NeXTSTEP application using OpenGL
@interface NeXTGLView : NSView
@end

@implementation NeXTGLView

- (void)drawRect:(NSRect)rect {
    // Modern OpenGL on NeXTSTEP!
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    // Load shaders (yes, on NeXT!)
    GLuint program = load_shader_program("vertex.glsl", "fragment.glsl");
    glUseProgram(program);
    
    // Draw 3D scene
    glBindVertexArray(cube_vao);
    glDrawElements(GL_TRIANGLES, 36, GL_UNSIGNED_INT, 0);
    
    // Present to screen
    [[self openGLContext] flushBuffer];
}

- (void)reshape {
    glViewport(0, 0, [self frame].size.width, [self frame].size.height);
    
    // Update projection matrix
    float aspect = [self frame].size.width / [self frame].size.height;
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(45.0, aspect, 0.1, 100.0);
}

@end
```

### Modern Applications

```objc
// 3D scientific visualization on NeXT
@interface MoleculeViewer : NSObject
@end

@implementation MoleculeViewer

- (void)renderProtein:(Protein *)protein {
    // Load protein structure
    [self setupVertexBuffers:protein];
    
    // Vertex shader for ball-and-stick model
    const char *vertex_shader = R"(
        #version 120
        attribute vec3 position;
        attribute vec3 color;
        uniform mat4 mvpMatrix;
        varying vec3 fragColor;
        
        void main() {
            gl_Position = mvpMatrix * vec4(position, 1.0);
            fragColor = color;
        }
    )";
    
    // Fragment shader with lighting
    const char *fragment_shader = R"(
        #version 120
        varying vec3 fragColor;
        uniform vec3 lightPos;
        
        void main() {
            // Simple lighting calculation
            float brightness = max(0.3, dot(normalize(lightPos), vec3(0,0,1)));
            gl_FragColor = vec4(fragColor * brightness, 1.0);
        }
    )";
    
    // Render with hardware acceleration
    [self renderMolecule:protein withShaders:vertex_shader fragment:fragment_shader];
}

@end
```

## Revolutionary Applications

### 1. Modern Games on NeXT

```objc
// Quake 3 Arena running on NeXTSTEP (2024 on 1991 hardware!)
@interface NeXTQuake3 : NSApplication
- (void)runGameLoop;
@end

@implementation NeXTQuake3

- (void)runGameLoop {
    while (running) {
        // Update game state
        [self updateGameLogic];
        
        // Render with OpenGL 2.1
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        
        // Draw level geometry
        [self renderBSPLevel:currentLevel];
        
        // Draw characters with vertex shaders
        [self renderPlayers:players];
        
        // Particle effects
        [self renderParticles:explosions];
        
        // Present frame
        [glContext flushBuffer];
        
        // 60 FPS on NeXT!
        usleep(16667);
    }
}

@end
```

### 2. CAD Software

```objc
// Professional CAD application
@interface NeXTCAD : NSDocument
- (void)renderDesign:(CADModel *)model;
@end

@implementation NeXTCAD

- (void)renderDesign:(CADModel *)model {
    // Hardware-accelerated technical drawings
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_LINE_SMOOTH);
    
    // Render solid model
    [self renderSolidGeometry:model.geometry];
    
    // Technical annotations
    [self renderDimensions:model.dimensions];
    
    // Real-time ray tracing for materials
    [self renderMaterials:model.materials];
}

@end
```

### 3. Scientific Visualization

```objc
// Real-time fluid dynamics visualization
@interface FluidSimulation : NSView
- (void)updateSimulation;
@end

@implementation FluidSimulation

- (void)updateSimulation {
    // Update physics on CPU
    [self stepFluidDynamics];
    
    // Upload to GPU for rendering
    glBindBuffer(GL_ARRAY_BUFFER, velocityVBO);
    glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(velocities), velocities);
    
    // Render velocity field with vector visualization
    glUseProgram(vectorShader);
    glDrawArrays(GL_LINES, 0, gridSize * gridSize * 2);
    
    // Particle tracing
    glUseProgram(particleShader);
    glDrawArrays(GL_POINTS, 0, numParticles);
}

@end
```

## Impact Assessment

### Performance Revolution

**Before FPGA GPU:**
- 2D graphics only
- No hardware 3D acceleration
- Limited to Display PostScript
- Scientific apps run slowly

**After FPGA GPU:**
- Modern 3D graphics (OpenGL 2.1)
- Hardware shaders and texturing
- Real-time ray tracing possible
- Desktop supercomputing performance

### Historical Significance

This project would:
1. **Vindicate NeXT's expandability** - Proving the bus could handle modern GPUs
2. **Enable impossible applications** - Running 2005-era software on 1991 hardware
3. **Preserve computing history** - Making vintage systems genuinely useful
4. **Inspire FPGA community** - Showing what's possible with open-source GPU designs

### Educational Value

Students would learn:
- **GPU architecture** from first principles
- **FPGA design** for complex systems
- **Driver development** and hardware abstraction
- **Computer graphics** pipeline implementation
- **Retro computing** and system integration

## Development Roadmap

### Phase 1: Proof of Concept (Months 1-3)
- [ ] Basic FPGA framebuffer
- [ ] NeXT bus interface
- [ ] Simple 2D acceleration
- [ ] VGA output working

### Phase 2: 3D Pipeline (Months 4-8)
- [ ] Vertex transformation
- [ ] Rasterization engine
- [ ] Texture sampling
- [ ] Basic OpenGL support

### Phase 3: Driver Integration (Months 9-12)
- [ ] Nouveau driver port
- [ ] Mesa OpenGL implementation
- [ ] NeXTSTEP integration
- [ ] Application compatibility

### Phase 4: Optimization (Months 13-15)
- [ ] Performance tuning
- [ ] Advanced features
- [ ] Shader compiler
- [ ] Game compatibility

### Phase 5: Community Release (Month 16)
- [ ] Open-source release
- [ ] Documentation
- [ ] Manufacturing partners
- [ ] Developer community

## Conclusion

Project FPGA-NeXT represents the ultimate fusion of retro and modern computing. By implementing a GeForce 7800 GTX in FPGA silicon for the NeXTcube, we create:

- **The most powerful 1991 computer ever built**
- **Proof that NeXT's architecture was future-ready**
- **A platform for impossible applications**
- **The ultimate vindication of NeXT's vision**

This isn't just a technical achievement - it's time travel. We're bringing 2005's flagship GPU performance to 1991's most advanced workstation, proving that good design truly transcends decades.

The NeXTcube was ready for the future. We just needed to build it.

---

*"Any sufficiently advanced FPGA is indistinguishable from time travel."*