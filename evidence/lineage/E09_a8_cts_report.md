# 엄격한 CTS 완료 재실행

최종 분류: **H1_SUPPORTED_CTS_STRICT_PASS**. 기준 prompt SHA256:
`016bb087a4c918c24d74baa6d295215d7f5558f03e8170b3092f87cd5f4f366c`.

source, recipe, baseline, canonical-tool, resource, ownership, DPL, completion, output 및 independent reopen gate가 모두 통과했습니다. canonical CTS 실행 파일은 `external/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad`이며 SHA256은 `ed2d72763fd57a7500f18a03ddb714c3a31730c12ef3bcaf4e19cf688ef327f9`, 버전은 `26Q3-1080-gab6fd26351`입니다. route-free seed hash는 ODB `61ce871b8b3d9a4db1204557f733788d475affabaf67921021e17b5676dcd879`, SDC `51ff83730acbf6710614999f79a9dd7d7b8aff7824f4d36a4b05b3c88f33a5fd`입니다. CTS는 정확히 한 번 실행했고 종료 코드 0, wall time 02:07:04, peak RSS 31,669,600 kB였습니다.

프로세스 내부 marker `R3_STRICT_CTS_TCL_COMPLETE PASS`와 외부 marker `R3_STRICT_CTS_COMPLETION PASS`가 있습니다. 최종 `check_placement -verbose`는 위반 0건, 미배치 instance 0개를 보고했습니다. ownership hook에는 모호한 할당과 기존 group/region 변경이 없었고, 두 번째 detailed placement는 4번째 iteration에서 위반 0/불법 셀 0/불법 site 0으로 수렴했습니다. 출력 hash는 `4_1_cts.odb` `2aa6698071258bba5e6853b04245f546189457729ac59118b1d43bbb798502d5`, `4_cts.sdc` `c3f1381d0f8c236bd826f1fb0ab2a3b069a29242fdc89a2b9d2f29d4795950e8`입니다.

Independent Liberty-first reopen은 예상 block, `clk_i` clock 1개, bump 565개, EXCLUSIVE region 4개, 배치 위반 0, 미배치 instance 0, `have_routes=0`, detailed route 0 및 실제 dbWire-bearing net 0개로 통과했습니다.

Global route, FastRoute/CUGR, detailed route, RC extraction, post-route STA, power/PPA, fill, GDS/OASIS, DRC/LVS/antenna/manufacturing signoff는 **NOT_RUN**입니다. 이전 R3/R6/R7 산출물은 변경하지 않는 증거로 남겼으며 CTS 입력으로 사용하지 않았습니다.
