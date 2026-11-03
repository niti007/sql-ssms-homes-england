USE HousingDelivery;
GO
/* ============================================================================
   MODULE 05 - GROUPING: GROUP BY, HAVING, CASE, ORDER OF EXECUTION
   Database : HousingDelivery (see SPEC.md)      Target : SQL Server 2019+ / SSMS
   NetFunding  : Homes * GrantPerHome * (1 - ClawbackRate)

   Run one example at a time (highlight + F5). Lines starting with -- ERROR:
   fail on purpose; they are commented out.

   CONCEPTS
     A. GROUP BY - single column
     B. GROUP BY - multiple columns and expressions
     C. Grouping on dirty values ('England' / 'england' / 'UK' / 'United Kingdom', NULL, spaces)
     D. WHERE vs HAVING
     E. CASE - simple and searched
     F. CASE inside aggregates (pivot-style counts)
     G. Logical application of query execution
   ============================================================================ */


/* ############################################################################
   CONCEPT A : GROUP BY - SINGLE COLUMN
   ############################################################################
   GROUP BY splits rows into buckets (one per distinct value) and runs the
   aggregate once per bucket. Rule: every column in SELECT must be either in
   GROUP BY or inside an aggregate function.
   ########################################################################## */

-- A.1  Applications per status
SELECT Status, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY Status;

-- A.2  Same, sorted by the biggest bucket
SELECT Status, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY Status
ORDER BY Applications DESC;

-- A.3  Applicants per household type
SELECT HouseholdType, COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY HouseholdType
ORDER BY Applicants DESC;

-- A.4  Several aggregates per group
SELECT TenureTypeID,
       COUNT(*)       AS Sites,
       MIN(UnitPrice) AS LowestGrant,
       MAX(UnitPrice) AS HighestGrant,
       AVG(UnitPrice) AS AvgGrantPerHome
FROM dbo.Sites
GROUP BY TenureTypeID
ORDER BY TenureTypeID;          -- NULL tenure forms its own group (shown first)

-- A.5  Sites per partner: top 5
SELECT TOP (5) PartnerID, COUNT(*) AS Sites
FROM dbo.Sites
GROUP BY PartnerID
ORDER BY Sites DESC, PartnerID;

-- A.6  NetFunding per application (ApplicationDetails only)
SELECT TOP (10) ApplicationID,
       COUNT(*)                                   AS Lines,
       SUM(Homes * GrantPerHome * (1 - ClawbackRate)) AS NetFunding
FROM dbo.FundingLines
GROUP BY ApplicationID
ORDER BY NetFunding DESC;

-- A.7  AdminFee per programme (NULL ProgrammeID is its own group; NULL admin fee skipped)
SELECT ProgrammeID,
       COUNT(*)      AS Applications,
       SUM(AdminFee)  AS TotalAdminFee,
       AVG(AdminFee)  AS AvgAdminFee
FROM dbo.Applications
GROUP BY ProgrammeID
ORDER BY ProgrammeID;

-- A.8  Online self-service applications (no staff member) vs staff-assisted
SELECT CASE WHEN StaffID IS NULL THEN 'Online' ELSE 'Staff-assisted' END AS Channel,
       COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY CASE WHEN StaffID IS NULL THEN 'Online' ELSE 'Staff-assisted' END;

-- A.9  GROUP BY without an aggregate = DISTINCT
SELECT HouseholdType FROM dbo.Applicants GROUP BY HouseholdType;
SELECT DISTINCT HouseholdType FROM dbo.Applicants;       -- same result

-- A.10 Number of distinct applicants per property region (COUNT DISTINCT inside groups)
SELECT TOP (5) PropertyRegion,
       COUNT(*)                   AS Applications,
       COUNT(DISTINCT ApplicantID) AS Applicants
FROM dbo.Applications
GROUP BY PropertyRegion
ORDER BY Applications DESC;

-- A.11 Planned homes by stalled flag
SELECT IsStalled, COUNT(*) AS Sites, SUM(PlannedHomes) AS PlannedHomes
FROM dbo.Sites
GROUP BY IsStalled;

-- A.12 Staff by department: headcount and payroll
SELECT Directorate,
       COUNT(*)    AS Headcount,
       SUM(Salary) AS Payroll,
       AVG(Salary) AS AvgSalary
FROM dbo.Staff
GROUP BY Directorate
ORDER BY Payroll DESC;

-- A.13 ERROR demo: selecting a column that is not grouped
-- ERROR: SELECT Status, PropertyRegion, COUNT(*) FROM dbo.Applications GROUP BY Status;
-- Fix: add PropertyRegion to GROUP BY (that changes the grain) or drop it.

/* ---- Common mistakes (A) ---------------------------------------------------
   1. Selecting a non-grouped, non-aggregated column (A.13).
   2. ORDER BY an aggregate without alias: allowed (ORDER BY COUNT(*) DESC).
   3. Expecting a specific application without ORDER BY. GROUP BY does not sort.
   4. Forgetting NULL forms its own group (A.4, A.7).
   5. Using * in COUNT(*) when you meant COUNT(DISTINCT col).
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (A) ------------------------------------------------
   Q1. SELECT HouseholdType, COUNT(*) FROM dbo.Applicants GROUP BY HouseholdType;
       How many rows are returned? (HouseholdType has 3 values, no NULLs.)
   Q2. If the 10,000 applicants are split 5000/3000/2000, what do the counts add up to?
   Q3. How many rows does GROUP BY ProgrammeID return? (5 programmes, but one is
       never used, and some applications have NULL ProgrammeID.)
   Answers: 3 ; 10,000 ; 5 (four used programmes + the NULL group).
   ---------------------------------------------------------------------------- */

/* ---- Try it (A) ------------------------------------------------------------
   Count of applications per Status and the TOTAL AdminFee per Status.
   Which Status has the most NULL AdminFee? (Hint: COUNT(*) - COUNT(AdminFee)).
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT B : GROUP BY - MULTIPLE COLUMNS AND EXPRESSIONS
   ############################################################################
   More columns in GROUP BY = finer buckets (one per unique COMBINATION).
   You can group by an expression such as YEAR(ApplicationDate); then you must repeat
   the same expression in SELECT (or group by it and select it unchanged).
   ########################################################################## */

-- B.1  Applications by year
SELECT YEAR(ApplicationDate) AS Yr, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY YEAR(ApplicationDate)
ORDER BY Yr;                  -- includes the future-dated 2026/2027 rows

-- B.2  Year and month
SELECT YEAR(ApplicationDate) AS Yr, MONTH(ApplicationDate) AS Mo, COUNT(*) AS Applications
FROM dbo.Applications
WHERE ApplicationDate >= '2024-01-01' AND ApplicationDate < '2025-01-01'
GROUP BY YEAR(ApplicationDate), MONTH(ApplicationDate)
ORDER BY Yr, Mo;

-- B.2b Homes funded per UK financial year (April to March), not calendar year
SELECT YEAR(DATEADD(MONTH, -3, a.ApplicationDate)) AS FYStartYear,
       CONCAT('FY ', YEAR(DATEADD(MONTH, -3, a.ApplicationDate)), '/',
              RIGHT(CAST(YEAR(DATEADD(MONTH, -3, a.ApplicationDate)) + 1 AS VARCHAR(4)), 2)) AS FinancialYear,
       SUM(fl.Homes) AS HomesFunded
FROM dbo.Applications a
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
WHERE a.ApplicationDate >= '2022-04-01' AND a.ApplicationDate < '2025-04-01'
GROUP BY YEAR(DATEADD(MONTH, -3, a.ApplicationDate))
ORDER BY FYStartYear;          -- an application on 31 March 2025 23:59:59 belongs to FY 2024/25

-- B.3  Two plain columns: applicants by country AND household type
SELECT TOP (10) Country, HouseholdType, COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY Country, HouseholdType
ORDER BY Applicants DESC;

-- B.4  Status within year (a crosstab in long form)
SELECT YEAR(ApplicationDate) AS Yr, Status, COUNT(*) AS Applications
FROM dbo.Applications
WHERE ApplicationDate < '2026-01-01'
GROUP BY YEAR(ApplicationDate), Status
ORDER BY Yr, Status;

-- B.5  NetFunding by year (needs ApplicationDetails joined to Applications; join preview)
SELECT YEAR(a.ApplicationDate) AS Yr,
       SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate)) AS NetFunding
FROM dbo.Applications AS a
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
GROUP BY YEAR(a.ApplicationDate)
ORDER BY Yr;

-- B.6  Group by a derived label: grant-per-home band
SELECT CASE WHEN UnitPrice = 0 THEN 'Land only'
            WHEN UnitPrice < 30000 THEN 'Low grant'
            WHEN UnitPrice < 80000 THEN 'Medium grant'
            ELSE 'High grant' END AS GrantBand,
       COUNT(*) AS Sites
FROM dbo.Sites
GROUP BY CASE WHEN UnitPrice = 0 THEN 'Land only'
              WHEN UnitPrice < 30000 THEN 'Low grant'
              WHEN UnitPrice < 80000 THEN 'Medium grant'
              ELSE 'High grant' END;
-- Tip: copying the CASE twice is ugly - Module 07 (CTEs/subqueries) fixes that.

-- B.7  Weekday pattern: which weekday gets the most applications?
SELECT DATENAME(WEEKDAY, ApplicationDate) AS Weekday, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY DATENAME(WEEKDAY, ApplicationDate)
ORDER BY Applications DESC;

-- B.8  Hour of day (the time part of ApplicationDate)
SELECT DATEPART(HOUR, ApplicationDate) AS Hr, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY DATEPART(HOUR, ApplicationDate)
ORDER BY Hr;

-- B.9  Hire year of staff
SELECT YEAR(HireDate) AS HireYear, COUNT(*) AS Hired
FROM dbo.Staff
GROUP BY YEAR(HireDate)
ORDER BY HireYear;

-- B.10 Application of GROUP BY columns does not change the numbers, only habit
SELECT HouseholdType, Country, COUNT(*) AS C1 FROM dbo.Applicants GROUP BY HouseholdType, Country
EXCEPT
SELECT HouseholdType, Country, COUNT(*)       FROM dbo.Applicants GROUP BY Country, HouseholdType;   -- returns 0 rows

-- B.11 ROLLUP: subtotals and a grand total
SELECT HouseholdType, Status, COUNT(*) AS Applications
FROM dbo.Applications AS a
JOIN dbo.Applicants AS ap ON ap.ApplicantID = a.ApplicantID
GROUP BY ROLLUP (HouseholdType, Status)
ORDER BY HouseholdType, Status;      -- NULLs here mean "subtotal", not missing data!

-- B.12 GROUPING() tells a subtotal NULL from a real NULL
SELECT CASE WHEN GROUPING(HouseholdType) = 1 THEN 'ALL' ELSE HouseholdType END AS HouseholdType,
       COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY ROLLUP (HouseholdType);

-- B.13 Grain mistake: grouping by a unique column defeats the point
SELECT TOP (5) ApplicantID, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY ApplicantID
ORDER BY Applications DESC;          -- OK: a applicant has many applications
-- But GROUP BY ApplicationID, COUNT(*) always gives 1 per row on Applications.

/* ---- Common mistakes (B) ---------------------------------------------------
   1. SELECT YEAR(ApplicationDate) ... GROUP BY ApplicationDate  -> one group per timestamp.
   2. Using the SELECT alias in GROUP BY (SQL Server rejects it): repeat the
      expression instead.
   3. Reading ROLLUP NULLs as missing data.
   4. Grouping by month number only (MONTH) and merging 2022-03 with 2025-03.
   5. Sorting month names alphabetically (April before January): sort by number.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (B) ------------------------------------------------
   Q1. Applications span 4 years plus a few future ones. How many rows does
       GROUP BY YEAR(ApplicationDate) return?  (4 + number of future years: 2026, 2027.)
   Q2. GROUP BY HouseholdType, Country with 3 household types and 4 spellings of Country: max rows?
   Q3. In B.11 how many "grand total" rows are there?   Answers: 6 ; 12 raw spellings (9 under a case-insensitive collation) ; 1.
   ---------------------------------------------------------------------------- */

/* ---- Try it (B) ------------------------------------------------------------
   NetFunding by financial year AND FY quarter (Apr-Jun = Q1) for FY 2023/24 and FY 2024/25 only.
   Group by financial year, then quarter.
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT C : GROUPING ON DIRTY VALUES
   ############################################################################
   GROUP BY trusts the data. If 'England', 'england', 'UK' and 'United Kingdom' all exist, they
   are different spellings of one country. Whether 'England' = 'england' depends on the
   database COLLATION: the default (..._CI_AS) is case-INSENSITIVE, so those two
   merge, but 'UK' and 'United Kingdom' are still separate. Spaces also matter.
   ########################################################################## */

-- C.1  Look at the mess first (always profile before you trust a report)
SELECT Country, COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY Country
ORDER BY Country;

-- C.2  Which collation are we on? (CI = case-insensitive)
SELECT DATABASEPROPERTYEX('HousingDelivery', 'Collation') AS DbCollation;

-- C.3  Force a case-sensitive grouping to SEE the dirt
SELECT Country COLLATE Latin1_General_CS_AS AS Country, COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY Country COLLATE Latin1_General_CS_AS
ORDER BY Country COLLATE Latin1_General_CS_AS;

-- C.4  Just the rows that mean England/UK
SELECT Country COLLATE Latin1_General_CS_AS AS Country, COUNT(*) AS Applicants
FROM dbo.Applicants
WHERE UPPER(Country) IN ('ENGLAND', 'UK', 'UNITED KINGDOM')
GROUP BY Country COLLATE Latin1_General_CS_AS;

-- C.5  Clean with UPPER + TRIM (fixes case/space issues only)
SELECT UPPER(TRIM(Country)) AS CountryClean, COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY UPPER(TRIM(Country))
ORDER BY CountryClean;

-- C.6  Fix the spelling variants with CASE, then group
SELECT CASE WHEN UPPER(TRIM(Country)) IN ('ENGLAND', 'UK', 'UNITED KINGDOM') THEN 'England'
            ELSE TRIM(Country) END AS CountryFixed,
       COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY CASE WHEN UPPER(TRIM(Country)) IN ('ENGLAND', 'UK', 'UNITED KINGDOM') THEN 'England'
              ELSE TRIM(Country) END
ORDER BY Applicants DESC;

-- C.7  Same problem on Applications.PropertyRegion ('North West' vs 'North-West') - check it too
SELECT PropertyRegion, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY PropertyRegion
ORDER BY PropertyRegion;

-- C.8  Region has many NULLs: a NULL group appears
SELECT Region, COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY Region
ORDER BY Applicants DESC;

-- C.9  Label the NULL group for the report
SELECT ISNULL(Region, '(none)') AS Region, COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY ISNULL(Region, '(none)')
ORDER BY Applicants DESC;

-- C.10 Names: duplicates hidden by case/space
SELECT TOP (10) LastName COLLATE Latin1_General_CS_AS AS LastName, COUNT(*) AS Raw_Count
FROM dbo.Applicants
GROUP BY LastName COLLATE Latin1_General_CS_AS
ORDER BY Raw_Count DESC;      -- 'SMITH' and 'Smith' are separate when CS

SELECT TOP (10) UPPER(TRIM(LastName)) AS LastNameClean, COUNT(*) AS Cleaned_Count
FROM dbo.Applicants
GROUP BY UPPER(TRIM(LastName))
ORDER BY Cleaned_Count DESC;

-- C.11 Email domain profile, treating '' and NULL as "no email"
SELECT CASE WHEN NULLIF(TRIM(Email), '') IS NULL THEN '(no email)'
            ELSE SUBSTRING(Email, CHARINDEX('@', Email) + 1, 100) END AS Domain,
       COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY CASE WHEN NULLIF(TRIM(Email), '') IS NULL THEN '(no email)'
              ELSE SUBSTRING(Email, CHARINDEX('@', Email) + 1, 100) END
ORDER BY Applicants DESC;

-- C.12 Does the cleaned country count equal 10,000 in total?  A sanity check.
SELECT SUM(Applicants) AS Total
FROM (SELECT UPPER(TRIM(Country)) AS C, COUNT(*) AS Applicants
      FROM dbo.Applicants GROUP BY UPPER(TRIM(Country))) AS x;

/* ---- Common mistakes (C) ---------------------------------------------------
   1. Reporting without profiling: the "England" bar is silently split in several.
   2. UPPER() fixes case only. 'UK' vs 'England' needs a mapping (CASE
      or, in real projects, a lookup table).
   3. Cleaning in SELECT but not in GROUP BY (SQL Server will complain, or
      you will group on the dirty value).
   4. Assuming the collation is case-sensitive (it usually is not).
   5. Forgetting that NULL and '' are different groups.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (C) ------------------------------------------------
   Under a case-INSENSITIVE collation, how many groups does GROUP BY Country
   give for the values 'England', 'england', 'UK', 'United Kingdom'?
   Answer: 3 (England/england merge; UK and United Kingdom stay).
   Under a case-SENSITIVE collation: 4.
   ---------------------------------------------------------------------------- */

/* ---- Try it (C) ------------------------------------------------------------
   Produce applications per property region, cleaning PropertyRegion with
   REPLACE(TRIM(PropertyRegion), '-', ' ') so 'North-West' and 'North West' merge.
   Does the top region change after cleaning?
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT D : WHERE vs HAVING
   ############################################################################
   WHERE filters ROWS before grouping (cannot see aggregates).
   HAVING filters GROUPS after grouping (can use aggregates).
   Rule of thumb: if the condition is about a single row, use WHERE (faster -
   fewer rows to group). If it is about a group total/count, use HAVING.
   ########################################################################## */

-- D.1  WHERE only: cancelled applications per year
SELECT YEAR(ApplicationDate) AS Yr, COUNT(*) AS Withdrawn
FROM dbo.Applications
WHERE Status = 'Withdrawn'
GROUP BY YEAR(ApplicationDate)
ORDER BY Yr;

-- D.2  HAVING only: applicants with 10 or more applications
SELECT ApplicantID, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY ApplicantID
HAVING COUNT(*) >= 10
ORDER BY Applications DESC;

-- D.3  Both: completed applications only, applicants with 5+ of them
SELECT ApplicantID, COUNT(*) AS CompletedApplications
FROM dbo.Applications
WHERE Status = 'Completed'            -- row filter first
GROUP BY ApplicantID
HAVING COUNT(*) >= 5                  -- group filter after
ORDER BY CompletedApplications DESC;

-- D.4  Same question, wrong tool (slower, but works for non-aggregates)
SELECT Status, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY Status
HAVING Status = 'Completed';          -- legal! but WHERE is better

-- D.5  TenureTypes with more than 40 sites
SELECT TenureTypeID, COUNT(*) AS Sites
FROM dbo.Sites
GROUP BY TenureTypeID
HAVING COUNT(*) > 40;

-- D.6  Applications whose net funding exceeds 1,000
SELECT ApplicationID, SUM(Homes * GrantPerHome * (1 - ClawbackRate)) AS NetFunding
FROM dbo.FundingLines
GROUP BY ApplicationID
HAVING SUM(Homes * GrantPerHome * (1 - ClawbackRate)) > 1000
ORDER BY NetFunding DESC;

-- D.7  Excluding bad lines BEFORE grouping: WHERE Homes > 0 removes reversals
SELECT TOP (5) ApplicationID, SUM(Homes * GrantPerHome * (1 - ClawbackRate)) AS NetFunding
FROM dbo.FundingLines
WHERE Homes > 0 AND ClawbackRate < 1
GROUP BY ApplicationID
ORDER BY NetFunding DESC;

-- D.8  Applications that contain a reversal (negative homes) - HAVING with MIN
SELECT ApplicationID, MIN(Homes) AS WorstHomes
FROM dbo.FundingLines
GROUP BY ApplicationID
HAVING MIN(Homes) < 0;

-- D.9  Departments whose average salary is above the company average
SELECT Directorate, AVG(Salary) AS AvgSalary
FROM dbo.Staff
GROUP BY Directorate
HAVING AVG(Salary) > (SELECT AVG(Salary) FROM dbo.Staff);

-- D.10 Duplicate finder: names that appear more than once
SELECT TOP (10) UPPER(TRIM(FirstName)) AS F, UPPER(TRIM(LastName)) AS L, COUNT(*) AS Dupes
FROM dbo.Applicants
GROUP BY UPPER(TRIM(FirstName)), UPPER(TRIM(LastName))
HAVING COUNT(*) > 1
ORDER BY Dupes DESC;

-- D.11 Several HAVING conditions
SELECT ApplicantID, COUNT(*) AS Applications, SUM(AdminFee) AS AdminFee
FROM dbo.Applications
GROUP BY ApplicantID
HAVING COUNT(*) >= 5 AND SUM(AdminFee) > 500
ORDER BY AdminFee DESC;

-- D.12 Sites funded on fewer than 300 funding lines (only sites that WERE funded)
SELECT SiteID, COUNT(*) AS TimesApplied
FROM dbo.FundingLines
GROUP BY SiteID
HAVING COUNT(*) < 300
ORDER BY TimesApplied, SiteID;
-- Sites never funded are not here at all - that needs a LEFT JOIN (Module 06).

-- D.13 ERROR demos
-- ERROR: SELECT Status, COUNT(*) FROM dbo.Applications WHERE COUNT(*) > 5 GROUP BY Status;
--        "An aggregate may not appear in the WHERE clause..."
-- ERROR: SELECT Status AS S, COUNT(*) FROM dbo.Applications GROUP BY Status HAVING S = 'Approved';
--        "Invalid column name 'S'"  (aliases don't exist yet in HAVING)

/* ---- Common mistakes (D) ---------------------------------------------------
   1. Aggregate in WHERE (D.13).
   2. Alias in HAVING / WHERE (D.13).
   3. Putting row-level filters in HAVING: works but wastes effort.
   4. HAVING without GROUP BY: legal (treats whole table as one group) but rare.
   5. Mixing up "applicants with >=5 applications" (HAVING COUNT) and "applications with
      Homes >= 5" (WHERE).
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (D) ------------------------------------------------
   Q1. 100 completed applications, 30 withdrawn. WHERE Status='Completed' then
       GROUP BY Status then HAVING COUNT(*) > 50 : how many rows?
   Q2. Same but HAVING COUNT(*) > 150?     Answers: 1 ; 0.
   Q3. Which runs first, WHERE or HAVING?  WHERE.
   ---------------------------------------------------------------------------- */

/* ---- Try it (D) ------------------------------------------------------------
   Find applicants whose TOTAL admin fee on non-cancelled applications exceeds 300 and who
   placed at least 4 such applications. Show ApplicantID, application count, total admin fee.
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT E : CASE - SIMPLE AND SEARCHED
   ############################################################################
   CASE is SQL's if/else that returns a VALUE (it is an expression, not a
   statement). Simple CASE compares one expression to values:
       CASE x WHEN 1 THEN ... WHEN 2 THEN ... ELSE ... END
   Searched CASE evaluates full conditions in sequence and returns the first TRUE:
       CASE WHEN x > 5 THEN ... WHEN x > 2 THEN ... ELSE ... END
   No ELSE and nothing matches -> NULL.
   ########################################################################## */

-- E.1  Simple CASE: readable stalled flag
SELECT TOP (10) SiteName,
       CASE IsStalled WHEN 1 THEN 'Stalled' WHEN 0 THEN 'Active' END AS State
FROM dbo.Sites
ORDER BY SiteID;

-- E.2  Simple CASE on text with ELSE
SELECT TOP (10) ApplicationID, Status,
       CASE Status
            WHEN 'Submitted'   THEN 'Waiting'
            WHEN 'Approved'   THEN 'Being assessed'
            WHEN 'Completed' THEN 'Done'
            ELSE 'Problem'                     -- Withdrawn, Rejected
       END AS Friendly
FROM dbo.Applications
ORDER BY ApplicationID;

-- E.3  Searched CASE: delivery status of a site
SELECT TOP (10) SiteName, PlannedHomes, IsStalled,
       CASE WHEN IsStalled = 1 AND PlannedHomes > 0 THEN 'Stalled - homes at risk'
            WHEN PlannedHomes = 0 THEN 'No homes planned'
            WHEN PlannedHomes < 20 THEN 'Small scheme'
            ELSE 'Large scheme' END AS SiteStatus
FROM dbo.Sites
ORDER BY SiteID;

-- E.4  Order matters: first TRUE wins
SELECT UnitPrice,
       CASE WHEN UnitPrice >= 0   THEN 'Low grant'      -- catches EVERYTHING
            WHEN UnitPrice >= 100000 THEN 'High grant'  -- never reached
       END AS WrongBand
FROM (VALUES (5000.00), (150000.00)) AS t(UnitPrice);

-- E.5  Handling NULL in CASE: NULL never equals anything
SELECT TOP (10) ApplicantID, Region,
       CASE Region WHEN NULL THEN 'none' ELSE Region END       AS Wrong,  -- NULL stays NULL
       CASE WHEN Region IS NULL THEN 'none' ELSE Region END    AS Correct
FROM dbo.Applicants
ORDER BY ApplicantID;

-- E.6  Clean the inconsistent country
SELECT Country,
       CASE WHEN UPPER(TRIM(Country)) IN ('ENGLAND','UK','UNITED KINGDOM') THEN 'England'
            ELSE TRIM(Country) END AS CountryClean,
       COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY Country
HAVING UPPER(TRIM(Country)) IN ('ENGLAND','UK','UNITED KINGDOM');

-- E.7  Data quality flag on Applications
SELECT TOP (15) ApplicationID, ApplicationDate, CompletionDate, Status,
       CASE WHEN CompletionDate IS NULL AND Status IN ('Completed') THEN 'Missing completion date'
            WHEN CompletionDate < CAST(ApplicationDate AS DATE) THEN 'Completed before applied'
            WHEN ApplicationDate >= '2026-01-01' THEN 'Future application'
            ELSE 'OK' END AS Quality
FROM dbo.Applications
WHERE CompletionDate < CAST(ApplicationDate AS DATE) OR ApplicationDate >= '2026-01-01'
ORDER BY ApplicationID;

-- E.8  ClawbackRate label including the 100% edge
SELECT TOP (10) FundingLineID, Homes, ClawbackRate,
       CASE WHEN ClawbackRate = 1 THEN 'FULL CLAWBACK (100%)'
            WHEN ClawbackRate >= 0.25 THEN 'Heavy'
            WHEN ClawbackRate > 0 THEN 'Light'
            ELSE 'None' END AS ClawbackBand
FROM dbo.FundingLines
ORDER BY ClawbackRate DESC, FundingLineID;

-- E.9  Classify line type, including reversals and zero homes
SELECT CASE WHEN Homes < 0 THEN 'Reversal'
            WHEN Homes = 0 THEN 'Zero homes'
            ELSE 'Funded' END AS LineType,
       COUNT(*) AS Lines
FROM dbo.FundingLines
GROUP BY CASE WHEN Homes < 0 THEN 'Reversal'
              WHEN Homes = 0 THEN 'Zero homes'
              ELSE 'Funded' END;

-- E.10 CASE in ORDER BY: custom sort (Submitted first, then Approved ...)
SELECT TOP (20) ApplicationID, Status
FROM dbo.Applications
ORDER BY CASE Status WHEN 'Submitted' THEN 1 WHEN 'Approved' THEN 2
                     WHEN 'Completed' THEN 3 ELSE 4 END, ApplicationID;

-- E.11 CASE in an UPDATE-style calculation: grant per home after a pretend 10% uplift for mid-range sites
SELECT TOP (10) SiteName, UnitPrice,
       CASE WHEN UnitPrice BETWEEN 20000 AND 100000 THEN UnitPrice * 1.10 ELSE UnitPrice END AS UpliftedGrant
FROM dbo.Sites
ORDER BY SiteID;

-- E.12 IIF and CHOOSE: shortcuts
SELECT TOP (5) SiteName,
       IIF(IsStalled = 1, 'Stalled', 'Active') AS Flag,
       CHOOSE(TenureTypeID % 3 + 1, 'A', 'B', 'C') AS Bucket     -- 1-based; NULL if out of range
FROM dbo.Sites
WHERE TenureTypeID IS NOT NULL
ORDER BY SiteID;

-- E.13 Mixed result types: all branches must be compatible
-- ERROR: SELECT CASE WHEN 1 = 1 THEN 'text' ELSE 5 END;     -- 'text' can't become INT
SELECT CASE WHEN 1 = 1 THEN 'text' ELSE CAST(5 AS VARCHAR(10)) END AS Fine;

-- E.14 Salary band for staff
SELECT TOP (10) FirstName, LastName, Salary,
       CASE WHEN Salary >= 150000 THEN 'Executive'
            WHEN Salary >= 80000  THEN 'Senior'
            ELSE 'Standard' END AS Band
FROM dbo.Staff
ORDER BY Salary DESC;

/* ---- Common mistakes (E) ---------------------------------------------------
   1. CASE col WHEN NULL (E.5) - use WHEN col IS NULL in searched form.
   2. Overlapping conditions in the wrong application (E.4).
   3. Forgetting END, or putting a comma before THEN.
   4. Branches with different data types.
   5. Forgetting ELSE and being surprised by NULLs.
   6. Thinking CASE can run statements. It returns values only.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (E) ------------------------------------------------
   Q1. CASE WHEN 5 > 3 THEN 'A' WHEN 5 > 1 THEN 'B' ELSE 'C' END
   Q2. CASE 2 WHEN 1 THEN 'one' WHEN 2 THEN 'two' END
   Q3. CASE 9 WHEN 1 THEN 'one' END
   Q4. CASE WHEN NULL = NULL THEN 'equal' ELSE 'not equal' END
   Answers: A ; two ; NULL ; not equal.
   ---------------------------------------------------------------------------- */

/* ---- Try it (E) ------------------------------------------------------------
   For each Applicants.HouseholdType show a support label: 'Key worker' -> 'Priority',
   'First-time buyer' -> 'Standard', 'Home mover' -> 'Self-serve', anything else 'Other'. Then
   count applicants per label.
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT F : CASE INSIDE AGGREGATES (PIVOT-STYLE COUNTS)
   ############################################################################
   Put a CASE inside SUM/COUNT to count or add only some rows - producing
   several columns in ONE pass. This turns "rows per tenure" into
   "one column per tenure" (a manual pivot).
       SUM(CASE WHEN cond THEN 1 ELSE 0 END)   -> counts rows matching cond
       COUNT(CASE WHEN cond THEN 1 END)        -> same (COUNT skips the NULL)
       SUM(CASE WHEN cond THEN amount END)     -> total of matching rows
   ########################################################################## */

-- F.1  Applications by status as COLUMNS
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN Status = 'Submitted'   THEN 1 ELSE 0 END) AS Submitted,
       SUM(CASE WHEN Status = 'Approved'   THEN 1 ELSE 0 END) AS Approved,
       SUM(CASE WHEN Status = 'Completed' THEN 1 ELSE 0 END) AS Completed,
       SUM(CASE WHEN Status = 'Withdrawn' THEN 1 ELSE 0 END) AS Withdrawn,
       SUM(CASE WHEN Status = 'Rejected'  THEN 1 ELSE 0 END) AS Rejected
FROM dbo.Applications;

-- F.2  Status columns BY YEAR (GROUP BY + pivot)
SELECT YEAR(ApplicationDate) AS Yr,
       COUNT(*) AS Applications,
       COUNT(CASE WHEN Status = 'Completed' THEN 1 END) AS Completed,
       COUNT(CASE WHEN Status = 'Withdrawn' THEN 1 END) AS Withdrawn,
       COUNT(CASE WHEN Status = 'Rejected'  THEN 1 END) AS Rejected
FROM dbo.Applications
GROUP BY YEAR(ApplicationDate)
ORDER BY Yr;

-- F.3  Cancel rate per year (watch integer division!)
SELECT YEAR(ApplicationDate) AS Yr,
       CAST(100.0 * SUM(CASE WHEN Status = 'Withdrawn' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS CancelPct
FROM dbo.Applications
GROUP BY YEAR(ApplicationDate)
ORDER BY Yr;

-- F.4  Conditional SUM: net funding split into funded homes vs reversals
SELECT SUM(CASE WHEN Homes > 0 THEN Homes * GrantPerHome * (1 - ClawbackRate) ELSE 0 END) AS FundedNetFunding,
       SUM(CASE WHEN Homes < 0 THEN Homes * GrantPerHome * (1 - ClawbackRate) ELSE 0 END) AS ReversalsValue,
       SUM(Homes * GrantPerHome * (1 - ClawbackRate))                                       AS NetNetFunding
FROM dbo.FundingLines;

-- F.5  Applicants by household type as columns, per country
SELECT TOP (10) Country,
       COUNT(*) AS Applicants,
       SUM(CASE WHEN HouseholdType = 'First-time buyer'    THEN 1 ELSE 0 END) AS FirstTimeBuyer,
       SUM(CASE WHEN HouseholdType = 'Key worker'   THEN 1 ELSE 0 END) AS KeyWorker,
       SUM(CASE WHEN HouseholdType = 'Home mover' THEN 1 ELSE 0 END) AS HomeMover
FROM dbo.Applicants
GROUP BY Country
ORDER BY Applicants DESC;

-- F.6  Contactability report in one row
SELECT COUNT(*) AS Applicants,
       SUM(CASE WHEN Email IS NULL THEN 1 ELSE 0 END)           AS EmailNull,
       SUM(CASE WHEN Email = ''    THEN 1 ELSE 0 END)           AS EmailEmpty,
       SUM(CASE WHEN Email LIKE '%@%' THEN 1 ELSE 0 END)        AS EmailValidish,
       SUM(CASE WHEN Phone IS NULL THEN 1 ELSE 0 END)           AS PhoneNull,
       SUM(CASE WHEN Email IS NULL AND Phone IS NULL THEN 1 ELSE 0 END) AS Unreachable
FROM dbo.Applicants;

-- F.7  Line type counts per application (which applications have reversals?)
SELECT TOP (10) ApplicationID,
       SUM(CASE WHEN Homes > 0 THEN 1 ELSE 0 END) AS FundedLines,
       SUM(CASE WHEN Homes < 0 THEN 1 ELSE 0 END) AS ReversalLines,
       SUM(CASE WHEN ClawbackRate = 1 THEN 1 ELSE 0 END) AS FullClawbackLines
FROM dbo.FundingLines
GROUP BY ApplicationID
HAVING SUM(CASE WHEN Homes < 0 THEN 1 ELSE 0 END) > 0
ORDER BY ApplicationID;

-- F.8  Year-over-year columns: net funding 2023 vs 2024 side by side
SELECT SUM(CASE WHEN a.ApplicationDate >= '2023-01-01' AND a.ApplicationDate < '2024-01-01'
                THEN fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate) END) AS Net2023,
       SUM(CASE WHEN a.ApplicationDate >= '2024-01-01' AND a.ApplicationDate < '2025-01-01'
                THEN fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate) END) AS Net2024
FROM dbo.Applications AS a
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID;

-- F.9  Quarterly pivot for FY 2024/25 (UK financial year: Q1 = Apr-Jun ... Q4 = Jan-Mar)
SELECT SUM(CASE WHEN MONTH(ApplicationDate) BETWEEN 4  AND 6  THEN 1 ELSE 0 END) AS FY_Q1_AprJun,
       SUM(CASE WHEN MONTH(ApplicationDate) BETWEEN 7  AND 9  THEN 1 ELSE 0 END) AS FY_Q2_JulSep,
       SUM(CASE WHEN MONTH(ApplicationDate) BETWEEN 10 AND 12 THEN 1 ELSE 0 END) AS FY_Q3_OctDec,
       SUM(CASE WHEN MONTH(ApplicationDate) BETWEEN 1  AND 3  THEN 1 ELSE 0 END) AS FY_Q4_JanMar
FROM dbo.Applications
WHERE ApplicationDate >= '2024-04-01' AND ApplicationDate < '2025-04-01';

-- F.10 Site grant-per-home bands by tenure
SELECT TenureTypeID,
       COUNT(*) AS Sites,
       COUNT(CASE WHEN UnitPrice = 0 THEN 1 END)                  AS LandOnly,
       COUNT(CASE WHEN UnitPrice > 0 AND UnitPrice < 50000 THEN 1 END) AS Under50k,
       COUNT(CASE WHEN UnitPrice >= 50000 THEN 1 END)             AS Over50k
FROM dbo.Sites
GROUP BY TenureTypeID
ORDER BY TenureTypeID;

-- F.11 Average only over some rows: AVG ignores the NULLs CASE produces
SELECT AVG(CASE WHEN Status = 'Completed' THEN AdminFee END) AS AvgAdminFeeCompleted,
       AVG(CASE WHEN Status = 'Withdrawn' THEN AdminFee END) AS AvgAdminFeeWithdrawn
FROM dbo.Applications;
-- If you wrote ELSE 0, the AVG would be dragged down. Leave ELSE out for AVG!

-- F.12 Using PIVOT-style counts for departments
SELECT Directorate,
       COUNT(*) AS Headcount,
       SUM(CASE WHEN Salary >= 80000 THEN 1 ELSE 0 END) AS HighEarners,
       MAX(Salary) AS TopSalary
FROM dbo.Staff
GROUP BY Directorate;

/* ---- Common mistakes (F) ---------------------------------------------------
   1. ELSE 0 inside AVG (F.11) - zeros count as data.
   2. COUNT(CASE WHEN ... THEN 1 ELSE 0 END) counts EVERY row (0 is not NULL).
      Use SUM for the ELSE 0 form, or COUNT with no ELSE.
   3. Integer division in percentages (F.3).
   4. Hard-coding a pivot when tenure types change often (then use PIVOT/dynamic SQL).
   5. Mixing the conditional filter and WHERE: WHERE removes rows from ALL columns.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (F) ------------------------------------------------
   Four rows with Status: Completed, Completed, Withdrawn, Submitted.
   Q1. COUNT(CASE WHEN Status='Completed' THEN 1 ELSE 0 END)   -> 4
   Q2. SUM(CASE WHEN Status='Completed' THEN 1 ELSE 0 END)     -> 2
   Q3. COUNT(CASE WHEN Status='Completed' THEN 1 END)          -> 2
   Q4. AdminFee 10,20,NULL,30: AVG(AdminFee)=20 but AVG(ISNULL(AdminFee,0))=15.
   ---------------------------------------------------------------------------- */

/* ---- Try it (F) ------------------------------------------------------------
   One row per HouseholdType (via Applicants JOIN Applications): total applications and, as columns,
   applications from 2022, 2023, 2024, 2025 (use date ranges, not BETWEEN).
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT G : LOGICAL ORDER OF QUERY EXECUTION
   ############################################################################
   You WRITE a query in this application:  SELECT, FROM, WHERE, GROUP BY, HAVING, ORDER BY
   SQL Server LOGICALLY processes it in this application:

       1. FROM / JOIN       (build the row set)
       2. WHERE             (filter rows)
       3. GROUP BY          (make groups)
       4. HAVING            (filter groups)
       5. SELECT            (compute columns, aliases are born here)
       6. DISTINCT
       7. ORDER BY          (can use aliases)
       8. TOP / OFFSET-FETCH

   This explains almost every "why can't I use that alias / aggregate here?" error.
   ########################################################################## */

-- G.1  Alias is born in SELECT (step 5) so ORDER BY (step 7) can use it ...
SELECT Status, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY Status
ORDER BY Applications DESC;

-- G.2  ... but WHERE (step 2) cannot
-- ERROR: SELECT ApplicationID, AdminFee * 2 AS DoubleAdminFee FROM dbo.Applications WHERE DoubleAdminFee > 50;
SELECT ApplicationID, AdminFee * 2 AS DoubleAdminFee
FROM dbo.Applications
WHERE AdminFee * 2 > 50;                 -- repeat the expression

-- G.3  ... a derived table makes the alias available "earlier"
SELECT *
FROM (SELECT ApplicationID, AdminFee * 2 AS DoubleAdminFee FROM dbo.Applications) AS x
WHERE DoubleAdminFee > 50;

-- G.4  WHERE runs before GROUP BY: the filtered rows are what get counted
SELECT COUNT(*) AS AllApplications FROM dbo.Applications;
SELECT COUNT(*) AS Completed FROM dbo.Applications WHERE Status = 'Completed';

-- G.5  HAVING runs after: it can see group totals, WHERE cannot
SELECT ApplicantID, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY ApplicantID
HAVING COUNT(*) > 15;

-- G.6  Row-by-row trace of one query
--  Question: "Which years had more than 10,000 completed applications?"
SELECT YEAR(ApplicationDate) AS Yr,                   -- 5. compute Yr
       COUNT(*)        AS Completed             -- 5. compute count
FROM dbo.Applications                                 -- 1. take all 60,000 applications
WHERE Status = 'Completed'                      -- 2. keep completed rows only
GROUP BY YEAR(ApplicationDate)                        -- 3. one bucket per year
HAVING COUNT(*) > 10000                         -- 4. drop small buckets
ORDER BY Yr;                                    -- 7. sort

-- G.7  DISTINCT then ORDER BY: ORDER BY must use selected columns with DISTINCT
SELECT DISTINCT Status FROM dbo.Applications ORDER BY Status;
-- ERROR: SELECT DISTINCT Status FROM dbo.Applications ORDER BY ApplicationDate;
--        "ORDER BY items must appear in the select list if SELECT DISTINCT is specified."

-- G.8  TOP is last: it picks from the SORTED result
SELECT TOP (3) SiteName, UnitPrice FROM dbo.Sites ORDER BY UnitPrice DESC;
-- Without ORDER BY, TOP gives "any 3 rows" - not reliable.

-- G.9  Window/SELECT-level expressions can't be grouped by alias
-- ERROR: SELECT YEAR(ApplicationDate) AS Yr, COUNT(*) FROM dbo.Applications GROUP BY Yr;
SELECT YEAR(ApplicationDate) AS Yr, COUNT(*) AS Applications
FROM dbo.Applications GROUP BY YEAR(ApplicationDate);

-- G.10 Filtering a CASE-based label: WHERE cannot see the label either
SELECT *
FROM (SELECT SiteID, SiteName,
             CASE WHEN UnitPrice = 0 THEN 'LandOnly' ELSE 'Grant-funded' END AS Kind
      FROM dbo.Sites) AS sk
WHERE Kind = 'LandOnly';

-- G.11 Putting a condition in WHERE vs inside the aggregate changes the answer
SELECT COUNT(*) AS AllApplications,
       COUNT(CASE WHEN AdminFee IS NULL THEN 1 END) AS NullAdminFee
FROM dbo.Applications;                       -- both numbers in ONE pass
-- A WHERE AdminFee IS NULL would give only the second number, and lose the first.

-- G.12 Same logical application applies to joins: the join happens BEFORE WHERE
SELECT TOP (5) ap.ApplicantID, COUNT(a.ApplicationID) AS Applications
FROM dbo.Applicants AS ap
LEFT JOIN dbo.Applications AS a ON a.ApplicantID = ap.ApplicantID
WHERE ap.Region = 'North West'
GROUP BY ap.ApplicantID
ORDER BY Applications;                       -- joins covered fully in Module 06

/* ---- Common mistakes (G) ---------------------------------------------------
   1. Using a SELECT alias in WHERE, GROUP BY or HAVING.
   2. Using an aggregate in WHERE.
   3. Believing TOP applies before ORDER BY.
   4. Expecting GROUP BY to sort.
   5. Filtering on the "pretty" value (FORMAT) rather than the real one.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (G) ------------------------------------------------
   Put these in the sequence SQL Server processes them:
       ORDER BY, HAVING, FROM, SELECT, WHERE, GROUP BY
   Answer: FROM, WHERE, GROUP BY, HAVING, SELECT, ORDER BY.
   Does this work?  SELECT Status s FROM dbo.Applications ORDER BY s;   -> yes.
   Does this work?  SELECT Status s FROM dbo.Applications WHERE s = 'x';  -> no.
   ---------------------------------------------------------------------------- */

/* ---- Try it (G) ------------------------------------------------------------
   Rewrite this broken query so it works, and say which step each fix touches:
       SELECT HouseholdType AS Seg, COUNT(*) AS N
       FROM dbo.Applicants
       WHERE N > 100
       GROUP BY Seg;
   ---------------------------------------------------------------------------- */
GO

/* ===================== END OF MODULE 05 =====================
   Next: module06_joins.sql
   ============================================================ */
