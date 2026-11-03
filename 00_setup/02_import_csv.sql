/* =====================================================================
   02_import_csv.sql  –  load the HousingDelivery data from CSV files
   ---------------------------------------------------------------------
   Run AFTER 01_create_database.sql (it creates empty tables; to reload,
   re-run 01 first).

   1. Copy the 00_setup\data folder somewhere the SQL Server service
      can read, e.g. C:\SQLCourse\data\  (BULK INSERT reads files on the
      SERVER's disk, not your laptop's, unless they are the same machine).
   2. Change @DataPath below to that folder (keep the trailing slash).
   3. Press F5. Takes under a minute.

   CSV conventions:
     - first row is the header
     - an empty field means NULL
     - <EMPTY> means an empty string '' (used for some Applicant emails,
       a deliberate "blank vs NULL" teaching trap)
   ===================================================================== */
USE HousingDelivery;
GO
SET NOCOUNT ON;

DECLARE @DataPath NVARCHAR(400) = N'C:\SQLCourse\data\';   -- <<< CHANGE ME

DECLARE @tables TABLE (Seq INT, TableName SYSNAME);
INSERT @tables VALUES (1,'TenureTypes'),(2,'Partners'),(3,'Programmes'),(4,'Sites'),
                      (5,'Applicants'),(6,'Staff'),(7,'Applications'),(8,'FundingLines');

DECLARE @t SYSNAME, @sql NVARCHAR(MAX), @i INT = 1;
WHILE @i <= 8
BEGIN
    SELECT @t = TableName FROM @tables WHERE Seq = @i;
    SET @sql = N'BULK INSERT dbo.' + QUOTENAME(@t) + N'
FROM ''' + @DataPath + @t + N'.csv''
WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0d0a'',
      CODEPAGE = ''65001'', KEEPIDENTITY, TABLOCK, CHECK_CONSTRAINTS);';
    EXEC sys.sp_executesql @sql;
    PRINT CONCAT(@t, ': ', @@ROWCOUNT, ' rows loaded');
    SET @i += 1;
END;

-- restore the empty-string sentinel
UPDATE dbo.Applicants SET Email = N'' WHERE Email = N'<EMPTY>';
GO

-- quick check (full check: 03_verify.sql)
SELECT 'Applications' AS TableName, COUNT(*) AS Rows FROM dbo.Applications
UNION ALL SELECT 'FundingLines', COUNT(*) FROM dbo.FundingLines
UNION ALL SELECT 'Applicants',   COUNT(*) FROM dbo.Applicants;
GO
