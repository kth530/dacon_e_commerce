# SQL 중심 분석 워크플로

이 프로젝트는 **추출·집계·분류는 SQL, 모델링·통계·시각화는 Python, 발표는 Tableau**로 역할을 나눈다.

## 원칙: SQL이 할 일만 SQL로

| 작업 | 담당 | 이유 |
|------|------|------|
| 집계·필터·조인·조건집계 | **SQL** | DB에서 처리하는 게 자연스럽고 빠름 |
| 분류·라벨링 (등급·세그먼트) | **SQL** (CASE WHEN, VIEW) | 비즈니스 룰을 선언적으로 한 곳에 |
| 윈도우 (LAG·ROW_NUMBER) | **SQL** | 구매 간격·순위 계산 |
| RFM 점수화 (qcut·IQR·PCA·KMeans) | **Python** | SQL이 지원하지 않는 분위/머신러닝 연산 |
| 코호트 피벗 | **Python** | 행→열 피벗은 pandas가 적합 |
| 통계 검정·회귀 (scipy) | **Python** | — |
| median 병기 집계 | **Python** | MySQL 8에 깔끔한 median 함수 없음 |
| 시각화 | **Python (Plotly)** + **Tableau** | 노트북은 분석 깊이, Tableau는 발표 |

## SQL 파일 구조

분석 노트북 02~07은 각각 짝이 되는 `sql/NN_*.sql` 파일을 가진다.
각 쿼리는 `-- name: 이름 | 설명` 마커로 구분한다.

```sql
-- name: bronze_rfm | Bronze 등급 고객의 RFM 점수·지표
SELECT 고객ID, 세그먼트, Recency, Frequency, Monetary, R, F, M, RFM_score
FROM rfm_result
WHERE 등급 = 'Bronze'
```

> `00_etl`(타입변환·적재)·`01_eda`(탐색·Plotly)는 Python 비중이 높아 인라인 유지한다.
> `02_retention`은 SQL(코호트·`curve_a/b` 추출)은 외부화하고, 코호트 피벗·`qcut`만 Python에 둔다.
> 동적 값 주입이 필요한 쿼리는 `Q['이름'].format(...)`으로 호출한다 (예: `02`의 `cohort_by_cat`).

## 노트북에서 쿼리 호출

각 노트북 setup 셀에 헬퍼가 있다:

```python
SQL_FILE = Path('../sql/04_segment_bronze.sql')

def load_queries(path):
    body = Path(path).read_text(encoding='utf-8')
    parts = re.split(r'(?m)^--\s*name:\s*(\w+).*$', body)
    return {parts[i]: parts[i + 1].strip() for i in range(1, len(parts), 2)}

Q = load_queries(SQL_FILE)

def run(name, **kwargs):      # SELECT → DataFrame
    return pd.read_sql(Q[name], engine, **kwargs)

def execute(name):           # DDL(세미콜론 구분) 실행 — VIEW·TABLE 생성
    with engine.begin() as conn:
        for stmt in [s for s in Q[name].split(';') if s.strip()]:
            conn.execute(text(stmt))
```

사용:
```python
bronze_rfm = run('bronze_rfm')
execute('create_rfm_scored_view')
```

집계를 SQL로 옮길 때 **반올림·비중은 Python에 둔다** (pandas의 banker's rounding과 MySQL ROUND의 차이로 표시값이 어긋나는 것을 방지). SQL은 원시 `COUNT/SUM/AVG`까지만 한다.

## RFM 분류는 SQL VIEW

점수화는 Python, 등급·세그먼트 분류는 SQL VIEW로 분리한다.

```
orders_master ──(Python: qcut·IQR·PCA)──▶ rfm_scores (테이블: 고객ID·R·F·M·RFM_score…)
                                                  │
                              (SQL VIEW rfm_scored: 등급·세그먼트 CASE WHEN)
                                                  │
                                          rfm_result (테이블, 04~07이 JOIN)
```

- `등급`: `RFM_score` 임계값(95/80/65/50) CASE WHEN
- `세그먼트`: `CONCAT(R,F,M)` 3자리 코드를 11종 룰에 `IN`으로 매핑 (`sql/03_rfm_segmentation.sql`)

## Tableau 파이프라인

`tableau/`는 발표용 레이어다. 노트북 Plotly를 대체하지 않고 보완한다.

```
rfm_scored / orders_master ──(tableau_views.sql)──▶ v_tableau_orders/customer/monthly
                            ──(export_csv.py)──────▶ CSV 4종 ──▶ Tableau Desktop
```

대시보드 제작에 필요한 공개 대상 코드는 `tableau/tableau_views.sql`과 `tableau/export_csv.py`에 정리한다.
