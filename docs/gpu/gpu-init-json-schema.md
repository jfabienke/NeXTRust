# GPU Init Sequence JSON Schema Specification

*Last updated: 2025-01-16 12:05 PM*

## Overview

This document defines the JSON schema for GPU initialization sequences extracted from option ROMs. The schema ensures consistency, validation, and forward compatibility.

## Schema Version 1.0

### Top-Level Structure

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://nextrust.org/schemas/gpu-init-v1.json",
  "type": "object",
  "required": ["_metadata", "init_sequence"],
  "properties": {
    "_metadata": {
      "type": "object",
      "required": [
        "SPDX-FileCopyrightText",
        "SPDX-License-Identifier",
        "Source-ROM-SHA1",
        "Generated",
        "Pipeline-Version",
        "Card-SKU"
      ],
      "properties": {
        "SPDX-FileCopyrightText": {
          "type": "string",
          "pattern": "^\\d{4} .+$"
        },
        "SPDX-License-Identifier": {
          "type": "string",
          "enum": ["CC0-1.0"]
        },
        "Source-ROM-SHA1": {
          "type": "string",
          "pattern": "^[a-f0-9]{40}$"
        },
        "Source-ROM-URL": {
          "type": "string",
          "format": "uri"
        },
        "Generated": {
          "type": "string",
          "format": "date-time"
        },
        "Pipeline-Version": {
          "type": "string",
          "pattern": "^\\d+\\.\\d+$"
        },
        "Card-SKU": {
          "type": "string",
          "pattern": "^[A-Za-z0-9_]+$"
        }
      }
    },
    "init_sequence": {
      "type": "array",
      "maxItems": 1024,
      "items": {
        "$ref": "#/definitions/operation"
      }
    }
  },
  "definitions": {
    "operation": {
      "oneOf": [
        {"$ref": "#/definitions/cfg_op"},
        {"$ref": "#/definitions/mmio_op"},
        {"$ref": "#/definitions/delay_op"},
        {"$ref": "#/definitions/poll_op"},
        {"$ref": "#/definitions/end_op"}
      ]
    },
    "cfg_op": {
      "type": "object",
      "required": ["op", "addr", "data"],
      "properties": {
        "op": {"const": "CFG"},
        "addr": {
          "type": "integer",
          "minimum": 0,
          "maximum": 255
        },
        "data": {
          "type": "integer",
          "minimum": 0,
          "maximum": 4294967295
        }
      }
    },
    "mmio_op": {
      "type": "object",
      "required": ["op", "addr", "data"],
      "properties": {
        "op": {"const": "MMIO"},
        "addr": {
          "type": "integer",
          "minimum": 0,
          "maximum": 16777215
        },
        "data": {
          "type": "integer",
          "minimum": 0,
          "maximum": 4294967295
        }
      }
    },
    "delay_op": {
      "type": "object",
      "required": ["op", "ns"],
      "properties": {
        "op": {"const": "DELAY"},
        "ns": {
          "type": "integer",
          "minimum": 1000,
          "maximum": 1000000000
        }
      }
    },
    "poll_op": {
      "type": "object",
      "required": ["op", "addr", "mask", "value", "timeout_us"],
      "properties": {
        "op": {"const": "POLL"},
        "addr": {
          "type": "integer",
          "minimum": 0,
          "maximum": 16777215
        },
        "mask": {
          "type": "integer",
          "minimum": 0,
          "maximum": 4294967295
        },
        "value": {
          "type": "integer",
          "minimum": 0,
          "maximum": 4294967295
        },
        "timeout_us": {
          "type": "integer",
          "minimum": 1,
          "maximum": 10000000
        }
      }
    },
    "end_op": {
      "type": "object",
      "required": ["op"],
      "properties": {
        "op": {"const": "END"}
      }
    }
  }
}
```

## Operation Types

### CFG - PCI Configuration Space Write

Writes to PCI configuration space registers.

```json
{
  "op": "CFG",
  "addr": 0x04,    // Configuration register offset (0-255)
  "data": 0x0007   // 32-bit value to write
}
```

Common addresses:
- 0x04: Command register
- 0x10-0x24: Base Address Registers (BARs)
- 0x3C: Interrupt line
- 0x80+: Device-specific

### MMIO - Memory-Mapped I/O Write

Writes to memory-mapped registers within the GPU's address space.

```json
{
  "op": "MMIO",
  "addr": 0x0200,      // Offset within BAR0 (24-bit)
  "data": 0x00000001   // 32-bit value to write
}
```

### DELAY - Time Delay

Inserts a delay between operations.

```json
{
  "op": "DELAY",
  "ns": 20000000   // Delay in nanoseconds (20ms in this example)
}
```

Constraints:
- Minimum: 1 microsecond (1000 ns)
- Maximum: 1 second (1000000000 ns)

### POLL - Register Polling

Polls a register until a condition is met or timeout occurs.

```json
{
  "op": "POLL",
  "addr": 0x0144,          // Register to read
  "mask": 0x00000001,      // Bit mask to apply
  "value": 0x00000000,     // Expected value after masking
  "timeout_us": 100000     // Timeout in microseconds
}
```

The operation succeeds when: `(register_value & mask) == value`

### END - Sequence Terminator

Marks the end of the initialization sequence.

```json
{
  "op": "END"
}
```

## Validation Rules

### 1. Sequence Structure
- Must start with at least one CFG operation (enable memory/IO)
- Must end with exactly one END operation
- Maximum 1024 operations per sequence

### 2. Address Validation
- CFG addresses: 0-255 (8-bit PCI config space)
- MMIO addresses: 0-16777215 (24-bit offset within BAR)
- No writes to reserved PCI config registers (0x00-0x03)

### 3. Timing Constraints
- DELAY operations: 1µs to 1s
- POLL timeouts: 1µs to 10s
- Total sequence time should not exceed 30 seconds

### 4. Data Integrity
- All numeric values must be integers
- No floating point or string data in operations
- Addresses and data are unsigned integers

## Evolution Path

### Schema Version 2.0 (Planned)

Additional operation types:
```json
{
  "op": "CFG_EXT",   // PCIe extended config space (12-bit address)
  "addr": 0x100,
  "data": 0x00000000
}

{
  "op": "MMIO_64",   // 64-bit MMIO write
  "addr": 0x1000,
  "data_low": 0x00000000,
  "data_high": 0x00000000
}

{
  "op": "POWER",     // Power rail control
  "rail": "3.3V",
  "state": "on",
  "delay_ms": 10
}
```

### Backward Compatibility
- Version 1.0 files will be auto-converted to 2.0
- New operations will have fallback behavior
- Metadata version field enables conditional parsing

## Examples

### Minimal Sequence
```json
{
  "_metadata": {
    "SPDX-FileCopyrightText": "2025 NeXTRust Contributors",
    "SPDX-License-Identifier": "CC0-1.0",
    "Source-ROM-SHA1": "1234567890abcdef1234567890abcdef12345678",
    "Generated": "2025-01-16T12:00:00Z",
    "Pipeline-Version": "1.0",
    "Card-SKU": "S3_Trio64"
  },
  "init_sequence": [
    {"op": "CFG", "addr": 0x04, "data": 0x0003},
    {"op": "END"}
  ]
}
```

### Complex Sequence with Polling
```json
{
  "_metadata": {
    "SPDX-FileCopyrightText": "2025 NeXTRust Contributors",
    "SPDX-License-Identifier": "CC0-1.0",
    "Source-ROM-SHA1": "abcdef1234567890abcdef1234567890abcdef12",
    "Generated": "2025-01-16T12:00:00Z",
    "Pipeline-Version": "1.0",
    "Card-SKU": "GeForce_FX_5200"
  },
  "init_sequence": [
    {"op": "CFG", "addr": 0x04, "data": 0x0007},
    {"op": "CFG", "addr": 0x10, "data": 0xF0000000},
    {"op": "DELAY", "ns": 1000000},
    {"op": "MMIO", "addr": 0x0000, "data": 0x00000000},
    {"op": "MMIO", "addr": 0x0100, "data": 0x00000001},
    {"op": "POLL", "addr": 0x0100, "mask": 0x80000000, "value": 0x80000000, "timeout_us": 50000},
    {"op": "MMIO", "addr": 0x0200, "data": 0xDEADBEEF},
    {"op": "END"}
  ]
}
```

## Validation Tools

### Python Validator
```python
import json
import jsonschema

def validate_init_sequence(json_file):
    """Validate a GPU init sequence against the schema."""
    with open('schema/gpu-init-v1.json') as f:
        schema = json.load(f)
    
    with open(json_file) as f:
        data = json.load(f)
    
    try:
        jsonschema.validate(data, schema)
        print(f"✓ {json_file} is valid")
        return True
    except jsonschema.ValidationError as e:
        print(f"✗ {json_file} validation failed: {e.message}")
        return False
```

### Command Line Validation
```bash
# Validate single file
python -m jsonschema -i radeon_9200.json schema/gpu-init-v1.json

# Validate all files
find json/ -name "*.json" -exec python -m jsonschema -i {} schema/gpu-init-v1.json \;
```

## Best Practices

1. **Keep sequences minimal** - Only include necessary operations
2. **Document delays** - Add comments in source about why delays exist
3. **Test thoroughly** - Validate on real hardware before marking as "validated"
4. **Version control** - Track changes to sequences over time
5. **Cross-reference** - Compare with open-source drivers when available

---

*End of GPU Init JSON Schema Specification v1.0*