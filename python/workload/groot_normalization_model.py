#!/usr/bin/env python3
"""Parameterized GR00T normalization placement model.

This model deliberately separates simulator-measured element-wise cycles from assumed
reduction, interconnect, and RSQRT parameters. It is an architectural sensitivity model,
not a claim of measured GPU or signoff RTL performance.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List


ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "reports" / "groot_normalization"
MANIFEST = REPORT_DIR / "gr00t_normalization_profile_manifest.csv"
PARAMETERS = REPORT_DIR / "common_model_parameters.json"


@dataclass(frozen=True)
class Profile:
    profile_id: str
    norm_type: str
    rows: int
    hidden_size: int
    invocations: int
    measured_elementwise_cycles: int
    input_bytes: int
    output_bytes: int
    affine_bytes: int
    stat_scalars: int

    @property
    def statistic_count(self) -> int:
        return 1 if self.norm_type == "RMSNorm" else 2

    @property
    def return_scalars(self) -> int:
        return 1 if self.norm_type == "RMSNorm" else 2


def load_profiles(path: Path = MANIFEST) -> List[Profile]:
    with path.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    return [
        Profile(
            profile_id=row["profile_id"],
            norm_type=row["norm_type"],
            rows=int(row["rows"]),
            hidden_size=int(row["hidden_size"]),
            invocations=int(row["invocations"]),
            measured_elementwise_cycles=int(row["cycles_per_profile_run"]),
            input_bytes=int(row["logical_input_bytes_per_call"]),
            output_bytes=int(row["logical_output_bytes_per_call"]),
            affine_bytes=int(row["affine_parameter_bytes_per_call"]),
            stat_scalars=int(row["global_stat_scalars_per_call"]),
        )
        for row in rows
    ]


def load_parameters(path: Path = PARAMETERS) -> Dict:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def transfer_ns(byte_count: int, bandwidth_gbps: float, fixed_latency_ns: float) -> float:
    # Gbps is decimal gigabits/s; 1 byte at 1 Gbps takes 8 ns.
    return fixed_latency_ns + byte_count * 8.0 / bandwidth_gbps


def cycles_to_ns(cycles: float, clock_mhz: float) -> float:
    return cycles * 1000.0 / clock_mhz


def logic_raw_reduce_cycles(profile: Profile, logic_pcus: int, lanes: int) -> int:
    """Assumed vector reduction throughput; no matching raw-input RTL yet."""
    parallel_elements = max(1, logic_pcus * lanes)
    return math.ceil(profile.rows * profile.hidden_size / parallel_elements) * profile.statistic_count


def bank_local_reduce_cycles(profile: Profile, banks: int) -> int:
    """Current RTL consumes one element per bank per cycle and forms SUM/SUMSQ together."""
    parallel_elements = max(1, banks)
    return math.ceil(profile.rows * profile.hidden_size / parallel_elements)


def local_reduce_cycles(profile: Profile, banks: int, bank_pcus: int, lanes: int) -> int:
    """Backward-compatible analytical helper for the assumed vector design."""
    parallel_elements = max(1, banks * bank_pcus * lanes)
    return math.ceil(profile.rows * profile.hidden_size / parallel_elements) * profile.statistic_count


def global_reduce_cycles(profile: Profile, banks: int, partial_ports: int) -> int:
    # Current RTL accepts one paired SUM/SUMSQ partial per cycle and therefore
    # spends BANKS collection/accumulation cycles for each row assigned to an engine.
    return math.ceil(profile.rows * banks / max(1, partial_ports))


def rsqrt_cycles(profile: Profile, engines: int, latency: int, initiation_interval: int) -> int:
    waves = math.ceil(profile.rows / max(1, engines))
    return latency + max(0, waves - 1) * initiation_interval


def finalize_cycles(profile: Profile, engines: int, ref: Dict) -> int:
    per_row = (
        int(ref["rmsnorm_finalize_cycles_per_row"])
        if profile.norm_type == "RMSNorm"
        else int(ref["layernorm_finalize_cycles_per_row"])
    )
    return math.ceil(profile.rows / max(1, engines)) * per_row


def model_profile(profile: Profile, case: str, ref: Dict) -> Dict[str, float | int | str | None]:
    clock = float(ref["clock_mhz"])
    banks = int(ref["banks"])
    bank_pcus = int(ref["bank_pcus"])
    logic_pcus = int(ref["logic_pcus"])
    lanes = int(ref["vector_lanes_per_pcu"])
    scalar_bytes = 4
    partial_bytes = profile.stat_scalars * banks * scalar_bytes
    return_bytes = profile.rows * profile.return_scalars * scalar_bytes
    tensor_bytes = profile.input_bytes + profile.affine_bytes + profile.output_bytes

    breakdown = {
        "prepare_ns": 0.0,
        "local_reduce_ns": 0.0,
        "partial_transfer_ns": 0.0,
        "global_reduce_ns": 0.0,
        "finalize_ns": 0.0,
        "rsqrt_ns": 0.0,
        "return_ns": 0.0,
        "apply_ns": 0.0,
        "queue_sync_ns": 0.0,
        "mode_switch_ns": 0.0,
    }
    traffic = {"tensor_bytes": 0, "partial_bytes": 0, "return_bytes": 0}

    bank_local_cycles = bank_local_reduce_cycles(profile, banks)
    logic_local_cycles = logic_raw_reduce_cycles(profile, logic_pcus, lanes)
    hierarchical_global_cycles = global_reduce_cycles(
        profile, banks, int(ref.get("logic_partial_input_ports", 1))
    )
    sqrt_cycles = rsqrt_cycles(
        profile,
        logic_pcus,
        int(ref["rsqrt_latency_cycles"]),
        int(ref["rsqrt_initiation_interval_cycles"]),
    )
    finish_cycles = finalize_cycles(profile, logic_pcus, ref)
    apply_cycles = profile.measured_elementwise_cycles

    if case == "gpu_full":
        traffic["tensor_bytes"] = tensor_bytes
        breakdown["partial_transfer_ns"] = transfer_ns(
            profile.input_bytes + profile.affine_bytes,
            float(ref["offload_bandwidth_gbps"]),
            float(ref["offload_one_way_latency_ns"]),
        )
        breakdown["return_ns"] = transfer_ns(
            profile.output_bytes,
            float(ref["offload_bandwidth_gbps"]),
            float(ref["offload_one_way_latency_ns"]),
        )
        # Assumed bandwidth roofline plus launch; not a measured GPU kernel.
        gpu_bytes_per_ns = float(ref["gpu_hbm_bandwidth_gbytes_per_s"])
        breakdown["global_reduce_ns"] = tensor_bytes / gpu_bytes_per_ns
        breakdown["queue_sync_ns"] = float(ref["gpu_kernel_launch_ns"])
        evidence = "ASSUMED_GPU_ROOFLINE"
    elif case in {"gpu_partial", "bank_only"}:
        traffic["partial_bytes"] = partial_bytes
        traffic["return_bytes"] = return_bytes
        breakdown["local_reduce_ns"] = cycles_to_ns(bank_local_cycles, clock)
        breakdown["partial_transfer_ns"] = transfer_ns(
            partial_bytes,
            float(ref["offload_bandwidth_gbps"]),
            float(ref["offload_one_way_latency_ns"]),
        )
        gpu_bytes_per_ns = float(ref["gpu_hbm_bandwidth_gbytes_per_s"])
        gpu_rows_per_ns = float(ref["gpu_normalization_rows_per_ns"])
        breakdown["global_reduce_ns"] = (partial_bytes + return_bytes) / gpu_bytes_per_ns
        breakdown["finalize_ns"] = profile.rows / gpu_rows_per_ns
        breakdown["rsqrt_ns"] = profile.rows / gpu_rows_per_ns
        breakdown["return_ns"] = transfer_ns(
            return_bytes,
            float(ref["offload_bandwidth_gbps"]),
            float(ref["offload_one_way_latency_ns"]),
        )
        breakdown["apply_ns"] = cycles_to_ns(apply_cycles, clock)
        breakdown["queue_sync_ns"] = float(ref["gpu_kernel_launch_ns"])
        evidence = "MIXED_MEASURED_ELEMENTWISE_ASSUMED_OFFLOAD"
    elif case == "logic_only":
        traffic["tensor_bytes"] = tensor_bytes
        breakdown["partial_transfer_ns"] = transfer_ns(
            profile.input_bytes + profile.affine_bytes,
            float(ref["ondie_bandwidth_gbps"]),
            float(ref["ondie_one_way_latency_ns"]),
        )
        breakdown["local_reduce_ns"] = cycles_to_ns(logic_local_cycles, clock)
        # Logic-only consumes the raw tensor directly; it does not traverse the
        # Bank-partial dispatcher modeled by hierarchical_global_cycles.
        breakdown["global_reduce_ns"] = 0.0
        breakdown["finalize_ns"] = cycles_to_ns(finish_cycles, clock)
        breakdown["rsqrt_ns"] = cycles_to_ns(sqrt_cycles, clock)
        breakdown["apply_ns"] = cycles_to_ns(
            math.ceil(apply_cycles * bank_pcus / max(1, logic_pcus)), clock
        )
        breakdown["return_ns"] = transfer_ns(
            profile.output_bytes,
            float(ref["ondie_bandwidth_gbps"]),
            float(ref["ondie_one_way_latency_ns"]),
        )
        evidence = "ASSUMED_LOGIC_THROUGHPUT_PROXY"
    elif case == "hierarchical":
        traffic["partial_bytes"] = partial_bytes
        traffic["return_bytes"] = return_bytes
        breakdown["local_reduce_ns"] = cycles_to_ns(bank_local_cycles, clock)
        breakdown["partial_transfer_ns"] = transfer_ns(
            partial_bytes,
            float(ref["ondie_bandwidth_gbps"]),
            float(ref["ondie_one_way_latency_ns"]),
        )
        breakdown["global_reduce_ns"] = cycles_to_ns(hierarchical_global_cycles, clock)
        breakdown["finalize_ns"] = cycles_to_ns(finish_cycles, clock)
        breakdown["rsqrt_ns"] = cycles_to_ns(sqrt_cycles, clock)
        breakdown["return_ns"] = transfer_ns(
            return_bytes,
            float(ref["ondie_bandwidth_gbps"]),
            float(ref["ondie_one_way_latency_ns"]),
        )
        breakdown["apply_ns"] = cycles_to_ns(apply_cycles, clock)
        evidence = "MIXED_MEASURED_ELEMENTWISE_ASSUMED_LOGIC"
    else:
        raise ValueError(f"unknown case: {case}")

    total_ns = sum(breakdown.values())
    result: Dict[str, float | int | str | None] = {
        "case": case,
        "profile_id": profile.profile_id,
        "norm_type": profile.norm_type,
        "rows": profile.rows,
        "hidden_size": profile.hidden_size,
        "invocations": profile.invocations,
        "clock_mhz": clock,
        "latency_ns_per_call": round(total_ns, 6),
        "projected_latency_ns": round(total_ns * profile.invocations, 6),
        "cycles_equivalent_per_call": math.ceil(total_ns * clock / 1000.0),
        **{key: round(value, 6) for key, value in breakdown.items()},
        **traffic,
        "energy_nj": None,
        "area_um2": None,
        "evidence_class": evidence,
        "assumptions_id": "reference_point_v1",
    }
    return result


def write_csv(path: Path, rows: Iterable[Dict]) -> None:
    rows = list(rows)
    if not rows:
        raise ValueError("no rows to write")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def generate_reference(profiles: List[Profile], params: Dict) -> List[Dict]:
    cases = ["gpu_full", "gpu_partial", "bank_only", "logic_only", "hierarchical"]
    return [model_profile(profile, case, params["reference_point"]) for case in cases for profile in profiles]


def generate_break_even(profiles: List[Profile], params: Dict) -> List[Dict]:
    base = dict(params["reference_point"])
    rows: List[Dict] = []
    for latency in params["sweeps"]["offload_one_way_latency_ns"]:
        for bandwidth in params["sweeps"]["offload_bandwidth_gbps"]:
            ref = dict(base)
            ref["offload_one_way_latency_ns"] = latency
            ref["offload_bandwidth_gbps"] = bandwidth
            for profile in profiles:
                hierarchical = model_profile(profile, "hierarchical", ref)
                bank_only = model_profile(profile, "bank_only", ref)
                gpu_full = model_profile(profile, "gpu_full", ref)
                h = float(hierarchical["latency_ns_per_call"])
                b = float(bank_only["latency_ns_per_call"])
                g = float(gpu_full["latency_ns_per_call"])
                rows.append(
                    {
                        "profile_id": profile.profile_id,
                        "offload_one_way_latency_ns": latency,
                        "offload_bandwidth_gbps": bandwidth,
                        "hierarchical_ns": round(h, 6),
                        "bank_only_ns": round(b, 6),
                        "gpu_full_ns": round(g, 6),
                        "hierarchical_speedup_vs_bank_only": round(b / h, 6),
                        "hierarchical_speedup_vs_gpu_full": round(g / h, 6),
                        "winner": min(
                            ((h, "hierarchical"), (b, "bank_only"), (g, "gpu_full"))
                        )[1],
                        "evidence_class": "ASSUMED_SENSITIVITY",
                    }
                )
    return rows


def self_test(profiles: List[Profile], params: Dict) -> None:
    assert len(profiles) == 7
    assert sum(profile.invocations for profile in profiles) == 333
    ref = dict(params["reference_point"])
    qk = next(profile for profile in profiles if profile.profile_id == "qwen_query_key")
    vl = next(profile for profile in profiles if profile.profile_id == "vlln")
    assert qk.input_bytes == vl.input_bytes
    assert qk.rows == 32 * vl.rows
    assert rsqrt_cycles(qk, 16, 16, 1) > rsqrt_cycles(vl, 16, 16, 1)
    slow = dict(ref, offload_one_way_latency_ns=10000)
    fast = dict(ref, offload_one_way_latency_ns=250)
    assert model_profile(vl, "gpu_full", slow)["latency_ns_per_call"] > model_profile(
        vl, "gpu_full", fast
    )["latency_ns_per_call"]
    assert model_profile(vl, "hierarchical", slow)["latency_ns_per_call"] == model_profile(
        vl, "hierarchical", fast
    )["latency_ns_per_call"]
    for result in generate_reference(profiles, params):
        assert float(result["latency_ns_per_call"]) > 0
        assert result["energy_nj"] is None
        assert result["area_um2"] is None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--output-dir", type=Path, default=REPORT_DIR / "results")
    args = parser.parse_args()
    profiles = load_profiles()
    params = load_parameters()
    self_test(profiles, params)
    if args.self_test:
        print("GROOT_NORMALIZATION_MODEL_SELF_TEST PASS")
        return
    reference = generate_reference(profiles, params)
    sweep = generate_break_even(profiles, params)
    write_csv(args.output_dir / "reference_architecture_comparison.csv", reference)
    write_csv(args.output_dir / "offload_break_even_sweep.csv", sweep)
    print(f"WROTE reference_rows={len(reference)} sweep_rows={len(sweep)}")


if __name__ == "__main__":
    main()
