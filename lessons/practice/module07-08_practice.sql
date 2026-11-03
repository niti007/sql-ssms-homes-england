USE HousingDelivery;
GO
/* ============================================================================
   PRACTICE - MODULES 07 and 08  (subqueries, DML, DDL, constraints)
   10 business questions, easy -> hard. Try each one BEFORE opening its solution.
   To check yourself: copy the SOLUTION text out of the comment (or remove the
   comment marks), run it, and compare with your own result.
   Net funding = Homes * GrantPerHome * (1 - ClawbackRate)
   UK financial year (FY) = 1 April to 31 March. FY 2024/25 = 1 Apr 2024 .. 31 Mar 2025.

   Every question that changes data (Q7, Q8, Q9) must be wrapped in
   BEGIN TRAN ... ROLLBACK so the shared dataset stays untouched.
   Several questions hit planted data traps - read the "TRAP" line after trying.
   ============================================================================ */


/* ----------------------------------------------------------------------------
   Q1 (easy) - Above-average grant
   The programme board asks: which sites receive a grant per home (UnitPrice) above
   the average for grant-funded sites? Show the count of such sites and the 10 with
   the highest grant (SiteID, SiteName, Region, UnitPrice).
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q1
SELECT COUNT(*) AS SitesAboveAverage
FROM dbo.Sites
WHERE UnitPrice > (SELECT AVG(UnitPrice) FROM dbo.Sites WHERE UnitPrice > 0);

SELECT TOP (10) SiteID, SiteName, Region, UnitPrice
FROM dbo.Sites
WHERE UnitPrice > (SELECT AVG(UnitPrice) FROM dbo.Sites WHERE UnitPrice > 0)
ORDER BY UnitPrice DESC, SiteID;
-- TRAP: land-only sites have UnitPrice = 0; if you average ALL sites those zeros drag the average
--       down and too many sites look "above average". The inner WHERE UnitPrice > 0 matters.
*/


/* ----------------------------------------------------------------------------
   Q2 (easy) - Applicants who have been turned down
   How many DIFFERENT applicants have had at least one Rejected application? Then list
   the first 10 by ApplicantID with their name and city.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q2
SELECT COUNT(*) AS ApplicantsWithRejection
FROM dbo.Applicants
WHERE ApplicantID IN (SELECT ApplicantID FROM dbo.Applications WHERE Status = 'Rejected');

SELECT TOP (10) ApplicantID, TRIM(FirstName) AS FirstName, TRIM(LastName) AS LastName, City
FROM dbo.Applicants
WHERE ApplicantID IN (SELECT ApplicantID FROM dbo.Applications WHERE Status = 'Rejected')
ORDER BY ApplicantID;
-- TRAP: a JOIN to Applications returns one row PER rejected application, so COUNT(*) over a join counts
--       applications, not applicants. IN (or EXISTS) counts each applicant once.
*/


/* ----------------------------------------------------------------------------
   Q3 (easy-medium) - Unused programmes
   Which programmes have never been used by any application? Write it with NOT EXISTS,
   then try NOT IN as well and explain why the two differ.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q3
SELECT p.ProgrammeID, p.ProgrammeName
FROM dbo.Programmes AS p
WHERE NOT EXISTS (SELECT 1 FROM dbo.Applications a WHERE a.ProgrammeID = p.ProgrammeID);

-- The NOT IN version returns ZERO rows:
SELECT p.ProgrammeID, p.ProgrammeName
FROM dbo.Programmes AS p
WHERE p.ProgrammeID NOT IN (SELECT a.ProgrammeID FROM dbo.Applications a);

-- Fixed NOT IN:
SELECT p.ProgrammeID, p.ProgrammeName
FROM dbo.Programmes AS p
WHERE p.ProgrammeID NOT IN (SELECT a.ProgrammeID FROM dbo.Applications a WHERE a.ProgrammeID IS NOT NULL);
-- TRAP: Applications.ProgrammeID contains NULLs, and x NOT IN (..., NULL) is never TRUE, so NOT IN finds
--       nothing. Expected answer: Community Housing Fund.
*/


/* ----------------------------------------------------------------------------
   Q4 (medium) - Two financial years side by side
   Using a derived table (subquery in FROM), show for FY 2023/24 and FY 2024/25: the number of
   applications that have funding lines, total homes funded and total net funding.
   Applications dated 2026 or later are future-dated errors and must not appear.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q4
SELECT x.FinYear,
       COUNT(DISTINCT x.ApplicationID) AS Applications,
       SUM(x.Homes)                    AS HomesFunded,
       SUM(x.Net)                      AS NetFunding
FROM (SELECT a.ApplicationID, f.Homes,
             f.Homes * f.GrantPerHome * (1 - f.ClawbackRate) AS Net,
             CASE WHEN a.ApplicationDate >= '2023-04-01' AND a.ApplicationDate < '2024-04-01' THEN '2023/24'
                  WHEN a.ApplicationDate >= '2024-04-01' AND a.ApplicationDate < '2025-04-01' THEN '2024/25'
             END AS FinYear
      FROM dbo.Applications AS a
      JOIN dbo.FundingLines  AS f ON f.ApplicationID = a.ApplicationID) AS x
WHERE x.FinYear IS NOT NULL
GROUP BY x.FinYear
ORDER BY x.FinYear;
-- TRAP: BETWEEN '2024-04-01' AND '2025-03-31' on a DATETIME2 column drops everything on 31 March after
--       00:00:00 (incl. the 23:59:59 rows). Use  >= start AND < next-day-after-end. The ranges also
--       exclude the future-dated 2026-27 applications for free.
*/


/* ----------------------------------------------------------------------------
   Q5 (medium) - Best-paid in every office
   HR wants the highest-paid person (or people!) in each office: Office, name, JobTitle, Salary.
   Use a correlated subquery.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q5
SELECT s.Office, s.FirstName, s.LastName, s.JobTitle, s.Salary
FROM dbo.Staff AS s
WHERE s.Salary = (SELECT MAX(x.Salary) FROM dbo.Staff AS x WHERE x.Office = s.Office)
ORDER BY s.Office, s.LastName;
-- TRAP: salaries are tied in this dataset, so an office can have two top earners. TOP (1) ... per office
--       (or ROW_NUMBER) would silently hide one of them. "= MAX" keeps all of them.
*/


/* ----------------------------------------------------------------------------
   Q6 (medium) - Possible duplicate applicants with a completion
   The data team suspects duplicate registrations. List applicants (ApplicantID, name, City, RegisteredDate) who
   (a) share their full name with at least one OTHER applicant, ignoring case and stray spaces, and
   (b) have at least one Completed application. Use EXISTS for both tests; first 20 rows.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q6
SELECT TOP (20) ap.ApplicantID, TRIM(ap.FirstName) AS FirstName, TRIM(ap.LastName) AS LastName, ap.City, ap.RegisteredDate
FROM dbo.Applicants AS ap
WHERE EXISTS (SELECT 1 FROM dbo.Applicants AS o
              WHERE o.ApplicantID <> ap.ApplicantID
                AND UPPER(TRIM(o.FirstName)) = UPPER(TRIM(ap.FirstName))
                AND UPPER(TRIM(o.LastName))  = UPPER(TRIM(ap.LastName)))
  AND EXISTS (SELECT 1 FROM dbo.Applications AS a
              WHERE a.ApplicantID = ap.ApplicantID AND a.Status = 'Completed')
ORDER BY TRIM(ap.LastName), TRIM(ap.FirstName), ap.ApplicantID;
-- TRAP: names carry stray spaces and mixed case, so TRIM/UPPER is the safe habit and TRIM also keeps
--       the displayed names clean. (In this dataset a plain = happens to find the same 482 applicants, because
--       the default collation ignores case and trailing spaces - do not rely on that.) A shared name is only a
--       CANDIDATE duplicate: different cities = probably different people.
*/


/* ----------------------------------------------------------------------------
   Q7 (medium-hard) - Cap the Affordable Rent grant (UPDATE ... JOIN ... OUTPUT)
   Policy proposes capping the grant per home at 60,000 for sites whose tenure is exactly 'Affordable Rent'
   (not 'London Affordable Rent'). Inside a transaction: apply the cap only to sites above 60,000, show
   SiteID, old grant and new grant with OUTPUT, report how many sites changed, then ROLL BACK.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q7
BEGIN TRAN;
    DECLARE @Changed TABLE (SiteID INT, OldGrant DECIMAL(10,2), NewGrant DECIMAL(10,2));

    UPDATE s
    SET s.UnitPrice = 60000.00
    OUTPUT inserted.SiteID, deleted.UnitPrice, inserted.UnitPrice INTO @Changed
    FROM dbo.Sites AS s
    JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID
    WHERE t.TenureName = N'Affordable Rent' AND s.UnitPrice > 60000.00;

    SELECT COUNT(*) AS SitesCapped, MAX(OldGrant) AS HighestOldGrant, MAX(NewGrant) AS HighestNewGrant FROM @Changed;
    SELECT TOP (10) * FROM @Changed ORDER BY OldGrant DESC;
ROLLBACK TRAN;
-- TRAP: filtering with LIKE '%Affordable Rent%' would also catch 'London Affordable Rent'; sites with a NULL
--       TenureTypeID never match the INNER JOIN (correctly, here). Always ROLLBACK on the shared database.
*/


/* ----------------------------------------------------------------------------
   Q8 (hard) - Remove future-dated applications
   About 20 applications are dated 2026 or later (data-entry errors). Inside a transaction: delete their
   funding lines first, then the applications, capturing how many of each were removed; show both counts and
   the total number of applications afterwards; ROLL BACK. Explain what error you would get if you deleted
   the applications first (for those that have lines).
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q8
BEGIN TRAN;
    DECLARE @Lines INT, @Apps INT;

    DELETE f
    FROM dbo.FundingLines AS f
    JOIN dbo.Applications AS a ON a.ApplicationID = f.ApplicationID
    WHERE a.ApplicationDate >= '2026-01-01';
    SET @Lines = @@ROWCOUNT;

    DELETE FROM dbo.Applications WHERE ApplicationDate >= '2026-01-01';
    SET @Apps = @@ROWCOUNT;

    SELECT @Lines AS FundingLinesDeleted, @Apps AS ApplicationsDeleted,
           (SELECT COUNT(*) FROM dbo.Applications) AS ApplicationsRemaining;
ROLLBACK TRAN;
SELECT COUNT(*) AS ApplicationsAfterRollback FROM dbo.Applications;    -- original total is back
-- TRAP: @@ROWCOUNT is overwritten by the very next statement - copy it into a variable immediately.
--       Parent-first deletes fail with error 547 (FOREIGN KEY constraint FK_..._Applications) for applications that
--       have funding lines; children go first.
*/


/* ----------------------------------------------------------------------------
   Q9 (hard) - Design a safe scratch table
   Create dbo.Scratch_Q9 for tracking scheme reviews: ReviewID identity primary key; SchemeName NVARCHAR(100) NOT NULL;
   Homes INT NOT NULL with a CHECK (>= 0); ClawbackRate DECIMAL(4,2) NULL with a CHECK between 0 and 1; Status with
   DEFAULT 'Planned'. Then (inside TRY...CATCH, one per case) prove that negative Homes is rejected, ClawbackRate of 1.5 is
   rejected, but ClawbackRate = NULL is ACCEPTED. Finally drop the table.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q9
DROP TABLE IF EXISTS dbo.Scratch_Q9;
CREATE TABLE dbo.Scratch_Q9 (
    ReviewID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ScratchQ9 PRIMARY KEY,
    SchemeName   NVARCHAR(100) NOT NULL,
    Homes        INT           NOT NULL CONSTRAINT CK_ScratchQ9_Homes CHECK (Homes >= 0),
    ClawbackRate DECIMAL(4,2)  NULL     CONSTRAINT CK_ScratchQ9_Clawback CHECK (ClawbackRate BETWEEN 0 AND 1),
    Status       NVARCHAR(20)  NOT NULL CONSTRAINT DF_ScratchQ9_Status DEFAULT (N'Planned')
);

BEGIN TRY
    INSERT INTO dbo.Scratch_Q9 (SchemeName, Homes) VALUES (N'Negative homes', -5);
END TRY
BEGIN CATCH
    SELECT 'Homes check' AS Test, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

BEGIN TRY
    INSERT INTO dbo.Scratch_Q9 (SchemeName, Homes, ClawbackRate) VALUES (N'150 percent clawback', 10, 1.50);
END TRY
BEGIN CATCH
    SELECT 'Clawback check' AS Test, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

INSERT INTO dbo.Scratch_Q9 (SchemeName, Homes, ClawbackRate) VALUES (N'Unknown clawback', 10, NULL);
SELECT * FROM dbo.Scratch_Q9;          -- the NULL clawback row got in, Status = 'Planned' by default

DROP TABLE dbo.Scratch_Q9;
-- TRAP: CHECK rejects only FALSE, not UNKNOWN. NULL >= 0 is UNKNOWN, so a nullable column passes the check.
--       If a value is mandatory, add NOT NULL as well. Also: IDENTITY values used by failed inserts are lost (gaps).
*/


/* ----------------------------------------------------------------------------
   Q10 (hardest) - Over-performing sites within their tenure
   Which sites have a total net funding ABOVE the average site net funding of their own tenure type? Stage per-site
   net funding in a #temp table (SELECT INTO), then use a correlated subquery. Show TenureTypeID, SiteName,
   NetFunding, and the tenure average. Sites with no tenure (NULL TenureTypeID) should be compared with each
   other as one group, not silently dropped. Top 15 by NetFunding.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q10
DROP TABLE IF EXISTS #SiteNet;
SELECT s.SiteID, s.SiteName, s.TenureTypeID,
       SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate)) AS NetFunding
INTO #SiteNet
FROM dbo.Sites AS s
JOIN dbo.FundingLines AS f ON f.SiteID = s.SiteID
GROUP BY s.SiteID, s.SiteName, s.TenureTypeID;

SELECT TOP (15) n.TenureTypeID, n.SiteName, n.NetFunding,
       (SELECT AVG(x.NetFunding) FROM #SiteNet AS x
        WHERE x.TenureTypeID = n.TenureTypeID
           OR (x.TenureTypeID IS NULL AND n.TenureTypeID IS NULL)) AS TenureAverage
FROM #SiteNet AS n
WHERE n.NetFunding > (SELECT AVG(x.NetFunding) FROM #SiteNet AS x
                      WHERE x.TenureTypeID = n.TenureTypeID
                         OR (x.TenureTypeID IS NULL AND n.TenureTypeID IS NULL))
ORDER BY n.NetFunding DESC, n.SiteID;

DROP TABLE #SiteNet;
-- TRAP: x.TenureTypeID = n.TenureTypeID is never true for NULL, so the ~5 no-tenure sites would get an
--       average of NULL and disappear. Also, never-funded sites are not in #SiteNet at all (INNER JOIN) -
--       they cannot be "above average", and including them as 0 would drag every average down.
*/


/* ============================================================================
   END OF PRACTICE 07-08
   ============================================================================ */
