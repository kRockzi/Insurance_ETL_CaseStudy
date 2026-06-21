-- CREATE TABLE dbo.PIPELINE_LOG (
--     LOG_ID INT IDENTITY(1,1) PRIMARY KEY,
--     RUN_DATETIME DATETIME DEFAULT GETDATE(),
--     EXECUTION_TIME_SECONDS INT,  -- Performance Trend
--     ROWS_SCANNED INT,            -- Pipeline Volume
--     ROWS_INSERTED INT,           -- Growth metric
--     ROWS_UPDATED INT,            -- Change velocity
--     ROWS_IGNORED INT,            -- Compute efficiency (Duplicates)
--     ROWS_QUARANTINED INT,        -- Data Quality indicator
--     PIPELINE_STATUS VARCHAR(20)  -- 'SUCCESS' or 'WARNING'
-- );
-- GO


-- Run this AFTER your main pipeline transformation script completes
--  Truncate TABLE dbo.PIPELINE_LOG;

/* INSERT INTO dbo.PIPELINE_LOG (
    RUN_DATETIME, 
    EXECUTION_TIME_SECONDS, 
    ROWS_SCANNED, 
    ROWS_INSERTED, 
    ROWS_UPDATED, 
    ROWS_IGNORED, 
    ROWS_QUARANTINED, 
    PIPELINE_STATUS
)
SELECT 
    GETDATE(),
    0, -- Duration
    (SELECT COUNT(*) FROM dbo.STG_POLICY),
    (SELECT COUNT(*) FROM dbo.ILM_POLICY WHERE LOAD_TS >= DATEADD(MINUTE, -5, GETDATE())), 
    0, 
    0, 
    (SELECT COUNT(*) FROM dbo.ERROR_POLICY WHERE CAST(REJECT_TS AS DATE) = CAST(GETDATE() AS DATE)), -- Corrected column name here
    'SUCCESS'; */


-- SELECT * FROM dbo.PIPELINE_LOG;
-- SELECT * FROM dbo.STG_POLICY;
-- SELECT * FROM dbo.ERROR_POLICY;

-- SELECT 
--     COUNT(*) AS Total_Error_Rows, 
--     COUNT(DISTINCT POL_NBR) AS Unique_Policy_Errors
-- FROM dbo.ERROR_POLICY;