#!/usr/bin/env python3
"""
rotate_status.py - Backward compatibility wrapper for nextrust rotate-status

This wrapper maintains compatibility with existing code that calls rotate_status.py
while delegating to the unified nextrust CLI tool.
"""
import sys
import subprocess

def main():
    # Call nextrust CLI with default arguments
    cmd = [
        sys.executable,
        "ci/scripts/tools/nextrust_cli.py",
        "rotate-status"
    ]
    
    # Check if any arguments were passed
    if len(sys.argv) > 1:
        # Pass through any arguments (though original script didn't take any)
        cmd.extend(sys.argv[1:])
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    # Pass through stdout/stderr
    if result.stdout:
        print(result.stdout, end='')
    if result.stderr:
        print(result.stderr, end='', file=sys.stderr)
    
    sys.exit(result.returncode)

if __name__ == "__main__":
    main()