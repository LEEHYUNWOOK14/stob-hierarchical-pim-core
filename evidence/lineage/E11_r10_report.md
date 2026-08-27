# R10 H10 met3 escape-capacity 엄격 배선 보고서

분류: `H10_MET3_CAPACITY_SENSITIVE_PARTIAL`

provenance, canonical-tool, resource, preflight, policy, single-route, output 및 independent-reopen gate가 모두 통과했습니다. R6 대비 유일한 physical-policy 변경은 met3 adjustment `0.20 -> 0.10`이었고, met1/met2는 0.00, met4는 0.20, met5는 R6 관측값인 10.33% reduction, CUGR iteration은 1로 유지했습니다.

R10 resource 표에서 met1/met2/met3/met4/met5 reduction은
`0.00/0.00/10.00/20.00/10.33%`입니다. Route 종료 코드는 0이고 RRR
iteration이 한 번 추가로 실행되었습니다. routed/skipped net은
`3,799,490/0`, unresolved resource는 `1`, report record는 `3`, total
congestion은 `0.79`, wire/via overflow는 `0.74/0.05`, max-edge overflow는
`0.51`입니다. OpenROAD가 `GRT-0115` 및 `GRT-0118`을 출력했으므로 엄격한
zero PASS는 인정하지 않습니다.

H10 partial-improvement 지표 6개는 모두 R6보다 개선되었습니다. unresolved는
`3 -> 1`, record는 `9 -> 3`, total은 `2.55 -> 0.79`, wire overflow는
`2.27 -> 0.74`, via overflow는 `0.28 -> 0.05`, max-edge는 `0.63 -> 0.51`이
되었습니다. Debug 증거는 R9의 3D/spreadable overflow `3/3`에서 `1/1`로
개선되었고, 실제 planar 2D overflow는 `0`으로 남았습니다. Layer report의
overflow는 met1/met2에만 남았으며(`0.25/0.03`, `0.49/0.02` wire/via),
met3/met4/met5는 0이었습니다.

Independent reopen은 예상 block, `clk_i` 1개, bump 565개, EXCLUSIVE region 4개, 배치 위반 없음, 미배치 instance 없음, global route 존재, detailed route 없음, dbWire-bearing net 없음 및 비어 있지 않은 guide로 통과했습니다. 엄격한 0을 달성하지 못했으므로 후속 detailed route, extraction, STA/PPA, fill, GDS 및 signoff는 계속 `NOT_RUN`입니다.

Timing/resource 증거: user `961.66s`, system `26.83s`, wall `16:27.42`, peak RSS `31,613,528 KiB`.

Output SHA256: `global_route.log` `d1b94d0c858e2f100c4cab20e225404243e61292ea390c098dc81d3cd613d02d`; `r10.congestion.rpt` `a85e069c0fe77cc2e94e5202a72b92263359f581bc45215df9c08b3aaa81fd15`; `r10.route_guide` `38039c0ef90583f65ccb42dee4135487d4404173959a43c09277fc6bc25bb22a`; `r10_global_route.odb` `04dfe8c9223a1db034e5491e47c5758ba113c122ee1f57017b2f53e7d1d3559a`; `r10_global_route.sdc` `c3f1381d0f8c236bd826f1fb0ab2a3b069a29242fdc89a2b9d2f29d4795950e8`; reopen log `2b0ce006585549eab25856496f6621ac378402ef521c2a0290d8ee1f0fe4c765`.
