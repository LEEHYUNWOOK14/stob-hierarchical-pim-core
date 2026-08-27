#!/usr/bin/env python3
"""Compare GR00T PyTorch BF16 golden rows with RTL output rows."""

from __future__ import annotations

import csv
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/groot_normalization/results/actual_groot"
VECTORS = BASE / "rtl_accuracy_vectors"
RESULTS = BASE / "rtl_accuracy_results"
THRESHOLD = 0.025


def read_hex(path: Path) -> list[int]:
    return [int(word, 16) for word in path.read_text(encoding="ascii").split()]


def bf16_float(word: int) -> float:
    return struct.unpack(">f", struct.pack(">I", word << 16))[0]


def ordered(word: int) -> int:
    return 0x8000 - (word & 0x7FFF) if word & 0x8000 else 0x8000 + word


def main() -> int:
    cases = list(csv.DictReader((VECTORS / "cases.csv").open(encoding="utf-8")))
    rows = []
    for case in cases:
        profile = case["profile_id"]
        expected_bits = read_hex(Path(ROOT, case["expected_file"]))
        actual_bits = read_hex(RESULTS / f"{profile}_actual.hex")
        if len(expected_bits) != len(actual_bits):
            raise RuntimeError(f"length mismatch for {profile}")
        expected = [bf16_float(word) for word in expected_bits]
        actual = [bf16_float(word) for word in actual_bits]
        abs_errors = [abs(a - e) for a, e in zip(actual, expected)]
        rel_errors = [error / max(abs(e), 1.0e-12) for error, e in zip(abs_errors, expected)]
        ulps = [abs(ordered(a) - ordered(e)) for a, e in zip(actual_bits, expected_bits)]
        nonfinite = sum(not math.isfinite(value) for value in actual)
        exact = sum(a == e for a, e in zip(actual_bits, expected_bits))
        max_index = max(range(len(abs_errors)), key=abs_errors.__getitem__)
        row = {
            "profile_id": profile,
            "hidden_size": len(actual),
            "samples": len(actual),
            "bit_exact_matches": exact,
            "bit_exact_mismatches": len(actual) - exact,
            "bit_exact_rate": exact / len(actual),
            "max_abs": max(abs_errors),
            "mean_abs": sum(abs_errors) / len(abs_errors),
            "max_rel": max(rel_errors),
            "mean_rel": sum(rel_errors) / len(rel_errors),
            "rmse": math.sqrt(sum(error * error for error in abs_errors) / len(abs_errors)),
            "max_ulp": max(ulps),
            "mean_ulp": sum(ulps) / len(ulps),
            "nonfinite": nonfinite,
            "worst_index": max_index,
            "worst_expected_bf16": f"{expected_bits[max_index]:04x}",
            "worst_actual_bf16": f"{actual_bits[max_index]:04x}",
            "max_abs_threshold": THRESHOLD,
            "result": "PASS" if nonfinite == 0 and max(abs_errors) <= THRESHOLD else "FAIL",
            "source_classification": case["source_classification"],
        }
        rows.append(row)
    with (RESULTS / "accuracy_summary.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = {
        "threshold_policy": "pre-existing project max_abs <= 0.025",
        "source_classification": rows[0]["source_classification"],
        "profiles": rows,
        "passed_profiles": sum(row["result"] == "PASS" for row in rows),
        "failed_profiles": sum(row["result"] == "FAIL" for row in rows),
        "overall_result": "PASS" if all(row["result"] == "PASS" for row in rows) else "FAIL",
    }
    (RESULTS / "accuracy_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(
        "GROOT_RTL_ACCURACY_ANALYSIS "
        f"result={summary['overall_result']} passed={summary['passed_profiles']} "
        f"failed={summary['failed_profiles']} threshold={THRESHOLD}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
