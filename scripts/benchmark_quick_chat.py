#!/usr/bin/env python3
"""Explicit synthetic-only benchmark. Uses existing account limits, never user text.

No prompts, replies, thread IDs, account data or raw diagnostics are written.
First-answer is complete-message receipt in CLI mode, NOT first-token streaming.
"""
import json
from pathlib import Path
import statistics
import subprocess
import sys
import argparse
import math
from quick_chat_benchmark_cases import CASES

PROBE = Path(__file__).with_name("probe_quick_chat_exec.py")


def summarize(samples):
    metrics = {}
    for name in ("startup", "first_answer", "completion"):
        values = [s[name] for s in samples if s.get(name) is not None]
        metrics[name] = {"median": round(statistics.median(values), 3),
                         "p95_nearest_rank": sorted(values)[math.ceil(len(values) * 0.95) - 1],
                         "slowest": max(values)} if values else None
    return {"samples": len(samples), "quality_passes": sum(s.get("quality", False) for s in samples),
            "no_thread_record": sum(s.get("no_thread_record", False) for s in samples), "metrics": metrics,
            "measurement_surface": "CLI backend, not signed-app visible text",
            "small_sample_tail_warning": len(samples) < 20}


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--old-startup", action="store_true")
    mode.add_argument("--realistic", action="store_true", help="Counterbalanced default/candidate short and long cases")
    parser.add_argument("--repetitions", type=int, choices=range(1, 6), default=2)
    options = parser.parse_args()
    configurations = [
        ("installed-default", ["--reuse-provider-state"]),
        ("default-low", ["--reuse-provider-state", "--effort", "low"]),
        ("terra-low-candidate", ["--reuse-provider-state", "--model", "gpt-5.6-terra", "--effort", "low"]),
        ("think-deeper", ["--reuse-provider-state", "--effort", "high"]),
    ]
    if options.old_startup:
        configurations = [("fresh-state-baseline", [])]
    if options.realistic:
        configurations = [configurations[0], configurations[2]]
    reports = {label: [] for label, _ in configurations}
    cases = list(CASES) if options.realistic else ["focus", "arithmetic", "format"]
    for repetition in range(options.repetitions):
        for case_index, case in enumerate(cases):
            # Alternate order to reduce systematic warm-cache/time-of-day bias.
            ordered = configurations if (repetition + case_index) % 2 == 0 else configurations[::-1]
            for label, arguments in ordered:
                try:
                    result = subprocess.run([sys.executable, str(PROBE), "--latency", "--case", case, *arguments],
                                            capture_output=True, text=True, timeout=75)
                    report = json.loads(result.stdout)
                    passed = result.returncode == 0
                except (ValueError, subprocess.TimeoutExpired):
                    report = {}
                    passed = False
                events = report.get("event_timings", [])
                def first(kind, item=None):
                    return next((e["seconds"] for e in events if e["type"] == kind and
                                 (item is None or e.get("item_type") == item)), None)
                sample = {"case": case, "repetition": repetition + 1, "passed": passed,
                          "startup": first("thread.started"),
                          "first_answer": first("item.completed", "agent_message"),
                          "completion": report.get("elapsed_seconds"),
                          "quality": report.get("quality_check", False) and report.get("expected_reply", False),
                          "no_thread_record": report.get("provider_thread_persistence") == "no-thread-record"}
                reports[label].append(sample)
                print(json.dumps({"configuration": label, **sample}), flush=True)
    print(json.dumps({"summary": {label: summarize(samples) for label, samples in reports.items()}}), flush=True)


if __name__ == "__main__":
    main()
