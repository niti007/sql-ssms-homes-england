/* HousingDelivery - verification (all data fictional) */
USE HousingDelivery;
GO
SET NOCOUNT ON;

SELECT 'TenureTypes' AS TableName, COUNT(*) AS Rows FROM dbo.TenureTypes
UNION ALL SELECT 'Partners', COUNT(*) FROM dbo.Partners
UNION ALL SELECT 'Programmes', COUNT(*) FROM dbo.Programmes
UNION ALL SELECT 'Sites', COUNT(*) FROM dbo.Sites
UNION ALL SELECT 'Applicants', COUNT(*) FROM dbo.Applicants
UNION ALL SELECT 'Staff', COUNT(*) FROM dbo.Staff
UNION ALL SELECT 'Applications', COUNT(*) FROM dbo.Applications
UNION ALL SELECT 'FundingLines', COUNT(*) FROM dbo.FundingLines;

IF (SELECT COUNT(*) FROM dbo.Applications) < 50000
    THROW 50001, 'Verification failed: Applications has fewer than 50000 rows. Re-run 02_insert_data.sql.', 1;

SELECT 'Applicants Email NULL' AS EdgeCase, COUNT(*) AS Cnt FROM dbo.Applicants WHERE Email IS NULL
UNION ALL SELECT 'Applicants Email empty string', COUNT(*) FROM dbo.Applicants WHERE Email = ''
UNION ALL SELECT 'Applicants Phone NULL', COUNT(*) FROM dbo.Applicants WHERE Phone IS NULL
UNION ALL SELECT 'Applicants Region NULL', COUNT(*) FROM dbo.Applicants WHERE Region IS NULL
UNION ALL SELECT 'Applicants AnnualIncome NULL', COUNT(*) FROM dbo.Applicants WHERE AnnualIncome IS NULL
UNION ALL SELECT 'Names with leading/trailing spaces', COUNT(*) FROM dbo.Applicants WHERE FirstName <> LTRIM(RTRIM(FirstName)) OR LastName <> LTRIM(RTRIM(LastName))
UNION ALL SELECT 'FirstName all lower case', COUNT(*) FROM dbo.Applicants WHERE FirstName COLLATE Latin1_General_CS_AS = LOWER(FirstName) COLLATE Latin1_General_CS_AS
UNION ALL SELECT 'LastName all UPPER case', COUNT(*) FROM dbo.Applicants WHERE LastName COLLATE Latin1_General_CS_AS = UPPER(LastName) COLLATE Latin1_General_CS_AS
UNION ALL SELECT 'Applicants with apostrophe in name', COUNT(*) FROM dbo.Applicants WHERE LastName LIKE N'%''%' OR FirstName LIKE N'%''%'
UNION ALL SELECT 'Applicants in duplicate full-name groups (exact match)', COUNT(*) FROM dbo.Applicants a WHERE EXISTS (SELECT 1 FROM dbo.Applicants b WHERE b.FirstName = a.FirstName AND b.LastName = a.LastName AND b.ApplicantID <> a.ApplicantID)
UNION ALL SELECT 'Sites with % or _ in name', COUNT(*) FROM dbo.Sites WHERE SiteName LIKE N'%[%]%' OR SiteName LIKE N'%[_]%'
UNION ALL SELECT 'Country <> "England" (variants)', COUNT(*) FROM dbo.Applicants WHERE Country COLLATE Latin1_General_CS_AS <> N'England'
UNION ALL SELECT '  of which exactly "england"', COUNT(*) FROM dbo.Applicants WHERE Country COLLATE Latin1_General_CS_AS = N'england'
UNION ALL SELECT '  of which "UK"', COUNT(*) FROM dbo.Applicants WHERE Country = N'UK'
UNION ALL SELECT '  of which "United Kingdom"', COUNT(*) FROM dbo.Applicants WHERE Country = N'United Kingdom'
UNION ALL SELECT 'Region variant "North-West"', COUNT(*) FROM dbo.Applicants WHERE Region = N'North-West'
UNION ALL SELECT 'Region variant "Yorkshire & The Humber"', COUNT(*) FROM dbo.Applicants WHERE Region = N'Yorkshire & The Humber'
UNION ALL SELECT 'Applicants with no applications', COUNT(*) FROM dbo.Applicants a WHERE NOT EXISTS (SELECT 1 FROM dbo.Applications x WHERE x.ApplicantID = a.ApplicantID)
UNION ALL SELECT 'Sites never funded', COUNT(*) FROM dbo.Sites s WHERE NOT EXISTS (SELECT 1 FROM dbo.FundingLines f WHERE f.SiteID = s.SiteID)
UNION ALL SELECT 'Tenure types with no sites', COUNT(*) FROM dbo.TenureTypes t WHERE NOT EXISTS (SELECT 1 FROM dbo.Sites s WHERE s.TenureTypeID = t.TenureTypeID)
UNION ALL SELECT 'Sites with TenureTypeID NULL', COUNT(*) FROM dbo.Sites WHERE TenureTypeID IS NULL
UNION ALL SELECT 'Programmes never used', COUNT(*) FROM dbo.Programmes p WHERE NOT EXISTS (SELECT 1 FROM dbo.Applications a WHERE a.ProgrammeID = p.ProgrammeID)
UNION ALL SELECT 'Sites UnitPrice = 0 (land only)', COUNT(*) FROM dbo.Sites WHERE UnitPrice = 0
UNION ALL SELECT 'Stalled sites with PlannedHomes > 0', COUNT(*) FROM dbo.Sites WHERE IsStalled = 1 AND PlannedHomes > 0
UNION ALL SELECT 'FundingLines Homes = 0', COUNT(*) FROM dbo.FundingLines WHERE Homes = 0
UNION ALL SELECT 'FundingLines Homes < 0 (reversals)', COUNT(*) FROM dbo.FundingLines WHERE Homes < 0
UNION ALL SELECT 'FundingLines ClawbackRate = 1.00', COUNT(*) FROM dbo.FundingLines WHERE ClawbackRate = 1.00
UNION ALL SELECT 'Applications CompletionDate NULL', COUNT(*) FROM dbo.Applications WHERE CompletionDate IS NULL
UNION ALL SELECT 'Submitted/Withdrawn/Rejected with CompletionDate NULL', COUNT(*) FROM dbo.Applications WHERE Status IN (N'Submitted', N'Withdrawn', N'Rejected') AND CompletionDate IS NULL
UNION ALL SELECT 'Applications CompletionDate < ApplicationDate (error)', COUNT(*) FROM dbo.Applications WHERE CompletionDate < CAST(ApplicationDate AS DATE)
UNION ALL SELECT 'Applications with no FundingLines', COUNT(*) FROM dbo.Applications a WHERE NOT EXISTS (SELECT 1 FROM dbo.FundingLines f WHERE f.ApplicationID = a.ApplicationID)
UNION ALL SELECT 'Applications StaffID NULL (online)', COUNT(*) FROM dbo.Applications WHERE StaffID IS NULL
UNION ALL SELECT 'Applications future-dated (>= 2026-01-01)', COUNT(*) FROM dbo.Applications WHERE ApplicationDate >= '2026-01-01'
UNION ALL SELECT 'Applications on 2024-02-29', COUNT(*) FROM dbo.Applications WHERE CAST(ApplicationDate AS DATE) = '2024-02-29'
UNION ALL SELECT 'Applications on 31 Mar', COUNT(*) FROM dbo.Applications WHERE MONTH(ApplicationDate) = 3 AND DAY(ApplicationDate) = 31
UNION ALL SELECT 'Applications on 1 Apr', COUNT(*) FROM dbo.Applications WHERE MONTH(ApplicationDate) = 4 AND DAY(ApplicationDate) = 1
UNION ALL SELECT 'Applications on Dec 31', COUNT(*) FROM dbo.Applications WHERE MONTH(ApplicationDate) = 12 AND DAY(ApplicationDate) = 31
UNION ALL SELECT 'Applications on Jan 1', COUNT(*) FROM dbo.Applications WHERE MONTH(ApplicationDate) = 1 AND DAY(ApplicationDate) = 1
UNION ALL SELECT 'Applications with time 23:59:59', COUNT(*) FROM dbo.Applications WHERE CAST(ApplicationDate AS TIME(0)) = '23:59:59'
UNION ALL SELECT 'Applications AdminFee NULL', COUNT(*) FROM dbo.Applications WHERE AdminFee IS NULL
UNION ALL SELECT 'Applications AdminFee = 0', COUNT(*) FROM dbo.Applications WHERE AdminFee = 0
UNION ALL SELECT 'Staff Chief Executive (ManagerID NULL)', COUNT(*) FROM dbo.Staff WHERE ManagerID IS NULL
UNION ALL SELECT 'Staff sharing a salary with another', COUNT(*) FROM dbo.Staff e WHERE EXISTS (SELECT 1 FROM dbo.Staff x WHERE x.Salary = e.Salary AND x.StaffID <> e.StaffID);
GO
