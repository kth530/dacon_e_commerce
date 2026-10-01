-- name: silver_rfm | Silver 등급 고객의 RFM 점수·지표
SELECT
    고객ID, 세그먼트, Recency, Frequency, Monetary, R, F, M, RFM_score
FROM rfm_result
WHERE 등급 = 'Silver'

-- name: visit_days_by_segment | Silver 세그먼트별 고객 방문일수
SELECT
    r.세그먼트,
    r.고객ID,
    a.구매일수 AS 방문일수
FROM rfm_result r
JOIN customer_purchase_activity a ON r.고객ID = a.고객ID
WHERE r.등급 = 'Silver'

-- name: timing | Silver 고객별 첫·마지막 구매일 + Recency
SELECT
    r.고객ID,
    r.세그먼트,
    a.첫구매일,
    a.마지막구매일,
    a.Recency
FROM rfm_result r
JOIN customer_purchase_activity a ON r.고객ID = a.고객ID
WHERE r.등급 = 'Silver'

-- name: max_gap | Silver 고객별 최대 구매 간격
SELECT
    a.고객ID,
    a.최대구매간격
FROM customer_purchase_activity a
JOIN rfm_result r ON a.고객ID = r.고객ID
WHERE r.등급 = 'Silver'
    AND a.최대구매간격 IS NOT NULL

-- name: silver_monetary | Silver 고객 Monetary (놓치면 안될 고객 제외)
SELECT
    세그먼트,
    Monetary
FROM rfm_result
WHERE 등급 = 'Silver'
    AND 세그먼트 != '놓치면 안될 고객'
