<div align="center">

# 🚨 심사위원 공개 접속 안내 🚨

## `reviewer@34.47.124.14:22`

**SSH 포트: `22` · 계정: `reviewer` · 읽기 전용 격리 심사 환경**

</div>

심사위원은 아래 명령으로 접속하십시오.

```bash
ssh -p 22 reviewer@34.47.124.14
```

접속하면 자동으로 읽기 전용 컨테이너에 진입합니다. 별첨 증거자료의 기준 경로는 다음과 같습니다.

```text
/evidence/home/forstobpim/PIM_simulator
```

심사 환경은 지정된 별첨 증거자료만 제공하며, 호스트 프로젝트에는 접근할 수 없습니다. 파일 생성·수정·삭제와 네트워크 접근은 차단되어 있습니다. SSH 개인키나 비밀키는 이 저장소와 README에 포함하지 않습니다.

# STOB 계층형 PIM 핵심 코드

계층형 HBM2-PIM 연구 프로토타입 제출용 패키지입니다.

## 범위

이 저장소에는 프로젝트의 SystemVerilog 정규화 PCU RTL, 선별한 RTL 검증
테스트벤치, 독립 reference/분석 유틸리티와 선별 증거자료가 포함됩니다.
삼성 PIMSimulator/DRAMSim2 기반 C++ 시뮬레이터, 시뮬레이터 바이너리,
열 분석 파이프라인, 외부 논문 및 대형 물리 설계 데이터베이스는 배포하지 않습니다.

## 핵심 결과

주요 소스는 `rtl/core/normalization_pcu/` 아래의 16-bank, 8-lane,
분리 read/write 정규화 PCU입니다. `rtl/integration/` 아래에는 선별한
quad-local B2 경로가 있습니다.

## 증거의 범위

포함된 결과는 연구 증거로만 사용해야 합니다. RTL 기능 PASS는 timing
closure, power signoff, 제조 signoff 또는 tape-out 준비 완료를 의미하지
않습니다. workload는 GR00T에서 파생한 정규화 경계 연구이며, GR00T 전체
end-to-end 추론이 아닙니다.

## 재현

`reproducibility/commands.md`와 `reproducibility/tool_versions.txt`를
참조하십시오. 원본 서버 절대 경로는 제거했으며, 모든 경로는 이 저장소
기준 상대 경로 또는 명시된 외부 도구 설치 경로로 해석되어야 합니다.

## 라이선스 및 제3자 코드

`THIRD_PARTY_NOTICES.md`를 참조하십시오. 제한된 시뮬레이터 소스가 이
저장소에 없다는 사실은 해당 소스의 재배포 허가를 의미하지 않습니다.
