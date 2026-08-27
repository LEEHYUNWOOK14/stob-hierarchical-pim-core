#!/usr/bin/env python3
"""Decompose actual GR00T-row BF16 RTL error by normalization stage."""

from __future__ import annotations

import csv
import json
import math
import re
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/groot_normalization/results/actual_groot"
VECTORS = BASE / "rtl_accuracy_vectors"
RESULTS = BASE / "rtl_accuracy_results"
RTL_LINE = re.compile(r"profile=(\S+).* mean=([0-9a-fA-F]+) inv=([0-9a-fA-F]+)")


def read_hex(path: Path) -> list[int]:
    return [int(word, 16) for word in path.read_text(encoding="ascii").split()]


def as_float(word: int) -> float:
    return struct.unpack(">f", struct.pack(">I", word << 16))[0]


def as_bits(value: float) -> int:
    if math.isnan(value):
        return 0x7FC0
    word = struct.unpack(">I", struct.pack(">f", float(value)))[0]
    if (word & 0x7F800000) != 0x7F800000:
        word += 0x7FFF + ((word >> 16) & 1)
    return (word >> 16) & 0xFFFF


def q(value: float) -> float:
    return as_float(as_bits(value))


def qadd(lhs: float, rhs: float) -> float:
    return q(q(lhs) + q(rhs))


def qmul(lhs: float, rhs: float) -> float:
    return q(q(lhs) * q(rhs))


def rtl_rsqrt(value: float) -> float:
    """Match bf16_rsqrt_lut256: midpoint LUT, no Newton iteration."""
    value = q(value)
    if math.isnan(value) or value < 0:
        return math.nan
    if value == 0:
        return math.inf
    if math.isinf(value):
        return 0.0
    mantissa, exponent = math.frexp(value)
    mantissa *= 2.0
    exponent -= 1
    if exponent & 1:
        mantissa *= 2.0
        exponent -= 1
    index = min(255, max(0, int((mantissa - 1.0) * 256.0 / 3.0)))
    midpoint = 1.0 + (index + 0.5) * 3.0 / 256.0
    return q(math.ldexp(q(1.0 / math.sqrt(midpoint)), -(exponent // 2)))


def rtl_reduction(values: list[float], banks: int = 16) -> tuple[float, float]:
    per_bank = len(values) // banks
    partials: list[tuple[float, float]] = []
    for bank in range(banks):
        total = 0.0
        sumsq = 0.0
        for local_index in range(per_bank):
            column = (local_index // 4) * banks * 4 + bank * 4 + local_index % 4
            value = values[column]
            total = qadd(total, value)
            sumsq = qadd(sumsq, qmul(value, value))
        partials.append((total, sumsq))
    total = 0.0
    sumsq = 0.0
    for partial_sum, partial_sumsq in partials:
        total = qadd(total, partial_sum)
        sumsq = qadd(sumsq, partial_sumsq)
    return total, sumsq


def rtl_scalars(values: list[float], epsilon: float) -> dict[str, float]:
    total, sumsq = rtl_reduction(values)
    inv_hidden = q(1.0 / len(values))
    mean = qmul(total, inv_hidden)
    mean_square = qmul(sumsq, inv_hidden)
    mean_squared = qmul(mean, mean)
    variance_raw = qadd(mean_square, -mean_squared)
    variance = 0.0 if variance_raw < 0.0 else variance_raw
    argument = qadd(variance, q(epsilon))
    inv_std = rtl_rsqrt(argument)
    return {
        "sum": total,
        "sumsq": sumsq,
        "mean": mean,
        "mean_square": mean_square,
        "mean_squared": mean_squared,
        "variance": variance,
        "rsqrt_argument": argument,
        "inv_std": inv_std,
    }


def apply(values: list[float], gamma: list[float], beta: list[float], mean: float, inv: float) -> list[int]:
    output = []
    for x, weight, bias in zip(values, gamma, beta):
        centered = qadd(x, -mean)
        normalized = qmul(centered, inv)
        scaled = qmul(normalized, weight)
        output.append(as_bits(qadd(scaled, bias)))
    return output


def metrics(actual_bits: list[int], expected_bits: list[int]) -> dict[str, float | int]:
    errors = [abs(as_float(a) - as_float(e)) for a, e in zip(actual_bits, expected_bits)]
    return {
        "bit_mismatches": sum(a != e for a, e in zip(actual_bits, expected_bits)),
        "max_abs": max(errors),
        "mean_abs": sum(errors) / len(errors),
        "rmse": math.sqrt(sum(error * error for error in errors) / len(errors)),
    }


def main() -> int:
    cases = list(csv.DictReader((VECTORS / "cases.csv").open(encoding="utf-8")))
    logged = {}
    for match in RTL_LINE.finditer((RESULTS / "rtl_runs.log").read_text(encoding="utf-8")):
        logged[match.group(1)] = (int(match.group(2), 16), int(match.group(3), 16))
    rows = []
    details = {}
    for case in cases:
        profile = case["profile_id"]
        x = [as_float(v) for v in read_hex(ROOT / case["x_file"])]
        gamma = [as_float(v) for v in read_hex(ROOT / case["gamma_file"])]
        beta = [as_float(v) for v in read_hex(ROOT / case["beta_file"])]
        expected = read_hex(ROOT / case["expected_file"])
        actual = read_hex(RESULTS / f"{profile}_actual.hex")
        epsilon = float(case["epsilon"])
        staged = rtl_scalars(x, epsilon)
        logged_mean_bits, logged_inv_bits = logged[profile]
        logged_mean, logged_inv = as_float(logged_mean_bits), as_float(logged_inv_bits)
        canonical_mean = sum(x) / len(x)
        canonical_variance = sum((value - canonical_mean) ** 2 for value in x) / len(x)
        canonical_inv = 1.0 / math.sqrt(canonical_variance + epsilon)
        replay_logged = apply(x, gamma, beta, logged_mean, logged_inv)
        replay_canonical = apply(x, gamma, beta, q(canonical_mean), q(canonical_inv))
        actual_metrics = metrics(actual, expected)
        logged_metrics = metrics(replay_logged, expected)
        canonical_metrics = metrics(replay_canonical, expected)
        row = {
            "profile_id": profile,
            "hidden_size": len(x),
            "rtl_mean_hex": f"{logged_mean_bits:04x}",
            "emulated_mean_hex": f"{as_bits(staged['mean']):04x}",
            "canonical_mean": canonical_mean,
            "rtl_mean_abs_error": abs(logged_mean - canonical_mean),
            "rtl_inv_std_hex": f"{logged_inv_bits:04x}",
            "emulated_inv_std_hex": f"{as_bits(staged['inv_std']):04x}",
            "canonical_inv_std": canonical_inv,
            "rtl_inv_std_abs_error": abs(logged_inv - canonical_inv),
            "rtl_emulation_bit_mismatches": sum(a != b for a, b in zip(actual, replay_logged)),
            "rtl_vs_pytorch_max_abs": actual_metrics["max_abs"],
            "rtl_vs_pytorch_mean_abs": actual_metrics["mean_abs"],
            "canonical_scalar_rtl_apply_vs_pytorch_max_abs": canonical_metrics["max_abs"],
            "canonical_scalar_rtl_apply_vs_pytorch_mean_abs": canonical_metrics["mean_abs"],
            "logged_scalar_rtl_apply_vs_pytorch_max_abs": logged_metrics["max_abs"],
            "dominant_stage": "reduction/scalar" if float(actual_metrics["max_abs"]) > float(canonical_metrics["max_abs"]) else "apply_rounding",
        }
        rows.append(row)
        details[profile] = {
            "canonical": {"mean": canonical_mean, "variance": canonical_variance, "inv_std": canonical_inv},
            "rtl_staged": staged,
            "metrics": {
                "actual_rtl_vs_pytorch": actual_metrics,
                "emulated_logged_scalars_vs_pytorch": logged_metrics,
                "canonical_scalars_rtl_apply_vs_pytorch": canonical_metrics,
            },
        }
    with (RESULTS / "stage_accuracy_summary.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = {
        "method": "software emulation of the exact 16-bank BF16 reduction order, BF16 scalar datapath, LUT256 RSQRT, and four-operation BF16 affine apply",
        "all_logged_scalars_match_emulation": all(row["rtl_mean_hex"] == row["emulated_mean_hex"] and row["rtl_inv_std_hex"] == row["emulated_inv_std_hex"] for row in rows),
        "all_actual_outputs_match_emulated_apply": all(row["rtl_emulation_bit_mismatches"] == 0 for row in rows),
        "profiles": details,
    }
    (RESULTS / "stage_accuracy_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(
        "GROOT_RTL_STAGE_ANALYSIS "
        f"scalar_match={summary['all_logged_scalars_match_emulation']} "
        f"apply_match={summary['all_actual_outputs_match_emulated_apply']} profiles={len(rows)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
