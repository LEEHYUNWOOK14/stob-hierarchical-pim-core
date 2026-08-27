# 혼합 정밀도 정확도 및 핵심 성능 목표 최종 보고서

## 핵심 결론

설계로 normalization의 **수치 정확도**와 **핵심 연산 성능**을 모두 개선할 수 있음을 RTL과 실제 GR00T trace로 확인했다.

- 정확도: BF16 baseline 0/6 PASS에서 C11 6/6 PASS로 개선
- C11 RTL: 1,909,248 elements에서 numerical model mismatch 0
- PyTorch BF16 대비: 37 bit mismatches, overall max abs 0.015625
- core time: C10 약 6.19µs/row에서 C11 약 4.43µs/row로 약 1.40배 개선
- end-to-end: 현재 single-row 4-lane C11은 GPU 대비 0.052x로 NO-GO

따라서 “정확도와 core 성능을 개선하는 mixed-precision datapath” 목표는 달성했지만, “GPU보다 빠른 production PIM”은 아직 달성하지 못했다. replay/DRAM write-back production 확장은 의도대로 보류한다.

## 정확도 설계 결론

정확도를 만족하는 최소 numerical contract는 다음과 같다.

```text
BF16 input
→ FP32 local/global SUM·SUMSQ
→ FP32 variance
→ BF16 LUT seed + FP32 Newton-Raphson 2회
→ FP32 affine intermediate
→ final BF16 RNE
```

다음 축소 후보는 실제 trace gate에서 실패했다.

- BF16 reduction 유지
- BF16 staged apply 유지
- Newton-Raphson 1회

여기서 정확도는 모델의 task accuracy를 새로 높이는 것이 아니라 PyTorch normalization을 하드웨어가 보존하는 numerical fidelity다.

## C11 RTL 구현

- `fp32_add_pipe4`: 20,225 vectors bit-exact, latency 3, II=1
- `fp32_mul_pipe4`: 20,225 vectors bit-exact, latency 3, II=1
- 4-way interleaved local reducer
- 4-level pipelined 16-bank global tree
- shared pipelined scalar FSM, FP32 NR2
- 12-cycle/II=1 four-lane apply
- reservation FIFO 기반 arbitrary output backpressure
- one-hot FIFO write pointer로 fanout 완화
- 16-bank C11 integration top

최종 전용 회귀는 add, mul, reducer, global, scalar, apply/backpressure가 모두 PASS했다.

## 전체 tensor 증거

| profile | elements | model mismatch | PyTorch bit mismatch | cycles |
|---|---:|---:|---:|---:|
| action_vlln | 573,440 | 0 | 5 | 49,001 |
| action_vl_self_attention_norm1 | 573,440 | 0 | 7 | 49,001 |
| action_vl_self_attention_norm3 | 573,440 | 0 | 17 | 49,001 |
| action_dit_adaln_norm1 | 62,976 | 0 | 4 | 6,520 |
| action_dit_norm3 | 62,976 | 0 | 0 | 6,520 |
| action_dit_norm_out | 62,976 | 0 | 4 | 6,520 |
| **합계** | **1,909,248** | **0** | **37** | — |

## timing 증거

Sky130 HD TT 25C 1.8V mapping 결과:

| block | C10 arrival | C11 arrival | improvement |
|---|---:|---:|---:|
| local reducer | 61.22ns | 12.83ns | 4.77x vs original C10 block |
| global reducer | 62.67ns | 15.50ns | 4.04x |
| scalar | 78.34ns | 22.54ns | 3.48x |
| apply | 61.06ns | 27.85ns | 2.19x |

C11 top의 component-bound period는 apply 27.85ns, 약 35.9MHz다. 이는 component STA이며 full placed-and-routed top timing closure는 아니다.

## 아키텍처 gate

실제 269 calls와 logical traffic을 반영한 결과:

- GPU measured: 3.121ms
- Hierarchical PIM C11: 59.534ms
- current speedup: 0.052x
- 동일 serial 구조 break-even: 약 693.3MHz

현재 성능 부족의 원인은 FP32 한 연산의 속도만이 아니라 row 직렬화다. 다음 architecture 후보 projection은 다음을 제시한다.

- 16 lanes/bank
- 8 scalar engines
- multi-row overlap
- 50MHz timing closure
- projected latency 2.768ms, projected speedup 1.127x

이는 아직 구현되지 않은 projection이며 면적·전력·routing 검증 전에는 GO가 아니다.

## 다음 권장 목표

다음 작업은 production replay/write-back이 아니라 **multi-row throughput architecture validation**이어야 한다.

1. row context table과 8 scalar engines로 reduce/scalar/apply overlap
2. bank lane 4/8/16 RTL DSE
3. FP32 multiplier 추가 stage로 50MHz closure
4. actual 6-profile cycle 재측정
5. full-top PPA와 actual traffic 재비교
6. speedup > 1일 때 production replay/write-back 진행

## 주요 보고서

- `37_mixed_precision_baseline_and_requirements.md`
- `38_mixed_precision_design_space_exploration.md`
- `39_c10_full_tensor_rtl_accuracy_report.md`
- `40_c11_timing_optimization_and_actual_trace_report.md`
- `41_c11_actual_traffic_architecture_recomparison.md`
- 본 문서 `42_mixed_precision_goal_final_report.md`
