--  reconciliation logic rebuilding in progress 



SELECT DISTINCT POL_NBR FROM dbo.STG_POLICY
EXCEPT 
(
    SELECT POLICY_NUMBER FROM dbo.ILM_POLICY
    UNION 
    SELECT POL_NBR FROM dbo.ERROR_POLICY
);