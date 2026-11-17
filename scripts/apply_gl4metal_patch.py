#!/usr/bin/env python3
"""Apply the bundled renderer changes to the exact upstream revision used by CI."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def apply(source):
    bundle = Path(__file__).resolve().parents[1] / "patches/gl4metal"
    manifest = json.loads((bundle / "manifest.json").read_text(encoding="utf-8"))
    patch = bundle / manifest["patch"]
    digest = hashlib.sha256(patch.read_bytes()).hexdigest()
    if digest != manifest["sha256"]:
        raise ValueError("Bundled gl4metal patch checksum mismatch")
    head = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if head != manifest["base_commit"]:
        raise ValueError(f"Expected gl4metal {manifest['base_commit']}, found {head}")
    command = ["git", "-C", str(source), "apply", "--whitespace=nowarn"]
    # Rerunning the preparation step must be harmless. Never reset user files.
    applied = subprocess.run(command + ["--reverse", "--check", str(patch)], capture_output=True)
    if applied.returncode == 0:
        print("Custom gl4metal patch already applied")
        return
    subprocess.run(command + ["--check", str(patch)], check=True)
    subprocess.run(command + [str(patch)], check=True)
    print(f"Applied custom gl4metal (3D images, SSBOs, compute), patch SHA256 {digest}")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: apply_gl4metal_patch.py /path/to/gl4metal")
        apply(Path(sys.argv[1]).resolve())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"Cannot prepare custom gl4metal: {error}")
