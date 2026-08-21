-- name: orders_all | 분석용 마스터 테이블 전체 로드
SELECT *
FROM orders_master

-- name: monthly_sales | 월별 총매출·거래건수·고객수
SELECT
    월,
    ROUND(SUM(세후금액), 0) AS 총매출,
    COUNT(DISTINCT 거래ID) AS 거래건수,
    COUNT(DISTINCT 고객ID) AS 고객수
FROM orders_master
GROUP BY 월
ORDER BY 월

-- name: category_sales | 카테고리별 총매출·거래건수·평균단가
SELECT
    제품카테고리,
    ROUND(SUM(세후금액), 0) AS 총매출,
    COUNT(DISTINCT 거래ID) AS 거래건수,
    ROUND(AVG(평균금액), 2) AS 평균단가
FROM orders_master
GROUP BY 제품카테고리
ORDER BY 총매출 DESC

-- name: category_top_products | 거래량 상위 5개 카테고리별 인기 제품 Top 5
WITH cat_top5 AS (
    SELECT 제품카테고리
    FROM orders_master
    GROUP BY 제품카테고리
    ORDER BY COUNT(DISTINCT 거래ID) DESC
    LIMIT 5
),
product_stats AS (
    SELECT
        o.제품카테고리,
        o.제품ID,
        COUNT(DISTINCT o.거래ID) AS 거래건수,
        ROUND(SUM(o.세후금액), 0) AS 총매출
    FROM orders_master o
    JOIN cat_top5 c ON o.제품카테고리 = c.제품카테고리
    GROUP BY o.제품카테고리, o.제품ID
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY 제품카테고리
               ORDER BY 거래건수 DESC
           ) AS rn
    FROM product_stats
)
SELECT 제품카테고리, 제품ID, 거래건수, 총매출
FROM ranked
WHERE rn <= 5
ORDER BY 제품카테고리, 거래건수 DESC

-- name: gender_sales | 성별 총매출·고객수·고객당 평균지출
SELECT
    성별,
    ROUND(SUM(고객지출), 0) AS 총매출,
    COUNT(*) AS 고객수,
    ROUND(AVG(고객지출), 2) AS 평균구매액
FROM (
    SELECT 성별, 고객ID, SUM(세후금액) AS 고객지출
    FROM orders_master
    GROUP BY 성별, 고객ID
) customer_level
GROUP BY 성별

-- name: region_sales | 지역별 총매출·고객수
SELECT
    고객지역,
    ROUND(SUM(세후금액), 0) AS 총매출,
    COUNT(DISTINCT 고객ID) AS 고객수
FROM orders_master
GROUP BY 고객지역
ORDER BY 총매출 DESC

-- name: tenure_behavior | 가입기간 구간별 고객수·평균구매액·쿠폰사용률·구매빈도 (행 기준·고객 기준 병기)
WITH cust_level AS (
    SELECT
        고객ID,
        CASE
            WHEN MAX(가입기간) BETWEEN 1  AND 12 THEN '0~12개월'
            WHEN MAX(가입기간) BETWEEN 13 AND 24 THEN '13~24개월'
            ELSE '25개월 이상'
        END AS 가입기간_구간,
        COUNT(DISTINCT 거래ID) AS 구매빈도,
        MAX(할인적용여부) AS 쿠폰사용여부
    FROM orders_master
    GROUP BY 고객ID
),
group_stats AS (
    SELECT
        CASE
            WHEN 가입기간 BETWEEN 1  AND 12 THEN '0~12개월'
            WHEN 가입기간 BETWEEN 13 AND 24 THEN '13~24개월'
            ELSE '25개월 이상'
        END AS 가입기간_구간,
        COUNT(DISTINCT 고객ID) AS 고객수,
        ROUND(AVG(세후금액), 2) AS 평균구매액,
        ROUND(SUM(세후금액) / COUNT(DISTINCT 고객ID), 2) AS 고객당_평균구매금액,
        ROUND(AVG(할인적용여부) * 100, 1) AS 쿠폰사용률
    FROM orders_master
    GROUP BY 가입기간_구간
),
cust_stats AS (
    SELECT
        가입기간_구간,
        ROUND(AVG(구매빈도), 2) AS 구매빈도,
        ROUND(AVG(쿠폰사용여부) * 100, 1) AS 쿠폰사용고객비율
    FROM cust_level
    GROUP BY 가입기간_구간
)
SELECT
    g.가입기간_구간,
    g.고객수,
    g.평균구매액,
    g.고객당_평균구매금액,
    g.쿠폰사용률,
    c.쿠폰사용고객비율,
    c.구매빈도
FROM group_stats g
JOIN cust_stats c ON g.가입기간_구간 = c.가입기간_구간
ORDER BY
    CASE g.가입기간_구간
        WHEN '0~12개월' THEN 1
        WHEN '13~24개월' THEN 2
        ELSE 3
    END

-- name: purchase_frequency | 고객별 거래 건수 분포
SELECT
    COUNT(DISTINCT 거래ID) AS 거래건수
FROM orders_master
GROUP BY 고객ID
ORDER BY 거래건수

-- name: revisit_frequency | 고객별 재방문 횟수(구매일 수 - 1) 분포
SELECT
    COUNT(DISTINCT DATE(거래날짜)) - 1 AS 재방문횟수
FROM orders_master
GROUP BY 고객ID
ORDER BY 재방문횟수

-- name: coupon_status | 쿠폰 상태별 상품라인수·3단계 라인평균(세전/할인후세전/할인후세후)·총매출
SELECT
    쿠폰상태,
    COUNT(*) AS 상품라인수,
    ROUND(AVG(총매출), 2) AS 라인평균_세전,
    ROUND(AVG(할인후금액), 2) AS 라인평균_할인후_세전,
    ROUND(AVG(세후금액), 2) AS 라인평균_할인후_세후,
    ROUND(SUM(세후금액), 0) AS 총매출
FROM orders_master
GROUP BY 쿠폰상태

-- name: discount_rate | 할인율별 상품라인수·3단계 라인평균(세전/할인후세전/할인후세후) (쿠폰 적용 상품라인)
SELECT
    할인율,
    COUNT(*) AS 상품라인수,
    ROUND(AVG(총매출), 2) AS 라인평균_세전,
    ROUND(AVG(할인후금액), 2) AS 라인평균_할인후_세전,
    ROUND(AVG(세후금액), 2) AS 라인평균_할인후_세후
FROM orders_master
WHERE 할인적용여부 = 1
GROUP BY 할인율
ORDER BY 할인율

-- name: marketing_monthly | 월별 총매출·오프라인비용·온라인비용
WITH sales_monthly AS (
    SELECT
        월,
        SUM(세후금액) AS 총매출
    FROM orders_master
    GROUP BY 월
),
marketing_monthly AS (
    SELECT
        MONTH(날짜) AS 월,
        SUM(오프라인비용) AS 오프라인비용,
        SUM(온라인비용) AS 온라인비용
    FROM marketing
    GROUP BY MONTH(날짜)
)
SELECT
    s.월,
    ROUND(s.총매출, 0) AS 총매출,
    ROUND(m.오프라인비용, 0) AS 오프라인비용,
    ROUND(m.온라인비용, 0) AS 온라인비용,
    ROUND(s.총매출 / NULLIF(m.오프라인비용 + m.온라인비용, 0), 2) AS 매출_광고비_배수
FROM sales_monthly s
JOIN marketing_monthly m ON s.월 = m.월
ORDER BY s.월

-- name: customer_summary | 고객별 구매횟수·총구매금액·평균구매금액
SELECT
    고객ID,
    COUNT(DISTINCT 거래ID) AS 구매횟수,
    ROUND(SUM(세후금액), 0) AS 총구매금액,
    ROUND(SUM(세후금액) / COUNT(DISTINCT 거래ID), 2) AS 평균구매금액
FROM orders_master
GROUP BY 고객ID

-- name: region_customer_summary | 지역별 고객수·평균구매횟수·평균구매금액
SELECT
    고객지역,
    COUNT(DISTINCT 고객ID) AS 고객수,
    ROUND(AVG(구매횟수), 2) AS 평균구매횟수,
    ROUND(AVG(평균구매금액), 2) AS 평균구매금액
FROM (
    SELECT
        고객지역,
        고객ID,
        COUNT(DISTINCT 거래ID) AS 구매횟수,
        ROUND(SUM(세후금액) / COUNT(DISTINCT 거래ID), 2) AS 평균구매금액
    FROM orders_master
    GROUP BY 고객지역, 고객ID
) cust
GROUP BY 고객지역
ORDER BY 평균구매금액 DESC

-- name: weekday_pattern | 요일별 일평균 거래건수·평균 거래금액
SELECT
    ELT(WEEKDAY(거래날짜)+1,
        'Mon','Tue','Wed','Thu','Fri','Sat','Sun') AS 거래요일,
    ROUND(COUNT(DISTINCT 거래ID) / COUNT(DISTINCT 거래날짜), 2) AS 일평균_거래건수,
    ROUND(SUM(세후금액) / COUNT(DISTINCT 거래ID), 2) AS 평균_거래금액
FROM orders_master
GROUP BY 거래요일, WEEKDAY(거래날짜)
ORDER BY WEEKDAY(거래날짜)

-- name: basket_size | 거래별 상품수량·상품라인수·카테고리 수
SELECT
    거래ID,
    SUM(수량) AS 아이템수,
    COUNT(제품ID) AS 상품라인수,
    COUNT(DISTINCT 제품카테고리) AS 카테고리수
FROM orders_master
GROUP BY 거래ID

-- name: customer_category_diversity | 고객별 구매 카테고리 수
SELECT
    고객ID,
    COUNT(DISTINCT 제품카테고리) AS 구매카테고리수
FROM orders_master
GROUP BY 고객ID
