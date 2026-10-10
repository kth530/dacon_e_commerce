# SQL 조회·검산 워크플로

[최종 분석 노트북](../notebooks/README.md)은 `data/`의 CSV를 Python으로 읽어 전처리·RFM 점수화·시각화를 수행한다. MySQL은 적재 결과를 별도로 조회하고 Python 결과와 집계 기준을 대조하는 경로다. 노트북을 읽거나 실행하는 데 SQL 서버는 필요하지 않다.

## 1. 데이터 적재

[02 데이터 준비](../notebooks/02_data_preparation.ipynb)의 `RUN_MYSQL_LOAD`를 `True`로 설정하고 프로젝트 루트의 `.env`에 `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`를 넣어 실행한다. 이 셀은 `onlinesales`, `customers`, `discount`, `marketing`, `tax`, `orders_master`, `rfm_scores`, `rfm_result`를 적재한다. `if_exists='replace'`를 사용하므로 실행 전 대상 데이터베이스를 확인한다.

기준 주문 키는 `(고객ID, 거래ID)`다. 상품매출은 할인 후·GST 포함·배송비 제외 금액이며, 배송비는 고객 주문마다 한 번 반영한다. 자세한 정의는 [지표 계약](metric_contract.md)을 따른다.

## 2. SQL 실행 순서

MySQL 8에서 [최종 SQL 폴더](../sql/README.md)의 파일을 아래 순서로 실행한다.

| 순서 | 파일 | 결과 |
|---|---|---|
| 1 | [02 데이터 준비 SQL](../sql/02_data_preparation.sql) | 원천·주문 키·금액·분류 검산, `fa_` 고객 주문·활동·월·프로파일 뷰 생성 |
| 2 | [03 데이터 개요 SQL](../sql/03_data_overview.sql) | 원천 컬럼과 결합 필드, 주문·월·등급·세그먼트 구성 조회 |
| 3 | [04 가설 검증 SQL](../sql/04_eda_validation.sql) | 다른 날 재방문, 관측 첫 구매월 복귀, 등급별 상품매출, 등급 내부 상태 조회 |

각 `-- name:` 블록은 개별 SQL 문장이다. 02의 `create_*` 뷰를 순서대로 생성한 다음 03·04를 실행한다. SQL 클라이언트에서 파일 전체를 실행해도 조회 결과가 순서대로 나온다. 뷰는 적재 테이블을 삭제하거나 교체하지 않는다.

R·F·M 점수, PCA 가중치, 등급·세그먼트는 노트북에서 만든다. SQL의 `fa_rfm_classified` 뷰는 적재된 `rfm_scores`에 같은 등급·세그먼트 규칙을 적용해 `rfm_result`와 대조한다. SQL 집계는 원시 수와 금액을 유지하고, 표시용 반올림과 차트는 노트북에서 처리한다.

## 3. 전체 실행과 Tableau

프로젝트 루트에서 `python scripts/run_pipeline.py`를 실행하면 노트북 02→03→04가 순서대로 실행된다. `--dry-run`은 실행 대상만 확인한다. MySQL 적재는 노트북의 `RUN_MYSQL_LOAD` 설정에 따른다.

Tableau CSV는 프로젝트 루트에서 `python tableau/export_csv.py`를 실행해 생성한다. 추출 코드는 최종 02 노트북의 Python 분석 테이블과 03·04의 필요한 셀을 이용한다. MySQL 적재는 필요하지 않으며, 이미 적재한 DB와 대조하려면 `--verify-mysql`을 추가한다. 주문 수는 고객ID와 거래ID의 조합으로 세고, 주문라인 CSV의 `고객주문키`를 Tableau 계산에 사용한다. CSV 계약과 워크북 수정 사항은 [Tableau 안내](../tableau/README.md)를 참고한다.
