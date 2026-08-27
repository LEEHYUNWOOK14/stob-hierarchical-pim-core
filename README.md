# STOB Hierarchical PIM Core

Submission-oriented package for the hierarchical HBM2-PIM research prototype.

## Scope

This repository contains the project's SystemVerilog normalization PCU RTL,
selected RTL verification benches, independent reference/analysis utilities,
and selected evidence. It intentionally does not redistribute the Samsung
PIMSimulator/DRAMSim2-based C++ simulator, simulator binaries, thermal-analysis
pipeline, external papers, or large physical-design databases.

## Core result

The primary source is the 16-bank, 8-lane, split-read/write normalization PCU
under `rtl/core/normalization_pcu/`. The integration sources under
`rtl/integration/` are the selected quad-local B2 path.

## Evidence boundary

The included results are research evidence only. RTL functional PASS does not
mean timing closure, power signoff, manufacturing signoff, or tape-out readiness.
The workload is a GR00T-derived normalization boundary study, not full GR00T
end-to-end inference.

## Reproduction

See `reproducibility/commands.md` and `reproducibility/tool_versions.txt`.
The original server absolute paths have been removed from this package; all
references must resolve relative to this repository or to an explicitly listed
external tool installation.

## License and third-party code

See `THIRD_PARTY_NOTICES.md`. The absence of the restricted simulator source
from this repository does not grant permission to redistribute it.
