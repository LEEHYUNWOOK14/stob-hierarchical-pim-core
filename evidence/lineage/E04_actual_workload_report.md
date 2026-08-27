# 1단계 실제 GR00T 정규화 workload 보고서

작성일: 2026-08-11

## 판정

`PARTIAL PASS — pinned official source/checkpoint 기반 workload manifest 완료, pretrained runtime profiling 미완료`

Phase 2 진입 조건인 실제 GR00T normalization invocation 식별은 충족했다. 다만 현재 PC에서는 pretrained GR00T 전체 inference를 아직 실행하지 않았으므로 dynamic token 수와 실제 invocation timeline은 측정값이 아니다.

## 대상과 증거

- 모델: `nvidia/GR00T-N1.7-3B`
- checkpoint revision: `2fc962b973bccdd5d8ce4f67cc63b264d6886495`
- Isaac-GR00T revision: `b9955401d50c92a29258732e3ad6ccd579f1bdc0`
- checkpoint config dtype: BF16
- checkpoint payload: 6,910,361,856 bytes, 1,031 weights, 2 safetensors shards
- 로컬 공식 source: `../STOB_PIM_pure_layornorm/references/Isaac-GR00T`
- 공식 checkpoint config 및 safetensors header를 payload 다운로드 없이 직접 감사

공식 NVIDIA 문서는 N1.7-3B inference에 16GB 이상 GPU VRAM을 요구한다. 현재 데스크톱은 RTX 4060 8GB이며 Windows/WSL Python에 PyTorch가 설치되어 있지 않았다. 따라서 이 단계에서 runtime 수치를 만들어내지 않고 static/checkpoint evidence로 분류했다.

## 확인된 구조

| 영역 | 확인 결과 | 근거 등급 |
|---|---:|---|
| language layers | 16 | checkpoint weight index |
| language hidden width | 2,048 | safetensors shape |
| query heads × width | 16 × 128 | q_proj 및 q_norm shape |
| key/value heads × width | 8 × 128 | k_proj 및 k_norm shape |
| vision blocks | 24 | checkpoint weight index |
| vision norm width | 1,024 | safetensors shape |
| DiT layers | 32 | checkpoint config |
| DiT hidden width | 1,536 | 32 heads × 48 |
| action rows, batch 1 | 41 | state token 1 + action horizon 40 |
| denoising steps | 4 | checkpoint config |
| VL self-attention layers | 4 | checkpoint config |

## 기존 manifest에서 발견한 중요 수정점

기존 provisional manifest는 Q/K RMSNorm을 `[8960,64]`로 묶었다. 실제 checkpoint shape는 다음과 같다.

- Q norm width: 128, query heads: 16
- K norm width: 128, key/value heads: 8
- legacy sequence length 280을 가정한 대표 row 수: Q 4,480, K 2,240

따라서 기존 `[8960,64]` profile은 현재 pinned N1.7 checkpoint와 일치하지 않는다. 새 manifest에서는 Q와 K를 분리했으며 token 수 280은 runtime 측정이 아닌 legacy representative로 표시했다.

## 호출 수 식

batch 1, action horizon 40, denoising step 4 기준으로 확정 가능한 action-head 호출은 다음과 같다.

| Profile | Shape | Calls/policy |
|---|---|---:|
| DiT AdaLayerNorm | `[41,1536]` | 128 |
| DiT norm3 LayerNorm | `[41,1536]` | 128 |
| DiT norm_out LayerNorm | `[41,1536]` | 4 |

Backbone 및 VL token normalization은 sequence/image token 수가 입력에 따라 달라진다. module count는 checkpoint에서 확인했지만 row 수는 runtime hook으로 확정해야 한다.

새 manifest는 13개 profile을 포함하며 vision block LayerNorm과 language final RMSNorm도 기존 7-profile manifest에 추가했다. weight index에서 확인한 module 수를 단순 합산한 static count는 382이지만, 조건부 vision merger normalization과 실제 runtime execution 여부가 남아 있으므로 실제 총 호출 횟수로 주장하지 않는다.

## 산출물

- `tools/audit_actual_groot_normalization.py`
- `reports/groot_normalization/results/groot_actual_workload_manifest.csv`
- `reports/groot_normalization/results/groot_actual_workload_manifest.json`
- `reports/groot_normalization/results/actual_groot/checkpoint_config.json`

재현 명령:

```powershell
python tools/audit_actual_groot_normalization.py
```

확인 결과:

```text
ACTUAL_GROOT_NORMALIZATION_AUDIT PASS profiles=13 language_layers=16 vision_blocks=24 dit_layers=32 steps=4 runtime=NOT_CAPTURED
```

## 남은 항목

- 실제 image/language 입력의 sequence length
- vision token 수와 merger/deepstack norm 실행 횟수
- runtime module별 epsilon introspection
- 실제 hook 기반 invocation 순서와 call count
- pretrained BF16 activation
- GPU latency와 traffic

다음 단계에서는 capture hook과 실행 환경을 준비하고, 전체 모델 실행이 하드웨어 한계로 불가능하면 action-head pretrained weight 또는 명시적 fallback trace와 실제 trace를 엄격히 분리한다.
