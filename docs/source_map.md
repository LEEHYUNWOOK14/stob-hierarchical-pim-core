# 소스 맵

| 패키지 영역 | 출처 및 역할 | 제출 상태 |
|---|---|---|
| `rtl/core/normalization_pcu/` | 프로젝트 정규화 PCU 동결 RTL | 포함 |
| `rtl/integration/` | 프로젝트 quad-local 통합 RTL | 포함 |
| `verification/` | 선별 RTL 및 통합 테스트벤치 | 선별 포함 |
| `cpp/reference/` | 독립 FP16 vector 유틸리티 | 포함, 시뮬레이터 코드 아님 |
| `python/` | 선별 workload/분석/provenance 유틸리티 | 선별 포함 |
| `data/`, `evidence/` | 선별 파생 증거 | 선별 포함 |
| `excluded-simulator-source/` | 삼성 PIMSimulator 및 DRAMSim2 파생 C++ | 제외 |
| `sim`, `libdramsim`, `obj_dir` | 빌드/실행 산출물 | 제외 |
| `thermal/`, `hardware_cost/thermal/` | 열 분석 파이프라인 | 제외 |
| 외부 논문/checkpoint | 제3자 원자료 | 복사하지 않음 |
