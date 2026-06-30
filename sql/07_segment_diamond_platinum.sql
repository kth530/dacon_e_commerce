-- name: purchase_cycle | Diamond·Platinum 고객의 연속 구매일 간격(구매 사이클)
WITH daily AS (
    SELECT DISTINCT
        고객ID,
        DATE(거래날짜) AS 구매일
    FROM orders_master
),
ranked AS (
    SELECT
        고객ID,
        구매일,
        ROW_NUMBER() OVER (PARTITION BY 고객ID ORDER BY 구매일) AS rn
    FROM daily
)
SELECT
    r1.고객ID,
    rr.등급,
    DATEDIFF(r2.구매일, r1.구매일) AS 구매_사이클
FROM ranked r1
JOIN ranked r2
    ON r2.고객ID = r1.고객ID
    AND r1.rn + 1 = r2.rn
JOIN rfm_result rr
    ON rr.고객ID = r1.고객ID
WHERE rr.등급 IN ('Diamond', 'Platinum')

-- name: dp_orders | Diamond·Platinum 거래 내역
SELECT
    o.고객ID,
    o.거래ID,
    o.거래날짜,
    o.제품카테고리,
    o.세후금액,
    r.등급
FROM orders_master o
JOIN rfm_result r ON o.고객ID = r.고객ID
WHERE r.등급 IN ('Diamond', 'Platinum')
ORDER BY o.거래날짜

-- name: coupon_by_grade | 등급별 쿠폰 사용 거래수/총 거래수
WITH tx_coupon AS (
    SELECT
        고객ID,
        거래ID,
        MAX(CASE WHEN 쿠폰상태 = 'Used' THEN 1 ELSE 0 END) AS 쿠폰사용
    FROM orders_master
    GROUP BY 고객ID, 거래ID
)
SELECT
    r.등급,
    SUM(t.쿠폰사용) AS 쿠폰_거래수,
    COUNT(*) AS 총_거래수
FROM tx_coupon t
JOIN rfm_result r ON t.고객ID = r.고객ID
WHERE r.등급 IN ('Diamond', 'Platinum')
GROUP BY r.등급

-- name: coupon_by_category | 등급·카테고리별 쿠폰 사용 (거래 100건 초과만)
SELECT
    r.등급,
    o.제품카테고리,
    SUM(CASE WHEN o.쿠폰상태 = 'Used' THEN 1 ELSE 0 END) AS 쿠폰사용_건수,
    COUNT(*) AS 총_건수
FROM orders_master o
JOIN rfm_result r ON o.고객ID = r.고객ID
WHERE r.등급 IN ('Diamond', 'Platinum')
GROUP BY r.등급, o.제품카테고리
HAVING 총_건수 > 100
ORDER BY 총_건수 DESC

-- name: platinum_recency | Platinum 고객별 Recency·구매일수·총구매금액
SELECT
    o.고객ID,
    DATEDIFF('2019-12-31', MAX(o.거래날짜)) AS Recency,
    COUNT(DISTINCT DATE(o.거래날짜)) AS 구매일수,
    ROUND(SUM(o.세후금액), 0) AS 총구매금액
FROM orders_master o
JOIN rfm_result r ON o.고객ID = r.고객ID
WHERE r.등급 = 'Platinum'
GROUP BY o.고객ID

-- name: max_gap_platinum | Platinum 고객별 최대 구매 간격
WITH 구매일목록 AS (
    SELECT
        o.고객ID,
        DATE(o.거래날짜) AS 구매일
    FROM orders_master o
    JOIN rfm_result r ON o.고객ID = r.고객ID
    WHERE r.등급 = 'Platinum'
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

-- name: first_category | 고객별 첫 구매일 주력 카테고리 + 등급
WITH first_dates AS (
    SELECT
        고객ID,
        MIN(거래날짜) AS 첫_구매일
    FROM orders_master
    GROUP BY 고객ID
),
first_day_amounts AS (
    SELECT
        o.고객ID,
        o.제품카테고리,
        SUM(o.세후금액) AS 카테고리_금액
    FROM orders_master o
    JOIN first_dates f
        ON o.고객ID = f.고객ID
        AND o.거래날짜 = f.첫_구매일
    GROUP BY o.고객ID, o.제품카테고리
),
ranked AS (
    SELECT
        고객ID,
        제품카테고리,
        ROW_NUMBER() OVER (
            PARTITION BY 고객ID
            ORDER BY 카테고리_금액 DESC, 제품카테고리 ASC
        ) AS rn
    FROM first_day_amounts
)
SELECT
    r.고객ID,
    r.제품카테고리 AS 첫_카테고리,
    g.등급
FROM ranked r
JOIN rfm_result g ON r.고객ID = g.고객ID
WHERE r.rn = 1

-- name: first_category_agg | 첫 구매 카테고리별 전체·DP 고객수 (비율·전환율은 Python)
WITH first_dates AS (
    SELECT
        고객ID,
        MIN(거래날짜) AS 첫_구매일
    FROM orders_master
    GROUP BY 고객ID
),
first_day_amounts AS (
    SELECT
        o.고객ID,
        o.제품카테고리,
        SUM(o.세후금액) AS 카테고리_금액
    FROM orders_master o
    JOIN first_dates f
        ON o.고객ID = f.고객ID
        AND o.거래날짜 = f.첫_구매일
    GROUP BY o.고객ID, o.제품카테고리
),
ranked AS (
    SELECT
        고객ID,
        제품카테고리,
        ROW_NUMBER() OVER (
            PARTITION BY 고객ID
            ORDER BY 카테고리_금액 DESC, 제품카테고리 ASC
        ) AS rn
    FROM first_day_amounts
),
first_cat AS (
    SELECT
        r.고객ID,
        r.제품카테고리 AS 첫_카테고리,
        g.등급
    FROM ranked r
    JOIN rfm_result g ON r.고객ID = g.고객ID
    WHERE r.rn = 1
)
SELECT
    첫_카테고리,
    COUNT(*) AS 전체_고객수,
    SUM(CASE WHEN 등급 IN ('Diamond', 'Platinum') THEN 1 ELSE 0 END) AS DP_고객수
FROM first_cat
GROUP BY 첫_카테고리
