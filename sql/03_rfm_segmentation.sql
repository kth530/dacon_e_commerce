-- name: create_rfm_scored_view | rfm_scores에 등급·세그먼트 분류(CASE WHEN) 추가
-- 점수화(R/F/M·RFM_score)는 Python(qcut·IQR·PCA)에서 rfm_scores 테이블로 저장하고,
-- 등급 컷오프와 세그먼트 룰(11종)은 SQL CASE WHEN으로 분류한다.
CREATE OR REPLACE VIEW rfm_scored AS
SELECT
    고객ID, R, F, M, RFM_score, Recency, Frequency, Monetary,
    CASE
        WHEN RFM_score >= 95 THEN 'Diamond'
        WHEN RFM_score >= 80 THEN 'Platinum'
        WHEN RFM_score >= 65 THEN 'Gold'
        WHEN RFM_score >= 50 THEN 'Silver'
        ELSE 'Bronze'
    END AS 등급,
    CASE
        WHEN CONCAT(R, F, M) IN (
            '555', '554', '544', '545', '454', '455',
            '445'
        ) THEN 'VIP 고객'
        WHEN CONCAT(R, F, M) IN (
            '543', '444', '435', '355', '354', '345',
            '344', '335'
        ) THEN '충성 고객'
        WHEN CONCAT(R, F, M) IN (
            '553', '551', '552', '541', '542', '533',
            '532', '531', '452', '451', '442', '441',
            '431', '453', '433', '432', '423', '353',
            '352', '351', '342', '341', '333', '323'
        ) THEN '잠재 충성 고객'
        WHEN CONCAT(R, F, M) IN (
            '512', '511', '422', '421', '412', '411',
            '311'
        ) THEN '신규 고객'
        WHEN CONCAT(R, F, M) IN (
            '525', '524', '523', '522', '521', '515',
            '514', '513', '425', '424', '413', '414',
            '415', '315', '314', '313'
        ) THEN '가망 고객'
        WHEN CONCAT(R, F, M) IN (
            '535', '534', '443', '434', '343', '334',
            '325', '324'
        ) THEN '관심 필요 고객'
        WHEN CONCAT(R, F, M) IN (
            '331', '321', '312', '221', '213', '231',
            '241', '251'
        ) THEN '이탈 조짐 고객'
        WHEN CONCAT(R, F, M) IN (
            '155', '154', '144', '214', '215', '115',
            '114', '113'
        ) THEN '놓치면 안될 고객'
        WHEN CONCAT(R, F, M) IN (
            '255', '254', '245', '244', '253', '252',
            '243', '242', '235', '234', '225', '224',
            '153', '152', '145', '143', '142', '135',
            '134', '133', '125', '124'
        ) THEN '이탈 위험 고객'
        WHEN CONCAT(R, F, M) IN (
            '332', '322', '233', '232', '223', '222',
            '132', '123', '122', '212', '211'
        ) THEN '휴면 고객'
        WHEN CONCAT(R, F, M) IN (
            '111', '112', '121', '131', '141', '151'
        ) THEN '이탈 고객'
        ELSE 'Others'
    END AS 세그먼트
FROM rfm_scores

-- name: rfm_graded | rfm_scored 뷰에서 고객별 등급·세그먼트
SELECT 고객ID, 등급, 세그먼트
FROM rfm_scored

-- name: create_rfm_result | rfm_scored 뷰에서 다운스트림용 rfm_result 테이블 생성
DROP TABLE IF EXISTS rfm_result;
CREATE TABLE rfm_result AS
SELECT 고객ID, 등급, 세그먼트, R, F, M, RFM_score, Recency, Frequency, Monetary
FROM rfm_scored

-- name: segment_counts | 세그먼트별 고객 수
SELECT 세그먼트, COUNT(*) AS 고객수
FROM rfm_result
GROUP BY 세그먼트
ORDER BY 고객수 DESC

-- name: grade_summary | 등급별 고객수·매출합계·1인당지출 (비중·반올림은 Python)
SELECT
    등급,
    COUNT(*) AS 고객수,
    SUM(Monetary) AS 매출합계,
    AVG(Monetary) AS 1인당지출
FROM rfm_result
GROUP BY 등급

-- name: grade_segment_counts | 세그먼트×등급 고객수 (long, pivot은 Python)
SELECT 세그먼트, 등급, COUNT(*) AS 고객수
FROM rfm_result
GROUP BY 세그먼트, 등급

-- name: grade_revisit_rate | 등급별 재방문(방문일수>1) 고객수·전체수 (재방문율은 Python)
SELECT
    r.등급,
    SUM(CASE WHEN v.방문일수 > 1 THEN 1 ELSE 0 END) AS 재방문고객,
    COUNT(*) AS 전체고객
FROM rfm_result r
JOIN (
    SELECT 고객ID, COUNT(DISTINCT DATE(거래날짜)) AS 방문일수
    FROM orders_master
    GROUP BY 고객ID
) v ON r.고객ID = v.고객ID
GROUP BY r.등급
