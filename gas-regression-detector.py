#!/usr/bin/env python3
"""
Gas Regression Detector

Tracks gas cost changes against baseline to detect regressions.
Usage: python3 gas-regression-detector.py [--baseline | --check | --update]
"""

import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Tuple


class GasRegressor:
    def __init__(self, baseline_file: str = ".gas-benchmarks.json"):
        self.baseline_file = baseline_file
        self.baseline = self._load_baseline()

    def _load_baseline(self) -> Dict[str, Any]:
        """Load baseline measurements from JSON file."""
        with open(self.baseline_file, "r") as f:
            return json.load(f)

    def run_gas_report(self) -> Dict[str, Any]:
        """Execute targeted gas tests and extract measurements."""
        metrics = {}
        test_cases = {
            "settlementCreation": "test_executionCoordinatorApprovesAndAuthorizesSettlement",
            "settlementExecution": "test_completeSettlementMarksSettlementCompleted",
            "signatureVerification": "test_signedPayloadIsAcceptedAndStored",
            "hookCallback": "test_beforeSwapIntegrationAppliesVerifiedPayload",
        }

        for metric_name, test_name in test_cases.items():
            try:
                result = subprocess.run(
                    ["forge", "test", "--match-test", test_name, "-vv"],
                    cwd="/home/lukman12/MEV-SHIELD",
                    capture_output=True,
                    text=True,
                    timeout=120,
                )
                gas_value = self._parse_test_output(result.stdout)
                if gas_value:
                    metrics[metric_name] = {
                        "avg": gas_value,
                        "min": gas_value,
                        "median": gas_value,
                        "max": gas_value,
                    }
            except Exception as e:
                print(f"⚠️  Could not measure {metric_name}: {e}")

        return metrics

    def _parse_test_output(self, output: str) -> int:
        """Extract gas value from test output."""
        import re

        match = re.search(r"\(gas:\s*(\d+)\)", output)
        if match:
            return int(match.group(1))
        return 0

    def check_regression(
        self, current: Dict[str, Any]
    ) -> Tuple[str, Dict[str, Any]]:
        """Compare current measurements against baseline."""
        status = "✅ PASS"
        results = {}

        for op_name, op_baseline in self.baseline.get("operations", {}).items():
            if op_name not in current:
                continue

            current_avg = current[op_name].get("avg", 0)
            baseline_avg = op_baseline.get("current", {}).get("avg", 0)
            target = op_baseline.get("target")

            if baseline_avg == 0:
                continue

            increase_pct = (current_avg - baseline_avg) / baseline_avg
            threshold_yellow = self.baseline["regressionThresholds"]["yellow"][
                "maxIncrease"
            ]
            threshold_red = self.baseline["regressionThresholds"]["red"]["maxIncrease"]

            result = {
                "baseline": baseline_avg,
                "current": current_avg,
                "change": current_avg - baseline_avg,
                "changePercent": increase_pct * 100,
                "target": target,
                "status": "✅",
            }

            if increase_pct > threshold_red:
                result["status"] = "🔴"
                status = "🔴 REGRESSION DETECTED"
            elif increase_pct > threshold_yellow:
                result["status"] = "🟡"
                if status != "🔴 REGRESSION DETECTED":
                    status = "🟡 WARNING"

            results[op_name] = result

        return status, results

    def print_report(self, results: Dict[str, Any], status: str):
        """Print formatted regression report."""
        print("\n" + "=" * 80)
        print(f"Gas Regression Report — {datetime.now().isoformat()}")
        print("=" * 80 + "\n")

        print(f"Status: {status}\n")

        for op_name, metrics in results.items():
            op_display = op_name.replace("_", " ").title()
            icon = metrics.pop("status")

            baseline = metrics.pop("baseline")
            current = metrics.pop("current")
            change = metrics.pop("change")
            change_pct = metrics.pop("changePercent")
            target = metrics.pop("target")

            print(f"{icon} {op_display}")
            print(f"   Baseline: {baseline:,} gas")
            print(f"   Current:  {current:,} gas")
            print(f"   Change:   {change:+,} gas ({change_pct:+.1f}%)")
            if target:
                print(f"   Target:   {target:,} gas")
                utilization = (current / target) * 100
                print(f"   Used:     {utilization:.0f}% of target")
            print()

        print("=" * 80)

    def save_report(self, current: Dict[str, Any]):
        """Save current measurements as new baseline."""
        self.baseline["benchmarkDate"] = datetime.now().isoformat().split("T")[0]
        for op_name, metrics in current.items():
            if op_name in self.baseline["operations"]:
                self.baseline["operations"][op_name]["current"] = metrics

        with open(self.baseline_file, "w") as f:
            json.dump(self.baseline, f, indent=2)

        print(f"✅ Baseline updated and saved to {self.baseline_file}")


def main():
    regressor = GasRegressor()

    if len(sys.argv) > 1:
        if sys.argv[1] == "--baseline":
            print("📊 Generating fresh gas report baseline...")
            current = regressor.run_gas_report()
            regressor.save_report(current)
            return

        elif sys.argv[1] == "--update":
            print("📊 Updating baseline with current measurements...")
            current = regressor.run_gas_report()
            regressor.save_report(current)
            return

    print("📊 Running gas regression check...")
    current = regressor.run_gas_report()
    status, results = regressor.check_regression(current)
    regressor.print_report(results, status)

    if "REGRESSION DETECTED" in status:
        sys.exit(1)


if __name__ == "__main__":
    main()
