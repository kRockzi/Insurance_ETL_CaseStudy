-- In Progress


WITH Missing_Data_Check AS (
    SELECT DISTINCT TRIM(POL_NBR) AS Missing_Policies 
    FROM dbo.STG_POLICY
    EXCEPT 
    (
        SELECT TRIM(POLICY_NUMBER) FROM dbo.ILM_POLICY
        UNION 
        SELECT TRIM(POL_NBR) FROM dbo.ERROR_POLICY
    )
)
-- SCENARIO A: The query found missing data
SELECT 
    'WARNING: Missing Record Detected' AS Alert_Message,
    'Investigate source data immediately' AS Recommended_Action,
    Missing_Policies
FROM Missing_Data_Check
UNION ALL
-- SCENARIO B: The query found absolutely nothing
SELECT 
    'SUCCESS: Zero Drops' AS Alert_Message,
    'Pipeline balanced perfectly' AS Recommended_Action,
    'NONE' AS Missing_Policies
WHERE NOT EXISTS (SELECT 1 FROM Missing_Data_Check);
GO
