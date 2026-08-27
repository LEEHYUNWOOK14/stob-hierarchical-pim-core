# R6 H6 nominal-capacity/local-demand signoff

## Final classification

`H6_CAPACITY_SENSITIVE_PARTIAL`

Global-route invocation count is 1 and exit code is 0. Runtime is `00:17:24` router / `00:18:23.62` wrapper. R6 used the R3 CTS route-free ODB/SDC and changed only met1/met2 explicit adjustment from 0.05 to 0.00; CUGR effort remained 1.

| metric | R4 control | R6 candidate | delta |
|---|---:|---:|---:|
| unresolved resources | 4 | 3 | -1 |
| report records | 15 | 9 | -6 |
| total congestion | 4.32 | 2.55 | -1.77 |
| wire overflow | 3.86 | 2.27 | -1.59 |
| via overflow | 0.46 | 0.28 | -0.18 |
| max-edge overflow | 0.86 | 0.63 | -0.23 |
| wirelength (um) | 202,231,223 | 201,145,943 | -1,085,280 |
| vias | 18,981,170 | 18,815,475 | -165,695 |

The five H6 partial criteria are all satisfied, but strict zero is not: R6 contains `GRT-0118` (3 residual resources), `GRT-0115`, 9 report records, and nonzero overflow. Therefore this is capacity-sensitive partial evidence, not signoff-quality routing.

## Local-demand evidence

The read-only audit covers all R4 (15) and R6 (9) report windows expanded by one 6.9um GCell pitch. Exact overlap is 1 and adjacent overlap is 0. The retained exact hotspot is met1 Horizontal `(6713.7,6568.8)-(6720.6,6575.7)`. Full per-window placement/pin/clock/reset/region data is in `audit/hotspot_local_demand.tsv`; clock/reset membership is correlation evidence only.

## Reopen and policy gates

Independent Liberty-first reopen PASS: `have_routes=1`, `detailed_routes=0`, 565 bumps, 4 EXCLUSIVE regions, legal placement, zero unplaced instances. met1/met2 resource reduction is 0.00%; met3/met4/met5 provenance remains 20%/20%/10.33%. No skipped nets were reported; routed nets are 3,799,490.

## Boundary

Detailed route, extraction, post-route STA, PPA, fill/GDS, DRC/LVS/antenna, ECO, and any second route/sweep are `NOT_RUN`. A future targeted post-CTS local-demand experiment requires separate approval and namespace.
