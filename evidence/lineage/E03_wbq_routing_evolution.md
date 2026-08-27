# V1~V8 물리 실험과 WBQ 구조 전환

## 이 문서의 목적

이 문서는 GR00T normalization RTL의 배선 가능성을 확인하기 위해 수행한 V1~V8 물리 실험과, 이후 중앙 집중형 writeback을 WBQ(Writeback Quad Slice) 구조로 바꾼 이유를 설명합니다.

V1~V8의 숫자는 제품 완성도나 RTL 세대를 뜻하지 않습니다. 동일한 normalization RTL을 대상으로 배치, HBM 접점 모델, bank locality, 라우터 반복 횟수 등을 바꿔 본 **물리 설계 실험 번호**입니다. 따라서 번호가 큰 V8이 V4보다 더 완성된 배선 결과라는 뜻은 아닙니다.

## 먼저 알아야 할 용어

- **Placement(배치):** 표준 셀을 칩 평면의 실제 위치에 놓는 단계입니다.
- **Global route(전역 배선):** 각 신호선이 지나갈 대략적인 배선 통로를 정하고 혼잡을 측정하는 단계입니다.
- **Residual congestion(잔여 혼잡):** 라우터가 배선을 분산한 뒤에도 배선 수요가 가용 용량을 초과한 정도입니다. 숫자가 0이 아니면 배선 가능성이 아직 입증되지 않은 것입니다.
- **Landing pad:** HBM과 logic die 사이의 내부 접점을 연구용으로 근사한 물리 모델입니다. 실제 제조용 micro-bump sign-off 모델은 아닙니다.
- **WBQ:** 16개 bank를 4개 quad로 나누고, reduction·replay·writeback을 가까운 quad에서 먼저 처리하는 구조입니다.

## V1~V8에서 확인한 것

| 버전 | 바꾼 내용 | 결과 또는 상태 | 얻은 판단 |
|---|---|---|---|
| V1 | 초기 repaired/legal placement에서 기본 global route 수행 | 초기 배선 기준선 확보 | 합법 배치만으로 배선 가능성이 보장되지는 않음 |
| V2 | fanout·slew·cap repair 후 재합법화, perimeter HBM pin 모델로 route | 잔여 혼잡 `1,600,437`, FAIL | HBM 내부 연결을 die 가장자리 package I/O처럼 둔 모델이 큰 인공 병목을 만듦 |
| V3 | command/read 신호를 분산 met5 landing pad로 옮기고 routing 5회 시도 | 실험 스크립트는 보존됐지만 최종 비교 기준으로 채택된 정량 결과는 없음 | 내부 접점 분산 방향을 시험 |
| V4 | 565개 분산 met5 landing pad, met1~met5, CuGR 1회 | 잔여 혼잡 `2,620`, overflow edge `2,003`, report entry `5,998`, FAIL | perimeter-pin 병목은 99.84% 줄었지만 flat placement 내부 hotspot이 남음 |
| V5 | 16개 bank를 4×4 guide로 묶어 bank-aware placement | 합법 배치는 성공했으나 잔여 혼잡 `1,182,646`, FAIL | bank를 섬처럼 나누면 2048-bit급 global/replay/writeback 연결이 경계에 몰림 |
| V6 | V5 bank guide를 사용하되 배치 조건을 다시 조정 | placement 실험 단계 | bank locality만으로 해결 가능한지 재검토 |
| V7 | V4의 배치·landing-pad 조건을 유지하고 routing 반복을 1회에서 5회로 증가 | 확정된 개선 수치 없음 | 라우터 반복만으로 구조적 병목을 해결할 수 있는지 분리 실험 |
| V8 | hard/soft bank region 없이 routability-driven placement 적용 | placement ODB/SDC 생성용 실험이며 완료된 global-route 비교 수치 없음 | 혼잡 피드백만으로 셀을 분산하는 마지막 placement 방향 |

표의 수치는 `reports/groot_normalization/physical_feasibility/physical_feasibility_metrics.json`과 물리 타당성 보고서에 기록된 값입니다. V3, V6, V7, V8은 실행 스크립트의 목적은 확인되지만, V4와 같은 조건으로 채택할 수 있는 완료된 정량 결과가 없으므로 결과를 추정하지 않습니다.

## 왜 V4가 비교 기준인가

V4는 번호가 최신이어서가 아니라 다음 조건을 만족하는 가장 좋은 완료 기준이기 때문입니다.

1. 실제 global route를 수행했습니다.
2. route guide와 congestion report를 생성했습니다.
3. 잔여 혼잡 `2,620`이라는 재현 가능한 수치가 있습니다.
4. 분산 landing pad를 사용해 잘못된 perimeter-pin 병목을 제거했습니다.
5. 최신 WBQ에서도 같은 pin 모델, 배선층과 metric 정의를 사용할 수 있습니다.

V5는 V4보다 혼잡이 크게 악화됐고, V8은 배치 단계 이후의 완료 global-route 수치가 없습니다. 따라서 WBQ의 효과를 공정하게 판단하려면 V4 조건을 control로 고정하고 아키텍처 차이만 비교해야 합니다.

## 왜 배치 실험을 멈추고 WBQ로 바꿨는가

V4~V8은 landing pad, bank 배치와 라우터 옵션을 바꾸는 실험이었습니다. 그러나 반복 결과는 혼잡의 핵심 원인이 단순한 셀 위치가 아니라 **중앙 집중형 연결 구조**임을 보여주었습니다.

기존 구조에서는 다음 현상이 발생했습니다.

```text
Bank 0  ─┐
Bank 1  ─┤
...      ├── 2048-bit급 global/replay/writeback 연결 ── 중앙 처리부
Bank 15 ─┘
```

- 16개 bank의 넓은 신호가 중앙으로 모입니다.
- bank를 물리적으로 나누어도 넓은 버스가 각 영역 경계를 통과합니다.
- 중앙부와 bank 경계의 제한된 배선 통로에 수요가 집중됩니다.
- 라우터 반복 횟수를 늘리거나 셀을 조금 이동해도 연결 관계 자체는 바뀌지 않습니다.

도로에 비유하면 모든 지역의 화물을 하나의 중앙 물류센터로 보내는 구조입니다. 도로 위치를 바꾸는 것만으로는 도심 진입 정체를 없애기 어렵습니다.

WBQ는 이 연결 관계를 다음처럼 바꿉니다.

```text
Bank 0~3   ── Quad 0 WBQ ─┐
Bank 4~7   ── Quad 1 WBQ ─┤
Bank 8~11  ── Quad 2 WBQ ─┼── 축약된 quad 결과 ── 중앙 처리부
Bank 12~15 ── Quad 3 WBQ ─┘
```

각 quad가 가까운 bank의 reduction·replay·writeback을 먼저 처리하므로 중앙까지 이동하는 원시 데이터와 wide-bus fanout을 줄일 수 있습니다. 즉, WBQ는 라우터 설정 변경이 아니라 **배선 병목의 원인이 된 데이터 이동 구조 자체를 바꾼 아키텍처 수정**입니다.

## 현재까지 증명된 범위

- WBQ unit test와 PCU→WBQ→HBM adapter 통합 조합은 기능 회귀를 통과했습니다.
- 최신 WBQ RTL은 Sky130HD technology mapping을 통과했습니다.
- 현재는 WBQ mapped netlist의 repair·placement·legalization을 진행하고 있습니다.
- WBQ global route가 V4의 잔여 혼잡 `2,620`보다 개선되는지는 아직 측정해야 합니다.
- Global route 이후에도 CTS, detailed route, timing 및 구조 검증을 통과해야 최종 연구용 routed GDS로 판정할 수 있습니다.

따라서 현재의 정확한 결론은 다음과 같습니다.

> V1~V8은 중앙 집중형 normalization RTL의 물리 병목을 찾은 실험이고, WBQ는 그 병목을 배치 옵션이 아닌 아키텍처 수준에서 해결하기 위한 후속 구조입니다. WBQ의 기능과 합성은 확인됐지만 최종 배선 가능성은 아직 검증 중입니다.

## 관련 근거

- 정량 지표: [`../reports/groot_normalization/physical_feasibility/physical_feasibility_metrics.json`](../reports/groot_normalization/physical_feasibility/physical_feasibility_metrics.json)
- 물리 타당성 보고서: [`../reports/groot_normalization/physical_feasibility/01_lightweight_physical_feasibility_report.html`](../reports/groot_normalization/physical_feasibility/01_lightweight_physical_feasibility_report.html)
- V1~V8 실행 스크립트: [`../verification/groot_normalization/`](../verification/groot_normalization/)
- WBQ 기능 회귀 보고서: [`../reports/final_integrated_gds_execution/01_wbq_functional_regression_report.html`](../reports/final_integrated_gds_execution/01_wbq_functional_regression_report.html)
- WBQ 합성 보고서: [`../reports/final_integrated_gds_execution/02_wbq_synthesis_report.html`](../reports/final_integrated_gds_execution/02_wbq_synthesis_report.html)
