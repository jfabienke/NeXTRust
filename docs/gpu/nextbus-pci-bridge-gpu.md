# NeXTBus-to-PCI Bridge: Real GeForce 7800 GTX in NeXTcube

*Last updated: 2025-07-15 2:45 PM*

## The Practical Revolution

Instead of implementing an entire GPU in FPGA, we create a NeXTBus-to-PCI bridge that allows a real GeForce 7800 GTX to work in a NeXTcube. This approach gives us:

- **Full hardware performance** of the actual GPU
- **Proven silicon** with known characteristics  
- **Existing Nouveau drivers** to adapt
- **Simpler FPGA design** focused on bus translation
- **Real-world compatibility** with actual GPU firmware

Combined with the Apollo 68080 CPU accelerator, this creates the ultimate NeXT workstation!

## Technical Architecture

### NeXTBus-to-PCI Bridge Design

```verilog
// FPGA-based bridge between NeXT and PCI worlds
module nextbus_pci_bridge (
    // NeXT bus interface
    input  [31:0] next_addr,
    input  [31:0] next_data_in,
    output [31:0] next_data_out,
    input         next_strobe,
    input         next_write,
    output        next_ack,
    input         next_burst,
    
    // PCI interface  
    inout  [31:0] pci_ad,
    inout  [3:0]  pci_cbe,
    inout         pci_frame_n,
    inout         pci_irdy_n,
    inout         pci_trdy_n,
    inout         pci_stop_n,
    input         pci_clk,
    input         pci_rst_n,
    
    // Configuration and control
    input         bridge_enable,
    output [7:0]  bridge_status
);

// Address translation logic
address_translator addr_xlat (
    .next_addr(next_addr),
    .pci_addr(translated_addr),
    .translation_table(addr_map_table)
);

// Protocol conversion
protocol_converter proto_conv (
    // NeXT side
    .next_strobe(next_strobe),
    .next_write(next_write),
    .next_burst(next_burst),
    .next_ack(next_ack),
    
    // PCI side
    .pci_frame_n(pci_frame_n),
    .pci_irdy_n(pci_irdy_n),
    .pci_trdy_n(pci_trdy_n)
);

// Data buffering for performance
data_buffer buffer (
    .next_clk(next_clk),        // ~25MHz NeXT bus
    .pci_clk(pci_clk),          // 33MHz PCI bus
    .buffer_data(buffered_data),
    .buffer_control(buffer_ctrl)
);

endmodule
```

### Address Space Mapping

```verilog
// Memory map translation between NeXT and PCI address spaces
module address_translator (
    input  [31:0] next_addr,
    output [31:0] pci_addr,
    input  [31:0] translation_table [15:0]
);

always @(*) begin
    case (next_addr[31:28])
        4'h0: begin
            // NeXT system RAM - no translation needed
            pci_addr = 32'h00000000;  // Invalid for GPU
        end
        
        4'h2: begin 
            // NeXT device space -> PCI memory space
            // Map NeXT 0x2000_0000 to PCI 0xF000_0000 (GPU VRAM)
            pci_addr = {4'hF, next_addr[27:0]};
        end
        
        4'h3: begin
            // NeXT I/O space -> PCI configuration space
            // Map NeXT 0x3000_0000 to PCI config (GPU registers)
            pci_addr = {8'h00, next_addr[23:0]};
        end
        
        default: begin
            pci_addr = 32'h00000000;  // Invalid
        end
    endcase
end

endmodule
```

### Bus Protocol Conversion

```verilog
// Convert NeXT bus transactions to PCI transactions
module protocol_converter (
    // NeXT protocol signals
    input         next_strobe,
    input         next_write,
    input         next_burst,
    output reg    next_ack,
    
    // PCI protocol signals
    output reg    pci_frame_n,
    output reg    pci_irdy_n,
    input         pci_trdy_n,
    input         pci_stop_n,
    
    // Control
    input         clk,
    input         reset_n
);

typedef enum {
    IDLE,
    PCI_ADDRESS,
    PCI_DATA,
    PCI_TURNAROUND,
    NEXT_ACK
} state_t;

state_t current_state, next_state;

// State machine for protocol conversion
always @(posedge clk) begin
    if (!reset_n) begin
        current_state <= IDLE;
        next_ack <= 1'b0;
        pci_frame_n <= 1'b1;
        pci_irdy_n <= 1'b1;
    end else begin
        case (current_state)
            IDLE: begin
                if (next_strobe) begin
                    // Start PCI transaction
                    pci_frame_n <= 1'b0;
                    current_state <= PCI_ADDRESS;
                end
            end
            
            PCI_ADDRESS: begin
                // Assert IRDY to indicate valid address
                pci_irdy_n <= 1'b0;
                pci_frame_n <= 1'b1;  // Deassert FRAME
                current_state <= PCI_DATA;
            end
            
            PCI_DATA: begin
                // Wait for target ready
                if (!pci_trdy_n) begin
                    current_state <= PCI_TURNAROUND;
                end
            end
            
            PCI_TURNAROUND: begin
                // Complete PCI transaction
                pci_irdy_n <= 1'b1;
                current_state <= NEXT_ACK;
            end
            
            NEXT_ACK: begin
                // Acknowledge to NeXT bus
                next_ack <= 1'b1;
                current_state <= IDLE;
                next_ack <= 1'b0;  // Single cycle ack
            end
        endcase
    end
end

endmodule
```

## Hardware Implementation

### Bridge Card Design

```
NeXT-PCI Bridge Card Layout:
┌─────────────────────────────────────┐
│  NeXT Bus Connector (96-pin)        │
├─────────────────────────────────────┤
│  Xilinx Spartan-7 FPGA             │  <- Bridge logic
│  (XC7S50)                           │     + Configuration
├─────────────────────────────────────┤
│  PCI Slot (32-bit, 33MHz)           │  <- GeForce 7800 GTX
├─────────────────────────────────────┤
│  Level shifters (5V ↔ 3.3V)        │  <- Voltage compatibility
├─────────────────────────────────────┤
│  Configuration EEPROM               │  <- Bridge settings
├─────────────────────────────────────┤
│  Power regulation                   │  <- +12V, +5V, +3.3V for GPU
└─────────────────────────────────────┘
```

### Power Requirements

```
Power Budget Analysis:
- GeForce 7800 GTX: 110W (max)
- FPGA Bridge: 5W
- Total: 115W

NeXT Power Supply:
- +5V: 6A available → 30W
- +12V: 8A available → 96W  
- -12V: 1A available → 12W
- Total available: ~138W

Verdict: NeXT PSU can handle the load!
```

### Physical Form Factor

```
Mechanical Design:
┌─────────────────────────┐
│     NeXT Slot Card      │  <- Fits in NeXT expansion slot
│                         │
│  ┌─────────────────┐    │
│  │   PCI Socket    │    │  <- Standard PCI card socket
│  │                 │    │
│  │  GeForce 7800   │    │  <- Full-size GPU card
│  │      GTX        │    │
│  │                 │    │
│  └─────────────────┘    │
│                         │
│   FPGA + Support        │
└─────────────────────────┘

Dimensions: Fits in NeXT Turbo slot (longest slot)
```

## OpenFirmware Adaptation

### Reverse Engineering the GPU BIOS

```c
// Analyzing GeForce 7800 GTX OpenFirmware
// File: gf7800_of_analysis.c

typedef struct {
    uint32_t signature;       // "NVGI" or similar
    uint16_t version;
    uint16_t header_size;
    uint32_t init_script_ptr;
    uint32_t macro_index_ptr;
    uint32_t macro_table_ptr;
    uint32_t condition_table_ptr;
    uint32_t io_condition_ptr;
    uint32_t io_flag_condition_ptr;
    uint32_t init_function_ptr;
} nvidia_bios_header_t;

// Parse the initialization scripts
int parse_nvidia_init_script(uint8_t *bios_data, uint32_t script_offset) {
    uint8_t *script = bios_data + script_offset;
    
    while (*script != 0x71) {  // End-of-script marker
        uint8_t opcode = *script++;
        
        switch (opcode) {
            case 0x32: {  // IO write
                uint16_t port = *(uint16_t*)script; script += 2;
                uint32_t value = *(uint32_t*)script; script += 4;
                printf("IO Write: port=0x%04x, value=0x%08x\n", port, value);
                break;
            }
            
            case 0x33: {  // Memory write
                uint32_t addr = *(uint32_t*)script; script += 4;
                uint32_t value = *(uint32_t*)script; script += 4;
                printf("Mem Write: addr=0x%08x, value=0x%08x\n", addr, value);
                break;
            }
            
            case 0x5B: {  // Condition
                uint16_t reg = *(uint16_t*)script; script += 2;
                uint32_t mask = *(uint32_t*)script; script += 4;
                uint32_t compare = *(uint32_t*)script; script += 4;
                printf("Condition: reg=0x%04x, mask=0x%08x, cmp=0x%08x\n", 
                       reg, mask, compare);
                break;
            }
        }
    }
    
    return 0;
}
```

### NeXT OpenFirmware Integration

```forth
\ NeXT OpenFirmware driver for GeForce 7800 GTX
\ File: gf7800-next.of

" display" device-name
" pci" device-type

\ Properties for NeXT boot process
my-address my-space 1000000 reg   \ Base address and size
d# 8 encode-int " width" property  \ 8 bits per pixel initially
d# 32 encode-int " depth" property

\ PCI configuration
: map-pci-memory  ( -- )
    \ Map GPU memory spaces
    my-space 10 + " assigned-addresses" get-property if
        \ Fallback: use default mapping
        my-space 10 or -1 next-virtual 1000000 map-in
    else
        decode-int nip nip  \ Get base address
        dup 1000000 map-in
    then
    to gfx-base
;

\ Initialize GPU hardware
: init-gf7800  ( -- )
    \ Reset GPU
    gfx-base 200 + 1 swap l!  \ Assert reset
    100 ms                    \ Wait 100ms
    gfx-base 200 + 0 swap l!  \ Release reset
    
    \ Configure memory controller
    gfx-base 100140 + 00000000 swap l!  \ Memory config
    gfx-base 100144 + 12345678 swap l!  \ Memory timing
    
    \ Set up display mode
    init-display-mode
    
    \ Enable accelerated 2D operations
    init-2d-engine
;

\ Set up display mode for NeXT
: init-display-mode  ( -- )
    \ Configure for 1120x832 (NeXT standard)
    gfx-base 600800 + 460 swap l!      \ Horizontal total
    gfx-base 600804 + 340 swap l!      \ Horizontal active (1120)
    gfx-base 600808 + 420 swap l!      \ Vertical total
    gfx-base 60080C + 340 swap l!      \ Vertical active (832)
    
    \ Set pixel format
    gfx-base 600900 + 5 swap l!        \ 32-bit ARGB
    
    \ Configure framebuffer
    gfx-base 800000 + to frame-buffer-adr
    1120 832 * 4 * to fb-size
;

\ 2D acceleration for NeXT graphics
: init-2d-engine  ( -- )
    \ Enable 2D context
    gfx-base 400000 + DEADBEEF swap l!  \ Context switch
    
    \ Set up clip rectangle
    gfx-base 40180C + 0 swap l!          \ Clip x,y
    gfx-base 401810 + 1120 832 + swap l! \ Clip width,height
    
    \ Configure solid fill
    gfx-base 401900 + 1 swap l!          \ Enable solid fill
;

\ Graphics operations for NeXT
: gf-fill-rect  ( x y w h color -- )
    gfx-base 401A00 + swap l!     \ Set color
    gfx-base 401A04 + swap l!     \ Set height  
    gfx-base 401A08 + swap l!     \ Set width
    gfx-base 401A0C + swap l!     \ Set y
    gfx-base 401A10 + swap l!     \ Set x, trigger operation
;

: gf-bitblt  ( src-x src-y dst-x dst-y w h -- )
    gfx-base 401B00 + swap l!     \ height
    gfx-base 401B04 + swap l!     \ width  
    gfx-base 401B08 + swap l!     \ dst-y
    gfx-base 401B0C + swap l!     \ dst-x
    gfx-base 401B10 + swap l!     \ src-y
    gfx-base 401B14 + swap l!     \ src-x, trigger blit
;

\ Install methods
" map-pci-memory" " map-in" 1 make-openfw-method
" init-gf7800" " init" 0 make-openfw-method
" gf-fill-rect" " fill-rectangle" 5 make-openfw-method
" gf-bitblt" " copy-rectangle" 6 make-openfw-method

\ Boot-time initialization
map-pci-memory
init-gf7800
" GeForce 7800 GTX initialized for NeXT" type cr
```

## Software Integration

### Enhanced Nouveau Driver

```c
// Enhanced Nouveau driver for NeXT bridge
// File: nouveau_next_bridge.c

#include <next/device_driver.h>
#include <nouveau/nouveau.h>

struct next_bridge_device {
    device_header_t header;
    
    // Bridge-specific fields
    volatile uint32_t *bridge_mmio;
    volatile uint32_t *gpu_mmio;
    
    // PCI configuration mirror
    uint32_t pci_config[64];
    
    // Performance monitoring
    uint32_t transactions_per_sec;
    uint32_t bridge_latency_us;
};

// Initialize bridge and GPU
int next_bridge_probe(device_t *dev) {
    struct next_bridge_device *bridge = (struct next_bridge_device *)dev;
    
    // Map bridge control registers
    bridge->bridge_mmio = map_device_memory(dev->base_address, 0x1000);
    
    // Configure bridge for PCI transactions
    bridge->bridge_mmio[BRIDGE_CONFIG] = 
        BRIDGE_ENABLE | 
        BRIDGE_PCI_MASTER |
        BRIDGE_BURST_MODE;
    
    // Scan for PCI GPU
    uint32_t gpu_vendor_id = bridge->bridge_mmio[PCI_VENDOR_ID];
    if (gpu_vendor_id == 0x10DE) {  // NVIDIA
        // Found GPU, map its memory space
        bridge->gpu_mmio = (volatile uint32_t *)(bridge->bridge_mmio + 0x100000);
        
        // Initialize Nouveau for the bridged GPU
        return init_nouveau_bridge(bridge);
    }
    
    return -1;  // No GPU found
}

// Bridge-aware memory operations
void bridge_gpu_write32(struct next_bridge_device *bridge, 
                       uint32_t offset, uint32_t value) {
    // Route through bridge with performance optimization
    if (bridge->bridge_mmio[BRIDGE_STATUS] & BRIDGE_FIFO_FULL) {
        // Wait for bridge FIFO space
        while (bridge->bridge_mmio[BRIDGE_STATUS] & BRIDGE_FIFO_FULL);
    }
    
    // Write through bridge
    bridge->gpu_mmio[offset / 4] = value;
    
    // Optional: Update performance counters
    bridge->transactions_per_sec++;
}

uint32_t bridge_gpu_read32(struct next_bridge_device *bridge, uint32_t offset) {
    // Ensure bridge is ready
    while (bridge->bridge_mmio[BRIDGE_STATUS] & BRIDGE_BUSY);
    
    return bridge->gpu_mmio[offset / 4];
}
```

### NeXTSTEP Graphics Integration

```objc
// NeXTSTEP graphics driver integration
// File: NeXTGeForce.m

@interface NeXTGeForce : NSGraphicsDevice
{
    struct next_bridge_device *bridge;
    void *opengl_context;
    BOOL hardware_acceleration_enabled;
}

- (id)initWithBridge:(struct next_bridge_device *)bridgeDevice;
- (void)setGraphicsState:(NSGraphicsState *)state;
- (void)drawRect:(NSRect)rect withColor:(NSColor *)color;
- (void)copyBitsFrom:(NSRect)src to:(NSRect)dst;

@end

@implementation NeXTGeForce

- (id)initWithBridge:(struct next_bridge_device *)bridgeDevice {
    self = [super init];
    if (self) {
        bridge = bridgeDevice;
        
        // Initialize OpenGL context
        opengl_context = create_opengl_context_bridge(bridge);
        hardware_acceleration_enabled = (opengl_context != NULL);
        
        NSLog(@"NeXT GeForce 7800 GTX: Hardware acceleration %@", 
              hardware_acceleration_enabled ? @"ENABLED" : @"disabled");
    }
    return self;
}

- (void)setGraphicsState:(NSGraphicsState *)state {
    if (hardware_acceleration_enabled) {
        // Use GPU for graphics operations
        bridge_gpu_write32(bridge, NV30_COLOR_CLEAR, [state.color rgbaValue]);
        bridge_gpu_write32(bridge, NV30_CLIP_RECT, NSRectToGPURect([state clipRect]));
    } else {
        // Fallback to software
        [super setGraphicsState:state];
    }
}

- (void)drawRect:(NSRect)rect withColor:(NSColor *)color {
    if (hardware_acceleration_enabled) {
        // Hardware-accelerated rectangle fill
        uint32_t gpu_color = NSColorToGPUColor(color);
        uint32_t gpu_rect = NSRectToGPURect(rect);
        
        bridge_gpu_write32(bridge, NV30_FILL_COLOR, gpu_color);
        bridge_gpu_write32(bridge, NV30_FILL_RECT, gpu_rect);
        bridge_gpu_write32(bridge, NV30_FILL_TRIGGER, 1);
    } else {
        [super drawRect:rect withColor:color];
    }
}

@end
```

## Apollo 68080 Integration

### Unified System Architecture

```
Complete NeXT Powerhouse System:
┌─────────────────────────────────────┐
│  Apollo 68080 CPU Card              │  <- 100MHz 68080 + modern features
├─────────────────────────────────────┤
│  NeXT-PCI Bridge Card               │  <- FPGA bridge logic
│    └── GeForce 7800 GTX             │  <- Real GPU hardware
├─────────────────────────────────────┤
│  Enhanced Memory Card               │  <- 256MB+ RAM
├─────────────────────────────────────┤
│  Modern Storage (CF/SD)             │  <- Fast, reliable storage
└─────────────────────────────────────┘

Performance:
- CPU: 100MHz 68080 (4x faster than 68040)
- GPU: GeForce 7800 GTX (2005 flagship)
- RAM: 256MB+ (128x standard NeXT)
- Storage: SSD-speed via CompactFlash
```

### Software Synergy

```c
// Optimized code for Apollo 68080 + GeForce combo
// File: apollo_geforce_optimization.c

// Take advantage of Apollo's enhanced caching
void apollo_optimized_graphics_loop(struct graphics_command *cmds, int count) {
    // Apollo 68080 has better cache - batch GPU commands
    struct gpu_command_batch batch;
    batch.count = 0;
    
    for (int i = 0; i < count; i++) {
        // Apollo's faster execution allows more complex batching
        switch (cmds[i].type) {
            case DRAW_LINE:
                batch.commands[batch.count++] = convert_to_gpu_line(&cmds[i]);
                break;
                
            case DRAW_RECT:
                batch.commands[batch.count++] = convert_to_gpu_rect(&cmds[i]);
                break;
                
            case BLIT:
                // Apollo can handle complex blit preprocessing
                optimize_blit_apollo(&cmds[i]);
                batch.commands[batch.count++] = convert_to_gpu_blit(&cmds[i]);
                break;
        }
        
        // Submit batch when full (Apollo can handle larger batches)
        if (batch.count >= 64) {
            submit_gpu_batch_bridge(&batch);
            batch.count = 0;
        }
    }
    
    // Submit remaining commands
    if (batch.count > 0) {
        submit_gpu_batch_bridge(&batch);
    }
}
```

## Performance Projections

### Ultimate NeXT Performance

| Component | Stock NeXTcube | Apollo + GeForce |
|-----------|---------------|------------------|
| CPU | 25MHz 68040 | 100MHz 68080 |
| CPU Performance | 18 MIPS | 120 MIPS |
| Graphics | Software only | GeForce 7800 GTX |
| 3D Performance | 0 fps | 60+ fps |
| Memory | 32MB max | 256MB+ |
| Storage | 400MB SCSI | 128GB CF |

### Real-World Applications

```objc
// Quake 3 Arena running smoothly on enhanced NeXT
@interface NeXTQuake3 : NSApplication {
    ApolloGPURenderer *renderer;
}
@end

@implementation NeXTQuake3

- (void)gameLoop {
    while (running) {
        // Apollo 68080: 4x faster game logic
        [self updateGameLogic];  // 25ms → 6ms
        
        // GeForce 7800: Hardware 3D rendering
        [renderer renderFrame];  // 60+ FPS
        
        // Perfect 60fps possible!
        usleep(16667);
    }
}

@end
```

## Development Roadmap

### Phase 1: Bridge Development (Months 1-4)
- [ ] FPGA bridge design and testing
- [ ] NeXT bus interface validation
- [ ] PCI protocol conversion
- [ ] Power and signal integrity

### Phase 2: GPU Integration (Months 5-8)
- [ ] GeForce 7800 GTX compatibility
- [ ] OpenFirmware reverse engineering
- [ ] NeXT boot integration
- [ ] Basic 2D acceleration

### Phase 3: Driver Development (Months 9-12)
- [ ] Nouveau driver adaptation
- [ ] NeXTSTEP graphics integration
- [ ] OpenGL implementation
- [ ] Performance optimization

### Phase 4: Apollo Integration (Months 13-15)
- [ ] Apollo 68080 compatibility testing
- [ ] Optimized driver paths
- [ ] System-level optimization
- [ ] Benchmark applications

### Phase 5: Applications (Months 16-18)
- [ ] Modern games porting
- [ ] CAD software enhancement
- [ ] Scientific applications
- [ ] Community release

## Bill of Materials

| Component | Part Number | Cost | Purpose |
|-----------|-------------|------|---------|
| Spartan-7 FPGA | XC7S50-FGGA484 | $60 | Bridge logic |
| GeForce 7800 GTX | Used card | $50 | Graphics processing |
| PCB (6-layer) | Custom NeXT form | $150 | Board design |
| Power regulation | Multiple ICs | $40 | Voltage conversion |
| Connectors | NeXT + PCI | $30 | Physical interface |
| Components | Passives, etc. | $20 | Support circuitry |
| **Total** | | **$350** | Complete solution |

## Conclusion

The NeXTBus-to-PCI bridge approach is brilliant because it:

1. **Leverages real GPU hardware** - Full GeForce 7800 GTX performance
2. **Simplifies development** - Focus on bus translation, not GPU implementation  
3. **Enables future upgrades** - Other PCI cards become possible
4. **Proves NeXT's expandability** - Shows the bus could handle modern hardware
5. **Combined with Apollo 68080** - Creates the ultimate NeXT system

This project would transform a 1991 NeXTcube into a system that outperforms many 2005-era PCs, proving that NeXT's architecture was so advanced it could seamlessly integrate hardware designed 14 years in its future!

---

*"The best retro computer is one that can run tomorrow's software today."*