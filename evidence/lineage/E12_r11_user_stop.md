# R11 H11 DRT user-stop audit

classification = INCONCLUSIVE_USER_STOP_AFTER_OPTIMIZATION_1
research_gate  = NOT_PASS
drt_complete   = false
downstream     = NOT_AUTHORIZED

The active OpenROAD child was identity-checked and received exactly one
SIGINT at the user's explicit stop request. No additional signal was sent.
At audit time, the OpenROAD child, `/usr/bin/time`, and wrapper remained alive;
therefore the final process exit code and end-of-run evidence were not yet
available.

The log had completed optimization iteration 0 and had entered optimization
iteration 1. Iteration 1 `Completing 100%` and `DRT-0199` had not been observed
at the time of the user stop. No DRT PASS marker is asserted. RCX, STA, PPA,
R12, fill, GDS, and signoff are not authorized by this interrupted run.
