"""Tableau 데이터 소스 CSV 추출 파이프라인.

tableau_views.sql 의 VIEW를 생성한 뒤 SELECT 결과를 CSV로 내보낸다.
코호트 리텐션은 SQL 미지원(피벗)이라 pandas로 별도 생성한다.
Tableau Public은 MySQL 라이브 연결이 안 되므로 이 CSV를 데이터 소스로 연결한다.

실행: python tableau/export_csv.py
"""
import os
import re
import json
import hashlib
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import URL, create_engine, text

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
load_dotenv(ROOT / '.env')
DATA_DIR = Path(os.getenv('DATA_DIR', ROOT / 'data'))

engine = create_engine(
    URL.create(
        'mysql+mysqlconnector',
        username=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD'),
        host=os.getenv('DB_HOST'),
        database=os.getenv('DB_NAME'),
    )
)


def load_queries(path):
    """`-- name: 이름 | 설명` 마커로 SQL을 쪼개 {이름: 쿼리}로 반환."""
    body = Path(path).read_text(encoding='utf-8')
    parts = re.split(r'(?m)^--\s*name:\s*(\w+).*$', body)
    return {parts[i]: parts[i + 1].strip() for i in range(1, len(parts), 2)}


def add_scatter_coords(df):
    """노트북 03 산점도와 동일한 R_scale/F_scale/marker_size 부여.

    R·F 점수(1~5) 밴드 안에서 각 고객을 실제 Recency/거래건수 위치에 배치하고
    ±0.1 지터를 더해 판 전체에 부드럽게 흩뿌린다 (Tableau 산점도 좌표).
    수식은 노트북 셀과 동일, 컬럼명만 CSV에 맞춤(Frequency→거래건수, Monetary→총지출).
    """
    df = df.copy()
    r_intervals = pd.qcut(df['Recency'], q=[0, 0.2, 0.4, 0.6, 0.8, 1.0])
    r_left = r_intervals.apply(lambda x: x.left).astype(float).clip(lower=0)
    r_right = r_intervals.apply(lambda x: x.right).astype(float)
    df['R_scale'] = (df['R'] - 1) + (df['Recency'] - r_left - 0.01) / (r_right - r_left) - 0.0001

    f_q1 = df['거래건수'].quantile(0.25)
    f_q2 = df['거래건수'].quantile(0.50)
    f_q3 = df['거래건수'].quantile(0.75)
    f_upper = f_q3 + 1.5 * (f_q3 - f_q1)
    f_intervals = pd.cut(df['거래건수'], bins=[0, f_q1, f_q2, f_q3, f_upper, df['거래건수'].max()])
    f_left = f_intervals.apply(lambda x: x.left).astype(float)
    f_right = f_intervals.apply(lambda x: x.right).astype(float)
    df['F_scale'] = (df['F'] - 1) + (df['거래건수'] - f_left - 0.01) / (f_right - f_left) - 0.0001

    np.random.seed(42)
    df['R_scale'] = (df['R_scale'] + np.random.uniform(-0.1, 0.1, len(df))).round(4)
    df['F_scale'] = (df['F_scale'] + np.random.uniform(-0.1, 0.1, len(df))).round(4)

    m_min = df['총지출'].min()
    m_cap = df['총지출'].quantile(0.95)
    df['marker_size'] = (
        (df['총지출'].clip(upper=m_cap) - m_min) / (m_cap - m_min) * 16 + 4
    ).round(0)
    return df


Q = load_queries(HERE / 'tableau_views.sql')

# 1) VIEW 생성
with engine.begin() as conn:
    for name in ('create_orders_view', 'create_customer_view', 'create_monthly_view'):
        for stmt in [s for s in Q[name].split(';') if s.strip()]:
            conn.execute(text(stmt))

# 2) VIEW → CSV (utf-8-sig: Tableau에서 한글 정상 표시)
exports = {
    'v_tableau_orders.csv': 'SELECT * FROM v_tableau_orders',
    'v_tableau_customer.csv': 'SELECT * FROM v_tableau_customer',
    'v_tableau_monthly.csv': 'SELECT * FROM v_tableau_monthly ORDER BY 월',
}
for fname, q in exports.items():
    df = pd.read_sql(q, engine)
    if fname == 'v_tableau_customer.csv':
        df = add_scatter_coords(df)  # ⑤ 행동 세그먼트 산점도 좌표(노트북 03과 동일)
    df.to_csv(HERE / fname, index=False, encoding='utf-8-sig')
    print(f'{fname:26s} {len(df):>6,}행 x {df.shape[1]}열')

# 3) 관측기간 코호트 리텐션 (Python 피벗 → long 포맷, 등급 차원 포함)
#    등급별로 쪼개되 원시 카운트(고객수·코호트크기)를 유지한다. Tableau에서 리텐션율을
#    SUM(고객수)/SUM(코호트크기)로 재계산하면, 등급 필터 시 해당 등급 리텐션이 나오고
#    '전체'(등급 합산)는 고객이 등급 하나에만 속하므로 기존 전체 수치와 정확히 일치한다.
orders = pd.read_sql(
    "SELECT o.고객ID, DATE(o.거래날짜) AS 구매일, r.등급 "
    "FROM orders_master o JOIN rfm_scored r ON o.고객ID = r.고객ID",
    engine,
    parse_dates=['구매일'],
)
orders['구매월'] = orders['구매일'].dt.month
first_month = orders.groupby('고객ID')['구매월'].min().rename('코호트월')
orders = orders.merge(first_month, on='고객ID')
orders['경과월'] = orders['구매월'] - orders['코호트월']

cohort = (
    orders.groupby(['등급', '코호트월', '경과월'])['고객ID']
    .nunique()
    .reset_index(name='고객수')
)
size = cohort[cohort['경과월'] == 0].set_index(['등급', '코호트월'])['고객수']
cohort['코호트크기'] = cohort.set_index(['등급', '코호트월']).index.map(size).to_numpy()
cohort['리텐션율'] = (cohort['고객수'] / cohort['코호트크기'] * 100).round(1)
cohort = cohort.sort_values(['등급', '코호트월', '경과월']).reset_index(drop=True)
cohort.to_csv(HERE / 'cohort_retention.csv', index=False, encoding='utf-8-sig')
print(f"{'cohort_retention.csv':26s} {len(cohort):>6,}행 x {cohort.shape[1]}열")

# 4) 검증
cust = pd.read_csv(HERE / 'v_tableau_customer.csv')
assert len(cust) == 1468, f'고객수 불일치: {len(cust)}'
grade = cust['등급'].value_counts().to_dict()
expected = {'Bronze': 698, 'Silver': 315, 'Gold': 243, 'Platinum': 154, 'Diamond': 58}
assert grade == expected, f'등급 분포 불일치: {grade}'
print('\n검증 통과 — 고객 1,468명, 등급 분포 일치:', expected)

orders_export = pd.read_csv(HERE / 'v_tableau_orders.csv')
assert len(orders_export) == 52924, f'거래라인 수 불일치: {len(orders_export)}'


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


metadata = {
    'generated_at_utc': datetime.now(timezone.utc).isoformat(),
    'source_sha256': {
        path.name: sha256(path)
        for path in sorted(DATA_DIR.glob('*.csv'))
    },
    'rows': {
        'v_tableau_orders.csv': len(orders_export),
        'v_tableau_customer.csv': len(cust),
        'v_tableau_monthly.csv': len(pd.read_csv(HERE / 'v_tableau_monthly.csv')),
        'cohort_retention.csv': len(cohort),
    },
    'grade_counts': expected,
}
(HERE / 'pipeline_metadata.json').write_text(
    json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8'
)
print('pipeline_metadata.json 생성 — 원본 해시·행 수·등급 분포 기록')
