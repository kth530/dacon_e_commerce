-- name: bronze_rfm | Bronze 등급 고객의 RFM 점수·지표
SELECT
    고객ID, 세그먼트, Recency, Frequency, Monetary, R, F, M, RFM_score
FROM rfm_result
WHERE 등급 = 'Bronze'

-- name: visit_days_by_segment | Bronze 세그먼트별 고객 방문일수
WITH visit_days AS (
    SELECT
        r.세그먼트,
        r.고객ID,
        COUNT(DISTINCT DATE(o.거래날짜)) AS 방문일수
    FROM rfm_result r
    JOIN orders_master o ON r.고객ID = o.고객ID
    WHERE r.등급 = 'Bronze'
    GROUP BY r.세그먼트, r.고객ID
)
SELECT 세그먼트, 고객ID, 방문일수
FROM visit_days

-- name: visit_days_all | Bronze 전체 고객 방문일수
WITH vd AS (
    SELECT o.고객ID, COUNT(DISTINCT DATE(o.거래날짜)) AS 방문일수
    FROM orders_master o
    JOIN rfm_result r ON o.고객ID = r.고객ID
    WHERE r.등급 = 'Bronze'
    GROUP BY o.고객ID
)
SELECT r.고객ID, v.방문일수
FROM rfm_result r
JOIN vd v ON r.고객ID = v.고객ID
WHERE r.등급 = 'Bronze'

-- name: tier_stats | Bronze·Silver 고객의 Monetary·Frequency
SELECT 등급, 고객ID, Monetary, Frequency
FROM rfm_result
WHERE 등급 IN ('Bronze', 'Silver')

-- name: timing | Bronze 고객별 첫·마지막 구매일 + Recency
SELECT
    r.고객ID,
    r.세그먼트,
    DATE(MIN(o.거래날짜)) AS 첫구매일,
    DATE(MAX(o.거래날짜)) AS 마지막구매일,
    DATEDIFF('2019-12-31', MAX(DATE(o.거래날짜))) AS Recency
FROM rfm_result r
JOIN orders_master o ON r.고객ID = o.고객ID
WHERE r.등급 = 'Bronze'
GROUP BY r.고객ID, r.세그먼트

-- name: max_gap | Bronze 고객별 최대 구매 간격
WITH 구매일목록 AS (
    SELECT o.고객ID, DATE(o.거래날짜) AS 구매일
    FROM orders_master o
    JOIN rfm_result r ON o.고객ID = r.고객ID
    WHERE r.등급 = 'Bronze'
    GROUP BY o.고객ID, DATE(o.거래날짜)
),
간격계산 AS (
    SELECT 고객ID, 구매일,
        LAG(구매일) OVER (PARTITION BY 고객ID ORDER BY 구매일) AS 이전구매일
    FROM 구매일목록
)
SELECT 고객ID, MAX(DATEDIFF(구매일, 이전구매일)) AS 최대구매간격
FROM 간격계산
WHERE 이전구매일 IS NOT NULL
GROUP BY 고객ID
