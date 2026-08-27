# R6 H6 nominal-capacity/local-demand signoff 보고서

## 최종 분류

`H6_CAPACITY_SENSITIVE_PARTIAL`

Global-route 호출 횟수는 1회이며 종료 코드는 0입니다. Runtime은 router `00:17:24`, wrapper `00:18:23.62`입니다. R6는 R3 CTS route-free ODB/SDC를 사용했고 met1/met2 explicit adjustment만 0.05에서 0.00으로 변경했으며 CUGR effort는 1로 유지했습니다.

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

H6 partial 기준 5개는 모두 만족하지만 엄격한 0은 아닙니다. R6에는 `GRT-0118`(잔여 resource 3개), `GRT-0115`, report record 9개 및 0이 아닌 overflow가 있습니다. 따라서 이는 signoff 수준 배선이 아니라 capacity-sensitive partial 증거입니다.

## 국소 수요 증거

읽기 전용 감사는 6.9um GCell pitch만큼 확장한 R4(15개)와 R6(9개) report window 전체를 다룹니다. exact overlap은 1, adjacent overlap은 0입니다. 보존된 exact hotspot은 met1 Horizontal `(6713.7,6568.8)-(6720.6,6575.7)`입니다. window별 placement/pin/clock/reset/region 전체 데이터는 `audit/hotspot_local_demand.tsv`에 있으며 clock/reset membership은 상관관계 증거일 뿐입니다.

## 재개방 및 정책 gate

Independent Liberty-first reopen은 PASS입니다: `have_routes=1`, `detailed_routes=0`, bump 565개, EXCLUSIVE region 4개, 합법 배치 및 미배치 instance 0개입니다. met1/met2 resource reduction은 0.00%이며 met3/met4/met5 provenance는 20%/20%/10.33%로 유지됩니다. skipped net은 없었고 routed net은 3,799,490개입니다.

## 범위 한계

Detailed route, extraction, post-route STA, PPA, fill/GDS, DRC/LVS/antenna, ECO 및 두 번째 route/sweep은 `NOT_RUN`입니다. 향후 targeted post-CTS local-demand 실험에는 별도 승인과 namespace가 필요합니다.
