#!/usr/bin/env python3
"""
match-known-issue.py - Backward compatibility wrapper for nextrust check-known-issue

This wrapper maintains compatibility with existing code that calls match-known-issue.py
while delegating to the unified nextrust CLI tool.
"""
import sys
import subprocess
import os

def main():
    if len(sys.argv) < 2:
        print("Usage: match-known-issue.py <error_message> [phase] [cpu_variant]", file=sys.stderr)
        sys.exit(1)
    
    error_message = sys.argv[1]
    phase = sys.argv[2] if len(sys.argv) > 2 else None
    cpu_variant = sys.argv[3] if len(sys.argv) > 3 else None
    
    # Build command
    cmd = [
        sys.executable,
        "ci/scripts/tools/nextrust_cli.py",
        "check-known-issue",
        error_message
    ]
    
    if phase:
        cmd.extend(["--phase", phase])
    
    if cpu_variant:
        cmd.extend(["--cpu-variant", cpu_variant])
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    # Pass through stdout/stderr
    if result.stdout:
        print(result.stdout, end='')
    if result.stderr:
        print(result.stderr, end='', file=sys.stderr)
    
    sys.exit(result.returncode)

if __name__ == "__main__":
    main()