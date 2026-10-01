-- name: bronze_rfm | Bronze 등급 고객의 RFM 점수·지표
SELECT
    고객ID, 세그먼트, Recency, Frequency, Monetary, R, F, M, RFM_score
FROM rfm_result
WHERE 등급 = 'Bronze'

-- name: visit_days_by_segment | Bronze 세그먼트별 고객 방문일수
SELECT
    r.세그먼트,
    r.고객ID,
    a.구매일수 AS 방문일수
FROM rfm_result r
JOIN customer_purchase_activity a ON r.고객ID = a.고객ID
WHERE r.등급 = 'Bronze'

-- name: visit_days_all | Bronze 전체 고객 방문일수
SELECT r.고객ID, a.구매일수 AS 방문일수
FROM rfm_result r
JOIN customer_purchase_activity a ON r.고객ID = a.고객ID
WHERE r.등급 = 'Bronze'

-- name: tier_stats | Bronze·Silver 고객의 Monetary·Frequency
SELECT 등급, 고객ID, Monetary, Frequency
FROM rfm_result
WHERE 등급 IN ('Bronze', 'Silver')

-- name: timing | Bronze 고객별 첫·마지막 구매일 + Recency
SELECT
    r.고객ID,
    r.세그먼트,
    a.첫구매일,
    a.마지막구매일,
    a.Recency
FROM rfm_result r
JOIN customer_purchase_activity a ON r.고객ID = a.고객ID
WHERE r.등급 = 'Bronze'

-- name: max_gap | Bronze 고객별 최대 구매 간격
SELECT
    a.고객ID,
    a.최대구매간격
FROM customer_purchase_activity a
JOIN rfm_result r ON a.고객ID = r.고객ID
WHERE r.등급 = 'Bronze'
    AND a.최대구매간격 IS NOT NULL
