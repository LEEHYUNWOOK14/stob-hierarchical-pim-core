# Strict CTS completion rerun

Final classification: **H1_SUPPORTED_CTS_STRICT_PASS**. Governing prompt SHA256: `016bb087a4c918c24d74baa6d295215d7f5558f03e8170b3092f87cd5f4f366c`.

All source, recipe, baseline, canonical-tool, resource, ownership, DPL, completion, output, and independent reopen gates passed. The canonical CTS executable was `external/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad`, SHA256 `ed2d72763fd57a7500f18a03ddb714c3a31730c12ef3bcaf4e19cf688ef327f9`, version `26Q3-1080-gab6fd26351`. The route-free seed hashes were `61ce871b8b3d9a4db1204557f733788d475affabaf67921021e17b5676dcd879` (ODB) and `51ff83730acbf6710614999f79a9dd7d7b8aff7824f4d36a4b05b3c88f33a5fd` (SDC). CTS ran exactly once, exited 0, and took 02:07:04 wall time with peak RSS 31,669,600 kB.

The in-process marker `R3_STRICT_CTS_TCL_COMPLETE PASS` and external marker `R3_STRICT_CTS_COMPLETION PASS` are present. Final `check_placement -verbose` reported zero violations, unplaced instances were 0, ownership hooks had zero ambiguous assignments and zero existing group/region changes, and second detailed placement converged to 0 violations / 0 illegal cells / 0 illegal sites at iteration 4. Output hashes: `4_1_cts.odb` `2aa6698071258bba5e6853b04245f546189457729ac59118b1d43bbb798502d5`; `4_cts.sdc` `c3f1381d0f8c236bd826f1fb0ab2a3b069a29242fdc89a2b9d2f29d4795950e8`.

Independent Liberty-first reopen passed with the expected block, one `clk_i` clock, 565 bumps, four EXCLUSIVE regions, zero placement violations, zero unplaced instances, `have_routes=0`, detailed routes=0, and zero actual dbWire-bearing nets.

Global route, FastRoute/CUGR, detailed route, RC extraction, post-route STA, power/PPA, fill, GDS/OASIS, DRC/LVS/antenna/manufacturing signoff: **NOT_RUN**. The older R3/R6/R7 artifacts remain immutable evidence and were not used as CTS input.
