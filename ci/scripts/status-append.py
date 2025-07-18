#!/usr/bin/env python3
"""
status-append.py - Backward compatibility wrapper for nextrust append-status

This wrapper maintains compatibility with existing code that calls status-append.py
while delegating to the unified nextrust CLI tool.
"""
import sys
import subprocess
import json

def main():
    if len(sys.argv) < 3:
        print("Usage: status-append.py <entry_type> <json_data>", file=sys.stderr)
        sys.exit(1)
    
    entry_type = sys.argv[1]
    json_data = sys.argv[2]
    
    # Validate JSON
    try:
        json.loads(json_data)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON data - {e}", file=sys.stderr)
        sys.exit(1)
    
    # Call nextrust CLI
    cmd = [
        sys.executable,
        "ci/scripts/tools/nextrust_cli.py",
        "append-status",
        entry_type,
        json_data
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    # Pass through stdout/stderr
    if result.stdout:
        print(result.stdout, end='')
    if result.stderr:
        print(result.stderr, end='', file=sys.stderr)
    
    sys.exit(result.returncode)

if __name__ == "__main__":
    main()