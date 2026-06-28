/*-- ========================================================================
-- 1. CLEAN SLATE & ENVIRONMENT CLEANUP (Idempotency Checks)
-- ========================================================================
-- Wipe out historical test runs to clear old 1900-01-01 data bugs
TRUNCATE TABLE dbo.ILM_POLICY;
TRUNCATE TABLE dbo.ERROR_POLICY;

-- Drop temp processing blocks if they exist from a crashed run
IF OBJECT_ID('tempdb..#TempRoutedData') IS NOT NULL 
    DROP TABLE #TempRoutedData;
GO

-- ========================================================================
-- 2. THE MASTER TRANSFORMATION PIPELINE
-- ========================================================================
WITH 
-- Station 1: The Deduplication Layer (Isolate the valid grain)
cte_dedup AS (
    SELECT 
        POL_NBR, EFF_DT, PREM_AMT, ST_CD, LOB_CD, LNAME, FNAME, CANCEL_FLG, SRC_UPDATE_TS,
        ROW_NUMBER() OVER(
            PARTITION BY POL_NBR 
            ORDER BY 
                SRC_UPDATE_TS DESC, 
                COALESCE(PREM_AMT, 0.00) DESC -- Tie-Breaker for exact millisecond collisions
        ) as RowRank
    FROM dbo.STG_POLICY
),

-- Station 2 & 3: Cleansing and Reference Lookups
cte_transform AS (
    SELECT 
        -- A. PRESERVE RAW COLUMNS (Needed for Error Table if the row fails)
        d.POL_NBR           AS RAW_POL_NBR,
        d.EFF_DT            AS RAW_EFF_DT,
        d.PREM_AMT          AS RAW_PREM_AMT,
        d.ST_CD             AS RAW_ST_CD,
        d.LOB_CD            AS RAW_LOB_CD,
        d.LNAME             AS RAW_LNAME,
        d.FNAME             AS RAW_FNAME,
        d.CANCEL_FLG        AS RAW_CANCEL_FLG,
        d.SRC_UPDATE_TS     AS RAW_SRC_UPDATE_TS,

        -- B. TRANSFORM & VALIDATE TARGET COLUMNS (For ILM_POLICY)
        TRIM(d.POL_NBR)     AS TGT_POL_NBR,
        
        
        TRY_CONVERT(DATE, NULLIF(TRIM(d.EFF_DT), ''), 112) AS TGT_EFF_DT,
        
        -- Default Premium to 0.00 safely
        CAST(COALESCE(d.PREM_AMT, 0.00) AS DECIMAL(14,2)) AS TGT_PREM_AMT,
        
        -- State Lookup (Upper/Trim to clean string before matching)
        rs.STATE_CD         AS TGT_ST_CD,
        
        -- LOB Lookup (Default to 'UNKNOWN' if no match)
        COALESCE(rl.LOB_DESC, 'UNKNOWN') AS TGT_LOB,
        
        -- Safe Concatenation (CONCAT_WS ignores NULLs to prevent data wipeout)
        CONCAT_WS(', ', NULLIF(TRIM(d.LNAME), ''), NULLIF(TRIM(d.FNAME), '')) AS TGT_NAME,
        
        -- Decode Status Flag
        CASE UPPER(TRIM(d.CANCEL_FLG))
            WHEN 'Y' THEN 'CANCELLED'
            WHEN 'N' THEN 'ACTIVE'
            ELSE 'UNKNOWN'
        END AS TGT_STATUS

    FROM cte_dedup d
    LEFT JOIN dbo.REF_STATE rs ON UPPER(TRIM(d.ST_CD)) = rs.STATE_CD
    LEFT JOIN dbo.REF_LOB rl   ON TRIM(d.LOB_CD) = rl.LOB_CD
    WHERE d.RowRank = 1
),

-- Station 4: The Routing Engine (The Inspector)
cte_routing AS (
    SELECT 
        *,
        CASE 
            -- STRICT DATE ROUTING: Catches garbage text, blanks (''), and NULLs cleanly
            WHEN TGT_EFF_DT IS NULL 
                THEN 'INVALID_OR_MISSING_DATE'
                
            -- Trap invalid or missing states
            WHEN TGT_ST_CD IS NULL 
                THEN 'INVALID_OR_MISSING_STATE_CODE'
                
            -- Everything passed successfully
            ELSE 'VALID'
        END AS ROUTING_FLAG
    FROM cte_transform
)

-- Execute the CTE pipeline and dump results into a temporary table in RAM
SELECT * INTO #TempRoutedData 
FROM cte_routing;
GO

-- ========================================================================
-- 3. THE DATA SPLIT (Load the physical tables)
-- ========================================================================

-- A. INCREMENTAL UPSERT: Merge clean data into Target Table (ILM_POLICY)
MERGE dbo.ILM_POLICY AS TGT
USING (
    SELECT 
        TGT_POL_NBR, TGT_EFF_DT, TGT_PREM_AMT, TGT_ST_CD, 
        TGT_LOB, TGT_NAME, TGT_STATUS
    FROM #TempRoutedData
    WHERE ROUTING_FLAG = 'VALID'
) AS SRC
ON TGT.POLICY_NUMBER = SRC.TGT_POL_NBR

-- If the policy number already matches, update the existing system record 
WHEN MATCHED THEN
    UPDATE SET 
        TGT.EFFECTIVE_DATE   = SRC.TGT_EFF_DT,
        TGT.PREMIUM_AMOUNT   = SRC.TGT_PREM_AMT,
        TGT.STATE_CODE       = SRC.TGT_ST_CD,
        TGT.LINE_OF_BUSINESS = SRC.TGT_LOB,
        TGT.INSURED_NAME     = SRC.TGT_NAME,
        TGT.STATUS           = SRC.TGT_STATUS -- Captures soft-delete status flips

-- If it's a completely fresh policy record, insert it 
WHEN NOT MATCHED THEN
    INSERT (
        POLICY_NUMBER, EFFECTIVE_DATE, PREMIUM_AMOUNT, STATE_CODE, 
        LINE_OF_BUSINESS, INSURED_NAME, STATUS
    )
    VALUES (
        SRC.TGT_POL_NBR, SRC.TGT_EFF_DT, SRC.TGT_PREM_AMT, SRC.TGT_ST_CD, 
        SRC.TGT_LOB, SRC.TGT_NAME, SRC.TGT_STATUS
);

-- B. AUDIT TRAIL INSERT: Load the Error Quarantine Table (ERROR_POLICY)
INSERT INTO dbo.ERROR_POLICY (
    POL_NBR, EFF_DT, PREM_AMT, ST_CD, LOB_CD, LNAME, FNAME, 
    CANCEL_FLG, SRC_UPDATE_TS, REJECT_REASON
)
SELECT 
    RAW_POL_NBR, RAW_EFF_DT, RAW_PREM_AMT, RAW_ST_CD, RAW_LOB_CD, 
    RAW_LNAME, RAW_FNAME, RAW_CANCEL_FLG, RAW_SRC_UPDATE_TS, 
    ROUTING_FLAG
FROM #TempRoutedData
WHERE ROUTING_FLAG != 'VALID';
GO

-- ========================================================================
-- 4. CLEANUP
-- ========================================================================
DROP TABLE #TempRoutedData;
GO */

-- WITH Missing_Data_Check AS (
--     SELECT DISTINCT TRIM(POL_NBR) AS Missing_Policies 
--     FROM dbo.STG_POLICY
--     EXCEPT 
--     (
--         SELECT TRIM(POLICY_NUMBER) FROM dbo.ILM_POLICY
--         UNION 
--         SELECT TRIM(POL_NBR) FROM dbo.ERROR_POLICY
--     )
-- )
-- -- SCENARIO A: The query found missing data
-- SELECT 
--     'WARNING: Missing Record Detected' AS Alert_Message,
--     'Investigate source data immediately' AS Recommended_Action,
--     Missing_Policies
-- FROM Missing_Data_Check
-- UNION ALL
-- -- SCENARIO B: The query found absolutely nothing
-- SELECT 
--     'SUCCESS: Zero Drops' AS Alert_Message,
--     'Pipeline balanced perfectly' AS Recommended_Action,
--     'NONE' AS Missing_Policies
-- WHERE NOT EXISTS (SELECT 1 FROM Missing_Data_Check);
-- GO

-- select *  from [dbo].[ERROR_POLICY];
-- select * from [dbo].[ILM_POLICY]

-- SELECT count(Distinct POL_NBR) from [dbo].[STG_POLICY];