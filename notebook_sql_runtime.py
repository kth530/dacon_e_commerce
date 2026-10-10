"""최종 SQL 파일의 named query를 선택적으로 실행하는 유틸리티."""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Callable

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import URL, create_engine, text
from sqlalchemy.engine import Engine


NAMED_QUERY_PATTERN = r"(?m)^--\s*name:\s*(\w+).*$"


def find_project_root(start: Path | None = None) -> Path:
    """`.env`와 `sql/`을 함께 가진 가장 가까운 프로젝트 루트를 찾는다."""
    start_path = (start or Path.cwd()).resolve()
    for path in [start_path, *start_path.parents]:
        if (path / ".env").exists() and (path / "sql").is_dir():
            return path
    raise FileNotFoundError(f"Project root not found from: {start_path}")


def create_engine_from_env(project_root: Path) -> Engine:
    """프로젝트 `.env`를 읽어 MySQL engine을 만든다."""
    load_dotenv(project_root / ".env")
    db_url = URL.create(
        "mysql+mysqlconnector",
        username=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        host=os.getenv("DB_HOST"),
        database=os.getenv("DB_NAME"),
    )
    return create_engine(db_url)


def load_named_queries(path: Path) -> dict[str, str]:
    """`-- name:` 마커로 SQL 파일을 쪼개 이름별 query를 반환한다."""
    sql_path = Path(path)
    body = sql_path.read_text(encoding="utf-8")
    parts = re.split(NAMED_QUERY_PATTERN, body)
    names = parts[1::2]
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        joined = ", ".join(duplicates)
        raise ValueError(f"Duplicate named query in {sql_path}: {joined}")
    return {parts[i]: parts[i + 1].strip() for i in range(1, len(parts), 2)}


def create_runtime(
    project_root: Path,
    sql_file: Path,
) -> tuple[Engine, dict[str, str], Callable[..., pd.DataFrame], Callable[[str], None]]:
    """engine과 `Q`, `run`, `execute`를 반환한다."""
    sql_path = Path(sql_file)
    engine = create_engine_from_env(Path(project_root))
    queries = load_named_queries(sql_path)

    def get_query(name: str) -> str:
        try:
            return queries[name]
        except KeyError:
            raise KeyError(f"Named query '{name}' not found in {sql_path}") from None

    def run(name: str, **kwargs) -> pd.DataFrame:
        query = get_query(name)
        try:
            return pd.read_sql(query, engine, **kwargs)
        except Exception as exc:
            raise RuntimeError(f"Failed to run named query '{name}' from {sql_path}") from exc

    def execute(name: str) -> None:
        query = get_query(name)
        try:
            with engine.begin() as conn:
                for statement in [part for part in query.split(";") if part.strip()]:
                    conn.execute(text(statement))
        except Exception as exc:
            raise RuntimeError(f"Failed to execute named query '{name}' from {sql_path}") from exc

    return engine, queries, run, execute


__all__ = [
    "create_engine_from_env",
    "create_runtime",
    "find_project_root",
    "load_named_queries",
]
