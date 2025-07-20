#!/usr/bin/env python3
"""
NeXTRust AI Budget Monitor
Monitors API usage costs and enforces budget limits for AI services.
"""

import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import typer
from collections import defaultdict

app = typer.Typer(help="NeXTRust AI Budget Monitoring and Enforcement")

# Configuration paths
PRICING_CONFIG = Path("ci/config/model-pricing.json")
METRICS_DIR = Path("docs/ci-status/metrics")
USAGE_DIR = Path("docs/ci-status/usage")
BUDGET_STATE = Path(".claude/budget-state.json")

class BudgetMonitor:
    def __init__(self):
        self.pricing_config = self._load_pricing_config()
        self.budget_state = self._load_budget_state()
        
    def _load_pricing_config(self) -> Dict:
        """Load model pricing and limits configuration."""
        if not PRICING_CONFIG.exists():
            typer.echo(f"❌ Pricing config not found: {PRICING_CONFIG}", err=True)
            sys.exit(1)
            
        with open(PRICING_CONFIG) as f:
            return json.load(f)
    
    def _load_budget_state(self) -> Dict:
        """Load current budget state or create new one."""
        if BUDGET_STATE.exists():
            with open(BUDGET_STATE) as f:
                return json.load(f)
        else:
            # Initialize empty budget state
            return {
                "daily_usage": {},
                "monthly_usage": {},
                "last_reset": {
                    "daily": None,
                    "monthly": None
                },
                "violations": []
            }
    
    def _save_budget_state(self):
        """Save current budget state to disk."""
        BUDGET_STATE.parent.mkdir(parents=True, exist_ok=True)
        with open(BUDGET_STATE, 'w') as f:
            json.dump(self.budget_state, f, indent=2)
    
    def _get_current_usage(self, days: int = 1) -> Dict[str, Dict[str, float]]:
        """Calculate current usage from metrics files."""
        usage_stats = defaultdict(lambda: defaultdict(float))
        cutoff_date = datetime.now().replace(tzinfo=None) - timedelta(days=days)
        
        # Process usage logs
        if USAGE_DIR.exists():
            for usage_file in USAGE_DIR.glob("*.jsonl"):
                try:
                    with open(usage_file) as f:
                        for line in f:
                            try:
                                entry = json.loads(line.strip())
                                
                                # Parse timestamp
                                timestamp_str = entry.get("timestamp", "")
                                if timestamp_str:
                                    entry_time = datetime.fromisoformat(timestamp_str.replace("Z", "+00:00")).replace(tzinfo=None)
                                    if entry_time >= cutoff_date:
                                        service = entry.get("service", entry.get("model", "unknown"))
                                        usage_stats[service]["calls"] += 1
                                        usage_stats[service]["cost_usd"] += entry.get("cost_usd", 0.0)
                                        usage_stats[service]["tokens_in"] += entry.get("tokens_in", 0)
                                        usage_stats[service]["tokens_out"] += entry.get("tokens_out", 0)
                            except (json.JSONDecodeError, ValueError, KeyError):
                                continue
                except (OSError, IOError):
                    continue
        
        return dict(usage_stats)
    
    def check_usage_limits(self, service: str, requested_operation: str = "request") -> Tuple[bool, List[str]]:
        """Check if a service request would violate usage limits."""
        violations = []
        
        # Get service config
        pricing = self.pricing_config.get("prices_per_million_tokens", {})
        service_config = pricing.get(service, {})
        limits = service_config.get("usage_limits", {})
        
        if not limits:
            return True, []  # No limits configured
        
        # Get current usage
        daily_usage = self._get_current_usage(days=1)
        hourly_usage = self._get_current_usage(days=1/24)  # Last hour
        monthly_usage = self._get_current_usage(days=30)
        
        service_daily = daily_usage.get(service, {})
        service_hourly = hourly_usage.get(service, {})
        service_monthly = monthly_usage.get(service, {})
        
        # Check daily request limit
        max_daily_requests = limits.get("max_requests_per_day", float('inf'))
        if service_daily.get("calls", 0) >= max_daily_requests:
            violations.append(f"Daily request limit exceeded: {service_daily.get('calls', 0)}/{max_daily_requests}")
        
        # Check hourly request limit
        max_hourly_requests = limits.get("max_requests_per_hour", float('inf'))
        if service_hourly.get("calls", 0) >= max_hourly_requests:
            violations.append(f"Hourly request limit exceeded: {service_hourly.get('calls', 0)}/{max_hourly_requests}")
        
        # Check daily cost limit
        max_daily_cost = limits.get("max_cost_per_day", float('inf'))
        if service_daily.get("cost_usd", 0) >= max_daily_cost:
            violations.append(f"Daily cost limit exceeded: ${service_daily.get('cost_usd', 0):.2f}/${max_daily_cost:.2f}")
        
        # Check monthly cost limit
        max_monthly_cost = limits.get("max_cost_per_month", float('inf'))
        if service_monthly.get("cost_usd", 0) >= max_monthly_cost:
            violations.append(f"Monthly cost limit exceeded: ${service_monthly.get('cost_usd', 0):.2f}/${max_monthly_cost:.2f}")
        
        return len(violations) == 0, violations
    
    def enforce_cooldown(self, service: str) -> Tuple[bool, Optional[int]]:
        """Check if service is in cooldown period."""
        pricing = self.pricing_config.get("prices_per_million_tokens", {})
        service_config = pricing.get(service, {})
        limits = service_config.get("usage_limits", {})
        
        cooldown_minutes = limits.get("cooldown_minutes", 0)
        if cooldown_minutes <= 0:
            return True, None  # No cooldown configured
        
        # Check last request time for this service
        last_request_key = f"last_request_{service}"
        last_request_time = self.budget_state.get(last_request_key)
        
        if last_request_time:
            last_time = datetime.fromisoformat(last_request_time)
            cooldown_end = last_time + timedelta(minutes=cooldown_minutes)
            
            if datetime.now() < cooldown_end:
                remaining_minutes = int((cooldown_end - datetime.now()).total_seconds() / 60)
                return False, remaining_minutes
        
        return True, None
    
    def record_request(self, service: str, cost_usd: float = 0.0):
        """Record a service request in budget state."""
        now = datetime.now().isoformat()
        
        # Update last request time
        self.budget_state[f"last_request_{service}"] = now
        
        # Initialize usage tracking if needed
        today = datetime.now().strftime("%Y-%m-%d")
        month = datetime.now().strftime("%Y-%m")
        
        if "daily_usage" not in self.budget_state:
            self.budget_state["daily_usage"] = {}
        if "monthly_usage" not in self.budget_state:
            self.budget_state["monthly_usage"] = {}
        
        # Initialize service usage if needed
        if service not in self.budget_state["daily_usage"]:
            self.budget_state["daily_usage"][service] = {}
        if service not in self.budget_state["monthly_usage"]:
            self.budget_state["monthly_usage"][service] = {}
        
        # Record daily usage
        if today not in self.budget_state["daily_usage"][service]:
            self.budget_state["daily_usage"][service][today] = {"requests": 0, "cost_usd": 0.0}
        
        self.budget_state["daily_usage"][service][today]["requests"] += 1
        self.budget_state["daily_usage"][service][today]["cost_usd"] += cost_usd
        
        # Record monthly usage
        if month not in self.budget_state["monthly_usage"][service]:
            self.budget_state["monthly_usage"][service][month] = {"requests": 0, "cost_usd": 0.0}
        
        self.budget_state["monthly_usage"][service][month]["requests"] += 1
        self.budget_state["monthly_usage"][service][month]["cost_usd"] += cost_usd
        
        self._save_budget_state()

@app.command()
def check(
    service: str = typer.Argument(..., help="Service to check (gemini, o3)"),
    operation: str = typer.Option("request", help="Operation type"),
    cost: float = typer.Option(0.0, help="Estimated cost for the operation")
):
    """Check if a service request is allowed under current budget limits."""
    monitor = BudgetMonitor()
    
    # Check usage limits
    allowed, violations = monitor.check_usage_limits(service, operation)
    
    # Check cooldown
    cooldown_ok, remaining_minutes = monitor.enforce_cooldown(service)
    
    if not allowed:
        typer.echo("❌ Budget limit violations:", err=True)
        for violation in violations:
            typer.echo(f"  • {violation}", err=True)
        sys.exit(1)
    
    if not cooldown_ok:
        typer.echo(f"⏳ Service {service} is in cooldown. Wait {remaining_minutes} minutes.", err=True)
        sys.exit(1)
    
    # Check estimated cost against daily limits
    if cost > 0:
        daily_usage = monitor._get_current_usage(days=1)
        service_usage = daily_usage.get(service, {})
        current_daily_cost = service_usage.get("cost_usd", 0)
        
        pricing = monitor.pricing_config.get("prices_per_million_tokens", {})
        service_config = pricing.get(service, {})
        limits = service_config.get("usage_limits", {})
        max_daily_cost = limits.get("max_cost_per_day", float('inf'))
        
        if current_daily_cost + cost > max_daily_cost:
            typer.echo(f"❌ Estimated cost ${cost:.2f} would exceed daily limit: ${current_daily_cost:.2f} + ${cost:.2f} > ${max_daily_cost:.2f}", err=True)
            sys.exit(1)
    
    typer.echo(f"✅ Service {service} request approved")
    
    # Optionally record the request if --record flag is used
    if cost > 0:
        monitor.record_request(service, cost)
        typer.echo(f"📊 Recorded request: ${cost:.2f}")

@app.command()
def status(
    days: int = typer.Option(7, help="Number of days to analyze"),
    service: Optional[str] = typer.Option(None, help="Filter by service")
):
    """Show current budget status and usage."""
    monitor = BudgetMonitor()
    
    typer.echo(f"💰 NeXTRust AI Budget Status (Last {days} Days)")
    typer.echo("=" * 60)
    
    # Get usage data
    usage_data = monitor._get_current_usage(days=days)
    
    total_cost = 0.0
    
    for svc, stats in usage_data.items():
        if service and svc != service:
            continue
            
        cost = stats.get("cost_usd", 0)
        calls = stats.get("calls", 0)
        total_cost += cost
        
        typer.echo(f"\n🧠 {svc.title()}")
        typer.echo(f"  📞 Requests: {calls}")
        typer.echo(f"  💸 Cost: ${cost:.2f}")
        typer.echo(f"  📥 Tokens In: {stats.get('tokens_in', 0):,}")
        typer.echo(f"  📤 Tokens Out: {stats.get('tokens_out', 0):,}")
        
        # Show limits
        pricing = monitor.pricing_config.get("prices_per_million_tokens", {})
        service_config = pricing.get(svc, {})
        limits = service_config.get("usage_limits", {})
        
        if limits:
            typer.echo(f"  📋 Limits:")
            for limit_type, limit_value in limits.items():
                if limit_type.startswith("max_"):
                    typer.echo(f"    {limit_type}: {limit_value}")
    
    typer.echo(f"\n💰 Total Cost: ${total_cost:.2f}")
    
    # Budget warnings
    thresholds = monitor.pricing_config.get("thresholds", {})
    daily_warning = thresholds.get("cost_per_day", {}).get("warning", 50.0)
    daily_critical = thresholds.get("cost_per_day", {}).get("critical", 200.0)
    
    if total_cost > daily_critical:
        typer.echo(f"🚨 CRITICAL: Cost exceeds ${daily_critical:.2f} threshold", err=True)
    elif total_cost > daily_warning:
        typer.echo(f"⚠️  WARNING: Cost exceeds ${daily_warning:.2f} threshold")

@app.command()
def reset(
    service: Optional[str] = typer.Option(None, help="Service to reset (or all)"),
    confirm: bool = typer.Option(False, "--confirm", help="Confirm the reset")
):
    """Reset budget state for a service or all services."""
    if not confirm:
        typer.echo("⚠️  This will reset budget tracking. Use --confirm to proceed.")
        sys.exit(1)
    
    monitor = BudgetMonitor()
    
    if service:
        # Reset specific service
        for key in list(monitor.budget_state.keys()):
            if service in key:
                del monitor.budget_state[key]
        typer.echo(f"✅ Reset budget state for {service}")
    else:
        # Reset all
        monitor.budget_state = {
            "daily_usage": {},
            "monthly_usage": {},
            "last_reset": {
                "daily": datetime.now().isoformat(),
                "monthly": datetime.now().isoformat()
            },
            "violations": []
        }
        typer.echo("✅ Reset all budget state")
    
    monitor._save_budget_state()

@app.command()
def alert(
    threshold: float = typer.Option(10.0, help="Cost threshold for alert"),
    days: int = typer.Option(1, help="Days to check")
):
    """Check if current usage exceeds threshold and send alerts."""
    monitor = BudgetMonitor()
    
    usage_data = monitor._get_current_usage(days=days)
    total_cost = sum(stats.get("cost_usd", 0) for stats in usage_data.values())
    
    if total_cost > threshold:
        alert_msg = f"🚨 AI Budget Alert: ${total_cost:.2f} exceeds ${threshold:.2f} threshold in last {days} days"
        typer.echo(alert_msg, err=True)
        
        # Log alert
        alert_record = {
            "timestamp": datetime.now().isoformat(),
            "threshold": threshold,
            "actual_cost": total_cost,
            "days": days,
            "usage_breakdown": usage_data
        }
        
        monitor.budget_state.setdefault("violations", []).append(alert_record)
        monitor._save_budget_state()
        
        # TODO: Send to Slack/email if configured
        sys.exit(1)
    else:
        typer.echo(f"✅ Usage ${total_cost:.2f} is within ${threshold:.2f} threshold")

if __name__ == "__main__":
    app()