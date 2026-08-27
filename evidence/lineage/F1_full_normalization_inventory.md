# GR00T 전체 정규화 workload inventory 보고서

작성일: 2026-08-12  
대상 모델: `nvidia/GR00T-N1.7-3B`  
모델 revision: `2fc962b973bccdd5d8ce4f67cc63b264d6886495`  
Isaac-GR00T revision: `b9955401d50c92a29258732e3ad6ccd579f1bdc0`

## 1. 왜 이 작업을 수행했는가

기존 PCU 선택은 pretrained action-head에서 capture한 6개 normalization profile을 기준으로 했다. 이 범위에서는 8-lane 구조가 4-lane 대비 cycle을 36.3% 줄이고, 16-lane의 추가 이득은 8.3%에 그쳐 8-lane을 기본 후보로 선정했다.

하지만 GR00T 전체에는 action-head 외에 다음 연산이 존재한다.

- language backbone의 2048-wide RMSNorm
- attention Q/K의 128-wide RMSNorm
- vision backbone의 1024-wide LayerNorm

특히 128-wide RMSNorm은 1536/2048-wide action-head LayerNorm보다 lane 활용률과 scalar 병목 비율이 다르다. 따라서 action-head 결과만으로 “GR00T 전체 normalization에도 8-lane이 균형점”이라고 주장하면 workload 대표성이 부족하다.

이번 작업의 목적은 전체 모델을 하드웨어에서 실행하는 것이 아니라 다음 질문에 답하는 것이다.

> GR00T에 존재하는 모든 normalization 계열의 종류, width, row 수, 호출 수, dtype, affine 조건을 한 번 목록화하고, 미확정 값까지 명시했을 때 기존 8-lane 선택이 구조적으로 유지되는가?

이 확인이 필요한 이유는 arithmetic RTL을 다시 검증하기 위해서가 아니라, **lane 수와 hardware cost 결론이 action-head workload에 과도하게 편향되지 않았는지 확인하기 위해서**다.

## 2. “전체 정규화 workload inventory 확인”의 구체 작업

이번 inventory는 다음 7단계로 수행했다.

1. pinned GR00T checkpoint config, weight index 및 safetensors header에서 layer 수와 normalization width를 확인한다.
2. pinned Isaac-GR00T source revision이 기대 revision과 일치하는지 확인한다.
3. source의 action-head, DiT, backbone construction/call path 파일을 hash로 고정한다.
4. normalization module을 subsystem별 profile family로 묶고 종류·width·호출 수를 기록한다.
5. 기존 pretrained action-head hook trace에서 실제 shape, dtype, epsilon, affine 여부와 호출 수를 다시 읽는다.
6. static 정보와 runtime trace가 충돌하면 runtime trace를 우선하고 차이를 별도 기록한다.
7. runtime row 수가 없는 vision normalization은 256/1024/4096-row 시나리오로 분리하여 4/8/16-lane 민감도를 계산한다.

이 과정에서 GR00T 전체 inference는 수행하지 않았다. Inventory에 필요한 것은 모든 profile family와 multiplicity, normalization dimension 및 workload weighting이기 때문이다. 전체 activation replay는 arithmetic 정확도 검증의 별도 단계이며 action-head에 대해서는 이미 RTL 검증이 완료돼 있다.

## 3. 사용한 증거와 등급

| 증거 | 사용 목적 | 등급 |
|---|---|---|
| pinned checkpoint audit manifest | language/vision layer 수, hidden width, head 수, 전체 profile 후보 | CHECKPOINT/CODE DERIVED |
| local Isaac-GR00T checkout | action-head 및 DiT normalization construction/call path | PINNED SOURCE RECHECKED |
| source SHA-256 4개 | 사용한 코드 상태 고정 | HASHED LOCAL EVIDENCE |
| pretrained action-head hook trace | 6개 profile의 shape, dtype, epsilon, affine, 호출 수 | MEASURED RUNTIME |
| 기존 4/8/16-lane PCU top RTL trace | action-head weighted RTL cycle | MEASURED RTL |
| bank/replay/write-back cycle model | 미capture backbone profile의 lane 민감도 | MODELED |
| vision row 256/1024/4096 | runtime-dependent vision token 수에 대한 민감도 | EXPLICIT SCENARIO |

원격 checkpoint header를 이번 실행에서 다시 읽으려는 명령은 네트워크 응답 지연으로 120초 제한을 초과했다. 이 때문에 기존 pinned checkpoint audit manifest를 사용했다. 로컬 Isaac-GR00T source는 이번 실행에서 revision과 SHA-256을 다시 확인했다.

## 4. 전체 Inventory 결과

총 13개 normalization profile family와 policy call당 382회 호출을 확인했다.

| Subsystem | Profile | Type | Shape/width | Calls | Shape 증거 |
|---|---|---|---:|---:|---|
| Action | vlln | LayerNorm | 280 × 2048 | 1 | runtime measured |
| Action | VL attention norm1 | LayerNorm | 280 × 2048 | 4 | runtime measured |
| Action | VL attention norm3 | LayerNorm | 280 × 2048 | 4 | runtime measured |
| Action | DiT AdaLN norm1 | AdaLayerNorm | 41 × 1536 | 128 | runtime measured |
| Action | DiT norm3 | LayerNorm | 41 × 1536 | 128 | runtime measured |
| Action | DiT norm_out | LayerNorm | 41 × 1536 | 4 | runtime measured |
| Language | input RMSNorm | RMSNorm | representative 280 × 2048 | 16 | checkpoint/code + representative rows |
| Language | post-attention RMSNorm | RMSNorm | representative 280 × 2048 | 16 | checkpoint/code + representative rows |
| Language | Q RMSNorm | RMSNorm | representative 4480 × 128 | 16 | 280 tokens × 16 heads |
| Language | K RMSNorm | RMSNorm | representative 2240 × 128 | 16 | 280 tokens × 8 KV heads |
| Language | final RMSNorm | RMSNorm | representative 280 × 2048 | 1 | checkpoint/code + representative rows |
| Vision | block norm1 | LayerNorm | dynamic rows × 1024 | 24 | width/calls confirmed, rows open |
| Vision | block norm2 | LayerNorm | dynamic rows × 1024 | 24 | width/calls confirmed, rows open |

요약:

- profile family coverage: **13/13**
- static call count: **382 calls/policy call**
- runtime-confirmed action calls: **269 calls**
- runtime-confirmed profile family: **6개**
- normalization width: **128, 1024, 1536, 2048**
- normalization type: **RMSNorm, LayerNorm, AdaLayerNorm**
- vision 제외 runtime/representative weighted elements: **54,220,800**
- 아직 runtime row 수가 없는 profile: **vision norm1, vision norm2 두 개**

### 정적 정보와 runtime 차이 발견

기존 static manifest는 `action_dit_norm3`를 `elementwise_affine=true`로 분류했지만 pretrained runtime module trace는 `false`였다. 새 inventory는 runtime 값을 우선했다.

이 수정은 gamma/beta operand traffic 계산에 영향을 주지만, reduction/scalar/apply arithmetic 구조나 lane cycle 결론을 뒤집지는 않는다. 차이는 `evidence_discrepancies.csv`에 남겼다.

## 5. 4/8/16-lane 민감도

Action-head cycle은 실제 PCU top RTL 측정값을 사용했다. Backbone은 bank/replay/write-back event model의 32→64-row steady-state를 긴 row에 투영했다. 따라서 아래 결과는 measured+modeled hybrid이며 full-model runtime 측정값이 아니다.

### cycle 감소율

| Workload 범위 | 4→8 lane 감소 | 8→16 lane 감소 | Balanced knee |
|---|---:|---:|---:|
| vision 제외 11개 profile | 15.72% | 4.28% | 8 lane |
| vision 256 rows | 14.87% | 3.87% | 8 lane |
| vision 1024 rows | 12.98% | 2.96% | 8 lane |
| vision 4096 rows | 9.83% | 1.52% | 8 lane |

Hardware relative cost 변화:

- 4→8 lane: **+77.29%**
- 8→16 lane: **+87.19%**

전체 inventory를 반영하면 4→8 lane 이득은 action-head 단독의 36.3%보다 작아진다. 128-wide Q/K RMSNorm과 scalar service 비중 때문이다. 그러나 모든 시나리오에서 8→16 lane의 marginal gain은 1.5~4.3%로 더 작아지며, 16-lane 비용 증가는 87.2%다.

따라서:

- **8-lane:** throughput과 hardware cost를 함께 보는 balanced default
- **4-lane:** 명시적인 throughput floor가 없고 최소 hardware 비용이 최우선일 때의 cost-minimum 구성
- **16-lane:** 전체 normalization workload 기준으로 추가 비용을 정당화하기 어려움

## 6. 설계 방향에 미치는 영향

이번 inventory는 기존 parameterized RTL을 폐기하거나 다시 설계해야 한다는 결과를 만들지 않았다.

권고 사항은 다음과 같다.

1. RTL은 4/8/16-lane parameterization을 유지한다.
2. 기본 balanced configuration은 8-lane/4-scalar/16-context를 유지한다.
3. 시스템 throughput 요구사항이 정해지지 않은 상태에서는 4-lane cost-minimum variant도 freeze 후보로 보존한다.
4. 16-lane은 기본 후보에서 제외한다.
5. RMSNorm은 실제 backbone activation trace가 없으므로, 최종 “전체 GR00T 수치 정확도” 주장을 하려면 width 128과 2048 대표 RMSNorm trace가 추가로 필요하다.

즉, 전체 workload inventory는 8-lane 결론을 완전히 뒤집지는 않았지만, **8-lane을 유일한 최적해가 아니라 balanced default로 낮추고 4-lane을 최소 비용 대안으로 명시하게 만들었다.**

## 7. 꼭 full-model inference를 추가로 해야 하는가

현재 설계 방향을 결정하기 위해서는 필수가 아니다. 이번 inventory로 모든 normalization family, width와 호출 multiplicity를 확인했고, 남은 vision row 수에 대해서도 넓은 시나리오에서 lane 결론을 검사했다.

다만 다음 주장을 하려면 한 번의 full-model hook capture가 필요하다.

- 정확한 GR00T 전체 normalization weighted cycle
- 정확한 전체 외부 I/O 감소 byte
- 실제 vision token row 수
- backbone RMSNorm의 실제 activation 분포와 수치 정확도

따라서 현재 가능한 정확한 표현은 다음과 같다.

> 전체 GR00T normalization profile inventory와 representative/scenario weighting에서 8-lane은 balanced PCU 후보이며, 4-lane은 최소 비용 대안이다. Action-head는 실제 BF16 RTL trace로 검증됐고, backbone cycle과 vision row는 모델/시나리오 증거다.

## 8. 재현 명령과 산출물

```powershell
.\.venv\Scripts\python.exe tools\build_full_normalization_inventory.py `
  --source "C:\Users\Admin\OneDrive\2026-summer\STOB_semiconductor_pim\STOB_PIM_pure_layornorm\references\Isaac-GR00T"
```

산출물:

- `reports/groot_normalization/results/full_normalization_inventory/full_normalization_inventory.csv`
- `reports/groot_normalization/results/full_normalization_inventory/inventory_summary.json`
- `reports/groot_normalization/results/full_normalization_inventory/lane_sensitivity.csv`
- `reports/groot_normalization/results/full_normalization_inventory/source_evidence.csv`
- `reports/groot_normalization/results/full_normalization_inventory/evidence_discrepancies.csv`
