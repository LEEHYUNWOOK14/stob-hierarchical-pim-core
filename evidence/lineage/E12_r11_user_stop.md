# R11 H11 DRT 사용자 중단 감사

분류 = INCONCLUSIVE_USER_STOP_AFTER_OPTIMIZATION_1
연구 gate = NOT_PASS
drt_complete = false
후속 단계 = NOT_AUTHORIZED

활성 OpenROAD child의 신원을 확인했으며 사용자의 명시적 중단 요청 시
SIGINT를 정확히 한 번 보냈습니다. 추가 signal은 보내지 않았습니다. 감사
시점에 OpenROAD child, `/usr/bin/time` 및 wrapper가 계속 살아 있었으므로
최종 프로세스 종료 코드와 실행 종료 증거는 아직 확인할 수 없었습니다.

로그는 optimization iteration 0을 완료하고 iteration 1에 진입한 상태였습니다.
사용자 중단 시점에는 iteration 1의 `Completing 100%`와 `DRT-0199`를 관측하지
못했습니다. DRT PASS marker는 선언하지 않습니다. 이 중단된 실행으로는
RCX, STA, PPA, R12, fill, GDS 및 signoff를 승인할 수 없습니다.
