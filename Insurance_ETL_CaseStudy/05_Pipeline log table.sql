-- 1. Initialize our precise tracking variables BEFORE the run starts
DECLARE @StartTime DATETIME = GETDATE();
DECLARE @RowsScanned INT = 0;
DECLARE @ErrorsAtStart INT = 0;
DECLARE @ErrorsAtEnd INT = 0;
DECLARE @RowsQuarantined INT = 0;
DECLARE @TotalTargetBefore INT = 0;
DECLARE @TotalTargetAfter INT = 0;
DECLARE @RowsInserted INT = 0;
DECLARE @RowsUpdated INT = 0;
DECLARE @RowsIgnored INT = 0;
DECLARE @Status VARCHAR(20) = 'SUCCESS';

BEGIN TRY
    -- 2. Take a "Snapshot" of the database state before we do any work
    SET @RowsScanned = (SELECT COUNT(*) FROM dbo.STG_POLICY);
    SET @ErrorsAtStart = (SELECT COUNT(*) FROM dbo.ERROR_POLICY);
    SET @TotalTargetBefore = (SELECT COUNT(*) FROM dbo.ILM_POLICY);

    -- =========================================================================
  EXACT EXISTING PIPELINE SCRIPT GOES HERE <<<
    -- (1. Insert to Quarantine)
    -- (2. MERGE statement into ILM_POLICY)
    -- =========================================================================
    
    -- Capture Total Inserts + Updates generated specifically by the MERGE statement
    DECLARE @MergeAffectedRows INT = @@ROWCOUNT; 

    -- 3. Take a "Snapshot" of the database state AFTER the work is done
    SET @ErrorsAtEnd = (SELECT COUNT(*) FROM dbo.ERROR_POLICY);
    SET @TotalTargetAfter = (SELECT COUNT(*) FROM dbo.ILM_POLICY);

    
    
    -- Problem 2 Solved: Only count errors generated during THIS specific execution
    SET @RowsQuarantined = @ErrorsAtEnd - @ErrorsAtStart;
    
    -- Problem 1 Solved: Calculate exact inserts by looking at physical table growth
    SET @RowsInserted = @TotalTargetAfter - @TotalTargetBefore;
    
    -- Problem 4 Solved: Updates = Total MERGE actions minus the actual new rows
    SET @RowsUpdated = @MergeAffectedRows - @RowsInserted;
    
    -- Problem 5 Solved: Ignored = Total incoming minus everything we actually processed
    SET @RowsIgnored = @RowsScanned - (@RowsInserted + @RowsUpdated + @RowsQuarantined);

    -- Problem 6 Solved: If errors were caught, update the status to a Warning
    IF @RowsQuarantined > 0 
        SET @Status = 'WARNING (ERRORS CAUGHT)';

    -- 5. Write  Log Entry
    INSERT INTO dbo.PIPELINE_LOG (
        RUN_DATETIME, EXECUTION_TIME_SECONDS, ROWS_SCANNED, 
        ROWS_INSERTED, ROWS_UPDATED, ROWS_IGNORED, ROWS_QUARANTINED, PIPELINE_STATUS
    )
    VALUES (
        GETDATE(), 
        DATEDIFF(SECOND, @StartTime, GETDATE()), -- Problem 3 Solved
        @RowsScanned, @RowsInserted, @RowsUpdated, @RowsIgnored, @RowsQuarantined, @Status
    );

END TRY
BEGIN CATCH
    -- The Ultimate Failsafe: If the pipeline crashes completely, log the failure!
    INSERT INTO dbo.PIPELINE_LOG (
        RUN_DATETIME, EXECUTION_TIME_SECONDS, ROWS_SCANNED, 
        ROWS_INSERTED, ROWS_UPDATED, ROWS_IGNORED, ROWS_QUARANTINED, PIPELINE_STATUS
    )
    VALUES (
        GETDATE(), DATEDIFF(SECOND, @StartTime, GETDATE()), @RowsScanned, 
        0, 0, 0, 0, 'FAILED'
    );

    -- Re-throw the actual SQL error so you can see it in the console
    THROW;
END CATCH











-- not valid 
-- -- CREATE TABLE dbo.PIPELINE_LOG (
-- --     LOG_ID INT IDENTITY(1,1) PRIMARY KEY,
-- --     RUN_DATETIME DATETIME DEFAULT GETDATE(),
-- --     EXECUTION_TIME_SECONDS INT,  -- Performance Trend
-- --     ROWS_SCANNED INT,            -- Pipeline Volume
-- --     ROWS_INSERTED INT,           -- Growth metric
-- --     ROWS_UPDATED INT,            -- Change velocity
-- --     ROWS_IGNORED INT,            -- Compute efficiency (Duplicates)
-- --     ROWS_QUARANTINED INT,        -- Data Quality indicator
-- --     PIPELINE_STATUS VARCHAR(20)  -- 'SUCCESS' or 'WARNING'
-- -- );
-- -- GO


-- -- Run this AFTER your main pipeline transformation script completes
-- --  Truncate TABLE dbo.PIPELINE_LOG;

-- /* INSERT INTO dbo.PIPELINE_LOG (
--     RUN_DATETIME, 
--     EXECUTION_TIME_SECONDS, 
--     ROWS_SCANNED, 
--     ROWS_INSERTED, 
--     ROWS_UPDATED, 
--     ROWS_IGNORED, 
--     ROWS_QUARANTINED, 
--     PIPELINE_STATUS
-- )
-- SELECT 
--     GETDATE(),
--     0, -- Duration
--     (SELECT COUNT(*) FROM dbo.STG_POLICY),
--     (SELECT COUNT(*) FROM dbo.ILM_POLICY WHERE LOAD_TS >= DATEADD(MINUTE, -5, GETDATE())), 
--     0, 
--     0, 
--     (SELECT COUNT(*) FROM dbo.ERROR_POLICY WHERE CAST(REJECT_TS AS DATE) = CAST(GETDATE() AS DATE)), -- Corrected column name here
--     'SUCCESS'; */


-- -- SELECT * FROM dbo.PIPELINE_LOG;
-- -- SELECT * FROM dbo.STG_POLICY;
-- -- SELECT * FROM dbo.ERROR_POLICY;

-- -- SELECT 
-- --     COUNT(*) AS Total_Error_Rows, 
-- --     COUNT(DISTINCT POL_NBR) AS Unique_Policy_Errors
-- -- FROM dbo.ERROR_POLICY;
