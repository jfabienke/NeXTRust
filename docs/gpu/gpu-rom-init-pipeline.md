# GPU ROM Init Sequence Extraction Pipeline

*NeXTRust Project – v0.1 blueprint*

*Last updated: 2025-01-16 12:00 PM*

---

## 0. Purpose

A repeatable, legally safe pipeline that ingests proprietary GPU option-ROMs and emits minimal, public-domain JSON init sequences ready for the FPGA micro-sequencer and NeXTSTEP driver.

---

## 1. Architecture Overview

```
ROM sources ─┐      1 Harvest      2 Classify       3 Extract
             ▼
  raw_rom/ -> DB  →  sha_check     pci_header      code_blocks
                          │              │               │
                          ▼              ▼               ▼
                     4 Reduce  ─────→  canonical JSON  ──┐
                          │                             │
                SPDX + provenance   ◄────────────────────┘
                          │
                          ▼
                 5 Test-bench & dev-board validation
                          │
                          ▼
               6 Publish: json/, docs/, CI status badges
```

See §A for a full sequence diagram.

---

## A. Complete Pipeline Architecture

### A1. Seven-step flow

1. **Harvest** – Scrape TechPowerUp, Macintosh Repository, SunShack, etc.
2. **Classify** – Read PCI ROM header → vendor:device:subsys, dedupe by SHA-1.
3. **Extract** –
   - FCode → detok → plain text
   - x86 BIOS → Bochs/QEMU I/O trace
   - Store intermediate YAML.
4. **Reduce** – Collapse duplicate writes, detect delay loops & status polls, output canonical init-seq JSON.
5. **Test** – Verilator + real FPGA board; assert PCI IDs and video sync.
6. **Publish** – Commit JSON + SPDX header; generate MkDocs site.
7. **Alert-bot** – GitHub Action watches new ROM feeds; auto-PRs diff.

### A2. Tool-chain table

| Stage | Key tools | Notes |
|-------|-----------|-------|
| Harvest | requests, BeautifulSoup | Extensible scraper modules |
| Extract – FCode | rombin, detok, fcode_dump | Tokenised Forth → text |
| Extract – x86 | Bochs + --log-io, binwalk | 10 ms trace window |
| Reduce | Python + Pandas | Outputs JSON schema v1.0 |
| Test (sim) | Verilator + cocotb | One-shot per PR |
| Test (hw) | Rust harness over UART/JTAG | 48 h burn-in loop |
| CI/CD | GitHub Actions | Linux runner w/ docker-image |

---

## B. Implementation Details

### B1. Automated provenance system

- SPDX header template added to every JSON file.
- pre-commit hook validates SHA-1, schema, licence tag.
- SHA-1 of source ROM kept in roms/manifest.sqlite (private).

Example SPDX header:
```json
{
  "_metadata": {
    "SPDX-FileCopyrightText": "2025 NeXTRust Contributors",
    "SPDX-License-Identifier": "CC0-1.0",
    "Source-ROM-SHA1": "ee52a7c4b9d8f0e1c8a6b5d9e3f4a1b9c4",
    "Source-ROM-URL": "https://www.techpowerup.com/vgabios/12345/",
    "Generated": "2025-01-16T12:00:00Z",
    "Pipeline-Version": "1.0"
  },
  "init_sequence": [...]
}
```

### B2. Test-harness design

#### Simulator level
- Verilog test bench asserts order & timing (<1 µs gap).
- Validates all writes exit FIFO in correct sequence.
- Randomized inter-write delays to test timing robustness.

#### Dev board
- PCI riser + scope: lspci check, DAC sync, 48 h reset loop.
- Automated test sequence:
  1. Power cycle
  2. Load init sequence
  3. Verify PCI enumeration
  4. Check video output signal
  5. Stress test with repeated init cycles

### B3. Card taxonomy schema (cards.yaml)

```yaml
- sku: Radeon_9200_Mac_PCI
  vendor: 0x1002      # ATI
  device: 0x5962
  subsys: 0x00021002
  bus: pci
  power_max_w: 28
  memory_mb: 128
  init_seq: json/ati/radeon_9200_mac_pci_v119.json
  rom_sha1: ee52a7c4b9d8f0e1c8a6b5d9e3f4a1b9c4
  status: validated
  validated_date: 2025-01-15
  notes: Requires DELAY 20 ms after MC reset
  
- sku: GeForce_7800_GTX_256
  vendor: 0x10de      # NVIDIA
  device: 0x0091
  subsys: 0x00000000
  bus: pcie
  power_max_w: 110
  memory_mb: 256
  init_seq: json/nvidia/geforce_7800_gtx_256_v1.json
  rom_sha1: a1b2c3d4e5f6789012345678901234567890abcd
  status: testing
  notes: PCIe 1.0, requires 6-pin power
```

Driver and sequencer select the correct JSON via PCI IDs at runtime.

---

## C. Automation Features

### C1. ROM-diff alert bot

GitHub Action that monitors TechPowerUp RSS; diff new ROM → PR with new JSON + docs.

```yaml
name: ROM Update Monitor
on:
  schedule:
    - cron: '0 0 * * *'  # Daily check
  workflow_dispatch:

jobs:
  check-new-roms:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Check TechPowerUp RSS
        run: python tools/scrapers/check_new_roms.py
      - name: Process new ROMs
        run: python tools/pipeline/process_new.py
      - name: Create PR if changes
        uses: peter-evans/create-pull-request@v4
        with:
          title: "New GPU ROM: ${{ env.NEW_ROM_NAME }}"
          body: "Automated extraction of init sequence"
```

### C2. CI pipeline

Workflow: scrape → extract → reduce → test-sim → test-schema. Verilator step gate-keeps merges.

```yaml
name: GPU Init Pipeline CI
on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Validate JSON schema
        run: python -m jsonschema -i json/**/*.json schema/init_seq_v1.json
      
      - name: Check SPDX headers
        run: python tools/ci/check_spdx.py
      
      - name: Simulate init sequences
        run: |
          cd sim
          verilator --cc gpu_init_sequencer.v --exe test_sequences.cpp
          make -C obj_dir -f Vgpu_init_sequencer.mk
          ./obj_dir/Vgpu_init_sequencer
```

### C3. Auto-docs

MkDocs plugin generates tables & diagrams from cards.yaml and JSON metadata.

---

## D. Code Examples

### D1. TechPowerUp scraper (tools/scrapers/techpowerup.py)

```python
#!/usr/bin/env python3
"""Scrape GPU ROMs from TechPowerUp VGA BIOS Collection."""

import requests
from bs4 import BeautifulSoup
import hashlib
import json
from pathlib import Path

class TechPowerUpScraper:
    BASE_URL = "https://www.techpowerup.com/vgabios/"
    
    def scrape_index(self):
        """Fetch main index and extract ROM links."""
        resp = requests.get(self.BASE_URL)
        soup = BeautifulSoup(resp.text, 'html.parser')
        
        roms = []
        for row in soup.find_all('tr', class_='rom-entry'):
            rom_info = {
                'url': row.find('a')['href'],
                'vendor': row.find('td', class_='vendor').text,
                'model': row.find('td', class_='model').text,
                'version': row.find('td', class_='version').text,
                'date': row.find('td', class_='date').text,
                'size': row.find('td', class_='size').text
            }
            roms.append(rom_info)
        
        return roms
    
    def download_rom(self, rom_info, output_dir):
        """Download ROM and calculate SHA-1."""
        resp = requests.get(rom_info['url'])
        
        sha1 = hashlib.sha1(resp.content).hexdigest()
        filename = f"{rom_info['vendor']}_{rom_info['model']}_{sha1[:8]}.rom"
        
        output_path = Path(output_dir) / filename
        output_path.write_bytes(resp.content)
        
        rom_info['sha1'] = sha1
        rom_info['local_path'] = str(output_path)
        
        return rom_info
```

### D2. FCode extractor (tools/extractors/fcode.py)

```python
#!/usr/bin/env python3
"""Extract init sequences from FCode ROMs."""

import subprocess
import re
from pathlib import Path

class FCodeExtractor:
    def __init__(self, detok_path='/usr/local/bin/detok'):
        self.detok_path = detok_path
    
    def extract(self, rom_path):
        """Extract FCode and parse init sequences."""
        # Check for FCode signature
        with open(rom_path, 'rb') as f:
            if f.read(1) != b'\xf1':
                return None  # Not FCode
        
        # Run detok
        result = subprocess.run(
            [self.detok_path, rom_path],
            capture_output=True,
            text=True
        )
        
        # Parse config-w! and mem-w! sequences
        sequences = []
        for line in result.stdout.split('\n'):
            # Match: "1234 5678 config-w!"
            match = re.match(r'([0-9a-f]+)\s+([0-9a-f]+)\s+(config-[wb]!|mem-[wb]!)', line)
            if match:
                value, addr, op = match.groups()
                sequences.append({
                    'op': 'CFG' if 'config' in op else 'MMIO',
                    'addr': int(addr, 16),
                    'data': int(value, 16),
                    'width': 8 if 'b!' in op else 16 if 'w!' in op else 32
                })
        
        return sequences
```

### D3. Reducer (tools/reducers/reduce.py)

```python
#!/usr/bin/env python3
"""Reduce raw init sequences to canonical form."""

import pandas as pd
from typing import List, Dict

class InitSequenceReducer:
    def reduce(self, raw_sequences: List[Dict]) -> List[Dict]:
        """Collapse duplicates and detect patterns."""
        # Convert to DataFrame for easier manipulation
        df = pd.DataFrame(raw_sequences)
        
        # Remove consecutive duplicate writes to same address
        df['addr_changed'] = df['addr'] != df['addr'].shift(1)
        df = df[df['addr_changed'] | (df.index == 0)]
        
        # Detect delays (gaps > 1ms in timestamps)
        if 'timestamp_us' in df.columns:
            df['time_delta'] = df['timestamp_us'].diff()
            
            # Insert DELAY operations where needed
            delays = df[df['time_delta'] > 1000]
            for idx, row in delays.iterrows():
                delay_op = {
                    'op': 'DELAY',
                    'ns': int(row['time_delta'] * 1000)
                }
                # Insert delay before this operation
                df = pd.concat([
                    df[:idx],
                    pd.DataFrame([delay_op]),
                    df[idx:]
                ]).reset_index(drop=True)
        
        # Convert back to list of dicts
        return df[['op', 'addr', 'data']].fillna(0).astype(int).to_dict('records')
```

### D4. Micro-sequencer (rtl/gpu_init_sequencer.v)

```verilog
// GPU initialization micro-sequencer
// Executes init sequences from BRAM

module gpu_init_sequencer #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter SEQ_DEPTH = 1024
)(
    input wire clk,
    input wire rst_n,
    
    // Control
    input wire start,
    output reg done,
    output reg error,
    
    // Sequence selection
    input wire [7:0] gpu_id,
    
    // PCI interface
    output reg [ADDR_WIDTH-1:0] pci_addr,
    output reg [DATA_WIDTH-1:0] pci_data,
    output reg pci_write,
    input wire pci_ack,
    
    // Status
    output reg [15:0] seq_counter
);

// Instruction format (64-bit)
// [63:60] = opcode (CFG, MMIO, DELAY, POLL, END)
// [59:32] = address/delay value
// [31:0]  = data/mask

localparam OP_CFG   = 4'h1;
localparam OP_MMIO  = 4'h2;
localparam OP_DELAY = 4'h3;
localparam OP_POLL  = 4'h4;
localparam OP_END   = 4'hF;

// Sequence memory (initialized from JSON via .coe file)
reg [63:0] seq_mem [0:SEQ_DEPTH-1];
initial $readmemh("gpu_init_sequences.mem", seq_mem);

// State machine
reg [2:0] state;
localparam S_IDLE = 3'd0;
localparam S_FETCH = 3'd1;
localparam S_EXECUTE = 3'd2;
localparam S_WAIT_ACK = 3'd3;
localparam S_DELAY = 3'd4;
localparam S_DONE = 3'd5;

reg [63:0] current_inst;
reg [31:0] delay_counter;

always @(posedge clk) begin
    if (!rst_n) begin
        state <= S_IDLE;
        done <= 1'b0;
        error <= 1'b0;
        seq_counter <= 16'd0;
        pci_write <= 1'b0;
    end else begin
        case (state)
            S_IDLE: begin
                if (start) begin
                    state <= S_FETCH;
                    seq_counter <= 16'd0;
                    done <= 1'b0;
                end
            end
            
            S_FETCH: begin
                current_inst <= seq_mem[seq_counter];
                state <= S_EXECUTE;
            end
            
            S_EXECUTE: begin
                case (current_inst[63:60])
                    OP_CFG, OP_MMIO: begin
                        pci_addr <= current_inst[59:32];
                        pci_data <= current_inst[31:0];
                        pci_write <= 1'b1;
                        state <= S_WAIT_ACK;
                    end
                    
                    OP_DELAY: begin
                        delay_counter <= current_inst[31:0];
                        state <= S_DELAY;
                    end
                    
                    OP_END: begin
                        state <= S_DONE;
                        done <= 1'b1;
                    end
                    
                    default: begin
                        error <= 1'b1;
                        state <= S_IDLE;
                    end
                endcase
            end
            
            S_WAIT_ACK: begin
                if (pci_ack) begin
                    pci_write <= 1'b0;
                    seq_counter <= seq_counter + 1;
                    state <= S_FETCH;
                end
            end
            
            S_DELAY: begin
                if (delay_counter == 0) begin
                    seq_counter <= seq_counter + 1;
                    state <= S_FETCH;
                end else begin
                    delay_counter <= delay_counter - 1;
                end
            end
            
            S_DONE: begin
                done <= 1'b1;
                if (!start) state <= S_IDLE;
            end
        endcase
    end
end

endmodule
```

### D5. Driver stub generator (generators/driver_stub.py)

```python
#!/usr/bin/env python3
"""Generate NeXTSTEP driver stubs from card taxonomy."""

import yaml
from pathlib import Path

def generate_driver_stub(card_info):
    """Generate C driver skeleton for a GPU card."""
    
    template = '''/* Auto-generated driver stub for {sku} */
/* SPDX-License-Identifier: MIT */

#include <driverkit/generalFuncs.h>
#include <driverkit/IODevice.h>
#include <driverkit/IOFrameBufferDisplay.h>

#define VENDOR_ID 0x{vendor:04x}
#define DEVICE_ID 0x{device:04x}
#define SUBSYS_ID 0x{subsys:08x}

#define BAR0_SIZE {memory_mb}*1024*1024

@interface {driver_class} : IOFrameBufferDisplay
{{
    void *framebuffer_base;
    vm_size_t framebuffer_size;
    int currentMode;
}}
@end

@implementation {driver_class}

+ (BOOL)probe:deviceDescription
{{
    IOPCIDeviceDescription *pciDesc = (IOPCIDeviceDescription *)deviceDescription;
    
    if (pciDesc->vendorID == VENDOR_ID && pciDesc->deviceID == DEVICE_ID) {{
        IOLog("{sku}: Found matching device\\n");
        return YES;
    }}
    
    return NO;
}}

- initFromDeviceDescription:deviceDescription
{{
    if ((self = [super initFromDeviceDescription:deviceDescription]) == nil)
        return nil;
    
    IOLog("{sku}: Initializing...\\n");
    
    // Map framebuffer
    framebuffer_size = BAR0_SIZE;
    if ([self mapMemoryRange:0 to:(vm_address_t *)&framebuffer_base 
                     findSpace:YES cache:IO_DISPLAY_CACHE_WRITETHROUGH] != IO_R_SUCCESS) {{
        IOLog("{sku}: Failed to map framebuffer\\n");
        [self free];
        return nil;
    }}
    
    // Card-specific initialization will be handled by FPGA sequencer
    IOLog("{sku}: Initialization complete\\n");
    
    return self;
}}

@end
'''
    
    driver_class = card_info['sku'].replace('_', '')
    
    return template.format(
        sku=card_info['sku'],
        vendor=card_info['vendor'],
        device=card_info['device'],
        subsys=card_info['subsys'],
        memory_mb=card_info.get('memory_mb', 32),
        driver_class=driver_class
    )

if __name__ == '__main__':
    # Load card taxonomy
    with open('cards.yaml') as f:
        cards = yaml.safe_load(f)
    
    # Generate driver for each card
    for card in cards:
        if card['status'] == 'validated':
            driver_code = generate_driver_stub(card)
            
            output_path = Path(f"drivers/{card['sku']}.m")
            output_path.parent.mkdir(exist_ok=True)
            output_path.write_text(driver_code)
            
            print(f"Generated driver stub: {output_path}")
```

---

## E. Evolution Strategy

### E1. Bus migration
- Add CFG_EXT opcode (64-bit addr) for PCIe extended config space
- Abstract write widths (8/16/32/64-bit)
- Support multi-function devices

### E2. Power rails
- BOM note: add 3.3V @ 4A regulator for AGP cards
- PCIe: 3.3V + 12V, up to 75W from slot
- External power detection and validation

### E3. Schema v2
```json
{
  "schema_version": "2.0",
  "card_info": {
    "sku": "...",
    "multi_gpu": false,
    "sli_capable": false
  },
  "power_sequence": [
    {"rail": "3.3V", "delay_ms": 10},
    {"rail": "1.8V", "delay_ms": 5}
  ],
  "init_sequence": [...],
  "shutdown_sequence": [...]
}
```

---

## F. Community & Legal

### F1. Licensing
- **Init-seq JSON** – CC0-1.0 (public domain)
- **Pipeline & RTL tooling** – MIT licence
- **Documentation** – CC-BY-4.0

### F2. Contribution guide
- CLA-free; PR must include SHA-1 of source ROM & explicit provenance
- All JSON files must pass schema validation
- Hardware validation required for 'validated' status
- No copyrighted material (ROMs, logos, etc.) in public repo

### F3. Repository structure
```
gpu-init-db/
├── roms/               # Private submodule (not distributed)
│   └── manifest.sqlite # SHA-1 to filename mapping
├── json/               # Public init sequences
│   ├── 3dfx/
│   ├── ati/
│   ├── matrox/
│   ├── nvidia/
│   └── s3/
├── schema/             # JSON schema definitions
├── tools/              # Extraction pipeline
│   ├── scrapers/
│   ├── extractors/
│   ├── reducers/
│   └── generators/
├── rtl/                # Verilog sequencer
├── tests/              # Validation suite
│   ├── unit/
│   ├── integration/
│   └── hardware/
├── docs/               # MkDocs source
└── .github/            # CI/CD workflows
```

---

## G. Timeline & Milestones

| Week | Deliverable |
|------|-------------|
| 1-2 | Core scraper + repo skeleton |
| 3-4 | FCode & x86 extractors complete |
| 5-6 | Reducer + JSON schema + sim tests |
| 7-8 | FPGA dev-board validation loop |
| 9-10 | CI/CD end-to-end, docs site live |
| 11-12 | Public community launch |

### Detailed schedule

**Weeks 1-2: Foundation**
- Set up repository structure
- Implement TechPowerUp scraper
- Create SQLite manifest database
- Define JSON schema v1.0

**Weeks 3-4: Extraction**
- FCode detokenizer integration
- x86 BIOS tracer (Bochs setup)
- Raw sequence capture
- Initial deduplication

**Weeks 5-6: Intelligence**
- Duplicate write collapsing
- Delay detection algorithm
- POLL operation recognition
- Schema validation

**Weeks 7-8: Hardware**
- Verilog sequencer implementation
- FPGA synthesis and testing
- Dev board validation setup
- First 5 cards validated

**Weeks 9-10: Automation**
- GitHub Actions CI pipeline
- Automated testing framework
- Documentation generation
- ROM monitoring bot

**Weeks 11-12: Launch**
- Community documentation
- Contribution guidelines
- First 20 cards complete
- Public announcement

---

## H. Example JSON Output

### H1. Radeon 9200 Mac Edition

```json
{
  "_metadata": {
    "SPDX-FileCopyrightText": "2025 NeXTRust Contributors",
    "SPDX-License-Identifier": "CC0-1.0",
    "Source-ROM-SHA1": "ee52a7c4b9d8f0e1c8a6b5d9e3f4a1b9c4",
    "Source-ROM-URL": "https://www.techpowerup.com/vgabios/12345/",
    "Generated": "2025-01-16T12:00:00Z",
    "Pipeline-Version": "1.0",
    "Card-SKU": "Radeon_9200_Mac_PCI"
  },
  "init_sequence": [
    {"op": "CFG", "addr": 0x04, "data": 0x0006},
    {"op": "CFG", "addr": 0x10, "data": 0x0C000000},
    {"op": "DELAY", "ns": 1000000},
    {"op": "MMIO", "addr": 0x0050, "data": 0x00000001},
    {"op": "MMIO", "addr": 0x0054, "data": 0x00000000},
    {"op": "MMIO", "addr": 0x0058, "data": 0x08000000},
    {"op": "DELAY", "ns": 20000000},
    {"op": "MMIO", "addr": 0x0140, "data": 0x00000400},
    {"op": "POLL", "addr": 0x0144, "mask": 0x00000001, "value": 0x00000000, "timeout_us": 100000},
    {"op": "MMIO", "addr": 0x0200, "data": 0x00FF00FF},
    {"op": "END"}
  ]
}
```

### H2. GeForce 7800 GTX

```json
{
  "_metadata": {
    "SPDX-FileCopyrightText": "2025 NeXTRust Contributors",
    "SPDX-License-Identifier": "CC0-1.0",
    "Source-ROM-SHA1": "a1b2c3d4e5f6789012345678901234567890abcd",
    "Source-ROM-URL": "https://www.techpowerup.com/vgabios/67890/",
    "Generated": "2025-01-16T12:00:00Z",
    "Pipeline-Version": "1.0",
    "Card-SKU": "GeForce_7800_GTX_256"
  },
  "init_sequence": [
    {"op": "CFG", "addr": 0x04, "data": 0x0007},
    {"op": "CFG", "addr": 0x10, "data": 0xF0000000},
    {"op": "CFG", "addr": 0x14, "data": 0x0C000000},
    {"op": "DELAY", "ns": 1000000},
    {"op": "MMIO", "addr": 0x0000, "data": 0x00000000},
    {"op": "MMIO", "addr": 0x0200, "data": 0x00000001},
    {"op": "DELAY", "ns": 5000000},
    {"op": "MMIO", "addr": 0x0088, "data": 0x00002000},
    {"op": "MMIO", "addr": 0x008C, "data": 0x01000000},
    {"op": "POLL", "addr": 0x0088, "mask": 0x00000100, "value": 0x00000100, "timeout_us": 50000},
    {"op": "MMIO", "addr": 0x0600, "data": 0x00000001},
    {"op": "MMIO", "addr": 0x0604, "data": 0x10000000},
    {"op": "END"}
  ]
}
```

---

## I. Security Considerations

### I1. Input validation
- ROM size limits (max 1MB)
- SHA-1 verification before processing
- Sandboxed execution for extractors

### I2. Output sanitization
- Address range validation (no system memory access)
- Data value bounds checking
- Maximum sequence length (1024 operations)

### I3. CI security
- No credentials in scripts
- Read-only access to ROM sources
- Isolated test environments

---

## J. Future Expansion

### J1. Additional sources
- VGA Museum
- drivers.softpedia.com archives
- retro computing forums
- eBay ROM dumps (with permission)

### J2. Card types
- Professional cards (3DLabs, E&S)
- Embedded GPUs (Intel, SiS)
- Exotic architectures (PowerVR, Rendition)
- Modern retro (MiSTer cores)

### J3. Integration possibilities
- QEMU device models
- MiSTer FPGA cores
- PCem/86Box emulation
- Real hardware archives

---

*End of document – rev 0.1 (2025-01-16)*