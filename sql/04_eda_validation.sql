-- 04. 가설 검증과 판단
-- 2019년 관측값을 같은 기간에 만든 RFM 등급·세그먼트와 비교한다.
-- 비율은 분자·분모를 함께 반환한다. 미래 리텐션·캠페인 효과의 검증값이 아니다.

-- name: revisit_overall | 다른 날 재방문과 관측 첫 구매월 +1개월 복귀
SELECT COUNT(*) AS 전체고객수,
       SUM(다른날재방문) AS 다른날재방문고객수,
       SUM(다음달관찰가능) AS 첫구매월_1개월관찰가능고객수,
       SUM(첫구매월_1개월복귀) AS 첫구매월_1개월복귀고객수
FROM fa_customer_profile;

-- name: purchase_day_bands | 고객별 구매일수 구간
SELECT CASE
           WHEN 구매일수 = 1 THEN '1일(재방문 없음)'
           WHEN 구매일수 = 2 THEN '2일'
           WHEN 구매일수 BETWEEN 3 AND 5 THEN '3~5일'
           WHEN 구매일수 BETWEEN 6 AND 10 THEN '6~10일'
           ELSE '11일 이상'
       END AS 구매일수구간,
       COUNT(*) AS 고객수
FROM fa_customer_profile
GROUP BY 구매일수구간
ORDER BY FIELD(구매일수구간,'1일(재방문 없음)','2일','3~5일','6~10일','11일 이상');

-- name: revisit_by_grade | 등급별 다른 날 재방문 분자·분모
SELECT 등급, COUNT(*) AS 고객수,
       SUM(다른날재방문) AS 다른날재방문고객수
FROM fa_customer_profile
GROUP BY 등급
ORDER BY FIELD(등급,'Bronze','Silver','Gold','Platinum','Diamond');

-- name: cohort_lag | 경과월별 고객 가중 복귀 분자·관찰 가능 고객 수
WITH RECURSIVE lag_months AS (
    SELECT 1 AS 경과월
    UNION ALL
    SELECT 경과월 + 1 FROM lag_months WHERE 경과월 < 11
)
SELECT l.경과월,
       COUNT(*) AS 관찰가능고객수,
       SUM(m.고객ID IS NOT NULL) AS 복귀고객수
FROM fa_customer_profile c
JOIN lag_months l ON c.관측첫구매월 + l.경과월 <= 12
LEFT JOIN fa_customer_month m
  ON m.고객ID = c.고객ID AND m.구매월 = c.관측첫구매월 + l.경과월
GROUP BY l.경과월
ORDER BY l.경과월;

-- name: cohort_matrix | 관측 첫 구매월×경과월별 고객 수와 복귀 수
WITH RECURSIVE lag_months AS (
    SELECT 0 AS 경과월
    UNION ALL
    SELECT 경과월 + 1 FROM lag_months WHERE 경과월 < 11
)
SELECT c.관측첫구매월, l.경과월,
       COUNT(*) AS 코호트고객수,
       SUM(m.고객ID IS NOT NULL) AS 복귀고객수
FROM fa_customer_profile c
JOIN lag_months l ON c.관측첫구매월 + l.경과월 <= 12
LEFT JOIN fa_customer_month m
  ON m.고객ID = c.고객ID AND m.구매월 = c.관측첫구매월 + l.경과월
GROUP BY c.관측첫구매월, l.경과월
ORDER BY c.관측첫구매월, l.경과월;

-- name: grade_revenue | 등급별 고객 수와 배송비 제외 상품매출
SELECT 등급, COUNT(*) AS 고객수,
       SUM(CAST(Monetary AS DECIMAL(18,2))) AS 상품매출
FROM fa_customer_profile
GROUP BY 등급
ORDER BY FIELD(등급,'Bronze','Silver','Gold','Platinum','Diamond');

-- name: grade_monetary | 고객 누적 상품매출 중앙값·평균·범위
WITH ranked AS (
    SELECT 등급, Monetary,
           ROW_NUMBER() OVER (PARTITION BY 등급 ORDER BY Monetary, 고객ID) AS 순위,
           COUNT(*) OVER (PARTITION BY 등급) AS 고객수
    FROM fa_customer_profile
)
SELECT 등급, MAX(고객수) AS 고객수,
       AVG(CASE WHEN 순위 IN (FLOOR((고객수 + 1) / 2), FLOOR((고객수 + 2) / 2))
                THEN Monetary END) AS 고객별상품매출_중앙값,
       AVG(Monetary) AS 고객별상품매출_평균,
       MIN(Monetary) AS 고객별상품매출_최솟값,
       MAX(Monetary) AS 고객별상품매출_최댓값
FROM ranked
GROUP BY 등급
ORDER BY FIELD(등급,'Bronze','Silver','Gold','Platinum','Diamond');

-- name: grade_segment_mix | 등급 안의 세그먼트별 고객 수
SELECT 등급, 세그먼트, COUNT(*) AS 고객수
FROM fa_customer_profile
GROUP BY 등급, 세그먼트
ORDER BY FIELD(등급,'Bronze','Silver','Gold','Platinum','Diamond'), 고객수 DESC;

-- name: grade_segment_profile | 모든 등급·세그먼트의 구매 공백·빈도·누적 구매액 중앙값
WITH ranked AS (
    SELECT 등급, 세그먼트, 고객ID, Recency, Frequency, Monetary,
           다른날재방문, 장기미방문_90일예시,
           ROW_NUMBER() OVER (
               PARTITION BY 등급, 세그먼트 ORDER BY Recency, 고객ID
           ) AS R순위,
           ROW_NUMBER() OVER (
               PARTITION BY 등급, 세그먼트 ORDER BY Frequency, 고객ID
           ) AS F순위,
           ROW_NUMBER() OVER (
               PARTITION BY 등급, 세그먼트 ORDER BY Monetary, 고객ID
           ) AS M순위,
           COUNT(*) OVER (PARTITION BY 등급, 세그먼트) AS 고객수
    FROM fa_customer_profile
)
SELECT 등급, 세그먼트, MAX(고객수) AS 고객수,
       AVG(CASE WHEN R순위 IN (FLOOR((고객수 + 1) / 2), FLOOR((고객수 + 2) / 2))
                THEN Recency END) AS Recency_중앙값_일,
       AVG(CASE WHEN F순위 IN (FLOOR((고객수 + 1) / 2), FLOOR((고객수 + 2) / 2))
                THEN Frequency END) AS Frequency_중앙값_건,
       AVG(CASE WHEN M순위 IN (FLOOR((고객수 + 1) / 2), FLOOR((고객수 + 2) / 2))
                THEN Monetary END) AS Monetary_중앙값_달러,
       SUM(다른날재방문) AS 다른날재방문고객수,
       SUM(장기미방문_90일예시) AS 기준일_구매공백90일초과_고객수
FROM ranked
GROUP BY 등급, 세그먼트
ORDER BY FIELD(등급,'Bronze','Silver','Gold','Platinum','Diamond'), 고객수 DESC;

-- name: within_grade_points | 등급 내부 분포 차트용 고객별 원지표
SELECT 고객ID, 등급, 세그먼트, Recency, Frequency, Monetary,
       다른날재방문, 장기미방문_90일예시
FROM fa_customer_profile
ORDER BY FIELD(등급,'Bronze','Silver','Gold','Platinum','Diamond'), 세그먼트, 고객ID;

-- name: platinum_gap_states | Platinum의 현재 공백과 연중 장기 공백 후 복귀
WITH daily_purchase AS (
    SELECT DISTINCT 고객ID, 거래날짜 AS 구매일
    FROM fa_customer_orders
), purchase_sequence AS (
    SELECT 고객ID, 구매일,
           LAG(구매일) OVER (PARTITION BY 고객ID ORDER BY 구매일) AS 이전구매일
    FROM daily_purchase
), max_gap AS (
    SELECT 고객ID,
           COALESCE(MAX(DATEDIFF(구매일, 이전구매일)),0) AS 최대구매간격_일
    FROM purchase_sequence
    GROUP BY 고객ID
)
SELECT c.고객ID, c.Recency, c.구매일수, c.Monetary,
       g.최대구매간격_일,
       CASE
           WHEN c.Recency > 90 THEN '기준일 90일 초과'
           WHEN g.최대구매간격_일 > 90 THEN '장기 공백 후 복귀'
           ELSE '그 외 Platinum'
       END AS 공백상태
FROM fa_customer_profile c
JOIN max_gap g ON c.고객ID = g.고객ID
WHERE c.등급 = 'Platinum'
ORDER BY c.고객ID;
