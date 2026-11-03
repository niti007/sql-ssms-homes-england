USE HousingDelivery;
GO
/* ============================================================================
   PRACTICE - MODULE 09  (CTEs, window functions, procedures, functions)
   10 business questions, easy -> hard. Try each one BEFORE opening its solution.
   To check yourself: copy the SOLUTION text out of the comment (or remove the
   comment marks), run it, and compare with your own result.
   Net funding = Homes * GrantPerHome * (1 - ClawbackRate)
   UK financial year (FY) = 1 April to 31 March. FY 2024/25 = 1 Apr 2024 .. 31 Mar 2025.

   Q3 uses dbo.fn_FinancialYear from module09_advanced.sql - run Concept H there first.
   Several questions hit planted data traps - read the "TRAP" line after trying.
   ============================================================================ */


/* ----------------------------------------------------------------------------
   Q1 (easy) - Top three salary levels
   HR wants everyone who is on one of the three highest DISTINCT salaries (so people who tie are all included).
   Show StaffID, name, JobTitle, Salary and the salary level (1 = highest).
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q1
WITH Ranked AS (
    SELECT StaffID, FirstName, LastName, JobTitle, Salary,
           DENSE_RANK() OVER (ORDER BY Salary DESC) AS SalaryLevel
    FROM dbo.Staff
)
SELECT StaffID, FirstName, LastName, JobTitle, Salary, SalaryLevel
FROM Ranked
WHERE SalaryLevel <= 3
ORDER BY SalaryLevel, StaffID;
-- TRAP: salaries tie. TOP (3) or ROW_NUMBER <= 3 returns exactly 3 people and arbitrarily drops tied colleagues;
--       RANK <= 3 skips levels after a tie (1,1,3) so you may get fewer levels than you wanted.
*/


/* ----------------------------------------------------------------------------
   Q2 (easy) - Funding by tenure
   Using a CTE, show for EVERY tenure type (including those with no sites) the number of sites and total net funding.
   Sites that have no tenure at all should appear on a line labelled '(No tenure)'. Order by net funding, highest first.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q2
WITH SiteNet AS (
    SELECT SiteID, SUM(Homes * GrantPerHome * (1 - ClawbackRate)) AS NetFunding
    FROM dbo.FundingLines
    GROUP BY SiteID
),
Labelled AS (
    SELECT s.SiteID, ISNULL(t.TenureName, N'(No tenure)') AS TenureName, n.NetFunding
    FROM dbo.Sites AS s
    LEFT JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID
    LEFT JOIN SiteNet AS n ON n.SiteID = s.SiteID
)
SELECT TenureName, COUNT(*) AS Sites, ISNULL(SUM(NetFunding), 0) AS NetFunding
FROM Labelled
GROUP BY TenureName
UNION ALL
SELECT t.TenureName, 0, 0
FROM dbo.TenureTypes AS t
WHERE NOT EXISTS (SELECT 1 FROM dbo.Sites s WHERE s.TenureTypeID = t.TenureTypeID)
ORDER BY NetFunding DESC;
-- TRAP: an INNER JOIN from Sites to TenureTypes loses the sites with NULL TenureTypeID, and starting FROM TenureTypes
--       loses them too. The tenure with no sites (Self/Custom Build) needs its own row (NOT EXISTS branch).
*/


/* ----------------------------------------------------------------------------
   Q3 (easy-medium) - Applications by financial year, and the boundary
   Using dbo.fn_FinancialYear, show the number of applications in each financial year. Then show how many applications
   fall on exactly 31 March 2025 and on 1 April 2025 and which FY each belongs to.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q3
SELECT dbo.fn_FinancialYear(ApplicationDate) AS FinYear, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY dbo.fn_FinancialYear(ApplicationDate)
ORDER BY FinYear;

SELECT CAST(ApplicationDate AS DATE) AS Dt,
       dbo.fn_FinancialYear(ApplicationDate) AS FinYear,
       COUNT(*) AS Applications
FROM dbo.Applications
WHERE ApplicationDate >= '2025-03-31' AND ApplicationDate < '2025-04-02'
GROUP BY CAST(ApplicationDate AS DATE), dbo.fn_FinancialYear(ApplicationDate)
ORDER BY Dt;
-- TRAP: the list will contain FY 2026/27 (and 2025/26 partly) because ~20 applications are future-dated - flag or
--       exclude them. Filtering the boundary with BETWEEN '2025-03-31' AND '2025-04-01' would include all of
--       1 April; with  < '2025-04-02'  you get the two whole days, including 23:59:59 on 31 March.
*/


/* ----------------------------------------------------------------------------
   Q4 (medium) - Regional shortlist
   For each region list the three sites with the most planned homes. Produce two versions: exactly 3 rows per region
   (ROW_NUMBER, tie-break on SiteID) and a version that keeps ALL sites tied for a top-3 place (RANK). Which regions
   return more than three rows in the second version?
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q4
WITH R AS (
    SELECT Region, SiteID, SiteName, PlannedHomes,
           ROW_NUMBER() OVER (PARTITION BY Region ORDER BY PlannedHomes DESC, SiteID) AS rn,
           RANK()       OVER (PARTITION BY Region ORDER BY PlannedHomes DESC)         AS rk
    FROM dbo.Sites
)
SELECT Region, rn, SiteName, PlannedHomes FROM R WHERE rn <= 3 ORDER BY Region, rn;

WITH R AS (
    SELECT Region, SiteName, PlannedHomes,
           RANK() OVER (PARTITION BY Region ORDER BY PlannedHomes DESC) AS rk
    FROM dbo.Sites
)
SELECT Region, rk, SiteName, PlannedHomes FROM R WHERE rk <= 3 ORDER BY Region, rk, SiteName;

WITH R AS (
    SELECT Region, RANK() OVER (PARTITION BY Region ORDER BY PlannedHomes DESC) AS rk FROM dbo.Sites
)
SELECT Region, COUNT(*) AS RowsReturned FROM R WHERE rk <= 3 GROUP BY Region HAVING COUNT(*) > 3;
-- TRAP: PlannedHomes ties are common. ROW_NUMBER picks one of the tied sites by your tie-breaker (fair but
--       arbitrary); RANK returns every tied site, so some regions show 4 or 5 rows.
*/


/* ----------------------------------------------------------------------------
   Q5 (medium) - Financial-year-to-date funding
   For FY 2024/25 show, month by month, the net funding, the running total since 1 April 2024, and the running total as a
   percentage of the full-year net funding.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q5
WITH Monthly AS (
    SELECT DATEFROMPARTS(YEAR(a.ApplicationDate), MONTH(a.ApplicationDate), 1) AS MonthStart,
           SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate)) AS NetFunding
    FROM dbo.Applications AS a
    JOIN dbo.FundingLines AS f ON f.ApplicationID = a.ApplicationID
    WHERE a.ApplicationDate >= '2024-04-01' AND a.ApplicationDate < '2025-04-01'
    GROUP BY DATEFROMPARTS(YEAR(a.ApplicationDate), MONTH(a.ApplicationDate), 1)
)
SELECT MonthStart, NetFunding,
       SUM(NetFunding) OVER (ORDER BY MonthStart ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS FYToDate,
       CAST(100.0 * SUM(NetFunding) OVER (ORDER BY MonthStart ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            / NULLIF(SUM(NetFunding) OVER (), 0) AS DECIMAL(5,1)) AS CumPctOfYear
FROM Monthly
ORDER BY MonthStart;
-- TRAP: FY 2024/25 runs April 2024 to MARCH 2025 - grouping by calendar year splits it in two. Use a half-open date
--       range (< 2025-04-01) so 31 March 23:59:59 rows are in. Negative (reversal) lines can make a month's net negative.
*/


/* ----------------------------------------------------------------------------
   Q6 (medium) - Month-over-month completions
   For Completed applications, count completions per month of CompletionDate and show the previous month's count, the change
   and the % change. Exclude records where CompletionDate is earlier than ApplicationDate (data errors). Cover every month
   from December 2021 to December 2025, showing 0 for months with no completions.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q6
WITH Cal AS (
    SELECT CAST('2021-12-01' AS DATE) AS MonthStart
    UNION ALL
    SELECT DATEADD(MONTH, 1, MonthStart) FROM Cal WHERE MonthStart < '2025-12-01'
),
Done AS (
    SELECT DATEFROMPARTS(YEAR(CompletionDate), MONTH(CompletionDate), 1) AS MonthStart, COUNT(*) AS Completions
    FROM dbo.Applications
    WHERE Status = 'Completed'
      AND CompletionDate IS NOT NULL
      AND CompletionDate >= CAST(ApplicationDate AS DATE)
    GROUP BY DATEFROMPARTS(YEAR(CompletionDate), MONTH(CompletionDate), 1)
),
Joined AS (
    SELECT c.MonthStart, ISNULL(d.Completions, 0) AS Completions
    FROM Cal AS c LEFT JOIN Done AS d ON d.MonthStart = c.MonthStart
)
SELECT MonthStart, Completions,
       LAG(Completions) OVER (ORDER BY MonthStart) AS PreviousMonth,
       Completions - LAG(Completions) OVER (ORDER BY MonthStart) AS Change,
       CAST(100.0 * (Completions - LAG(Completions) OVER (ORDER BY MonthStart))
            / NULLIF(LAG(Completions) OVER (ORDER BY MonthStart), 0) AS DECIMAL(7,1)) AS PctChange
FROM Joined
ORDER BY MonthStart
OPTION (MAXRECURSION 100);
-- TRAP: ~30 applications have CompletionDate < ApplicationDate (28 of them complete in Dec 2021 - Jan 2022); including
--       them makes Jan 2022 show 64 completions instead of 40 and gives Dec 2021 a count of 4 instead of 0. Dec 2021 has
--       zero valid completions, so it is simply MISSING from the GROUP BY output unless you build the calendar first
--       (then LAG would compare Jan 2022 with nothing). Divide with NULLIF because the previous month is 0.
*/


/* ----------------------------------------------------------------------------
   Q7 (medium-hard) - Duplicate applicant clean-up (preview only)
   The registration team wants to merge duplicate applicant records. On a TEMP COPY of Applicants, treat records with the
   same first and last name (ignoring case and stray spaces) as duplicates. Keep the earliest registration (tie-break on
   ApplicantID). Report: how many records would be removed, and show 10 example groups with the kept ApplicantID next to
   the ones to remove. Do NOT touch dbo.Applicants.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q7
DROP TABLE IF EXISTS #ApplicantsCopy;
SELECT * INTO #ApplicantsCopy FROM dbo.Applicants;

WITH Dup AS (
    SELECT ApplicantID, UPPER(TRIM(FirstName)) AS Fn, UPPER(TRIM(LastName)) AS Ln, City, RegisteredDate,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(FirstName)), UPPER(TRIM(LastName))
                              ORDER BY RegisteredDate, ApplicantID) AS rn
    FROM #ApplicantsCopy
)
SELECT SUM(CASE WHEN rn > 1 THEN 1 ELSE 0 END) AS RecordsToRemove, COUNT(*) AS TotalRecords FROM Dup;

WITH Dup AS (
    SELECT ApplicantID, UPPER(TRIM(FirstName)) AS Fn, UPPER(TRIM(LastName)) AS Ln, City, RegisteredDate,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(FirstName)), UPPER(TRIM(LastName))
                              ORDER BY RegisteredDate, ApplicantID) AS rn
    FROM #ApplicantsCopy
)
SELECT TOP (10) k.Fn, k.Ln, k.ApplicantID AS KeepID, k.City AS KeepCity, d.ApplicantID AS RemoveID, d.City AS RemoveCity
FROM Dup AS k
JOIN Dup AS d ON d.Fn = k.Fn AND d.Ln = k.Ln AND d.rn > 1
WHERE k.rn = 1
ORDER BY k.Ln, k.Fn, d.ApplicantID;

DROP TABLE #ApplicantsCopy;
-- TRAP: UPPER(TRIM()) is the safe habit so 'smith ' and 'Smith' compare equal (here the same 250 are found without it,
--       because the default collation ignores case and trailing spaces). Equal names are only
--       CANDIDATE duplicates (see the City columns). And the real table has Applications pointing at every ApplicantID -
--       deleting the "extra" ones would break foreign keys; you would re-point applications first.
*/


/* ----------------------------------------------------------------------------
   Q8 (hard) - Who sits under whom?
   For every person with direct or indirect reports, count how many people are below them anywhere in the Staff
   hierarchy and the total salary cost of that branch (their reports, excluding themselves). Show managers with at
   least 5 people below them, largest branch first. Use a recursive CTE.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q8
WITH Below AS (
    SELECT StaffID AS RootID, StaffID AS MemberID, Salary AS MemberSalary, 0 AS Depth
    FROM dbo.Staff
    UNION ALL
    SELECT b.RootID, s.StaffID, s.Salary, b.Depth + 1
    FROM Below AS b
    JOIN dbo.Staff AS s ON s.ManagerID = b.MemberID
)
SELECT st.StaffID, st.FirstName, st.LastName, st.JobTitle,
       SUM(CASE WHEN b.Depth > 0 THEN 1 ELSE 0 END) AS PeopleBelow,
       SUM(CASE WHEN b.Depth > 0 THEN b.MemberSalary ELSE 0 END) AS BranchSalaryCost
FROM Below AS b
JOIN dbo.Staff AS st ON st.StaffID = b.RootID
GROUP BY st.StaffID, st.FirstName, st.LastName, st.JobTitle
HAVING SUM(CASE WHEN b.Depth > 0 THEN 1 ELSE 0 END) >= 5
ORDER BY PeopleBelow DESC, st.StaffID
OPTION (MAXRECURSION 50);
-- TRAP: the anchor row is the manager themself (Depth 0): counting it (COUNT(*)) is off by one, and their own
--       salary is not part of the branch below them, hence the Depth > 0 tests. The Chief Executive has ManagerID NULL,
--       so is never anyone's report, only a root. Anchor and recursive columns must have identical types.
*/


/* ----------------------------------------------------------------------------
   Q9 (hard) - A reusable partner report (stored procedure)
   Create dbo.usp_PartnerTypeSummary with optional parameters @PartnerType NVARCHAR(30) = NULL, @FromDate DATE = NULL and
   @ToDate DATE = NULL (exclusive upper bound). It returns, per partner type, the number of distinct sites funded, homes funded
   and net funding for applications inside the window. NULL means "no restriction". An unknown partner type must
   raise a clear error. Call it for all types, for 'Developer' in FY 2024/25, and with a bad type inside TRY...CATCH.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q9
-- (run the CREATE on its own - it must be alone in its batch, i.e. put GO before and after it)
CREATE OR ALTER PROCEDURE dbo.usp_PartnerTypeSummary
    @PartnerType NVARCHAR(30) = NULL,
    @FromDate    DATE = NULL,
    @ToDate      DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @PartnerType IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Partners WHERE PartnerType = @PartnerType)
        THROW 50010, 'Unknown partner type. Use Developer, Registered Provider, Local Authority or SME Builder.', 1;

    SELECT p.PartnerType,
           COUNT(DISTINCT s.SiteID) AS SitesFunded,
           SUM(f.Homes)             AS HomesFunded,
           SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate)) AS NetFunding
    FROM dbo.Partners     AS p
    JOIN dbo.Sites        AS s ON s.PartnerID = p.PartnerID
    JOIN dbo.FundingLines AS f ON f.SiteID = s.SiteID
    JOIN dbo.Applications AS a ON a.ApplicationID = f.ApplicationID
    WHERE (@PartnerType IS NULL OR p.PartnerType = @PartnerType)
      AND (@FromDate IS NULL OR a.ApplicationDate >= @FromDate)
      AND (@ToDate   IS NULL OR a.ApplicationDate <  @ToDate)
    GROUP BY p.PartnerType
    ORDER BY p.PartnerType;
END;
-- (GO here, then:)
EXEC dbo.usp_PartnerTypeSummary;
EXEC dbo.usp_PartnerTypeSummary @PartnerType = N'Developer', @FromDate = '2024-04-01', @ToDate = '2025-04-01';
BEGIN TRY
    EXEC dbo.usp_PartnerTypeSummary @PartnerType = N'Housing Association';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;
-- TRAP: with  ToDate = '2025-03-31'  and  <  you would lose the whole of 31 March - that is why the upper bound is
--       exclusive (pass 2025-04-01 for FY 2024/25). COUNT(*) instead of COUNT(DISTINCT SiteID) would count funding
--       lines, not sites (one site has many lines). Unfunded sites do not appear at all (inner joins) - decide if that is wanted.
*/


/* ----------------------------------------------------------------------------
   Q10 (hardest) - When does each region reach half its annual funding?
   For FY 2024/25, by site Region and month, work out net funding, the running total, and the region's full-year total.
   Then report, for each region, the FIRST month in which the running total exceeds 50% of that region's full-year total,
   with the percentage reached. Regions are Sites.Region, funding comes via FundingLines.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q10
WITH Monthly AS (
    SELECT s.Region,
           DATEFROMPARTS(YEAR(a.ApplicationDate), MONTH(a.ApplicationDate), 1) AS MonthStart,
           SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate)) AS NetFunding
    FROM dbo.Applications AS a
    JOIN dbo.FundingLines AS f ON f.ApplicationID = a.ApplicationID
    JOIN dbo.Sites        AS s ON s.SiteID = f.SiteID
    WHERE a.ApplicationDate >= '2024-04-01' AND a.ApplicationDate < '2025-04-01'
    GROUP BY s.Region, DATEFROMPARTS(YEAR(a.ApplicationDate), MONTH(a.ApplicationDate), 1)
),
Running AS (
    SELECT Region, MonthStart, NetFunding,
           SUM(NetFunding) OVER (PARTITION BY Region ORDER BY MonthStart ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningNet,
           SUM(NetFunding) OVER (PARTITION BY Region) AS YearNet
    FROM Monthly
),
Flagged AS (
    SELECT *, CAST(100.0 * RunningNet / NULLIF(YearNet, 0) AS DECIMAL(5,1)) AS PctReached,
           ROW_NUMBER() OVER (PARTITION BY Region ORDER BY MonthStart) AS rn
    FROM Running
    WHERE RunningNet > 0.5 * YearNet
)
SELECT Region, MonthStart AS HalfwayMonth, RunningNet, YearNet, PctReached
FROM Flagged
WHERE rn = 1
ORDER BY MonthStart, Region;
-- TRAP: three traps at once - (1) the FY runs April to March, so partition by region only and use the April-March
--       range (not YEAR()); (2) negative reversal lines can make a running total dip (not in this particular data, but it happens), so "first month above 50%" must be
--       the first row after filtering, not a LAG comparison; (3) use ROWS not the default RANGE so rows with the same
--       ORDER BY value cannot share a running value.
*/


/* ============================================================================
   END OF PRACTICE 09
   ============================================================================ */
