# B25 Track B 배치 실패 진단

갱신일: 2026-08-19 UTC

## 판정

B25는 저비용 기능 및 mapped-locality gate는 통과했지만 global route 이전의 detailed placement에서 실패했습니다. 이 실패는 legalization/capacity 실패이며, RTL protocol 또는 arithmetic 실패로 입증된 것은 아닙니다.

근거:

- `cheap_gate_manifest.json`: 전체 결과 `PASS`.
- `b25_placement_authorization.json`: 배치 승인 `PASS`.
- `physical/b25_placement_execution_report.json`: 배치 `FAIL`, 종료 코드 `2`.
- `physical/b25_place.log`: `DPL-0033`, 불법 셀 48,736개 잔여, overlap 검사 17,972회 및 padding 검사 17,972회.
- 요청한 목표를 수용할 fenced free area가 부족해 배치 흐름이 목표 밀도를 `0.39`에서 `0.43`으로 올렸습니다.

## 원인 분류

B25 completion-descriptor ECO로 중앙 completion interface는 68비트에서 17비트로 줄었지만, 물리 실패는 여전히 다음 요소의 상호작용이 지배합니다.

1. four exclusive quad fences;
2. central corridor and clock/reset/control routing demand;
3. resized buffer/inverter cells around payload, apply, and control paths;
4. insufficient legal row space for the detailed legalizer to resolve overlaps and padding.

이 실패를 잔여 배선 혼잡만의 원인으로 해석해서는 안 됩니다. B25는 합법적인
배치 또는 배선 입력을 생성하지 못했습니다.

## 다음 실험: B26 배치 정책 격리

B25 RTL을 다시 변경하기 전에 봉인된 B25 mapped netlist와 동일한 floorplan/fence 계약으로 B26 격리 실험을 한 번 수행합니다. 배치 복구 정책만 변경합니다.

- B25 RTL, mapped netlist, floorplan, SDC 및 fence geometry를 보존합니다.
- 마지막 유효 B25 pre-detail checkpoint에서 명시적 incremental detailed-placement recovery pass를 사용합니다.
- 확립된 DRC-penalty 정책값 (`20`, 이후 `100`)을 별도 output namespace에서 시험합니다.
- `set_placement_padding -global -left 0 -right 0`을 유지합니다.
- 독립 legality/fence reopen 감사를 요구합니다.
- 배치 위반 및 overlap/padding 검사가 0이 아니면 배선하지 않습니다.

이 실험은 B25 실패가 legalization 정책으로 복구 가능한지 분리합니다. 두 정책 시험이 동일한 fence 국소 위반으로 실패하면 다음 ECO는 물리 밀도/용량 또는 배치에 보이는 buffer/control 구조를 바꿔야 합니다. B25 산출물은 덮어쓰지 않습니다.

## 승격 규칙

합법적인 배치를 가진 B26 후보만 단일 global route로 진행할 수 있습니다. `rrr_residual=0` 및 `overflow_edges=0`인 후보만 CTS로 진행할 수 있습니다. 0이 아닌 결과는 Track B 탐색 증거로 남기며 최종 PPA/signoff 증거로 사용하지 않습니다.
