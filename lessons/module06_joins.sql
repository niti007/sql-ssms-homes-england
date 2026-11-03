USE HousingDelivery;
GO
/* ============================================================================
   MODULE 06 - JOINS AND SET OPERATORS
   Database : HousingDelivery (see SPEC.md)      Target : SQL Server 2019+ / SSMS
   NetFunding  : Homes * GrantPerHome * (1 - ClawbackRate)

   Run one example at a time (highlight + F5). Lines starting with -- ERROR:
   fail on purpose; they are commented out.

   CONCEPTS
     A. INNER JOIN
     B. LEFT, RIGHT and FULL OUTER JOIN
     C. Finding unmatched rows (anti-joins)
     D. CROSS JOIN
     E. Self join (Staff -> Manager)
     F. Multi-table joins (Applications -> FundingLines -> Sites -> TenureTypes)
     G. The join row-multiplication trap
     H. UNION vs UNION ALL (and INTERSECT / EXCEPT)

   MENTAL MODEL: a join glues two tables side by side by matching a key.
   Think of two lists on a desk: INNER keeps only pairs that match;
   LEFT keeps everything from the left list, even without a partner;
   FULL keeps everything from both.
   ============================================================================ */


/* ############################################################################
   CONCEPT A : INNER JOIN
   ############################################################################
   INNER JOIN returns only rows with a match on BOTH sides. Rows without a
   partner disappear silently - the most common source of "missing" data.
   Always give tables short ALIASES (o, c, d ...) and qualify every column.
   ########################################################################## */

-- A.1  Applications with their applicant name
SELECT TOP (10) a.ApplicationID, a.ApplicationDate, ap.FirstName, ap.LastName
FROM dbo.Applications AS a
INNER JOIN dbo.Applicants AS ap ON ap.ApplicantID = a.ApplicantID
ORDER BY a.ApplicationID;

-- A.2  INNER is the default; JOIN alone means INNER JOIN
SELECT TOP (10) a.ApplicationID, ap.City
FROM dbo.Applications AS a
JOIN dbo.Applicants AS ap ON ap.ApplicantID = a.ApplicantID
ORDER BY a.ApplicationID;

-- A.3  Sites with their partner
SELECT TOP (10) s.SiteName, s.UnitPrice, pr.PartnerName, pr.Region
FROM dbo.Sites AS s
JOIN dbo.Partners AS pr ON pr.PartnerID = s.PartnerID
ORDER BY s.SiteID;

-- A.4  Sites with tenure: note how many rows survive
SELECT COUNT(*) AS SitesTotal FROM dbo.Sites;
SELECT COUNT(*) AS SitesWithTenure
FROM dbo.Sites AS s
JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID;       -- ~5 fewer: NULL TenureTypeID can't match

-- A.5  Filter after joining
SELECT TOP (10) a.ApplicationID, a.Status, ap.HouseholdType
FROM dbo.Applications AS a
JOIN dbo.Applicants AS ap ON ap.ApplicantID = a.ApplicantID
WHERE ap.HouseholdType = 'Key worker' AND a.Status = 'Completed'
ORDER BY a.ApplicationID;

-- A.6  Aggregate after joining: applications per applicant
SELECT TOP (10) ap.ApplicantID, ap.FirstName, ap.LastName, COUNT(*) AS Applications
FROM dbo.Applicants AS ap
JOIN dbo.Applications AS a ON a.ApplicantID = ap.ApplicantID
GROUP BY ap.ApplicantID, ap.FirstName, ap.LastName
ORDER BY Applications DESC, ap.ApplicantID;

-- A.7  Application lines with site names
SELECT TOP (10) fl.ApplicationID, s.SiteName, fl.Homes, fl.GrantPerHome, fl.ClawbackRate
FROM dbo.FundingLines AS fl
JOIN dbo.Sites AS s ON s.SiteID = fl.SiteID
ORDER BY fl.FundingLineID;

-- A.8  Grant per home on the funding line vs the site's current average (they can differ!)
SELECT TOP (10) fl.FundingLineID, s.SiteName,
       fl.GrantPerHome AS GrantWhenFunded, s.UnitPrice AS GrantNow
FROM dbo.FundingLines AS fl
JOIN dbo.Sites AS s ON s.SiteID = fl.SiteID
WHERE fl.GrantPerHome <> s.UnitPrice
ORDER BY fl.FundingLineID;

-- A.9  Join on two columns (composite) - pattern shown with a pretend key
SELECT TOP (5) a.ApplicationID, a.PropertyCity, ap.City
FROM dbo.Applications AS a
JOIN dbo.Applicants AS ap ON ap.ApplicantID = a.ApplicantID AND ap.City = a.PropertyCity   -- property in the applicant's home city
ORDER BY a.ApplicationID;

-- A.10 Applications with their programme (INNER drops applications with NULL ProgrammeID)
SELECT COUNT(*) AS ApplicationsTotal FROM dbo.Applications;
SELECT COUNT(*) AS ApplicationsWithProgramme
FROM dbo.Applications AS a JOIN dbo.Programmes AS pg ON pg.ProgrammeID = a.ProgrammeID;

-- A.11 Applications with their staff member (INNER drops online self-service applications: StaffID NULL)
SELECT COUNT(*) AS StaffApplications
FROM dbo.Applications AS a JOIN dbo.Staff AS st ON st.StaffID = a.StaffID;

-- A.12 Old-style comma join (you will meet it in legacy code - do not write it)
SELECT TOP (5) a.ApplicationID, ap.LastName
FROM dbo.Applications AS a, dbo.Applicants ap
WHERE a.ApplicantID = ap.ApplicantID
ORDER BY a.ApplicationID;

-- A.13 Forgetting the ON clause
-- ERROR: SELECT * FROM dbo.Applications AS a JOIN dbo.Applicants AS ap;     -- "Incorrect syntax near ';'"

-- A.14 Ambiguous column
-- ERROR: SELECT ApplicationID, ApplicantID FROM dbo.Applications AS a JOIN dbo.Applicants AS ap ON ap.ApplicantID = a.ApplicantID;
--        "Ambiguous column name 'ApplicantID'" -> write a.ApplicantID

/* ---- Common mistakes (A) ---------------------------------------------------
   1. Joining on the wrong columns (e.g. ApplicationID = ApplicantID) - runs, but junk.
   2. Forgetting a join condition (becomes a CROSS JOIN, see Concept D).
   3. Not noticing INNER JOIN dropped rows (NULL keys, no children).
   4. Un-qualified column names that exist in both tables.
   5. Using SELECT * on joins: duplicate column names (ApplicantID twice).
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (A) ------------------------------------------------
   Table L has IDs 1,2,3. Table R has IDs 2,3,4.  L INNER JOIN R ON L.ID = R.ID
   Q1. Which IDs come out?     Answer: 2 and 3.
   Q2. 60,000 applications, each with exactly one applicant; how many rows does
       Applications JOIN Applicants return? Answer: 60,000 (applicant is unique per application).
   ---------------------------------------------------------------------------- */

/* ---- Try it (A) ------------------------------------------------------------
   List 15 sites with tenure name and partner region, only for sites
   with a grant per home above 50000. Then explain which sites are NOT in your list because
   of the INNER JOIN, not the grant filter.
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT B : LEFT, RIGHT, FULL OUTER JOIN
   ############################################################################
   LEFT JOIN  : all rows from the LEFT table + matches (NULLs where no match).
   RIGHT JOIN : mirror image. (Rarely needed: swap table application and use LEFT.)
   FULL JOIN  : all rows from BOTH; NULLs on whichever side lacks a partner.
   ########################################################################## */

-- B.1  TenureTypes with site counts: LEFT keeps the empty tenure
SELECT t.TenureTypeID, t.TenureName, COUNT(s.SiteID) AS Sites
FROM dbo.TenureTypes AS t
LEFT JOIN dbo.Sites AS s ON s.TenureTypeID = t.TenureTypeID
GROUP BY t.TenureTypeID, t.TenureName
ORDER BY Sites, t.TenureTypeID;               -- one tenure shows 0

-- B.2  Same query as INNER: the empty tenure vanishes
SELECT t.TenureTypeID, t.TenureName, COUNT(s.SiteID) AS Sites
FROM dbo.TenureTypes AS t
JOIN dbo.Sites AS s ON s.TenureTypeID = t.TenureTypeID
GROUP BY t.TenureTypeID, t.TenureName
ORDER BY Sites;

-- B.3  COUNT(*) vs COUNT(right_column) in a LEFT JOIN
SELECT t.TenureName,
       COUNT(*)           AS WrongCount,     -- counts the NULL-padded row as 1
       COUNT(s.SiteID) AS RightCount      -- 0 for the empty tenure
FROM dbo.TenureTypes AS t
LEFT JOIN dbo.Sites AS s ON s.TenureTypeID = t.TenureTypeID
GROUP BY t.TenureName
ORDER BY RightCount;

-- B.4  Sites with tenure name, keeping the no-tenure ones
SELECT TOP (10) s.SiteID, s.SiteName, ISNULL(t.TenureName, '(no tenure)') AS Tenure
FROM dbo.Sites AS s
LEFT JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID
ORDER BY CASE WHEN t.TenureName IS NULL THEN 0 ELSE 1 END, s.SiteID;

-- B.5  Applications with staff member: LEFT keeps online applications
SELECT TOP (10) a.ApplicationID, a.StaffID,
       ISNULL(st.FirstName + ' ' + st.LastName, 'ONLINE') AS TakenBy
FROM dbo.Applications AS a
LEFT JOIN dbo.Staff AS st ON st.StaffID = a.StaffID
ORDER BY a.ApplicationID;

-- B.6  Applications per programme including the unused programme
SELECT pg.ProgrammeID, pg.ProgrammeName, COUNT(a.ApplicationID) AS Applications
FROM dbo.Programmes AS pg
LEFT JOIN dbo.Applications AS a ON a.ProgrammeID = pg.ProgrammeID
GROUP BY pg.ProgrammeID, pg.ProgrammeName
ORDER BY Applications;                               -- one programme = 0

-- B.7  The same with RIGHT JOIN (identical result, tables swapped)
SELECT pg.ProgrammeID, pg.ProgrammeName, COUNT(a.ApplicationID) AS Applications
FROM dbo.Applications AS a
RIGHT JOIN dbo.Programmes AS pg ON pg.ProgrammeID = a.ProgrammeID
GROUP BY pg.ProgrammeID, pg.ProgrammeName
ORDER BY Applications;

-- B.8  FULL OUTER JOIN: see both kinds of orphans at once
SELECT s.SiteID, s.SiteName, t.TenureTypeID, t.TenureName
FROM dbo.Sites AS s
FULL OUTER JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID
WHERE s.SiteID IS NULL OR t.TenureTypeID IS NULL;   -- empty tenure + no-tenure sites

-- B.9  Applicants and their application count (0 for the ~300 who never applied)
SELECT TOP (10) ap.ApplicantID, ap.LastName, COUNT(a.ApplicationID) AS Applications
FROM dbo.Applicants AS ap
LEFT JOIN dbo.Applications AS a ON a.ApplicantID = ap.ApplicantID
GROUP BY ap.ApplicantID, ap.LastName
ORDER BY Applications, ap.ApplicantID;

-- B.10 Applications with their line count (0 for applications without details)
SELECT TOP (10) a.ApplicationID, COUNT(fl.FundingLineID) AS Lines
FROM dbo.Applications AS a
LEFT JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
GROUP BY a.ApplicationID
ORDER BY Lines, a.ApplicationID;

-- B.11 THE LEFT JOIN TRAP: a WHERE on the right table kills the outer rows
SELECT COUNT(*) AS ApplicantsLeft_Wrong
FROM dbo.Applicants AS ap
LEFT JOIN dbo.Applications AS a ON a.ApplicantID = ap.ApplicantID
WHERE a.Status = 'Completed';         -- NULL rows fail this test -> acts like INNER JOIN

-- B.12 Fix: put the right-table condition in ON
SELECT COUNT(DISTINCT ap.ApplicantID) AS Applicants_Kept,
       COUNT(a.ApplicationID)             AS CompletedApplications
FROM dbo.Applicants AS ap
LEFT JOIN dbo.Applications AS a ON a.ApplicantID = ap.ApplicantID AND a.Status = 'Completed';

-- B.13 NetFunding per applicant, zero for applicants with no applications (LEFT chain)
SELECT TOP (10) ap.ApplicantID,
       ISNULL(SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate)), 0) AS NetFunding
FROM dbo.Applicants AS ap
LEFT JOIN dbo.Applications AS a       ON a.ApplicantID = ap.ApplicantID
LEFT JOIN dbo.FundingLines AS fl ON fl.ApplicationID    = a.ApplicationID
GROUP BY ap.ApplicantID
ORDER BY NetFunding, ap.ApplicantID;

-- B.14 Join type cheat sheet via counts
SELECT (SELECT COUNT(*) FROM dbo.Applicants AS ap JOIN dbo.Applications AS a ON a.ApplicantID = ap.ApplicantID)       AS InnerRows,
       (SELECT COUNT(*) FROM dbo.Applicants AS ap LEFT JOIN dbo.Applications AS a ON a.ApplicantID = ap.ApplicantID)  AS LeftRows,
       (SELECT COUNT(*) FROM dbo.Applicants AS ap FULL JOIN dbo.Applications AS a ON a.ApplicantID = ap.ApplicantID)  AS FullRows;
-- Left - Inner = number of applicants without applications. Full = Left (every application has a applicant).

/* ---- Common mistakes (B) ---------------------------------------------------
   1. WHERE on the right table after LEFT JOIN (B.11). Use ON, or test for NULL.
   2. COUNT(*) instead of COUNT(right_key) (B.3).
   3. Choosing RIGHT JOIN then mentally flipping tables: use LEFT consistently.
   4. Chaining INNER after LEFT: the later INNER JOIN re-removes the NULL rows.
   5. Confusing which side is "left": it is the table written BEFORE the JOIN keyword.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (B) ------------------------------------------------
   L = {1,2,3}, R = {2,3,4}.
   Q1. L LEFT JOIN R: how many rows, and which have NULL on the R side? (3 ; ID 1)
   Q2. L FULL JOIN R: how many rows? (4 : 1,2,3,4)
   Q3. L RIGHT JOIN R: which row has NULL on the L side? (ID 4)
   ---------------------------------------------------------------------------- */

/* ---- Try it (B) ------------------------------------------------------------
   Show every tenure with its number of sites AND its average grant per home
   (NULL average for the empty tenure should display as 0).
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT C : FINDING UNMATCHED ROWS (ANTI-JOINS)
   ############################################################################
   Business questions with "no" in them: applicants with NO applications, sites NEVER
   applied, applications with NO details. Pattern:
       FROM parent LEFT JOIN child ON ... WHERE child.key IS NULL
   Alternatives: NOT EXISTS (best), NOT IN (dangerous with NULLs).
   ########################################################################## */

-- C.1  Applicants who never applied (~300)
SELECT ap.ApplicantID, ap.FirstName, ap.LastName
FROM dbo.Applicants AS ap
LEFT JOIN dbo.Applications AS a ON a.ApplicantID = ap.ApplicantID
WHERE a.ApplicationID IS NULL
ORDER BY ap.ApplicantID;

-- C.2  Count them
SELECT COUNT(*) AS NeverApplied
FROM dbo.Applicants AS ap
LEFT JOIN dbo.Applications AS a ON a.ApplicantID = ap.ApplicantID
WHERE a.ApplicationID IS NULL;

-- C.3  Sites never funded (~40) with tenure
SELECT s.SiteID, s.SiteName, s.UnitPrice, ISNULL(t.TenureName, '(none)') AS Tenure
FROM dbo.Sites AS s
LEFT JOIN dbo.FundingLines AS fl ON fl.SiteID = s.SiteID
LEFT JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID
WHERE fl.FundingLineID IS NULL
ORDER BY s.SiteID;

-- C.4  Applications without any line items
SELECT a.ApplicationID, a.ApplicationDate, a.Status, a.ApplicantID
FROM dbo.Applications AS a
LEFT JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
WHERE fl.FundingLineID IS NULL
ORDER BY a.ApplicationID;

-- C.5  Same question with NOT EXISTS (usually the clearest)
SELECT a.ApplicationID
FROM dbo.Applications AS a
WHERE NOT EXISTS (SELECT 1 FROM dbo.FundingLines AS fl WHERE fl.ApplicationID = a.ApplicationID);

-- C.6  And with NOT IN - fine here because ApplicationID is never NULL
SELECT a.ApplicationID
FROM dbo.Applications AS a
WHERE a.ApplicationID NOT IN (SELECT fl.ApplicationID FROM dbo.FundingLines AS fl);

-- C.7  The NOT IN trap: one NULL in the list makes the result EMPTY
SELECT COUNT(*) AS TrapResult
FROM dbo.Applicants
WHERE ApplicantID NOT IN (SELECT 1 UNION ALL SELECT NULL);   -- returns 0 rows counted
-- 'x NOT IN (1, NULL)' is UNKNOWN for every x. NOT EXISTS has no such problem.

-- C.8  Staff who never took an application
SELECT st.StaffID, st.FirstName, st.LastName, st.JobTitle
FROM dbo.Staff AS st
LEFT JOIN dbo.Applications AS a ON a.StaffID = st.StaffID
WHERE a.ApplicationID IS NULL
ORDER BY st.StaffID;

-- C.9  Partners with no STALLED sites (the extra condition belongs in ON, not WHERE)
-- (Every partner has at least one site, so "partners with no sites at all" would return 0 rows.)
SELECT pr.PartnerID, pr.PartnerName
FROM dbo.Partners AS pr
LEFT JOIN dbo.Sites AS s ON s.PartnerID = pr.PartnerID AND s.IsStalled = 1
WHERE s.SiteID IS NULL;

-- C.10 Programme never used
SELECT pg.ProgrammeID, pg.ProgrammeName
FROM dbo.Programmes AS pg
LEFT JOIN dbo.Applications AS a ON a.ProgrammeID = pg.ProgrammeID
WHERE a.ApplicationID IS NULL;

-- C.11 Applicants who applied but never received anything (no Completed application)
SELECT ap.ApplicantID, ap.LastName
FROM dbo.Applicants AS ap
WHERE EXISTS (SELECT 1 FROM dbo.Applications AS a WHERE a.ApplicantID = ap.ApplicantID)
  AND NOT EXISTS (SELECT 1 FROM dbo.Applications AS a
                  WHERE a.ApplicantID = ap.ApplicantID AND a.Status = 'Completed');

-- C.12 Active applicants with no applications: a marketing list
SELECT ap.ApplicantID, ap.FirstName, ap.LastName, NULLIF(TRIM(ap.Email), '') AS Email
FROM dbo.Applicants AS ap
LEFT JOIN dbo.Applications AS a ON a.ApplicantID = ap.ApplicantID
WHERE a.ApplicationID IS NULL AND ap.IsActive = 1
  AND NULLIF(TRIM(ap.Email), '') IS NOT NULL;         -- skip NULL and '' emails

-- C.13 Percent of sites that were never funded
SELECT CAST(100.0 * SUM(CASE WHEN sf.FundingLineID IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS PctNeverFunded
FROM (SELECT s.SiteID, MIN(fl.FundingLineID) AS FundingLineID
      FROM dbo.Sites AS s LEFT JOIN dbo.FundingLines AS fl ON fl.SiteID = s.SiteID
      GROUP BY s.SiteID) AS sf;

/* ---- Common mistakes (C) ---------------------------------------------------
   1. Testing IS NULL on a column that can be NULL in the matched data too
      (use the child's PRIMARY KEY, e.g. ApplicationID / FundingLineID).
   2. Using INNER JOIN and wondering why no unmatched rows appear.
   3. NOT IN with a subquery that can return NULL (C.7).
   4. Putting the child filter in WHERE instead of ON (turns the anti-join wrong).
   5. Forgetting DISTINCT/aggregation when the join multiplies rows.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (C) ------------------------------------------------
   Q1. 10,000 applicants; 9,700 appear in Applications. How many rows does the anti-join
       (LEFT JOIN ... IS NULL) return?   Answer: 300.
   Q2. An applicant has 20 applications and one of them has no details. Does that
       applicant appear in C.4?  Not as an applicant - the APPLICATION does.
   ---------------------------------------------------------------------------- */

/* ---- Try it (C) ------------------------------------------------------------
   List stalled sites that were never funded AND still have homes planned. Show
   PlannedHomes and planned grant value (UnitPrice * PlannedHomes).
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT D : CROSS JOIN
   ############################################################################
   CROSS JOIN pairs EVERY row of A with EVERY row of B (A x B rows). No ON.
   Useful for building grids/calendars; dangerous if done by accident on big tables.
   ########################################################################## */

-- D.1  Tiny example
SELECT pg.ProgrammeName, ht.HouseholdType
FROM dbo.Programmes AS pg
CROSS JOIN (SELECT DISTINCT HouseholdType FROM dbo.Applicants) AS ht
ORDER BY pg.ProgrammeName, ht.HouseholdType;       -- 5 x 3 = 15 rows

-- D.2  Row count = site of counts
SELECT (SELECT COUNT(*) FROM dbo.Programmes)   AS Programmes,
       (SELECT COUNT(*) FROM dbo.TenureTypes) AS TenureTypes,
       (SELECT COUNT(*) FROM dbo.Programmes) * (SELECT COUNT(*) FROM dbo.TenureTypes) AS CrossRows;

-- D.3  Every year x every status = a complete grid
SELECT y.Yr, s.Status
FROM (VALUES (2022), (2023), (2024), (2025)) AS y(Yr)
CROSS JOIN (VALUES ('Submitted'), ('Approved'), ('Completed'), ('Withdrawn'), ('Rejected')) AS s(Status)
ORDER BY y.Yr, s.Status;

-- D.4  Use the grid to show ZERO rows: applications per year/status, gaps filled
SELECT g.Yr, g.Status, COUNT(a.ApplicationID) AS Applications
FROM (SELECT y.Yr, s.Status
      FROM (VALUES (2022), (2023), (2024), (2025)) AS y(Yr)
      CROSS JOIN (VALUES ('Submitted'), ('Approved'), ('Completed'), ('Withdrawn'), ('Rejected')) AS s(Status)) AS g
LEFT JOIN dbo.Applications AS a
       ON YEAR(a.ApplicationDate) = g.Yr AND a.Status = g.Status
GROUP BY g.Yr, g.Status
ORDER BY g.Yr, g.Status;

-- D.5  Calendar of 2024 months x household types (12 x 3 = 36 rows)
SELECT m.Mo, seg.HouseholdType
FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) AS m(Mo)
CROSS JOIN (VALUES ('First-time buyer'),('Key worker'),('Home mover')) AS seg(HouseholdType)
ORDER BY m.Mo, seg.HouseholdType;

-- D.6  Old comma syntax without WHERE = accidental CROSS JOIN
SELECT COUNT(*) AS AccidentRows
FROM dbo.Programmes pg, dbo.TenureTypes t;     -- 5 x 12 = 60

-- D.7  Warning: CROSS JOIN on big tables
-- DO NOT RUN: SELECT COUNT(*) FROM dbo.Applicants CROSS JOIN dbo.Applications;   -- 600,000,000 rows

-- D.8  Compare every site's grant per home with the average across all sites
SELECT TOP (5) s.SiteName, s.UnitPrice, a.AvgGrant, s.UnitPrice - a.AvgGrant AS Diff
FROM dbo.Sites AS s
CROSS JOIN (SELECT AVG(UnitPrice) AS AvgGrant FROM dbo.Sites) AS a    -- one row: safe
ORDER BY s.SiteID;

-- D.9  Generate a number list 1..100 (cross join of small sets)
SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
FROM dbo.TenureTypes a CROSS JOIN dbo.Programmes b CROSS JOIN dbo.Programmes c;   -- 12*5*5 = 300 rows available

-- D.10 Matching pairs of partners in the same region (join with a condition, not cross)
SELECT TOP (10) a.PartnerName AS PartnerA, b.PartnerName AS PartnerB, a.Region
FROM dbo.Partners a
JOIN dbo.Partners b ON b.Region = a.Region AND a.PartnerID < b.PartnerID    -- < avoids A-A and B-A duplicates
ORDER BY a.Region, a.PartnerID, b.PartnerID;

/* ---- Common mistakes (D) ---------------------------------------------------
   1. Forgetting the join condition so a normal join explodes into a cross join.
   2. CROSS JOIN on large tables (D.7).
   3. Expecting a WHERE to make it cheap: the pairs are still generated logically.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (D) ------------------------------------------------
   Q1. A has 4 rows, B has 6 rows, CROSS JOIN rows?  24
   Q2. A has 0 rows, B has 6?   0
   Q3. In D.10 with 40 partners, why a.PartnerID < b.PartnerID?
       To get each pair once, and never a partner paired with itself.
   ---------------------------------------------------------------------------- */

/* ---- Try it (D) ------------------------------------------------------------
   Build a grid of all HouseholdTypes x all Statuses and show the number of applications in
   each cell (0 where none), via Applicants and Applications.
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT E : SELF JOIN (EMPLOYEES -> MANAGER)
   ############################################################################
   A self join joins a table to ITSELF using two aliases. Staff has
   ManagerID, which points at another row's StaffID. Treat it like two
   copies of the table: e (the staff member) and m (the manager).
   The CEO has ManagerID NULL -> needs a LEFT JOIN or he disappears.
   ########################################################################## */

-- E.1  staff member and manager names
SELECT st.StaffID, st.FirstName + ' ' + st.LastName AS StaffMember,
       mgr.FirstName + ' ' + mgr.LastName AS Manager
FROM dbo.Staff AS st
JOIN dbo.Staff AS mgr ON mgr.StaffID = st.ManagerID
ORDER BY st.StaffID;                 -- 59 rows: the CEO is missing

-- E.2  LEFT JOIN keeps the CEO
SELECT st.StaffID, st.FirstName + ' ' + st.LastName AS StaffMember, st.JobTitle,
       ISNULL(mgr.FirstName + ' ' + mgr.LastName, '(no manager - top of tree)') AS Manager
FROM dbo.Staff AS st
LEFT JOIN dbo.Staff AS mgr ON mgr.StaffID = st.ManagerID
ORDER BY st.StaffID;

-- E.3  Direct reports per manager
SELECT mgr.StaffID, mgr.FirstName + ' ' + mgr.LastName AS Manager, COUNT(st.StaffID) AS DirectReports
FROM dbo.Staff AS mgr
LEFT JOIN dbo.Staff AS st ON st.ManagerID = mgr.StaffID
GROUP BY mgr.StaffID, mgr.FirstName, mgr.LastName
HAVING COUNT(st.StaffID) > 0
ORDER BY DirectReports DESC;

-- E.4  Staff who manage nobody (leaf nodes)
SELECT mgr.StaffID, mgr.FirstName, mgr.LastName, mgr.JobTitle
FROM dbo.Staff AS mgr
LEFT JOIN dbo.Staff AS st ON st.ManagerID = mgr.StaffID
WHERE st.StaffID IS NULL
ORDER BY mgr.StaffID;

-- E.5  Who earns more than their manager? (expected: 0 rows - nobody does; a useful sanity check)
SELECT st.FirstName + ' ' + st.LastName AS StaffMember, st.Salary AS EmpSalary,
       mgr.FirstName + ' ' + mgr.LastName AS Manager,  mgr.Salary AS MgrSalary
FROM dbo.Staff AS st
JOIN dbo.Staff AS mgr ON mgr.StaffID = st.ManagerID
WHERE st.Salary > mgr.Salary;

-- E.6  Two levels up: staff member -> manager -> manager's manager
SELECT st.FirstName + ' ' + st.LastName AS StaffMember,
       mgr.FirstName + ' ' + mgr.LastName AS Manager,
       gm.FirstName + ' ' + gm.LastName AS GrandManager
FROM dbo.Staff AS st
LEFT JOIN dbo.Staff AS mgr ON mgr.StaffID = st.ManagerID
LEFT JOIN dbo.Staff AS gm ON gm.StaffID = mgr.ManagerID
ORDER BY st.StaffID;

-- E.7  Hired before their manager? (a data-quality check)
SELECT st.StaffID, st.HireDate AS EmpHired, mgr.HireDate AS MgrHired
FROM dbo.Staff AS st
JOIN dbo.Staff AS mgr ON mgr.StaffID = st.ManagerID
WHERE st.HireDate < mgr.HireDate;

-- E.8  Colleagues in the same office (pairs, each pair once)
SELECT TOP (10) a.FirstName + ' ' + a.LastName AS PersonA,
                b.FirstName + ' ' + b.LastName AS PersonB, a.Office
FROM dbo.Staff a
JOIN dbo.Staff b ON b.Office = a.Office AND a.StaffID < b.StaffID
ORDER BY a.Office, a.StaffID, b.StaffID;

-- E.9  Average salary of each manager's team vs the manager's own salary
SELECT mgr.FirstName + ' ' + mgr.LastName AS Manager, mgr.Salary AS ManagerSalary,
       AVG(st.Salary) AS AvgTeamSalary, COUNT(*) AS TeamSize
FROM dbo.Staff AS mgr
JOIN dbo.Staff AS st ON st.ManagerID = mgr.StaffID
GROUP BY mgr.StaffID, mgr.FirstName, mgr.LastName, mgr.Salary
ORDER BY TeamSize DESC;

-- E.10 Applications taken by each staff member, with their manager (self join + another table)
SELECT TOP (10) st.FirstName + ' ' + st.LastName AS StaffMember,
       ISNULL(mgr.LastName, '-') AS ManagerLastName,
       COUNT(a.ApplicationID) AS Applications
FROM dbo.Staff AS st
LEFT JOIN dbo.Staff AS mgr ON mgr.StaffID = st.ManagerID
LEFT JOIN dbo.Applications AS a    ON a.StaffID = st.StaffID
GROUP BY st.StaffID, st.FirstName, st.LastName, mgr.LastName
ORDER BY Applications DESC;

/* ---- Common mistakes (E) ---------------------------------------------------
   1. Forgetting aliases: Staff JOIN Staff without aliases is ambiguous.
   2. Using INNER JOIN and losing the CEO (E.1 vs E.2).
   3. Joining st.StaffID = mgr.StaffID (matches self, not the manager).
   4. Reversing the direction: the key is  mgr.StaffID = st.ManagerID.
   5. Self-join pair queries without a < condition: duplicates and A-A pairs.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (E) ------------------------------------------------
   Q1. 60 staff, one has ManagerID NULL. Rows from INNER self join? 59
   Q2. Same with LEFT JOIN from the staff member side? 60
   Q3. E.3 groups by manager: which manager appears with the most reports?
       Probably someone at level 2-3; run it and check.
   ---------------------------------------------------------------------------- */

/* ---- Try it (E) ------------------------------------------------------------
   Show each staff member's Directorate, and flag with 'Cross-dept' if the manager is
   in a different Directorate (use CASE).
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT F : MULTI-TABLE JOINS
   ############################################################################
   Chain joins one after another, each ON linking to something already in the
   query. Path for funding analysis:
       Applications -> FundingLines -> Sites -> TenureTypes
   (and Applicants, Staff, Programmes, Partners hang off these).
   Tip: add ONE table at a time and re-check the row count.
   ########################################################################## */

-- F.1  Build it up step by step - rows after each join
SELECT COUNT(*) AS ApplicationRows       FROM dbo.Applications;
SELECT COUNT(*) AS WithDetails     FROM dbo.Applications AS a JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID;
SELECT COUNT(*) AS WithSites    FROM dbo.Applications AS a JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
                                   JOIN dbo.Sites AS s ON s.SiteID = fl.SiteID;
SELECT COUNT(*) AS WithTenureTypes  FROM dbo.Applications AS a JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
                                   JOIN dbo.Sites AS s ON s.SiteID = fl.SiteID
                                   JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID;   -- drops NULL-tenure sites

-- F.2  Line-level report
SELECT TOP (10) a.ApplicationID, a.ApplicationDate, s.SiteName, t.TenureName, fl.Homes,
       fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate) AS LineNetFunding
FROM dbo.Applications AS a
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
JOIN dbo.Sites AS s     ON s.SiteID = fl.SiteID
JOIN dbo.TenureTypes AS t   ON t.TenureTypeID = s.TenureTypeID
ORDER BY a.ApplicationID, fl.FundingLineID;

-- F.3  NetFunding by tenure
SELECT t.TenureName, SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate)) AS NetFunding
FROM dbo.FundingLines AS fl
JOIN dbo.Sites AS s   ON s.SiteID = fl.SiteID
JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID
GROUP BY t.TenureName
ORDER BY NetFunding DESC;

-- F.4  Keep the no-tenure sites in the net funding report (LEFT JOIN)
SELECT ISNULL(t.TenureName, '(no tenure)') AS Tenure,
       SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate)) AS NetFunding
FROM dbo.FundingLines AS fl
JOIN dbo.Sites AS s        ON s.SiteID = fl.SiteID
LEFT JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID
GROUP BY ISNULL(t.TenureName, '(no tenure)')
ORDER BY NetFunding DESC;

-- F.5  Net funding by site region and tenure (spelling variants cleaned)
SELECT TOP (10)
       REPLACE(TRIM(s.Region), '-', ' ') AS SiteRegion,
       ISNULL(t.TenureName, '(no tenure)') AS Tenure,
       SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate)) AS NetFunding
FROM dbo.FundingLines AS fl
JOIN dbo.Sites AS s            ON s.SiteID = fl.SiteID
LEFT JOIN dbo.TenureTypes t ON t.TenureTypeID = s.TenureTypeID
GROUP BY REPLACE(TRIM(s.Region), '-', ' '), ISNULL(t.TenureName, '(no tenure)')
ORDER BY NetFunding DESC;

-- F.6  Top 10 sites by net funding, with partner and tenure
SELECT TOP (10) s.SiteName, pr.PartnerName, ISNULL(t.TenureName,'-') AS Tenure,
       SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate)) AS NetFunding
FROM dbo.FundingLines AS fl
JOIN dbo.Sites AS s        ON s.SiteID = fl.SiteID
JOIN dbo.Partners AS pr       ON pr.PartnerID = s.PartnerID
LEFT JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID
GROUP BY s.SiteID, s.SiteName, pr.PartnerName, t.TenureName
ORDER BY NetFunding DESC;

-- F.7  NetFunding by programme and year (non-cancelled applications)
SELECT pg.ProgrammeName, YEAR(a.ApplicationDate) AS Yr,
       SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate)) AS NetFunding
FROM dbo.Applications AS a
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
JOIN dbo.Programmes AS pg    ON pg.ProgrammeID = a.ProgrammeID
WHERE a.Status <> 'Withdrawn'
GROUP BY pg.ProgrammeName, YEAR(a.ApplicationDate)
ORDER BY pg.ProgrammeName, Yr;

-- F.8  Case-owner league table (online applications grouped as 'ONLINE')
SELECT TOP (10) ISNULL(st.FirstName + ' ' + st.LastName, 'ONLINE') AS CaseOwner,
       COUNT(DISTINCT a.ApplicationID) AS Applications,
       SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate)) AS NetFunding
FROM dbo.Applications AS a
JOIN dbo.FundingLines AS fl    ON fl.ApplicationID = a.ApplicationID
LEFT JOIN dbo.Staff AS st  ON st.StaffID = a.StaffID
GROUP BY st.StaffID, st.FirstName, st.LastName
ORDER BY NetFunding DESC;

-- F.9  Table aliases keep long joins readable - a 6-table query
SELECT TOP (5) ap.LastName, a.ApplicationID, s.SiteName, t.TenureName, pr.PartnerName, pg.ProgrammeName
FROM dbo.Applicants AS ap
JOIN dbo.Applications AS a       ON a.ApplicantID  = ap.ApplicantID
JOIN dbo.FundingLines AS fl ON fl.ApplicationID     = a.ApplicationID
JOIN dbo.Sites AS s     ON s.SiteID   = fl.SiteID
JOIN dbo.TenureTypes AS t   ON t.TenureTypeID  = s.TenureTypeID
JOIN dbo.Partners AS pr    ON pr.PartnerID  = s.PartnerID
JOIN dbo.Programmes AS pg    ON pg.ProgrammeID  = a.ProgrammeID
ORDER BY a.ApplicationID;

-- F.10 Average funding lines per application, by household type
SELECT ap.HouseholdType,
       COUNT(DISTINCT a.ApplicationID)                          AS Applications,
       COUNT(*)                                           AS Lines,
       CAST(1.0 * COUNT(*) / COUNT(DISTINCT a.ApplicationID) AS DECIMAL(6,2)) AS LinesPerApplication
FROM dbo.Applicants AS ap
JOIN dbo.Applications AS a       ON a.ApplicantID = ap.ApplicantID
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
GROUP BY ap.HouseholdType;

-- F.11 Tenure net funding by year for 2024, only valid funded lines
SELECT t.TenureName,
       SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate)) AS NetFunding2024
FROM dbo.Applications AS a
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
JOIN dbo.Sites AS s     ON s.SiteID = fl.SiteID
JOIN dbo.TenureTypes AS t   ON t.TenureTypeID = s.TenureTypeID
WHERE a.ApplicationDate >= '2024-01-01' AND a.ApplicationDate < '2025-01-01'
  AND a.Status NOT IN ('Withdrawn','Rejected')
  AND fl.Homes > 0
GROUP BY t.TenureName
ORDER BY NetFunding2024 DESC;

-- F.12 Partners whose sites generate the least net funding (all partners shown)
SELECT TOP (10) pr.PartnerName,
       ISNULL(SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate)), 0) AS NetFunding
FROM dbo.Partners AS pr
LEFT JOIN dbo.Sites AS s      ON s.PartnerID = pr.PartnerID
LEFT JOIN dbo.FundingLines AS fl  ON fl.SiteID  = s.SiteID
GROUP BY pr.PartnerID, pr.PartnerName
ORDER BY NetFunding;

/* ---- Common mistakes (F) ---------------------------------------------------
   1. Mixing INNER after LEFT (the INNER drops the NULL-padded rows again).
   2. Joining to the wrong key (s.SiteID = a.ApplicationID).
   3. Grouping by a name instead of the ID: two applicants/sites with the same
      name get merged. Group by ID and show the name too.
   4. Joining a table you do not use - slower and may multiply rows.
   5. Summing AdminFee (an application-level column) after joining to FundingLines (G).
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (F) ------------------------------------------------
   Q1. F.1: will WithDetails be larger or smaller than ApplicationRows? (Larger: one
       application has many lines; but applications with NO details contribute nothing.)
   Q2. WithTenureTypes vs WithSites: equal or smaller?  (Smaller or equal.)
   Q3. In F.8, why group by st.StaffID as well as names?  Names might not be unique.
   ---------------------------------------------------------------------------- */

/* ---- Try it (F) ------------------------------------------------------------
   NetFunding by Tenure AND HouseholdType (cross-tab as rows) for completed applications only.
   Then add a column showing each row's share of its tenure using a CASE-less
   calculation if you can (Module 08 gives you window functions for that).
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT G : THE JOIN ROW-MULTIPLICATION TRAP
   ############################################################################
   Joining a parent to a child repeats the parent's columns once per child row.
   If you SUM a PARENT column (Applications.AdminFee) after joining to the CHILD
   (FundingLines), every application's admin fee is counted once PER LINE: the total is
   inflated. Rule: only sum a column at the grain it lives at.
   ########################################################################## */

-- G.1  Truth: total admin fee straight from Applications
SELECT SUM(AdminFee) AS TrueAdminFee, COUNT(*) AS Applications FROM dbo.Applications;

-- G.2  Wrong: admin fee after joining to lines
SELECT SUM(a.AdminFee) AS InflatedAdminFee, COUNT(*) AS RowsAfterJoin
FROM dbo.Applications AS a
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID;

-- G.3  See the repetition on one application
SELECT a.ApplicationID, a.AdminFee, fl.FundingLineID
FROM dbo.Applications AS a
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
WHERE a.ApplicationID = 1;                   -- same AdminFee on every line row

-- G.4  Fix A: aggregate the child first, then join (one row per application)
SELECT SUM(a.AdminFee)                AS TrueAdminFee_Again,
       SUM(x.ApplicationNetFunding)           AS NetFunding
FROM dbo.Applications AS a
JOIN (SELECT ApplicationID, SUM(Homes * GrantPerHome * (1 - ClawbackRate)) AS ApplicationNetFunding
      FROM dbo.FundingLines GROUP BY ApplicationID) AS x ON x.ApplicationID = a.ApplicationID;
-- Careful: this INNER JOIN drops applications without details, so admin fee is slightly lower than G.1!

-- G.5  Fix B: LEFT JOIN the pre-aggregated child to keep every application
SELECT SUM(a.AdminFee)                       AS TrueAdminFee,
       SUM(ISNULL(x.ApplicationNetFunding, 0))       AS NetFunding
FROM dbo.Applications AS a
LEFT JOIN (SELECT ApplicationID, SUM(Homes * GrantPerHome * (1 - ClawbackRate)) AS ApplicationNetFunding
           FROM dbo.FundingLines GROUP BY ApplicationID) AS x ON x.ApplicationID = a.ApplicationID;

-- G.6  Fix C: COUNT(DISTINCT) rescues counts, but NOT sums
SELECT COUNT(*)                AS RowsAfterJoin,
       COUNT(DISTINCT a.ApplicationID) AS RealApplications
FROM dbo.Applications AS a JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID;

-- G.7  Counting at the wrong grain: after joining down to lines, COUNT(*) counts LINES
--      (DISTINCT shows the real number of sites and lines)
SELECT t.TenureName,
       COUNT(*)               AS JoinRows,
       COUNT(DISTINCT s.SiteID) AS RealSites,
       COUNT(DISTINCT fl.FundingLineID) AS RealLines
FROM dbo.TenureTypes AS t
JOIN dbo.Sites AS s      ON s.TenureTypeID = t.TenureTypeID
JOIN dbo.FundingLines AS fl  ON fl.SiteID  = s.SiteID
GROUP BY t.TenureName
ORDER BY JoinRows DESC;       -- JoinRows = lines, not sites: COUNT(*) answers the wrong question

-- G.8  Average admin fee per application: correct vs inflated weighting
SELECT AVG(a.AdminFee) AS AvgAdminFee_Correct
FROM dbo.Applications AS a;

SELECT AVG(a.AdminFee) AS AvgAdminFee_Weighted_By_Lines
FROM dbo.Applications AS a JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID;   -- big applications count more

-- G.9  Joining on a non-unique key silently duplicates: applicant names
SELECT COUNT(*) AS RowsByName
FROM dbo.Applicants a
JOIN dbo.Applicants b ON b.LastName = a.LastName AND b.FirstName = a.FirstName;
-- Far more than 10,000 : duplicate full names pair up. Always join on keys, not names.

-- G.10 Safety habit: compare row counts before and after each join
SELECT (SELECT COUNT(*) FROM dbo.Applications)                                                   AS Applications,
       (SELECT COUNT(*) FROM dbo.Applications AS a JOIN dbo.Applicants AS ap ON ap.ApplicantID = a.ApplicantID) AS AfterApplicants,   -- same (many-to-one)
       (SELECT COUNT(*) FROM dbo.Applications AS a JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID)    AS AfterDetails;      -- more (one-to-many)

/* ---- Common mistakes (G) ---------------------------------------------------
   1. SUM(AdminFee) / SUM(Total) of a parent column after joining a child.
   2. Using DISTINCT to "fix" a duplicated join (hides the bug, wrong sums).
   3. Joining on non-key columns such as names.
   4. Not checking row counts before/after joins.
   5. INNER JOIN to a pre-aggregated child that omits some parents (G.4).
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (G) ------------------------------------------------
   Application 7 has AdminFee 10 and 4 detail lines. After Applications JOIN FundingLines:
   Q1. How many rows for application 7? (4)   Q2. SUM(AdminFee) contribution? (40)
   Q3. Correct admin fee for the application? (10)
   Q4. An application with no details: how many rows after an INNER JOIN? (0)  After LEFT? (1)
   ---------------------------------------------------------------------------- */

/* ---- Try it (G) ------------------------------------------------------------
   Per HouseholdType, give the correct total admin fee AND total net funding in one query,
   without inflating admin fee. (Hint: pre-aggregate FundingLines per application, then
   LEFT JOIN, then group by HouseholdType.)
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT H : UNION vs UNION ALL (and INTERSECT / EXCEPT)
   ############################################################################
   Joins add COLUMNS side by side. UNION stacks ROWS from two queries.
   Rules: same number of columns, compatible types, column names from the FIRST query.
   UNION removes duplicates (a sort/distinct step: slower).
   UNION ALL keeps everything (fast; use it unless you need de-duplication).
   INTERSECT = rows in both; EXCEPT = rows in the first but not the second.
   ########################################################################## */

-- H.1  Cities where we have applicants or partners (no duplicates)
SELECT City FROM dbo.Applicants
UNION
SELECT City FROM dbo.Partners
ORDER BY City;                         -- ORDER BY only once, at the very end

-- H.2  UNION ALL keeps duplicates
SELECT City FROM dbo.Applicants
UNION ALL
SELECT City FROM dbo.Partners;

-- H.3  Row counts tell the story
SELECT (SELECT COUNT(*) FROM dbo.Applicants) + (SELECT COUNT(*) FROM dbo.Partners) AS ExpectedUnionAll,
       (SELECT COUNT(*) FROM (SELECT City FROM dbo.Applicants UNION ALL SELECT City FROM dbo.Partners) x) AS UnionAllRows,
       (SELECT COUNT(*) FROM (SELECT City FROM dbo.Applicants UNION     SELECT City FROM dbo.Partners) x) AS UnionRows;

-- H.4  Label where each row came from
SELECT 'Applicant' AS Source, Region, COUNT(*) AS Rows_
FROM dbo.Applicants GROUP BY Region
UNION ALL
SELECT 'Partner', Region, COUNT(*)
FROM dbo.Partners GROUP BY Region
ORDER BY Region, Source;

-- H.5  A people directory: staff + applicants in one list
SELECT 'Staff' AS PersonType, FirstName, LastName, Office AS City FROM dbo.Staff
UNION ALL
SELECT 'Applicant', TRIM(FirstName), TRIM(LastName), City FROM dbo.Applicants
ORDER BY LastName, FirstName;

-- H.6  Different column names: first query wins
SELECT PartnerName AS Name, Region FROM dbo.Partners
UNION
SELECT ProgrammeName, NULL FROM dbo.Programmes;      -- NULL fills the missing column

-- H.7  Mismatched column count
-- ERROR: SELECT City, Region FROM dbo.Applicants UNION SELECT City FROM dbo.Partners;
--        "All queries combined using a UNION ... must have an equal number of expressions"

-- H.8  Mismatched types
-- ERROR: SELECT ApplicantID FROM dbo.Applicants UNION SELECT City FROM dbo.Partners;
--        Conversion failed (City text vs ApplicantID int)
SELECT CAST(ApplicantID AS VARCHAR(20)) AS Value FROM dbo.Applicants WHERE ApplicantID <= 3
UNION ALL
SELECT City FROM dbo.Partners WHERE PartnerID <= 3;

-- H.9  Report with a total row: UNION ALL a summary to detail
SELECT CAST(Status AS NVARCHAR(20)) AS Status, COUNT(*) AS Applications FROM dbo.Applications GROUP BY Status
UNION ALL
SELECT N'TOTAL', COUNT(*) FROM dbo.Applications;

-- H.10 Applicants who applied in 2023 AND in 2024: INTERSECT
SELECT ApplicantID FROM dbo.Applications WHERE ApplicationDate >= '2023-01-01' AND ApplicationDate < '2024-01-01'
INTERSECT
SELECT ApplicantID FROM dbo.Applications WHERE ApplicationDate >= '2024-01-01' AND ApplicationDate < '2025-01-01';

-- H.11 Applied in 2023 but NOT in 2024 (lost applicants): EXCEPT
SELECT ApplicantID FROM dbo.Applications WHERE ApplicationDate >= '2023-01-01' AND ApplicationDate < '2024-01-01'
EXCEPT
SELECT ApplicantID FROM dbo.Applications WHERE ApplicationDate >= '2024-01-01' AND ApplicationDate < '2025-01-01';

-- H.12 Regions in both applicants and partners
SELECT UPPER(REPLACE(TRIM(Region), '-', ' ')) FROM dbo.Applicants
INTERSECT
SELECT UPPER(REPLACE(TRIM(Region), '-', ' ')) FROM dbo.Partners;

-- H.13 UNION de-duplicates across the WHOLE row, and NULLs count as equal
SELECT NULL AS X UNION SELECT NULL;               -- one row
SELECT NULL AS X UNION ALL SELECT NULL;           -- two rows

-- H.14 Net funding vs reversals as two result blocks stacked, then totalled with a wrapper
SELECT LineType, SUM(Amount) AS Amount
FROM (
    SELECT 'Funded' AS LineType, Homes * GrantPerHome * (1 - ClawbackRate) AS Amount
    FROM dbo.FundingLines WHERE Homes > 0
    UNION ALL
    SELECT 'Reversals', Homes * GrantPerHome * (1 - ClawbackRate)
    FROM dbo.FundingLines WHERE Homes < 0
) AS u
GROUP BY LineType;

/* ---- Common mistakes (H) ---------------------------------------------------
   1. Using UNION when UNION ALL is meant: silently drops legitimate duplicates
      (two real applicants in the same city collapse to one) and is slower.
   2. Different column counts / applications between the SELECTs.
   3. ORDER BY inside the first SELECT (not allowed); only at the end.
   4. Expecting column names from the second query.
   5. Using UNION to combine tables when a JOIN (side-by-side) was needed.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (H) ------------------------------------------------
   Q1. A = {1,2,2,3}, B = {3,4}.  A UNION B ?       (1,2,3,4)
   Q2. A UNION ALL B ?                              (1,2,2,3,3,4)
   Q3. A INTERSECT B ?   (3)    A EXCEPT B ?  (1,2)
   ---------------------------------------------------------------------------- */

/* ---- Try it (H) ------------------------------------------------------------
   Make one list of "contact points": every applicant City plus every partner
   City, label the source, and count how many cities appear in BOTH sets.
   ---------------------------------------------------------------------------- */
GO

/* ===================== END OF MODULE 06 =====================
   Now do: practice/module04-06_practice.sql
   ============================================================ */
