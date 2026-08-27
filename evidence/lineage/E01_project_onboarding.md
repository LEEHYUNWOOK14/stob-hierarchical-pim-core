# STOB PIM2 프로젝트 온보딩 가이드

> 대상: 이 저장소와 PIM 연구를 처음 보는 개발자·연구자  
> 현재 상태 기준: 2026-08-24 UTC, `PIM_Simulator` 브랜치  
> 이 문서는 전체 연구의 지도와 현재 작업의 위치를 설명합니다. 세부 실행법은 링크된 전문 문서를 따르세요.

## 1. 한 문장으로 설명하면

이 프로젝트는 **HBM2 메모리 가까이에서 AI 연산을 수행하는 PIM(Processing-in-Memory) 구조**를 만들고, C++ 사이클 시뮬레이션에서 시작해 SystemVerilog RTL, 합성, 배치·배선, 3D 적층, 전력·열·비용 분석까지 같은 설계가 실제로 타당한지 단계별로 검증하는 연구 프로젝트입니다.

지금 가장 중요한 질문은 다음과 같습니다.

> 기능적으로 맞는 normalization PIM RTL을 실제 표준 셀로 배치하고 배선할 수 있는가? 배선 혼잡을 줄이기 위해 연산·reduction·writeback 구조를 어떻게 지역화해야 하는가?

## 2. 왜 이 일을 하는가

AI workload는 많은 데이터를 메모리와 연산기 사이에서 반복해서 옮깁니다. 이때 계산 자체보다 데이터 이동의 지연과 에너지가 더 큰 병목이 될 수 있습니다. 이 프로젝트는 연산 일부를 HBM bank 주변과 logic die로 옮겨 다음을 확인합니다.

- HBM channel·bank 병렬성을 활용하면 실행 시간과 데이터 이동량이 얼마나 줄어드는가?
- bank-side PIM과 logic-die PIM의 역할을 어떻게 나누는 것이 좋은가?
- command queue, buffer, broadcast, reduction, writeback의 병목은 어디서 생기는가?
- 시뮬레이터에서 유리한 구조가 RTL 기능 검증과 실제 배치·배선도 통과하는가?
- 성능뿐 아니라 면적, 전력, 온도, TSV·패키징, 비용 위험까지 함께 비교할 수 있는가?

대상 workload는 GEMV와 element-wise 연산, MobileNetV4 UIB, NVIDIA Isaac GR00T 계열의 LayerNorm/RMSNorm입니다.

## 3. 시스템 구조

```text
AI workload / host trace
          │
          ▼
C++ HBM2 PIM cycle simulator
  ├─ MemoryController와 command queue
  ├─ HBM channel / rank / bank timing
  └─ latency, traffic, bandwidth, energy 통계
          │ architecture 후보와 실행 trace
          ▼
SystemVerilog RTL
  ├─ bank-side PIM 연산기
  ├─ logic-die shared PCU
  ├─ reduction / replay / affine
  └─ WBQ writeback + HBM boundary adapter
          │ 기능 회귀와 합성된 netlist
          ▼
Yosys + OpenROAD + Sky130HD
  ├─ technology mapping
  ├─ floorplan / placement / legalization
  ├─ CTS / global route / detailed route
  └─ 연구용 GDS
          │ 측정값과 구조 정보
          ▼
PPA / thermal / package / yield / cost 비교
```

현재 normalization 물리 설계에서는 16개 bank를 4개 quad로 나눈 **WBQ(Writeback Quad Slice)** 구조를 사용합니다. 중앙에 하나의 큰 writeback 경로를 두는 대신 각 quad에서 reduction·replay·writeback을 처리해 긴 배선과 fanout을 줄이려는 구조입니다.

## 4. 검증은 네 층으로 나뉜다

| 층 | 질문 | 대표 도구·산출물 |
|---|---|---|
| 시스템 시뮬레이션 | 구조가 workload를 정확하고 빠르게 처리하는가? | C++, DRAMSim2 기반 simulator, cycle/traffic 통계 |
| RTL 기능 검증 | cycle·protocol·수치 결과가 하드웨어 모델에서도 맞는가? | Icarus Verilog, Verilator, testbench 로그 |
| 물리 구현 가능성 | 셀을 놓고 실제 배선을 만들 수 있는가? | Yosys, OpenROAD, ODB/SDC, congestion report, GDS |
| 시스템 비용 평가 | 성능 이득이 면적·전력·열·패키지 비용을 정당화하는가? | JSON/CSV metric, thermal/cost model, Pareto 비교 |

한 층의 PASS가 다음 층의 PASS를 뜻하지 않습니다. 예를 들어 RTL simulation PASS는 기능 증거이지만, 배선 가능성이나 timing closure의 증거는 아닙니다.

## 5. 현재 어디까지 왔는가

### 완료되었거나 기반이 확보된 부분

- HBM2 PIM cycle simulator와 PIM 명령 모델
- bank-side/logic-die 계층 구조 및 queue·buffer·backpressure 실험
- MobileNetV4 UIB 기능·성능 실험
- GR00T normalization workload와 FP16/BF16 RTL 검증
- WBQ 기능 회귀와 Sky130HD technology mapping
- PPA·열·패키징·수율·비용 분석 파이프라인
- 일반 HBM2/GPU, matched bank-level PIM, B26 계층형 PIM의 세 아키텍처 비교용 evidence package

### 현재 물리 검증 상태

Track B는 B26-L2D/A8의 CTS와 post-CTS global-route 실험을 거쳐 R11 detailed-route 단계까지 진입했습니다. 현재 manufacturing signoff가 아니라 post-route research PPA와 exploratory GDS/OASIS readback을 목표로 합니다.

| 단계 | 현재 결과 | 의미 |
|---|---|---|
| CTS/DPL | strict-completion lineage 보존 | clock tree와 legal placement를 downstream 입력으로 사용 |
| R10 global route | `H10_MET3_CAPACITY_SENSITIVE_PARTIAL` | route/reopen PASS, total congestion 0.79와 unresolved resource 1은 공개 |
| R11 detailed route | 진행 중 | pin access/track assignment 완료, detail routing 0th optimization iteration 진입 |
| RCX/post-route PPA | R11 Gate A 대기 | DRT integrity와 independent reopen 통과 시 실행 |
| exploratory GDS/OASIS | PPA 이후 별도 단계 | export/hash/독립 readback 필수, manufacturing-clean 주장은 금지 |
| full signoff | `OMITTED_BY_POLICY` | full DRC/LVS/antenna/process/tapeout 검증은 연구 범위 밖 |

현재 방향은 다음과 같습니다.

- R11에서 `design_is_routed`, unrouted/open/short/basic integrity와 independent reopen을 확인합니다.
- Gate A가 통과하면 routed parasitic extraction과 post-route STA/PPA를 수행합니다.
- PPA만으로 종료하지 않고 exploratory GDS/OASIS를 export하고 독립 readback합니다.
- full-chip/foundry DRC, LVS, antenna signoff 및 tapeout readiness는 실행하거나 주장하지 않습니다.
- 모든 결과는 `EXPLORATORY_PHYSICAL_PPA_RESULT` 또는 `POST_ROUTE_ESTIMATE`로 분류합니다.

현재 방향의 기준 문서는 다음입니다.

- [`TRACK_B_B26_L2D_A8_ACTIVE_DOWNSTREAM_PLAN.md`](TRACK_B_B26_L2D_A8_ACTIVE_DOWNSTREAM_PLAN.md)
- [`research_ppa_policy_update.md`](reports/groot_normalization/quad_local_b26_l2d_a8_cts_r3_fence_ownership_r1_20260823T001622Z/research_ppa_policy_update.md)
- [`research_ppa_work_plan.json`](reports/groot_normalization/quad_local_b26_l2d_a8_cts_r3_fence_ownership_r1_20260823T001622Z/research_ppa_work_plan.json)
- [`R11 candidate_plan.json`](reports/groot_normalization/quad_local_b26_l2d_a8_r11_h11_drt_rcx_ppa_r1_20260824T025851Z/candidate_plan.json)

## 6. 디렉터리 지도

| 경로 | 처음 보는 사람이 알아야 할 내용 |
|---|---|
| `src/` | C++ HBM2/PIM simulator 핵심 구현 |
| `src/tests/` | GoogleTest 기반 simulator 기능·benchmark 테스트 |
| `ini/`, `system_*.ini` | HBM device timing과 channel/address mapping 설정 |
| `data/` | 기능 테스트용 입력과 기대 출력 |
| `rtl/` | bank-side, logic-die, normalization SystemVerilog RTL |
| `verification/groot_normalization/` | normalization RTL 회귀·합성·OpenROAD 실행 및 감사 스크립트 |
| `flow/designs/sky130hd/` | OpenROAD-flow-scripts용 Sky130HD design 설정 |
| `experiment/` | architecture/workload 실험, 보고서, 재현 스크립트 |
| `reports/` | JSON/CSV/HTML/log evidence; 최신 판정은 manifest를 우선 |
| `hardware_cost/` | area·power·thermal·package·yield·cost 모델 |
| `design/` | 설계 계약, 구조 설명, 검증 체크리스트 |
| `tools/` | 분석·수집·검증·보고서 생성 도구 |
| `output/` | 생성된 GDS, 그림, 분석 출력; 대용량·재생성 파일 포함 |
| `frozen_rtl/` | 특정 검증 기준으로 동결한 RTL 스냅샷 |
| `work_status/` | 날짜별 작업 기록과 provenance |

`reports/`, `output/`, OpenROAD 결과에는 Git에 포함되지 않은 대용량 산출물이 많습니다. 파일 존재만으로 성공을 판단하지 말고 해당 실행의 manifest, hash, completion marker를 함께 확인해야 합니다.

## 7. 처음 읽을 문서

다음 순서가 가장 빠릅니다.

1. 이 문서: 전체 목적과 현재 위치 파악
2. [`README.md`](README.md): 연구 전체 범위와 세부 작업 트리
3. [`PIMSimulator_GUIDE.md`](PIMSimulator_GUIDE.md): C++ simulator 구조, 빌드, 테스트
4. [`design/wbq_routing_evolution_v1_v8.md`](design/wbq_routing_evolution_v1_v8.md): 물리 혼잡 문제와 WBQ로 전환한 이유
5. 최신 [`ladder_final_report.json`](reports/groot_normalization/quad_local_b26_l2d_corridor_widen_1gcell_r1_20260821T074358Z/ladder_final_report.json): 현재 실험 결과
6. [`hardware_cost/README.md`](hardware_cost/README.md): 비용·열·PPA 수치의 의미와 한계

특정 분야만 볼 경우:

- simulator: [`PIMSimulator_GUIDE.md`](PIMSimulator_GUIDE.md)
- 현재 PIM command routing: [`design/current_pim_routing_state.md`](design/current_pim_routing_state.md)
- RTL 구조: [`design/full_pim_rtl_architecture.md`](design/full_pim_rtl_architecture.md)
- physical design 환경: [`design/openroad_klayout_environment_setup.md`](design/openroad_klayout_environment_setup.md)
- 실험 실행 원칙: [`design/routing_experiment_checklist.md`](design/routing_experiment_checklist.md)
- GR00T placement 연구: [`experiment/gr00t_placement/overview.md`](experiment/gr00t_placement/overview.md)

## 8. 가장 가벼운 시작 방법

### C++ simulator 빌드

Ubuntu 기준 핵심 의존성은 SCons, C++17 compiler, GoogleTest입니다.

```bash
sudo apt install scons libgtest-dev
scons
```

빌드 결과는 `sim`이며, 테스트 목록은 다음처럼 확인합니다.

```bash
./sim --gtest_list_tests
```

가벼운 기능 테스트 예시는 다음과 같습니다.

```bash
./sim --gtest_filter=PIMKernelFixture.add
./sim --gtest_filter=PIMKernelFixture.mul
./sim --gtest_filter=PIMKernelFixture.gemv
```

전체 테스트 이름과 configuration 의미는 [`PIMSimulator_GUIDE.md`](PIMSimulator_GUIDE.md)를 참고하세요.

### 처음부터 실행하면 안 되는 것

OpenROAD placement/routing은 수십 GB 메모리와 긴 실행 시간이 필요할 수 있습니다. 새 참여자는 아래 조건을 확인하기 전에는 물리 flow를 실행하지 않는 편이 안전합니다.

- 입력 RTL/netlist/SDC/ODB hash가 어떤 후보를 가리키는지
- 해당 단계의 실행 권한 gate와 candidate budget이 열려 있는지
- 같은 호스트에서 다른 대형 OpenROAD 작업이 실행 중인지
- 출력 namespace가 기존 증거를 덮어쓰지 않는지
- 실패 시에도 manifest와 로그를 남기는지

## 9. 결과를 올바르게 읽는 법

이 저장소는 서로 다른 강도의 증거를 함께 다룹니다.

| 표현 | 뜻 |
|---|---|
| `measured` | 도구 또는 simulator가 직접 측정 |
| `rtl_simulated` | RTL testbench에서 기능 확인 |
| `synthesized` | 논리 합성/technology mapping 확인 |
| `placed` | 배치와 legalization 확인 |
| `routed_research_artifact` | 공개 PDK 기반 연구용 route/GDS 확보 |
| `modeled`, `estimated` | 모델과 명시된 가정에서 계산 |
| `illustrative` | 설명·시각화용 값 |

주의할 점:

- Sky130HD 결과는 구조의 구현 가능성을 보는 공개 공정 proxy이며 실제 HBM 제조 공정 signoff가 아닙니다.
- `overflow`가 0이 아니면 global routing은 닫히지 않은 것입니다.
- ODB 파일이 있어도 독립 reopen, legality, source hash가 확인되지 않으면 PASS가 아닙니다.
- compact thermal/cost 결과는 제조사 견적이나 실측 온도가 아닙니다.
- 오래된 Markdown 상태 문구보다 해당 실행의 machine-readable manifest가 우선합니다.

## 10. 실험을 추가할 때 지킬 규칙

1. 한 실험에서는 하나의 구조적 가설만 바꿉니다.
2. 기준 후보와 변경 후보의 RTL, netlist, SDC, floorplan 조건을 기록합니다.
3. 실행 명령, 시작·종료 시각, exit code, runtime, peak RSS를 보존합니다.
4. source와 주요 산출물의 SHA-256을 manifest에 연결합니다.
5. 기능 회귀 → 합성 → placement → route 순서의 gate를 건너뛰지 않습니다.
6. 실패한 실험도 원인과 `NOT_RUN` 단계를 명시해 보존합니다.
7. 측정값과 추정값을 같은 열이나 주장으로 섞지 않습니다.
8. 기존 canonical 산출물은 덮어쓰지 않고 새 namespace를 사용합니다.

## 11. 용어 빠른 정리

| 용어 | 의미 |
|---|---|
| PIM | 메모리 내부 또는 가까이에서 수행하는 연산 |
| HBM2 | 여러 channel·bank와 3D 적층을 사용하는 고대역폭 메모리 |
| PCU | PIM Compute Unit; 프로젝트의 연산 파이프라인 단위 |
| WBQ | Writeback Quad Slice; 16 bank를 4 quad로 지역화한 normalization 구조 |
| RTL | 실제 하드웨어 구조를 표현하는 Register Transfer Level 코드 |
| ODB | OpenROAD 설계 database checkpoint |
| SDC | clock과 timing constraint 파일 |
| legalization | 셀이 row/region 규칙을 위반하거나 겹치지 않도록 만드는 단계 |
| routing overflow | 주어진 배선 자원보다 수요가 큰 구간; 0이 아니면 배선 미완료 |
| CTS | Clock Tree Synthesis |
| PPA | Performance, Power, Area |
| PF-4 | 이 프로젝트의 global-routing/혼잡 구현 가능성 gate |
| canonical | 다음 실험의 기준으로 보존된 검증 후보 |

## 12. 지금 참여한다면 좋은 첫 작업

현재 병목은 simulator 기능이 아니라 B26-L2D 물리 구조의 region legality와 residual routing congestion입니다. 새 참여자가 바로 기여하려면 다음 순서가 적합합니다.

1. 최신 ladder report와 A5 execution manifest를 읽습니다.
2. `legal_place.log`의 `DPL-0008`/`DPL-0033`이 왜 3,615,582개 region violation으로 이어졌는지 재현 없이 분석합니다.
3. fence geometry 생성과 DPL region reconstruction의 입력·좌표·DBU 계약을 확인합니다.
4. 기존 L2D canonical을 손대지 않는 하나의 구조적 수정 가설을 제안합니다.
5. placement 재실행 전에 사전감사, candidate budget, 성공/중단 조건을 문서화합니다.

핵심은 “실행을 많이 하는 것”이 아니라 **기능적으로 동일한 후보를 비교 가능한 조건에서 검증하고, 성공과 실패 모두 재현 가능한 증거로 남기는 것**입니다.
