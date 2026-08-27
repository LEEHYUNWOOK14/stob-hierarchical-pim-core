#!/usr/bin/env python3
"""Explore mixed-precision LayerNorm datapaths on every captured GR00T row.

The model preserves the current 16-bank/4-lane order.  It distinguishes the
storage dtype (always BF16) from reduction, scalar, RSQRT and apply precision.
"""

from __future__ import annotations

import csv
import json
import math
from dataclasses import dataclass, asdict
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
TRACE = ROOT / "reports/groot_normalization/results/actual_groot/action_head_trace"
OUT = ROOT / "reports/groot_normalization/results/mixed_precision_exploration"
THRESHOLD = 0.025
BANKS = 16
LANES = 4


@dataclass(frozen=True)
class Candidate:
    candidate: str
    reduction: str
    scalar: str
    rsqrt: str
    scalar_broadcast: str
    apply: str
    change_count: int
    estimated_extra_fp32_ops_per_element: int
    estimated_extra_fp32_ops_per_row: int
    estimated_scalar_cost_units: int
    estimated_global_reduce_cycles: int


CANDIDATES = [
    Candidate("C0_CURRENT_BF16", "BF16_SEQUENTIAL", "BF16", "BF16_LUT256", "BF16", "BF16_STAGED", 0, 0, 0, 1, 16),
    Candidate("C1_FP32_REDUCE_SCALAR", "FP32_4LANE_TREE", "FP32", "BF16_LUT256", "BF16", "BF16_STAGED", 2, 2, 8, 1, 16),
    Candidate("C2_FP32_REDUCE_SCALAR_NR1", "FP32_4LANE_TREE", "FP32", "FP32_NR1", "BF16", "BF16_STAGED", 3, 2, 13, 6, 16),
    Candidate("C3_FUSED_APPLY_ONLY", "BF16_SEQUENTIAL", "BF16", "BF16_LUT256", "BF16", "FP32_FUSED", 1, 4, 0, 1, 16),
    Candidate("C4_BF16_REDUCE_FP32_SCALAR_FUSED", "BF16_SEQUENTIAL", "FP32", "FP32_NR1", "FP32", "FP32_FUSED", 3, 4, 7, 6, 16),
    Candidate("C5_FP32_REDUCE_LUT_FUSED", "FP32_4LANE_TREE", "FP32", "BF16_LUT256", "FP32", "FP32_FUSED", 3, 6, 8, 1, 16),
    Candidate("C6_FP32_REDUCE_NR1_FUSED", "FP32_4LANE_TREE", "FP32", "FP32_NR1", "FP32", "FP32_FUSED", 4, 6, 13, 6, 16),
    Candidate("C7_FP32_REDUCE_EXACT_FUSED", "FP32_4LANE_TREE", "FP32", "FP32_EXACT", "FP32", "FP32_FUSED", 4, 6, 8, 100, 16),
    Candidate("C8_CANONICAL_WELFORD_FUSED", "FP32_WELFORD", "FP32", "FP32_EXACT", "FP32", "FP32_FUSED", 5, 7, 6, 120, 16),
    Candidate("C9_FP32_REDUCE_NR2_FUSED", "FP32_4LANE_TREE", "FP32", "FP32_NR2", "FP32", "FP32_FUSED", 4, 6, 18, 11, 16),
    Candidate("C10_FP32_BALANCED_NR2_FUSED", "FP32_4LANE_BALANCED", "FP32", "FP32_NR2", "FP32", "FP32_FUSED", 4, 6, 18, 11, 4),
    Candidate("C11_FP32_INTERLEAVED4_NR2_FUSED", "FP32_INTERLEAVED4_BALANCED", "FP32", "FP32_NR2", "FP32", "FP32_FUSED", 4, 6, 18, 11, 4),
]


def read_hex(path: Path) -> np.ndarray:
    return np.fromiter((int(word, 16) for word in path.read_text(encoding="ascii").split()), dtype=np.uint16)


def bits_to_float(bits: np.ndarray) -> np.ndarray:
    return (bits.astype(np.uint32) << np.uint32(16)).view(np.float32)


def float_to_bits(values: np.ndarray) -> np.ndarray:
    values = np.asarray(values, dtype=np.float32)
    words = values.view(np.uint32)
    special = (words & np.uint32(0x7F800000)) == np.uint32(0x7F800000)
    rounded = words + np.uint32(0x7FFF) + ((words >> np.uint32(16)) & np.uint32(1))
    selected = np.where(special, words, rounded)
    return (selected >> np.uint32(16)).astype(np.uint16)


def q(values: np.ndarray) -> np.ndarray:
    return bits_to_float(float_to_bits(values))


def reduce_bf16(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    rows, hidden = x.shape
    vectors = math.ceil(hidden / (BANKS * LANES))
    layout = x.reshape(rows, vectors, BANKS, LANES)
    total = np.zeros((rows, BANKS), dtype=np.float32)
    sumsq = np.zeros((rows, BANKS), dtype=np.float32)
    for vector in range(vectors):
        for lane in range(LANES):
            value = layout[:, vector, :, lane]
            total = q(total + value)
            sumsq = q(sumsq + q(value * value))
    global_sum = np.zeros(rows, dtype=np.float32)
    global_sumsq = np.zeros(rows, dtype=np.float32)
    for bank in range(BANKS):
        global_sum = q(global_sum + total[:, bank])
        global_sumsq = q(global_sumsq + sumsq[:, bank])
    return global_sum, global_sumsq


def reduce_fp32_tree(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    rows, hidden = x.shape
    vectors = math.ceil(hidden / (BANKS * LANES))
    layout = x.reshape(rows, vectors, BANKS, LANES)
    total = np.zeros((rows, BANKS), dtype=np.float32)
    sumsq = np.zeros((rows, BANKS), dtype=np.float32)
    for vector in range(vectors):
        values = layout[:, vector]
        pair0 = np.asarray(values[:, :, 0] + values[:, :, 1], dtype=np.float32)
        pair1 = np.asarray(values[:, :, 2] + values[:, :, 3], dtype=np.float32)
        vector_sum = np.asarray(pair0 + pair1, dtype=np.float32)
        squares = np.asarray(values * values, dtype=np.float32)
        square_pair0 = np.asarray(squares[:, :, 0] + squares[:, :, 1], dtype=np.float32)
        square_pair1 = np.asarray(squares[:, :, 2] + squares[:, :, 3], dtype=np.float32)
        vector_sumsq = np.asarray(square_pair0 + square_pair1, dtype=np.float32)
        total = np.asarray(total + vector_sum, dtype=np.float32)
        sumsq = np.asarray(sumsq + vector_sumsq, dtype=np.float32)
    global_sum = np.zeros(rows, dtype=np.float32)
    global_sumsq = np.zeros(rows, dtype=np.float32)
    for bank in range(BANKS):
        global_sum = np.asarray(global_sum + total[:, bank], dtype=np.float32)
        global_sumsq = np.asarray(global_sumsq + sumsq[:, bank], dtype=np.float32)
    return global_sum, global_sumsq


def reduce_fp32_balanced(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    rows, hidden = x.shape
    vectors = math.ceil(hidden / (BANKS * LANES))
    layout = x.reshape(rows, vectors, BANKS, LANES)
    total = np.zeros((rows, BANKS), dtype=np.float32)
    sumsq = np.zeros((rows, BANKS), dtype=np.float32)
    for vector in range(vectors):
        values = layout[:, vector]
        pair0 = np.asarray(values[:, :, 0] + values[:, :, 1], dtype=np.float32)
        pair1 = np.asarray(values[:, :, 2] + values[:, :, 3], dtype=np.float32)
        total = np.asarray(total + np.asarray(pair0 + pair1, dtype=np.float32), dtype=np.float32)
        squares = np.asarray(values * values, dtype=np.float32)
        square_pair0 = np.asarray(squares[:, :, 0] + squares[:, :, 1], dtype=np.float32)
        square_pair1 = np.asarray(squares[:, :, 2] + squares[:, :, 3], dtype=np.float32)
        sumsq = np.asarray(sumsq + np.asarray(square_pair0 + square_pair1, dtype=np.float32), dtype=np.float32)
    while total.shape[1] > 1:
        total = np.asarray(total[:, 0::2] + total[:, 1::2], dtype=np.float32)
        sumsq = np.asarray(sumsq[:, 0::2] + sumsq[:, 1::2], dtype=np.float32)
    return total[:, 0], sumsq[:, 0]


def reduce_fp32_interleaved4(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    rows, hidden = x.shape
    vectors = math.ceil(hidden / (BANKS * LANES))
    layout = x.reshape(rows, vectors, BANKS, LANES)
    total = np.zeros((rows, BANKS, 4), dtype=np.float32)
    sumsq = np.zeros((rows, BANKS, 4), dtype=np.float32)
    for vector in range(vectors):
        values = layout[:, vector]
        pair0 = np.asarray(values[:, :, 0] + values[:, :, 1], dtype=np.float32)
        pair1 = np.asarray(values[:, :, 2] + values[:, :, 3], dtype=np.float32)
        vector_sum = np.asarray(pair0 + pair1, dtype=np.float32)
        squares = np.asarray(values * values, dtype=np.float32)
        square_pair0 = np.asarray(squares[:, :, 0] + squares[:, :, 1], dtype=np.float32)
        square_pair1 = np.asarray(squares[:, :, 2] + squares[:, :, 3], dtype=np.float32)
        vector_sumsq = np.asarray(square_pair0 + square_pair1, dtype=np.float32)
        slot = vector % 4
        total[:, :, slot] = np.asarray(total[:, :, slot] + vector_sum, dtype=np.float32)
        sumsq[:, :, slot] = np.asarray(sumsq[:, :, slot] + vector_sumsq, dtype=np.float32)
    total = np.asarray(np.asarray(total[:, :, 0] + total[:, :, 1], dtype=np.float32) + np.asarray(total[:, :, 2] + total[:, :, 3], dtype=np.float32), dtype=np.float32)
    sumsq = np.asarray(np.asarray(sumsq[:, :, 0] + sumsq[:, :, 1], dtype=np.float32) + np.asarray(sumsq[:, :, 2] + sumsq[:, :, 3], dtype=np.float32), dtype=np.float32)
    while total.shape[1] > 1:
        total = np.asarray(total[:, 0::2] + total[:, 1::2], dtype=np.float32)
        sumsq = np.asarray(sumsq[:, 0::2] + sumsq[:, 1::2], dtype=np.float32)
    return total[:, 0], sumsq[:, 0]


def scalar_bf16(total: np.ndarray, sumsq: np.ndarray, hidden: int, epsilon: float) -> tuple[np.ndarray, np.ndarray]:
    inv_hidden = q(np.asarray(1.0 / hidden, dtype=np.float32))
    mean = q(total * inv_hidden)
    mean_square = q(sumsq * inv_hidden)
    variance = q(mean_square + (-q(mean * mean)))
    variance = np.where(variance < 0, np.float32(0), variance).astype(np.float32)
    argument = q(variance + q(np.asarray(epsilon, dtype=np.float32)))
    return mean, lut256(argument)


def scalar_fp32(total: np.ndarray, sumsq: np.ndarray, hidden: int, epsilon: float, rsqrt: str) -> tuple[np.ndarray, np.ndarray]:
    inv_hidden = np.float32(1.0 / hidden)
    mean = np.asarray(total * inv_hidden, dtype=np.float32)
    mean_square = np.asarray(sumsq * inv_hidden, dtype=np.float32)
    variance = np.asarray(mean_square - np.asarray(mean * mean, dtype=np.float32), dtype=np.float32)
    variance = np.maximum(variance, np.float32(0.0)).astype(np.float32)
    argument = np.asarray(variance + np.float32(epsilon), dtype=np.float32)
    if rsqrt == "BF16_LUT256":
        inverse = lut256(argument)
    elif rsqrt in ("FP32_NR1", "FP32_NR2"):
        seed = lut256(argument)
        inverse = seed
        iterations = 1 if rsqrt == "FP32_NR1" else 2
        for _ in range(iterations):
            yy = np.asarray(inverse * inverse, dtype=np.float32)
            correction = np.asarray(np.float32(1.5) - np.asarray(np.float32(0.5) * np.asarray(argument * yy, dtype=np.float32), dtype=np.float32), dtype=np.float32)
            inverse = np.asarray(inverse * correction, dtype=np.float32)
    elif rsqrt == "FP32_EXACT":
        inverse = np.asarray(np.float32(1.0) / np.sqrt(argument), dtype=np.float32)
    else:
        raise ValueError(rsqrt)
    return mean, inverse


def scalar_welford(x: np.ndarray, epsilon: float) -> tuple[np.ndarray, np.ndarray]:
    # NumPy's FP32 mean/variance is the canonical algorithmic upper bound in
    # this DSE; RTL selection does not rely on this candidate unless required.
    mean = np.mean(x, axis=1, dtype=np.float32)
    variance = np.mean(np.asarray((x - mean[:, None]) ** 2, dtype=np.float32), axis=1, dtype=np.float32)
    inverse = np.asarray(np.float32(1.0) / np.sqrt(np.asarray(variance + np.float32(epsilon), dtype=np.float32)), dtype=np.float32)
    return mean, inverse


def lut256(values: np.ndarray) -> np.ndarray:
    source = q(values)
    mantissa, exponent = np.frexp(source)
    mantissa = np.asarray(mantissa * np.float32(2.0), dtype=np.float32)
    exponent = exponent - 1
    odd = (exponent & 1) != 0
    adjusted = np.where(odd, mantissa * np.float32(2.0), mantissa).astype(np.float32)
    even_exponent = np.where(odd, exponent - 1, exponent)
    index = np.clip(((adjusted - np.float32(1.0)) * np.float32(256.0 / 3.0)).astype(np.int32), 0, 255)
    midpoint = np.asarray(np.float32(1.0) + (index.astype(np.float32) + np.float32(0.5)) * np.float32(3.0 / 256.0), dtype=np.float32)
    seed = q(np.asarray(np.float32(1.0) / np.sqrt(midpoint), dtype=np.float32))
    return q(np.ldexp(seed, -(even_exponent // 2)))


def apply_bf16(x: np.ndarray, gamma: np.ndarray, beta: np.ndarray, mean: np.ndarray, inverse: np.ndarray) -> np.ndarray:
    mean = q(mean)[:, None]
    inverse = q(inverse)[:, None]
    centered = q(x - mean)
    normalized = q(centered * inverse)
    scaled = q(normalized * gamma[None, :])
    return float_to_bits(q(scaled + beta[None, :]))


def apply_fp32(x: np.ndarray, gamma: np.ndarray, beta: np.ndarray, mean: np.ndarray, inverse: np.ndarray) -> np.ndarray:
    centered = np.asarray(x - mean[:, None], dtype=np.float32)
    normalized = np.asarray(centered * inverse[:, None], dtype=np.float32)
    scaled = np.asarray(normalized * gamma[None, :], dtype=np.float32)
    shifted = np.asarray(scaled + beta[None, :], dtype=np.float32)
    return float_to_bits(shifted)


def calculate_metrics(actual_bits: np.ndarray, expected_bits: np.ndarray) -> dict[str, float | int]:
    actual = bits_to_float(actual_bits.reshape(-1))
    expected = bits_to_float(expected_bits.reshape(-1))
    errors = np.abs(actual - expected)
    return {
        "samples": int(errors.size),
        "bit_mismatches": int(np.count_nonzero(actual_bits.reshape(-1) != expected_bits.reshape(-1))),
        "bit_exact_rate": float(np.mean(actual_bits.reshape(-1) == expected_bits.reshape(-1))),
        "max_abs": float(np.max(errors)),
        "mean_abs": float(np.mean(errors, dtype=np.float64)),
        "rmse": float(np.sqrt(np.mean(np.asarray(errors * errors, dtype=np.float64)))),
        "nonfinite": int(np.count_nonzero(~np.isfinite(actual))),
    }


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((TRACE / "trace_manifest.json").read_text(encoding="utf-8"))
    detailed = []
    aggregate: dict[str, dict] = {candidate.candidate: {"candidate": asdict(candidate), "profiles": []} for candidate in CANDIDATES}
    for profile, sample in manifest["samples"].items():
        shape = sample["shape"]
        hidden = int(shape[-1])
        rows = math.prod(shape[:-1])
        x = bits_to_float(read_hex(TRACE / sample["input_hex"])).reshape(rows, hidden)
        gamma = bits_to_float(read_hex(TRACE / sample["gamma_hex"]))
        beta = bits_to_float(read_hex(TRACE / sample["beta_hex"]))
        expected = read_hex(TRACE / sample["output_hex"]).reshape(rows, hidden)
        epsilon = 1.0e-6 if profile == "action_dit_norm_out" else 1.0e-5
        bf16_total, bf16_sumsq = reduce_bf16(x)
        fp32_total, fp32_sumsq = reduce_fp32_tree(x)
        fp32_balanced_total, fp32_balanced_sumsq = reduce_fp32_balanced(x)
        fp32_interleaved_total, fp32_interleaved_sumsq = reduce_fp32_interleaved4(x)
        cached_scalars: dict[tuple[str, str], tuple[np.ndarray, np.ndarray]] = {}
        for candidate in CANDIDATES:
            if candidate.reduction == "BF16_SEQUENTIAL":
                total, sumsq = bf16_total, bf16_sumsq
            elif candidate.reduction == "FP32_4LANE_TREE":
                total, sumsq = fp32_total, fp32_sumsq
            elif candidate.reduction == "FP32_4LANE_BALANCED":
                total, sumsq = fp32_balanced_total, fp32_balanced_sumsq
            elif candidate.reduction == "FP32_INTERLEAVED4_BALANCED":
                total, sumsq = fp32_interleaved_total, fp32_interleaved_sumsq
            elif candidate.reduction == "FP32_WELFORD":
                total = sumsq = None
            else:
                raise ValueError(candidate.reduction)
            scalar_key = (candidate.reduction, candidate.scalar + candidate.rsqrt)
            if scalar_key not in cached_scalars:
                if candidate.reduction == "FP32_WELFORD":
                    cached_scalars[scalar_key] = scalar_welford(x, epsilon)
                elif candidate.scalar == "BF16":
                    cached_scalars[scalar_key] = scalar_bf16(total, sumsq, hidden, epsilon)
                else:
                    cached_scalars[scalar_key] = scalar_fp32(total, sumsq, hidden, epsilon, candidate.rsqrt)
            mean, inverse = cached_scalars[scalar_key]
            if candidate.scalar_broadcast == "BF16":
                mean, inverse = q(mean), q(inverse)
            actual = apply_bf16(x, gamma, beta, mean, inverse) if candidate.apply == "BF16_STAGED" else apply_fp32(x, gamma, beta, mean, inverse)
            metrics = calculate_metrics(actual, expected)
            result = "PASS" if metrics["nonfinite"] == 0 and metrics["max_abs"] <= THRESHOLD else "FAIL"
            row = {
                "candidate": candidate.candidate,
                "profile_id": profile,
                "rows": rows,
                "hidden_size": hidden,
                **metrics,
                "threshold": THRESHOLD,
                "result": result,
            }
            detailed.append(row)
            aggregate[candidate.candidate]["profiles"].append(row)
    summaries = []
    for candidate in CANDIDATES:
        profiles = aggregate[candidate.candidate]["profiles"]
        summary = {
            **asdict(candidate),
            "profile_passes": sum(row["result"] == "PASS" for row in profiles),
            "profile_count": len(profiles),
            "overall_max_abs": max(row["max_abs"] for row in profiles),
            "weighted_mean_abs": sum(row["mean_abs"] * row["samples"] for row in profiles) / sum(row["samples"] for row in profiles),
            "total_bit_mismatches": sum(row["bit_mismatches"] for row in profiles),
            "total_samples": sum(row["samples"] for row in profiles),
            "result": "PASS" if all(row["result"] == "PASS" for row in profiles) else "FAIL",
        }
        summaries.append(summary)
        aggregate[candidate.candidate]["summary"] = summary
    passing = [row for row in summaries if row["result"] == "PASS"]
    selected = min(passing, key=lambda row: (row["change_count"], row["estimated_scalar_cost_units"], row["estimated_extra_fp32_ops_per_element"], row["estimated_extra_fp32_ops_per_row"], row["estimated_global_reduce_cycles"])) if passing else None
    with (OUT / "mixed_precision_profile_accuracy.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(detailed[0]))
        writer.writeheader()
        writer.writerows(detailed)
    with (OUT / "mixed_precision_candidate_summary.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(summaries[0]))
        writer.writeheader()
        writer.writerows(summaries)
    payload = {
        "source_classification": manifest["classification"],
        "scope": "all rows and all elements in the six captured representative tensors",
        "banks": BANKS,
        "lanes": LANES,
        "threshold": {"metric": "max_abs", "value": THRESHOLD, "policy": "pre-existing project gate"},
        "selection_policy": "fewest changed precision blocks, then lower estimated scalar hardware cost, then fewer extra FP32 operations; selection requires all six profiles to pass",
        "selected_candidate": selected,
        "candidates": aggregate,
    }
    (OUT / "mixed_precision_exploration.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(
        "GROOT_MIXED_PRECISION_EXPLORATION "
        f"candidates={len(CANDIDATES)} passing={len(passing)} "
        f"selected={selected['candidate'] if selected else 'NONE'}"
    )
    return 0 if selected else 1


if __name__ == "__main__":
    raise SystemExit(main())
