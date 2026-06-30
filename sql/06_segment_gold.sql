-- name: gold_rfm | Gold 등급 고객의 RFM 점수·지표
SELECT
    고객ID, 세그먼트, Recency, Frequency, Monetary, R, F, M, RFM_score
FROM rfm_result
WHERE 등급 = 'Gold'

-- name: visit_days_all | Gold 전체 고객 방문일수
SELECT
    o.고객ID,
    COUNT(DISTINCT DATE(o.거래날짜)) AS 방문일수
FROM orders_master o
JOIN rfm_result r ON o.고객ID = r.고객ID
WHERE r.등급 = 'Gold'
GROUP BY o.고객ID

-- name: timing | Gold 고객별 첫·마지막 구매일 + Recency
SELECT
    o.고객ID,
    DATE(MIN(o.거래날짜)) AS 첫구매일,
    DATE(MAX(o.거래날짜)) AS 마지막구매일,
    DATEDIFF('2019-12-31', MAX(DATE(o.거래날짜))) AS Recency
FROM orders_master o
JOIN rfm_result r ON o.고객ID = r.고객ID
WHERE r.등급 = 'Gold'
GROUP BY o.고객ID

-- name: max_gap | Gold 고객별 최대 구매 간격
WITH 구매일목록 AS (
    SELECT
        o.고객ID,
        DATE(o.거래날짜) AS 구매일
    FROM orders_master o
    JOIN rfm_result r ON o.고객ID = r.고객ID
    WHERE r.등급 = 'Gold'
    GROUP BY o.고객ID, DATE(o.거래날짜)
),
간격계산 AS (
    SELECT
        고객ID,
        구매일,
        LAG(구매일) OVER (PARTITION BY 고객ID ORDER BY 구매일) AS 이전구매일
    FROM 구매일목록
)
SELECT
    고객ID,
    MAX(DATEDIFF(구매일, 이전구매일)) AS 최대구매간격
FROM 간격계산
WHERE 이전구매일 IS NOT NULL
GROUP BY 고객ID
