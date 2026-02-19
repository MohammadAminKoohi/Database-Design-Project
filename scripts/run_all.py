#!/usr/bin/env python3
"""
Run all database population scripts in order:
0. Apply constraints/triggers (ensures DB has latest rules, e.g. WalletTransaction allows negative Amount)
1. load_dataset.py - Import provided data
2. generate_extra_data.py - Generate missing data with Faker
3. reconstruct_wallet.py - Reconstruct wallet transaction history
"""
import os
import subprocess
import sys
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

load_dotenv()

SCRIPTS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPTS_DIR.parent


def apply_constraints():
    """Apply init/03-constraints-triggers.sql so constraints match the current file (e.g. WalletTransaction Amount <> 0)."""
    path = PROJECT_ROOT / "init" / "03-constraints-triggers.sql"
    if not path.exists():
        return
    print(f"\n{'='*60}\nApplying constraints and triggers\n{'='*60}")
    conn = psycopg2.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE", "bdbkala"),
        user=os.getenv("PGUSER", "admin"),
        password=os.getenv("PGPASSWORD", "admin"),
    )
    try:
        with conn.cursor() as cur:
            cur.execute(path.read_text())
        conn.commit()
        print("Constraints and triggers applied successfully.")
    finally:
        conn.close()


def run(script_name):
    print(f"\n{'='*60}\nRunning {script_name}\n{'='*60}")
    venv_python = SCRIPTS_DIR.parent / ".venv" / "bin" / "python"
    python = venv_python if venv_python.exists() else sys.executable
    result = subprocess.run([str(python), str(SCRIPTS_DIR / script_name)])
    if result.returncode != 0:
        print(f"ERROR: {script_name} failed with code {result.returncode}")
        sys.exit(result.returncode)


def main():
    apply_constraints()
    run("load_dataset.py")
    run("generate_extra_data.py")
    run("reconstruct_wallet.py")
    print("\n" + "=" * 60)
    print("All scripts completed successfully.")
    print("=" * 60)


if __name__ == "__main__":
    main()
