-- name: monthly_history | 고객별 월별 구매 이력 + 첫 구매월·경과월
WITH first_purchases AS (
    SELECT
        고객ID,
        MIN(월) AS first_month
    FROM orders_master
    GROUP BY 고객ID
)
SELECT
    o.고객ID,
    o.월,
    f.first_month,
    o.월 - f.first_month AS month_diff
FROM orders_master o
LEFT JOIN first_purchases f ON o.고객ID = f.고객ID

-- name: cohort_size | 월별 코호트 크기(해당 월 첫 구매 신규 고객 수)
SELECT
    first_month AS 월,
    COUNT(DISTINCT 고객ID) AS cohort_size
FROM (
    SELECT
        고객ID,
        MIN(월) AS first_month
    FROM orders_master
    GROUP BY 고객ID
) base
GROUP BY first_month
ORDER BY first_month

-- name: first_purchase_cost | 고객별 첫 구매일 기준 채널별 마케팅비용
SELECT
    v.고객ID,
    v.온라인비용,
    v.오프라인비용,
    v.온라인비용 + v.오프라인비용 AS 총마케팅비용
FROM orders_master v
INNER JOIN (
    SELECT 고객ID, MIN(거래날짜) AS first_date
    FROM orders_master
    GROUP BY 고객ID
) f ON v.고객ID = f.고객ID AND v.거래날짜 = f.first_date
GROUP BY v.고객ID, v.온라인비용, v.오프라인비용

-- name: top_categories | 고객 수 기준 상위 5개 카테고리
SELECT 제품카테고리
FROM orders_master
GROUP BY 제품카테고리
ORDER BY COUNT(DISTINCT 고객ID) DESC
LIMIT 5

-- name: category_history | 고객-카테고리-월 이력 + 첫 구매월·경과월
WITH first_purchases AS (
    SELECT 고객ID, MIN(월) AS first_month
    FROM orders_master
    GROUP BY 고객ID
)
SELECT o.고객ID, o.월, o.제품카테고리,
       f.first_month,
       o.월 - f.first_month AS month_diff
FROM orders_master o
LEFT JOIN first_purchases f ON o.고객ID = f.고객ID

-- name: curve_a | 첫 구매월 기준 코호트 — top5 카테고리 고객의 이후 월 (전 카테고리) 재구매율
WITH first_month AS (
    SELECT
        고객ID,
        MIN(월) AS first_month
    FROM orders_master
    GROUP BY 고객ID
),
cat_counts AS (
    SELECT
        성별,
        제품카테고리,
        COUNT(DISTINCT 고객ID) AS cnt
    FROM orders_master
    GROUP BY 성별, 제품카테고리
),
top_cats AS (
    SELECT 성별, 제품카테고리
    FROM (
        SELECT 성별, 제품카테고리,
               ROW_NUMBER() OVER (
                   PARTITION BY 성별
                   ORDER BY cnt DESC
               ) AS rn
        FROM cat_counts
    ) ranked
    WHERE rn <= 5
),
cat_customers AS (
    SELECT DISTINCT o.고객ID, o.성별, o.제품카테고리, f.first_month
    FROM orders_master o
    JOIN top_cats t ON o.성별 = t.성별 AND o.제품카테고리 = t.제품카테고리
    JOIN first_month f ON o.고객ID = f.고객ID
),
lags AS (
    SELECT 1 AS 경과월 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
    UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10
),
monthly_buyers AS (
    SELECT DISTINCT 고객ID, 월
    FROM orders_master
),
eligible AS (
    SELECT
        c.성별,
        c.제품카테고리,
        l.경과월 AS 구매후_경과월,
        CASE WHEN m.고객ID IS NOT NULL THEN 1 ELSE 0 END AS 재구매
    FROM cat_customers c
    CROSS JOIN lags l
    LEFT JOIN monthly_buyers m
        ON  c.고객ID = m.고객ID
        AND m.월    = c.first_month + l.경과월
    WHERE c.first_month + l.경과월 <= 12
)
SELECT
    성별,
    제품카테고리,
    구매후_경과월,
    ROUND(AVG(재구매) * 100, 1) AS 재구매율
FROM eligible
GROUP BY 성별, 제품카테고리, 구매후_경과월
ORDER BY 성별, 제품카테고리, 구매후_경과월

-- name: curve_b | 카테고리 첫 구매월 기준 코호트 — 동일 카테고리 재구매율
WITH cat_first_month AS (
    SELECT
        고객ID,
        성별,
        제품카테고리,
        MIN(월) AS cat_first_month
    FROM orders_master
    GROUP BY 고객ID, 성별, 제품카테고리
),
cat_counts AS (
    SELECT
        성별,
        제품카테고리,
        COUNT(DISTINCT 고객ID) AS cnt
    FROM cat_first_month
    GROUP BY 성별, 제품카테고리
),
top_cats AS (
    SELECT 성별, 제품카테고리
    FROM (
        SELECT 성별, 제품카테고리,
               ROW_NUMBER() OVER (
                   PARTITION BY 성별
                   ORDER BY cnt DESC
               ) AS rn
        FROM cat_counts
    ) ranked
    WHERE rn <= 5
),
cat_purchases AS (
    SELECT DISTINCT 고객ID, 성별, 제품카테고리, 월
    FROM orders_master
),
lags AS (
    SELECT 1 AS 경과월 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
    UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10
),
eligible AS (
    SELECT
        f.성별,
        f.제품카테고리,
        l.경과월 AS 구매후_경과월,
        CASE WHEN p.고객ID IS NOT NULL THEN 1 ELSE 0 END AS 재구매
    FROM cat_first_month f
    JOIN top_cats t ON f.성별 = t.성별 AND f.제품카테고리 = t.제품카테고리
    CROSS JOIN lags l
    LEFT JOIN cat_purchases p
        ON  f.고객ID        = p.고객ID
        AND f.제품카테고리   = p.제품카테고리
        AND p.월            = f.cat_first_month + l.경과월
    WHERE f.cat_first_month + l.경과월 <= 12
)
SELECT
    성별,
    제품카테고리,
    구매후_경과월,
    ROUND(AVG(재구매) * 100, 1) AS 재구매율
FROM eligible
GROUP BY 성별, 제품카테고리, 구매후_경과월
ORDER BY 성별, 제품카테고리, 구매후_경과월

-- name: cohort_by_cat | 성별 top1 카테고리 구매 고객의 코호트 이력 ({gender}/{cat} 치환)
WITH first_purchases AS (
    SELECT 고객ID, MIN(월) AS first_month
    FROM orders_master
    GROUP BY 고객ID
),
cat_buyers AS (
    SELECT DISTINCT 고객ID
    FROM orders_master
    WHERE 성별 = '{gender}' AND 제품카테고리 = '{cat}'
)
SELECT DISTINCT o.고객ID, o.월,
       f.first_month,
       o.월 - f.first_month AS month_diff
FROM orders_master o
JOIN first_purchases f ON o.고객ID = f.고객ID
JOIN cat_buyers c ON o.고객ID = c.고객ID
WHERE o.성별 = '{gender}'
