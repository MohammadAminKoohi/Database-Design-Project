#!/usr/bin/env python3
"""
Run all database population scripts in order:
1. load_dataset.py - Import provided data
2. generate_extra_data.py - Generate missing data with Faker
3. reconstruct_wallet.py - Reconstruct wallet transaction history
"""
import subprocess
import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent


def run(script_name):
    print(f"\n{'='*60}\nRunning {script_name}\n{'='*60}")
    venv_python = SCRIPTS_DIR.parent / ".venv" / "bin" / "python"
    python = venv_python if venv_python.exists() else sys.executable
    result = subprocess.run([str(python), str(SCRIPTS_DIR / script_name)])
    if result.returncode != 0:
        print(f"ERROR: {script_name} failed with code {result.returncode}")
        sys.exit(result.returncode)


def main():
    run("load_dataset.py")
    run("generate_extra_data.py")
    run("reconstruct_wallet.py")
    print("\n" + "=" * 60)
    print("All scripts completed successfully.")
    print("=" * 60)


if __name__ == "__main__":
    main()
