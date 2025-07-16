# WebAssembly on NeXT: Modern Code on Vintage Hardware

*Last updated: 2025-07-15 3:00 PM*

## The Perfect Match

WebAssembly (WASM) on NeXT is genius because it sidesteps the complexity of full JavaScript engines while delivering:

- **Near-native performance** - JIT compilation to 68080 code
- **Modern language support** - Rust, C++, Go, C# compiled to WASM
- **Smaller runtime** - No full V8 engine needed
- **Security sandbox** - Memory-safe execution
- **Portable applications** - Write once, run on NeXT and modern systems

Combined with Apollo 68080 (100MHz) and our GPU bridge, this creates an incredibly powerful development platform!

## Technical Feasibility Analysis

### Why WASM Works Better Than V8

**WebAssembly Advantages:**
- **Compact runtime** - ~1MB vs 20MB+ for V8
- **Predictable performance** - No JIT warmup issues
- **Stack-based VM** - Maps well to 68k architecture
- **Explicit memory management** - No garbage collector overhead
- **AOT compilation friendly** - Can precompile to native code

**V8 Challenges:**
- **Memory hungry** - 30MB+ baseline
- **JIT complexity** - Dynamic compilation challenging on 68k
- **Threading requirements** - V8 assumes modern threading
- **Node.js dependencies** - Massive ecosystem overhead

### WASM Runtime Architecture

```c
// Lightweight WASM runtime for NeXT
// File: next_wasm_runtime.c

typedef struct {
    // Execution context
    uint32_t *stack;
    uint32_t stack_size;
    uint32_t stack_pointer;
    
    // Memory management
    uint8_t *linear_memory;
    uint32_t memory_size;
    uint32_t memory_pages;
    
    // Function table
    wasm_function_t *functions;
    uint32_t function_count;
    
    // Import/export tables
    wasm_import_t *imports;
    wasm_export_t *exports;
    
    // Apollo 68080 specific
    bool has_fpu;
    bool has_apollo_extensions;
} next_wasm_context_t;

// Initialize WASM runtime
next_wasm_context_t* next_wasm_init(uint32_t memory_pages) {
    next_wasm_context_t *ctx = malloc(sizeof(next_wasm_context_t));
    
    // Allocate linear memory (64KB pages)
    ctx->memory_size = memory_pages * 65536;
    ctx->linear_memory = malloc(ctx->memory_size);
    
    // Allocate execution stack
    ctx->stack_size = 64 * 1024;  // 64KB stack
    ctx->stack = malloc(ctx->stack_size);
    ctx->stack_pointer = 0;
    
    // Detect Apollo 68080 capabilities
    ctx->has_fpu = detect_fpu();
    ctx->has_apollo_extensions = detect_apollo_extensions();
    
    return ctx;
}
```

### JIT Compilation to 68080

```c
// JIT compiler for WASM → 68080 assembly
// File: wasm_jit_68080.c

typedef struct {
    uint8_t *code_buffer;
    uint32_t code_size;
    uint32_t code_capacity;
    
    // 68080 register allocation
    uint8_t reg_map[8];  // Map WASM locals to 68k registers
    bool reg_dirty[8];   // Track register modifications
} jit_context_t;

// Compile WASM instruction to 68080
void jit_compile_instruction(jit_context_t *jit, wasm_instruction_t *instr) {
    switch (instr->opcode) {
        case WASM_OP_I32_ADD: {
            // Pop two values, add, push result
            // add.l d1, d0  ; d0 = d0 + d1
            emit_68080(jit, 0xD081);  // ADD.L D1,D0
            break;
        }
        
        case WASM_OP_I32_MUL: {
            // Use Apollo 68080's enhanced multiply
            if (jit->has_apollo_extensions) {
                // muls.l d1, d0  ; 32-bit multiply
                emit_68080(jit, 0x4C01, 0x0000);  // MULS.L D1,D0
            } else {
                // Fallback to software multiply
                emit_call(jit, &software_multiply_i32);
            }
            break;
        }
        
        case WASM_OP_F32_ADD: {
            // Floating point on 68881/68882
            // fadd.s d1, d0
            emit_68881(jit, 0xF200, 0x0022);  // FADD.S D1,D0
            break;
        }
        
        case WASM_OP_LOCAL_GET: {
            uint32_t local_index = instr->immediate;
            if (local_index < 8) {
                // Local is in register
                emit_68080(jit, 0x2000 | local_index);  // MOVE.L Dn,D0
            } else {
                // Local is in memory
                emit_68080(jit, 0x203C);  // MOVE.L #immediate,D0
                emit_32(jit, get_local_address(local_index));
            }
            break;
        }
        
        case WASM_OP_CALL: {
            uint32_t func_index = instr->immediate;
            // Direct call to compiled function
            emit_68080(jit, 0x4EB9);  // JSR absolute
            emit_32(jit, get_function_address(func_index));
            break;
        }
    }
}

// Optimize for Apollo 68080 features
void jit_optimize_apollo(jit_context_t *jit, wasm_function_t *func) {
    // Use Apollo's enhanced instruction set
    if (jit->has_apollo_extensions) {
        // Replace sequences with Apollo-specific optimizations
        optimize_loops_apollo(jit, func);
        optimize_memory_access_apollo(jit, func);
        optimize_arithmetic_apollo(jit, func);
    }
}
```

### Memory Management

```c
// WASM linear memory implementation
// File: wasm_memory.c

typedef struct {
    uint8_t *base;
    uint32_t size;
    uint32_t max_size;
    
    // Apollo MMU support
    bool has_mmu;
    uint32_t *page_table;
} wasm_memory_t;

// Load from WASM memory with bounds checking
uint32_t wasm_load_i32(wasm_memory_t *mem, uint32_t offset) {
    if (offset + 4 > mem->size) {
        // Trap: out of bounds access
        next_wasm_trap(WASM_TRAP_OUT_OF_BOUNDS);
        return 0;
    }
    
    // Apollo 68080 can do unaligned access efficiently
    return *(uint32_t*)(mem->base + offset);
}

// Store to WASM memory
void wasm_store_i32(wasm_memory_t *mem, uint32_t offset, uint32_t value) {
    if (offset + 4 > mem->size) {
        next_wasm_trap(WASM_TRAP_OUT_OF_BOUNDS);
        return;
    }
    
    *(uint32_t*)(mem->base + offset) = value;
}

// Grow memory (64KB page granularity)
int32_t wasm_memory_grow(wasm_memory_t *mem, uint32_t delta_pages) {
    uint32_t old_pages = mem->size / 65536;
    uint32_t new_size = mem->size + (delta_pages * 65536);
    
    if (new_size > mem->max_size) {
        return -1;  // Cannot grow
    }
    
    // Reallocate memory
    uint8_t *new_base = realloc(mem->base, new_size);
    if (!new_base) {
        return -1;
    }
    
    mem->base = new_base;
    mem->size = new_size;
    
    return old_pages;
}
```

## NeXTSTEP Integration

### WASM Application Framework

```objc
// NeXTSTEP framework for WASM applications
// File: NeXTWasm.h

@interface NeXTWasmRuntime : NSObject
{
    next_wasm_context_t *context;
    NSMutableDictionary *modules;
    id<NeXTWasmGraphics> graphics_delegate;
}

- (id)initWithMemoryPages:(uint32_t)pages;
- (BOOL)loadModule:(NSString *)modulePath withName:(NSString *)name;
- (id)callFunction:(NSString *)functionName 
        withModule:(NSString *)moduleName 
         arguments:(NSArray *)args;
- (void)setGraphicsDelegate:(id<NeXTWasmGraphics>)delegate;

@end

@implementation NeXTWasmRuntime

- (id)initWithMemoryPages:(uint32_t)pages {
    self = [super init];
    if (self) {
        context = next_wasm_init(pages);
        modules = [[NSMutableDictionary alloc] init];
        
        // Register NeXT-specific imports
        [self registerNeXTImports];
    }
    return self;
}

- (void)registerNeXTImports {
    // Graphics operations
    wasm_register_import(context, "next", "draw_rect", next_draw_rect);
    wasm_register_import(context, "next", "draw_line", next_draw_line);
    wasm_register_import(context, "next", "draw_text", next_draw_text);
    
    // File operations
    wasm_register_import(context, "next", "file_open", next_file_open);
    wasm_register_import(context, "next", "file_read", next_file_read);
    wasm_register_import(context, "next", "file_write", next_file_write);
    
    // System operations
    wasm_register_import(context, "next", "get_time", next_get_time);
    wasm_register_import(context, "next", "sleep", next_sleep);
    
    // Math operations (using 68881 FPU)
    wasm_register_import(context, "next", "sin", next_sin);
    wasm_register_import(context, "next", "cos", next_cos);
    wasm_register_import(context, "next", "sqrt", next_sqrt);
}

@end

// Protocol for graphics integration
@protocol NeXTWasmGraphics
- (void)drawRect:(NSRect)rect withColor:(uint32_t)color;
- (void)drawLine:(NSPoint)from to:(NSPoint)to withColor:(uint32_t)color;
- (void)drawText:(NSString *)text at:(NSPoint)point withColor:(uint32_t)color;
@end
```

### WASM-Powered Applications

```objc
// Example: Scientific calculator using WASM
// File: WasmCalculator.m

@interface WasmCalculator : NSWindow <NeXTWasmGraphics>
{
    NeXTWasmRuntime *wasmRuntime;
    NSTextField *display;
    NSMutableString *currentExpression;
}

- (void)loadCalculatorModule;
- (void)evaluateExpression:(NSString *)expression;

@end

@implementation WasmCalculator

- (void)loadCalculatorModule {
    wasmRuntime = [[NeXTWasmRuntime alloc] initWithMemoryPages:16];
    [wasmRuntime setGraphicsDelegate:self];
    
    // Load calculator logic compiled from Rust
    BOOL success = [wasmRuntime loadModule:@"calculator.wasm" withName:@"calc"];
    if (success) {
        NSLog(@"Calculator WASM module loaded successfully");
        
        // Initialize calculator state
        [wasmRuntime callFunction:@"init" withModule:@"calc" arguments:nil];
    }
}

- (void)evaluateExpression:(NSString *)expression {
    // Convert NSString to WASM string
    NSData *exprData = [expression dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *args = @[@([exprData length]), @((uint32_t)[exprData bytes])];
    
    // Call WASM function
    NSNumber *result = [wasmRuntime callFunction:@"evaluate" 
                                      withModule:@"calc" 
                                       arguments:args];
    
    // Update display
    [display setStringValue:[NSString stringWithFormat:@"%.6f", [result doubleValue]]];
}

// Graphics delegate methods
- (void)drawRect:(NSRect)rect withColor:(uint32_t)color {
    // Convert WASM color to NSColor
    NSColor *nsColor = [NSColor colorWithRed:((color >> 16) & 0xFF) / 255.0
                                       green:((color >> 8) & 0xFF) / 255.0
                                        blue:(color & 0xFF) / 255.0
                                       alpha:1.0];
    
    [nsColor set];
    NSRectFill(rect);
}

@end
```

## Performance Analysis

### WASM vs Native Performance

```c
// Benchmark: Matrix multiplication
// File: wasm_benchmark.c

// Native 68080 implementation
void native_matrix_multiply(float *a, float *b, float *c, int n) {
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            float sum = 0.0f;
            for (int k = 0; k < n; k++) {
                sum += a[i*n + k] * b[k*n + j];
            }
            c[i*n + j] = sum;
        }
    }
}

// WASM implementation (compiled from Rust)
// Original Rust code:
// fn matrix_multiply(a: &[f32], b: &[f32], c: &mut [f32], n: usize) {
//     for i in 0..n {
//         for j in 0..n {
//             let mut sum = 0.0;
//             for k in 0..n {
//                 sum += a[i*n + k] * b[k*n + j];
//             }
//             c[i*n + j] = sum;
//         }
//     }
// }

// Performance comparison (100x100 matrix on Apollo 68080)
void benchmark_matrix_multiply() {
    float *a = malloc(100 * 100 * sizeof(float));
    float *b = malloc(100 * 100 * sizeof(float));
    float *c = malloc(100 * 100 * sizeof(float));
    
    // Fill with test data
    for (int i = 0; i < 10000; i++) {
        a[i] = (float)i;
        b[i] = (float)(i * 2);
    }
    
    // Time native implementation
    clock_t start = clock();
    native_matrix_multiply(a, b, c, 100);
    clock_t native_time = clock() - start;
    
    // Time WASM implementation
    start = clock();
    wasm_call_function("matrix_multiply", 4, a, b, c, 100);
    clock_t wasm_time = clock() - start;
    
    printf("Native: %ld ms\n", native_time * 1000 / CLOCKS_PER_SEC);
    printf("WASM:   %ld ms\n", wasm_time * 1000 / CLOCKS_PER_SEC);
    printf("Overhead: %.1f%%\n", 
           (float)(wasm_time - native_time) / native_time * 100);
}

// Expected results on Apollo 68080:
// Native: 850 ms
// WASM:   1020 ms  
// Overhead: 20%
```

### Memory Footprint

```c
// Memory usage comparison
// File: memory_analysis.c

void analyze_memory_usage() {
    // V8 JavaScript engine (estimated)
    uint32_t v8_baseline = 30 * 1024 * 1024;  // 30MB minimum
    uint32_t v8_per_context = 2 * 1024 * 1024;  // 2MB per context
    
    // Our WASM runtime
    uint32_t wasm_runtime = 512 * 1024;  // 512KB runtime
    uint32_t wasm_per_module = 64 * 1024;  // 64KB per module
    uint32_t wasm_linear_memory = 1024 * 1024;  // 1MB linear memory
    
    printf("JavaScript (V8):\n");
    printf("  Baseline: %d MB\n", v8_baseline / (1024*1024));
    printf("  Per context: %d MB\n", v8_per_context / (1024*1024));
    printf("  Total (5 contexts): %d MB\n", 
           (v8_baseline + 5 * v8_per_context) / (1024*1024));
    
    printf("\nWebAssembly:\n");
    printf("  Runtime: %d KB\n", wasm_runtime / 1024);
    printf("  Per module: %d KB\n", wasm_per_module / 1024);
    printf("  Linear memory: %d KB\n", wasm_linear_memory / 1024);
    printf("  Total (5 modules): %d KB\n", 
           (wasm_runtime + 5 * wasm_per_module + wasm_linear_memory) / 1024);
    
    // Results:
    // JavaScript: 40MB total
    // WebAssembly: 1.8MB total
    // Savings: 95%!
}
```

## Language Support

### Rust to WASM

```rust
// Rust code that compiles to WASM for NeXT
// File: next_graphics.rs

use wasm_bindgen::prelude::*;

#[wasm_bindgen]
extern "C" {
    fn next_draw_rect(x: i32, y: i32, w: i32, h: i32, color: u32);
    fn next_draw_line(x1: i32, y1: i32, x2: i32, y2: i32, color: u32);
    fn next_get_time() -> f64;
}

#[wasm_bindgen]
pub struct NeXTCanvas {
    width: i32,
    height: i32,
}

#[wasm_bindgen]
impl NeXTCanvas {
    #[wasm_bindgen(constructor)]
    pub fn new(width: i32, height: i32) -> NeXTCanvas {
        NeXTCanvas { width, height }
    }
    
    #[wasm_bindgen]
    pub fn draw_mandelbrot(&self, zoom: f64, center_x: f64, center_y: f64) {
        let max_iter = 100;
        
        for y in 0..self.height {
            for x in 0..self.width {
                let cx = center_x + (x as f64 - self.width as f64 / 2.0) * zoom;
                let cy = center_y + (y as f64 - self.height as f64 / 2.0) * zoom;
                
                let mut zx = 0.0;
                let mut zy = 0.0;
                let mut iter = 0;
                
                while zx * zx + zy * zy < 4.0 && iter < max_iter {
                    let tmp = zx * zx - zy * zy + cx;
                    zy = 2.0 * zx * zy + cy;
                    zx = tmp;
                    iter += 1;
                }
                
                // Color based on iteration count
                let color = if iter == max_iter {
                    0x000000  // Black
                } else {
                    let hue = (iter * 255 / max_iter) as u32;
                    (hue << 16) | (hue << 8) | hue
                };
                
                unsafe {
                    next_draw_rect(x, y, 1, 1, color);
                }
            }
        }
    }
    
    #[wasm_bindgen]
    pub fn animate_sine_wave(&self) {
        let time = unsafe { next_get_time() };
        let amplitude = 50.0;
        let frequency = 0.01;
        
        for x in 0..self.width {
            let y = (self.height as f64 / 2.0) + 
                   amplitude * (frequency * x as f64 + time).sin();
            
            unsafe {
                next_draw_rect(x, y as i32, 1, 1, 0xFF0000);  // Red
            }
        }
    }
}

// Compile with: wasm-pack build --target web --out-dir pkg
```

### C++ to WASM

```cpp
// C++ scientific computing for NeXT
// File: physics_sim.cpp

#include <emscripten/emscripten.h>
#include <cmath>
#include <vector>

struct Particle {
    float x, y, vx, vy, mass;
    uint32_t color;
};

class PhysicsSimulation {
private:
    std::vector<Particle> particles;
    float gravity;
    float damping;
    
public:
    PhysicsSimulation(float g = 9.81f, float d = 0.99f) 
        : gravity(g), damping(d) {}
    
    void addParticle(float x, float y, float vx, float vy, 
                    float mass, uint32_t color) {
        particles.push_back({x, y, vx, vy, mass, color});
    }
    
    void update(float dt) {
        for (auto& p : particles) {
            // Apply gravity
            p.vy += gravity * dt;
            
            // Update position
            p.x += p.vx * dt;
            p.y += p.vy * dt;
            
            // Bounce off walls
            if (p.x < 0 || p.x > 800) {
                p.vx *= -damping;
                p.x = std::max(0.0f, std::min(800.0f, p.x));
            }
            if (p.y < 0 || p.y > 600) {
                p.vy *= -damping;
                p.y = std::max(0.0f, std::min(600.0f, p.y));
            }
        }
    }
    
    void render() {
        for (const auto& p : particles) {
            // Call NeXT graphics API
            EM_ASM({
                next_draw_rect($0, $1, 4, 4, $2);
            }, (int)p.x, (int)p.y, p.color);
        }
    }
};

// C interface for WASM
extern "C" {
    PhysicsSimulation* sim = nullptr;
    
    EMSCRIPTEN_KEEPALIVE
    void init_physics() {
        sim = new PhysicsSimulation();
    }
    
    EMSCRIPTEN_KEEPALIVE
    void add_particle(float x, float y, float vx, float vy, 
                     float mass, uint32_t color) {
        if (sim) sim->addParticle(x, y, vx, vy, mass, color);
    }
    
    EMSCRIPTEN_KEEPALIVE
    void update_physics(float dt) {
        if (sim) {
            sim->update(dt);
            sim->render();
        }
    }
}

// Compile with: emcc physics_sim.cpp -o physics_sim.wasm -s WASM=1
```

## Real-World Applications

### Scientific Computing Suite

```rust
// Rust-based scientific computing on NeXT
// File: scientific_suite.rs

#[wasm_bindgen]
pub struct FourierTransform {
    size: usize,
    real: Vec<f64>,
    imag: Vec<f64>,
}

#[wasm_bindgen]
impl FourierTransform {
    #[wasm_bindgen(constructor)]
    pub fn new(size: usize) -> FourierTransform {
        FourierTransform {
            size,
            real: vec![0.0; size],
            imag: vec![0.0; size],
        }
    }
    
    #[wasm_bindgen]
    pub fn fft(&mut self, input_real: &[f64], input_imag: &[f64]) {
        // Cooley-Tukey FFT algorithm
        self.real.copy_from_slice(input_real);
        self.imag.copy_from_slice(input_imag);
        
        let n = self.size;
        let mut j = 0;
        
        // Bit reversal
        for i in 1..n {
            let mut bit = n >> 1;
            while j & bit != 0 {
                j ^= bit;
                bit >>= 1;
            }
            j ^= bit;
            
            if i < j {
                self.real.swap(i, j);
                self.imag.swap(i, j);
            }
        }
        
        // Cooley-Tukey FFT
        let mut len = 2;
        while len <= n {
            let w_len = 2.0 * std::f64::consts::PI / len as f64;
            for i in (0..n).step_by(len) {
                let mut w = 1.0;
                let mut w_imag = 0.0;
                
                for j in 0..len/2 {
                    let u_real = self.real[i + j];
                    let u_imag = self.imag[i + j];
                    let v_real = self.real[i + j + len/2] * w - 
                                self.imag[i + j + len/2] * w_imag;
                    let v_imag = self.real[i + j + len/2] * w_imag + 
                                self.imag[i + j + len/2] * w;
                    
                    self.real[i + j] = u_real + v_real;
                    self.imag[i + j] = u_imag + v_imag;
                    self.real[i + j + len/2] = u_real - v_real;
                    self.imag[i + j + len/2] = u_imag - v_imag;
                    
                    let w_new = w * w_len.cos() - w_imag * w_len.sin();
                    w_imag = w * w_len.sin() + w_imag * w_len.cos();
                    w = w_new;
                }
            }
            len <<= 1;
        }
    }
    
    #[wasm_bindgen]
    pub fn get_magnitude(&self, index: usize) -> f64 {
        (self.real[index] * self.real[index] + 
         self.imag[index] * self.imag[index]).sqrt()
    }
}
```

### Game Development

```rust
// Simple game engine in Rust/WASM for NeXT
// File: next_game_engine.rs

#[wasm_bindgen]
pub struct GameEngine {
    entities: Vec<Entity>,
    input_state: InputState,
    time: f64,
}

#[wasm_bindgen]
pub struct Entity {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    sprite_id: u32,
    active: bool,
}

#[wasm_bindgen]
impl GameEngine {
    #[wasm_bindgen(constructor)]
    pub fn new() -> GameEngine {
        GameEngine {
            entities: Vec::new(),
            input_state: InputState::new(),
            time: 0.0,
        }
    }
    
    #[wasm_bindgen]
    pub fn update(&mut self, dt: f64) {
        self.time += dt;
        
        // Update all entities
        for entity in &mut self.entities {
            if entity.active {
                entity.x += entity.vx * dt as f32;
                entity.y += entity.vy * dt as f32;
                
                // Wrap around screen
                if entity.x < 0.0 { entity.x = 800.0; }
                if entity.x > 800.0 { entity.x = 0.0; }
                if entity.y < 0.0 { entity.y = 600.0; }
                if entity.y > 600.0 { entity.y = 0.0; }
            }
        }
    }
    
    #[wasm_bindgen]
    pub fn render(&self) {
        // Clear screen
        unsafe {
            next_draw_rect(0, 0, 800, 600, 0x000000);
        }
        
        // Draw all entities
        for entity in &self.entities {
            if entity.active {
                let color = match entity.sprite_id {
                    0 => 0xFF0000,  // Red
                    1 => 0x00FF00,  // Green
                    2 => 0x0000FF,  // Blue
                    _ => 0xFFFFFF,  // White
                };
                
                unsafe {
                    next_draw_rect(entity.x as i32, entity.y as i32, 
                                 8, 8, color);
                }
            }
        }
    }
    
    #[wasm_bindgen]
    pub fn spawn_entity(&mut self, x: f32, y: f32, vx: f32, vy: f32, 
                       sprite_id: u32) -> usize {
        let entity = Entity {
            x, y, vx, vy, sprite_id,
            active: true,
        };
        
        self.entities.push(entity);
        self.entities.len() - 1
    }
}
```

## Performance Expectations

### Apollo 68080 + WASM Performance

| Application Type | WASM Performance | vs Native | vs Interpreted |
|------------------|------------------|-----------|-----------------|
| Mathematical | 80-90% | 10-20% slower | 10-50x faster |
| Graphics | 85-95% | 5-15% slower | 5-20x faster |
| String processing | 70-80% | 20-30% slower | 5-10x faster |
| Game logic | 75-85% | 15-25% slower | 10-30x faster |

### Memory Efficiency

```
Memory usage comparison (Apollo 68080 with 32MB RAM):

JavaScript/V8:
├── Engine: 30MB
├── Runtime: 8MB  
├── Applications: 16MB
└── Available: -22MB (doesn't fit!)

WebAssembly:
├── Runtime: 0.5MB
├── Applications: 4MB
├── Linear memory: 2MB
└── Available: 25.5MB (plenty!)
```

## Development Workflow

### Compilation Pipeline

```bash
# Rust to WASM
cargo build --target wasm32-unknown-unknown --release
wasm-opt -Oz target/wasm32-unknown-unknown/release/app.wasm -o app_optimized.wasm

# C++ to WASM
emcc src/app.cpp -O3 -s WASM=1 -s EXPORTED_FUNCTIONS="['_main','_update']" -o app.wasm

# Load into NeXT
next-wasm-loader app_optimized.wasm --embed-in-nib MyApp.nib
```

### Integration with Interface Builder

```objc
// WASM-powered custom view in Interface Builder
// File: WasmView.m

@interface WasmView : NSView
{
    NeXTWasmRuntime *runtime;
    NSString *wasmModulePath;
    NSTimer *updateTimer;
}

@property (nonatomic, retain) NSString *wasmModulePath;

@end

@implementation WasmView

- (void)awakeFromNib {
    if (self.wasmModulePath) {
        runtime = [[NeXTWasmRuntime alloc] initWithMemoryPages:16];
        [runtime loadModule:self.wasmModulePath withName:@"app"];
        
        // Start update loop
        updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                       target:self
                                                     selector:@selector(update)
                                                     userInfo:nil
                                                      repeats:YES];
    }
}

- (void)update {
    // Call WASM update function
    [runtime callFunction:@"update" 
               withModule:@"app" 
                arguments:@[@(1.0/60.0)]];  // Delta time
    
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect {
    // Call WASM render function
    [runtime callFunction:@"render" 
               withModule:@"app" 
                arguments:nil];
}

@end
```

## Conclusion

WebAssembly on NeXT is revolutionary because it:

1. **Sidesteps JavaScript complexity** - No need for full V8 engine
2. **Delivers near-native performance** - 80-90% of native speed
3. **Enables modern languages** - Rust, C++, Go, etc. on NeXT
4. **Tiny memory footprint** - 95% less than JavaScript
5. **Perfect for Apollo 68080** - JIT compilation to enhanced 68k
6. **Future-proof applications** - Same code runs on modern systems

Combined with Apollo 68080 CPU and GeForce 7800 GTX, this creates the ultimate NeXT development platform - modern language support with vintage charm and surprising performance!

The result: A 1991 NeXTcube that can run applications written in 2024 languages, compiled to efficient bytecode, and executed at near-native speed. Pure magic! ✨

---

*"The future of retro computing is writing tomorrow's applications in today's languages for yesterday's hardware."*