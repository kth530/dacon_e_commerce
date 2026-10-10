# 고객 등급별 가치와 리텐션 분석

공개 이커머스 거래 데이터를 이용해 고객 재방문, 가치 등급, 같은 등급 내부의 구매 상태를 살펴본 포트폴리오 분석이다.

## 읽는 순서

1. [문제 정의와 가설](01_problem_hypothesis.md)
2. [데이터 준비](02_data_preparation.ipynb)
3. [데이터 개요](03_data_overview.ipynb)
4. [가설 검증과 판단](04_eda_validation.ipynb)

노트북은 프로젝트의 `data/` CSV와 02의 Python 전처리 코드로 실행된다. 03·04의 시작 셀은 02의 전처리 코드를 실행해 분석 테이블을 준비한다.

프로젝트 루트의 [실행 스크립트](../scripts/run_pipeline.py)는 02→03→04를 순서대로 실행한다. `--dry-run`으로 실행 대상만 확인할 수 있다.

MySQL에 적재한 결과를 별도로 조회·검산하는 SQL은 [SQL 안내](../sql/README.md)에 정리했다. 노트북 실행에는 MySQL이나 SQL 파일이 필요하지 않다.
