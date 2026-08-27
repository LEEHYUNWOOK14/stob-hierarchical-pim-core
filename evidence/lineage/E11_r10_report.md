# R10 H10 met3 escape-capacity strict-route report

Classification: `H10_MET3_CAPACITY_SENSITIVE_PARTIAL`

All provenance, canonical-tool, resource, preflight, policy, single-route, output, and independent-reopen gates passed. The only physical-policy change from R6 was met3 adjustment `0.20 -> 0.10`; met1/met2 remained 0.00, met4 remained 0.20, met5 remained at the R6 observed 10.33% reduction, and CUGR iterations remained 1.

R10 resource table: met1/met2/met3/met4/met5 reductions were `0.00/0.00/10.00/20.00/10.33%`. Route exit was 0, one extra RRR iteration ran, routed/skipped nets were `3,799,490/0`, unresolved resources were `1`, report records were `3`, total congestion was `0.79`, wire/via overflow was `0.74/0.05`, and max-edge overflow was `0.51`. OpenROAD emitted `GRT-0115` and `GRT-0118`, so strict zero PASS is rejected.

All six H10 partial-improvement metrics improved versus R6: unresolved `3 -> 1`, records `9 -> 3`, total `2.55 -> 0.79`, wire overflow `2.27 -> 0.74`, via overflow `0.28 -> 0.05`, and max-edge `0.63 -> 0.51`. Debug evidence improved from R9's 3D/spreadable overflow `3/3` to `1/1`, with true planar 2D overflow remaining `0`. Layer report overflow remained only on met1/met2 (`0.25/0.03` and `0.49/0.02` wire/via); met3/met4/met5 were zero.

Independent reopen passed with the expected block, one `clk_i`, 565 bumps, four EXCLUSIVE regions, no placement violations, no unplaced instances, global routes present, no detailed routes, no dbWire-bearing nets, and a non-empty guide. Downstream detailed route, extraction, STA/PPA, fill, GDS, and signoff remain `NOT_RUN` because strict zero was not achieved.

Timing/resource evidence: user `961.66s`, system `26.83s`, wall `16:27.42`, peak RSS `31,613,528 KiB`.

Output SHA256: `global_route.log` `d1b94d0c858e2f100c4cab20e225404243e61292ea390c098dc81d3cd613d02d`; `r10.congestion.rpt` `a85e069c0fe77cc2e94e5202a72b92263359f581bc45215df9c08b3aaa81fd15`; `r10.route_guide` `38039c0ef90583f65ccb42dee4135487d4404173959a43c09277fc6bc25bb22a`; `r10_global_route.odb` `04dfe8c9223a1db034e5491e47c5758ba113c122ee1f57017b2f53e7d1d3559a`; `r10_global_route.sdc` `c3f1381d0f8c236bd826f1fb0ab2a3b069a29242fdc89a2b9d2f29d4795950e8`; reopen log `2b0ce006585549eab25856496f6621ac378402ef521c2a0290d8ee1f0fe4c765`.
