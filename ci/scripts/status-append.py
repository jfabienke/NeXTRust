#!/usr/bin/env python3
# ci/scripts/status-append.py - Thread-safe status updates
#
# Purpose: Append status entries to both JSON and Markdown logs with file locking
# Usage: python status-append.py <entry_type> <json_data>
# Example: python status-append.py "build_failure" '{"error": "undefined reference", "file": "atomics.c"}'

import fcntl
import json
import sys
import time
from datetime import datetime
from pathlib import Path

def append_status(entry_type, data):
    """Append to status artifacts with file locking."""
    
    # Paths
    json_path = Path("docs/ci-status/pipeline-log.json")
    md_path = Path("docs/ci-status/pipeline-log.md")
    lock_path = Path(".claude/status.lock")
    
    # Ensure directories exist
    json_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Acquire exclusive lock
    with open(lock_path, "w") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        
        try:
            # Update JSON
            if json_path.exists():
                with open(json_path) as f:
                    status = json.load(f)
            else:
                status = {"activities": []}
            
            # Add new entry
            entry = {
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "type": entry_type,
                "details": data
            }
            status["activities"].append(entry)
            
            # Write atomically
            tmp_json = json_path.with_suffix(".tmp")
            with open(tmp_json, "w") as f:
                json.dump(status, f, indent=2)
            tmp_json.rename(json_path)
            
            # Update Markdown
            if not md_path.exists():
                with open(md_path, "w") as f:
                    f.write("# NeXTRust CI Pipeline Status\n")
                    f.write(f"*Last updated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC*\n\n")
                    f.write("## Recent Activities\n")
            
            with open(md_path, "a") as f:
                message = data.get('message', f'{entry_type}: {json.dumps(data)}')
                f.write(f"\n- {entry['timestamp']} - {entry_type}: {message}\n")
                
        finally:
            # Release lock
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

def main():
    if len(sys.argv) != 3:
        print("Usage: status-append.py <entry_type> <json_data>")
        sys.exit(1)
    
    entry_type = sys.argv[1]
    try:
        data = json.loads(sys.argv[2])
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON data - {e}")
        sys.exit(1)
    
    try:
        append_status(entry_type, data)
        print(f"Status updated: {entry_type}")
    except Exception as e:
        print(f"Error updating status: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()