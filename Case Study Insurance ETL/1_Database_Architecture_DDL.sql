/* CREATE DATABASE Insurance_ETL_CaseStudy;
GO
USE Insurance_ETL_CaseStudy;
GO
*/ 

--  Table STG Policy 
-- Here in this table SRC_UPDATE_TS Column Required to execute the "keep the latest" deduplication logic.


/* CREATE TABLE dbo.STG_POLICY (
    POL_NBR       VARCHAR(20)    NULL,
    EFF_DT        VARCHAR(8)     NULL,
    PREM_AMT      DECIMAL(12,2)  NULL,
    ST_CD         CHAR(2)        NULL,
    LOB_CD        VARCHAR(10)    NULL,
    LNAME         VARCHAR(40)    NULL,
    FNAME         VARCHAR(40)    NULL,
    CANCEL_FLG    CHAR(1)        NULL,
    SRC_UPDATE_TS DATETIME2      NULL   
);
*/



/*TRUNCATE TABLE dbo.STG_POLICY;
GO

INSERT INTO dbo.STG_POLICY 
    (POL_NBR, EFF_DT, PREM_AMT, ST_CD, LOB_CD, LNAME, FNAME, CANCEL_FLG, SRC_UPDATE_TS)
VALUES 
    -- ========================================================================
    -- 1(Perfectly clean data that should pass effortlessly)
    -- ========================================================================
    ('POL-10001', '20231001', 1200.50, 'TX', 'AUTO',   'Smith',    'John',   'N', '2023-10-01 08:00:00'),
    ('POL-10002', '20231002',  850.00, 'CA', 'HOME',   'Johnson',  'Mary',   'N', '2023-10-02 08:15:00'),
    ('POL-10003', '20231003',  400.25, 'NY', 'RENTER', 'Williams', 'James',  'N', '2023-10-03 09:30:00'),
    ('POL-10004', '20231004', 2100.00, 'FL', 'AUTO',   'Brown',    'Patricia','Y','2023-10-04 10:45:00'),
    ('POL-10005', '20231005',  999.99, 'IL', 'HOME',   'Jones',    'Robert', 'N', '2023-10-05 11:20:00'),
    ('POL-10006', '20231006',  350.00, 'TX', 'RENTER', 'Garcia',   'Linda',  'Y', '2023-10-06 13:00:00'),
    ('POL-10007', '20231007', 1750.75, 'CA', 'AUTO',   'Miller',   'Michael','N', '2023-10-07 14:10:00'),
    ('POL-10008', '20231008', 1100.00, 'NY', 'HOME',   'Davis',    'Barbara','N', '2023-10-08 15:55:00'),
    ('POL-10009', '20231009',  200.00, 'FL', 'RENTER', 'Rodriguez','William','N', '2023-10-09 16:30:00'),
    ('POL-10010', '20231010', 3200.00, 'IL', 'AUTO',   'Martinez', 'Richard','Y', '2023-10-10 17:45:00'),

    -- ========================================================================
    -- 2. DEDUPLICATION TESTS (Testing the Grain: "Keep the latest by SRC_UPDATE_TS")
    -- ========================================================================
    -- Policy 20001 arrives 3 times. Only the 10:05 record should survive.
    ('POL-20001', '20231101', 1000.00, 'TX', 'AUTO',   'Hernandez','Joseph', 'N', '2023-11-01 08:00:00'),
    ('POL-20001', '20231101', 1050.00, 'TX', 'AUTO',   'Hernandez','Joseph', 'N', '2023-11-01 09:30:00'),
    ('POL-20001', '20231101', 1100.00, 'TX', 'AUTO',   'Hernandez','Joseph', 'N', '2023-11-01 10:05:00'),
    -- Policy 20002 arrives 2 times.
    ('POL-20002', '20231102',  600.00, 'CA', 'HOME',   'Lopez',    'Charles','N', '2023-11-02 11:00:00'),
    ('POL-20002', '20231102',  600.00, 'CA', 'HOME',   'Lopez',    'Charles','Y', '2023-11-02 14:00:00'),

    -- ========================================================================
    -- 3. DATE CASTING ERRORS (These should route to the Error Table)
    -- ========================================================================
    ('POL-30001', '20230229',  500.00, 'NY', 'AUTO',   'Gonzalez', 'Thomas', 'N', '2023-11-05 08:00:00'), -- Invalid date (Not a leap year)
    ('POL-30002', '20231301',  450.00, 'FL', 'HOME',   'Wilson',   'Sarah',  'N', '2023-11-05 09:00:00'), -- Invalid month (13)
    ('POL-30003', 'ABCDEFGH',  300.00, 'TX', 'RENTER', 'Anderson', 'Matthew','N', '2023-11-05 10:00:00'), -- Pure garbage string
    ('POL-30004', '',          700.00, 'CA', 'AUTO',   'Thomas',   'Karen',  'N', '2023-11-05 11:00:00'), -- Empty string
    ('POL-30005', NULL,        800.00, 'IL', 'HOME',   'Taylor',   'Nancy',  'N', '2023-11-05 12:00:00'), -- NULL date

    -- ========================================================================
    -- 4. STATE CODE TESTS (Lookup failures & Case formatting)
    -- ========================================================================
    ('POL-40001', '20231110', 1200.00, 'tx', 'AUTO',   'Moore',    'Lisa',   'N', '2023-11-10 08:00:00'), -- Lowercase (Should be uppered and PASS)
    ('POL-40002', '20231110', 1300.00, 'ZZ', 'HOME',   'Jackson',  'Betty',  'N', '2023-11-10 09:00:00'), -- Invalid State (Should FAIL to error table)
    ('POL-40003', '20231110', 1400.00, NULL, 'RENTER', 'Martin',   'Margaret','N','2023-11-10 10:00:00'), -- NULL State (Should FAIL)
    ('POL-40004', '20231110', 1500.00, ' C', 'AUTO',   'Lee',      'Sandra', 'N', '2023-11-10 11:00:00'), -- Bad padding

    -- ========================================================================
    -- 5. LOB CODE TESTS (Default to 'UNKNOWN' if no match)
    -- ========================================================================
    ('POL-50001', '20231115',  900.00, 'TX', 'UMBRELLA','Perez',   'Ashley', 'N', '2023-11-15 08:00:00'), -- Valid syntax, but 'UMBRELLA' won't be in REF_LOB
    ('POL-50002', '20231115',  950.00, 'CA', NULL,      'Thompson','Steven', 'N', '2023-11-15 09:00:00'), -- NULL LOB

    -- ========================================================================
    -- 6. PREMIUM AMOUNT TESTS (Default to 0.00 if NULL)
    -- ========================================================================
    ('POL-60001', '20231120', NULL,    'NY', 'AUTO',   'White',    'Paul',   'N', '2023-11-20 08:00:00'), -- NULL Premium
    ('POL-60002', '20231120', NULL,    'FL', 'HOME',   'Harris',   'Andrew', 'N', '2023-11-20 09:00:00'), -- NULL Premium

    -- ========================================================================
    -- 7. NAME CONCATENATION TESTS (Handling NULLs safely)
    -- ========================================================================
    ('POL-70001', '20231125',  400.00, 'TX', 'RENTER', NULL,       'Joshua', 'N', '2023-11-25 08:00:00'), -- Missing Last Name
    ('POL-70002', '20231125',  450.00, 'CA', 'AUTO',   'Sanchez',  NULL,     'N', '2023-11-25 09:00:00'), -- Missing First Name
    ('POL-70003', '20231125',  500.00, 'NY', 'HOME',   NULL,       NULL,     'N', '2023-11-25 10:00:00'), -- Missing Both

    -- ========================================================================
    -- 8. STRING PADDING & STATUS TESTS (Trim policies, decode statuses)
    -- ========================================================================
    ('  POL-80001 ', '20231201', 100.00, 'FL', 'AUTO', 'Clark',    'Kenneth','Y', '2023-12-01 08:00:00'), -- Leading/Trailing spaces on Policy Number
    ('POL-80002', '20231201', 150.00, 'TX', 'HOME',   'Ramirez',  'Kevin',  'y', '2023-12-01 09:00:00'), -- Lowercase 'y'
    ('POL-80003', '20231201', 200.00, 'CA', 'RENTER', 'Lewis',    'Brian',  'X', '2023-12-01 10:00:00'), -- Invalid Status flag (Should map to 'UNKNOWN')
    ('POL-80004', '20231201', 250.00, 'NY', 'AUTO',   'Robinson', 'George', NULL,'2023-12-01 11:00:00'), -- NULL Status flag (Should map to 'UNKNOWN')

    -- ========================================================================
    -- ========================================================================
    ('POL-90001', '20231210',  750.00, 'FL', 'HOME',   'Walker',   'Edward', 'N', '2023-12-10 08:00:00'),
    ('POL-90002', '20231210',  800.00, 'TX', 'AUTO',   'Young',    'Ronald', 'N', '2023-12-10 09:00:00'),
    ('POL-90003', '20231210',  850.00, 'CA', 'RENTER', 'Allen',    'Timothy','Y', '2023-12-10 10:00:00'),
    ('POL-90004', '20231210',  900.00, 'NY', 'HOME',   'King',     'Jason',  'N', '2023-12-10 11:00:00'),
    ('POL-90005', '20231210',  950.00, 'FL', 'AUTO',   'Wright',   'Jeffrey','N', '2023-12-10 12:00:00'),
    ('POL-90006', '20231210', 1000.00, 'TX', 'HOME',   'Scott',    'Ryan',   'N', '2023-12-10 13:00:00'),
    ('POL-90007', '20231210', 1050.00, 'CA', 'AUTO',   'Torres',   'Jacob',  'Y', '2023-12-10 14:00:00'),
    ('POL-90008', '20231210', 1100.00, 'NY', 'RENTER', 'Nguyen',   'Gary',   'N', '2023-12-10 15:00:00'),
    ('POL-90009', '20231210', 1150.00, 'FL', 'HOME',   'Hill',     'Nicholas','N','2023-12-10 16:00:00'),
    ('POL-90010', '20231210', 1200.00, 'TX', 'AUTO',   'Flores',   'Eric',   'N', '2023-12-10 17:00:00'),
    ('POL-90011', '20231210', 1250.00, 'CA', 'HOME',   'Green',    'Stephen','N', '2023-12-10 18:00:00'),
    ('POL-90012', '20231210', 1300.00, 'NY', 'AUTO',   'Adams',    'Jonathan','Y','2023-12-10 19:00:00');
GO

*/

-- SELECT * FROM dbo.STG_POLICY;

/*
-- ========================================================================
-- 1. STATE REFERENCE TABLE
-- ========================================================================
IF OBJECT_ID('dbo.REF_STATE', 'U') IS NOT NULL 
    DROP TABLE dbo.REF_STATE;
GO

-- Using CHAR(2) for the Primary Key since state codes are strictly two letters
CREATE TABLE dbo.REF_STATE (
    STATE_CD CHAR(2) PRIMARY KEY
);
GO

-- Populating with valid states to test our STG data
INSERT INTO dbo.REF_STATE (STATE_CD)
VALUES ('TX'), ('CA'), ('NY'), ('FL'), ('IL'); 
GO

-- ========================================================================
-- 2. LINE OF BUSINESS (LOB) REFERENCE TABLE
-- ========================================================================
IF OBJECT_ID('dbo.REF_LOB', 'U') IS NOT NULL 
    DROP TABLE dbo.REF_LOB;
GO

CREATE TABLE dbo.REF_LOB (
    LOB_CD VARCHAR(10) PRIMARY KEY, 
    LOB_DESC VARCHAR(50) NOT NULL
);
GO

-- Populating with valid LOB mappings
INSERT INTO dbo.REF_LOB (LOB_CD, LOB_DESC)
VALUES 
    ('AUTO', 'Automobile Insurance'), 
    ('HOME', 'Homeowners Insurance'), 
    ('RENTER', 'Renters Insurance');
GO

*/ 

-- SELECT * FROM dbo.REF_STATE;
 
-- SELECT * FROM 
-- dbo.REF_LOB;

--  Target Table 
/*
-- Drop table if it already exists
IF OBJECT_ID('dbo.ILM_POLICY', 'U') IS NOT NULL 
    DROP TABLE dbo.ILM_POLICY;
GO

CREATE TABLE dbo.ILM_POLICY (
    -- Cleaned & Transformed Columns
    POLICY_NUMBER      VARCHAR(20)    NOT NULL,
    EFFECTIVE_DATE     DATE           NULL,          -- Strict DATE type
    PREMIUM_AMOUNT     DECIMAL(14,2)  NOT NULL,      -- Increased precision per STTM
    STATE_CODE         CHAR(2)        NULL,
    LINE_OF_BUSINESS   VARCHAR(50)    NULL,
    INSURED_NAME       VARCHAR(100)   NULL,
    STATUS             VARCHAR(10)    NULL,
    
    -- Audit Metadata (System timestamp at load)
    LOAD_TS            DATETIME2      DEFAULT SYSDATETIME() NOT NULL 
);
GO
*/ 

-- Error Table 

-- Drop table if it already exists
/*IF OBJECT_ID('dbo.ERROR_POLICY', 'U') IS NOT NULL 
    DROP TABLE dbo.ERROR_POLICY;
GO

CREATE TABLE dbo.ERROR_POLICY (
    -- Raw Staging Columns (Keeping them as strings/raw formats to prevent crashes)
    POL_NBR            VARCHAR(20)    NULL,
    EFF_DT             VARCHAR(8)     NULL,  
    PREM_AMT           DECIMAL(12,2)  NULL,
    ST_CD              CHAR(2)        NULL,
    LOB_CD             VARCHAR(10)    NULL,
    LNAME              VARCHAR(40)    NULL,
    FNAME              VARCHAR(40)    NULL,
    CANCEL_FLG         CHAR(1)        NULL,
    SRC_UPDATE_TS      DATETIME2      NULL,
    
    -- Error Metadata (The "Documented Reject" columns)
    REJECT_REASON      VARCHAR(255)   NOT NULL,
    REJECT_TS          DATETIME2      DEFAULT SYSDATETIME() NOT NULL
);
GO
*/

--SELECT * FROM sys.tables;


