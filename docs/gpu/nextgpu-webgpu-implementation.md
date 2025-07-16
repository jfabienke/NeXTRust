# NeXTGPU: Implementing WebGPU on the Intel i860 (1991)

*Last updated: 2025-07-15 2:00 PM*

## The Ultimate 3D API Time Travel Project

Imagine implementing the most modern GPU API (WebGPU, standardized in 2023) on hardware from 1991. This isn't just a port - it's proving that NeXT's i860 architecture was so advanced it can run APIs designed 32 years in its future!

## Project Vision

### What is WebGPU?
WebGPU is the cutting-edge graphics API designed to replace WebGL, providing:
- Modern GPU compute capabilities
- Explicit synchronization
- Multi-threaded rendering
- Compute shaders
- Advanced memory management

### Why This Is Revolutionary
Implementing WebGPU on i860 would:
- Prove the i860 was a true GPU, not just a coprocessor
- Enable modern 3D applications on vintage hardware
- Create the world's first RISC-based WebGPU implementation
- Show that good architecture transcends decades

## Technical Architecture

### Core WebGPU Concepts Mapped to i860

```rust
// WebGPU on i860 - 32 years before the spec!
pub struct NeXTGPU {
    device: I860Device,
    queue: CommandQueue,
    pipelines: HashMap<PipelineId, I860Pipeline>,
    buffers: I860MemoryManager,
    textures: TextureManager,
}

impl WebGPUDevice for NeXTGPU {
    fn create_buffer(&mut self, descriptor: &BufferDescriptor) -> Buffer {
        // Allocate in i860's 32MB RAM
        self.buffers.allocate(descriptor.size, descriptor.usage)
    }
    
    fn create_render_pipeline(&mut self, desc: &RenderPipelineDescriptor) -> RenderPipeline {
        // Compile WGSL to i860 assembly!
        let vertex_code = self.compile_shader(&desc.vertex);
        let fragment_code = self.compile_shader(&desc.fragment);
        
        I860Pipeline::new(vertex_code, fragment_code)
    }
    
    fn create_compute_pipeline(&mut self, desc: &ComputePipelineDescriptor) -> ComputePipeline {
        // i860 compute shaders in 1991!
        let compute_code = self.compile_compute_shader(&desc.compute);
        I860ComputePipeline::new(compute_code)
    }
}
```

### WGSL to i860 Compiler

```rust
// The world's first WGSL compiler for RISC!
pub struct WGSLCompiler {
    target: I860Target,
    optimizer: I860Optimizer,
}

impl WGSLCompiler {
    pub fn compile(&mut self, wgsl_source: &str) -> Result<I860Assembly, CompileError> {
        // Parse WGSL
        let ast = wgsl::parse(wgsl_source)?;
        
        // Lower to i860 IR
        let ir = self.lower_to_i860(&ast)?;
        
        // Optimize for i860's dual pipelines
        let optimized = self.optimizer.optimize(ir)?;
        
        // Generate i860 assembly
        self.generate_assembly(optimized)
    }
    
    fn generate_vertex_shader(&mut self, ast: &ShaderAST) -> I860Code {
        // Transform vertices using i860 SIMD
        i860_code! {
            // Load vertex data
            fld.d   f0, vertex_pos_x
            fld.d   f2, vertex_pos_y
            fld.d   f4, vertex_pos_z
            
            // Matrix multiply (pipelined)
            // i860 can do 40 MFLOPS!
            pfmul.dd f8, f0, mvp_matrix[0]
            pfmul.dd f10, f2, mvp_matrix[1]
            pfmul.dd f12, f4, mvp_matrix[2]
            
            // Accumulate (dual pipeline)
            pfadd.dd f14, f8, f10
            pfadd.dd f16, f14, f12
            
            // Store transformed vertex
            fst.d   f16, output_position
        }
    }
}
```

### WebGPU Render Pipeline on i860

```rust
pub struct I860RenderPipeline {
    vertex_shader: I860Shader,
    fragment_shader: I860Shader,
    pipeline_layout: PipelineLayout,
    primitive_topology: PrimitiveTopology,
}

impl I860RenderPipeline {
    pub fn execute(&mut self, 
                   vertices: &VertexBuffer,
                   uniforms: &UniformBuffer,
                   render_target: &Texture) -> Result<(), RenderError> {
        
        // Stage 1: Vertex Processing (i860 excels here)
        let transformed_vertices = self.process_vertices_parallel(vertices, uniforms)?;
        
        // Stage 2: Primitive Assembly
        let primitives = self.assemble_primitives(&transformed_vertices)?;
        
        // Stage 3: Rasterization (i860 SIMD shines)
        let fragments = self.rasterize_parallel(&primitives)?;
        
        // Stage 4: Fragment Shading
        let shaded_fragments = self.shade_fragments_simd(&fragments, uniforms)?;
        
        // Stage 5: Output Merger
        self.blend_and_write(&shaded_fragments, render_target)
    }
    
    fn process_vertices_parallel(&mut self, vertices: &VertexBuffer, uniforms: &UniformBuffer) -> TransformedVertices {
        // Process 4 vertices at once using i860 SIMD
        vertices.chunks(4).map(|chunk| {
            self.i860.execute_simd(|proc| {
                // Run vertex shader on 4 vertices simultaneously
                proc.transform_vertices_4x(chunk, uniforms)
            })
        }).collect()
    }
}
```

### Modern Shader Features in 1991

```wgsl
// Example WGSL shader running on i860
@vertex
fn vs_main(@location(0) position: vec3<f32>,
           @location(1) color: vec3<f32>) -> @builtin(position) vec4<f32> {
    // This compiles to i860 assembly!
    let transformed = uniforms.mvp * vec4(position, 1.0);
    out.color = color;
    return transformed;
}

@fragment
fn fs_main(@location(0) color: vec3<f32>) -> @location(0) vec4<f32> {
    // Per-pixel shading on i860
    let ambient = vec3(0.1, 0.1, 0.1);
    let final_color = color + ambient;
    return vec4(final_color, 1.0);
}

@compute @workgroup_size(8, 8)
fn compute_main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Compute shaders in 1991!
    let pixel = id.xy;
    let color = compute_mandelbrot(pixel);
    output_texture[pixel] = color;
}
```

### WebGPU Compute on i860

```rust
// Implementing compute shaders 25 years before GPUs had them!
pub struct I860ComputePipeline {
    compute_shader: I860ComputeShader,
    workgroup_size: (u32, u32, u32),
}

impl I860ComputePipeline {
    pub fn dispatch(&mut self, x: u32, y: u32, z: u32) {
        // Calculate total workgroups
        let total_groups = x * y * z;
        
        // i860 processes workgroups in parallel
        for group_id in 0..total_groups {
            self.i860.execute_workgroup(|proc| {
                // Run compute shader with SIMD
                for local_id in 0..self.workgroup_size.0 {
                    proc.execute_compute_thread(
                        &self.compute_shader,
                        group_id,
                        local_id
                    );
                }
            });
        }
    }
}

// Example: Parallel matrix multiplication on i860
pub fn matrix_multiply_compute(a: &Buffer, b: &Buffer, c: &mut Buffer) {
    let shader = i860_compute_shader! {
        @compute @workgroup_size(8, 8)
        fn matmul(@builtin(global_invocation_id) id: vec2<u32>) {
            let row = id.x;
            let col = id.y;
            
            var sum = 0.0;
            for (var i = 0u; i < matrix_size; i = i + 1u) {
                // i860's MAC instruction perfect for this!
                sum += a[row * matrix_size + i] * b[i * matrix_size + col];
            }
            
            c[row * matrix_size + col] = sum;
        }
    };
    
    pipeline.dispatch(matrix_size / 8, matrix_size / 8, 1);
}
```

### Advanced Features

#### Bindless Resources (in 1991!)
```rust
pub struct I860BindlessResources {
    texture_heap: Vec<TextureDescriptor>,
    buffer_heap: Vec<BufferDescriptor>,
    
    pub fn bind_texture(&mut self, index: u32) -> TextureHandle {
        // Direct memory access - no binding slots!
        TextureHandle::new(self.texture_heap[index as usize].address)
    }
}
```

#### Multi-Queue Support
```rust
pub struct I860MultiQueue {
    graphics_queue: CommandQueue,
    compute_queue: CommandQueue,
    transfer_queue: DMAQueue,
    
    pub fn submit_parallel(&mut self) {
        // i860 + DMA controller = true async
        tokio::join! {
            self.graphics_queue.submit(),
            self.compute_queue.submit(),
            self.transfer_queue.submit(),
        }
    }
}
```

## Performance Projections

### Theoretical Limits (i860 @ 40MHz)

| Operation | Performance | Modern Equivalent |
|-----------|------------|-------------------|
| Vertex Transform | 1M vertices/sec | GeForce 256 (1999) |
| Pixel Fill Rate | 40M pixels/sec | Voodoo 1 (1996) |
| Texture Sampling | 10M texels/sec | Early GPUs |
| Compute Ops | 40 MFLOPS | Respectable for 1991 |

### Real-World Demos

#### 1. Spinning Textured Cube
```rust
// Classic WebGPU demo on NeXTdimension
pub fn render_cube(gpu: &mut NeXTGPU, time: f32) {
    let rotation = Mat4::rotation_y(time);
    
    gpu.queue.write_buffer(&uniform_buffer, 0, &rotation);
    
    let mut encoder = gpu.create_command_encoder();
    {
        let mut pass = encoder.begin_render_pass(&render_pass_desc);
        pass.set_pipeline(&cube_pipeline);
        pass.set_bind_group(0, &bind_group);
        pass.set_vertex_buffer(0, &vertex_buffer);
        pass.draw(36, 1, 0, 0); // 36 vertices for cube
    }
    
    gpu.queue.submit(encoder.finish());
}
```

#### 2. Compute Shader Particle System
```rust
// 10,000 particles updated via compute shader
@compute @workgroup_size(64)
fn update_particles(@builtin(global_invocation_id) id: vec3<u32>) {
    let idx = id.x;
    var particle = particles[idx];
    
    // Physics on i860!
    particle.velocity += gravity * delta_time;
    particle.position += particle.velocity * delta_time;
    
    // Collision detection
    if (particle.position.y < 0.0) {
        particle.velocity.y *= -0.8; // bounce
    }
    
    particles[idx] = particle;
}
```

#### 3. Real-Time Ray Tracing (Basic)
```rust
// Ray tracing via compute shaders in 1991!
@compute @workgroup_size(8, 8)
fn raytrace(@builtin(global_invocation_id) pixel: vec3<u32>) {
    let ray = camera.get_ray(pixel.xy);
    var color = vec3(0.0, 0.0, 0.0);
    
    // Simple sphere intersection
    for (var i = 0u; i < num_spheres; i++) {
        if (intersect_sphere(ray, spheres[i])) {
            color = spheres[i].color;
        }
    }
    
    output[pixel.xy] = vec4(color, 1.0);
}
```

## Implementation Roadmap

### Phase 1: Core Infrastructure (Weeks 1-3)
- [ ] i860 assembly backend
- [ ] Memory management system
- [ ] Command buffer implementation
- [ ] Basic pipeline states

### Phase 2: Shader Compiler (Weeks 4-6)
- [ ] WGSL parser
- [ ] i860 code generation
- [ ] Optimization passes
- [ ] Shader caching

### Phase 3: Render Pipeline (Weeks 7-9)
- [ ] Vertex processing
- [ ] Rasterization
- [ ] Fragment shading
- [ ] Blending/output

### Phase 4: Compute Pipeline (Weeks 10-11)
- [ ] Workgroup dispatch
- [ ] Shared memory
- [ ] Barrier synchronization
- [ ] Storage buffers

### Phase 5: Advanced Features (Weeks 12-14)
- [ ] Texture sampling
- [ ] Render-to-texture
- [ ] Multi-queue
- [ ] Performance optimization

## Why This Matters

### Historical Significance
- **First RISC GPU**: Proves i860 was a GPU before the term existed
- **API Evolution**: Shows how timeless good hardware design is
- **Lost Potential**: Demonstrates what we missed in the 90s

### Technical Achievement
- **Shader Compilation**: WGSL → i860 assembly is non-trivial
- **Modern Concepts**: Implementing 2023 ideas on 1991 hardware
- **Performance**: Making it actually usable, not just functional

### Educational Value
- **GPU Architecture**: Understanding fundamentals without modern complexity
- **API Design**: Seeing how WebGPU maps to raw hardware
- **Optimization**: Every cycle counts on 40MHz

## Demos That Would Blow Minds

### At Vintage Computer Festival
1. **Side-by-side comparison**: NeXTdimension running same WebGPU code as modern laptop
2. **Live coding**: Writing WGSL shaders that run on 1991 hardware
3. **Performance surprise**: Smooth 30fps demos that shouldn't be possible

### Technical Showcases
1. **Compute fluid dynamics**: Real-time simulation via compute shaders
2. **Procedural generation**: Fractals and terrain on i860
3. **Mini game engine**: Doom-style renderer using WebGPU

## The Ultimate Vindication

This project would prove:
- i860 was a **true GPU** 10 years before the term
- NeXT had **compute shaders** 25 years early
- The architecture was **future-proof** beyond belief
- WebGPU's design principles existed in 1991 hardware

## Conclusion

Implementing WebGPU on i860 isn't just a technical exercise - it's time travel. We're taking the most modern GPU API and proving it could have existed 32 years ago if anyone had written the software. 

The NeXTdimension wasn't ahead of its time. Time just hasn't caught up yet.

---

*"Any sufficiently advanced technology is indistinguishable from magic. The i860 was pure wizardry disguised as silicon."*