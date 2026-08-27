# R16/H16 DRT=0 모델 보고서용 요약

## 모델 식별

- 버전: `quad_local_b26_l2d_a8_r16_h16_canonical_drt_completion_r1`
- 실행 ID: `quad_local_b26_l2d_a8_r16_h16_canonical_drt_completion_r1_20260824T153000Z`
- top block: `logic_die_normalization_hbm_quad_local_b2_top`
- platform: `sky130hd`
- 입력 계보: R15/H15 strict-zero global-route ODB/SDC/route guide
- OpenROAD SHA-256: `ed2d72763fd57a7500f18a03ddb714c3a31730c12ef3bcaf4e19cf688ef327f9`

## 핵심 결과

| 항목 | 값 |
|---|---:|
| 최종 DRT violations | 0 |
| `detailed_route_num_drvs` | 0 |
| `design_is_routed` | 1 |
| `have_detailed_routes` | 1 |
| placement violations | 0 |
| unplaced instances | 0 |
| dbWire-bearing nets | 3,799,490 |
| routed wire length | 147,956,981 µm |
| vias | 28,032,721 |
| components | 4,914,323 |
| terminals/pins | 755 |
| cmd/read bump terminals | 565 |
| DEF nets | 3,799,491 |
| die size | 9037.220 × 9037.220 µm |
| die area | 81.671345 mm² |
| DRT iterations observed | 23 (0–22) |
| wall time | 18:59:04 |
| peak RSS | 80.259 GiB |
| process exit | 0 |

DRT 위반 수는 초기 2,282,092건에서 최종 0건으로 감소했습니다. 마지막 0은 22번째 `stubborn tiles` 반복에서 관측됐고, 이어서 `Complete detail routing`, 최종 배선/via 통계, `R16_DRT_FINAL`, `R16_DRT_TCL_COMPLETE`가 기록됐습니다.

## 입력 global-route 상태

- routed nets: 3,799,490
- unresolved resources: 0
- total/wire/via/max-edge overflow: 0.0/0.0/0.0/0.0
- report records: 0

## 클록 및 제약

- clock: `clk` from `clk_i`
- period: 40.0 ns (constraint frequency 25.000 MHz)
- uncertainty: 0.5 ns
- input-delay statements: 378
- output-delay statements: 374
- false-path statements: 1

제약 주파수 25 MHz는 SDC 목표값이며, post-route STA로 검증된 달성 Fmax가 아닙니다.

## 주장 범위

이 패키지가 직접 뒷받침하는 결론은 **해당 OpenROAD DRT 실행의 최종 violation/DRV 값이 0이고 상세배선 상태가 완료됐다는 것**입니다. RCX/SPEF, post-route STA/PPA, power, GDS/OASIS readback, foundry DRC/LVS/antenna signoff, IR/EM 및 tapeout readiness는 이 결과로 입증되지 않습니다.
