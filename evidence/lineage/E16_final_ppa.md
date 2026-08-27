# 최종 PPA

생성일: 2026-08-25 UTC  
대상: `logic_die_normalization_hbm_quad_local_b2_top`  
후보: `R16/H16 canonical DRT completion`, 입력 계보 `R15/H15 strict-zero GRT`  
플랫폼: Sky130HD  
분류: `POST_ROUTE_EXTRACTED_EXPLORATORY_PPA_COMPLETE_WITH_LIMITATIONS`

> 이 문서에서 “최종”은 현재 연구 범위인 post-route extracted exploratory PPA의 최종 정리를 뜻한다. Timing closure, workload-annotated power, full signoff DRC/LVS, antenna, IR/EM, GDS/OASIS readback 또는 tapeout readiness를 뜻하지 않는다.

## 1. 결론

R16은 물리 배선 관점에서는 강한 결과를 냈다. R15 global routing은 strict-zero congestion을 달성했고, R16 detailed routing은 2,282,092개의 초기 violation을 반복 수리해 최종 DRV 0으로 끝났다. 독립 reopen에서 `design_is_routed=1`, `have_detailed_routes=1`, unplaced 0, placement violation 0, 유효 `dbWire` net 3,799,490개가 확인됐다. RCX도 3,799,491개 net에 대해 7.071GB SPEF를 생성하고 exit 0으로 끝났다.

반면 성능과 전력 신뢰도는 통과하지 못했다. 실제 STA 제약은 1.78ns가 아니라 **40ns, 25MHz**이며, 이 느슨한 주기에서도 일반 `clk` setup WNS가 **−318.878ns**, setup TNS가 **−21,913,132.319ns**이다. 비동기 reset recovery/removal도 위반하지만, 최악 setup은 reset 경로가 아니라 일반 clocked 경로다. 해당 경로에서는 약 **40.956pF** 부하와 **287.454ns slew**가 관찰되어 고fanout·대용량 부하·배선 지연이 핵심 병목임을 보여준다.

Power는 보고서 표기 기준 총 **1.830695W**지만 `VECTORLESS_ESTIMATE`이고 412,694개의 unannotated driver가 남아 있다. 따라서 동일 조건 후보 간 탐색 비교용으로만 제한적으로 사용할 수 있으며, 실제 workload 에너지나 signoff 전력으로 사용할 수 없다.

최종 연구 판정은 다음과 같다.

| 축 | 판정 | 근거 |
|---|---|---|
| Global routing | PASS | R15 total congestion 0, 3D/2D/spreadable overflow 0 |
| Detailed routing | PASS | final DRV 0, routed state true, placement/unplaced clean |
| Independent reopen | PASS with limitations | mandatory gates PASS; via recount와 independent DRT recount는 NOT_CHECKED |
| RC extraction | PASS with annotation limitation | SPEF 7.071GB, RCX exit 0, unannotated drivers 412,694 |
| Setup timing | FAIL | WNS −318.878ns, TNS −21.913M ns at 40ns |
| Hold timing | FAIL | WNS −5.380ns, TNS −4,164.843ns |
| Power | ESTIMATE ONLY | vectorless, activity 미주입, unit caveat |
| PPA 비교 우승 주장 | NOT AVAILABLE | 동일 단계·동일 조건의 extracted PPA baseline 없음 |
| 제조/signoff | OUT OF SCOPE | DRC/LVS/antenna/IR/EM/GDS readback 미수행 |

![Gate status](graphs/gate_status.svg)

## 2. 핵심 PPA 표

| 범주 | 지표 | 값 | 상태/해석 |
|---|---:|---:|---|
| Performance | Clock period | 40.000ns | 실제 R16 SDC |
| Performance | Nominal frequency | 25.000MHz | 주기에서 산출 |
| Performance | Setup WNS | −318.877946ns | FAIL |
| Performance | Setup TNS | −21,913,132.318712ns | FAIL |
| Performance | Hold WNS | −5.379516ns | FAIL |
| Performance | Hold TNS | −4,164.842839ns | FAIL |
| Area | Standard-cell design area | 31,855,576µm² = 31.855576mm² | 관측값 |
| Area | Utilization | 39% | 관측값 |
| Area | Implied placeable area | 약 81.680964mm² | area/0.39 파생값; die area로 단정 금지 |
| Power | Total | 1.830695W | vectorless·header 기준 |
| Power | Internal | 0.899090W | 49.1% |
| Power | Switching | 0.931592W | 50.9% |
| Power | Leakage | 0.0000132W | 약 0.00072% |
| Routing cost | Detailed wire length | 147,956,981µm = 147.956981m | DRT raw log |
| Routing cost | Vias | 28,032,721 | DRT raw log; 독립 recount 없음 |
| Routing integrity | Final DRV | 0 | PASS |
| RCX | SPEF | 7,071,219,382 bytes | PASS |
| RCX | Unannotated drivers | 412,694 | material limitation |
| Scale | DEF instances | 4,914,323 | timing model audit |

조건부로 `1.830695W × 40ns = 73.2278nJ/clock`을 계산할 수 있지만, activity가 없는 vectorless estimate이고 power unit 표기가 서로 충돌하므로 에너지/transaction 또는 실제 에너지 효율로 사용하지 않는다.

## 3. 물리 구현 결과

### 3.1 Global routing 계보

R6에서 R10, R15로 진행하면서 global-route congestion은 2.55 → 0.79 → 0.00으로 감소했다. R15는 precise overflow, 3D overflow, 2D aggregate overflow, spreadable overflow가 모두 0인 strict-zero 입력을 R16에 제공했다.

| Run | Total congestion | Wire overflow | Via overflow | Max-edge overflow | Unresolved | 판정 |
|---|---:|---:|---:|---:|---:|---|
| R6 | 2.55 | 2.27 | 0.28 | 0.63 | 3 | partial |
| R10 | 0.79 | 0.74 | 0.05 | 0.51 | 1 | partial improvement |
| R15 | 0.00 | 0.00 | 0.00 | 0.00 | 0 | strict-zero PASS |

![Global route lineage](graphs/global_route_lineage.svg)

이 표는 GRT 단계 안에서의 계보 비교다. R6/R10은 post-route extracted PPA가 아니므로 R16의 area/timing/power 우열 비교 기준으로 사용할 수 없다.

### 3.2 Detailed routing 수렴

DRT는 0번째 optimization iteration에서 2,282,092 violation을 기록한 뒤 17번째 iteration의 반복 repair에서 0에 도달했다. 4번째 iteration까지 99.38%, 10번째까지 99.998%, 최종적으로 100% 감소했다.

| Iteration | Phase | Violations | 초기 대비 감소 |
|---:|---|---:|---:|
| 0 | optimization | 2,282,092 | 0.000% |
| 1 | optimization | 1,240,531 | 45.641% |
| 2 | optimization | 1,153,053 | 49.474% |
| 3 | optimization | 175,294 | 92.319% |
| 4 | optimization | 14,051 | 99.384% |
| 5 | optimization | 2,025 | 99.911% |
| 6 | optimization | 653 | 99.971% |
| 7–10 | optimization | 305 → 46 | 99.987% → 99.998% |
| 11–16 | guides tiles | 23 → 15 | 99.999% 이상 |
| 17 final | optimization/repair | 17 → 8 → 4 → 0 | 100.000% |

![DRT convergence](graphs/drt_convergence.svg)

최종 물리 상태:

| 항목 | 값 |
|---|---:|
| `design_is_routed` | 1 |
| `have_routes` | 1 |
| `have_detailed_routes` | 1 |
| `detailed_route_num_drvs` | 0 |
| placement violations | empty |
| unplaced instances | 0 |
| dbWire-bearing nets | 3,799,490 |
| wire segments | 130,247,794 |
| invalid wire objects | 0 |
| back-reference mismatches | 0 |
| traversal API errors | 0 |
| final DRC report size | 0 bytes |

### 3.3 배선층 및 via

DRT raw log의 총 배선 길이는 147.956981m이며 met1과 met2가 합계 82.92%를 차지한다. 상위층 met5 사용은 사실상 0에 가깝다.

| Layer | Wire length | 전체 비율 |
|---|---:|---:|
| met1 | 56.710376m | 38.329% |
| met2 | 65.973281m | 44.590% |
| met3 | 18.878838m | 12.760% |
| met4 | 6.392155m | 4.320% |
| met5 | 0.002331m | 0.0016% |
| Total | 147.956981m | 100% |

![Wire length by layer](graphs/wirelength_by_layer.svg)

Via 수는 DRT raw log에서 28,032,721개다. R8 reopen verifier 정책상 via count를 독립적으로 재계수하지 않았으므로 `OBSERVED_NOT_INDEPENDENTLY_RECOUNTED`로 분류한다. 동일하게 DRT raw 총 배선 길이 147,956,981µm와 R8 parser 총 147,935,521.64µm 사이에는 약 21,459µm, 0.0145%의 차이가 있다. 측정 API/집계 정의가 다르므로 raw DRT 값을 기준값으로 유지하고 R8 값은 reopen numeric-validity 증거로만 사용한다.

## 4. RC extraction 및 annotation

RCX는 공식 Sky130HD symlink가 가리키는 Sky130HS `rcx_patterns.rules`를 사용했다. rule SHA256은 `d5bd9b1077ceac9929416abca272a6d52e51cd9a575453a31d129817bb286476`이다.

| RCX 지표 | 값 |
|---|---:|
| SPEF size | 7,071,219,382 bytes |
| SPEF SHA256 | `05f087ada748b994bb34eaac8d3ab438e98e5447682ab330a2d8063626c3745b` |
| Extracted nets | 3,799,491 |
| RC segments | 37,974,421 |
| RSegs | 41,773,760 |
| Caps | 41,773,760 |
| Coupling caps | 40,630,055 |
| RC segments/net | 약 9.995 |
| SPEF bytes/net | 약 1,861 bytes |
| Unannotated drivers | 412,694 |
| Partially unannotated drivers | 0 |

Unannotated driver 412,694개는 open/short/DRC 412,694건을 의미하지 않는다. SPEF의 RC가 STA driver에 매핑되지 않은 수다. annotation coverage의 전체 driver denominator가 report에 없으므로 “coverage 퍼센트”는 계산하지 않았다.

| 관찰 분류 | 수 | unannotated 내부 비율 |
|---|---:|---:|
| `clkload*` | 32,537 | 7.884% |
| `reset_leaf` 포함 이름 | 62 | 0.015% |
| top-level port | 1 | 0.0002% |
| 기타 hierarchical driver | 380,094 | 92.101% |

따라서 문제를 CTS clock net 또는 reset net 하나로만 축소할 수 없다. 대부분은 일반 hierarchical/synthesized driver다. 후속 분석에서는 ODB net 이름과 SPEF `*D_NET` 이름을 표본 대조하고, zero-length/local net인지 name-mapping 누락인지 분리해야 한다.

## 5. STA 상세 분석

### 5.1 제약과 단위

| 항목 | 값 |
|---|---|
| Clock | `clk` |
| Source | `clk_i` |
| Period | 40.000ns |
| Frequency | 25MHz |
| Clock uncertainty | 0.500ns, path report 기준 |
| Input delay | 주요 입력 2.000ns |
| Output delay | 주요 출력 2.000ns |
| Time unit | 1ns |
| Capacitance unit | 1pF |
| Resistance unit | 1kΩ |

이 결과는 1.78ns 제약 결과가 아니다. R16 `5_2_route.sdc`와 R8 STA runner가 요구한 실제 period는 40ns다. `check_setup_pass=1`은 constraint coverage 검사 성공이지 timing closure PASS가 아니다.

### 5.2 Slack 결과

| Check | WNS | TNS | 판정 |
|---|---:|---:|---|
| Setup/max | −318.877946ns | −21,913,132.318712ns | FAIL |
| Hold/min | −5.379516ns | −4,164.842839ns | FAIL |

![Timing slack](graphs/timing_slack.svg)

현재 frozen report는 전체 violating endpoint 수를 출력하지 않았다. 따라서 TNS는 사용할 수 있지만 violation endpoint count는 `NOT_AVAILABLE`이다. 극심한 slew와 annotation limitation 때문에 `40ns + |WNS|`로 Fmax를 단순 역산하는 것도 유효하지 않으며 Fmax는 `NOT_VALID_TO_DERIVE`로 남긴다.

### 5.3 최악 일반 setup 경로

| 항목 | 관찰값 |
|---|---|
| Startpoint | `u_quad_local_adapter/_4428_` |
| Endpoint | `g_quad[2].u_payload_store/_12466_` |
| Path group | `clk` |
| Path type | max |
| Data arrival | 365.5929ns |
| Data required | 46.7150ns |
| Slack | −318.8780ns |
| 핵심 고부하 node | `clone380183/B` |
| Capacitance | 40.9556pF |
| 핵심 output slew | 287.4541ns at `clone380183/Y` |

지연의 대부분은 긴 논리 깊이보다 `clone380183` 주변의 대부하·대slew에서 발생한다. 이 net은 buffer/split tree가 존재함에도 한 지점에서 40.956pF를 구동한다. R15/R8 로그에서도 `GRT-0281` large-fanout warning이 101개 발생했고 최대 fanout은 6,794 terminal이다. 따라서 1순위 병목은 payload/control 계열의 fanout과 물리 분배 구조다.

### 5.4 Reset recovery/removal

비동기 reset도 별도로 실패한다.

| Check | 경로 | Slack |
|---|---|---:|
| Recovery | `apply_reset_leaf` Q → 하위 `RESET_B` | −289.4002ns |
| Removal | `scalar_array_reset_leaf` Q → 하위 `RESET_B` | −2.7514ns |

RTL의 `normalization_quad_reset_leaf`는 비동기 assert, 2-flop synchronous release 구조다. 외부 `rst_ni`에는 false path가 있지만 내부 `sync_release_q → RESET_B`는 Liberty recovery/removal 검사를 받는다. 이 위반은 실제 reset integrity 문제일 수 있으므로 단순 false-path로 숨기면 안 된다. 다만 일반 `clk` setup 경로가 −318.878ns로 더 나쁘기 때문에 현재 전체 timing 실패가 reset-only 현상은 아니다.

### 5.5 Hold 경로

일반 hold 최악 경로는 `job_row_i[2]` 입력에서 adapter flop으로 가며 slack은 −5.3795ns다. 입력 external delay는 2ns인데 endpoint propagated clock insertion은 약 7.53ns이므로 post-CTS I/O latency 모델과 hold fixing이 충분하지 않다. 이는 내부 데이터 경로 hold와 구분해 I/O constraint/board model을 먼저 검증해야 한다.

## 6. Power 상세 분석

Power report의 그룹별 구성은 다음과 같다.

| Group | Internal | Switching | Leakage | Total | 비율 |
|---|---:|---:|---:|---:|---:|
| Sequential | 0.367784W | 0.068742W | 0.000004W | 0.436530W | 23.8% |
| Combinational | 0.302029W | 0.698337W | 0.000008W | 1.000374W | 54.6% |
| Clock | 0.231217W | 0.164844W | 0.000001W | 0.396062W | 21.6% |
| Total | 0.899090W | 0.931592W | 0.000013W | 1.830695W | 100% |

![Power breakdown](graphs/power_breakdown.svg)

해석:

- Combinational power가 54.6%로 가장 크고 그중 switching이 지배적이다.
- Clock power가 21.6%로 높다. 4.9M-instance 규모와 큰 clock tree가 반영된 결과다.
- Leakage는 거의 0으로 출력되지만, corner·library·unit 및 vectorless 조건을 고려하면 실제 칩 leakage 주장에 사용할 수 없다.
- SAIF/VCD가 없으므로 데이터 이동 패턴, normalization workload, idle/busy duty cycle이 반영되지 않았다.
- `power.rpt` 헤더는 Watts라 표기하지만 `report_units`는 power `1nW`를 출력한다. 본 보고서는 raw header 수치를 W로 보존하되 `UNIT_CAVEAT`를 유지한다.
- Sequential·Combinational·Clock의 raw total 합은 1.8329661W로 전체 Total 행 1.830695W보다 0.0022711W, 약 0.124% 크다. 반올림 또는 report 집계 차이로 보이지만 원인이 증명되지 않았으므로 `GROUP_SUM_MISMATCH`로 보존한다.

현재 power는 구조적 비교용이다. 실제 에너지 분석에는 대표 workload의 VCD/SAIF, cycle count, 처리 데이터량, 동일 PVT/corner 및 동일 clock constraint가 필요하다.

## 7. 실행 비용과 병목

| Stage | Wall time | 평균 CPU | Peak RSS | Exit |
|---|---:|---:|---:|---:|
| DRT | 18:59:04 | 1216% | 80.259GiB | 0 |
| R8 reopen | 00:06:25 | 약 1 core 수준 | 33.471GiB | 0 |
| RCX | 00:33:45 | 99% | 16.846GiB | 0 |
| STA/PPA | 00:56:16 | 147% | 33.321GiB | 0 |
| 합계 | 20:35:29 | — | — | all stage exits 0 |

![Runtime and memory](graphs/runtime_memory.svg)

DRT가 관측 chain wall time의 약 92.2%를 사용한 명확한 병목이다. 다음 가설 탐색에서 모든 후보를 DRT-clean까지 실행하면 비용이 크다. 합성/placement/CTS STA로 후보를 먼저 거르고, 유망 후보만 DRT/RCX/STA로 승격하는 계층형 검증이 필요하다.

## 8. 데이터 신뢰도 및 provenance

중복 제거 deep hash로 다음 대형 핵심 산출물을 직접 검증했고 모두 기존 evidence와 일치했다.

| Artifact | SHA256 | 판정 |
|---|---|---|
| Canonical OpenROAD | `ed2d7276…27f9` | PASS |
| R15 input guide | `aa94c894…c479` | PASS |
| R15 input ODB | `1988d2f8…2c78` | PASS |
| R16 final SDC | `c3f1381d…50e8` | PASS |
| R16 final DEF | `edc4fac9…5ad` | PASS |
| R16 final ODB | `3178f8e4…4ee` | PASS |
| R16 RCX SPEF | `05f087ad…745b` | PASS |
| Empty final DRC report | `e3b0c442…b855` | PASS_EMPTY |

다만 repository-wide governance 판정은 `PROVENANCE_MISMATCH`다.

- R16 root `execution_manifest.json`이 없다.
- historical R7 hash evidence가 현재 mutable active-plan JSON/Markdown의 이전 hash를 pin하고 있어 현재 파일과 불일치한다.
- candidate plan은 여전히 `PREPARED_NOT_EXECUTED`, `downstream_after_drt=NOT_AUTHORIZED`를 기록하며, 후속 R8 authorization은 별도 승인 문서로 존재한다.
- repository deep verifier는 1,958개 hash-evidence 행에서 같은 대형 파일을 반복 해시해 약 258GB를 읽은 뒤 중단했고, 핵심 대형 파일을 각각 한 번만 해시하는 검증으로 대체했다.

이 mismatch는 현재 사용한 ODB/DEF/SPEF의 hash mismatch가 아니다. 핵심 물리 산출물의 동일성은 PASS지만, 전체 연구 패키지의 단일 manifest 완결성은 부족하다. 그러므로 `PROVENANCE_PASS`로 승격하지 않는다.

## 9. 연구적 의미

이 결과는 “고성능 설계 성공”은 아니지만 연구적 의미는 분명하다.

1. 3.8M routed-net, 4.9M-instance 규모 설계에서 strict-zero GRT → DRT clean → RCX → extracted STA/PPA까지 end-to-end로 도달했다.
2. GRT strict-zero가 timing closure를 보장하지 않는다는 사실을 정량적으로 보였다.
3. DRT는 2.28M violation에서 0으로 수렴했지만 19시간이 필요했고, 탐색 비용 병목을 측정했다.
4. timing 병목이 reset-only가 아니라 일반 clocked payload/control path의 40.96pF 부하와 287ns slew에도 있음을 확인했다.
5. clock power 21.6%, combinational switching power 우세, met1/met2 배선 82.92%라는 구조적 trade-off 신호를 얻었다.
6. annotation coverage와 vectorless power가 탐색 PPA 신뢰도를 제한하는 지점을 명시적으로 찾았다.

삼성 제출/논문에서는 다음처럼 표현하는 것이 타당하다.

> 본 구현은 strict-zero global routing과 DRC-clean detailed routing을 달성하고 post-route RC extraction 및 exploratory PPA까지 완료했다. 한편 40ns constraint에서도 high-fanout payload/control distribution과 reset release network에서 심각한 timing violation이 관찰되었다. 따라서 본 결과는 timing-closed 제품 결과가 아니라 물리 실현 가능성, 병목 위치, 개선 우선순위를 정량화한 연구 artifact로 분류한다.

## 10. 다음 작업 우선순위

### P0 — 분석 신뢰도 보강

1. 동일 ODB/SPEF를 재사용해 STA report-only 실행을 수행한다. 일반 `clk`, async recovery/removal, I/O path group을 분리하고 violating endpoint 수, max transition, max capacitance, max fanout을 추가한다.
2. 40ns가 실제 연구 목표인지 확정한다. 1.78ns와 혼재된 과거 표기를 제거하고 모든 비교 후보에 동일 SDC를 적용한다.
3. 412,694 unannotated driver를 zero/local net, clock load, reset, 일반 hierarchical net으로 실제 SPEF name mapping 대조한다.

### P1 — Timing 병목 개선

1. `clone380183` 계열과 payload-store 입력망의 fanout을 분할하고 register/buffer replication을 적용한다.
2. quad-local payload/control 신호가 물리 영역을 가로지르지 않도록 source와 sink를 지역화한다.
3. reset leaf의 synchronous release와 downstream `RESET_B` recovery/removal를 별도 검증하고 clock/reset branch skew를 줄인다.
4. `job_row_i` hold는 외부 I/O latency 모델을 확인한 후 hold buffer 또는 input constraint를 수정한다.

### P2 — 연구용 power와 비교군 완성

1. 대표 normalization workload VCD/SAIF를 생성해 activity-annotated power를 산출한다.
2. 처리 cycle과 데이터량을 함께 기록해 energy/operation 및 energy/byte를 계산한다.
3. 동일 RTL·SDC·corner·activity·post-route stage의 baseline을 한 개 이상 생성한다.
4. 빠른 synthesis/placement/CTS STA로 후보를 선별하고 최종 후보만 DRT/RCX를 실행한다.

## 11. 원자료와 정규화 데이터

정규화 데이터:

- [summary_metrics.csv](data/summary_metrics.csv)
- [final_ppa_metrics.json](data/final_ppa_metrics.json)
- [drt_iteration_violations.csv](data/drt_iteration_violations.csv)
- [layer_wirelength.csv](data/layer_wirelength.csv)
- [power_breakdown.csv](data/power_breakdown.csv)
- [unannotated_driver_breakdown.csv](data/unannotated_driver_breakdown.csv)
- [runtime_resources.csv](data/runtime_resources.csv)
- [global_route_lineage.csv](data/global_route_lineage.csv)
- [provenance_checks.csv](data/provenance_checks.csv)

핵심 raw evidence:

- R16 DRT: `.../drt/detail_route.log`, `5_2_route.odb`, `5_2_route.def`, `5_2_route.sdc`, `5_route_drc.rpt`
- R8 independent reopen: `.../downstream/reopen_r8_20260825T141825Z/stdout.log`
- RCX: `.../downstream/rcx_r8_20260825T142632Z/r16_routed.spef`, `stdout.log`
- STA/PPA: `.../downstream/sta_ppa_r8_20260825T142632Z/reports/`
- R8 authorization: `.../R16_R8_APPROVED_DOWNSTREAM_PLAN.md`

## 12. 최종 claim boundary

지원되는 주장:

- R15 GRT strict-zero
- R16 detailed route clean, final DRV 0
- independent reopen mandatory gate PASS
- RCX 및 extracted exploratory STA/PPA 실행 완료
- area, wire, via, timing, vectorless power의 raw/derived 연구 데이터 확보
- timing closure 실패와 구체적 high-load/high-slew 병목 확인

지원되지 않는 주장:

- timing-closed 또는 25MHz 달성
- 1.78ns 달성
- workload-representative power/energy
- PPA가 baseline보다 우수하다는 주장
- signoff-clean GDS, 제조 가능, tapeout ready

최종 판정: **물리 배선과 RC extraction은 성공했고 exploratory PPA 원자료는 완성됐으나, timing은 실패했으며 power와 parasitic annotation에는 큰 신뢰도 제한이 있다. 연구 artifact로는 유의미하지만 제품/성능 성공 결과로 포장해서는 안 된다.**
