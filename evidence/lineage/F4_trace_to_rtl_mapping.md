# Phase 3 GR00T Trace-to-RTL Mapping Report

작성일: 2026-08-11

## 판정

`PASS — 6개 pretrained action-head BF16 sample을 16-bank × 4-lane packet으로 변환하고 bit-exact round trip 검증 완료`

Source trace의 증거 등급은 Phase 2와 동일하게 `PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT`이다.

## Mapping 규칙

hidden dimension의 column을 다음과 같이 mapping했다.

```text
column = vector_address × (BANKS × LANES) + bank × LANES + lane
```

- BANKS: 16
- LANES: 4
- 한 packet: BF16 4개, 64 bits
- packed hex 순서: lane3, lane2, lane1, lane0
- bank parity: bank ID bit 0
- tag: `0x1000 + profile_index × 0x400 + row`
- hidden tail: invalid lane을 zero padding

Reduction 입력과 apply replay 입력은 동일 input checksum과 mapping manifest를 사용한다. 이후 production replay 구현에서는 이 `(tag, bank, vector_address)`를 row context에 보존해야 한다.

## 변환 결과

| Profile | Rows | Hidden | Vectors/bank | Packets | Padding | Mismatch |
|---|---:|---:|---:|---:|---:|---:|
| action_vlln | 280 | 2048 | 32 | 143,360 | 0 | 0 |
| action_vl_self_attention_norm1 | 280 | 2048 | 32 | 143,360 | 0 | 0 |
| action_vl_self_attention_norm3 | 280 | 2048 | 32 | 143,360 | 0 | 0 |
| action_dit_adaln_norm1 | 41 | 1536 | 24 | 15,744 | 0 | 0 |
| action_dit_norm3 | 41 | 1536 | 24 | 15,744 | 0 | 0 |
| action_dit_norm_out | 41 | 1536 | 24 | 15,744 | 0 | 0 |
| 합계 | 963 | - | - | 477,312 | 0 | 0 |

각 profile에서 원본 BF16 input SHA-256와 mapping 역변환 SHA-256가 동일했다.

## 산출물

- 변환 도구: `tools/convert_groot_trace_to_rtl.py`
- mapping manifest: `reports/groot_normalization/results/actual_groot/rtl_mapping/mapping_manifest.json`
- 요약: `reports/groot_normalization/results/actual_groot/rtl_mapping/mapping_summary.csv`
- profile별 packet metadata: `*_bank_packets.csv`
- profile별 RTL packed input: `*_bank_packets.hex`

재현 명령:

```powershell
python tools/convert_groot_trace_to_rtl.py `
  --trace reports/groot_normalization/results/actual_groot/action_head_trace `
  --output reports/groot_normalization/results/actual_groot/rtl_mapping `
  --banks 16 --lanes 4
```

결과:

```text
GROOT_TRACE_TO_RTL PASS profiles=6 packets=477312 roundtrip_mismatches=0 banks=16 lanes=4
```

## 남은 연결 항목

- 현재 production Bank-PCU top은 packet CSV/hex를 직접 replay하지 않는다.
- BF16 full affine Bank-PCU top은 아직 FP16 Bank-PCU microprogram 경로와 분리되어 있다.
- AdaLayerNorm은 LayerNorm 이후 timestep-dependent scale/shift가 있으므로 inner LayerNorm과 dynamic modulation을 별도 단계로 검증해야 한다.
- 실제 DRAM address와 burst mapping은 아직 없으며 현재 vector address는 logical replay address다.

Phase 4에서는 저장된 PyTorch output과 RTL-equivalent BF16 normalization 결과를 비교한다.
