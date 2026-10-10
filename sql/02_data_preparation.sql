-- 02. 데이터 전처리와 고객 분류
-- MySQL 8. 02 노트북의 MySQL 적재가 끝난 뒤 실행한다.
-- Python: CSV 정제·조인, RFM 분위 점수, 군집 보조 탐색, PCA 가중치.
-- SQL: 적재 검증, 분류 규칙 대조, 분석 단위 뷰.

-- name: source_counts | 적재 테이블별 행 수
SELECT 'onlinesales' AS 테이블, COUNT(*) AS 행수 FROM onlinesales
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'discount', COUNT(*) FROM discount
UNION ALL SELECT 'marketing', COUNT(*) FROM marketing
UNION ALL SELECT 'tax', COUNT(*) FROM tax
UNION ALL SELECT 'orders_master', COUNT(*) FROM orders_master
UNION ALL SELECT 'rfm_scores', COUNT(*) FROM rfm_scores
UNION ALL SELECT 'rfm_result', COUNT(*) FROM rfm_result;

-- name: line_quality | 상품라인 날짜·결합 필드·금액 확인
SELECT COUNT(*) AS 상품라인수,
       MIN(DATE(거래날짜)) AS 시작일, MAX(DATE(거래날짜)) AS 종료일,
       SUM(고객ID IS NULL OR 거래ID IS NULL OR 거래날짜 IS NULL) AS 주문키_결측행,
       SUM(제품카테고리 IS NULL OR gst IS NULL OR 성별 IS NULL
           OR 오프라인비용 IS NULL) AS 결합필드_결측행,
       SUM(할인율 IS NULL OR 세후금액 IS NULL OR 최종결제금액 IS NULL) AS 계산필드_결측행,
       SUM(CAST(세후금액 AS DECIMAL(18,2))) AS 상품매출,
       SUM(CAST(배송비_배부액 AS DECIMAL(18,2))) AS 배송비_배부액,
       SUM(CAST(최종결제금액 AS DECIMAL(18,2))) AS 고객결제액
FROM orders_master;

-- name: order_key_quality | 고객 주문 내 날짜·배송비 일관성과 배송비 1회 배부
SELECT COUNT(*) AS 고객주문수,
       SUM(날짜종류수 <> 1) AS 날짜불일치_주문수,
       SUM(배송료종류수 <> 1) AS 배송료불일치_주문수,
       SUM(ABS(배송비_배부합 - 거래배송비) > 0.01) AS 배송비배부불일치_주문수,
       SUM(ABS(고객결제합 - 상품매출합 - 거래배송비) > 0.01) AS 결제액불일치_주문수
FROM (
    SELECT 고객ID, 거래ID,
           COUNT(DISTINCT DATE(거래날짜)) AS 날짜종류수,
           COUNT(DISTINCT 배송료) AS 배송료종류수,
           SUM(세후금액) AS 상품매출합,
           MAX(거래_배송비) AS 거래배송비,
           SUM(배송비_배부액) AS 배송비_배부합,
           SUM(최종결제금액) AS 고객결제합
    FROM orders_master
    GROUP BY 고객ID, 거래ID
) q;

-- name: create_customer_orders | 고객ID×거래ID당 한 행
CREATE OR REPLACE VIEW fa_customer_orders AS
SELECT 고객ID, 거래ID,
       MIN(DATE(거래날짜)) AS 거래날짜,
       COUNT(*) AS 상품라인수,
       SUM(CAST(세후금액 AS DECIMAL(18,2))) AS 상품매출,
       CAST(MAX(거래_배송비) AS DECIMAL(18,2)) AS 배송비,
       SUM(CAST(최종결제금액 AS DECIMAL(18,2))) AS 고객결제액
FROM orders_master
GROUP BY 고객ID, 거래ID;

-- name: create_customer_activity | 고객별 첫·마지막 구매일, 주문수와 구매일수
CREATE OR REPLACE VIEW fa_customer_activity AS
SELECT 고객ID,
       MIN(DATE(거래날짜)) AS 첫구매일,
       MAX(DATE(거래날짜)) AS 마지막구매일,
       MONTH(MIN(DATE(거래날짜))) AS 관측첫구매월,
       COUNT(DISTINCT 거래ID) AS 주문수,
       COUNT(DISTINCT DATE(거래날짜)) AS 구매일수,
       DATEDIFF('2019-12-31', MAX(DATE(거래날짜))) AS Recency
FROM orders_master
GROUP BY 고객ID;

-- name: create_customer_month | 고객×구매월당 한 행
CREATE OR REPLACE VIEW fa_customer_month AS
SELECT DISTINCT 고객ID, MONTH(거래날짜) AS 구매월
FROM orders_master;

-- name: create_rfm_classified | 점수 테이블에 동일한 등급·세그먼트 규칙 적용
CREATE OR REPLACE VIEW fa_rfm_classified AS
SELECT 고객ID, R, F, M, RFM_score, Recency, Frequency, Monetary,
       CASE
           WHEN RFM_score >= 95 THEN 'Diamond'
           WHEN RFM_score >= 80 THEN 'Platinum'
           WHEN RFM_score >= 65 THEN 'Gold'
           WHEN RFM_score >= 50 THEN 'Silver'
           ELSE 'Bronze'
       END AS 등급,
       CASE
           WHEN CONCAT(R,F,M) IN ('555','554','544','545','454','455','445') THEN 'VIP 고객'
           WHEN CONCAT(R,F,M) IN ('543','444','435','355','354','345','344','335') THEN '충성 고객'
           WHEN CONCAT(R,F,M) IN ('553','551','552','541','542','533','532','531',
                '452','451','442','441','431','453','433','432','423','353','352',
                '351','342','341','333','323') THEN '잠재 충성 고객'
           WHEN CONCAT(R,F,M) IN ('512','511','422','421','412','411','311') THEN '최근·저빈도 고객'
           WHEN CONCAT(R,F,M) IN ('525','524','523','522','521','515','514','513',
                '425','424','413','414','415','315','314','313') THEN '가망 고객'
           WHEN CONCAT(R,F,M) IN ('535','534','443','434','343','334','325','324') THEN '관심 필요 고객'
           WHEN CONCAT(R,F,M) IN ('331','321','312','221','213','231','241','251') THEN '이탈 조짐 고객'
           WHEN CONCAT(R,F,M) IN ('155','154','144','214','215','115','114','113') THEN '놓치면 안될 고객'
           WHEN CONCAT(R,F,M) IN ('255','254','245','244','253','252','243','242',
                '235','234','225','224','153','152','145','143','142','135','134',
                '133','125','124') THEN '이탈 위험 고객'
           WHEN CONCAT(R,F,M) IN ('332','322','233','232','223','222','132',
                '123','122','212','211') THEN '휴면 고객'
           WHEN CONCAT(R,F,M) IN ('111','112','121','131','141','151') THEN '이탈 고객'
           ELSE 'Others'
       END AS 세그먼트
FROM rfm_scores;

-- name: classification_quality | Python 적재 결과와 SQL 분류 일치 여부
SELECT COUNT(*) AS 고객수,
       SUM(NOT (r.등급 <=> c.등급)) AS 등급불일치_고객수,
       SUM(NOT (r.세그먼트 <=> c.세그먼트)) AS 세그먼트불일치_고객수,
       SUM(c.세그먼트 = 'Others') AS 미분류_고객수,
       SUM(NOT (r.Recency <=> c.Recency)
           OR NOT (r.Frequency <=> c.Frequency)
           OR ABS(r.Monetary - c.Monetary) > 0.01) AS RFM원지표불일치_고객수
FROM rfm_result r
JOIN fa_rfm_classified c ON r.고객ID = c.고객ID;

-- name: customer_key_quality | RFM 테이블의 고객 키 중복·구매 이력 누락
SELECT (SELECT COUNT(*) - COUNT(DISTINCT 고객ID) FROM rfm_scores) AS 점수테이블_중복고객수,
       (SELECT COUNT(*) - COUNT(DISTINCT 고객ID) FROM rfm_result) AS 결과테이블_중복고객수,
       (SELECT COUNT(*) FROM rfm_result r LEFT JOIN fa_customer_activity a
        ON r.고객ID = a.고객ID WHERE a.고객ID IS NULL) AS 구매이력_누락고객수;

-- name: create_customer_profile | 세 가설에서 공통 사용하는 고객 1명당 1행
CREATE OR REPLACE VIEW fa_customer_profile AS
SELECT r.고객ID, r.등급, r.세그먼트, r.R, r.F, r.M, r.RFM_score,
       r.Recency, r.Frequency, r.Monetary,
       a.첫구매일, a.마지막구매일, a.관측첫구매월,
       a.주문수, a.구매일수,
       (a.구매일수 > 1) AS 다른날재방문,
       (a.관측첫구매월 < 12) AS 다음달관찰가능,
       (a.관측첫구매월 < 12 AND m.고객ID IS NOT NULL) AS 첫구매월_1개월복귀,
       (r.Recency > 90) AS 장기미방문_90일예시
FROM rfm_result r
JOIN fa_customer_activity a ON r.고객ID = a.고객ID
LEFT JOIN fa_customer_month m
  ON r.고객ID = m.고객ID AND m.구매월 = a.관측첫구매월 + 1;

-- name: grain_reconciliation | 상품라인·고객 주문·고객 단위 총량
SELECT (SELECT COUNT(*) FROM orders_master) AS 상품라인수,
       (SELECT COUNT(*) FROM fa_customer_orders) AS 고객주문수,
       (SELECT COUNT(*) FROM fa_customer_profile) AS 고객수,
       (SELECT SUM(상품매출) FROM fa_customer_orders) AS 상품매출,
       (SELECT SUM(배송비) FROM fa_customer_orders) AS 배송비,
       (SELECT SUM(고객결제액) FROM fa_customer_orders) AS 고객결제액,
       (SELECT SUM(Frequency) FROM fa_customer_profile) AS Frequency합계,
       (SELECT SUM(다른날재방문) FROM fa_customer_profile) AS 다른날재방문고객수,
       (SELECT SUM(다음달관찰가능) FROM fa_customer_profile) AS 다음달관찰가능고객수,
       (SELECT SUM(첫구매월_1개월복귀) FROM fa_customer_profile) AS 다음달복귀고객수;
