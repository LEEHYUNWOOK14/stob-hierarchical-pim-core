#!/usr/bin/env python3
"""Capture the inputs and environment needed to reproduce a regression run."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git(root: Path, *args: str) -> str:
    try:
        return subprocess.check_output(["git", *args], cwd=root, text=True,
                                       stderr=subprocess.STDOUT).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        return f"unavailable: {exc}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run-results", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    tracked = [
        "tools/collect_reproducibility_manifest.py",
        "tools/run_full_regression_gate.py",
        "verification/reproducibility/regression_manifest.json",
    ]
    files = []
    for relative in tracked:
        path = root / relative
        if path.is_file():
            files.append({"path": relative, "bytes": path.stat().st_size,
                          "sha256": sha256(path)})
    result_path = args.run_results.resolve() if args.run_results else None
    if result_path and result_path.is_file():
        files.append({"path": str(result_path.relative_to(root)).replace("\\", "/"),
                      "bytes": result_path.stat().st_size, "sha256": sha256(result_path)})
    payload = {
        "manifest_version": 1,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "repository": {
            "root": str(root),
            "branch": git(root, "branch", "--show-current"),
            "commit": git(root, "rev-parse", "HEAD"),
            "status_short": git(root, "status", "--short").splitlines(),
        },
        "environment": {
            "python": sys.version,
            "platform": platform.platform(),
            "executable": sys.executable,
            "cwd": str(Path.cwd()),
        },
        "files": files,
        "run_results": str(result_path.relative_to(root)).replace("\\", "/") if result_path else None,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"REPRODUCIBILITY_MANIFEST PASS output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
