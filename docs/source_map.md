# Source map

| Package area | Origin and role | Submission status |
|---|---|---|
| `rtl/core/normalization_pcu/` | Project normalization PCU frozen RTL | Included |
| `rtl/integration/` | Project quad-local integration RTL | Included |
| `verification/` | Selected RTL and integration benches | Included selectively |
| `cpp/reference/` | Independent FP16 vector utility | Included; not simulator code |
| `python/` | Selected workload/analysis/provenance utilities | Included selectively |
| `data/`, `evidence/` | Selected derived evidence | Included selectively |
| `excluded-simulator-source/` | Samsung PIMSimulator + DRAMSim2-derived C++ | Excluded |
| `sim`, `libdramsim`, `obj_dir` | Build/runtime artifacts | Excluded |
| `thermal/`, `hardware_cost/thermal/` | Thermal analysis pipeline | Excluded |
| external papers/checkpoints | Third-party source material | Not copied |
