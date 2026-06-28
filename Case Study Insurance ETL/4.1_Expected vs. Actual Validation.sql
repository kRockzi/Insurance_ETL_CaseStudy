WITH cte_dedup AS
(
    SELECT *,
           ROW_NUMBER() OVER
           (
               PARTITION BY POL_NBR
               ORDER BY SRC_UPDATE_TS DESC,
                        COALESCE(PREM_AMT,0) DESC
           ) rn
    FROM dbo.STG_POLICY
),

Expected AS
(
    SELECT
        TRIM(d.POL_NBR)                                             AS POLICY_NUMBER,
        TRY_CONVERT(DATE,NULLIF(TRIM(d.EFF_DT),''),112)             AS EFFECTIVE_DATE,
        CAST(COALESCE(d.PREM_AMT,0.00) AS DECIMAL(14,2))            AS PREMIUM_AMOUNT,
        rs.STATE_CD                                                 AS STATE_CODE,
        COALESCE(rl.LOB_DESC,'UNKNOWN')                             AS LINE_OF_BUSINESS,
        CONCAT_WS(', ',
                  NULLIF(TRIM(d.LNAME),''),
                  NULLIF(TRIM(d.FNAME),'')
                 )                                                  AS INSURED_NAME,
        CASE UPPER(TRIM(d.CANCEL_FLG))
             WHEN 'Y' THEN 'CANCELLED'
             WHEN 'N' THEN 'ACTIVE'
             ELSE 'UNKNOWN'
        END                                                         AS STATUS
    FROM cte_dedup d
    LEFT JOIN dbo.REF_STATE rs
           ON UPPER(TRIM(d.ST_CD)) = rs.STATE_CD
    LEFT JOIN dbo.REF_LOB rl
           ON TRIM(d.LOB_CD) = rl.LOB_CD
    WHERE rn = 1
      AND TRY_CONVERT(DATE,NULLIF(TRIM(d.EFF_DT),''),112) IS NOT NULL
      AND rs.STATE_CD IS NOT NULL
)

SELECT *
FROM Expected

EXCEPT

SELECT
    POLICY_NUMBER,
    EFFECTIVE_DATE,
    PREMIUM_AMOUNT,
    STATE_CODE,
    LINE_OF_BUSINESS,
    INSURED_NAME,
    STATUS
FROM dbo.ILM_POLICY

UNION ALL

SELECT
    POLICY_NUMBER,
    EFFECTIVE_DATE,
    PREMIUM_AMOUNT,
    STATE_CODE,
    LINE_OF_BUSINESS,
    INSURED_NAME,
    STATUS
FROM dbo.ILM_POLICY

EXCEPT

SELECT *
FROM Expected;