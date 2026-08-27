# Track B 계획 색인

갱신일: 2026-08-24 UTC

이 문서는 Track B 계획 문서의 우선순위와 변경 가능 여부를 정의한다. 과거 실행 prompt와 candidate plan은 SHA-256 provenance에 포함되므로 내용을 수정하지 않고 역사 문서로 보존한다.

## 현재 기준 문서

1. `TRACK_B_B26_L2D_A8_ACTIVE_DOWNSTREAM_PLAN.md`
2. `TRACK_B_B26_L2D_A8_ACTIVE_DOWNSTREAM_PLAN.json`
3. Immutable policy reference: `reports/groot_normalization/quad_local_b26_l2d_a8_cts_r3_fence_ownership_r1_20260823T001622Z/research_ppa_policy_update.md`
4. Immutable work-plan reference: `reports/groot_normalization/quad_local_b26_l2d_a8_cts_r3_fence_ownership_r1_20260823T001622Z/research_ppa_work_plan.json`
5. Current bounded execution: `TRACK_B_B26_L2D_A8_R11_H11_DRT_RCX_PPA_PROMPT.md` and its R11 `candidate_plan.json`

현재 완료 방향:

```text
DRT 기본 무결성
→ independent reopen
→ routed RC extraction
→ post-route STA/PPA
→ exploratory GDS/OASIS export
→ independent readback
```

제조 signoff는 현재 완료 방향에 포함되지 않습니다.

## 변경하지 않는 과거 실행 문서

다음 문서는 실행 당시의 hash와 계약을 보존하기 위해 수정하지 않는다. 현재 계획과 충돌하면 current authority를 적용하며, 역사 문서를 재실행하지 않는다.

- `TRACK_B_B26_L2D_A6_FLOORPLAN_NATIVE_CORRIDOR_PROMPT.md`
- `TRACK_B_B26_L2D_A7_GLOBAL_MET1_MET2_PROMPT.md`
- `TRACK_B_B26_L2D_A7_PF4_INDEPENDENT_PROOF_PROMPT.md`
- `TRACK_B_B26_L2D_A8_CTS_R3_FENCE_OWNERSHIP_HYPOTHESIS_PROMPT.md`
- `TRACK_B_B26_L2D_A8_CTS_STRICT_COMPLETION_RERUN_PROMPT.md`
- `TRACK_B_B26_L2D_A8_CTS_TO_SIGNOFF_EXECUTION_PROMPT.md`
- `TRACK_B_B26_L2D_A8_INSTRUMENTED_PF4_REPRO_PROMPT.md`
- `TRACK_B_B26_L2D_A8_R5_CUGR_RRR10_ROUTE_INTEGRITY_PROMPT.md`
- `TRACK_B_B26_L2D_A8_R6_H6_NOMINAL_CAPACITY_LOCAL_DEMAND_PROMPT.md`
- `TRACK_B_B26_L2D_A8_R7_H7_FASTROUTE_CANONICAL_CONFIRM_R3_PROMPT.md`
- `TRACK_B_B26_L2D_A8_R7_H7_FASTROUTE_SOLVER_CROSSCHECK_PROMPT.md`
- `TRACK_B_B26_L2D_A8_R7_H7_FASTROUTE_SOLVER_CROSSCHECK_RETRY_R2_PROMPT.md`
- `TRACK_B_B26_L2D_A8_R8_H8_CUGR_RRR2_STRICT_ROUTE_PROMPT.md`
- `TRACK_B_B26_L2D_A8_R9_H9_CUGR_RRR0_STRICT_ROUTE_PROMPT.md`
- `TRACK_B_B26_L2D_A8_R10_H10_MET3_ESCAPE_CAPACITY_STRICT_ROUTE_PROMPT.md`
- `TRACK_B_B26_L2D_AUTONOMOUS_LADDER_PROMPT.md`
- `TRACK_B_B26_L2D_NEXT_ECO_PROMPT.md`
- `TRACK_B_B26_L2D_NEXT_ECO_PROMPT_LEGACY.md`
- `TRACK_B_B35_RESUME_PROMPT.md`

## 갱신된 상위 수준 문서

다음 상위 문서는 current authority를 가리키도록 갱신했다.

- `README.md`
- `PROJECT_ONBOARDING_GUIDE.md`
- `PAPER_THREE_ARCHITECTURE_COMPARISON_WORK_PLAN.md`
- `ppa_구현_로드맵_작업_프롬프트.md`
- `final_integrated_research_gds_goal_prompt.md`
- `NEXT_WORK_PROMPT_WBQ_PHASE3_5_PHASE4.md`

## 보존 규칙

- 이미 manifest나 prompt hash에 인용된 파일은 in-place 수정하지 않는다.
- 새 방향은 versioned plan/index로 추가한다.
- 실행 중인 R11 namespace와 입력 R10 namespace는 수정하지 않는다.
- final report와 execution manifest는 실행 종료 후 실제 관측값으로만 작성한다.
