# B25 Track B placement failure diagnosis

Updated: 2026-08-19 UTC

## Verdict

B25 passes the cheap functional and mapped-locality gates but fails before global route at detailed placement. The failure is a legalization/capacity failure, not a proven RTL protocol or arithmetic failure.

Evidence:

- `cheap_gate_manifest.json`: overall result `PASS`.
- `b25_placement_authorization.json`: placement authorization `PASS`.
- `physical/b25_placement_execution_report.json`: placement `FAIL`, exit code `2`.
- `physical/b25_place.log`: `DPL-0033`, 48,736 remaining illegal cells, 17,972 overlap checks and 17,972 padding checks.
- The placement flow raised target density from `0.39` to `0.43` because the available fenced free area was insufficient for the requested target.

## Root-cause classification

The B25 completion-descriptor ECO reduced the central completion interface from 68 to 17 bits, but the physical failure remains dominated by the interaction of:

1. four exclusive quad fences;
2. central corridor and clock/reset/control routing demand;
3. resized buffer/inverter cells around payload, apply, and control paths;
4. insufficient legal row space for the detailed legalizer to resolve overlaps and padding.

The failure must not be attributed to residual routing congestion alone: B25 never produced a legal placement or a route input.

## Next experiment: B26 placement-policy isolation

Before changing the B25 RTL again, run one isolated B26 experiment using the sealed B25 mapped netlist and the same floorplan/fence contract. Change only the placement recovery policy:

- preserve B25 RTL, mapped netlist, floorplan, SDC, and fence geometry;
- use an explicit incremental detailed-placement recovery pass from the last valid B25 pre-detail checkpoint;
- test the established DRC-penalty policy values (`20`, then `100`) in separate output namespaces;
- keep `set_placement_padding -global -left 0 -right 0`;
- require independent legality/fence reopen audit;
- do not route unless placement violations and overlap/padding checks are zero.

This isolates whether B25's failure is recoverable by legalization policy. If both policy probes fail with the same fence-localized violations, the next ECO must change physical density/capacity or the placement-visible buffer/control structure. No B25 artifact may be overwritten.

## Promotion rule

Only a B26 candidate with legal placement may proceed to the single-shot global route. Only a candidate with `rrr_residual=0` and `overflow_edges=0` may proceed to CTS. Any nonzero result remains Track B exploratory evidence and is not final PPA/signoff evidence.
