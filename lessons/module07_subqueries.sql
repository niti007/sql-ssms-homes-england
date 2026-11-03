USE HousingDelivery;
GO
/* ============================================================================
   MODULE 07 - SUBQUERIES
   Database : HousingDelivery (see SPEC.md)     Target : SQL Server 2019+ / SSMS
   Net funding : Homes * GrantPerHome * (1 - ClawbackRate)
   Financial year (FY) : April to March. 1 Apr 2024 .. 31 Mar 2025 = FY 2024/25.

   Run one example at a time (highlight + F5). Everything that fails on purpose
   is inside a commented-out "Common mistakes" block, so F5 on the WHOLE file works.
   Nothing in this module changes the shared tables: we only write to #temp
   tables, which vanish when your session closes.

   CONCEPTS
     A. Scalar subqueries (one value)
     B. Subqueries in WHERE (IN, =, >, HAVING)
     C. Subqueries in FROM (derived tables)
     D. Subqueries in SELECT
     E. Correlated subqueries
     F. EXISTS / NOT EXISTS  (and the NOT IN + NULL trap)
     G. ANY / SOME / ALL
     H. SELECT INTO  (#temp tables)
     I. INSERT INTO ... SELECT

   MENTAL MODEL: a subquery is a query inside a query, in brackets. The inner
   query runs first (or, if correlated, once per outer row) and hands its
   answer to the outer query - like asking a colleague a question before you
   can finish writing your own report.
   ============================================================================ */


/* ############################################################################
   CONCEPT A : SCALAR SUBQUERIES
   ############################################################################
   A scalar subquery returns exactly ONE row and ONE column - a single value.
   You can use it anywhere you could use a number: WHERE, SELECT, HAVING.
   If it returns more than one row you get an error; if it returns zero rows
   the value is NULL.
   ########################################################################## */

-- A.1  The simplest scalar query: one number
SELECT AVG(Salary) AS AvgSalary FROM dbo.Staff;

-- A.2  Staff paid above the average (we cannot write WHERE Salary > AVG(Salary))
SELECT StaffID, FirstName, LastName, JobTitle, Salary
FROM dbo.Staff
WHERE Salary > (SELECT AVG(Salary) FROM dbo.Staff)
ORDER BY Salary DESC, StaffID;

-- A.3  Sites with an above-average grant per home
SELECT TOP (15) SiteID, SiteName, Region, UnitPrice
FROM dbo.Sites
WHERE UnitPrice > (SELECT AVG(UnitPrice) FROM dbo.Sites)
ORDER BY UnitPrice DESC, SiteID;

-- A.4  Zero-grant (land-only) sites drag the average down. Compare the two averages.
SELECT (SELECT AVG(UnitPrice) FROM dbo.Sites)                    AS AvgIncludingLandOnly,
       (SELECT AVG(UnitPrice) FROM dbo.Sites WHERE UnitPrice > 0) AS AvgGrantFundedOnly;

-- A.5  The largest site(s) by planned homes (ties are all returned)
SELECT SiteID, SiteName, Region, PlannedHomes
FROM dbo.Sites
WHERE PlannedHomes = (SELECT MAX(PlannedHomes) FROM dbo.Sites);

-- A.6  Each region's share of all planned homes
SELECT Region,
       SUM(PlannedHomes) AS PlannedHomes,
       CAST(100.0 * SUM(PlannedHomes) / (SELECT SUM(PlannedHomes) FROM dbo.Sites) AS DECIMAL(5,2)) AS PctOfAll
FROM dbo.Sites
GROUP BY Region
ORDER BY PctOfAll DESC;

-- A.7  A scalar subquery in SELECT: how far is each salary from the average?
SELECT TOP (10) StaffID, LastName, Salary,
       Salary - (SELECT AVG(Salary) FROM dbo.Staff) AS DiffFromAvg
FROM dbo.Staff
ORDER BY DiffFromAvg DESC, StaffID;

-- A.8  Who was hired before the Chief Executive? (the CE is the row with no manager)
SELECT StaffID, FirstName, LastName, JobTitle, HireDate
FROM dbo.Staff
WHERE HireDate < (SELECT HireDate FROM dbo.Staff WHERE ManagerID IS NULL)
ORDER BY HireDate;

-- A.9  Latest application date, ignoring the ~20 future-dated records
SELECT MAX(ApplicationDate) AS LatestIncludingFuture,
       (SELECT MAX(ApplicationDate) FROM dbo.Applications WHERE ApplicationDate < '2026-01-01') AS LatestReal
FROM dbo.Applications;

-- A.10 Applications received on that last real day
SELECT ApplicationID, ApplicantID, ApplicationDate, Status
FROM dbo.Applications
WHERE CAST(ApplicationDate AS DATE) =
      (SELECT MAX(CAST(ApplicationDate AS DATE)) FROM dbo.Applications WHERE ApplicationDate < '2026-01-01')
ORDER BY ApplicationDate;

-- A.11 Zero rows from a scalar subquery gives NULL, not an error
SELECT (SELECT SiteName FROM dbo.Sites WHERE SiteID = -1) AS NoSuchSite;

-- A.12 Store a scalar subquery in a variable (run all 3 lines together)
DECLARE @AvgGrant DECIMAL(12,2) = (SELECT AVG(UnitPrice) FROM dbo.Sites WHERE UnitPrice > 0);
SELECT @AvgGrant AS AvgGrant;
SELECT COUNT(*) AS SitesAboveAvgGrant FROM dbo.Sites WHERE UnitPrice > @AvgGrant;

-- A.13 TOP (1) + ORDER BY inside a subquery makes it scalar: best-paid person's name
SELECT (SELECT TOP (1) FirstName + ' ' + LastName FROM dbo.Staff ORDER BY Salary DESC, StaffID) AS BestPaid;

/* --- Common mistakes (A) - uncomment ONE at a time to see the error ---------
-- ERROR: subquery returned more than 1 value (the = operator needs exactly one)
SELECT * FROM dbo.Sites WHERE Region = (SELECT Region FROM dbo.Partners);

-- ERROR: two columns in a scalar subquery
SELECT * FROM dbo.Staff WHERE Salary > (SELECT MIN(Salary), MAX(Salary) FROM dbo.Staff);

-- WRONG ANSWER, NO ERROR: "largest site" using a tie-blind TOP 1 hides tied sites
SELECT TOP (1) SiteName, PlannedHomes FROM dbo.Sites ORDER BY PlannedHomes DESC;
----------------------------------------------------------------------------- */

/* --- Predict the output (A) ---------------------------------------------------
   1. A.5 - will it always return exactly one row? (Think: tied PlannedHomes.)
   2. A.9 - which of the two columns is larger, and why?
   3. A.11 - error, empty result set, or one row containing NULL?
   Answers: 1) no, ties return several; 2) LatestIncludingFuture, because of the
   2026-2027 rows; 3) one row containing NULL.
----------------------------------------------------------------------------- */

-- Try it (A): list sites whose Hectares is below the average Hectares of ALL sites.
-- Bonus: show how many hectares below the average each one is.


/* ############################################################################
   CONCEPT B : SUBQUERIES IN WHERE
   ############################################################################
   When the inner query returns a LIST (one column, many rows) use IN / NOT IN.
   When it returns one value use =, >, < and friends. This is the classic
   "filter one table by facts held in another table" pattern.
   ########################################################################## */

-- B.1  Sites run by Registered Providers
SELECT TOP (15) SiteID, SiteName, Region, PartnerID
FROM dbo.Sites
WHERE PartnerID IN (SELECT PartnerID FROM dbo.Partners WHERE PartnerType = 'Registered Provider')
ORDER BY SiteID;

-- B.2  Sites that are NOT run by Developers (PartnerID is never NULL, so NOT IN is safe here)
SELECT COUNT(*) AS NonDeveloperSites
FROM dbo.Sites
WHERE PartnerID NOT IN (SELECT PartnerID FROM dbo.Partners WHERE PartnerType = 'Developer');

-- B.3  Sites whose tenure has "Rent" in its name
SELECT s.SiteID, s.SiteName, s.TenureTypeID
FROM dbo.Sites AS s
WHERE s.TenureTypeID IN (SELECT TenureTypeID FROM dbo.TenureTypes WHERE TenureName LIKE '%Rent%')
ORDER BY s.SiteID
OFFSET 0 ROWS FETCH NEXT 15 ROWS ONLY;

-- B.4  Applicants who have at least one Completed application
SELECT COUNT(*) AS ApplicantsWithCompletion
FROM dbo.Applicants
WHERE ApplicantID IN (SELECT ApplicantID FROM dbo.Applications WHERE Status = 'Completed');

-- B.5  Applications that include at least one brownfield site (3 tables, 2 levels)
SELECT COUNT(*) AS ApplicationsTouchingBrownfield
FROM dbo.Applications
WHERE ApplicationID IN (
        SELECT f.ApplicationID
        FROM dbo.FundingLines AS f
        WHERE f.SiteID IN (SELECT SiteID FROM dbo.Sites WHERE IsBrownfield = 1));

-- B.6  Everything in the same local authority as the 'Plot_7 Infill' site
SELECT SiteID, SiteName, LocalAuthority
FROM dbo.Sites
WHERE LocalAuthority IN (SELECT LocalAuthority FROM dbo.Sites WHERE SiteName = 'Plot_7 Infill')
ORDER BY SiteName;

-- B.7  Staff who have handled at least one application
--      (StaffID in Applications contains NULLs - harmless for IN, fatal for NOT IN; see Concept F)
SELECT StaffID, FirstName, LastName
FROM dbo.Staff
WHERE StaffID IN (SELECT StaffID FROM dbo.Applications)
ORDER BY StaffID;

-- B.8  Compare to a single value: sites with the same Hectares as the biggest site
SELECT SiteID, SiteName, Hectares
FROM dbo.Sites
WHERE Hectares = (SELECT MAX(Hectares) FROM dbo.Sites);

-- B.9  HAVING with a subquery: regions whose planned homes beat the average region
SELECT Region, SUM(PlannedHomes) AS PlannedHomes
FROM dbo.Sites
GROUP BY Region
HAVING SUM(PlannedHomes) > (SELECT AVG(RegionTotal)
                            FROM (SELECT SUM(PlannedHomes) AS RegionTotal
                                  FROM dbo.Sites GROUP BY Region) AS r)
ORDER BY PlannedHomes DESC;

-- B.10 Applicants registered before the earliest application ever recorded
SELECT COUNT(*) AS RegisteredBeforeFirstApp
FROM dbo.Applicants
WHERE RegisteredDate < (SELECT MIN(CAST(ApplicationDate AS DATE)) FROM dbo.Applications);

-- B.11 Stalled sites that still have homes planned, in tenures that DO have a name
SELECT TOP (10) SiteID, SiteName, PlannedHomes
FROM dbo.Sites
WHERE IsStalled = 1 AND PlannedHomes > 0
  AND TenureTypeID IN (SELECT TenureTypeID FROM dbo.TenureTypes)
ORDER BY PlannedHomes DESC, SiteID;

-- B.12 Applicants in the same household type as applicant 1
SELECT TOP (10) ApplicantID, FirstName, LastName, HouseholdType
FROM dbo.Applicants
WHERE HouseholdType = (SELECT HouseholdType FROM dbo.Applicants WHERE ApplicantID = 1)
ORDER BY ApplicantID;

/* --- Common mistakes (B) -------------------------------------------------------
-- ERROR: IN needs ONE column in the subquery
SELECT * FROM dbo.Sites WHERE PartnerID IN (SELECT PartnerID, PartnerName FROM dbo.Partners);

-- SUBTLE: = with a subquery that can return many rows works today, breaks tomorrow
SELECT * FROM dbo.Sites WHERE TenureTypeID = (SELECT TenureTypeID FROM dbo.TenureTypes WHERE TenureName LIKE '%Rent%');

-- WRONG: ORDER BY is not allowed inside a plain IN-subquery (without TOP)
SELECT * FROM dbo.Sites WHERE PartnerID IN (SELECT PartnerID FROM dbo.Partners ORDER BY PartnerName);
----------------------------------------------------------------------------- */

/* --- Predict the output (B) ---------------------------------------------------
   1. B.4 returns a count. Is it bigger or smaller than the number of applicants
      who have ANY application? (smaller or equal - Completed is just one status)
   2. B.9 - roughly half the regions appear, or all of them? (about half)
   3. In B.7 would adding NULL StaffID rows to the inner query change the answer? (no)
----------------------------------------------------------------------------- */

-- Try it (B): list Partners (name, type) that own at least one stalled site.


/* ############################################################################
   CONCEPT C : SUBQUERIES IN FROM (DERIVED TABLES)
   ############################################################################
   A query in the FROM clause behaves like a temporary table. Use it when you
   need to aggregate FIRST and then filter, join or aggregate again.
   It MUST have an alias. All its columns must have names.
   ########################################################################## */

-- C.1  Regions with more than 5,000 planned homes (aggregate, then filter)
SELECT r.Region, r.TotalHomes
FROM (SELECT Region, SUM(PlannedHomes) AS TotalHomes
      FROM dbo.Sites
      GROUP BY Region) AS r
WHERE r.TotalHomes > 5000
ORDER BY r.TotalHomes DESC;

-- C.2  Average of region totals (aggregate of an aggregate)
SELECT AVG(r.TotalHomes) AS AvgRegionTotal
FROM (SELECT Region, SUM(PlannedHomes) AS TotalHomes FROM dbo.Sites GROUP BY Region) AS r;

-- C.3  How many applicants have 1 application, 2 applications, 3 ...?
SELECT x.AppCount, COUNT(*) AS Applicants
FROM (SELECT ApplicantID, COUNT(*) AS AppCount
      FROM dbo.Applications
      GROUP BY ApplicantID) AS x
GROUP BY x.AppCount
ORDER BY x.AppCount;

-- C.4  Join a derived table: partners with their site counts
SELECT TOP (10) p.PartnerName, p.PartnerType, sc.SiteCount
FROM dbo.Partners AS p
JOIN (SELECT PartnerID, COUNT(*) AS SiteCount FROM dbo.Sites GROUP BY PartnerID) AS sc
     ON sc.PartnerID = p.PartnerID
ORDER BY sc.SiteCount DESC, p.PartnerID;

-- C.5  Net funding per application, then the average by status
SELECT a.Status, COUNT(*) AS Applications, AVG(nf.NetFunding) AS AvgNetFunding
FROM dbo.Applications AS a
JOIN (SELECT ApplicationID,
             SUM(Homes * GrantPerHome * (1 - ClawbackRate)) AS NetFunding
      FROM dbo.FundingLines
      GROUP BY ApplicationID) AS nf
     ON nf.ApplicationID = a.ApplicationID
GROUP BY a.Status
ORDER BY a.Status;

-- C.6  Net funding by financial year (the FY expression lives in the derived table)
SELECT fy.FinYear, SUM(fy.Net) AS NetFunding
FROM (SELECT CASE WHEN MONTH(a.ApplicationDate) >= 4 THEN YEAR(a.ApplicationDate)
                  ELSE YEAR(a.ApplicationDate) - 1 END AS FinYear,
             f.Homes * f.GrantPerHome * (1 - f.ClawbackRate) AS Net
      FROM dbo.Applications AS a
      JOIN dbo.FundingLines AS f ON f.ApplicationID = a.ApplicationID) AS fy
GROUP BY fy.FinYear
ORDER BY fy.FinYear;

-- C.7  Column aliases listed after the alias (alternative syntax)
SELECT t.Reg, t.N
FROM (SELECT Region, COUNT(*) FROM dbo.Sites GROUP BY Region) AS t (Reg, N)
ORDER BY t.N DESC;

-- C.8  Applicants whose application count is above the average application count
SELECT TOP (10) x.ApplicantID, x.AppCount
FROM (SELECT ApplicantID, COUNT(*) AS AppCount FROM dbo.Applications GROUP BY ApplicantID) AS x
WHERE x.AppCount > (SELECT AVG(1.0 * c) FROM (SELECT COUNT(*) AS c FROM dbo.Applications GROUP BY ApplicantID) AS y)
ORDER BY x.AppCount DESC, x.ApplicantID;

-- C.9  Compare two aggregations side by side: planned homes vs homes actually funded per region
SELECT p.Region, p.PlannedHomes, ISNULL(f.FundedHomes, 0) AS FundedHomes
FROM (SELECT Region, SUM(PlannedHomes) AS PlannedHomes FROM dbo.Sites GROUP BY Region) AS p
LEFT JOIN (SELECT s.Region, SUM(fl.Homes) AS FundedHomes
           FROM dbo.FundingLines AS fl JOIN dbo.Sites AS s ON s.SiteID = fl.SiteID
           GROUP BY s.Region) AS f
     ON f.Region = p.Region
ORDER BY p.Region;

-- C.10 Partner types ranked by their number of sites
SELECT t.PartnerType, t.Sites
FROM (SELECT p.PartnerType, COUNT(s.SiteID) AS Sites
      FROM dbo.Partners AS p LEFT JOIN dbo.Sites AS s ON s.PartnerID = p.PartnerID
      GROUP BY p.PartnerType) AS t
ORDER BY t.Sites DESC;

/* --- Common mistakes (C) -------------------------------------------------------
-- ERROR: derived table without an alias
SELECT * FROM (SELECT Region, COUNT(*) AS N FROM dbo.Sites GROUP BY Region);

-- ERROR: derived table column has no name
SELECT * FROM (SELECT Region, COUNT(*) FROM dbo.Sites GROUP BY Region) AS t;

-- ERROR: ORDER BY inside a derived table without TOP/OFFSET
SELECT * FROM (SELECT Region FROM dbo.Sites ORDER BY Region) AS t;

-- ERROR: using the alias from the same level (SELECT alias cannot be used in its own WHERE)
SELECT Region, SUM(PlannedHomes) AS Tot FROM dbo.Sites WHERE Tot > 5000 GROUP BY Region;
----------------------------------------------------------------------------- */

/* --- Predict the output (C) ---------------------------------------------------
   1. C.3 - what do you expect the FIRST row to be (AppCount = 1)? Applicants with
      no applications (~300) do NOT appear at all. Why? (they have no row to count)
   2. C.9 - a region where FundedHomes < PlannedHomes: is that an error? (no, funding is partial)
   3. C.6 - the first and last FinYear are probably "part" years (2021 data starts Jan 2022
      so FY 2021/22 is partial; the last FYs include future-dated rows).
----------------------------------------------------------------------------- */

-- Try it (C): using a derived table, show the average number of sites per partner.


/* ############################################################################
   CONCEPT D : SUBQUERIES IN SELECT
   ############################################################################
   A scalar subquery in the SELECT list adds a computed column to every row.
   When it refers to the outer row it is CORRELATED (more in Concept E).
   It is handy for "count of related things" but a JOIN + GROUP BY is often
   faster on big tables.
   ########################################################################## */

-- D.1  Each tenure with its number of sites (Self/Custom Build shows 0)
SELECT t.TenureTypeID, t.TenureName,
       (SELECT COUNT(*) FROM dbo.Sites AS s WHERE s.TenureTypeID = t.TenureTypeID) AS SiteCount
FROM dbo.TenureTypes AS t
ORDER BY t.TenureTypeID;

-- D.2  Partners with number of sites and total planned homes
SELECT TOP (10) p.PartnerID, p.PartnerName,
       (SELECT COUNT(*)                         FROM dbo.Sites s WHERE s.PartnerID = p.PartnerID) AS Sites,
       (SELECT ISNULL(SUM(s.PlannedHomes), 0)   FROM dbo.Sites s WHERE s.PartnerID = p.PartnerID) AS PlannedHomes
FROM dbo.Partners AS p
ORDER BY p.PartnerID;

-- D.3  Staff with the number of applications they processed
SELECT TOP (10) st.StaffID, st.LastName,
       (SELECT COUNT(*) FROM dbo.Applications a WHERE a.StaffID = st.StaffID) AS ApplicationsHandled
FROM dbo.Staff AS st
ORDER BY ApplicationsHandled DESC, st.StaffID;

-- D.4  First 10 applicants and the date of their latest application (NULL if none)
SELECT TOP (10) ap.ApplicantID, ap.LastName,
       (SELECT MAX(a.ApplicationDate) FROM dbo.Applications a WHERE a.ApplicantID = ap.ApplicantID) AS LastApplication
FROM dbo.Applicants AS ap
ORDER BY ap.ApplicantID;

-- D.5  Each tenure's share of sites, as a percentage of the grand total
SELECT t.TenureName,
       (SELECT COUNT(*) FROM dbo.Sites s WHERE s.TenureTypeID = t.TenureTypeID) AS Sites,
       CAST(100.0 * (SELECT COUNT(*) FROM dbo.Sites s WHERE s.TenureTypeID = t.TenureTypeID)
            / (SELECT COUNT(*) FROM dbo.Sites) AS DECIMAL(5,1)) AS PctOfSites
FROM dbo.TenureTypes AS t
ORDER BY Sites DESC;

-- D.6  Same as D.1 written as LEFT JOIN + GROUP BY (compare the plan with Ctrl+M later)
SELECT t.TenureTypeID, t.TenureName, COUNT(s.SiteID) AS SiteCount
FROM dbo.TenureTypes AS t
LEFT JOIN dbo.Sites AS s ON s.TenureTypeID = t.TenureTypeID
GROUP BY t.TenureTypeID, t.TenureName
ORDER BY t.TenureTypeID;

-- D.7  Subquery inside CASE: label each partner as 'Large' or 'Small' by site count
SELECT TOP (10) p.PartnerName,
       CASE WHEN (SELECT COUNT(*) FROM dbo.Sites s WHERE s.PartnerID = p.PartnerID) >= 15
            THEN 'Large' ELSE 'Small' END AS PartnerSize
FROM dbo.Partners AS p
ORDER BY p.PartnerID;

-- D.8  Subquery in ORDER BY: partners ordered by their site count
SELECT TOP (10) p.PartnerName
FROM dbo.Partners AS p
ORDER BY (SELECT COUNT(*) FROM dbo.Sites s WHERE s.PartnerID = p.PartnerID) DESC, p.PartnerID;

-- D.9  Net funding per application for the first 10 applications that have lines
SELECT TOP (10) a.ApplicationID, a.Status,
       (SELECT SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate))
        FROM dbo.FundingLines f WHERE f.ApplicationID = a.ApplicationID) AS NetFunding
FROM dbo.Applications AS a
WHERE EXISTS (SELECT 1 FROM dbo.FundingLines f WHERE f.ApplicationID = a.ApplicationID)
ORDER BY a.ApplicationID;

-- D.10 Applications with NO funding lines show NULL (not 0) for NetFunding
SELECT TOP (5) a.ApplicationID,
       (SELECT SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate))
        FROM dbo.FundingLines f WHERE f.ApplicationID = a.ApplicationID) AS NetFunding
FROM dbo.Applications AS a
WHERE NOT EXISTS (SELECT 1 FROM dbo.FundingLines f WHERE f.ApplicationID = a.ApplicationID)
ORDER BY a.ApplicationID;

/* --- Common mistakes (D) -------------------------------------------------------
-- ERROR: scalar subquery in SELECT returned more than one row (no aggregate)
SELECT p.PartnerName, (SELECT s.SiteName FROM dbo.Sites s WHERE s.PartnerID = p.PartnerID)
FROM dbo.Partners p;

-- WRONG: forgetting the correlation -> every row shows the SAME grand total
SELECT p.PartnerName, (SELECT COUNT(*) FROM dbo.Sites) AS Sites FROM dbo.Partners p;

-- SUBTLE: five near-identical subqueries on one table = five scans. Prefer one JOIN + GROUP BY.
----------------------------------------------------------------------------- */

/* --- Predict the output (D) ---------------------------------------------------
   1. D.1 - what SiteCount does 'Self/Custom Build' get? (0)  What tenure is missing
      from the SiteCount sum compared with COUNT(*) of Sites? (the ~5 NULL-tenure sites)
   2. D.10 - SUM over zero rows gives 0 or NULL? (NULL)
   3. D.4 - applicants with no applications show what in LastApplication? (NULL)
----------------------------------------------------------------------------- */

-- Try it (D): for the first 10 programmes show ProgrammeName and how many applications use it.
-- Which programme shows 0? (Community Housing Fund)


/* ############################################################################
   CONCEPT E : CORRELATED SUBQUERIES
   ############################################################################
   A correlated subquery refers to a column of the OUTER query, so it is
   re-evaluated for each outer row ("for each site, compute the average of THAT
   site's region"). Read it as a loop: for every row ... ask the question ...
   ########################################################################## */

-- E.1  Sites bigger than the average site IN THEIR OWN region
SELECT TOP (15) s.SiteID, s.SiteName, s.Region, s.PlannedHomes
FROM dbo.Sites AS s
WHERE s.PlannedHomes > (SELECT AVG(s2.PlannedHomes) FROM dbo.Sites AS s2 WHERE s2.Region = s.Region)
ORDER BY s.Region, s.PlannedHomes DESC, s.SiteID;

-- E.2  Staff paid more than the average of their own directorate
SELECT st.StaffID, st.LastName, st.Directorate, st.Salary
FROM dbo.Staff AS st
WHERE st.Salary > (SELECT AVG(x.Salary) FROM dbo.Staff AS x WHERE x.Directorate = st.Directorate)
ORDER BY st.Directorate, st.Salary DESC;

-- E.3  Each applicant's most recent application (first 20 applicants who have one)
SELECT TOP (20) a.ApplicantID, a.ApplicationID, a.ApplicationDate, a.Status
FROM dbo.Applications AS a
WHERE a.ApplicationDate = (SELECT MAX(b.ApplicationDate) FROM dbo.Applications AS b WHERE b.ApplicantID = a.ApplicantID)
ORDER BY a.ApplicantID;
-- note: if an applicant has two applications at the identical timestamp both come back

-- E.4  Highest-paid person in each office (salary ties return several people)
SELECT st.Office, st.LastName, st.Salary
FROM dbo.Staff AS st
WHERE st.Salary = (SELECT MAX(x.Salary) FROM dbo.Staff AS x WHERE x.Office = st.Office)
ORDER BY st.Office, st.StaffID;

-- E.5  The previous application date for each application (correlated MAX in SELECT)
SELECT TOP (15) a.ApplicantID, a.ApplicationID, a.ApplicationDate,
       (SELECT MAX(p.ApplicationDate) FROM dbo.Applications AS p
        WHERE p.ApplicantID = a.ApplicantID AND p.ApplicationDate < a.ApplicationDate) AS PreviousApplication
FROM dbo.Applications AS a
WHERE a.ApplicantID <= 50
ORDER BY a.ApplicantID, a.ApplicationDate;

-- E.6  Applications whose AdminFee is above that applicant's own average fee
--      (AVG ignores NULL fees; applications with NULL fee never satisfy ">")
SELECT TOP (15) a.ApplicationID, a.ApplicantID, a.AdminFee
FROM dbo.Applications AS a
WHERE a.AdminFee > (SELECT AVG(b.AdminFee) FROM dbo.Applications AS b WHERE b.ApplicantID = a.ApplicantID)
ORDER BY a.ApplicantID, a.ApplicationID;

-- E.7  The priciest-grant site(s) within each tenure
--      TRAP: sites with TenureTypeID NULL never match "= s.TenureTypeID" so they vanish
SELECT s.TenureTypeID, s.SiteName, s.UnitPrice
FROM dbo.Sites AS s
WHERE s.UnitPrice = (SELECT MAX(x.UnitPrice) FROM dbo.Sites AS x WHERE x.TenureTypeID = s.TenureTypeID)
ORDER BY s.TenureTypeID, s.SiteID;

-- E.8  Fix for E.7: treat NULL tenure as a group of its own
SELECT s.TenureTypeID, s.SiteName, s.UnitPrice
FROM dbo.Sites AS s
WHERE s.UnitPrice = (SELECT MAX(x.UnitPrice) FROM dbo.Sites AS x
                     WHERE x.TenureTypeID = s.TenureTypeID
                        OR (x.TenureTypeID IS NULL AND s.TenureTypeID IS NULL))
ORDER BY s.TenureTypeID, s.SiteID;

-- E.9  Correlated running total (works, but re-reads the table per row: see Module 09 for the better way)
SELECT TOP (10) a.ApplicationID, a.ApplicationDate,
       (SELECT COUNT(*) FROM dbo.Applications b WHERE b.ApplicationID <= a.ApplicationID) AS RunningCount
FROM dbo.Applications AS a
ORDER BY a.ApplicationID;

-- E.10 Staff who earn more than their own manager (correlated through ManagerID)
--      Expected: 0 rows - nobody out-earns their manager in this data.
SELECT st.StaffID, st.LastName, st.Salary
FROM dbo.Staff AS st
WHERE st.Salary > (SELECT m.Salary FROM dbo.Staff AS m WHERE m.StaffID = st.ManagerID);
-- the Chief Executive has ManagerID NULL: subquery returns NULL, comparison unknown, row dropped

-- E.11 Applicants who registered after their own first application (data-quality check;
--      expected: 0 rows - the data is consistent)
SELECT TOP (10) ap.ApplicantID, ap.RegisteredDate,
       (SELECT MIN(CAST(a.ApplicationDate AS DATE)) FROM dbo.Applications a WHERE a.ApplicantID = ap.ApplicantID) AS FirstApp
FROM dbo.Applicants AS ap
WHERE ap.RegisteredDate > (SELECT MIN(CAST(a.ApplicationDate AS DATE)) FROM dbo.Applications a WHERE a.ApplicantID = ap.ApplicantID)
ORDER BY ap.ApplicantID;

/* --- Common mistakes (E) -------------------------------------------------------
-- WRONG: same alias on inner and outer table so the "correlation" is s.Region = s.Region (always true)
SELECT s.SiteName FROM dbo.Sites s
WHERE s.PlannedHomes > (SELECT AVG(PlannedHomes) FROM dbo.Sites s WHERE s.Region = s.Region);

-- ERROR: outer alias used in the FROM of an uncorrelated derived table
SELECT * FROM dbo.Sites s JOIN (SELECT AVG(PlannedHomes) a FROM dbo.Sites WHERE Region = s.Region) x ON 1 = 1;

-- SLOW (not wrong): correlated subquery over 60,000 applications per row - test on TOP (n) first
----------------------------------------------------------------------------- */

/* --- Predict the output (E) ---------------------------------------------------
   1. E.4 - can an office appear twice? (yes, if two people tie on the top salary)
   2. E.7 vs E.8 - which returns more rows, and by how many? (E.8, by the NULL-tenure sites at the top)
   3. E.10 - is the Chief Executive in the output? (no)
----------------------------------------------------------------------------- */

-- Try it (E): sites with a UnitPrice higher than the average UnitPrice for the same PARTNER.


/* ############################################################################
   CONCEPT F : EXISTS / NOT EXISTS  (and the NOT IN + NULL trap)
   ############################################################################
   EXISTS asks "is there at least one matching row?" and answers TRUE/FALSE. The
   columns the inner query selects are irrelevant (people write SELECT 1).
   NOT EXISTS is the safe way to find "things that have none of ...".
   NOT IN is dangerous: if the inner list contains even ONE NULL, NOT IN
   returns NO rows at all (because x <> NULL is "unknown", never true).
   ########################################################################## */

-- F.1  Applicants with at least one application
SELECT COUNT(*) AS ApplicantsWithApps
FROM dbo.Applicants AS ap
WHERE EXISTS (SELECT 1 FROM dbo.Applications AS a WHERE a.ApplicantID = ap.ApplicantID);

-- F.2  Applicants with NO application (~300)
SELECT COUNT(*) AS ApplicantsNoApps
FROM dbo.Applicants AS ap
WHERE NOT EXISTS (SELECT 1 FROM dbo.Applications AS a WHERE a.ApplicantID = ap.ApplicantID);

-- F.3  Sites never funded (~40)
SELECT TOP (10) s.SiteID, s.SiteName, s.Region
FROM dbo.Sites AS s
WHERE NOT EXISTS (SELECT 1 FROM dbo.FundingLines AS f WHERE f.SiteID = s.SiteID)
ORDER BY s.SiteID;

-- F.4  Tenures with no sites (Self/Custom Build) - THE CORRECT WAY
SELECT t.TenureTypeID, t.TenureName
FROM dbo.TenureTypes AS t
WHERE NOT EXISTS (SELECT 1 FROM dbo.Sites AS s WHERE s.TenureTypeID = t.TenureTypeID);

-- F.5  The same question with NOT IN - returns NOTHING. Why? Sites.TenureTypeID contains NULLs.
SELECT t.TenureTypeID, t.TenureName
FROM dbo.TenureTypes AS t
WHERE t.TenureTypeID NOT IN (SELECT s.TenureTypeID FROM dbo.Sites AS s);

-- F.6  Proof: how many NULLs are in the inner list?
SELECT COUNT(*) AS SitesWithNullTenure FROM dbo.Sites WHERE TenureTypeID IS NULL;

-- F.7  NOT IN fixed by removing NULLs from the list
SELECT t.TenureTypeID, t.TenureName
FROM dbo.TenureTypes AS t
WHERE t.TenureTypeID NOT IN (SELECT s.TenureTypeID FROM dbo.Sites AS s WHERE s.TenureTypeID IS NOT NULL);

-- F.8  Programmes never used by an application: NOT EXISTS works, NOT IN fails
SELECT p.ProgrammeID, p.ProgrammeName
FROM dbo.Programmes AS p
WHERE NOT EXISTS (SELECT 1 FROM dbo.Applications a WHERE a.ProgrammeID = p.ProgrammeID);

SELECT p.ProgrammeID, p.ProgrammeName     -- Applications.ProgrammeID has NULLs -> 0 rows
FROM dbo.Programmes AS p
WHERE p.ProgrammeID NOT IN (SELECT a.ProgrammeID FROM dbo.Applications a);

-- F.9  Staff who have never processed an application (StaffID NULL = online self-service)
SELECT st.StaffID, st.LastName
FROM dbo.Staff AS st
WHERE NOT EXISTS (SELECT 1 FROM dbo.Applications a WHERE a.StaffID = st.StaffID);

-- F.10 Anti-join with LEFT JOIN ... IS NULL: same answer as F.3
SELECT TOP (10) s.SiteID, s.SiteName
FROM dbo.Sites AS s
LEFT JOIN dbo.FundingLines AS f ON f.SiteID = s.SiteID
WHERE f.FundingLineID IS NULL
ORDER BY s.SiteID;

-- F.11 Applications with no funding lines (~600)
SELECT COUNT(*) AS ApplicationsNoLines
FROM dbo.Applications AS a
WHERE NOT EXISTS (SELECT 1 FROM dbo.FundingLines AS f WHERE f.ApplicationID = a.ApplicationID);

-- F.12 Duplicate applicant names: another applicant with the same first+last name
SELECT TOP (15) ap.ApplicantID, ap.FirstName, ap.LastName, ap.City
FROM dbo.Applicants AS ap
WHERE EXISTS (SELECT 1 FROM dbo.Applicants AS o
              WHERE o.ApplicantID <> ap.ApplicantID
                AND UPPER(TRIM(o.FirstName)) = UPPER(TRIM(ap.FirstName))
                AND UPPER(TRIM(o.LastName))  = UPPER(TRIM(ap.LastName)))
ORDER BY ap.LastName, ap.FirstName, ap.ApplicantID;
-- same name does NOT prove same person: always check DOB/address/email in real life

-- F.13 Combine EXISTS and NOT EXISTS: applicants with a data-error application
--      (CompletionDate earlier than ApplicationDate) who have never been Rejected
SELECT TOP (10) ap.ApplicantID
FROM dbo.Applicants AS ap
WHERE EXISTS (SELECT 1 FROM dbo.Applications a
              WHERE a.ApplicantID = ap.ApplicantID AND a.CompletionDate < CAST(a.ApplicationDate AS DATE))
  AND NOT EXISTS (SELECT 1 FROM dbo.Applications a
              WHERE a.ApplicantID = ap.ApplicantID AND a.Status = 'Rejected')
ORDER BY ap.ApplicantID;

-- F.14 EXISTS vs IN: same result, EXISTS stops at the first match
SELECT COUNT(*) AS ViaIn
FROM dbo.Sites WHERE SiteID IN (SELECT SiteID FROM dbo.FundingLines);
SELECT COUNT(*) AS ViaExists
FROM dbo.Sites s WHERE EXISTS (SELECT 1 FROM dbo.FundingLines f WHERE f.SiteID = s.SiteID);

/* --- Common mistakes (F) -------------------------------------------------------
-- WRONG: NOT IN against a column that can hold NULL (returns zero rows silently)
SELECT * FROM dbo.TenureTypes WHERE TenureTypeID NOT IN (SELECT TenureTypeID FROM dbo.Sites);

-- WRONG: forgetting the correlation in EXISTS -> TRUE for every row if the table has any row
SELECT * FROM dbo.Applicants WHERE EXISTS (SELECT 1 FROM dbo.Applications);

-- WRONG: NOT EXISTS correlated on the wrong column (returns the whole table)
SELECT * FROM dbo.Sites s WHERE NOT EXISTS (SELECT 1 FROM dbo.FundingLines f WHERE f.FundingLineID = s.SiteID);

-- WRONG: inner join + "IS NULL" on the LEFT table's column (never NULL for a real row)
SELECT s.SiteID FROM dbo.Sites s LEFT JOIN dbo.FundingLines f ON f.SiteID = s.SiteID WHERE s.SiteID IS NULL;
----------------------------------------------------------------------------- */

/* --- Predict the output (F) ---------------------------------------------------
   1. F.1 + F.2 add up to? (10,000 - the whole applicants table)
   2. F.5 returns how many rows? (0)   F.7? (1 - Self/Custom Build)
   3. F.10 and F.3 give the same rows? (yes, same set)
   4. Does F.12 prove that two applicants are the same person? (no)
----------------------------------------------------------------------------- */

-- Try it (F): list Partners with no sites at all (expect 0 rows - say why that is good news), using NOT EXISTS. Then repeat with NOT IN
-- and decide whether NOT IN would have been safe (is Sites.PartnerID ever NULL?).


/* ############################################################################
   CONCEPT G : ANY / SOME / ALL
   ############################################################################
   Compare a value with a whole list returned by a subquery:
     x > ANY (list)  = bigger than AT LEAST ONE value   (same as x > MIN)
     x > ALL (list)  = bigger than EVERY value          (same as x > MAX)
     x = ANY (list)  = same as IN
     x <> ALL (list) = same as NOT IN (and has the same NULL trap)
   SOME is a synonym for ANY. ALL over an EMPTY list is TRUE.
   ########################################################################## */

-- G.1  Sites with a grant higher than AT LEAST ONE North East site
SELECT COUNT(*) AS Cnt
FROM dbo.Sites
WHERE UnitPrice > ANY (SELECT UnitPrice FROM dbo.Sites WHERE Region = 'North East');

-- G.2  Sites with a grant higher than EVERY North East site
SELECT SiteID, SiteName, Region, UnitPrice
FROM dbo.Sites
WHERE UnitPrice > ALL (SELECT UnitPrice FROM dbo.Sites WHERE Region = 'North East')
ORDER BY UnitPrice DESC, SiteID
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;

-- G.3  > ANY is the same as > MIN
SELECT COUNT(*) AS SameAsG1
FROM dbo.Sites
WHERE UnitPrice > (SELECT MIN(UnitPrice) FROM dbo.Sites WHERE Region = 'North East');

-- G.4  > ALL is the same as > MAX
SELECT COUNT(*) AS SameAsG2
FROM dbo.Sites
WHERE UnitPrice > (SELECT MAX(UnitPrice) FROM dbo.Sites WHERE Region = 'North East');

-- G.5  = ANY is IN
SELECT COUNT(*) AS Via_EqAny
FROM dbo.Sites WHERE PartnerID = ANY (SELECT PartnerID FROM dbo.Partners WHERE PartnerType = 'SME Builder');
SELECT COUNT(*) AS Via_In
FROM dbo.Sites WHERE PartnerID IN (SELECT PartnerID FROM dbo.Partners WHERE PartnerType = 'SME Builder');

-- G.6  Staff who earn more than EVERYONE in the Leeds office
SELECT StaffID, LastName, Office, Salary
FROM dbo.Staff
WHERE Salary > ALL (SELECT Salary FROM dbo.Staff WHERE Office = 'Leeds')
ORDER BY Salary DESC, StaffID;

-- G.7  Staff who earn at least as much as SOME London colleague (SOME = ANY)
SELECT COUNT(*) AS Cnt
FROM dbo.Staff
WHERE Salary >= SOME (SELECT Salary FROM dbo.Staff WHERE Office = 'London');

-- G.8  Salary ties: who ties for the top of Leeds? Use >= ALL
SELECT StaffID, LastName, Salary
FROM dbo.Staff
WHERE Office = 'Leeds'
  AND Salary >= ALL (SELECT Salary FROM dbo.Staff WHERE Office = 'Leeds');

-- G.9  ALL over an empty list is TRUE - every staff row survives
SELECT COUNT(*) AS AllStaff
FROM dbo.Staff
WHERE Salary > ALL (SELECT Salary FROM dbo.Staff WHERE Office = 'Atlantis');

-- G.10 ANY over an empty list is FALSE - zero rows
SELECT COUNT(*) AS NoRows
FROM dbo.Staff
WHERE Salary > ANY (SELECT Salary FROM dbo.Staff WHERE Office = 'Atlantis');

-- G.11 <> ALL behaves like NOT IN: the NULL tenure on Sites poisons it -> 0 rows
SELECT TenureTypeID, TenureName
FROM dbo.TenureTypes
WHERE TenureTypeID <> ALL (SELECT TenureTypeID FROM dbo.Sites);

-- G.12 Sites with more planned homes than ALL brownfield sites in London
SELECT TOP (10) SiteID, SiteName, PlannedHomes
FROM dbo.Sites
WHERE PlannedHomes > ALL (SELECT PlannedHomes FROM dbo.Sites WHERE Region = 'London' AND IsBrownfield = 1)
ORDER BY PlannedHomes DESC, SiteID;

/* --- Common mistakes (G) -------------------------------------------------------
-- ERROR: ANY / ALL need a comparison operator before them
SELECT * FROM dbo.Sites WHERE UnitPrice ANY (SELECT UnitPrice FROM dbo.Sites);

-- ERROR: ANY / ALL need a subquery, not a literal list
SELECT * FROM dbo.Sites WHERE UnitPrice > ALL (100, 200);

-- WRONG: thinking "> ANY" means "greater than all" (it means greater than the SMALLEST)
----------------------------------------------------------------------------- */

/* --- Predict the output (G) ---------------------------------------------------
   1. G.1 returns more or fewer rows than G.2? (more, ANY is easier to satisfy)
   2. G.3 vs G.1 - same count? (yes)   G.9 vs G.10 - 60 vs 0.
   3. G.11 - zero rows because of the NULL. Which fix do you remember? (filter NULLs, or NOT EXISTS)
----------------------------------------------------------------------------- */

-- Try it (G): find sites whose PlannedHomes is smaller than ANY London site's PlannedHomes, then
-- rewrite the same filter using MAX instead of ANY and check the counts match.


/* ############################################################################
   CONCEPT H : SELECT INTO (#temp tables)
   ############################################################################
   SELECT ... INTO #name creates a NEW table from a query result in one step
   and fills it. A name starting with # is a TEMP table: only you can see it
   and it vanishes when you disconnect. Great for staging an answer you will
   reuse several times, without touching the shared tables.
   If the table already exists, SELECT INTO fails - so DROP TABLE IF EXISTS first.
   ########################################################################## */

-- H.1  Stage region totals
DROP TABLE IF EXISTS #RegionTotals;
SELECT Region, COUNT(*) AS Sites, SUM(PlannedHomes) AS PlannedHomes
INTO #RegionTotals
FROM dbo.Sites
GROUP BY Region;
SELECT * FROM #RegionTotals ORDER BY PlannedHomes DESC;

-- H.2  Use it like any table
SELECT r.Region, r.PlannedHomes, s.SiteName
FROM #RegionTotals AS r
JOIN dbo.Sites AS s ON s.Region = r.Region AND s.PlannedHomes = (SELECT MAX(PlannedHomes) FROM dbo.Sites x WHERE x.Region = r.Region)
ORDER BY r.Region;

-- H.3  Copy structure only (no rows) with WHERE 1 = 0
DROP TABLE IF EXISTS #SitesShell;
SELECT * INTO #SitesShell FROM dbo.Sites WHERE 1 = 0;
SELECT COUNT(*) AS RowsCopied FROM #SitesShell;

-- H.4  Computed columns need an alias, or the INTO fails
DROP TABLE IF EXISTS #SiteGrant;
SELECT SiteID, SiteName, PlannedHomes * UnitPrice AS GrossGrant
INTO #SiteGrant
FROM dbo.Sites
WHERE UnitPrice > 0;
SELECT TOP (5) * FROM #SiteGrant ORDER BY GrossGrant DESC;

-- H.5  Check a temp table exists
SELECT OBJECT_ID('tempdb..#SiteGrant') AS TempTableId;   -- NULL means it does not exist

-- H.6  Stage funding for FY 2024/25 (1 Apr 2024 - 31 Mar 2025). Midnight-safe date range.
DROP TABLE IF EXISTS #FY2425;
SELECT a.ApplicationID, a.ApplicationDate, a.Status,
       f.SiteID, f.Homes, f.Homes * f.GrantPerHome * (1 - f.ClawbackRate) AS NetFunding
INTO #FY2425
FROM dbo.Applications AS a
JOIN dbo.FundingLines AS f ON f.ApplicationID = a.ApplicationID
WHERE a.ApplicationDate >= '2024-04-01' AND a.ApplicationDate < '2025-04-01';
SELECT COUNT(*) AS Lines, SUM(NetFunding) AS NetFunding FROM #FY2425;
-- a BETWEEN '2024-04-01' AND '2025-03-31' filter would drop 31 March after 00:00:00 - use < next day

-- H.7  Reuse the staged data several times without re-joining
SELECT Status, COUNT(DISTINCT ApplicationID) AS Applications, SUM(NetFunding) AS NetFunding
FROM #FY2425 GROUP BY Status ORDER BY Status;

-- H.8  Column types are inherited from the source (check them)
SELECT c.name, t.name AS TypeName, c.max_length, c.is_nullable
FROM tempdb.sys.columns AS c
JOIN tempdb.sys.types AS t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('tempdb..#RegionTotals');

-- H.9  A temp table is a real table: you can index it afterwards
CREATE INDEX IX_RegionTotals_Region ON #RegionTotals (Region);
-- (SELECT INTO copies no keys or indexes - add the ones you need yourself)

-- H.10 Global temp table ## is visible to other sessions too (use sparingly)
DROP TABLE IF EXISTS ##LastRun;
SELECT SYSDATETIME() AS RunAt, SUSER_SNAME() AS RunBy INTO ##LastRun;
SELECT * FROM ##LastRun;
DROP TABLE ##LastRun;

-- H.11 Tidy up
DROP TABLE IF EXISTS #RegionTotals, #SitesShell, #SiteGrant, #FY2425;

/* --- Common mistakes (H) -------------------------------------------------------
-- ERROR: table already exists (run H.1 twice without the DROP)
SELECT Region INTO #RegionTotals FROM dbo.Sites;

-- ERROR: no column name for the computed column
SELECT SiteID, PlannedHomes * UnitPrice INTO #Bad FROM dbo.Sites;

-- GOTCHA: SELECT INTO does NOT copy PRIMARY KEY, FOREIGN KEY, indexes or defaults
-- GOTCHA: INTO must come after the SELECT list and before FROM
----------------------------------------------------------------------------- */

/* --- Predict the output (H) ---------------------------------------------------
   1. H.3 - how many rows? (0)   Does #SitesShell have columns? (yes, all Sites columns)
   2. H.5 - a number or NULL? (a number, while the table exists; NULL after H.11)
   3. Open a new query window and select from #FY2425 - what happens? (Invalid object name)
----------------------------------------------------------------------------- */

-- Try it (H): build #BrownfieldSites holding SiteID, SiteName, Region of all brownfield sites
-- that are not stalled, then count them by region from the temp table.


/* ############################################################################
   CONCEPT I : INSERT INTO ... SELECT
   ############################################################################
   INSERT INTO existing_table (columns) SELECT ... copies the rows a query
   returns into a table that ALREADY exists. Column order and data types must
   line up. Unlike SELECT INTO, you control the target's design (keys, defaults).
   Here we use #temp tables so the shared data is never touched; Module 08 shows
   the same pattern on real tables inside BEGIN TRAN ... ROLLBACK.
   ########################################################################## */

-- I.1  Create the target, then fill it from a query
DROP TABLE IF EXISTS #FYSummary;
CREATE TABLE #FYSummary (
    FinYear      INT           NOT NULL PRIMARY KEY,
    Applications INT           NOT NULL,
    NetFunding   DECIMAL(18,2) NULL
);
INSERT INTO #FYSummary (FinYear, Applications, NetFunding)
SELECT CASE WHEN MONTH(a.ApplicationDate) >= 4 THEN YEAR(a.ApplicationDate) ELSE YEAR(a.ApplicationDate) - 1 END,
       COUNT(DISTINCT a.ApplicationID),
       SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate))
FROM dbo.Applications AS a
LEFT JOIN dbo.FundingLines AS f ON f.ApplicationID = a.ApplicationID
GROUP BY CASE WHEN MONTH(a.ApplicationDate) >= 4 THEN YEAR(a.ApplicationDate) ELSE YEAR(a.ApplicationDate) - 1 END;
SELECT * FROM #FYSummary ORDER BY FinYear;

-- I.2  Column list lets you skip columns (they get NULL or their DEFAULT)
DROP TABLE IF EXISTS #SmallSites;
CREATE TABLE #SmallSites (SiteID INT, SiteName NVARCHAR(100), Note NVARCHAR(50) NULL);
INSERT INTO #SmallSites (SiteID, SiteName)
SELECT TOP (5) SiteID, SiteName FROM dbo.Sites ORDER BY PlannedHomes, SiteID;
SELECT * FROM #SmallSites;

-- I.3  Add a constant and a computed value while copying
INSERT INTO #SmallSites (SiteID, SiteName, Note)
SELECT TOP (3) SiteID, SiteName, 'stalled, ' + CAST(PlannedHomes AS VARCHAR(10)) + ' homes planned'
FROM dbo.Sites
WHERE IsStalled = 1 AND PlannedHomes > 0
ORDER BY PlannedHomes DESC, SiteID;
SELECT * FROM #SmallSites ORDER BY SiteID;

-- I.4  Avoid duplicates: insert only rows that are not already there
INSERT INTO #SmallSites (SiteID, SiteName, Note)
SELECT TOP (8) s.SiteID, s.SiteName, 'second pass'
FROM dbo.Sites AS s
WHERE NOT EXISTS (SELECT 1 FROM #SmallSites AS t WHERE t.SiteID = s.SiteID)
ORDER BY s.PlannedHomes, s.SiteID;
SELECT COUNT(*) AS RowsNow, COUNT(DISTINCT SiteID) AS DistinctSites FROM #SmallSites;

-- I.5  Insert the result of a join with a derived table
DROP TABLE IF EXISTS #PartnerStats;
CREATE TABLE #PartnerStats (PartnerID INT PRIMARY KEY, PartnerName NVARCHAR(100), Sites INT, PlannedHomes INT);
INSERT INTO #PartnerStats
SELECT p.PartnerID, p.PartnerName, COUNT(s.SiteID), ISNULL(SUM(s.PlannedHomes), 0)
FROM dbo.Partners AS p LEFT JOIN dbo.Sites AS s ON s.PartnerID = p.PartnerID
GROUP BY p.PartnerID, p.PartnerName;
SELECT TOP (5) * FROM #PartnerStats ORDER BY PlannedHomes DESC;

-- I.6  Without a column list the SELECT must match ALL columns in order (fragile - avoid!)
--      (works above only because the SELECT list matches the 4 columns exactly)

-- I.7  Row counts: @@ROWCOUNT shows how many rows went in (read it immediately)
INSERT INTO #SmallSites (SiteID, SiteName)
SELECT TOP (2) SiteID, SiteName FROM dbo.Sites ORDER BY SiteID DESC;
SELECT @@ROWCOUNT AS RowsInserted;

-- I.8  INSERT ... SELECT with UNION ALL: combine two sources
DROP TABLE IF EXISTS #Contacts;
CREATE TABLE #Contacts (Source VARCHAR(10), FullName NVARCHAR(200), Email NVARCHAR(100));
INSERT INTO #Contacts (Source, FullName, Email)
SELECT 'Applicant', TRIM(FirstName) + ' ' + TRIM(LastName), NULLIF(TRIM(Email), '')
FROM dbo.Applicants WHERE ApplicantID <= 5
UNION ALL
SELECT 'Partner', ContactName, NULL
FROM dbo.Partners WHERE PartnerID <= 5;
SELECT * FROM #Contacts;

-- I.9  Type problems: the target column is too small -> truncation error. Test safely:
--      (see Common mistakes)

-- I.10 Tidy up
DROP TABLE IF EXISTS #FYSummary, #SmallSites, #PartnerStats, #Contacts;

/* --- Common mistakes (I) -------------------------------------------------------
-- ERROR: column count mismatch (3 targets, 2 selected)
INSERT INTO #SmallSites (SiteID, SiteName, Note) SELECT SiteID, SiteName FROM dbo.Sites;

-- ERROR: String or binary data would be truncated
CREATE TABLE #Tiny (Name NVARCHAR(5)); INSERT INTO #Tiny SELECT SiteName FROM dbo.Sites;

-- ERROR: primary key violation if you run I.1 twice (FinYear already there)

-- SILENT BUG: columns in the wrong order but compatible types -> data lands in the wrong column
INSERT INTO #PartnerStats SELECT PartnerID, PartnerName, PlannedHomes, 0 FROM dbo.Sites;
----------------------------------------------------------------------------- */

/* --- Predict the output (I) ---------------------------------------------------
   1. I.1 - the lowest FinYear is 2021 (Jan-Mar 2022 applications belong to FY 2021/22).
   2. I.4 - the second insert adds 8 or fewer rows? (up to 8; skipped ones already present)
   3. I.7 - @@ROWCOUNT = 2.
----------------------------------------------------------------------------- */

-- Try it (I): create #TopSites (SiteID INT, SiteName NVARCHAR(100), Region NVARCHAR(50)) and fill it
-- with the 3 sites with the most PlannedHomes in each of two regions of your choice (two INSERTs).


/* ============================================================================
   END OF MODULE 07. Next: module08_dml_ddl.sql
   ============================================================================ */
