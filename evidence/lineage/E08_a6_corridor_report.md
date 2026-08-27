# Track B A6 최종 보고서

## REGRESSED — PF-4 FAIL

A6 floorplan-native corridor 후보는 floorplan 및 placement gate를 통과했습니다. 승인된 global-route 호출 1회가 종료 코드 0으로 완료되었고 valid guide, congestion report, routed ODB, routed SDC 및 completion marker를 생성했습니다. 혼잡이 남아 PF-4는 실패했습니다.

1. A5 was not a hypothesis refutation: A5 mutated regions after completed placement, produced 3,615,582 region violations, no placement ODB, and did not route. A4 preaudit measured 5,659 outside instances; these populations are not equivalent.
2. H-A6 used one variable only: each central-facing quad edge moved inward by 6.9 µm, widening each corridor by 13.8 µm. Netlist, SDC, die/core, bump grid, layer range, and route recipe were preserved.
3. Floorplan gate PASS: 4 exclusive regions/groups, 3,617,332 grouped instances, ownership/geometry errors 0, approved bboxes exact, raw utilization 0.386254.
4. Placement gate PASS: skip-IO global placement, IO placement, global placement, one B26 detailed placement, optimize_mirroring, and independent clean reopen all passed.
5. Route: executed exactly once with exit code 0; congestion remaining is `6`, with `29` report entries, `4` actual overflow edges, and `4` overflow tracks: one met1 and three met2. L2D is `(3,3,3)`, A1 is `(1,2,2)`, and A6 is `(6,4,4)`.
6. Hotspot result: A6 is valid and classified `REGRESSED` against L2D. The corridor hypothesis did not close routing congestion.
7. Candidate runtimes/peak RSS: global skip-IO 1178 s/13.6 GB; IO 46 s/8.9 GB; global placement 1593 s/14.1 GB; DPL 195.52 s/13.7 GB; independent reopen 97 s/17.1 GB. Candidate OpenROAD process count at sealing: 0. An unrelated pre-existing Yosys process was not part of this candidate.
8. Artifact namespace: `server_snapshot/PIM_simulator/reports/groot_normalization/quad_local_b26_l2d_a6_floorplan_native_corridor_1gcell_r1_20260822T084006Z`; route output hashes are sealed in `sha256_inventory.txt` and `execution_manifest.json`.
9. Canonical B26, B26-L2D, and A1–A5 artifacts were not overwritten; candidate outputs use isolated result paths.
10. PF-4 is FAIL and Phase 6 is not authorized; CTS/STA/detailed route/fill/GDS were not run.
