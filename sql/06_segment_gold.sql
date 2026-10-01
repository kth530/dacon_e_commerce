-- name: gold_rfm | Gold 등급 고객의 RFM 점수·지표
SELECT
    고객ID, 세그먼트, Recency, Frequency, Monetary, R, F, M, RFM_score
FROM rfm_result
WHERE 등급 = 'Gold'

-- name: visit_days_all | Gold 전체 고객 방문일수
SELECT
    a.고객ID,
    a.구매일수 AS 방문일수
FROM customer_purchase_activity a
JOIN rfm_result r ON a.고객ID = r.고객ID
WHERE r.등급 = 'Gold'

-- name: timing | Gold 고객별 첫·마지막 구매일 + Recency
SELECT
    a.고객ID,
    a.첫구매일,
    a.마지막구매일,
    a.Recency
FROM customer_purchase_activity a
JOIN rfm_result r ON a.고객ID = r.고객ID
WHERE r.등급 = 'Gold'

-- name: max_gap | Gold 고객별 최대 구매 간격
SELECT
    a.고객ID,
    a.최대구매간격
FROM customer_purchase_activity a
JOIN rfm_result r ON a.고객ID = r.고객ID
WHERE r.등급 = 'Gold'
    AND a.최대구매간격 IS NOT NULL
