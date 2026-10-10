-- 03. 데이터 개요와 구매 구조
-- 조회 전 02_data_preparation.sql의 create_* 뷰를 생성한다.
-- 모든 조회는 데이터 구성과 분포를 위한 기술 통계다.

-- name: source_columns | 적재 테이블과 분석 뷰의 컬럼·자료형
SELECT TABLE_NAME AS 테이블, ORDINAL_POSITION AS 컬럼순서,
       COLUMN_NAME AS 컬럼, DATA_TYPE AS 자료형
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('onlinesales','customers','discount','marketing','tax',
                     'orders_master','rfm_result','fa_customer_orders','fa_customer_profile')
ORDER BY FIELD(TABLE_NAME,'onlinesales','customers','discount','marketing','tax',
                            'orders_master','rfm_result','fa_customer_orders','fa_customer_profile'),
         ORDINAL_POSITION;

-- name: line_preview | 할인·세금·배송비가 결합된 상품라인 예시
SELECT 고객ID, 거래ID, 거래날짜, 제품카테고리, 쿠폰상태, 할인율, gst,
       총매출, 할인후금액, 세후금액, 배송비_배부액, 최종결제금액
FROM orders_master
ORDER BY 거래날짜, 고객ID, 거래ID
LIMIT 5;

-- name: order_preview | 고객 주문 예시
SELECT 고객ID, 거래ID, 거래날짜, 상품라인수, 상품매출, 배송비, 고객결제액
FROM fa_customer_orders
ORDER BY 거래날짜, 고객ID, 거래ID
LIMIT 5;

-- name: customer_preview | 고객 RFM·구매 이력 예시
SELECT 고객ID, 등급, 세그먼트, Recency, Frequency, Monetary,
       첫구매일, 마지막구매일, 구매일수
FROM fa_customer_profile
ORDER BY 고객ID
LIMIT 5;

-- name: category_gst | 제품카테고리별 상품라인·고객 주문·GST 구성
SELECT 제품카테고리, COUNT(*) AS 상품라인수,
       COUNT(DISTINCT 고객ID, 거래ID) AS 고객주문수,
       COUNT(DISTINCT 고객ID) AS 고객수,
       MIN(gst) AS GST_최솟값, MAX(gst) AS GST_최댓값,
       SUM(CAST(세후금액 AS DECIMAL(18,2))) AS 상품매출
FROM orders_master
GROUP BY 제품카테고리
ORDER BY 상품라인수 DESC, 제품카테고리;

-- name: customer_gender | 성별 고객 구성
SELECT 성별, COUNT(*) AS 고객수
FROM customers
GROUP BY 성별
ORDER BY 고객수 DESC;

-- name: customer_region | 고객지역별 고객 구성
SELECT 고객지역, COUNT(*) AS 고객수
FROM customers
GROUP BY 고객지역
ORDER BY 고객수 DESC;

-- name: customer_tenure | 가입기간 구간별 고객 구성
SELECT CASE
           WHEN 가입기간 BETWEEN 1 AND 12 THEN '1~12개월'
           WHEN 가입기간 BETWEEN 13 AND 24 THEN '13~24개월'
           ELSE '25개월 이상'
       END AS 가입기간구간,
       COUNT(*) AS 고객수
FROM customers
GROUP BY 가입기간구간
ORDER BY FIELD(가입기간구간,'1~12개월','13~24개월','25개월 이상');

-- name: coupon_status | 쿠폰 상태×할인정보 제공×실제 할인 적용 구성
SELECT 쿠폰상태, 할인정보제공여부, 할인적용여부,
       COUNT(*) AS 상품라인수,
       SUM(CAST(총매출 AS DECIMAL(18,2))) AS 세전상품금액,
       SUM(CAST(할인후금액 AS DECIMAL(18,2))) AS 할인후_세전금액,
       SUM(CAST(세후금액 AS DECIMAL(18,2))) AS 할인후_세후상품매출
FROM orders_master
GROUP BY 쿠폰상태, 할인정보제공여부, 할인적용여부
ORDER BY FIELD(쿠폰상태,'Used','Clicked','Not Used'), 쿠폰상태,
         할인정보제공여부, 할인적용여부;

-- name: marketing_monthly | 일별 마케팅 비용의 월별 합계
SELECT MONTH(날짜) AS 월,
       SUM(CAST(오프라인비용 AS DECIMAL(18,2))) AS 오프라인비용,
       SUM(CAST(온라인비용 AS DECIMAL(18,2))) AS 온라인비용
FROM marketing
GROUP BY MONTH(날짜)
ORDER BY 월;

-- name: order_composition | 고객 주문의 상품라인수·배송비·결제액 규모
SELECT COUNT(*) AS 고객주문수,
       SUM(상품라인수) AS 상품라인수,
       MIN(상품라인수) AS 최소상품라인수,
       AVG(상품라인수) AS 평균상품라인수,
       MAX(상품라인수) AS 최대상품라인수,
       SUM(상품매출) AS 상품매출,
       SUM(배송비) AS 배송비,
       SUM(고객결제액) AS 고객결제액
FROM fa_customer_orders;

-- name: order_size_bands | 고객 주문의 상품라인 수 구간
SELECT CASE
           WHEN 상품라인수 = 1 THEN '1개'
           WHEN 상품라인수 = 2 THEN '2개'
           ELSE '3개 이상'
       END AS 상품라인수구간,
       COUNT(*) AS 고객주문수
FROM fa_customer_orders
GROUP BY 상품라인수구간
ORDER BY FIELD(상품라인수구간,'1개','2개','3개 이상');

-- name: monthly_orders | 월별 고객 주문·고객·상품매출
SELECT MONTH(거래날짜) AS 월,
       COUNT(*) AS 고객주문수,
       COUNT(DISTINCT 고객ID) AS 고객수,
       SUM(상품매출) AS 상품매출,
       SUM(배송비) AS 배송비
FROM fa_customer_orders
GROUP BY MONTH(거래날짜)
ORDER BY 월;

-- name: order_frequency | 고객별 주문 수 분포
SELECT Frequency AS 고객주문수, COUNT(*) AS 고객수
FROM fa_customer_profile
GROUP BY Frequency
ORDER BY 고객주문수;

-- name: purchase_days | 고객별 서로 다른 구매일 수 분포
SELECT 구매일수, COUNT(*) AS 고객수
FROM fa_customer_profile
GROUP BY 구매일수
ORDER BY 구매일수;

-- name: rfm_inputs | RFM 원지표 분포·박스플롯용 고객별 값
SELECT 고객ID, Recency, Frequency, Monetary, R, F, M, RFM_score
FROM fa_customer_profile
ORDER BY 고객ID;

-- name: grade_counts | RFM 등급별 고객 수
SELECT 등급, COUNT(*) AS 고객수
FROM fa_customer_profile
GROUP BY 등급
ORDER BY FIELD(등급,'Bronze','Silver','Gold','Platinum','Diamond');

-- name: segment_counts | 행동 세그먼트별 고객 수
SELECT 세그먼트, COUNT(*) AS 고객수
FROM fa_customer_profile
GROUP BY 세그먼트
ORDER BY 고객수 DESC, 세그먼트;

-- name: grade_segment_counts | 등급×세그먼트 분포
SELECT 등급, 세그먼트, COUNT(*) AS 고객수
FROM fa_customer_profile
GROUP BY 등급, 세그먼트
ORDER BY FIELD(등급,'Bronze','Silver','Gold','Platinum','Diamond'), 고객수 DESC;
