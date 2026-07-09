# Dacon 이커머스 고객 분석

온라인 커머스 1년치(2019) 거래 데이터를 기반으로 고객 구매 패턴, 리텐션, RFM 등급을 분석하고, 등급별 고객 관리 우선순위를 도출한 데이터 분석 프로젝트.

---

## 프로젝트 배경

**왜 이 분석을 시작했나**  
CRM/마케팅팀으로부터 "고객 재구매율을 높이기 위해 어떤 고객군을 우선 관리해야 하는가"라는 분석 요청을 받았다는 상황을 가정했다. 단순히 매출이 높은 카테고리나 고객을 찾는 것보다, 고객이 언제 이탈하고 어떤 등급에서 전환 가능성이 있는지 확인하는 것이 핵심이었다.

**어떻게 풀었나**  
원본 거래 데이터를 정제해 고객 단위 분석 테이블을 만들고, ① EDA로 매출·고객·카테고리 구조 파악 → ② 코호트 리텐션으로 재구매 흐름 확인 → ③ RFM 점수화와 등급 배정 → ④ Bronze/Silver/Gold/Diamond·Platinum 등급별 심층 분석 순서로 진행했다.

**그래서, 무엇을 알게 됐나**  
전체 매출은 상위 고객군과 특정 카테고리에 집중되어 있었지만, 리텐션 관점에서는 첫 구매 이후 이탈 방어와 등급별 재참여 타이밍이 더 중요한 과제로 나타났다. 개선 우선순위는 다음처럼 정리된다.

| 우선순위 | 무엇을 | 근거 |
|---|---|---|
| 1 | 신규·Bronze 고객의 2차 구매 유도 | 전체 코호트 리텐션이 낮고 첫 구매 직후 이탈 방어가 중요 |
| 2 | Silver·Gold 이탈 위험 고객 재참여 | 최근 구매가 줄었어도 구매금액이 높은 고객군 존재 |
| 3 | Platinum·Diamond 고객 유지 전략 | 상위 2등급이 전체 고객의 약 14%지만 매출의 약 48% 담당 |

> 데이터가 2019년 1개년 기준이므로 계절성 반복 여부와 캠페인 효과는 다년도 데이터와 실제 캠페인 실험으로 재검증이 필요하다.

---

## Tableau 대시보드

RFM 등급 분석 결과를 인터랙티브 대시보드로 시각화했다. 등급 분포 차트에서 등급을 선택하면 KPI·매출 추이·카테고리·행동 세그먼트·코호트 리텐션이 해당 등급 기준으로 갱신되고, 등급 분포·비중 차트는 전 등급 비교 기준으로 고정된다.

🔗 **[Tableau Public에서 대시보드 보기](https://public.tableau.com/app/profile/.16528220/viz/_17835946862180/sheet14)**

**주요 인터랙션**
- 등급 분포 파이 클릭 → 반응 차트가 선택 등급으로 필터되고 KPI 제목·수치가 동적으로 갱신된다.
- 코호트 리텐션을 등급별로 재생성해, 등급 선택 시 해당 등급의 리텐션을 표시한다.
- 등급 분포·등급별 비중은 필터 대신 하이라이트로 선택 등급을 강조한다.

대시보드 산출용 CSV와 워크북은 로컬 작업 산출물로 관리하며, 공개 저장소에는 데이터 소스 구성 코드 중심으로 남긴다.

| 파일 | 역할 |
|------|------|
| [`tableau/tableau_views.sql`](tableau/tableau_views.sql) | Tableau용 고객·주문·월별 뷰 정의 |
| [`tableau/export_csv.py`](tableau/export_csv.py) | Tableau 입력용 CSV 추출 (등급별 코호트 포함) |

---

## 폴더 구조

```text
dacon_e_commerce/
├── README.md
├── docs/           # RFM 방법론·SQL/Python 역할 분리
├── notebooks/      # 00-08 분석 노트북
├── sql/            # 02-07 분석 쿼리
├── tableau/        # Tableau 데이터 소스 구성 코드
└── data/           # 원본 CSV, 저장소 제외
```

---

## 데이터 개요

| 항목 | 내용 |
|------|------|
| 데이터 출처 | [Dacon 이커머스 데이터셋](https://dacon.io/competitions/official/236222/data) |
| 분석 기간 | 2019-01-01 ~ 2019-12-31 |
| 고객 수 | 1,468명 |
| 거래 원천 | 온라인 주문, 고객 정보, 할인 정보, 마케팅 비용, 세금 정보 |
| 금액 단위 | 달러($) |

| 파일 | 행 수 | 주요 컬럼 |
|------|------:|----------|
| `Onlinesales_info.csv` | 52,924 | 고객ID, 거래ID, 거래날짜, 제품카테고리, 수량, 평균금액, 배송료, 쿠폰상태 |
| `Customer_info.csv` | 1,468 | 고객ID, 성별, 고객지역, 가입기간 |
| `Discount_info.csv` | 204 | 월, 제품카테고리, 쿠폰코드, 할인율 |
| `Marketing_info.csv` | 365 | 날짜, 오프라인비용, 온라인비용 |
| `Tax_info.csv` | 20 | 제품카테고리, GST |

> 원본 CSV, 로컬 환경 변수, Tableau 추출 CSV, Tableau 워크북은 공개 저장소에 포함하지 않는다.

---

## 핵심 인사이트

1. **매출은 소수 카테고리와 상위 고객군에 집중되어 있다** - Nest-USA 단일 카테고리가 전체 매출의 약 54%를 차지하고, Diamond/Platinum은 전체 고객의 약 14%지만 매출의 약 48%를 담당한다. ([01 EDA](notebooks/01_eda.ipynb), [03 RFM](notebooks/03_rfm_segmentation.ipynb))
2. **첫 구매 이후 이탈 방어가 핵심 과제다** - 전체 코호트 리텐션은 낮고, +1개월 복귀율이 전 구간에서 낮게 나타난다. ([02 Retention](notebooks/02_retention.ipynb))
3. **고객 가치는 Recency만으로 설명되지 않는다** - Silver, Gold, Platinum에서 최근 구매가 줄어든 고객 중에도 구매금액이 높은 고객군이 확인된다. ([05 Silver](notebooks/05_segment_silver.ipynb), [06 Gold](notebooks/06_segment_gold.ipynb), [07 Diamond·Platinum](notebooks/07_segment_diamond_platinum.ipynb))
4. **등급별 관리 질문이 다르다** - Bronze는 재활성화, Silver는 Gold 전환, Gold는 이탈 방어와 Platinum 전환, Diamond/Platinum은 유지 전략이 핵심이다. ([04 Bronze](notebooks/04_segment_bronze.ipynb), [05 Silver](notebooks/05_segment_silver.ipynb), [06 Gold](notebooks/06_segment_gold.ipynb), [07 Diamond·Platinum](notebooks/07_segment_diamond_platinum.ipynb))
5. **단일 캠페인보다 세그먼트별 타이밍 분리가 필요하다** - 이탈 시점과 전환 가능성이 등급·세그먼트마다 다르게 나타난다. ([04 Bronze](notebooks/04_segment_bronze.ipynb), [05 Silver](notebooks/05_segment_silver.ipynb), [06 Gold](notebooks/06_segment_gold.ipynb))

---

## 추천 액션

분석 결과를 등급·세그먼트별 상태에 맞춘 실행 우선순위로 정리했다. 전체 고객 대상 일괄 캠페인보다 메시지·타이밍·혜택을 분리하는 방향이 적합하다.

| 우선순위 | 대상 | 액션 방향 |
|----------|------|-----------|
| 1 | 신규·Bronze 고객 | 첫 구매 후 14-30일 내 2차 구매 리마인더 |
| 2 | Bronze 휴면 고객 | 마지막 구매 후 90-150일 구간 재활성화 캠페인 |
| 3 | Silver 잠재 충성 고객 | Gold 전환 진행률 알림과 F/M 부스터 |
| 4 | Gold 이탈 위험군 | 7-8월 이탈 집중 전 선제 접촉 |
| 5 | Platinum 이탈 조짐 고객 | 과거 구매 품목 기반 개인화 재참여 |
| 6 | Diamond 고객 | 할인보다 전용 혜택과 등급 유지 경험 강화 |

등급별 상세 근거는 심층 분석 노트북([04 Bronze](notebooks/04_segment_bronze.ipynb) · [05 Silver](notebooks/05_segment_silver.ipynb) · [06 Gold](notebooks/06_segment_gold.ipynb) · [07 Diamond·Platinum](notebooks/07_segment_diamond_platinum.ipynb))에, 전체 요약은 [08 프로젝트 요약](notebooks/08_project_summary.ipynb)에 정리했다.

---

## 분석 구조

| 번호 | 노트북 | 내용 |
|------|--------|------|
| 00 | [`00_etl_pipeline.ipynb`](notebooks/00_etl_pipeline.ipynb) | 원본 5개 테이블 정제, 조인, `orders_master` 생성 |
| 01 | [`01_eda.ipynb`](notebooks/01_eda.ipynb) | 매출, 카테고리, 고객, 쿠폰, 마케팅, 지역, 요일, 장바구니 분석 |
| 02 | [`02_retention.ipynb`](notebooks/02_retention.ipynb) | 코호트 리텐션, 마케팅 비용, 카테고리별 재구매율 |
| 03 | [`03_rfm_segmentation.ipynb`](notebooks/03_rfm_segmentation.ipynb) | RFM 점수화, PCA 가중치, 등급/세그먼트 배정 |
| 04 | [`04_segment_bronze.ipynb`](notebooks/04_segment_bronze.ipynb) | Bronze 고객 재활성화와 Silver 전환 가능성 |
| 05 | [`05_segment_silver.ipynb`](notebooks/05_segment_silver.ipynb) | Silver 고객 이탈 구조와 Gold 전환 가능성 |
| 06 | [`06_segment_gold.ipynb`](notebooks/06_segment_gold.ipynb) | Gold 고객 이탈 위험과 Platinum 전환 경로 |
| 07 | [`07_segment_diamond_platinum.ipynb`](notebooks/07_segment_diamond_platinum.ipynb) | Diamond/Platinum 고객 재구매 패턴과 유지 전략 |
| 08 | [`08_project_summary.ipynb`](notebooks/08_project_summary.ipynb) | 파일별 핵심 인사이트·등급별 액션 요약 |

**워크플로**: Python에서 정제·점수화·시각화를 수행하고, SQL은 분석용 조회·집계·등급/세그먼트 분류를 담당한다. 노트북은 `load_queries()`로 `sql/` 폴더의 쿼리를 이름 호출한다.

RFM 점수화와 등급 기준은 [`docs/methodology.md`](docs/methodology.md), SQL/Python 역할 분리는 [`docs/sql_workflow.md`](docs/sql_workflow.md)에 정리했다.

---

## 기술 스택

![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=flat-square&logo=mysql&logoColor=white)
![Tableau](https://img.shields.io/badge/Tableau-E97627?style=flat-square&logo=tableau&logoColor=white)

---

## 열람 안내

원본 데이터와 Tableau 산출 CSV는 공개 저장소에 포함하지 않는다.

- 주요 분석 결과는 렌더된 노트북에서 확인할 수 있다.
- 02-07 분석에서 사용한 SQL 쿼리는 [`sql/`](sql/) 폴더에 분리했다.
- RFM 점수화, 등급 기준, SQL/Python 역할 분리는 [`docs/`](docs/)에서 확인할 수 있다.
- 전체 요약은 [`notebooks/08_project_summary.ipynb`](notebooks/08_project_summary.ipynb)에 정리했다.

---

## 데이터 한계

- 2019년 1개년 데이터이므로 계절성 반복 여부를 단정하기 어렵다.
- Dacon 제공 데이터셋 특성상 실제 서비스 로그와 동일한 운영 환경을 완전히 반영한다고 보기는 어렵다.
- 캠페인 효율은 실제 발송 비용, 마진, 전환율이 포함된 실험 데이터가 있어야 정밀하게 평가할 수 있다.
- RFM 등급은 고객 행동을 설명하는 운영 기준이며, 최종 캠페인 우선순위는 예상 구매금액·재방문 가능성·비용을 함께 고려해야 한다.
