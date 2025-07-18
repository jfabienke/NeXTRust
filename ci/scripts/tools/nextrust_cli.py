#!/usr/bin/env python3
"""
nextrust_cli.py - Unified CLI tool for NeXTRust CI operations

Purpose: Provide a clean, testable interface for common CI operations
replacing complex shell script pipelines with structured Python code.
"""

import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, Dict, Any, List
import glob

import typer
from typer import Argument, Option

app = typer.Typer(
    name="nextrust",
    help="NeXTRust CI/CD unified tool",
    add_completion=False
)

# Configuration
STATUS_FILE = Path("docs/ci-status/pipeline-log.json")
PROMPT_LOG_FILE = Path("docs/ci-status/prompt-log.json")
KNOWN_ISSUES_FILE = Path("docs/ci-status/known-issues.json")


def ensure_dir(file_path: Path):
    """Ensure directory exists for a file path."""
    file_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(file_path: Path) -> Dict[str, Any]:
    """Read JSON file safely."""
    if not file_path.exists():
        return {}
    try:
        with open(file_path, 'r') as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {}


def write_json(file_path: Path, data: Dict[str, Any]):
    """Write JSON file safely."""
    ensure_dir(file_path)
    with open(file_path, 'w') as f:
        json.dump(data, f, indent=2, default=str)


@app.command()
def update_status(
    message: str = Argument(..., help="Status message to append"),
    status_type: str = Option("info", help="Status type: info, warning, error, success"),
    phase: Optional[str] = Option(None, help="Current phase ID"),
    metadata: Optional[str] = Option(None, help="Additional metadata as JSON string")
):
    """Update pipeline status with a new entry."""
    # Read existing status
    status_data = read_json(STATUS_FILE)
    
    # Initialize structure if needed
    if "entries" not in status_data:
        status_data["entries"] = []
    
    # Create new entry
    entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "type": status_type,
        "message": message,
        "phase": phase or status_data.get("current_phase", {}).get("id", "unknown")
    }
    
    # Add metadata if provided
    if metadata:
        try:
            entry["metadata"] = json.loads(metadata)
        except json.JSONDecodeError:
            typer.echo(f"Warning: Invalid JSON metadata: {metadata}", err=True)
    
    # Append entry
    status_data["entries"].append(entry)
    
    # Keep only last 1000 entries to prevent unbounded growth
    if len(status_data["entries"]) > 1000:
        status_data["entries"] = status_data["entries"][-1000:]
    
    # Write back
    write_json(STATUS_FILE, status_data)
    
    typer.echo(f"✅ Status updated: [{status_type}] {message}")


@app.command()
def get_phase():
    """Get the current pipeline phase."""
    status_data = read_json(STATUS_FILE)
    current_phase = status_data.get("current_phase", {})
    
    phase_id = current_phase.get("id", "unknown")
    phase_name = current_phase.get("name", "Unknown")
    phase_status = current_phase.get("status", "unknown")
    
    typer.echo(f"Phase ID: {phase_id}")
    typer.echo(f"Phase Name: {phase_name}")
    typer.echo(f"Status: {phase_status}")
    
    # Return just the ID for scripting
    return phase_id


@app.command()
def set_phase(
    phase_id: str = Argument(..., help="Phase ID to set"),
    phase_name: str = Argument(..., help="Human-readable phase name"),
    status: str = Option("in_progress", help="Phase status")
):
    """Set the current pipeline phase."""
    status_data = read_json(STATUS_FILE)
    
    status_data["current_phase"] = {
        "id": phase_id,
        "name": phase_name,
        "status": status,
        "started_at": datetime.utcnow().isoformat() + "Z"
    }
    
    write_json(STATUS_FILE, status_data)
    
    typer.echo(f"✅ Phase set to: {phase_id} ({phase_name})")


@app.command()
def check_known_issue(
    error_message: str = Argument(..., help="Error message to check"),
    phase: Optional[str] = Option(None, help="Current phase"),
    cpu_variant: Optional[str] = Option(None, help="CPU variant (m68030/m68040)")
):
    """Check if an error matches a known issue."""
    known_issues = read_json(KNOWN_ISSUES_FILE)
    
    if "issues" not in known_issues:
        typer.echo("No known issues database found")
        raise typer.Exit(1)
    
    # Simple pattern matching (can be enhanced with regex)
    for issue in known_issues["issues"]:
        # Check phase match
        if phase and issue.get("phase") != phase:
            continue
            
        # Check CPU variant match
        if cpu_variant and issue.get("cpu_variant") and issue["cpu_variant"] != cpu_variant:
            continue
            
        # Check pattern match
        pattern = issue.get("pattern", "")
        if pattern in error_message:
            typer.echo(f"✅ Matched known issue: {issue.get('id', 'unknown')}")
            typer.echo(f"Description: {issue.get('description', 'N/A')}")
            
            if issue.get("auto_fix"):
                typer.echo(f"Auto-fix available: {issue['auto_fix']}")
            
            # Return JSON for scripting
            print(json.dumps(issue))
            raise typer.Exit(0)
    
    typer.echo("❌ No matching known issue found")
    raise typer.Exit(1)


@app.command()
def github_comment(
    pr_number: int = Argument(..., help="PR number to comment on"),
    message: str = Argument(..., help="Comment message"),
    repo: Optional[str] = Option(None, help="Repository (owner/name)")
):
    """Post a comment to a GitHub PR."""
    if not repo:
        repo = os.environ.get("GITHUB_REPOSITORY", "")
    
    if not repo:
        typer.echo("Error: Repository not specified and GITHUB_REPOSITORY not set", err=True)
        raise typer.Exit(1)
    
    # This would use the GitHub API - simplified for now
    typer.echo(f"Would post to PR #{pr_number} in {repo}:")
    typer.echo(message)
    
    # In real implementation, would use requests or gh CLI
    # For now, shell out to gh if available
    import subprocess
    try:
        result = subprocess.run(
            ["gh", "api", f"repos/{repo}/issues/{pr_number}/comments", "-f", f"body={message}"],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            typer.echo("✅ Comment posted successfully")
        else:
            typer.echo(f"❌ Failed to post comment: {result.stderr}", err=True)
            raise typer.Exit(1)
    except FileNotFoundError:
        typer.echo("Warning: gh CLI not found, comment not posted", err=True)


@app.command()
def rotate_logs(
    retention_days: int = Option(30, help="Number of days to retain logs"),
    dry_run: bool = Option(False, help="Show what would be deleted without deleting")
):
    """Rotate old log files and status artifacts."""
    from datetime import datetime, timedelta
    
    cutoff_date = datetime.now() - timedelta(days=retention_days)
    
    # Directories to clean
    log_dirs = [
        Path("docs/ci-status/archive"),
        Path("docs/ci-status/build-logs"),
        Path("docs/ci-status/snapshots"),
        Path(".claude/hook-logs")
    ]
    
    total_deleted = 0
    total_size = 0
    
    for log_dir in log_dirs:
        if not log_dir.exists():
            continue
            
        typer.echo(f"\nChecking {log_dir}...")
        
        for file_path in log_dir.rglob("*"):
            if not file_path.is_file():
                continue
                
            # Check file age
            mtime = datetime.fromtimestamp(file_path.stat().st_mtime)
            if mtime < cutoff_date:
                size = file_path.stat().st_size
                
                if dry_run:
                    typer.echo(f"  Would delete: {file_path.name} ({size:,} bytes)")
                else:
                    file_path.unlink()
                    typer.echo(f"  Deleted: {file_path.name} ({size:,} bytes)")
                
                total_deleted += 1
                total_size += size
    
    typer.echo(f"\n{'Would delete' if dry_run else 'Deleted'} {total_deleted} files")
    typer.echo(f"Total size: {total_size:,} bytes ({total_size / 1024 / 1024:.1f} MB)")


@app.command()
def version():
    """Show version information."""
    typer.echo("nextrust-cli version 1.0.0")
    typer.echo("Part of NeXTRust CI/CD pipeline")


@app.command()
def usage_report(
    days: int = Option(7, help="Report for last N days"),
    group_by: str = Option("phase", help="Group by: phase, user, command_type, model"),
    output_format: str = Option("table", help="Output format: table, json, csv"),
    show_costs: bool = Option(True, help="Show cost breakdown")
):
    """Generate token usage report with cost analysis."""
    from collections import defaultdict
    from datetime import datetime, timedelta
    
    # Calculate date range
    end_date = datetime.now()
    start_date = end_date - timedelta(days=days)
    
    typer.echo(f"\n📊 Token Usage Report")
    typer.echo(f"Period: {start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}")
    typer.echo("=" * 60)
    
    # Collect usage data
    metrics_dir = Path("docs/ci-status/metrics")
    all_usage = []
    
    # Read token usage files
    for usage_file in metrics_dir.glob("token-usage-*.jsonl"):
        if usage_file.exists():
            with open(usage_file, 'r') as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())
                        if entry.get('type') == 'usage_captured':
                            # Parse timestamp
                            timestamp = datetime.fromisoformat(entry['timestamp'].replace('Z', '+00:00'))
                            if start_date <= timestamp <= end_date:
                                all_usage.append(entry)
                    except (json.JSONDecodeError, KeyError):
                        continue
    
    if not all_usage:
        typer.echo("No usage data found for the specified period.")
        return
    
    # Group data
    grouped_data = defaultdict(lambda: {
        'sessions': 0,
        'total_tokens': 0,
        'input_tokens': 0,
        'output_tokens': 0,
        'total_cost': 0.0
    })
    
    for entry in all_usage:
        # Determine group key
        if group_by == "phase":
            key = entry.get('phase', 'unknown')
        elif group_by == "user":
            key = entry.get('user', 'unknown')
        elif group_by == "model":
            key = entry.get('model', 'unknown')
        else:  # command_type - need to look this up from prompt audit
            key = 'unknown'  # Would need correlation with prompt audit
        
        # Aggregate data
        group = grouped_data[key]
        group['sessions'] += 1
        group['total_tokens'] += entry['tokens']['total']
        group['input_tokens'] += entry['tokens']['input']
        group['output_tokens'] += entry['tokens']['output']
        group['total_cost'] += entry['cost_usd']['total']
    
    # Calculate totals
    total_sessions = sum(g['sessions'] for g in grouped_data.values())
    total_tokens = sum(g['total_tokens'] for g in grouped_data.values())
    total_cost = sum(g['total_cost'] for g in grouped_data.values())
    
    # Output based on format
    if output_format == "json":
        output = {
            'period': {
                'start': start_date.isoformat(),
                'end': end_date.isoformat()
            },
            'summary': {
                'total_sessions': total_sessions,
                'total_tokens': total_tokens,
                'total_cost_usd': round(total_cost, 2)
            },
            'grouped_by': group_by,
            'groups': dict(grouped_data)
        }
        typer.echo(json.dumps(output, indent=2))
    
    elif output_format == "csv":
        # CSV header
        typer.echo(f"{group_by},sessions,total_tokens,input_tokens,output_tokens,cost_usd")
        for key, data in sorted(grouped_data.items()):
            typer.echo(f"{key},{data['sessions']},{data['total_tokens']},{data['input_tokens']},{data['output_tokens']},{data['total_cost']:.2f}")
    
    else:  # table format
        # Print summary
        typer.echo(f"\n📈 Summary:")
        typer.echo(f"  Total Sessions: {total_sessions:,}")
        typer.echo(f"  Total Tokens: {total_tokens:,}")
        typer.echo(f"  Total Cost: ${total_cost:.2f}")
        typer.echo(f"  Avg Tokens/Session: {total_tokens//total_sessions if total_sessions > 0 else 0:,}")
        typer.echo(f"  Avg Cost/Session: ${total_cost/total_sessions if total_sessions > 0 else 0:.2f}")
        
        # Print grouped data
        typer.echo(f"\n📊 By {group_by.title()}:")
        typer.echo("-" * 80)
        typer.echo(f"{'Group':<20} {'Sessions':>10} {'Tokens':>15} {'Cost':>10} {'Avg/Session':>12}")
        typer.echo("-" * 80)
        
        for key, data in sorted(grouped_data.items(), key=lambda x: x[1]['total_cost'], reverse=True):
            avg_tokens = data['total_tokens'] // data['sessions'] if data['sessions'] > 0 else 0
            typer.echo(
                f"{key:<20} {data['sessions']:>10,} {data['total_tokens']:>15,} "
                f"${data['total_cost']:>9.2f} {avg_tokens:>12,}"
            )
        
        typer.echo("-" * 80)
        
        # Show token efficiency metrics
        typer.echo(f"\n🎯 Token Efficiency:")
        if total_tokens > 0:
            input_pct = (sum(g['input_tokens'] for g in grouped_data.values()) / total_tokens) * 100
            output_pct = (sum(g['output_tokens'] for g in grouped_data.values()) / total_tokens) * 100
            typer.echo(f"  Input Tokens: {input_pct:.1f}%")
            typer.echo(f"  Output Tokens: {output_pct:.1f}%")
        
        # Check for estimation accuracy
        prompt_audit_files = list(metrics_dir.glob("prompt-audit-*.jsonl"))
        if prompt_audit_files:
            accuracies = []
            for audit_file in prompt_audit_files:
                with open(audit_file, 'r') as f:
                    for line in f:
                        try:
                            entry = json.loads(line.strip())
                            accuracy = entry.get('metadata', {}).get('prompt_metrics', {}).get('estimation_accuracy')
                            if accuracy is not None:
                                accuracies.append(accuracy)
                        except:
                            continue
            
            if accuracies:
                avg_accuracy = sum(accuracies) / len(accuracies)
                typer.echo(f"\n📏 Estimation Accuracy:")
                typer.echo(f"  Average Error: {abs(avg_accuracy):.1f}%")
                typer.echo(f"  Samples: {len(accuracies)}")


@app.command()
def append_status(
    entry_type: str = Argument(..., help="Type of status entry"),
    data: str = Argument(..., help="JSON data for the entry"),
    timeout: int = Option(5, help="Lock timeout in seconds")
):
    """Append status entry to pipeline log with thread-safe locking."""
    import fcntl
    import time
    import errno
    
    # Parse JSON data
    try:
        entry_data = json.loads(data)
    except json.JSONDecodeError as e:
        typer.echo(f"Error: Invalid JSON data - {e}", err=True)
        raise typer.Exit(1)
    
    # Paths
    json_path = Path("docs/ci-status/pipeline-log.json")
    lock_path = Path(".claude/status.lock")
    
    # Ensure directories exist
    json_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Acquire lock with timeout
    start_time = time.time()
    with open(lock_path, "w") as lock_file:
        while True:
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except IOError as e:
                if e.errno != errno.EWOULDBLOCK:
                    raise
                
                elapsed = time.time() - start_time
                if elapsed >= timeout:
                    typer.echo(f"Error: Could not acquire lock after {timeout} seconds", err=True)
                    raise typer.Exit(1)
                
                # Exponential backoff with jitter
                backoff = min(0.1 * (2 ** (elapsed // 1)), 1.0)
                time.sleep(backoff * (0.5 + 0.5 * time.time() % 1))
        
        try:
            # Read existing data
            if json_path.exists():
                with open(json_path, 'r') as f:
                    status_data = json.load(f)
            else:
                status_data = {"activities": [], "phase_history": []}
            
            # Create entry
            entry = {
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "type": entry_type,
                "details": entry_data
            }
            
            # Append to activities
            if "activities" not in status_data:
                status_data["activities"] = []
            status_data["activities"].append(entry)
            
            # Keep only last 1000 activities
            if len(status_data["activities"]) > 1000:
                status_data["activities"] = status_data["activities"][-1000:]
            
            # Write back
            with open(json_path, 'w') as f:
                json.dump(status_data, f, indent=2, default=str)
            
            typer.echo(f"✅ Status updated: {entry_type}")
            
        finally:
            # Release lock
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


@app.command()
def rotate_status(
    max_age_days: int = Option(30, help="Maximum age of entries to keep"),
    max_size_mb: int = Option(5, help="Maximum file size before rotation"),
    dry_run: bool = Option(False, help="Show what would be done without doing it")
):
    """Rotate status logs to prevent unbounded growth."""
    json_path = Path("docs/ci-status/pipeline-log.json")
    archive_dir = Path("docs/ci-status/archive")
    
    if not json_path.exists():
        typer.echo("No status log to rotate")
        return
    
    # Check size
    size_mb = json_path.stat().st_size / (1024 * 1024)
    needs_rotation = False
    reason = ""
    
    if size_mb > max_size_mb:
        needs_rotation = True
        reason = f"Size {size_mb:.2f}MB exceeds {max_size_mb}MB limit"
    else:
        # Check age
        try:
            with open(json_path) as f:
                data = json.load(f)
        except json.JSONDecodeError:
            typer.echo("Error: Invalid JSON in status log", err=True)
            raise typer.Exit(1)
        
        if data.get("activities"):
            oldest_timestamp = None
            for activity in data["activities"]:
                if "timestamp" in activity:
                    ts = datetime.fromisoformat(activity["timestamp"].replace("Z", "+00:00"))
                    if oldest_timestamp is None or ts < oldest_timestamp:
                        oldest_timestamp = ts
            
            if oldest_timestamp:
                age_days = (datetime.now(timezone.utc) - oldest_timestamp).days
                if age_days > max_age_days:
                    needs_rotation = True
                    reason = f"Oldest entry is {age_days} days old (max: {max_age_days})"
    
    if not needs_rotation:
        typer.echo(f"No rotation needed (size: {size_mb:.2f}MB)")
        return
    
    typer.echo(f"Rotation needed: {reason}")
    
    if dry_run:
        typer.echo("Dry run - no changes made")
        return
    
    # Create archive
    archive_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    archive_file = archive_dir / f"pipeline-log-{timestamp}.json"
    
    # Copy to archive
    import shutil
    shutil.copy2(json_path, archive_file)
    typer.echo(f"Archived to: {archive_file}")
    
    # Filter entries
    cutoff_date = datetime.now(timezone.utc) - timedelta(days=max_age_days)
    
    with open(json_path) as f:
        data = json.load(f)
    
    # Filter activities
    if "activities" in data:
        original_count = len(data["activities"])
        data["activities"] = [
            a for a in data["activities"]
            if datetime.fromisoformat(a["timestamp"].replace("Z", "+00:00")) > cutoff_date
        ]
        removed_count = original_count - len(data["activities"])
        typer.echo(f"Removed {removed_count} old activities")
    
    # Write filtered data
    with open(json_path, 'w') as f:
        json.dump(data, f, indent=2, default=str)
    
    typer.echo("✅ Rotation complete")


@app.command()
def tips():
    """Show helpful tips and common CI commands."""
    tips_text = """
🚀 NeXTRust CI Tips & Common Commands

📋 Most Used Commands:
  nextrust update-status "Build started" --phase build
  nextrust get-phase
  nextrust check-known-issue "error message" --cpu-variant m68040
  nextrust github-comment 123 "Status update"
  nextrust usage-report --days 7 --group-by phase

🔧 Common CI Flags:
  --phase <id>      Specify pipeline phase (build, test, deploy)
  --metadata <json> Add structured metadata to logs
  --dry-run         Preview without making changes
  --status-type     Log level: info, warning, error, success

💡 Slash Commands:
  /ci-help          Show all available CI commands
  /ci-usage         Display token usage statistics
  /ci-status        Check current pipeline status
  /ci-review gemini Request AI code review

📊 Token Savings:
  Build logs are automatically summarized when >10KB
  Check metrics: cat docs/ci-status/metrics/summarizer-*.jsonl

🔍 Debugging:
  export CLAUDE_CODE_DEBUG=1  # Enable debug output
  tail -f docs/ci-status/pipeline-log.json
  
📚 Documentation:
  docs/infrastructure/ci-pipeline.md
  docs/infrastructure/claude-code-deep-integration.md
  
💬 Get Help:
  nextrust --help            # Command help
  nextrust <command> --help  # Specific command help
"""
    typer.echo(tips_text)


if __name__ == "__main__":
    app()