#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
forbidden='(^|/)(src|libdramsim|obj_dir|bin|thermal|hardware_cost/thermal|r16_thermal)(/|$)|(^|/)(sim)$|\.(a|so|gds|oas|odb|def|spef)$'
if find "$root" -type f -printf '%P\n' | rg -n "$forbidden"; then
  echo "FORBIDDEN_SUBMISSION_CONTENT_FOUND" >&2
  exit 1
fi
if rg -n '/home/forstobpim|PIM_simulator/' "$root/docs" "$root/reproducibility"; then
  echo "SERVER_ABSOLUTE_PATH_FOUND" >&2
  exit 1
fi
echo "SUBMISSION_TREE_CHECK_PASS"
