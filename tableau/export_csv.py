"""최종 분석 노트북의 테이블로 단일 대시보드용 CSV 세 개를 생성한다.

02의 pipeline 셀과 03·04의 산점도/구매 간격 셀을 그대로 실행한다.
출력은 임시 디렉터리에서 검증한 다음 지정한 디렉터리에 교체한다.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parent.parent
HERE = Path(__file__).resolve().parent
DATA = ROOT / "data"
GRADE_ORDER = ["Bronze", "Silver", "Gold", "Platinum", "Diamond"]
EXPECTED_GRADES = {"Bronze": 698, "Silver": 315, "Gold": 243, "Platinum": 154, "Diamond": 58}
SOURCE_FILES = [
    "Onlinesales_info.csv",
    "Customer_info.csv",
    "Discount_info.csv",
    "Marketing_info.csv",
    "Tax_info.csv",
]

# 기존 워크북의 필드 참조와 추출 스키마를 유지한다. 새 고객 필드는 뒤에 추가한다.
ORDER_COLUMNS = [
    "고객ID", "거래ID", "고객주문키", "거래날짜", "월", "제품카테고리", "제품ID",
    "수량", "세후금액", "쿠폰상태", "성별", "고객지역", "가입기간",
    "등급", "세그먼트", "R", "F", "M",
]
CUSTOMER_COLUMNS = [
    "고객ID", "등급", "세그먼트", "R", "F", "M", "RFM_score", "Recency",
    "거래건수", "총지출", "성별", "고객지역", "가입기간", "구매일수",
    "재방문여부", "첫구매월", "R_scale", "F_scale", "marker_size",
]
CUSTOMER_EXTRA_COLUMNS = [
    "다음달관찰가능", "첫구매월+1개월복귀", "장기미방문_90일예시",
    "최대구매간격_일", "공백상태_90일예시",
]
COHORT_COLUMNS = ["등급", "코호트월", "경과월", "고객수", "코호트크기", "리텐션율", "관찰가능"]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_analysis() -> tuple[dict, dict[str, str]]:
    """노트북 코드를 복제하지 않고 현재 저장된 분석 셀을 한 번 실행한다."""
    for name in SOURCE_FILES:
        if not (DATA / name).is_file():
            raise FileNotFoundError(DATA / name)

    namespace: dict = {}
    code_hashes: dict[str, str] = {}
    previous_cwd = Path.cwd()
    try:
        # 02 첫 셀의 프로젝트 루트 탐색은 현재 작업 디렉터리를 사용한다.
        os.chdir(ROOT)
        with contextlib.redirect_stdout(io.StringIO()):
            for filename, cell_id in (
                ("02_data_preparation.ipynb", None),
                ("03_data_overview.ipynb", "overview-033"),
                ("04_eda_validation.ipynb", "ffc97dba"),
            ):
                notebook_path = ROOT / "notebooks" / filename
                cells = json.loads(notebook_path.read_text(encoding="utf-8"))["cells"]
                if cell_id is None:
                    selected = [
                        cell for cell in cells
                        if cell["cell_type"] == "code"
                        and "pipeline" in cell.get("metadata", {}).get("tags", [])
                    ]
                else:
                    selected = [
                        cell for cell in cells
                        if cell["cell_type"] == "code" and cell.get("id") == cell_id
                    ]
                if not selected or (cell_id is not None and len(selected) != 1):
                    raise ValueError(f"필요한 분석 셀을 찾지 못했습니다: {notebook_path.name} / {cell_id}")
                source = "\n".join("".join(cell["source"]) for cell in selected)
                code_hashes[filename] = hashlib.sha256(source.encode("utf-8")).hexdigest()
                for cell in selected:
                    code = "".join(cell["source"])
                    exec(compile(code, f"{notebook_path}#{cell.get('id')}", "exec"), namespace)
    finally:
        os.chdir(previous_cwd)

    needed = (
        "sales_lines", "analysis_orders", "analysis_customers", "customer_month",
        "customer", "rfm_plot", "max_purchase_gap",
        "platinum_gap_summary",
    )
    missing = [name for name in needed if name not in namespace]
    if missing:
        raise RuntimeError(f"최종 노트북 실행 결과가 부족합니다: {missing}")
    return namespace, code_hashes


def build_orders(analysis: dict) -> pd.DataFrame:
    lines = analysis["sales_lines"]
    customer = analysis["analysis_customers"]
    labels = customer[["고객ID", "등급", "세그먼트", "R", "F", "M"]]
    frame = lines.merge(labels, on="고객ID", how="left", validate="many_to_one", sort=False)
    frame["고객주문키"] = frame["고객ID"].astype(str) + "|" + frame["거래ID"].astype(str)
    return frame[ORDER_COLUMNS].copy()


def build_customers(analysis: dict) -> pd.DataFrame:
    customer = analysis["analysis_customers"].merge(
        analysis["customer"][["고객ID", "성별", "고객지역", "가입기간"]],
        on="고객ID", validate="one_to_one",
    )
    coords = analysis["rfm_plot"][["고객ID", "R_scale", "F_scale", "marker_size"]]
    customer = customer.merge(coords, on="고객ID", validate="one_to_one")
    customer = customer.merge(
        analysis["max_purchase_gap"].rename("최대구매간격_일").reset_index(),
        on="고객ID", validate="one_to_one",
    )
    customer = customer.rename(columns={
        "Frequency": "거래건수", "Monetary": "총지출",
        "다른날재방문": "재방문여부", "관측첫구매월": "첫구매월",
    })
    for name in ("재방문여부", "다음달관찰가능", "첫구매월+1개월복귀", "장기미방문_90일예시"):
        customer[name] = customer[name].astype(int)
    customer[["R_scale", "F_scale"]] = customer[["R_scale", "F_scale"]].round(4)
    customer["공백상태_90일예시"] = np.select(
        [customer["Recency"].gt(90), customer["최대구매간격_일"].gt(90)],
        ["기준일 90일 초과", "장기 공백 후 복귀"], default="그 외",
    )
    return customer[CUSTOMER_COLUMNS + CUSTOMER_EXTRA_COLUMNS].copy()


def build_cohort(analysis: dict) -> pd.DataFrame:
    """등급×관측 첫 구매월×경과월의 전체 격자를 만든다."""
    customer = analysis["analysis_customers"][["고객ID", "등급", "관측첫구매월"]]
    sizes = customer.groupby(["등급", "관측첫구매월"]).size()
    purchases = analysis["customer_month"].merge(customer, on="고객ID", validate="many_to_one")
    purchases["경과월"] = purchases["구매월"] - purchases["관측첫구매월"]
    returned = purchases.groupby(["등급", "관측첫구매월", "경과월"])["고객ID"].nunique()

    rows = []
    for (grade, first_month), size in sizes.items():
        for lag in range(12):
            observable = first_month + lag <= 12
            count = int(returned.get((grade, first_month, lag), 0)) if observable else pd.NA
            rows.append({
                "등급": grade,
                "코호트월": int(first_month),
                "경과월": lag,
                "고객수": count,
                "코호트크기": int(size) if observable else pd.NA,
                "리텐션율": round(count / size * 100, 1) if observable else np.nan,
                "관찰가능": int(observable),
            })
    cohort = pd.DataFrame(rows, columns=COHORT_COLUMNS)
    cohort[["고객수", "코호트크기"]] = cohort[["고객수", "코호트크기"]].astype("Int64")
    cohort["등급"] = pd.Categorical(cohort["등급"], categories=GRADE_ORDER, ordered=True)
    cohort = cohort.sort_values(["등급", "코호트월", "경과월"]).reset_index(drop=True)
    cohort["등급"] = cohort["등급"].astype(str)
    return cohort


def validate_frames(frames: dict[str, pd.DataFrame], analysis: dict) -> dict:
    orders = frames["v_tableau_orders.csv"]
    customer = frames["v_tableau_customer.csv"]
    cohort = frames["cohort_retention.csv"]
    source_customer = analysis["analysis_customers"]

    assert list(orders.columns) == ORDER_COLUMNS
    assert list(customer.columns) == CUSTOMER_COLUMNS + CUSTOMER_EXTRA_COLUMNS
    assert list(cohort.columns) == COHORT_COLUMNS
    assert len(orders) == 52924 and len(customer) == 1468
    assert customer["고객ID"].is_unique and not customer["고객ID"].isna().any()
    assert orders["고객ID"].nunique() == len(customer)
    assert orders["고객주문키"].nunique() == 26631
    assert orders.groupby(["고객ID", "거래ID"])["고객주문키"].nunique().eq(1).all()
    assert customer["등급"].value_counts().to_dict() == EXPECTED_GRADES
    assert customer["세그먼트"].ne("Others").all()
    assert customer[["R_scale", "F_scale", "marker_size"]].notna().all().all()
    assert customer["재방문여부"].sum() == 734
    assert customer["다음달관찰가능"].sum() == 1362
    assert customer["첫구매월+1개월복귀"].sum() == 130
    assert customer["첫구매월"].between(1, 12).all()
    assert customer["최대구매간격_일"].ge(0).all()
    platinum_states = customer.loc[customer["등급"].eq("Platinum"), "공백상태_90일예시"].value_counts()
    assert [int(platinum_states.get(label, 0)) for label in
            ("그 외", "장기 공백 후 복귀", "기준일 90일 초과")] == [49, 72, 33]

    sales = round(float(orders["세후금액"].sum()), 2)
    assert sales == 4840102.19
    assert round(float(customer["총지출"].sum()), 2) == sales
    line_grade = orders.groupby("등급")["세후금액"].sum().reindex(GRADE_ORDER)
    customer_grade = customer.groupby("등급")["총지출"].sum().reindex(GRADE_ORDER)
    assert np.allclose(line_grade, customer_grade, rtol=0, atol=0.01)
    assert np.allclose(
        customer_grade, source_customer.groupby("등급")["Monetary"].sum().reindex(GRADE_ORDER),
        rtol=0, atol=0.01,
    )
    source_labels = source_customer.set_index("고객ID")[["등급", "세그먼트", "R", "F", "M"]]
    export_labels = customer.set_index("고객ID")[["등급", "세그먼트", "R", "F", "M"]]
    assert export_labels.sort_index().equals(source_labels.sort_index())
    assert orders[["고객ID", "등급", "세그먼트"]].drop_duplicates().set_index("고객ID").sort_index().equals(
        customer[["고객ID", "등급", "세그먼트"]].set_index("고객ID").sort_index()
    )

    assert len(cohort) == 720 and cohort[["등급", "코호트월", "경과월"]].duplicated().sum() == 0
    observed = cohort["관찰가능"].eq(1)
    assert observed.equals(cohort["코호트월"].add(cohort["경과월"]).le(12))
    assert cohort.loc[observed, ["고객수", "코호트크기", "리텐션율"]].notna().all().all()
    assert cohort.loc[~observed, ["고객수", "코호트크기", "리텐션율"]].isna().all().all()
    assert (cohort.loc[observed, "고객수"] <= cohort.loc[observed, "코호트크기"]).all()
    assert cohort.loc[cohort["경과월"].eq(0), "고객수"].sum() == len(customer)
    assert cohort.loc[cohort["경과월"].eq(0), "코호트크기"].sum() == len(customer)
    returning = analysis["customer_month"].merge(
        source_customer[["고객ID", "관측첫구매월"]],
        on="고객ID", validate="many_to_one",
    )
    for lag in range(1, 12):
        rows = cohort.loc[cohort["경과월"].eq(lag) & observed]
        eligible = source_customer["관측첫구매월"].le(12 - lag)
        expected_denominator = int(eligible.sum())
        expected_numerator = int(returning["구매월"].sub(returning["관측첫구매월"]).eq(lag).sum())
        assert int(rows["코호트크기"].sum()) == expected_denominator
        assert int(rows["고객수"].sum()) == expected_numerator
    next_month = cohort.loc[cohort["경과월"].eq(1) & observed]
    assert (int(next_month["고객수"].sum()), int(next_month["코호트크기"].sum())) == (130, 1362)
    assert next_month["고객수"].sum() / next_month["코호트크기"].sum() * 100 == 130 / 1362 * 100
    next_month_by_grade = next_month.groupby("등급")[["고객수", "코호트크기"]].sum()
    customer_next_month = customer.groupby("등급")[["첫구매월+1개월복귀", "다음달관찰가능"]].sum()
    for grade in GRADE_ORDER:
        assert int(next_month_by_grade.loc[grade, "고객수"]) == int(
            customer_next_month.loc[grade, "첫구매월+1개월복귀"]
        )
        assert int(next_month_by_grade.loc[grade, "코호트크기"]) == int(
            customer_next_month.loc[grade, "다음달관찰가능"]
        )
    for grade, count in EXPECTED_GRADES.items():
        base = cohort.loc[cohort["등급"].eq(grade) & cohort["경과월"].eq(0)]
        assert int(base["코호트크기"].sum()) == count

    return {
        "상품라인수": len(orders), "고객주문수": orders["고객주문키"].nunique(),
        "고객수": len(customer), "상품매출": sales,
        "다른날재방문고객수": int(customer["재방문여부"].sum()),
        "다음달복귀": "130/1362", "등급별고객수": EXPECTED_GRADES,
        "등급별상품매출": {grade: round(float(customer_grade.loc[grade]), 2) for grade in GRADE_ORDER},
        "등급별다음달복귀": {
            grade: {
                "복귀고객": int(next_month_by_grade.loc[grade, "고객수"]),
                "관찰가능고객": int(next_month_by_grade.loc[grade, "코호트크기"]),
            }
            for grade in GRADE_ORDER
        },
        "코호트_관찰가능_행": int(observed.sum()),
        "코호트_구매0건_행": int((cohort.loc[observed, "고객수"] == 0).sum()),
        "코호트_미관측_행": int((~observed).sum()),
        "Platinum_공백상태_고객수": {"그 외": 49, "장기 공백 후 복귀": 72, "기준일 90일 초과": 33},
    }


def verify_mysql(analysis: dict) -> dict:
    """선택 검사: 현재 DB의 고객 분류와 고객 주문을 Python 결과에 대조한다."""
    from dotenv import dotenv_values
    from sqlalchemy import URL, create_engine

    config = dotenv_values(ROOT / ".env")
    names = ("DB_USER", "DB_PASSWORD", "DB_HOST", "DB_NAME")
    missing = [name for name in names if not config.get(name)]
    if missing:
        raise ValueError(f"MySQL 검증용 .env 항목이 없습니다: {missing}")
    engine = create_engine(URL.create(
        "mysql+mysqlconnector", username=config["DB_USER"], password=config["DB_PASSWORD"],
        host=config["DB_HOST"], database=config["DB_NAME"],
    ))
    try:
        db_customer = pd.read_sql(
            "SELECT 고객ID, 등급, 세그먼트, R, F, M, RFM_score, Recency, Frequency, Monetary "
            "FROM rfm_result", engine,
        )
        db_orders = pd.read_sql(
            "SELECT 고객ID, 거래ID, COUNT(*) AS 상품라인수, MIN(DATE(거래날짜)) AS 거래날짜, "
            "SUM(CAST(세후금액 AS DECIMAL(18,2))) AS 상품매출, MAX(배송료) AS 배송비 "
            "FROM orders_master GROUP BY 고객ID, 거래ID", engine,
        )
    finally:
        engine.dispose()

    source_customer = analysis["analysis_customers"]
    cols = ["고객ID", "등급", "세그먼트", "R", "F", "M", "RFM_score", "Recency", "Frequency", "Monetary"]
    comparison = source_customer[cols].merge(db_customer, on="고객ID", suffixes=("_py", "_db"), validate="one_to_one")
    assert len(comparison) == 1468 and len(db_customer) == 1468
    for col in ("등급", "세그먼트", "R", "F", "M", "Recency", "Frequency"):
        assert comparison[f"{col}_py"].eq(comparison[f"{col}_db"]).all(), col
    for col in ("RFM_score", "Monetary"):
        assert np.allclose(comparison[f"{col}_py"], comparison[f"{col}_db"], rtol=0, atol=0.01), col

    source_orders = analysis["analysis_orders"][[
        "고객ID", "거래ID", "상품라인수", "거래날짜", "상품매출", "배송비"
    ]]
    merged = source_orders.merge(db_orders, on=["고객ID", "거래ID"],
                                 suffixes=("_py", "_db"), validate="one_to_one")
    assert len(merged) == len(source_orders) == len(db_orders) == 26631
    assert merged["상품라인수_py"].eq(merged["상품라인수_db"]).all()
    assert pd.to_datetime(merged["거래날짜_py"]).dt.date.eq(
        pd.to_datetime(merged["거래날짜_db"]).dt.date
    ).all()
    for col in ("상품매출", "배송비"):
        assert np.allclose(merged[f"{col}_py"].astype(float), merged[f"{col}_db"].astype(float),
                           rtol=0, atol=0.01), col
    return {"status": "passed", "rfm_customers": len(comparison), "customer_orders": len(merged),
            "note": "행·분류·금액 대조만 가능하며 DB에 원천 파일/노트북 코드 해시가 없어 적재 버전 증명은 불가"}


def publish(frames: dict[str, pd.DataFrame], output_dir: Path, metadata: dict) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".tableau_export_", dir=output_dir) as temp:
        staged = Path(temp)
        for name, frame in frames.items():
            frame.to_csv(staged / name, index=False, encoding="utf-8-sig", na_rep="")
            check = pd.read_csv(staged / name)
            assert len(check) == len(frame) and list(check.columns) == list(frame.columns), name
            if name == "cohort_retention.csv":
                observable = check["관찰가능"].eq(1)
                assert check.loc[observable, ["고객수", "코호트크기", "리텐션율"]].notna().all().all()
                assert check.loc[~observable, ["고객수", "코호트크기", "리텐션율"]].isna().all().all()
        (staged / "pipeline_metadata.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        for name in [*frames, "pipeline_metadata.json"]:
            os.replace(staged / name, output_dir / name)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=HERE,
                        help="검증 후 CSV와 메타데이터를 놓을 디렉터리 (기본: tableau/)")
    parser.add_argument("--verify-mysql", action="store_true",
                        help="현재 MySQL 적재 테이블을 노트북 결과와 추가 대조")
    args = parser.parse_args()

    analysis, code_hashes = load_analysis()
    frames = {
        "v_tableau_customer.csv": build_customers(analysis),
        "v_tableau_orders.csv": build_orders(analysis),
        "cohort_retention.csv": build_cohort(analysis),
    }
    checks = validate_frames(frames, analysis)
    mysql_check = verify_mysql(analysis) if args.verify_mysql else {"status": "not_requested"}
    metadata = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "source": "notebooks/02 pipeline + 03 scatter cell + 04 purchase-gap cell",
        "source_sha256": {name: sha256(DATA / name) for name in SOURCE_FILES},
        "analysis_code_sha256": code_hashes,
        "rows": {name: len(frame) for name, frame in frames.items()},
        "columns": {name: list(frame.columns) for name, frame in frames.items()},
        "validation": checks,
        "mysql_verification": mysql_check,
    }
    publish(frames, args.output_dir.resolve(), metadata)
    for name, frame in frames.items():
        print(f"{name:26s} {len(frame):>6,}행 x {len(frame.columns)}열")
    print("검증 통과:", checks)
    print("MySQL 대조:", mysql_check["status"])
    print("출력:", args.output_dir.resolve())


if __name__ == "__main__":
    main()
