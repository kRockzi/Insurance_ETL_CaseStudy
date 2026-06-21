-- SELECT name from sys.tables;
-- SELECT * FROM STG_POLICY;
-- SELECT * FROM ILM_POLICY;
-- SELECT * FROM ERROR_POLICY;



-- Update With New data :  inserted new rows 
-- Case 1:

/* INSERT INTO dbo.STG_POLICY (
    POL_NBR, EFF_DT, PREM_AMT, ST_CD, LOB_CD, LNAME, FNAME, CANCEL_FLG, SRC_UPDATE_TS
)
VALUES 
    -- Row 1: Valid Data (8-character date, matching your schema)
    ('POL-80002', '20240501', 1250.50, 'NY', 'HOME', 'Smith', 'John', 'N', GETDATE()),

    -- Row 2: Invalid Data (8-character date, NULL state code to test routing)
    ('POL-80003', '20240515', 850.00, NULL, 'AUTO', 'Doe', 'Jane', 'N', GETDATE());
*/


/*
-- Transformation Script ( change instead of insert utilize merge )

-- ========================================================================
-- 1. CLEANUP PREVIOUS RUNS (Idempotency Check)
-- ========================================================================
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
        
        -- STRICT CONVERSION: Style 112 (YYYYMMDD) per STTM
        TRY_CONVERT(DATE, TRIM(d.EFF_DT), 112) AS TGT_EFF_DT,
        
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
            -- STRICT DATE ROUTING: Catches garbage text, blanks (''), and NULLs
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

-- A. The "Traffic Cop" for Valid Data (MERGE into ILM_POLICY)
MERGE INTO dbo.ILM_POLICY AS Target
USING (
    -- Only bring the strictly valid data to the intersection
    SELECT * FROM #TempRoutedData WHERE ROUTING_FLAG = 'VALID'
) AS Source
ON Target.POLICY_NUMBER = Source.TGT_POL_NBR

-- SCENARIO 2: The True Update (Match Found)
WHEN MATCHED THEN
    UPDATE SET 
        Target.EFFECTIVE_DATE   = Source.TGT_EFF_DT,
        Target.PREMIUM_AMOUNT   = Source.TGT_PREM_AMT,
        Target.STATE_CODE       = Source.TGT_ST_CD,
        Target.LINE_OF_BUSINESS = Source.TGT_LOB,
        Target.INSURED_NAME     = Source.TGT_NAME,
        Target.STATUS           = Source.TGT_STATUS

-- SCENARIO 1: The "Net-New" Arrival (No Match Found)
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        POLICY_NUMBER, EFFECTIVE_DATE, PREMIUM_AMOUNT, STATE_CODE, 
        LINE_OF_BUSINESS, INSURED_NAME, STATUS
    )
    VALUES (
        Source.TGT_POL_NBR, Source.TGT_EFF_DT, Source.TGT_PREM_AMT, Source.TGT_ST_CD, 
        Source.TGT_LOB, Source.TGT_NAME, Source.TGT_STATUS
    );


-- B. Load the Error Quarantine Table (ERROR_POLICY)
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
GO 
*/




/*UPDATE dbo.STG_POLICY
SET 
    PREM_AMT = 1500.00,
    SRC_UPDATE_TS = CURRENT_TIMESTAMP
WHERE POL_NBR = 'POL-10001';
*/


/*

-- Simulate a bulk batch of 15 net-new policies arriving in the staging file
INSERT INTO dbo.STG_POLICY (
    POL_NBR, EFF_DT, PREM_AMT, ST_CD, LOB_CD, LNAME, FNAME, CANCEL_FLG, SRC_UPDATE_TS
)
VALUES 
    ('POL-11001', '20240201', 1050.00, 'TX', 'AUTO',   'Adams',    'John',     'N', GETDATE()),
    ('POL-11002', '20240202', 1200.25, 'NY', 'HOME',   'Baker',    'Sarah',    'N', GETDATE()),
    ('POL-11003', '20240203', 450.00,  'FL', 'RENTER', 'Clark',    'David',    'N', GETDATE()),
    ('POL-11004', '20240204', 2100.50, 'IL', 'AUTO',   'Davis',    'Emily',    'N', GETDATE()),
    ('POL-11005', '20240205', 1500.00, 'CA', 'HOME',   'Evans',    'Michael',  'N', GETDATE()),
    ('POL-11006', '20240206', 300.00,  'TX', 'RENTER', 'Ford',     'Jessica',  'N', GETDATE()),
    ('POL-11007', '20240207', 1340.75, 'NY', 'AUTO',   'Garcia',   'Robert',   'N', GETDATE()),
    ('POL-11008', '20240208', 2200.00, 'FL', 'HOME',   'Hall',     'Ashley',   'N', GETDATE()),
    ('POL-11009', '20240209', 350.25,  'IL', 'RENTER', 'Irwin',    'James',    'N', GETDATE()),
    ('POL-11010', '20240210', 1750.00, 'CA', 'AUTO',   'Jones',    'Mary',     'N', GETDATE()),
    ('POL-11011', '20240211', 1100.00, 'TX', 'HOME',   'King',     'William',  'N', GETDATE()),
    ('POL-11012', '20240212', 410.50,  'NY', 'RENTER', 'Lee',      'Patricia', 'N', GETDATE()),
    ('POL-11013', '20240213', 1980.00, 'FL', 'AUTO',   'Moore',    'Richard',  'N', GETDATE()),
    ('POL-11014', '20240214', 1650.25, 'IL', 'HOME',   'Nelson',   'Linda',    'N', GETDATE()),
    ('POL-11015', '20240215', 290.00,  'CA', 'RENTER', 'Ortiz',    'Charles',  'N', GETDATE());


*/


