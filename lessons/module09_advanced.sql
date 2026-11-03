USE HousingDelivery;
GO
/* ============================================================================
   MODULE 09 - ADVANCED T-SQL: CTEs, WINDOW FUNCTIONS, PROCEDURES, FUNCTIONS
   Database : HousingDelivery (see SPEC.md)     Target : SQL Server 2019+ / SSMS
   Net funding : Homes * GrantPerHome * (1 - ClawbackRate)
   Financial year (FY) : April-March. 31 Mar 2025 is FY 2024/25; 1 Apr 2025 is FY 2025/26.

   Run one example at a time (highlight + F5). Failing examples live in
   commented-out "Common mistakes" blocks. Objects this module creates:
   dbo.fn_FinancialYear, dbo.fn_NetFunding, dbo.usp_RegionSummary,
   dbo.usp_TopSitesByRegion, dbo.usp_FinYearSummary, dbo.usp_ApplicationCount,
   dbo.usp_SetSiteStalled. Data-changing demos use #temp tables or BEGIN TRAN/ROLLBACK.

   CONCEPTS
     A. CTEs (WITH ... AS)
     B. Recursive CTEs (Staff hierarchy)
     C. Ranking: ROW_NUMBER, RANK, DENSE_RANK, NTILE
     D. PARTITION BY and aggregate window functions
     E. Running totals (net funding by financial year)
     F. LAG / LEAD (month-over-month completions)
     G. Top N per group, and de-duplication with ROW_NUMBER
     H. Scalar functions (dbo.fn_FinancialYear)
     I. Stored procedures with parameters (dbo.usp_RegionSummary @Region)

   MENTAL MODEL: a window function looks at a "window" of related rows around
   the current row WITHOUT collapsing them (unlike GROUP BY). A CTE is simply
   a name you give to a query so later queries can read it like a table.
   ============================================================================ */


/* ############################################################################
   CONCEPT A : CTEs  (COMMON TABLE EXPRESSIONS)
   ############################################################################
   WITH Name AS ( query ) followed by ONE statement that uses Name. Think of it
   as a sticky note naming an intermediate result. It makes long queries readable
   (top to bottom) and lets you chain steps: first CTE feeds the second.
   The CTE lives only for that one statement. The statement BEFORE a WITH must
   end with a semicolon.
   ########################################################################## */

-- A.1  The basics: region totals, then filter
WITH RegionTotals AS (
    SELECT Region, COUNT(*) AS Sites, SUM(PlannedHomes) AS PlannedHomes
    FROM dbo.Sites
    GROUP BY Region
)
SELECT Region, Sites, PlannedHomes
FROM RegionTotals
WHERE PlannedHomes > 5000
ORDER BY PlannedHomes DESC;

-- A.2  Use the CTE twice: regions versus the average region
WITH RegionTotals AS (
    SELECT Region, SUM(PlannedHomes) AS PlannedHomes FROM dbo.Sites GROUP BY Region
)
SELECT r.Region, r.PlannedHomes,
       r.PlannedHomes - a.AvgHomes AS DiffFromAvg
FROM RegionTotals AS r
CROSS JOIN (SELECT AVG(1.0 * PlannedHomes) AS AvgHomes FROM RegionTotals) AS a
ORDER BY DiffFromAvg DESC;

-- A.3  Column names listed in brackets (alternative to aliasing inside)
WITH Tenures (TenureTypeID, SiteCount) AS (
    SELECT TenureTypeID, COUNT(*) FROM dbo.Sites GROUP BY TenureTypeID
)
SELECT t.TenureName, ISNULL(x.SiteCount, 0) AS SiteCount
FROM dbo.TenureTypes AS t
LEFT JOIN Tenures AS x ON x.TenureTypeID = t.TenureTypeID
ORDER BY SiteCount DESC;

-- A.4  Chained CTEs: net funding per application -> per financial year
WITH AppNet AS (
    SELECT a.ApplicationID, a.ApplicationDate,
           SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate)) AS NetFunding
    FROM dbo.Applications AS a
    JOIN dbo.FundingLines AS f ON f.ApplicationID = a.ApplicationID
    GROUP BY a.ApplicationID, a.ApplicationDate
),
AppFY AS (
    SELECT ApplicationID, NetFunding,
           CASE WHEN MONTH(ApplicationDate) >= 4 THEN YEAR(ApplicationDate) ELSE YEAR(ApplicationDate) - 1 END AS FYStart
    FROM AppNet
)
SELECT CAST(FYStart AS CHAR(4)) + '/' + RIGHT(CAST(FYStart + 1 AS VARCHAR(4)), 2) AS FinYear,
       COUNT(*) AS Applications, SUM(NetFunding) AS NetFunding
FROM AppFY
GROUP BY FYStart
ORDER BY FYStart;

-- A.5  Applicants who applied more than the average applicant
WITH PerApplicant AS (
    SELECT ApplicantID, COUNT(*) AS Apps FROM dbo.Applications GROUP BY ApplicantID
)
SELECT TOP (10) ApplicantID, Apps
FROM PerApplicant
WHERE Apps > (SELECT AVG(1.0 * Apps) FROM PerApplicant)
ORDER BY Apps DESC, ApplicantID;

-- A.6  CTE + NOT EXISTS: partners that have sites but none of them ever funded
--      (expected: 0 rows - every partner has at least one funded site; a clean-data check)
WITH FundedSites AS (SELECT DISTINCT SiteID FROM dbo.FundingLines)
SELECT p.PartnerID, p.PartnerName
FROM dbo.Partners AS p
WHERE EXISTS (SELECT 1 FROM dbo.Sites s WHERE s.PartnerID = p.PartnerID)
  AND NOT EXISTS (SELECT 1 FROM dbo.Sites s JOIN FundedSites fs ON fs.SiteID = s.SiteID WHERE s.PartnerID = p.PartnerID);

-- A.7  A CTE as a data-quality dashboard (one row per issue)
WITH Issues AS (
    SELECT 'Applicants with NULL email'        AS Issue, COUNT(*) AS Cnt FROM dbo.Applicants WHERE Email IS NULL
    UNION ALL SELECT 'Applicants with empty email',      COUNT(*) FROM dbo.Applicants WHERE Email = ''
    UNION ALL SELECT 'Applications in the future',       COUNT(*) FROM dbo.Applications WHERE ApplicationDate >= '2026-01-01'
    UNION ALL SELECT 'Completed before applied',         COUNT(*) FROM dbo.Applications WHERE CompletionDate < CAST(ApplicationDate AS DATE)
    UNION ALL SELECT 'Applications with no funding line',COUNT(*) FROM dbo.Applications a
                                                          WHERE NOT EXISTS (SELECT 1 FROM dbo.FundingLines f WHERE f.ApplicationID = a.ApplicationID)
    UNION ALL SELECT 'Sites with no tenure',             COUNT(*) FROM dbo.Sites WHERE TenureTypeID IS NULL
)
SELECT Issue, Cnt FROM Issues ORDER BY Cnt DESC;

-- A.8  CTE with TOP and ORDER BY inside (allowed when TOP is present)
WITH TopGrant AS (
    SELECT TOP (5) SiteID, SiteName, UnitPrice FROM dbo.Sites ORDER BY UnitPrice DESC, SiteID
)
SELECT t.SiteName, t.UnitPrice, p.PartnerName
FROM TopGrant AS t
JOIN dbo.Sites AS s ON s.SiteID = t.SiteID
JOIN dbo.Partners AS p ON p.PartnerID = s.PartnerID
ORDER BY t.UnitPrice DESC;

-- A.9  Year-on-year change by FY (CTE joined to itself)
WITH FY AS (
    SELECT CASE WHEN MONTH(a.ApplicationDate) >= 4 THEN YEAR(a.ApplicationDate) ELSE YEAR(a.ApplicationDate) - 1 END AS FYStart,
           SUM(f.Homes) AS Homes
    FROM dbo.Applications a JOIN dbo.FundingLines f ON f.ApplicationID = a.ApplicationID
    WHERE a.ApplicationDate < '2026-01-01'
    GROUP BY CASE WHEN MONTH(a.ApplicationDate) >= 4 THEN YEAR(a.ApplicationDate) ELSE YEAR(a.ApplicationDate) - 1 END
)
SELECT cur.FYStart, cur.Homes, prev.Homes AS PrevHomes, cur.Homes - prev.Homes AS Change
FROM FY AS cur
LEFT JOIN FY AS prev ON prev.FYStart = cur.FYStart - 1
ORDER BY cur.FYStart;

-- A.10 A CTE can feed DELETE/UPDATE (here on a temp copy): remove land-only sites
DROP TABLE IF EXISTS #SitesCopy;
SELECT * INTO #SitesCopy FROM dbo.Sites;
WITH LandOnly AS (SELECT * FROM #SitesCopy WHERE UnitPrice = 0)
DELETE FROM LandOnly;
SELECT COUNT(*) AS RowsLeft FROM #SitesCopy;
DROP TABLE #SitesCopy;

-- A.11 Different aggregation levels side by side (site count and funded-site count per region)
WITH AllSites AS (SELECT Region, COUNT(*) AS Sites FROM dbo.Sites GROUP BY Region),
     Funded   AS (SELECT s.Region, COUNT(DISTINCT s.SiteID) AS FundedSites
                  FROM dbo.Sites s JOIN dbo.FundingLines f ON f.SiteID = s.SiteID GROUP BY s.Region)
SELECT a.Region, a.Sites, ISNULL(f.FundedSites, 0) AS FundedSites,
       CAST(100.0 * ISNULL(f.FundedSites, 0) / a.Sites AS DECIMAL(5,1)) AS PctFunded
FROM AllSites a LEFT JOIN Funded f ON f.Region = a.Region
ORDER BY PctFunded;

/* --- Common mistakes (A) -------------------------------------------------------
-- ERROR: the CTE only lives for ONE statement; the second SELECT cannot see it
WITH R AS (SELECT Region FROM dbo.Sites GROUP BY Region) SELECT * FROM R;
SELECT * FROM R;

-- ERROR: the statement before WITH has no semicolon
SELECT 1
WITH R AS (SELECT 1 AS x) SELECT * FROM R;

-- ERROR: CTE column without a name
WITH R AS (SELECT Region, COUNT(*) FROM dbo.Sites GROUP BY Region) SELECT * FROM R;

-- GOTCHA: a CTE is NOT stored. Used twice, it is calculated twice. Heavy? use a #temp table.
----------------------------------------------------------------------------- */

/* --- Predict the output (A) ---------------------------------------------------
   A.4 - the first FY row is 2021/22 (Jan-Mar 2022 only, a partial year) and the last
   rows include the future-dated 2026 applications unless you filter them out as A.9 does.
   A.7 - which issue has the biggest count? (empty/NULL emails or no-funding-line apps)
   A.10 - RowsLeft = 500 minus the number of land-only sites.
----------------------------------------------------------------------------- */

-- Try it (A): with two chained CTEs, find the region whose AVERAGE UnitPrice (grant-funded sites only,
-- UnitPrice > 0) is highest, and show that average.


/* ############################################################################
   CONCEPT B : RECURSIVE CTEs  (THE STAFF HIERARCHY)
   ############################################################################
   A recursive CTE has two parts joined by UNION ALL:
     ANCHOR    - the starting rows (the Chief Executive, ManagerID IS NULL)
     RECURSIVE - joins the table back to the CTE itself to find the next level
   It repeats until no new rows appear. SQL Server stops at 100 levels unless
   you say OPTION (MAXRECURSION n). Use it for org charts, folders, parts lists.
   ########################################################################## */

-- B.1  Warm-up: count from 1 to 10
WITH n AS (
    SELECT 1 AS Num
    UNION ALL
    SELECT Num + 1 FROM n WHERE Num < 10
)
SELECT Num FROM n;

-- B.2  A calendar of every month in FY 2024/25 (handy for filling gaps later)
WITH m AS (
    SELECT CAST('2024-04-01' AS DATE) AS MonthStart
    UNION ALL
    SELECT DATEADD(MONTH, 1, MonthStart) FROM m WHERE MonthStart < '2025-03-01'
)
SELECT MonthStart, EOMONTH(MonthStart) AS MonthEnd FROM m;

-- B.3  The Staff org chart, top-down, with level number
WITH Org AS (
    SELECT StaffID, FirstName, LastName, JobTitle, ManagerID, 0 AS Lvl
    FROM dbo.Staff
    WHERE ManagerID IS NULL
    UNION ALL
    SELECT s.StaffID, s.FirstName, s.LastName, s.JobTitle, s.ManagerID, o.Lvl + 1
    FROM dbo.Staff AS s
    JOIN Org AS o ON s.ManagerID = o.StaffID
)
SELECT Lvl, StaffID, FirstName, LastName, JobTitle, ManagerID
FROM Org
ORDER BY Lvl, StaffID;

-- B.4  Indented tree, siblings together (sort by a built-up path)
WITH Org AS (
    SELECT StaffID, FirstName, LastName, JobTitle, 0 AS Lvl,
           CAST(RIGHT('00000' + CAST(StaffID AS VARCHAR(5)), 5) AS VARCHAR(1000)) AS SortPath
    FROM dbo.Staff WHERE ManagerID IS NULL
    UNION ALL
    SELECT s.StaffID, s.FirstName, s.LastName, s.JobTitle, o.Lvl + 1,
           CAST(o.SortPath + '/' + RIGHT('00000' + CAST(s.StaffID AS VARCHAR(5)), 5) AS VARCHAR(1000))
    FROM dbo.Staff AS s JOIN Org AS o ON s.ManagerID = o.StaffID
)
SELECT REPLICATE('    ', Lvl) + FirstName + ' ' + LastName + '  -  ' + JobTitle AS OrgChart
FROM Org
ORDER BY SortPath;

-- B.5  Chain of command as text: "CE > Director > Manager > Person"
WITH Org AS (
    SELECT StaffID, CAST(FirstName + ' ' + LastName AS NVARCHAR(1000)) AS Chain, 0 AS Lvl
    FROM dbo.Staff WHERE ManagerID IS NULL
    UNION ALL
    SELECT s.StaffID, CAST(o.Chain + N' > ' + s.FirstName + N' ' + s.LastName AS NVARCHAR(1000)), o.Lvl + 1
    FROM dbo.Staff s JOIN Org o ON s.ManagerID = o.StaffID
)
SELECT TOP (10) Lvl, Chain FROM Org WHERE Lvl >= 2 ORDER BY Chain;

-- B.6  Bottom-up: walk UP from one person to the Chief Executive
WITH Up AS (
    SELECT StaffID, ManagerID, FirstName, LastName, JobTitle, 0 AS StepsUp
    FROM dbo.Staff WHERE StaffID = (SELECT MAX(StaffID) FROM dbo.Staff)
    UNION ALL
    SELECT m.StaffID, m.ManagerID, m.FirstName, m.LastName, m.JobTitle, u.StepsUp + 1
    FROM dbo.Staff m JOIN Up u ON m.StaffID = u.ManagerID
)
SELECT StepsUp, FirstName, LastName, JobTitle FROM Up ORDER BY StepsUp;

-- B.7  How many levels deep is the organisation, and how many staff at each level?
WITH Org AS (
    SELECT StaffID, 0 AS Lvl FROM dbo.Staff WHERE ManagerID IS NULL
    UNION ALL
    SELECT s.StaffID, o.Lvl + 1 FROM dbo.Staff s JOIN Org o ON s.ManagerID = o.StaffID
)
SELECT Lvl, COUNT(*) AS StaffAtLevel FROM Org GROUP BY Lvl ORDER BY Lvl;

-- B.8  Everyone below each manager: total reports at any depth (not just direct)
WITH Below AS (
    SELECT StaffID AS RootID, StaffID AS MemberID FROM dbo.Staff
    UNION ALL
    SELECT b.RootID, s.StaffID FROM Below b JOIN dbo.Staff s ON s.ManagerID = b.MemberID
)
SELECT TOP (10) st.StaffID, st.FirstName, st.LastName, st.JobTitle, COUNT(*) - 1 AS TotalReports
FROM Below b JOIN dbo.Staff st ON st.StaffID = b.RootID
GROUP BY st.StaffID, st.FirstName, st.LastName, st.JobTitle
ORDER BY TotalReports DESC, st.StaffID;

-- B.9  Salary cost of each manager's whole branch
WITH Below AS (
    SELECT StaffID AS RootID, StaffID AS MemberID, Salary FROM dbo.Staff
    UNION ALL
    SELECT b.RootID, s.StaffID, s.Salary FROM Below b JOIN dbo.Staff s ON s.ManagerID = b.MemberID
)
SELECT TOP (5) RootID, SUM(Salary) AS BranchSalaryCost, COUNT(*) AS BranchSize
FROM Below GROUP BY RootID ORDER BY BranchSalaryCost DESC, RootID;

-- B.10 Staff with no direct reports (leaf nodes)
SELECT s.StaffID, s.LastName, s.JobTitle
FROM dbo.Staff s
WHERE NOT EXISTS (SELECT 1 FROM dbo.Staff r WHERE r.ManagerID = s.StaffID)
ORDER BY s.StaffID
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;

-- B.11 Generate 365 days: needs a higher recursion limit (default is 100)
WITH d AS (
    SELECT CAST('2024-04-01' AS DATE) AS Dt
    UNION ALL
    SELECT DATEADD(DAY, 1, Dt) FROM d WHERE Dt < '2025-03-31'
)
SELECT COUNT(*) AS DaysInFY2425, MIN(Dt) AS FirstDay, MAX(Dt) AS LastDay FROM d
OPTION (MAXRECURSION 400);

-- B.12 Does anyone earn more than their boss? (recursion not needed, but shows the self-join first)
--      Expected: 0 rows - nobody does.
SELECT e.StaffID, e.LastName, e.Salary, m.LastName AS Boss, m.Salary AS BossSalary
FROM dbo.Staff e JOIN dbo.Staff m ON m.StaffID = e.ManagerID
WHERE e.Salary > m.Salary;

/* --- Common mistakes (B) -------------------------------------------------------
-- ERROR: infinite loop. Forgetting the stop condition (or a cycle in the data) ends with
--        "maximum recursion 100 has been exhausted".
WITH n AS (SELECT 1 AS Num UNION ALL SELECT Num + 1 FROM n) SELECT * FROM n;
-- ERROR: anchor and recursive part have different data types for a column (e.g. Chain VARCHAR vs longer string)
--        -> CAST both to the same type, as in B.5
-- ERROR: UNION instead of UNION ALL in the recursive CTE
-- WRONG: forgetting WHERE ManagerID IS NULL in the anchor -> every person becomes a "root"
-- DEFENCE: add OPTION (MAXRECURSION 20) on org charts so a bad ManagerID loop fails fast
----------------------------------------------------------------------------- */

/* --- Predict the output (B) ---------------------------------------------------
   B.1: 10 rows. B.2: 12 rows, April to March. B.7: 4 levels (0..3), counts add to 60.
   B.8: the Chief Executive has the most reports (59). B.11: 365 days (2024 is a leap year, but
   29 Feb 2024 falls in FY 2023/24 so this FY has 365 days).
----------------------------------------------------------------------------- */

-- Try it (B): list every person in the Chief Executive's tree who is at Lvl 2 and earns more than the
-- average salary of ALL level-2 staff.


/* ############################################################################
   CONCEPT C : RANKING FUNCTIONS
   ############################################################################
   ROW_NUMBER() 1,2,3,4 - always unique, ties broken arbitrarily
   RANK()       1,2,2,4 - ties share a rank, then a gap
   DENSE_RANK() 1,2,2,3 - ties share a rank, no gap
   NTILE(n)     splits rows into n roughly equal buckets (quartiles = NTILE(4))
   All need OVER (ORDER BY ...). Add PARTITION BY to restart numbering per group.
   You cannot filter on them directly in WHERE - wrap in a CTE first.
   ########################################################################## */

-- C.1  ROW_NUMBER over all staff by salary
SELECT TOP (12) StaffID, LastName, Salary,
       ROW_NUMBER() OVER (ORDER BY Salary DESC) AS RowNum
FROM dbo.Staff
ORDER BY RowNum;

-- C.2  The three side by side: tied salaries expose the difference
SELECT TOP (15) StaffID, LastName, Salary,
       ROW_NUMBER() OVER (ORDER BY Salary DESC) AS RowNum,
       RANK()       OVER (ORDER BY Salary DESC) AS Rnk,
       DENSE_RANK() OVER (ORDER BY Salary DESC) AS DenseRnk
FROM dbo.Staff
ORDER BY Salary DESC, StaffID;

-- C.3  Make ROW_NUMBER deterministic with a tie-breaker (ORDER BY Salary DESC, StaffID)
SELECT TOP (10) StaffID, LastName, Salary,
       ROW_NUMBER() OVER (ORDER BY Salary DESC, StaffID) AS RowNum
FROM dbo.Staff ORDER BY RowNum;

-- C.4  Rank within each directorate
SELECT Directorate, LastName, Salary,
       DENSE_RANK() OVER (PARTITION BY Directorate ORDER BY Salary DESC) AS RankInDirectorate
FROM dbo.Staff
ORDER BY Directorate, RankInDirectorate, StaffID;

-- C.5  NTILE(4): salary quartiles (1 = top quarter)
SELECT StaffID, LastName, Salary,
       NTILE(4) OVER (ORDER BY Salary DESC, StaffID) AS Quartile
FROM dbo.Staff
ORDER BY Quartile, Salary DESC, StaffID;

-- C.6  NTILE with a number that doesn't divide evenly: 60 people into 7 buckets
--      (the first buckets get one extra person)
SELECT Bucket, COUNT(*) AS People
FROM (SELECT NTILE(7) OVER (ORDER BY Salary DESC, StaffID) AS Bucket FROM dbo.Staff) AS x
GROUP BY Bucket ORDER BY Bucket;

-- C.7  NTILE and ties: two people with the SAME salary can land in different buckets
SELECT Salary, MIN(Quartile) AS LowestQuartile, MAX(Quartile) AS HighestQuartile, COUNT(*) AS People
FROM (SELECT Salary, NTILE(4) OVER (ORDER BY Salary DESC, StaffID) AS Quartile FROM dbo.Staff) AS q
GROUP BY Salary
HAVING MIN(Quartile) <> MAX(Quartile);

-- C.8  Filtering on a window result needs a CTE: the 3 highest salary LEVELS (ties included)
WITH Ranked AS (
    SELECT StaffID, LastName, Salary, DENSE_RANK() OVER (ORDER BY Salary DESC) AS DR
    FROM dbo.Staff
)
SELECT StaffID, LastName, Salary, DR FROM Ranked WHERE DR <= 3 ORDER BY DR, StaffID;
-- more than 3 rows if salaries tie; compare with ROW_NUMBER <= 3 (exactly 3 rows, arbitrary among ties)

-- C.9  Rank sites by planned homes within each region (top 2 per region; RANK keeps ties)
WITH R AS (
    SELECT Region, SiteName, PlannedHomes,
           RANK() OVER (PARTITION BY Region ORDER BY PlannedHomes DESC) AS Rnk
    FROM dbo.Sites
)
SELECT Region, SiteName, PlannedHomes, Rnk FROM R WHERE Rnk <= 2 ORDER BY Region, Rnk, SiteName;

-- C.10 Longest-serving staff in each office (earliest HireDate = rank 1) - ties kept by RANK
WITH R AS (
    SELECT Office, FirstName, LastName, HireDate,
           RANK() OVER (PARTITION BY Office ORDER BY HireDate) AS Seniority
    FROM dbo.Staff
)
SELECT Office, FirstName, LastName, HireDate FROM R WHERE Seniority = 1 ORDER BY Office;

-- C.11 PERCENT_RANK and CUME_DIST: where does each salary sit (0-1)?
SELECT TOP (8) LastName, Salary,
       CAST(PERCENT_RANK() OVER (ORDER BY Salary) AS DECIMAL(5,3)) AS PctRank,
       CAST(CUME_DIST()    OVER (ORDER BY Salary) AS DECIMAL(5,3)) AS CumeDist
FROM dbo.Staff ORDER BY Salary DESC, StaffID;

-- C.12 NULLs sort FIRST in ascending order and LAST in descending: rank applicants by income
SELECT TOP (8) ApplicantID, AnnualIncome,
       DENSE_RANK() OVER (ORDER BY AnnualIncome) AS AscRank    -- NULL income gets rank 1!
FROM dbo.Applicants
ORDER BY AscRank, ApplicantID;

-- C.13 Rank partners by planned homes, but only the ones that own at least one site
WITH PartnerHomes AS (
    SELECT p.PartnerName, SUM(s.PlannedHomes) AS Homes
    FROM dbo.Partners p JOIN dbo.Sites s ON s.PartnerID = p.PartnerID
    GROUP BY p.PartnerName
)
SELECT TOP (5) PartnerName, Homes, RANK() OVER (ORDER BY Homes DESC) AS Rnk FROM PartnerHomes ORDER BY Rnk, PartnerName;

/* --- Common mistakes (C) -------------------------------------------------------
-- ERROR: window function in WHERE
SELECT * FROM dbo.Staff WHERE ROW_NUMBER() OVER (ORDER BY Salary) <= 3;
-- ERROR: ranking functions require ORDER BY in OVER
SELECT ROW_NUMBER() OVER () FROM dbo.Staff;
-- WRONG: ROW_NUMBER without a unique tie-breaker gives a different "top 3" each run for tied salaries
-- WRONG: NTILE(4) assumed to put equal values in the same bucket (it doesn't)
-- WRONG: expecting RANK to have no gaps (use DENSE_RANK)
----------------------------------------------------------------------------- */

/* --- Predict the output (C) ---------------------------------------------------
   C.2: where salaries tie, RowNum differs, Rnk repeats and the next Rnk jumps; DenseRnk repeats and
        continues with the next integer.
   C.6: buckets 1-4 have 9 people, buckets 5-7 have 8 (60 = 4*9 + 3*8).
   C.8: DR <= 3 returns >= 3 rows.  C.12: top rows are NULL-income applicants, all with rank 1.
----------------------------------------------------------------------------- */

-- Try it (C): rank Staff by Salary DESC within each Office with RANK and DENSE_RANK, then list the people
-- who share the top salary in their office (rank 1).


/* ############################################################################
   CONCEPT D : PARTITION BY AND AGGREGATE WINDOW FUNCTIONS
   ############################################################################
   SUM/AVG/COUNT/MIN/MAX followed by OVER (PARTITION BY x) calculate the group
   figure but KEEP every detail row. Compare:
     GROUP BY Directorate  -> one row per directorate
     AVG() OVER (PARTITION BY Directorate) -> one row per person, with the avg beside it
   OVER () with empty brackets means "the whole result set".
   ########################################################################## */

-- D.1  Each person next to their directorate average
SELECT TOP (12) Directorate, LastName, Salary,
       AVG(Salary) OVER (PARTITION BY Directorate) AS DirectorateAvg
FROM dbo.Staff
ORDER BY Directorate, Salary DESC, StaffID;

-- D.2  Difference from that average, and a flag
SELECT TOP (12) Directorate, LastName, Salary,
       Salary - AVG(Salary) OVER (PARTITION BY Directorate) AS DiffFromAvg,
       CASE WHEN Salary > AVG(Salary) OVER (PARTITION BY Directorate) THEN 'Above' ELSE 'At/Below' END AS Position
FROM dbo.Staff
ORDER BY Directorate, DiffFromAvg DESC, StaffID;

-- D.3  Each site's share of its region's planned homes
SELECT TOP (10) Region, SiteName, PlannedHomes,
       CAST(100.0 * PlannedHomes / NULLIF(SUM(PlannedHomes) OVER (PARTITION BY Region), 0) AS DECIMAL(5,2)) AS PctOfRegion
FROM dbo.Sites
ORDER BY Region, PlannedHomes DESC, SiteID;

-- D.4  OVER () = whole table: each region's share of ALL planned homes (no subquery needed)
SELECT DISTINCT Region,
       SUM(PlannedHomes) OVER (PARTITION BY Region) AS RegionHomes,
       SUM(PlannedHomes) OVER ()                    AS AllHomes
FROM dbo.Sites
ORDER BY Region;

-- D.5  Several windows in one query: count, min, max per office
SELECT DISTINCT Office,
       COUNT(*)    OVER (PARTITION BY Office) AS Staff,
       MIN(Salary) OVER (PARTITION BY Office) AS LowestSalary,
       MAX(Salary) OVER (PARTITION BY Office) AS HighestSalary
FROM dbo.Staff ORDER BY Office;

-- D.6  GROUP BY version of D.5 for comparison (same numbers, fewer lines)
SELECT Office, COUNT(*) AS Staff, MIN(Salary) AS LowestSalary, MAX(Salary) AS HighestSalary
FROM dbo.Staff GROUP BY Office ORDER BY Office;

-- D.7  FIRST_VALUE: compare every site's grant with the highest grant in its region
SELECT TOP (10) Region, SiteName, UnitPrice,
       FIRST_VALUE(UnitPrice) OVER (PARTITION BY Region ORDER BY UnitPrice DESC, SiteID) AS RegionMaxGrant
FROM dbo.Sites ORDER BY Region, UnitPrice DESC, SiteID;

-- D.8  LAST_VALUE gotcha: the default frame stops at the current row, so you must widen it
SELECT TOP (6) Region, SiteName, UnitPrice,
       LAST_VALUE(UnitPrice) OVER (PARTITION BY Region ORDER BY UnitPrice DESC, SiteID)                                      AS WrongLast,
       LAST_VALUE(UnitPrice) OVER (PARTITION BY Region ORDER BY UnitPrice DESC, SiteID
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)                                  AS RightLast
FROM dbo.Sites ORDER BY Region, UnitPrice DESC, SiteID;

-- D.9  Applicants: how many share my household type within my region (NULL region = its own group)
SELECT TOP (10) ApplicantID, Region, HouseholdType,
       COUNT(*) OVER (PARTITION BY Region, HouseholdType) AS SameRegionAndType
FROM dbo.Applicants ORDER BY ApplicantID;

-- D.10 Applications per applicant with the applicant's total beside each row
SELECT TOP (10) ApplicantID, ApplicationID, ApplicationDate,
       COUNT(*) OVER (PARTITION BY ApplicantID) AS TotalApps
FROM dbo.Applications
WHERE ApplicantID <= 20
ORDER BY ApplicantID, ApplicationDate;

/* --- Common mistakes (D) -------------------------------------------------------
-- ERROR: mixing a window function with GROUP BY columns that don't include the PARTITION column
SELECT Region, SUM(PlannedHomes), AVG(PlannedHomes) OVER (PARTITION BY TenureTypeID) FROM dbo.Sites GROUP BY Region;
-- WRONG: expecting DISTINCT to be required - without it D.4 returns one row per site
-- WRONG: LAST_VALUE with default frame (see D.8)
-- WRONG: dividing by a window SUM that may be 0 without NULLIF
----------------------------------------------------------------------------- */

/* --- Predict the output (D) ---------------------------------------------------
   D.1: the DirectorateAvg value repeats on every row of a directorate. D.4: AllHomes identical on every row.
   D.8: WrongLast equals UnitPrice on each row, RightLast is the region's lowest grant.
----------------------------------------------------------------------------- */

-- Try it (D): for each office show each person's salary as a percentage of their office's total salary bill.


/* ############################################################################
   CONCEPT E : RUNNING TOTALS (NET FUNDING BY FINANCIAL YEAR)
   ############################################################################
   SUM(x) OVER (ORDER BY y) adds up as you go. Always state the frame:
     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
   If you omit it SQL Server uses RANGE, which treats rows with the SAME
   ORDER BY value as one block - a classic surprise when there are ties.
   ########################################################################## */

-- E.1  Net funding per FY, then a cumulative total across FYs
WITH FY AS (
    SELECT CASE WHEN MONTH(a.ApplicationDate) >= 4 THEN YEAR(a.ApplicationDate) ELSE YEAR(a.ApplicationDate) - 1 END AS FYStart,
           SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate)) AS NetFunding
    FROM dbo.Applications a JOIN dbo.FundingLines f ON f.ApplicationID = a.ApplicationID
    WHERE a.ApplicationDate < '2026-01-01'
    GROUP BY CASE WHEN MONTH(a.ApplicationDate) >= 4 THEN YEAR(a.ApplicationDate) ELSE YEAR(a.ApplicationDate) - 1 END
)
SELECT CAST(FYStart AS CHAR(4)) + '/' + RIGHT(CAST(FYStart + 1 AS VARCHAR(4)), 2) AS FinYear,
       NetFunding,
       SUM(NetFunding) OVER (ORDER BY FYStart ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeNet
FROM FY ORDER BY FYStart;

-- E.2  Stage monthly net funding in a temp table (reused by E.3 - E.8)
DROP TABLE IF EXISTS #MonthlyNet;
SELECT DATEFROMPARTS(YEAR(a.ApplicationDate), MONTH(a.ApplicationDate), 1) AS MonthStart,
       SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate)) AS NetFunding,
       SUM(f.Homes) AS Homes
INTO #MonthlyNet
FROM dbo.Applications a JOIN dbo.FundingLines f ON f.ApplicationID = a.ApplicationID
WHERE a.ApplicationDate < '2026-01-01'
GROUP BY DATEFROMPARTS(YEAR(a.ApplicationDate), MONTH(a.ApplicationDate), 1);
SELECT TOP (6) * FROM #MonthlyNet ORDER BY MonthStart;

-- E.3  Running total that RESTARTS each financial year ("FY to date")
SELECT MonthStart, NetFunding,
       CASE WHEN MONTH(MonthStart) >= 4 THEN YEAR(MonthStart) ELSE YEAR(MonthStart) - 1 END AS FYStart,
       SUM(NetFunding) OVER (PARTITION BY CASE WHEN MONTH(MonthStart) >= 4 THEN YEAR(MonthStart) ELSE YEAR(MonthStart) - 1 END
                             ORDER BY MonthStart ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS FYToDate
FROM #MonthlyNet
WHERE MonthStart >= '2024-01-01' AND MonthStart < '2026-01-01'
ORDER BY MonthStart;
-- watch FYToDate drop back to a single month in April: the FY boundary

-- E.4  Cumulative % of the financial-year total reached by each month (FY 2024/25 only)
SELECT MonthStart, NetFunding,
       CAST(100.0 * SUM(NetFunding) OVER (ORDER BY MonthStart ROWS UNBOUNDED PRECEDING)
            / SUM(NetFunding) OVER () AS DECIMAL(5,1)) AS CumPctOfFY
FROM #MonthlyNet
WHERE MonthStart >= '2024-04-01' AND MonthStart < '2025-04-01'
ORDER BY MonthStart;

-- E.5  Moving 3-month average (current month + 2 before)
SELECT MonthStart, NetFunding,
       AVG(NetFunding) OVER (ORDER BY MonthStart ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS Avg3M
FROM #MonthlyNet
WHERE MonthStart >= '2024-04-01' AND MonthStart < '2025-04-01'
ORDER BY MonthStart;

-- E.6  The ROWS vs RANGE surprise: running count of sites by region - ties on Region
SELECT Region, SiteID,
       COUNT(*) OVER (ORDER BY Region)                                         AS Default_RANGE,
       COUNT(*) OVER (ORDER BY Region ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS Explicit_ROWS
FROM (SELECT TOP (12) Region, SiteID FROM dbo.Sites ORDER BY Region, SiteID) AS t
ORDER BY Region, SiteID;
-- RANGE gives every row of the same region the SAME total; ROWS counts up one by one

-- E.7  Running total of homes funded per region within FY 2024/25 (PARTITION BY region)
WITH M AS (
    SELECT s.Region, DATEFROMPARTS(YEAR(a.ApplicationDate), MONTH(a.ApplicationDate), 1) AS MonthStart,
           SUM(f.Homes) AS Homes
    FROM dbo.Applications a
    JOIN dbo.FundingLines f ON f.ApplicationID = a.ApplicationID
    JOIN dbo.Sites s ON s.SiteID = f.SiteID
    WHERE a.ApplicationDate >= '2024-04-01' AND a.ApplicationDate < '2025-04-01'
    GROUP BY s.Region, DATEFROMPARTS(YEAR(a.ApplicationDate), MONTH(a.ApplicationDate), 1)
)
SELECT TOP (14) Region, MonthStart, Homes,
       SUM(Homes) OVER (PARTITION BY Region ORDER BY MonthStart ROWS UNBOUNDED PRECEDING) AS RunningHomes
FROM M ORDER BY Region, MonthStart;

-- E.8  The old way (correlated subquery) gives the same answer but re-reads the table per row
SELECT TOP (6) m.MonthStart, m.NetFunding,
       (SELECT SUM(x.NetFunding) FROM #MonthlyNet x WHERE x.MonthStart <= m.MonthStart) AS CumulativeNet
FROM #MonthlyNet m ORDER BY m.MonthStart;

-- E.9  FY boundary check: the last day of FY 2023/24 and first day of FY 2024/25
SELECT CAST(a.ApplicationDate AS DATE) AS Dt,
       CASE WHEN MONTH(a.ApplicationDate) >= 4 THEN YEAR(a.ApplicationDate) ELSE YEAR(a.ApplicationDate) - 1 END AS FYStart,
       COUNT(*) AS Applications
FROM dbo.Applications a
WHERE a.ApplicationDate >= '2024-03-31' AND a.ApplicationDate < '2024-04-02'
GROUP BY CAST(a.ApplicationDate AS DATE),
         CASE WHEN MONTH(a.ApplicationDate) >= 4 THEN YEAR(a.ApplicationDate) ELSE YEAR(a.ApplicationDate) - 1 END
ORDER BY Dt;

-- E.10 Negative lines (reversals) pull the running total down - find months where net funding was negative
--      (expected: 0 rows - reversals are too small to push a whole month below zero)
WITH C AS (
    SELECT MonthStart, NetFunding,
           SUM(NetFunding) OVER (ORDER BY MonthStart ROWS UNBOUNDED PRECEDING) AS Cum
    FROM #MonthlyNet
)
SELECT MonthStart, NetFunding FROM C WHERE NetFunding < 0;

DROP TABLE IF EXISTS #MonthlyNet;

/* --- Common mistakes (E) -------------------------------------------------------
-- WRONG: SUM(x) OVER (ORDER BY MonthStart) without a frame: with duplicate MonthStart rows
--        (e.g. per region) every duplicate gets the same running total (RANGE). Write ROWS.
-- WRONG: BETWEEN '2024-04-01' AND '2025-03-31' for FY 2024/25 on a DATETIME2 column loses 31 March after midnight
-- WRONG: forgetting PARTITION BY the financial year so the "FY to date" never resets
-- WRONG: including the ~20 future-dated applications in 2026-27 FY totals
-- ERROR: ORDER BY is required for running totals; SUM(x) OVER (ROWS UNBOUNDED PRECEDING) fails without it
----------------------------------------------------------------------------- */

/* --- Predict the output (E) ---------------------------------------------------
   E.3: FYToDate resets at every April. E.4: last row is 100.0. E.6: Default_RANGE repeats the same
   number for all rows in a region; Explicit_ROWS goes 1,2,3,...
   E.10: any months returned are those where reversals exceeded new funding (could be empty).
----------------------------------------------------------------------------- */

-- Try it (E): produce a cumulative count of Completed applications by month for FY 2023/24 (use ApplicationDate).


/* ############################################################################
   CONCEPT F : LAG / LEAD  (MONTH-OVER-MONTH)
   ############################################################################
   LAG(col, n, default) OVER (ORDER BY ...)  looks n rows BEFORE the current row.
   LEAD(...)                                  looks n rows AFTER.
   Perfect for "this month versus last month". Beware: it compares neighbouring
   ROWS, not neighbouring MONTHS - if a month is missing from the data, LAG
   silently compares with an earlier month.
   ########################################################################## */

-- F.1  Stage completions per month (Status Completed, by CompletionDate)
DROP TABLE IF EXISTS #MonthlyCompletions;
SELECT DATEFROMPARTS(YEAR(CompletionDate), MONTH(CompletionDate), 1) AS MonthStart,
       COUNT(*) AS Completions
INTO #MonthlyCompletions
FROM dbo.Applications
WHERE Status = 'Completed' AND CompletionDate IS NOT NULL
GROUP BY DATEFROMPARTS(YEAR(CompletionDate), MONTH(CompletionDate), 1);
SELECT TOP (6) * FROM #MonthlyCompletions ORDER BY MonthStart;

-- F.2  Previous month beside this month
SELECT TOP (14) MonthStart, Completions,
       LAG(Completions) OVER (ORDER BY MonthStart) AS PrevMonth
FROM #MonthlyCompletions ORDER BY MonthStart;

-- F.3  Change and % change (NULLIF protects against division by zero)
SELECT TOP (14) MonthStart, Completions,
       Completions - LAG(Completions) OVER (ORDER BY MonthStart) AS Change,
       CAST(100.0 * (Completions - LAG(Completions) OVER (ORDER BY MonthStart))
            / NULLIF(LAG(Completions) OVER (ORDER BY MonthStart), 0) AS DECIMAL(6,1)) AS PctChange
FROM #MonthlyCompletions ORDER BY MonthStart;

-- F.4  LEAD: next month
SELECT TOP (8) MonthStart, Completions,
       LEAD(Completions) OVER (ORDER BY MonthStart) AS NextMonth
FROM #MonthlyCompletions ORDER BY MonthStart;

-- F.5  Default value instead of NULL for the first row
SELECT TOP (4) MonthStart, Completions,
       LAG(Completions, 1, 0) OVER (ORDER BY MonthStart) AS PrevOrZero
FROM #MonthlyCompletions ORDER BY MonthStart;

-- F.6  Same month last year (offset 12 rows - only valid if NO months are missing!)
SELECT TOP (16) MonthStart, Completions,
       LAG(Completions, 12) OVER (ORDER BY MonthStart) AS SameMonthLastYear
FROM #MonthlyCompletions ORDER BY MonthStart;

-- F.7  Are any months missing? Compare month gap with 1 (a gap breaks LAG(12))
--      (expected: 0 rows - Jan 2022 to Dec 2025 has no gaps)
SELECT MonthStart, PrevMonthStart, DATEDIFF(MONTH, PrevMonthStart, MonthStart) AS MonthsGap
FROM (SELECT MonthStart, LAG(MonthStart) OVER (ORDER BY MonthStart) AS PrevMonthStart FROM #MonthlyCompletions) AS g
WHERE DATEDIFF(MONTH, PrevMonthStart, MonthStart) > 1;

-- F.8  Fix gaps by joining to a full calendar of months (recursive CTE from Concept B)
WITH Cal AS (
    SELECT CAST('2022-01-01' AS DATE) AS MonthStart
    UNION ALL
    SELECT DATEADD(MONTH, 1, MonthStart) FROM Cal WHERE MonthStart < '2025-12-01'
)
SELECT TOP (14) c.MonthStart,
       ISNULL(m.Completions, 0) AS Completions,
       LAG(ISNULL(m.Completions, 0)) OVER (ORDER BY c.MonthStart) AS PrevMonth
FROM Cal c LEFT JOIN #MonthlyCompletions m ON m.MonthStart = c.MonthStart
ORDER BY c.MonthStart
OPTION (MAXRECURSION 100);

-- F.9  Biggest month-on-month drops (data-quality alarm)
WITH D AS (
    SELECT MonthStart, Completions,
           Completions - LAG(Completions) OVER (ORDER BY MonthStart) AS Change
    FROM #MonthlyCompletions
)
SELECT TOP (5) MonthStart, Completions, Change FROM D WHERE Change IS NOT NULL ORDER BY Change;

-- F.10 LAG with PARTITION BY: monthly applications per property region
WITH M AS (
    SELECT PropertyRegion, DATEFROMPARTS(YEAR(ApplicationDate), MONTH(ApplicationDate), 1) AS MonthStart, COUNT(*) AS Apps
    FROM dbo.Applications
    WHERE ApplicationDate >= '2024-04-01' AND ApplicationDate < '2025-04-01'
    GROUP BY PropertyRegion, DATEFROMPARTS(YEAR(ApplicationDate), MONTH(ApplicationDate), 1)
)
SELECT TOP (14) PropertyRegion, MonthStart, Apps,
       LAG(Apps) OVER (PARTITION BY PropertyRegion ORDER BY MonthStart) AS PrevMonth
FROM M ORDER BY PropertyRegion, MonthStart;

-- F.11 Days between an applicant's consecutive applications
SELECT TOP (12) ApplicantID, ApplicationID, ApplicationDate,
       DATEDIFF(DAY, LAG(ApplicationDate) OVER (PARTITION BY ApplicantID ORDER BY ApplicationDate, ApplicationID), ApplicationDate) AS DaysSincePrevious
FROM dbo.Applications
WHERE ApplicantID <= 30
ORDER BY ApplicantID, ApplicationDate, ApplicationID;

-- F.12 Completions affected by the "completed before applied" data error: how many months include them?
SELECT COUNT(*) AS BadRows, COUNT(DISTINCT DATEFROMPARTS(YEAR(CompletionDate), MONTH(CompletionDate), 1)) AS MonthsAffected
FROM dbo.Applications
WHERE CompletionDate < CAST(ApplicationDate AS DATE);

DROP TABLE IF EXISTS #MonthlyCompletions;

/* --- Common mistakes (F) -------------------------------------------------------
-- WRONG: LAG(x) with no ORDER BY in OVER                 (error)
-- WRONG: LAG(x, 12) as "same month last year" when months are missing
-- WRONG: dividing by LAG(x) without NULLIF -> divide-by-zero error
-- WRONG: forgetting PARTITION BY, so Region A's first month compares with Region B's last month
-- WRONG: ordering by a text month name ('April','August') instead of a real date
----------------------------------------------------------------------------- */

/* --- Predict the output (F) ---------------------------------------------------
   F.2: first row PrevMonth is NULL. F.5: first row shows 0. F.6: first 12 rows are NULL.
   F.7: probably no rows (continuous months), F.8 would then equal F.2 shape.
----------------------------------------------------------------------------- */

-- Try it (F): show monthly counts of NEW applications (by ApplicationDate, all statuses) for calendar 2025
-- with the previous month and the LEAD (next) month. What happens in Jan and Dec?


/* ############################################################################
   CONCEPT G : TOP N PER GROUP, AND DE-DUPLICATION
   ############################################################################
   Pattern: number rows inside each group with ROW_NUMBER() OVER (PARTITION BY
   group ORDER BY measure DESC), then keep rn <= N. Switch to RANK/DENSE_RANK
   if ties should all be included.
   De-duplication: partition by the columns that define "a duplicate", number
   the rows, keep rn = 1, delete rn > 1.
   ########################################################################## */

-- G.1  Top 3 sites per region by planned homes
WITH Ranked AS (
    SELECT Region, SiteName, PlannedHomes,
           ROW_NUMBER() OVER (PARTITION BY Region ORDER BY PlannedHomes DESC, SiteID) AS rn
    FROM dbo.Sites
)
SELECT Region, rn, SiteName, PlannedHomes FROM Ranked WHERE rn <= 3 ORDER BY Region, rn;

-- G.2  Same with RANK: ties at 3rd place are ALL kept (more than 3 rows possible)
WITH Ranked AS (
    SELECT Region, SiteName, PlannedHomes,
           RANK() OVER (PARTITION BY Region ORDER BY PlannedHomes DESC) AS rk
    FROM dbo.Sites
)
SELECT Region, rk, SiteName, PlannedHomes FROM Ranked WHERE rk <= 3 ORDER BY Region, rk, SiteName;

-- G.3  How many rows did RANK add compared with ROW_NUMBER?
WITH Ranked AS (
    SELECT RANK() OVER (PARTITION BY Region ORDER BY PlannedHomes DESC) AS rk FROM dbo.Sites
)
SELECT COUNT(*) AS RowsFromRank FROM Ranked WHERE rk <= 3;       -- compare with 3 * number of regions

-- G.4  Top 3 sites per region by NET FUNDING (aggregate first, rank second)
WITH SiteNet AS (
    SELECT s.SiteID, s.SiteName, s.Region,
           SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate)) AS NetFunding
    FROM dbo.Sites s JOIN dbo.FundingLines f ON f.SiteID = s.SiteID
    GROUP BY s.SiteID, s.SiteName, s.Region
),
Ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY Region ORDER BY NetFunding DESC, SiteID) AS rn FROM SiteNet
)
SELECT Region, rn, SiteName, NetFunding FROM Ranked WHERE rn <= 3 ORDER BY Region, rn;

-- G.5  The CROSS APPLY alternative (TOP inside, correlated to each region)
SELECT r.Region, t.SiteName, t.PlannedHomes
FROM (SELECT DISTINCT Region FROM dbo.Sites) AS r
CROSS APPLY (SELECT TOP (3) s.SiteName, s.PlannedHomes
             FROM dbo.Sites s WHERE s.Region = r.Region
             ORDER BY s.PlannedHomes DESC, s.SiteID) AS t
ORDER BY r.Region, t.PlannedHomes DESC;

-- G.6  Latest application per applicant (rn = 1 ordered DESC)
WITH L AS (
    SELECT ApplicantID, ApplicationID, ApplicationDate, Status,
           ROW_NUMBER() OVER (PARTITION BY ApplicantID ORDER BY ApplicationDate DESC, ApplicationID DESC) AS rn
    FROM dbo.Applications
)
SELECT TOP (10) ApplicantID, ApplicationID, ApplicationDate, Status FROM L WHERE rn = 1 ORDER BY ApplicantID;

-- G.7  First application per applicant (rn = 1 ordered ASC) and how many applicants that is
WITH F AS (
    SELECT ApplicantID, ROW_NUMBER() OVER (PARTITION BY ApplicantID ORDER BY ApplicationDate, ApplicationID) AS rn
    FROM dbo.Applications
)
SELECT COUNT(*) AS ApplicantsWithAtLeastOneApp FROM F WHERE rn = 1;

-- G.8  Highest-paid in each office - RANK keeps salary ties
WITH R AS (
    SELECT Office, FirstName, LastName, Salary, RANK() OVER (PARTITION BY Office ORDER BY Salary DESC) AS rk
    FROM dbo.Staff
)
SELECT Office, FirstName, LastName, Salary FROM R WHERE rk = 1 ORDER BY Office, LastName;

-- G.9  Find duplicate applicant names (normalise case and spaces first)
WITH Dup AS (
    SELECT ApplicantID, FirstName, LastName, City, RegisteredDate,
           COUNT(*) OVER (PARTITION BY UPPER(TRIM(FirstName)), UPPER(TRIM(LastName))) AS Copies,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(FirstName)), UPPER(TRIM(LastName)) ORDER BY RegisteredDate, ApplicantID) AS rn
    FROM dbo.Applicants
)
SELECT TOP (12) * FROM Dup WHERE Copies > 1 ORDER BY LastName, FirstName, rn;

-- G.10 How many "extra" copies would a de-dup remove?
WITH Dup AS (
    SELECT ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(FirstName)), UPPER(TRIM(LastName)) ORDER BY RegisteredDate, ApplicantID) AS rn
    FROM dbo.Applicants
)
SELECT SUM(CASE WHEN rn > 1 THEN 1 ELSE 0 END) AS ExtraCopies, COUNT(*) AS TotalApplicants FROM Dup;

-- G.11 De-duplicate on a TEMP COPY (never on the real table!). Keep the oldest registration.
DROP TABLE IF EXISTS #ApplicantsCopy;
SELECT * INTO #ApplicantsCopy FROM dbo.Applicants;
SELECT COUNT(*) AS RowsBefore FROM #ApplicantsCopy;

WITH Dup AS (
    SELECT ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(FirstName)), UPPER(TRIM(LastName)) ORDER BY RegisteredDate, ApplicantID) AS rn
    FROM #ApplicantsCopy
)
DELETE FROM Dup WHERE rn > 1;

SELECT COUNT(*) AS RowsAfter FROM #ApplicantsCopy;

GO
-- G.12 Smarter keep-rule: prefer the record that HAS an email, then the newest registration
DROP TABLE IF EXISTS #ApplicantsCopy;
SELECT * INTO #ApplicantsCopy FROM dbo.Applicants;
WITH Dup AS (
    SELECT ApplicantID,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(FirstName)), UPPER(TRIM(LastName))
                              ORDER BY CASE WHEN NULLIF(TRIM(Email), '') IS NULL THEN 1 ELSE 0 END,
                                       RegisteredDate DESC, ApplicantID) AS rn
    FROM #ApplicantsCopy
)
SELECT COUNT(*) AS WouldDelete FROM Dup WHERE rn > 1;
DROP TABLE #ApplicantsCopy;

-- G.13 Why "same name" is not "same person": same name in different cities
SELECT TOP (8) UPPER(TRIM(FirstName)) AS FirstName, UPPER(TRIM(LastName)) AS LastName,
       COUNT(*) AS Copies, COUNT(DISTINCT City) AS Cities
FROM dbo.Applicants
GROUP BY UPPER(TRIM(FirstName)), UPPER(TRIM(LastName))
HAVING COUNT(*) > 1
ORDER BY Cities DESC, Copies DESC, LastName;

-- G.14 Bottom 2 sites per region among grant-funded sites (ASC order, UnitPrice > 0)
WITH Ranked AS (
    SELECT Region, SiteName, UnitPrice,
           ROW_NUMBER() OVER (PARTITION BY Region ORDER BY UnitPrice, SiteID) AS rn
    FROM dbo.Sites WHERE UnitPrice > 0
)
SELECT Region, SiteName, UnitPrice FROM Ranked WHERE rn <= 2 ORDER BY Region, rn;

/* --- Common mistakes (G) -------------------------------------------------------
-- WRONG: ROW_NUMBER without PARTITION BY gives the top N overall, not per group
-- WRONG: ORDER BY inside OVER without a unique tie-breaker -> results change between runs
-- WRONG: de-duplicating by name only and deleting real different people
-- WRONG: deleting duplicates from the live table without checking foreign keys (Applications reference Applicants)
-- ERROR: DELETE FROM a CTE that is based on a join of several tables (ambiguous target)
----------------------------------------------------------------------------- */

/* --- Predict the output (G) ---------------------------------------------------
   G.1: exactly 3 rows per region (fewer if a region has < 3 sites). G.2: >= G.1 rows.
   G.10: ExtraCopies is roughly 5% of 10,000. G.11: RowsAfter = RowsBefore - ExtraCopies.
----------------------------------------------------------------------------- */

-- Try it (G): list the single most recent application for each PropertyRegion (ties broken by highest ApplicationID),
-- ignoring future-dated applications.


/* ############################################################################
   CONCEPT H : SCALAR FUNCTIONS  (dbo.fn_FinancialYear)
   ############################################################################
   A user-defined scalar function takes values in and returns ONE value, so you
   can reuse a rule everywhere (e.g. "which financial year is this date in?").
   CREATE OR ALTER FUNCTION must be the only statement in its batch (use GO).
   Call it with its schema name: dbo.fn_FinancialYear(date).
   Keep functions simple: a scalar function on a column in WHERE stops index use.
   ########################################################################## */

GO
-- H.1  Create the financial-year function
CREATE OR ALTER FUNCTION dbo.fn_FinancialYear (@d DATE)
RETURNS CHAR(7)
AS
BEGIN
    DECLARE @start INT = CASE WHEN MONTH(@d) >= 4 THEN YEAR(@d) ELSE YEAR(@d) - 1 END;
    RETURN CASE WHEN @d IS NULL THEN NULL
                ELSE CAST(@start AS CHAR(4)) + '/' + RIGHT(CAST(@start + 1 AS VARCHAR(4)), 2) END;
END;
GO

-- H.2  Net funding for one funding line, as a function
CREATE OR ALTER FUNCTION dbo.fn_NetFunding (@Homes INT, @GrantPerHome DECIMAL(10,2), @ClawbackRate DECIMAL(4,2))
RETURNS DECIMAL(18,2)
AS
BEGIN
    RETURN @Homes * @GrantPerHome * (1 - @ClawbackRate);
END;
GO

-- H.3  Test the edge cases: the FY boundary, the leap day, a New Year, and NULL
SELECT d.Label, d.Dt, dbo.fn_FinancialYear(d.Dt) AS FinYear
FROM (VALUES ('Last day of FY',  CAST('2025-03-31' AS DATE)),
             ('First day of FY', CAST('2025-04-01' AS DATE)),
             ('Leap day',        CAST('2024-02-29' AS DATE)),
             ('New Year Eve',    CAST('2024-12-31' AS DATE)),
             ('New Year Day',    CAST('2025-01-01' AS DATE)),
             ('NULL date',       CAST(NULL AS DATE))) AS d (Label, Dt);

-- H.4  23:59:59 timestamps convert to DATE correctly (time is dropped)
SELECT dbo.fn_FinancialYear(CAST('2025-03-31 23:59:59' AS DATETIME2(0))) AS LastSecondOfFY,
       dbo.fn_FinancialYear(CAST('2025-04-01 00:00:00' AS DATETIME2(0))) AS FirstSecondOfNext;

-- H.5  Use it in SELECT and GROUP BY: applications per financial year
SELECT dbo.fn_FinancialYear(ApplicationDate) AS FinYear, COUNT(*) AS Applications
FROM dbo.Applications
WHERE ApplicationDate < '2026-01-01'
GROUP BY dbo.fn_FinancialYear(ApplicationDate)
ORDER BY FinYear;

-- H.6  Net funding per FY using both functions
SELECT dbo.fn_FinancialYear(a.ApplicationDate) AS FinYear,
       SUM(dbo.fn_NetFunding(f.Homes, f.GrantPerHome, f.ClawbackRate)) AS NetFunding
FROM dbo.Applications a JOIN dbo.FundingLines f ON f.ApplicationID = a.ApplicationID
WHERE a.ApplicationDate < '2026-01-01'
GROUP BY dbo.fn_FinancialYear(a.ApplicationDate)
ORDER BY FinYear;

-- H.7  Use it in WHERE (works, but it is NOT index-friendly on big tables)
SELECT COUNT(*) AS FY2425_Applications
FROM dbo.Applications
WHERE dbo.fn_FinancialYear(ApplicationDate) = '2024/25';
-- index-friendly equivalent:
SELECT COUNT(*) AS FY2425_Applications_Range
FROM dbo.Applications
WHERE ApplicationDate >= '2024-04-01' AND ApplicationDate < '2025-04-01';

-- H.8  Cross-check: FY label from the function vs the label built from the date range
SELECT COUNT(*) AS Mismatches
FROM dbo.Applications
WHERE CASE WHEN dbo.fn_FinancialYear(ApplicationDate) = '2024/25' THEN 1 ELSE 0 END
   <> CASE WHEN ApplicationDate >= '2024-04-01' AND ApplicationDate < '2025-04-01' THEN 1 ELSE 0 END;

-- H.9  Look up function metadata
SELECT name, type_desc, create_date FROM sys.objects WHERE name IN ('fn_FinancialYear', 'fn_NetFunding');

/* --- Common mistakes (H) -------------------------------------------------------
-- ERROR: calling without the schema:  SELECT fn_FinancialYear('2025-04-01');   (must be dbo.fn_FinancialYear)
-- ERROR: CREATE FUNCTION not first in its batch (forgot GO before it)
-- ERROR: functions cannot INSERT/UPDATE/DELETE real tables or use TRY...CATCH
-- WRONG: passing a string like '01/04/2025' (ambiguous dd/mm vs mm/dd): use 'YYYY-MM-DD'
-- SLOW : a scalar function on a column in WHERE/JOIN over millions of rows
-- WRONG: hard-coding a calendar-year rule: YEAR(d) is NOT the financial year
----------------------------------------------------------------------------- */

/* --- Predict the output (H) ---------------------------------------------------
   H.3: 2024/25, 2025/26, 2023/24, 2024/25, 2024/25, NULL.
   H.4: 2024/25 then 2025/26. H.8: 0 mismatches.
----------------------------------------------------------------------------- */

-- Try it (H): write dbo.fn_FinancialYearStart (@d DATE) RETURNS DATE returning the 1 April that starts the FY
-- containing @d, and test it on 2025-03-31 and 2025-04-01.


/* ############################################################################
   CONCEPT I : STORED PROCEDURES WITH PARAMETERS
   ############################################################################
   A stored procedure is a saved batch of T-SQL you run with EXEC. It can take
   parameters (@Region), have defaults, return result sets, return values via
   OUTPUT parameters, and change data. Benefits: reuse, one place to fix logic,
   permissions (users run the proc, not the tables), cached plans.
   Always start with SET NOCOUNT ON to stop "(n rows affected)" noise.
   ########################################################################## */

GO
-- I.1  Region summary: one region, or all regions when @Region is NULL
CREATE OR ALTER PROCEDURE dbo.usp_RegionSummary
    @Region NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Region IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Sites WHERE Region = @Region)
    BEGIN
        THROW 50001, 'Unknown region - check the spelling (e.g. North West).', 1;
    END;

    WITH SiteNet AS (
        SELECT SiteID,
               SUM(Homes) AS HomesFunded,
               SUM(Homes * GrantPerHome * (1 - ClawbackRate)) AS NetFunding
        FROM dbo.FundingLines
        GROUP BY SiteID
    )
    SELECT s.Region,
           COUNT(*)                                        AS Sites,
           SUM(s.PlannedHomes)                             AS PlannedHomes,
           SUM(CASE WHEN s.IsStalled = 1 THEN 1 ELSE 0 END) AS StalledSites,
           ISNULL(SUM(n.HomesFunded), 0)                   AS HomesFunded,
           ISNULL(SUM(n.NetFunding), 0)                    AS NetFunding
    FROM dbo.Sites AS s
    LEFT JOIN SiteNet AS n ON n.SiteID = s.SiteID
    WHERE (@Region IS NULL OR s.Region = @Region)
    GROUP BY s.Region
    ORDER BY s.Region;
END;
GO

-- I.2  Top N sites in a region by net funding, within an optional date window (half-open range)
CREATE OR ALTER PROCEDURE dbo.usp_TopSitesByRegion
    @Region   NVARCHAR(50),
    @TopN     INT  = 3,
    @FromDate DATE = NULL,
    @ToDate   DATE = NULL           -- exclusive upper bound
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@TopN) s.SiteID, s.SiteName, s.LocalAuthority,
           SUM(f.Homes) AS Homes,
           SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate)) AS NetFunding
    FROM dbo.Sites AS s
    JOIN dbo.FundingLines AS f ON f.SiteID = s.SiteID
    JOIN dbo.Applications AS a ON a.ApplicationID = f.ApplicationID
    WHERE s.Region = @Region
      AND (@FromDate IS NULL OR a.ApplicationDate >= @FromDate)
      AND (@ToDate   IS NULL OR a.ApplicationDate <  @ToDate)
    GROUP BY s.SiteID, s.SiteName, s.LocalAuthority
    ORDER BY NetFunding DESC, s.SiteID;
END;
GO

-- I.3  Financial-year summary: parameter is '2024/25'; dates are derived (index-friendly range)
CREATE OR ALTER PROCEDURE dbo.usp_FinYearSummary
    @FinYear CHAR(7)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StartYear INT = TRY_CAST(LEFT(@FinYear, 4) AS INT);
    IF @StartYear IS NULL OR @FinYear NOT LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]'
    BEGIN
        THROW 50002, 'Financial year must look like 2024/25.', 1;
    END;
    DECLARE @From DATE = DATEFROMPARTS(@StartYear, 4, 1);
    DECLARE @To   DATE = DATEFROMPARTS(@StartYear + 1, 4, 1);

    SELECT a.Status,
           COUNT(DISTINCT a.ApplicationID) AS Applications,
           ISNULL(SUM(f.Homes), 0) AS Homes,
           ISNULL(SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate)), 0) AS NetFunding
    FROM dbo.Applications AS a
    LEFT JOIN dbo.FundingLines AS f ON f.ApplicationID = a.ApplicationID
    WHERE a.ApplicationDate >= @From AND a.ApplicationDate < @To
    GROUP BY a.Status
    ORDER BY a.Status;
END;
GO

-- I.4  OUTPUT parameter + RETURN code
CREATE OR ALTER PROCEDURE dbo.usp_ApplicationCount
    @Status NVARCHAR(20),
    @Count  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @Count = COUNT(*) FROM dbo.Applications WHERE Status = @Status;
    IF @Count = 0 RETURN 1;      -- 1 = nothing found
    RETURN 0;
END;
GO

-- I.5  A procedure that changes data, with validation and a transaction
CREATE OR ALTER PROCEDURE dbo.usp_SetSiteStalled
    @SiteID    INT,
    @IsStalled BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Sites WHERE SiteID = @SiteID)
        THROW 50003, 'No such site.', 1;
    BEGIN TRAN;
        UPDATE dbo.Sites SET IsStalled = @IsStalled WHERE SiteID = @SiteID;
    COMMIT TRAN;
    SELECT SiteID, SiteName, IsStalled FROM dbo.Sites WHERE SiteID = @SiteID;
END;
GO

-- I.6  Run it: by name with a parameter
EXEC dbo.usp_RegionSummary @Region = N'North West';

-- I.7  All regions (default parameter), and positional call
EXEC dbo.usp_RegionSummary;
EXEC dbo.usp_RegionSummary N'London';

-- I.8  Top 3 by default; override the TopN and date window (FY 2024/25)
EXEC dbo.usp_TopSitesByRegion @Region = N'London';
EXEC dbo.usp_TopSitesByRegion @Region = N'London', @TopN = 5, @FromDate = '2024-04-01', @ToDate = '2025-04-01';

-- I.9  Financial year summaries, including the boundary years
EXEC dbo.usp_FinYearSummary @FinYear = '2023/24';
EXEC dbo.usp_FinYearSummary '2024/25';

-- I.10 OUTPUT parameter and return code
DECLARE @n INT, @rc INT;
EXEC @rc = dbo.usp_ApplicationCount @Status = N'Completed', @Count = @n OUTPUT;
SELECT @n AS CompletedApplications, @rc AS ReturnCode;
EXEC @rc = dbo.usp_ApplicationCount @Status = N'Nonexistent', @Count = @n OUTPUT;
SELECT @n AS Count2, @rc AS ReturnCode2;

-- I.11 Catch the error from a bad parameter
BEGIN TRY
    EXEC dbo.usp_RegionSummary @Region = N'Narnia';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;     -- 50001
END CATCH;
BEGIN TRY
    EXEC dbo.usp_FinYearSummary @FinYear = '2024-25';              -- wrong format
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;     -- 50002
END CATCH;

-- I.12 Capture a procedure's result set into a temp table: INSERT ... EXEC
DROP TABLE IF EXISTS #RegionSummary;
CREATE TABLE #RegionSummary (Region NVARCHAR(50), Sites INT, PlannedHomes INT, StalledSites INT, HomesFunded INT, NetFunding DECIMAL(18,2));
INSERT INTO #RegionSummary EXEC dbo.usp_RegionSummary;
SELECT TOP (3) * FROM #RegionSummary ORDER BY NetFunding DESC;
DROP TABLE #RegionSummary;

-- I.13 The data-changing proc, safely inside a transaction we roll back
BEGIN TRAN;
    EXEC dbo.usp_SetSiteStalled @SiteID = 1, @IsStalled = 1;
ROLLBACK TRAN;
SELECT SiteID, IsStalled AS IsStalled_AfterRollback FROM dbo.Sites WHERE SiteID = 1;

-- I.14 See the source, then (optionally) drop
EXEC sp_helptext 'dbo.usp_RegionSummary';
-- DROP PROCEDURE IF EXISTS dbo.usp_RegionSummary;

/* --- Common mistakes (I) -------------------------------------------------------
-- ERROR: CREATE PROCEDURE not the first statement in its batch (missing GO)
-- ERROR: EXEC dbo.usp_RegionSummary North West;           (string literals need quotes)
-- ERROR: EXEC dbo.usp_ApplicationCount @Status = N'Completed';   (OUTPUT parameter @Count not supplied)
-- WRONG: leaving a data-changing proc call outside a transaction while teaching - it COMMITS (auto-commit)
-- WRONG: SELECT * inside procs - new columns silently change the output shape
-- WRONG: building SQL by concatenating @Region into a string (SQL injection) - use parameters / sp_executesql
-- GOTCHA: a wrong-case region ('north west') matches fine on a case-insensitive collation, but
--         'North-West' (hyphen) is a different value and returns the "Unknown region" error
----------------------------------------------------------------------------- */

/* --- Predict the output (I) ---------------------------------------------------
   I.6: one row for North West. I.7: one row per region. I.10: CompletedApplications > 0 with code 0, then 0 with code 1.
   I.11: errors 50001 and 50002.  I.13: IsStalled back to its original value.
----------------------------------------------------------------------------- */

-- Try it (I): write dbo.usp_ApplicantsByHousehold @HouseholdType NVARCHAR(20), @TopN INT = 10 returning the
-- applicants of that household type with the most applications. Call it for 'Key worker'.


/* ============================================================================
   TIDY UP (temp objects are already gone). The functions and procedures are
   kept for later modules and the practice file. To remove them, run:
     DROP PROCEDURE IF EXISTS dbo.usp_RegionSummary, dbo.usp_TopSitesByRegion,
                              dbo.usp_FinYearSummary, dbo.usp_ApplicationCount, dbo.usp_SetSiteStalled;
     DROP FUNCTION  IF EXISTS dbo.fn_FinancialYear, dbo.fn_NetFunding;
   END OF MODULE 09. Next: practice/module09_practice.sql
   ============================================================================ */
