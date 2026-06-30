"""Tableau 데이터 소스 CSV 추출 파이프라인.

tableau_views.sql 의 VIEW를 생성한 뒤 SELECT 결과를 CSV로 내보낸다.
코호트 리텐션은 SQL 미지원(피벗)이라 pandas로 별도 생성한다.
Tableau Public은 MySQL 라이브 연결이 안 되므로 이 CSV를 데이터 소스로 연결한다.

실행: python tableau/export_csv.py
"""
import os
import re
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

HERE = Path(__file__).resolve().parent
load_dotenv(HERE.parent / '.env')

engine = create_engine(
    f"mysql+mysqlconnector://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}"
    f"@{os.getenv('DB_HOST')}/{os.getenv('DB_NAME')}"
)


def load_queries(path):
    """`-- name: 이름 | 설명` 마커로 SQL을 쪼개 {이름: 쿼리}로 반환."""
    body = Path(path).read_text(encoding='utf-8')
    parts = re.split(r'(?m)^--\s*name:\s*(\w+).*$', body)
    return {parts[i]: parts[i + 1].strip() for i in range(1, len(parts), 2)}


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
    df.to_csv(HERE / fname, index=False, encoding='utf-8-sig')
    print(f'{fname:26s} {len(df):>6,}행 x {df.shape[1]}열')

# 3) 코호트 리텐션 (Python 피벗 → long 포맷, Tableau 히트맵용)
orders = pd.read_sql(
    "SELECT 고객ID, DATE(거래날짜) AS 구매일 FROM orders_master",
    engine,
    parse_dates=['구매일'],
)
orders['구매월'] = orders['구매일'].dt.month
first_month = orders.groupby('고객ID')['구매월'].min().rename('코호트월')
orders = orders.merge(first_month, on='고객ID')
orders['경과월'] = orders['구매월'] - orders['코호트월']

cohort = (
    orders.groupby(['코호트월', '경과월'])['고객ID']
    .nunique()
    .reset_index(name='고객수')
)
size = cohort[cohort['경과월'] == 0].set_index('코호트월')['고객수']
cohort['코호트크기'] = cohort['코호트월'].map(size)
cohort['리텐션율'] = (cohort['고객수'] / cohort['코호트크기'] * 100).round(1)
cohort = cohort.sort_values(['코호트월', '경과월']).reset_index(drop=True)
cohort.to_csv(HERE / 'cohort_retention.csv', index=False, encoding='utf-8-sig')
print(f"{'cohort_retention.csv':26s} {len(cohort):>6,}행 x {cohort.shape[1]}열")

# 4) 검증
cust = pd.read_csv(HERE / 'v_tableau_customer.csv')
assert len(cust) == 1468, f'고객수 불일치: {len(cust)}'
grade = cust['등급'].value_counts().to_dict()
expected = {'Bronze': 699, 'Silver': 314, 'Gold': 243, 'Platinum': 154, 'Diamond': 58}
assert grade == expected, f'등급 분포 불일치: {grade}'
print('\n검증 통과 — 고객 1,468명, 등급 분포 일치:', expected)
