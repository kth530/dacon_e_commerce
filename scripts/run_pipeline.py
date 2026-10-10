"""최종 분석 노트북을 순서대로 실행한다."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from jupyter_client.kernelspec import KernelSpecManager


ROOT = Path(__file__).resolve().parents[1]
NOTEBOOKS = [ROOT / "notebooks" / name for name in (
    "02_data_preparation.ipynb",
    "03_data_overview.ipynb",
    "04_eda_validation.ipynb",
)]


def run(command: list[str], dry_run: bool = False) -> None:
    print("RUN", " ".join(command), flush=True)
    if not dry_run:
        subprocess.run(command, cwd=ROOT, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="실행 파일과 명령만 확인")
    parser.add_argument("--with-tableau", action="store_true", help="노트북 실행 후 Tableau CSV 추출")
    args = parser.parse_args()

    for notebook in NOTEBOOKS:
        if not notebook.is_file():
            raise FileNotFoundError(notebook)
        run([
            "jupyter", "nbconvert", "--to", "notebook", "--execute", "--inplace",
            str(notebook), "--ExecutePreprocessor.kernel_name=ml_env",
            "--ExecutePreprocessor.timeout=600",
        ], args.dry_run)

    if args.with_tableau:
        exporter = ROOT / "tableau" / "export_csv.py"
        if not exporter.is_file():
            raise FileNotFoundError(exporter)
        kernel_python = KernelSpecManager().get_kernel_spec("ml_env").argv[0]
        run([kernel_python, str(exporter)], args.dry_run)


if __name__ == "__main__":
    main()
