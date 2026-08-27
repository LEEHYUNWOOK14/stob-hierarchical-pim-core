# 확정 RTL 구조 설명서

## 1. 이 폴더의 목적

이 폴더는 STOB PIM2 프로젝트에서 기능·구조 검증을 마치고 동결한 **Logic-die Normalization PCU RTL**만 따로 보존한 스냅샷이다. 실험 도중 만들어진 후보 RTL, testbench, 벡터, 합성 netlist, 로그, ODB/GDS 등은 포함하지 않는다. 이 폴더의 `rtl/` 아래에는 동결 top을 정적 elaboration하는 데 필요한 SystemVerilog 원본 17개만 있다.

동결 top module은 다음과 같다.

```text
logic_die_normalization_pcu_top
```

동결 구성의 이름은 다음과 같다.

```text
8-lane / 16-bank / split read-write / round-robin / 8 contexts / FIFO 16
```

이 스냅샷은 원본 `rtl/` 디렉터리를 대체하지 않는다. 원본 개발은 계속 기존 경로에서 수행하고, 이 폴더는 동결 시점의 구조를 비교·감사·재현하기 위한 읽기 전용 기준점으로 사용한다. 각 파일의 바이트 수와 SHA-256은 `SOURCE_MANIFEST.json`에 기록되어 있다.

## 2. 동결 상태의 의미

이 RTL이 “확정”되었다는 말은 다음 항목이 현재 연구 범위 안에서 결정되었다는 뜻이다.

- 16개 bank가 참여하는 cross-bank normalization 구조
- 첫 번째 pass에서 SUM과 SUMSQ를 수집하는 방식
- logic die에서 전역 합산과 scalar 계산을 수행하는 방식
- 두 번째 pass에서 원본 activation과 affine operand를 replay하는 방식
- 최종 결과를 bank로 직접 write-back하는 방식
- reduction read와 replay read가 하나의 read service slot을 공유하는 정책
- write-back이 read와 독립적으로 진행되는 split read/write 정책
- read 충돌 시 round-robin arbitration
- bank별 8개 BF16 lane
- scalar engine 4개
- 동시에 보존할 row context 8개
- bank-local reduction context 2개
- apply 결과 FIFO 깊이 16
- 내부 traffic counter 폭 32 bit

반대로 이 폴더는 다음을 확정하지 않는다.

- 실제 HBM PHY 전기 인터페이스
- 특정 제조사의 DRAM command/credit protocol
- DRAM cell array 또는 memory macro
- 클록 트리, 배치, 배선, GDS
- 공정별 타이밍 closure
- 실제 전력, 열, 면적 또는 silicon 측정값
- 제조 또는 tape-out 가능성

즉, 이것은 **합성 가능한 연구용 RTL microarchitecture의 기능 동결본**이지 제조 인계용 RTL package가 아니다.

## 3. 해결하려는 문제

LayerNorm과 RMSNorm은 한 원소만 보고 계산할 수 없다. 한 row 전체에 대한 통계량이 먼저 필요하다.

LayerNorm의 기본식은 다음과 같다.

```text
mean     = SUM(x) / N
variance = SUM(x*x) / N - mean*mean
inv_std  = 1 / sqrt(variance + epsilon)
y        = (x - mean) * inv_std * gamma + beta
```

RMSNorm의 기본식은 다음과 같다.

```text
mean_square = SUM(x*x) / N
inv_rms     = 1 / sqrt(mean_square + epsilon)
y           = x * inv_rms * gamma
```

데이터가 16개 bank에 분산되어 있으므로 각 bank에서 부분합을 만든 다음 logic die에서 16개 부분합을 합쳐야 한다. 통계량이 나온 뒤에는 같은 activation을 다시 읽어 normalization과 affine 연산을 적용해야 한다. 이 때문에 동결 구조는 본질적으로 다음의 **2-pass 구조**다.

1. reduction pass: 각 bank의 activation을 읽어 local SUM/SUMSQ 생성
2. scalar phase: 16개 bank의 partial SUM/SUMSQ를 전역 합산하고 mean/inv-std 또는 inv-RMS 계산
3. replay pass: activation, gamma, beta를 다시 읽어 원소별 normalization 적용
4. write-back: 결과를 원래 bank 방향으로 반환

## 4. 전체 계층 구조

```text
logic_die_normalization_pcu_top
├─ normalization_bank_scheduler
│  ├─ reduction/replay read arbitration
│  ├─ independent write-back path
│  ├─ 16-bank lockstep enforcement
│  └─ grant/conflict/skew/protocol counters
└─ mixed_precision_multirow_datapath
   ├─ mixed_precision_row_context_table          × 1
   ├─ mixed_precision_bank_reducer_pingpong      × 16 banks
   │  ├─ bf16_to_fp32                             × lanes
   │  ├─ fp32_mul                                 × lanes
   │  └─ fp32_add_pipe4 reduction/accumulation tree
   ├─ mixed_precision_global_reducer16_pipe      × 1
   │  └─ four-level balanced FP32 adder tree
   ├─ mixed_precision_scalar_engine_array        × 1
   │  └─ mixed_precision_scalar_nr2_pipe          × 4 engines
   │     ├─ fp32_add_pipe4                        × 1
   │     ├─ fp32_mul_pipe4                        × 1
   │     ├─ bf16_rsqrt_lut256                     × 1
   │     ├─ bf16_to_fp32 / fp32_to_bf16_rne
   │     └─ two Newton-Raphson refinement iterations
   └─ mixed_precision_bank_apply_pipe            × 16 banks
      ├─ BF16 → FP32 conversion per lane
      ├─ subtract mean
      ├─ multiply inverse standard deviation
      ├─ multiply gamma
      ├─ add beta for LayerNorm only
      ├─ FP32 → BF16 round-to-nearest-even
      └─ 16-entry output FIFO per bank
```

## 5. 확정 기본 파라미터

| 파라미터 | 기본값 | 의미 | 선택 이유 |
|---|---:|---|---|
| `BANKS` | 16 | 동시에 참여하는 bank 수 | 현재 global reducer가 16-bank balanced tree로 고정됨 |
| `LANES` | 8 | bank마다 한 cycle에 처리하는 BF16 원소 수 | 256-bit bank word의 절반인 128 bit/cycle 공급률을 만족하는 최소 비용점 |
| `SCALAR_ENGINES` | 4 | mean/variance/rsqrt scalar engine 수 | 현재 reducer 공급률과 workload에서 검증된 기본점 |
| `CONTEXTS` | 8 | top-level 동시 row context 수 | 16보다 상태와 fan-in이 작고 실제 trace cycle도 개선됨 |
| `LOCAL_REDUCE_CONTEXTS` | 2 | bank reducer의 ping-pong context 수 | 4로 늘려도 대표 RMS workload에서 cycle 이득이 없었음 |
| `APPLY_FIFO_DEPTH` | 16 | bank별 apply 결과 FIFO entry 수 | 8은 41×1536 trace에서 약 2.8% 성능 저하 |
| `TAG_WIDTH` | 16 | row/job tag 폭 | wrap-around와 full-context 회귀 검증 완료 |
| `COUNT_WIDTH` | 16 | bank별 vector 개수 폭 | 현재 workload row 길이 표현에 사용 |
| `COMMAND_BYTES` | 32 | invocation control traffic accounting 단위 | 외부 control byte counter 계산용 |
| `TRAFFIC_COUNTER_WIDTH` | 32 | 내부 byte counter 폭 | 64 bit 대비 192 state bit 절감, 현재 workload 범위 수용 |
| `STARVE_LIMIT` | 16 | shared-port 실험 mode의 starvation 제한 | 보수적 single-port 비교를 위한 age limit |
| `SHARED_RW_PORT` | 0 | 0이면 split R/W, 1이면 single shared port | 최종 정책은 split read/write |

`LANES=4`와 `LANES=16`도 일부 module에서 parameter 검증용으로 허용하지만 확정 구성은 8이다. 4-lane은 bank 공급률 하한 50%를 만족하지 못하고, 16-lane은 처리량 이득보다 구조 비용 증가가 커 최종값에서 제외되었다.

## 6. top-level interface 그룹

### 6.1 clock, reset, counter 제어

| 신호 | 방향 | 설명 |
|---|---|---|
| `clk_i` | input | 모든 순차 상태의 기준 clock |
| `rst_ni` | input | active-low asynchronous reset |
| `counter_clear_i` | input | traffic와 scheduler 관측 counter를 0으로 초기화 |

Reset은 context valid, pointer, pipeline valid, counter와 오류 상태를 초기화한다. 정상 동작 중인 transaction 도중 reset을 넣고 다시 작업할 수 있는지 회귀로 검증했다.

### 6.2 invocation 인터페이스

`invocation_valid_i/invocation_ready_o`는 외부에서 들어오는 큰 호출 단위의 control traffic을 계수하기 위한 경계다. 현재 wrapper는 항상 ready를 반환하며, handshake마다 `COMMAND_BYTES`를 외부 control byte counter에 더한다. 여러 row job은 하나의 invocation 아래에서 logic-die-local scheduler가 생성할 수 있다.

### 6.3 row job 인터페이스

| 신호 | 설명 |
|---|---|
| `job_valid_i/job_ready_o` | 새로운 row context를 할당하는 ready/valid handshake |
| `job_rms_norm_i` | 1이면 RMSNorm, 0이면 LayerNorm |
| `job_tag_i` | reduction, scalar, replay, write-back을 연결하는 row 식별자 |
| `job_vectors_per_bank_i` | 각 bank가 reduction pass에서 제공할 vector 수 |
| `job_inv_hidden_i` | `1/N`의 FP32 bit pattern |
| `job_epsilon_i` | 수치 안정화를 위한 epsilon의 FP32 bit pattern |
| `job_bank_mask_i` | 참여 bank mask |

현재 구현은 sparse bank mask를 받는 모양을 유지하지만 실제 global reducer는 16개 partial을 모두 요구한다. 따라서 `job_bank_mask_i`는 현재 반드시 all-one이어야 하며, 그렇지 않으면 job을 받지 않고 protocol error를 기록한다.

### 6.4 reduction pass 인터페이스

각 bank는 `reduction_valid_i[b]`와 `reduction_data_i[b]`를 제공한다. 각 data beat에는 `LANES`개의 BF16 activation이 있다. scheduler는 16개 bank가 모두 valid이고 downstream bank reducer 16개가 모두 ready인 경우에만 16개 bank 전체를 같은 cycle에 accept한다.

부분 bank만 valid인 상태에서 일부 데이터만 먼저 소비하지 않는다. 이것이 lockstep 규칙이다. 이 규칙은 bank skew가 있을 때 row 정렬이 깨지는 것을 방지한다.

### 6.5 replay request 인터페이스

scalar 결과가 준비되면 top wrapper는 해당 tag의 저장된 context를 찾아 다음 정보를 `replay_request_*`로 보낸다.

- replay할 row tag
- bank별 vector 수
- bank mask

`replay_request_valid_o`는 controller가 `replay_request_ready_i`를 올릴 때까지 유지된다. 따라서 backpressure 중에도 replay 명령이 사라지지 않는다. 동시에 하나의 replay request만 pending register에 유지되므로, 기존 request가 남은 상태에서 다른 scalar completion이 오면 protocol error다.

### 6.6 replay data 인터페이스

두 번째 pass에서는 bank별로 다음 값이 들어온다.

- `replay_x_i`: 원래 activation
- `replay_gamma_i`: affine scale
- `replay_beta_i`: affine bias
- `replay_tag_i`: row tag
- `replay_last_i`: 해당 bank의 마지막 vector 표시

reduction read와 replay read는 같은 read service slot을 공유한다. 둘 다 동시에 완전한 16-bank transaction으로 준비된 경우 round-robin bit가 선택권을 번갈아 준다.

### 6.7 write-back 인터페이스

`writeback_*`는 apply pipeline의 최종 BF16 결과를 bank로 돌려보내는 bank별 ready/valid interface다. split R/W 기본 mode에서는 write-back이 read slot을 차지하지 않으므로 reduction 또는 replay read와 같은 cycle에 진행할 수 있다.

각 bank의 `writeback_last_o` handshake가 발생하면 top context의 해당 bank completion bit가 설정된다. context의 bank completion mask가 job mask와 같아지는 순간 그 context를 해제한다. 따라서 scalar 계산이 끝났다고 context를 즉시 버리지 않고 **마지막 bank write-back까지** 수명을 유지한다.

## 7. 작업 한 건의 정확한 수명주기

### 단계 1: context 할당

1. 외부/local scheduler가 `job_valid_i`와 descriptor를 제시한다.
2. top wrapper는 빈 context가 있고 core가 begin을 받을 수 있으며 bank mask가 16-bank full mask인지 확인한다.
3. handshake가 발생하면 tag, vector count, bank mask와 completion mask를 저장한다.
4. 내부 row context table에는 mode, `inv_hidden`, epsilon을 저장한다.

Top wrapper context와 datapath 내부 scalar context는 목적과 해제 시점이 다르다. 내부 scalar context는 global reduction 결과가 scalar engine으로 넘어갈 때 소비될 수 있지만, top wrapper context는 replay 명령 정보와 bank별 최종 completion을 위해 write-back 종료까지 유지된다. 이 때문에 두 table을 하나로 합치지 않았다.

### 단계 2: bank-local reduction

각 bank의 `mixed_precision_bank_reducer_pingpong`은 입력 BF16을 FP32로 확장하고 다음 두 값을 병렬로 만든다.

```text
vector_sum   = Σ x_lane
vector_sumsq = Σ (x_lane × x_lane)
```

lane tree 결과는 context별 네 accumulation slot에 분산된다. pipeline latency 동안 새 vector를 받을 수 있도록 context와 slot metadata를 함께 지연시킨다. 지정된 vector 수를 모두 처리한 뒤 네 slot을 다시 합쳐 bank별 partial SUM과 partial SUMSQ를 만든다.

`LOCAL_REDUCE_CONTEXTS=2`는 한 row의 accumulation이 pipeline에 남아 있는 동안 다음 row가 시작될 수 있도록 ping-pong context를 제공한다.

### 단계 3: 16-bank global reduction

16개 bank partial이 모두 유효해지면 `mixed_precision_global_reducer16_pipe`가 각각 SUM과 SUMSQ에 대해 4-level balanced FP32 adder tree를 수행한다.

```text
16 inputs → 8 → 4 → 2 → 1 global value
```

이 block은 한 row를 in-flight로 유지하며, downstream이 막히면 output register에 결과와 tag를 안정적으로 보존한다.

### 단계 4: scalar 계산

global SUM/SUMSQ와 context의 `inv_hidden`, epsilon, mode가 scalar engine array로 전달된다. 4개 scalar engine은 request와 response 모두 round-robin으로 중재된다.

LayerNorm은 다음 순서로 계산한다.

1. `mean = sum × inv_hidden`
2. `mean_square = sumsq × inv_hidden`
3. `mean2 = mean × mean`
4. `variance = mean_square - mean2`
5. 음의 비정상 variance를 0으로 clamp
6. `argument = variance + epsilon`
7. BF16 LUT로 reciprocal-square-root 초기값 생성
8. Newton-Raphson 식 `y = y × (1.5 - 0.5 × x × y × y)`를 두 번 수행

RMSNorm은 mean과 `mean²` 계산을 건너뛰고 `sumsq × inv_hidden`을 직접 normalization argument로 사용한다. 응답에서 RMSNorm의 mean은 0이다.

scalar engine은 한 개의 pipelined FP32 adder와 한 개의 pipelined FP32 multiplier를 state machine으로 재사용한다. response register는 1-entry buffer이며, request ready가 response ready에 조합적으로 의존하지 않도록 설계되어 engine-array arbiter를 통한 combinational loop를 차단한다.

### 단계 5: apply configuration과 replay 요청

scalar response가 나오면 16개 bank apply pipeline에 동일한 tag, mode, mean, inverse standard deviation을 broadcast한다. 동시에 top wrapper는 저장된 context로부터 replay request를 만든다.

각 apply pipeline은 현재 tag 하나의 scalar configuration을 active 상태로 보관한다. config가 없는 vector 또는 tag가 다른 vector가 들어오면 context error를 기록한다.

### 단계 6: 원소별 apply pipeline

각 lane은 BF16 입력을 FP32로 확장한 뒤 다음 pipeline을 지난다.

LayerNorm:

```text
centered   = x - mean
normalized = centered × inv_std
scaled     = normalized × gamma
shifted    = scaled + beta
result     = BF16_RNE(shifted)
```

RMSNorm:

```text
centered   = x              // mean을 0으로 설정
normalized = x × inv_rms
scaled     = normalized × gamma
shifted    = scaled         // beta 대신 0을 더함
result     = BF16_RNE(shifted)
```

pipeline latency는 12 cycle이고 initiation interval은 1이다. metadata pipeline이 data와 함께 tag, last, mode, inverse value, gamma, beta를 정렬한다. 출력 FIFO는 pipeline 내부에 이미 들어온 결과까지 고려하기 위해 `fifo_count + inflight < FIFO_DEPTH`일 때만 새 vector를 받는다.

### 단계 7: write-back과 context 해제

각 bank 결과는 독립적으로 backpressure를 받을 수 있다. 결과가 ready가 될 때까지 data, tag, last는 유지된다. bank별 마지막 beat의 handshake를 모두 확인한 후 top context를 해제한다. 일부 bank만 끝났다면 completion bit만 누적하고 context는 유지한다.

## 8. bank scheduler 정책

### 8.1 기본 split read/write mode

기본값 `SHARED_RW_PORT=0`에서는 다음 자원 모델을 사용한다.

```text
read slot:  reduction 또는 replay 중 하나
write path: write-back 전용, read와 동시 진행 가능
```

reduction과 replay가 동시에 eligible이면 `read_rr_q`에 따라 하나를 고른다. 선택이 이루어질 때마다 round-robin 방향을 갱신하므로 양쪽이 계속 요청해도 한쪽이 영구적으로 굶지 않는다. stress regression에서 두 read class의 최대 대기는 각각 1 cycle이었다.

### 8.2 비교용 single shared mode

`SHARED_RW_PORT=1`은 reduction, replay, write-back이 하나의 port를 공유한다고 가정하는 보수적 비교 mode다. write-back을 우선하되 각 request class의 age counter가 `STARVE_LIMIT`에 도달하면 장기 대기를 방지한다. 이 mode는 DSE와 보수적 비교를 위해 남아 있지만 확정 production policy가 아니다.

### 8.3 lockstep 조건

각 transaction class는 16개 bank 모두 valid이고, 대응하는 16개 sink 모두 ready일 때만 eligible이다. 일부 bank만 valid인 상태는 `bank_skew_cycles_o`에 계수하며 어떤 bank도 ready handshake를 받지 않는다.

### 8.4 scheduler 관측값

| counter | 의미 |
|---|---|
| `scheduler_reduction_grants_o` | 실제로 발행한 reduction transaction 수 |
| `scheduler_replay_grants_o` | 실제로 발행한 replay transaction 수 |
| `scheduler_writeback_grants_o` | 실제로 발행한 write-back transaction 수 |
| `scheduler_read_conflict_cycles_o` | reduction과 replay가 동시에 read slot을 요구한 cycle 수 |
| `scheduler_bank_skew_cycles_o` | 일부 bank만 valid/ready여서 lockstep issue가 불가능했던 cycle 수 |

## 9. ready/valid 불변조건

이 RTL을 수정하거나 다른 controller에 연결할 때 다음 규칙을 깨면 안 된다.

1. 상태 변경은 `valid && ready` handshake에서만 일어나야 한다.
2. output valid가 1이고 ready가 0이면 data, tag, last와 mode는 그대로 유지되어야 한다.
3. 16-bank lockstep transaction에서 일부 bank만 소비하면 안 된다.
4. tag는 reduction 시작부터 최종 write-back까지 동일 row를 식별해야 한다.
5. 같은 tag를 context에 중복 할당하면 안 된다.
6. context lookup miss를 조용히 무시하면 안 된다.
7. replay request는 backpressure 중 pulse로 사라지면 안 된다.
8. output FIFO capacity 계산에는 FIFO에 저장된 entry뿐 아니라 pipeline in-flight 결과도 포함해야 한다.
9. reset 후 과거 valid/context/pending request가 다시 나타나면 안 된다.
10. split mode에서 write-back이 reduction/replay read slot을 불필요하게 막으면 안 된다.

## 10. 수치 표현과 정밀도

- bank 입출력 activation, gamma, beta, write-back result는 BF16 16 bit다.
- local reduction 전에 BF16을 FP32 bit pattern으로 확장한다.
- SUM, SUMSQ, mean, variance, inverse standard deviation과 apply 중간값은 FP32다.
- reciprocal-square-root seed를 구할 때 argument를 BF16 round-to-nearest-even으로 줄여 256-entry LUT를 조회한다.
- LUT seed를 FP32로 확장한 후 Newton-Raphson refinement를 두 번 수행한다.
- 최종 결과는 FP32에서 BF16 round-to-nearest-even으로 줄인다.
- NaN, infinity, zero, denormal과 rounding behavior는 프로젝트의 bit-level FP arithmetic 구현에 의해 결정된다.

이 구조는 BF16 I/O와 FP32 accumulation/scalar/apply의 mixed-precision 정책이다. 실제 vendor floating-point IP나 IEEE exception flag interface를 사용하지 않는다.

## 11. traffic 집계

Top wrapper는 구조 비교를 위해 다음 byte 수를 내부 32-bit counter로 누적하고 외부에는 64-bit zero-extension으로 제공한다.

| 출력 | 증가 조건 |
|---|---|
| `bank_activation_read_bytes_o` | reduction 또는 replay data handshake 수 × `LANES×2` byte |
| `bank_affine_read_bytes_o` | replay handshake 수 × `LANES×4` byte; gamma와 beta 합계 |
| `bank_writeback_bytes_o` | write-back handshake 수 × `LANES×2` byte |
| `bank_to_logic_partial_bytes_o` | scalar configuration마다 참여 bank 수 × 8 byte; SUM/SUMSQ |
| `logic_to_bank_scalar_bytes_o` | scalar configuration마다 참여 bank 수 × 8 byte; mean/inv value |
| `external_control_bytes_o` | invocation handshake 수 × `COMMAND_BYTES` |

이 값은 transaction 기반 정확한 byte accounting이지만 전력 측정값은 아니다. memory hierarchy energy를 얻으려면 별도 energy-per-access 모델 또는 측정값이 필요하다.

## 12. 오류 검출

`protocol_error_o`는 core, wrapper, scheduler 오류의 OR 결과다. 대표 오류 조건은 다음과 같다.

- 16개 bank 전체가 아닌 job mask
- scalar completion tag에 대응하는 top context가 없음
- 이전 replay request가 pending인데 새로운 scalar completion 발생
- bank reducer가 ready가 아닌 상태에서 vector valid를 강제로 제시
- row context duplicate tag allocation
- 존재하지 않는 tag lookup
- apply configuration이 없거나 tag가 다른 replay vector
- partial bank valid에 의한 skew 상황

일부 하위 오류는 sticky이고 일부 wrapper 오류는 pulse 성격이므로, system integration에서는 `protocol_error_o`를 관측·기록하는 logic이 필요하다.

## 13. 파일별 역할

### Integration과 제어

- `rtl/logic_die_normalization_pcu_top.sv`: 외부 integration boundary, top context lifetime, replay request, traffic counter, scheduler/datapath 연결
- `rtl/normalization_bank_scheduler.sv`: reduction/replay read arbitration, write-back path, lockstep issue, skew/conflict/grant counter
- `rtl/mixed_precision_multirow_datapath.sv`: 16 bank reducer, global reducer, scalar engines, apply pipelines와 context table을 연결하는 arithmetic core
- `rtl/mixed_precision_row_context_table.sv`: tag별 mode, inverse hidden size, epsilon 저장과 duplicate/miss 검출

### Reduction

- `rtl/mixed_precision_bank_reducer_pingpong.sv`: bank-local BF16 vector SUM/SUMSQ, 두 local context, pipeline accumulation slot
- `rtl/mixed_precision_global_reducer16_pipe.sv`: 16 bank partial을 합치는 4-level FP32 balanced tree

### Scalar와 reciprocal square root

- `rtl/mixed_precision_scalar_engine_array.sv`: 4/8/16 scalar engine request/response round-robin array
- `rtl/mixed_precision_scalar_nr2_pipe.sv`: LayerNorm/RMSNorm scalar state machine, shared add/multiply pipeline, Newton refinement 2회
- `rtl/bf16_rsqrt_lut256.sv`: BF16 reciprocal-square-root seed lookup handshake wrapper
- `rtl/bf16_rsqrt_lut256_case.svh`: 256-entry seed table include 파일

### Apply와 arithmetic primitive

- `rtl/mixed_precision_bank_apply_pipe.sv`: bank별 12-cycle apply pipeline과 16-entry 결과 FIFO
- `rtl/bf16_to_fp32.sv`: BF16을 FP32 encoding으로 확장
- `rtl/fp32_to_bf16_rne.sv`: FP32를 BF16 round-to-nearest-even으로 축소
- `rtl/fp32_add.sv`: 조합 FP32 adder
- `rtl/fp32_mul.sv`: 조합 FP32 multiplier
- `rtl/fp32_add_pipe4.sv`: timing split FP32 adder pipeline
- `rtl/fp32_mul_pipe4.sv`: timing split FP32 multiplier pipeline

## 14. 복사본에 포함하지 않은 것

다음은 의도적으로 이 폴더에 넣지 않았다.

- testbench와 golden vector: RTL 구조가 아니라 검증 자산이므로 원본 `verification/groot_normalization/`에 유지
- synthesis/STA/placement/route output: RTL source가 아닌 파생 산출물
- `logic_die_normalization_hbm_top.sv`와 HBM boundary adapter: RTL freeze 이후 physical feasibility를 위해 추가한 외부 adapter이며 이 PCU 구조 동결 범위 밖
- `full_pim_system_top.sv`: bank-side PIM과 전체 system을 포함하는 더 큰 top이며 이 freeze의 top이 아님
- 4/16-lane, C11, interleaved 등 실험 후보: 선택 근거에는 사용됐지만 최종 source closure에 필요하지 않은 별도 후보
- `.v`, `.json`, `.csv`, `.hex`, `.log`, `.odb`, `.gds`: 생성물 또는 evidence이며 source RTL이 아님

## 15. 검증 근거

동결 판단 시 다음 gate를 통과했다.

| 검증 | 결과 |
|---|---|
| LayerNorm numerical accuracy | PASS |
| RMSNorm width 128/2048 accuracy | PASS |
| AdaLayerNorm-style per-row affine | PASS |
| 4/8-lane regression | PASS |
| random backpressure | PASS |
| bank skew/conflict와 partial issue 차단 | PASS |
| context full과 tag `fffe→ffff→0000→0001` wrap | PASS |
| transaction 도중 reset과 recovery | PASS |
| transaction-level cycle model 대비 RTL 오차 | 최대 ±3% 이내 |
| traffic counter exact assertion | PASS |
| Verilator lint | PASS, 검토된 warning만 존재, `UNOPTFLAT=0` |
| Yosys generic structural check | 0 problems |

동결 8-lane hierarchy는 generic synthesis에서 16 bank reducer, 16 apply pipe, 4 scalar engine, 1 global reducer, 1 scheduler를 포함해 200,010 generic cell로 elaboration됐다. 이 값은 공정 면적이나 최종 PPA가 아니라 구조 복잡도와 synthesis closure를 확인하는 공정 독립 proxy다.

원본 evidence 위치:

```text
reports/groot_normalization/rtl_freeze/01_final_rtl_freeze_report.md
reports/groot_normalization/rtl_freeze/freeze_status.json
reports/groot_normalization/rtl_freeze/freeze_regression.log
reports/groot_normalization/rtl_freeze/yosys_generic_synthesis.log
reports/groot_normalization/results/logic_die_pcu_system_scheduler/system_decision.json
```

## 16. 이 스냅샷 자체를 elaboration하는 방법

아래 명령은 이 폴더를 현재 디렉터리로 두고 실행한다. `bf16_rsqrt_lut256.sv`가 `rtl/bf16_rsqrt_lut256_case.svh`를 include하므로 반드시 스냅샷 root에서 실행해야 한다.

```bash
cd frozen_rtl/logic_die_normalization_pcu_8lane_split_rw

SRC="rtl/bf16_to_fp32.sv \
rtl/fp32_to_bf16_rne.sv \
rtl/fp32_add.sv rtl/fp32_mul.sv \
rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv \
rtl/bf16_rsqrt_lut256.sv \
rtl/mixed_precision_bank_reducer_pingpong.sv \
rtl/mixed_precision_global_reducer16_pipe.sv \
rtl/mixed_precision_scalar_nr2_pipe.sv \
rtl/mixed_precision_scalar_engine_array.sv \
rtl/mixed_precision_bank_apply_pipe.sv \
rtl/mixed_precision_row_context_table.sv \
rtl/mixed_precision_multirow_datapath.sv \
rtl/normalization_bank_scheduler.sv \
rtl/logic_die_normalization_pcu_top.sv"

verilator --lint-only -Wall -Wno-fatal \
  --top-module logic_die_normalization_pcu_top $SRC

yosys -p "read_verilog -sv $SRC; \
  hierarchy -top logic_die_normalization_pcu_top; \
  proc; opt; check; stat"
```

전체 기능 회귀는 testbench를 중복 복사하지 않고 원본 저장소에서 수행한다.

```bash
bash verification/groot_normalization/run_logic_die_pcu_freeze_regression.sh
```

## 17. 수정 및 버전 관리 규칙

이 폴더의 RTL은 동결 증거이므로 직접 수정하지 않는 것을 원칙으로 한다. 구조를 변경해야 하면 다음 절차를 따른다.

1. 원본 `rtl/`에서 변경한다.
2. 전체 freeze regression을 다시 실행한다.
3. 성능·정확도·backpressure·reset·lint·synthesis 결과를 비교한다.
4. 기존 동결본을 덮어쓰지 않고 새 이름의 snapshot 폴더를 만든다.
5. 새 `SOURCE_MANIFEST.json`에 source path, hash, parameter와 근거 보고서를 기록한다.
6. 변경 이유와 이전 동결본과의 차이를 README에 기록한다.

이 규칙을 지키면 논문에 사용한 RTL, 물리 구현에 투입한 RTL, 이후 수정된 RTL을 서로 혼동하지 않을 수 있다.

## 18. 핵심 요약

이 RTL은 16개 bank에 분산된 activation을 대상으로 다음 작업을 수행하는 logic-die PCU다.

```text
16-bank BF16 activation
  → bank-local FP32 SUM/SUMSQ
  → global FP32 SUM/SUMSQ
  → 4-engine mean/variance/rsqrt
  → activation/gamma/beta replay
  → 8-lane mixed-precision apply
  → bank별 BF16 write-back
```

최종 설계 선택의 핵심은 다음 세 가지다.

1. **8 lanes:** 필요한 bank 공급률을 만족하는 최소 비용점
2. **split R/W:** read arbitration은 현실적으로 공유하되 write-back은 read와 병렬화
3. **bounded contexts/FIFO:** 무한 buffer를 가정하지 않고 backpressure와 row overlap을 유한 상태로 구현

따라서 이 폴더는 “normalization이 가능하다”는 알고리즘 설명이 아니라, tag 보존, lockstep bank issue, replay, backpressure, context lifetime과 write-back completion까지 포함한 구체적인 합성 가능 RTL 구조의 동결본이다.
