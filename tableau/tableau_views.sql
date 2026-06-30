-- Tableau 데이터 소스용 와이드 VIEW 정의
-- export_csv.py 가 이 뷰들을 생성한 뒤 SELECT 결과를 CSV로 내보낸다.
-- (Tableau Public은 MySQL 라이브 연결 불가 → CSV 추출 방식)

-- name: create_orders_view | 거래라인 + 등급/세그먼트 (매출·카테고리·쿠폰·요일 분석용)
CREATE OR REPLACE VIEW v_tableau_orders AS
SELECT
    o.고객ID,
    o.거래ID,
    o.거래날짜,
    o.월,
    o.제품카테고리,
    o.수량,
    o.세후금액,
    o.쿠폰상태,
    o.성별,
    o.고객지역,
    o.가입기간,
    r.등급,
    r.세그먼트,
    r.R,
    r.F,
    r.M
FROM orders_master o
JOIN rfm_scored r ON o.고객ID = r.고객ID

-- name: create_customer_view | 고객 단위 RFM + 행동 (세그먼트·등급 프로파일용)
CREATE OR REPLACE VIEW v_tableau_customer AS
SELECT
    r.고객ID,
    r.등급,
    r.세그먼트,
    r.R, r.F, r.M, r.RFM_score,
    r.Recency,
    r.Frequency AS 거래건수,
    r.Monetary AS 총지출,
    c.성별,
    c.고객지역,
    c.가입기간,
    o.구매일수,
    CASE WHEN o.구매일수 > 1 THEN 1 ELSE 0 END AS 재방문여부,
    o.첫구매월
FROM rfm_scored r
JOIN customers c ON r.고객ID = c.고객ID
JOIN (
    SELECT
        고객ID,
        COUNT(DISTINCT DATE(거래날짜)) AS 구매일수,
        MONTH(MIN(거래날짜)) AS 첫구매월
    FROM orders_master
    GROUP BY 고객ID
) o ON r.고객ID = o.고객ID

-- name: create_monthly_view | 월별 매출·거래·고객·마케팅비용·ARPPU (추세 분석용)
CREATE OR REPLACE VIEW v_tableau_monthly AS
SELECT
    s.월,
    s.매출,
    s.거래수,
    s.고객수,
    m.온라인비용,
    m.오프라인비용,
    ROUND(s.매출 / s.고객수, 2) AS ARPPU
FROM (
    SELECT
        월,
        SUM(세후금액) AS 매출,
        COUNT(DISTINCT 거래ID) AS 거래수,
        COUNT(DISTINCT 고객ID) AS 고객수
    FROM orders_master
    GROUP BY 월
) s
JOIN (
    SELECT
        MONTH(날짜) AS 월,
        SUM(온라인비용) AS 온라인비용,
        SUM(오프라인비용) AS 오프라인비용
    FROM marketing
    GROUP BY MONTH(날짜)
) m ON s.월 = m.월
