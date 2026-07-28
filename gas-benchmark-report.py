#!/usr/bin/env python3
"""
Gas Benchmark Report Generator

Generates and tracks gas cost baselines for core MEV-SHIELD operations.
Usage: python3 gas-benchmark-report.py [--save-baseline]
"""

import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Tuple


class GasBenchmark:
    def __init__(self, baseline_file: str = ".gas-benchmarks.json"):
        self.baseline_file = baseline_file
        self.baseline = self._load_baseline()
        self.key_functions = {
            "settlementCreation": "coordinateSubmission",
            "settlementExecution": "completeSettlement",
            "riskAssessment": "assessRiskPolicy",
            "hookCallback": "exposeBeforeSwap",
        }

    def _load_baseline(self) -> Dict[str, Any]:
        """Load baseline measurements."""
        try:
            with open(self.baseline_file, "r") as f:
                return json.load(f)
        except FileNotFoundError:
            return {"operations": {}}

    def generate_report(self) -> Tuple[str, Dict[str, Any]]:
        """Generate gas report and compare against baseline."""
        print("📊 Generating gas report...")
        try:
            result = subprocess.run(
                ["forge", "test", "--gas-report"],
                cwd="/home/lukman12/MEV-SHIELD",
                capture_output=True,
                text=True,
                timeout=600,
            )

            if result.returncode != 0:
                print("⚠️  Forge test warnings (continuing):")
                if result.stderr:
                    print(result.stderr[:500])

            current_metrics = self._parse_gas_report(result.stdout)
            status, comparison = self._compare_metrics(current_metrics)

            return status, comparison

        except subprocess.TimeoutExpired:
            print("❌ Gas report generation timed out after 600s")
            sys.exit(1)
        except Exception as e:
            print(f"❌ Error generating report: {e}")
            sys.exit(1)

    def _parse_gas_report(self, output: str) -> Dict[str, Dict[str, int]]:
        """Extract gas metrics for key functions from forge output."""
        metrics = {}
        lines = output.split("\n")

        for func_key, func_name in self.key_functions.items():
            for i, line in enumerate(lines):
                if func_name in line and "|" in line:
                    # Parse gas values from format: | funcname | min | avg | median | max | calls |
                    values = self._extract_line_values(line)
                    if values:
                        metrics[func_key] = values
                        break

        return metrics

    def _extract_line_values(self, line: str) -> Dict[str, int]:
        """Extract numeric gas values from a gas report line."""
        # Remove pipes and split
        parts = [p.strip() for p in line.split("|")]
        # Filter out empty parts and non-numeric
        numeric_parts = []
        for part in parts:
            if part and not any(c.isalpha() for c in part if c not in "eE"):
                try:
                    numeric_parts.append(int(part))
                except ValueError:
                    pass

        if len(numeric_parts) >= 4:
            return {
                "min": numeric_parts[0],
                "avg": numeric_parts[1],
                "median": numeric_parts[2],
                "max": numeric_parts[3],
            }
        return {}

    def _compare_metrics(
        self, current: Dict[str, Dict[str, int]]
    ) -> Tuple[str, Dict[str, Any]]:
        """Compare current against baseline and return status."""
        results = {}
        status = "✅ PASS"
        thresholds = self.baseline.get("regressionThresholds", {})
        yellow_threshold = thresholds.get("yellow", {}).get("maxIncrease", 0.10)
        red_threshold = thresholds.get("red", {}).get("maxIncrease", 0.20)

        for op_key, op_baseline in self.baseline.get("operations", {}).items():
            if op_key not in current:
                continue

            baseline_avg = op_baseline.get("current", {}).get("avg", 0)
            current_avg = current[op_key].get("avg", 0)
            target = op_baseline.get("target")

            if baseline_avg == 0 or current_avg == 0:
                continue

            delta = current_avg - baseline_avg
            delta_pct = delta / baseline_avg if baseline_avg > 0 else 0

            result = {
                "baseline": baseline_avg,
                "current": current_avg,
                "delta": delta,
                "deltaPct": delta_pct * 100,
                "target": target,
                "status": "✅",
            }

            if delta_pct > red_threshold:
                result["status"] = "🔴"
                status = "🔴 REGRESSION"
            elif delta_pct > yellow_threshold:
                result["status"] = "🟡"
                if status != "🔴 REGRESSION":
                    status = "🟡 WARNING"

            results[op_key] = result

        return status, results

    def print_report(self, status: str, results: Dict[str, Any]):
        """Print formatted comparison report."""
        print("\n" + "=" * 90)
        print(f"Gas Benchmark Report — {datetime.now().isoformat()}")
        print("=" * 90 + "\n")

        print(f"Status: {status}\n")

        for op_name in [
            "settlementCreation",
            "settlementExecution",
            "riskAssessment",
            "hookCallback",
        ]:
            if op_name not in results:
                continue

            metrics = results[op_name]
            icon = metrics.pop("status")
            op_display = op_name.replace("_", " ").title()

            baseline = metrics.pop("baseline")
            current = metrics.pop("current")
            delta = metrics.pop("delta")
            delta_pct = metrics.pop("deltaPct")
            target = metrics.pop("target")

            print(f"{icon} {op_display}")
            print(f"   Baseline: {baseline:>10,} gas")
            print(f"   Current:  {current:>10,} gas")
            print(f"   Change:   {delta:>+10,} gas ({delta_pct:>+6.1f}%)")
            if target:
                print(f"   Target:   {target:>10,} gas")
                used_pct = (current / target) * 100
                bar_width = 30
                filled = int((used_pct / 100) * bar_width)
                bar = "█" * filled + "░" * (bar_width - filled)
                print(f"   Usage:    [{bar}] {used_pct:5.0f}%")
            print()

        print("=" * 90)

    def save_baseline(self, current: Dict[str, Dict[str, int]]):
        """Save current measurements as new baseline."""
        self.baseline["benchmarkDate"] = datetime.now().isoformat().split("T")[0]

        for op_key, metrics in current.items():
            if op_key in self.baseline.get("operations", {}):
                self.baseline["operations"][op_key]["current"] = metrics
            else:
                print(f"⚠️  Unknown operation: {op_key}")

        with open(self.baseline_file, "w") as f:
            json.dump(self.baseline, f, indent=2)

        print(f"✅ Baseline updated: {self.baseline_file}")


def main():
    bench = GasBenchmark()

    if "--save-baseline" in sys.argv:
        print("📊 Generating and saving new baseline...")
        _, current_metrics = bench.generate_report()
        # Extract just the current values for saving
        current_for_save = {}
        for op_key, op_current in current_metrics.items():
            current_for_save[op_key] = {
                "min": op_current.get("baseline"),  # Use baseline as reference
                "avg": op_current.get("baseline"),
                "median": op_current.get("baseline"),
                "max": op_current.get("baseline"),
            }
        return

    status, results = bench.generate_report()
    bench.print_report(status, results)

    if "REGRESSION" in status:
        sys.exit(1)


if __name__ == "__main__":
    main()
