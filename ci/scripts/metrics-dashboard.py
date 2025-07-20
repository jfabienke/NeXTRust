#!/usr/bin/env python3
"""
NeXTRust Metrics Dashboard
Generates text-based metrics dashboard from pipeline logs.
"""

import json
import glob
from collections import defaultdict
from pathlib import Path
from datetime import datetime, timedelta
import typer
from typing import Optional

def main(
    days: int = typer.Option(7, help="Number of days to analyze"),
    service: Optional[str] = typer.Option(None, help="Filter by AI service (gemini, o3)"),
    format: str = typer.Option("text", help="Output format: text, csv, json")
):
    """Generates a metrics dashboard from pipeline logs."""
    
    metrics_dir = Path("docs/ci-status/metrics")
    usage_dir = Path("docs/ci-status/usage")
    
    if not metrics_dir.exists() and not usage_dir.exists():
        print("📊 No metrics directories found. Run some CI jobs first.")
        return

    print(f"📊 NeXTRust Metrics Dashboard (Last {days} Days)")
    print("=" * 60)

    # Collect metrics from JSONL files
    pipeline_stats = defaultdict(lambda: defaultdict(int))
    ai_usage_stats = defaultdict(lambda: defaultdict(float))
    
    # Process pipeline metrics
    if metrics_dir.exists():
        for metrics_file in sorted(metrics_dir.glob("pipeline-metrics-*.jsonl"), reverse=True):
            date = metrics_file.stem.replace("pipeline-metrics-", "")
            
            with open(metrics_file, "r") as f:
                for line in f:
                    try:
                        entry = json.loads(line)
                        entry_date = datetime.fromisoformat(entry["timestamp"].replace("Z", "+00:00"))
                        if entry_date >= datetime.now() - timedelta(days=days):
                            pipeline_stats[date][entry["name"]] += int(entry.get("value", 1))
                    except (json.JSONDecodeError, KeyError, ValueError):
                        continue

    # Process AI usage metrics  
    if usage_dir.exists():
        for usage_file in sorted(usage_dir.glob("*.jsonl"), reverse=True):
            # Handle different usage log formats
            if "gemini" in usage_file.name or "token-usage" in usage_file.name:
                with open(usage_file, "r") as f:
                    for line in f:
                        try:
                            entry = json.loads(line)
                            if service and entry.get("service") != service:
                                continue
                                
                            service_name = entry.get("service", entry.get("model", "unknown"))
                            ai_usage_stats[service_name]["calls"] += 1
                            ai_usage_stats[service_name]["cost_usd"] += entry.get("cost_usd", 0.0)
                            ai_usage_stats[service_name]["tokens_in"] += entry.get("tokens_in", 0)
                            ai_usage_stats[service_name]["tokens_out"] += entry.get("tokens_out", 0)
                        except (json.JSONDecodeError, KeyError):
                            continue

    # Display results based on format
    if format == "json":
        output = {
            "pipeline_metrics": dict(pipeline_stats),
            "ai_usage": dict(ai_usage_stats),
            "period_days": days
        }
        print(json.dumps(output, indent=2))
        
    elif format == "csv":
        print("date,metric,value")
        for date, metrics in pipeline_stats.items():
            for name, value in metrics.items():
                print(f"{date},{name},{value}")
        
        print("service,calls,cost_usd,tokens_in,tokens_out")
        for service_name, stats in ai_usage_stats.items():
            print(f"{service_name},{stats['calls']},{stats['cost_usd']:.4f},{stats['tokens_in']},{stats['tokens_out']}")
            
    else:  # text format
        # Pipeline Metrics
        if pipeline_stats:
            print("\n🔧 Pipeline Metrics")
            print("-" * 40)
            for date, metrics in list(pipeline_stats.items())[:5]:  # Last 5 days
                print(f"\n📅 {date}")
                for name, value in sorted(metrics.items()):
                    # Pretty print common metrics
                    if "hook" in name:
                        print(f"  🪝 {name}: {value}")
                    elif "build" in name:
                        print(f"  🔨 {name}: {value}")
                    elif "ccusage" in name:
                        print(f"  💰 {name}: {value}")
                    else:
                        print(f"  📊 {name}: {value}")

        # AI Usage Summary
        if ai_usage_stats:
            print("\n🤖 AI Services Usage")
            print("-" * 40)
            total_cost = 0.0
            
            for service_name, stats in ai_usage_stats.items():
                total_cost += stats["cost_usd"]
                efficiency = stats["tokens_out"] / max(stats["tokens_in"], 1)
                
                print(f"\n🧠 {service_name.title()}")
                print(f"  📞 Calls: {stats['calls']}")
                print(f"  💸 Cost: ${stats['cost_usd']:.4f}")
                print(f"  📥 Tokens In: {stats['tokens_in']:,}")
                print(f"  📤 Tokens Out: {stats['tokens_out']:,}")
                print(f"  ⚡ Efficiency: {efficiency:.2f}x")
            
            print(f"\n💰 Total AI Cost: ${total_cost:.4f}")
            
            # Budget warning
            monthly_budget = 500.0  # TODO: Read from config
            if total_cost > monthly_budget * 0.8:
                print(f"⚠️  Budget Warning: {(total_cost/monthly_budget)*100:.1f}% of monthly budget used")
        
        if not pipeline_stats and not ai_usage_stats:
            print("\n🔍 No metrics found. Try running some CI jobs first.")
            
        print(f"\n📈 Report generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

if __name__ == "__main__":
    typer.run(main)