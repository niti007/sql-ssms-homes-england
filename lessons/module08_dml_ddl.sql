USE HousingDelivery;
GO
/* ============================================================================
   MODULE 08 - CHANGING DATA (DML) AND DESIGNING TABLES (DDL)
   Database : HousingDelivery (see SPEC.md)     Target : SQL Server 2019+ / SSMS
   Net funding : Homes * GrantPerHome * (1 - ClawbackRate)

   *** THE GOLDEN RULE OF THIS MODULE ***
   The HousingDelivery database is SHARED by the whole class. Every INSERT,
   UPDATE or DELETE on a real table is wrapped in
         BEGIN TRAN;  ...  ROLLBACK TRAN;
   so you can see the effect, then undo it. Nothing is ever saved.
   Anything we need to keep (tables, views, indexes) uses a Scratch_ / vw_ name.
   A cleanup section at the very end drops all of it.

   Violations that would normally throw an error are wrapped in TRY...CATCH so
   the script keeps running and shows you the error message instead.

   CONCEPTS
     0. Transactions: why BEGIN TRAN ... ROLLBACK
     A. INSERT
     B. UPDATE
     C. DELETE (and TRUNCATE)
     D. UPDATE / DELETE with a JOIN, and the OUTPUT clause
     E. CREATE / ALTER / DROP (scratch tables)
     F. Constraints: NOT NULL, UNIQUE, CHECK, DEFAULT, PRIMARY KEY, FOREIGN KEY
     G. Views
     H. Indexes: clustered vs nonclustered, and reading the execution plan
     Z. Cleanup

   HOW TO RUN: highlight the WHOLE BEGIN TRAN ... ROLLBACK block, then F5.
   If you ever run BEGIN TRAN alone by accident, run:  ROLLBACK TRAN;
   ============================================================================ */


/* ############################################################################
   CONCEPT 0 : TRANSACTIONS - WHY BEGIN TRAN ... ROLLBACK
   ############################################################################
   A transaction groups changes into "all or nothing". BEGIN TRAN starts one,
   COMMIT TRAN saves it for everyone, ROLLBACK TRAN throws every change away.
   While a transaction is open, other users may be BLOCKED from the rows you
   touched - so never leave one open. In class we ALWAYS finish with ROLLBACK
   so the shared dataset stays pristine for the next learner.
   ########################################################################## */

-- 0.1  Is a transaction open right now? (0 = no)
SELECT @@TRANCOUNT AS OpenTransactions;

-- 0.2  The safe pattern: change, look, undo
BEGIN TRAN;
    UPDATE dbo.Sites SET PlannedHomes = 0 WHERE SiteID = 1;
    SELECT SiteID, PlannedHomes AS PlannedHomes_InsideTran, @@TRANCOUNT AS OpenTrans FROM dbo.Sites WHERE SiteID = 1;
ROLLBACK TRAN;
SELECT SiteID, PlannedHomes AS PlannedHomes_AfterRollback, @@TRANCOUNT AS OpenTrans FROM dbo.Sites WHERE SiteID = 1;

-- 0.3  Nested thinking: each BEGIN TRAN adds 1, ONE rollback undoes everything
BEGIN TRAN;
    BEGIN TRAN;
        SELECT @@TRANCOUNT AS Depth;      -- 2
ROLLBACK TRAN;
SELECT @@TRANCOUNT AS DepthAfterRollback;  -- 0

-- 0.4  Even DDL can be rolled back in SQL Server
BEGIN TRAN;
    CREATE TABLE dbo.Scratch_Temp (Id INT);
    SELECT OBJECT_ID('dbo.Scratch_Temp') AS ExistsInside;     -- a number
ROLLBACK TRAN;
SELECT OBJECT_ID('dbo.Scratch_Temp') AS ExistsAfter;          -- NULL

-- 0.5  Pattern for code that may fail: roll back in CATCH
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.Sites SET PlannedHomes = 1 / 0 WHERE SiteID = 1;   -- divide by zero
    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

/* --- Common mistakes (0) -------------------------------------------------------
-- DANGER: highlighting only "BEGIN TRAN" + the UPDATE and forgetting ROLLBACK/COMMIT.
--         Your window now holds locks. Run: ROLLBACK TRAN;  (check SELECT @@TRANCOUNT)
-- DANGER: typing COMMIT TRAN instead of ROLLBACK TRAN in the shared dataset.
-- GOTCHA: closing a query window with an open transaction makes SSMS ask "commit?" - answer No.
----------------------------------------------------------------------------- */

/* --- Predict the output (0) ---------------------------------------------------
   0.2: inside = 0, after rollback = original value. 0.3: 2 then 0. 0.4: number then NULL.
----------------------------------------------------------------------------- */

-- Try it (0): inside a BEGIN TRAN / ROLLBACK, set every site's PlannedHomes to 0, select
-- SUM(PlannedHomes), roll back, then SELECT SUM(PlannedHomes) again to prove it is restored.


/* ############################################################################
   CONCEPT A : INSERT
   ############################################################################
   INSERT adds new rows. Always name the columns - it survives table changes.
   IDENTITY columns number themselves: do not supply a value. Columns you leave
   out get their DEFAULT, or NULL if allowed, or an error if NOT NULL.
   ########################################################################## */

-- A.1  Look before you leap: current tenure types
SELECT TenureTypeID, TenureName FROM dbo.TenureTypes ORDER BY TenureTypeID;

-- A.2  Insert one row (TenureTypeID is IDENTITY - we leave it out)
BEGIN TRAN;
    INSERT INTO dbo.TenureTypes (TenureName, Description)
    VALUES (N'Key Worker Living', N'Intermediate rent for NHS and teaching staff');
    SELECT TOP (3) * FROM dbo.TenureTypes ORDER BY TenureTypeID DESC;
ROLLBACK TRAN;

-- A.3  Get the new identity value back with SCOPE_IDENTITY()
BEGIN TRAN;
    INSERT INTO dbo.TenureTypes (TenureName) VALUES (N'Rural Exception Site');
    SELECT SCOPE_IDENTITY() AS NewTenureTypeID;
ROLLBACK TRAN;

-- A.4  Several rows at once (multi-row VALUES)
BEGIN TRAN;
    INSERT INTO dbo.TenureTypes (TenureName, Description)
    VALUES (N'Test A', N'First'), (N'Test B', NULL), (N'Test C', N'Third');
    SELECT @@ROWCOUNT AS RowsInserted;
    SELECT COUNT(*) AS TenureRowsInside FROM dbo.TenureTypes;
ROLLBACK TRAN;
SELECT COUNT(*) AS TenureRowsAfter FROM dbo.TenureTypes;

-- A.5  Leaving out a nullable column vs. supplying NULL explicitly (same result)
BEGIN TRAN;
    INSERT INTO dbo.TenureTypes (TenureName) VALUES (N'No description');
    INSERT INTO dbo.TenureTypes (TenureName, Description) VALUES (N'Explicit NULL', NULL);
    SELECT TenureName, Description FROM dbo.TenureTypes WHERE TenureName IN (N'No description', N'Explicit NULL');
ROLLBACK TRAN;

-- A.6  INSERT ... SELECT: copy rows from another query
BEGIN TRAN;
    INSERT INTO dbo.TenureTypes (TenureName, Description)
    SELECT TenureName + N' (copy)', Description FROM dbo.TenureTypes WHERE TenureName LIKE N'%Rent%';
    SELECT TenureTypeID, TenureName FROM dbo.TenureTypes WHERE TenureName LIKE N'%(copy)';
ROLLBACK TRAN;

-- A.7  Forcing an identity value needs SET IDENTITY_INSERT ON (rare - migrations only)
BEGIN TRAN;
    SET IDENTITY_INSERT dbo.TenureTypes ON;
    INSERT INTO dbo.TenureTypes (TenureTypeID, TenureName) VALUES (100, N'Forced id');
    SET IDENTITY_INSERT dbo.TenureTypes OFF;
    SELECT TenureTypeID, TenureName FROM dbo.TenureTypes WHERE TenureTypeID = 100;
ROLLBACK TRAN;

-- A.8  Programmes has a plain (non-identity) key: we compute the next id ourselves.
--      (If your build made ProgrammeID IDENTITY, drop that column from the INSERT.)
BEGIN TRAN;
    INSERT INTO dbo.Programmes (ProgrammeID, ProgrammeName, StartYear)
    SELECT MAX(ProgrammeID) + 1, N'Rural Housing Pilot', 2026 FROM dbo.Programmes;
    SELECT * FROM dbo.Programmes ORDER BY ProgrammeID;
ROLLBACK TRAN;

-- A.9  IDENTITY values are NOT rolled back: the number is "used up" (gaps are normal!)
SELECT IDENT_CURRENT('dbo.TenureTypes') AS IdentityBefore;
BEGIN TRAN;
    INSERT INTO dbo.TenureTypes (TenureName) VALUES (N'Gap maker');
ROLLBACK TRAN;
SELECT IDENT_CURRENT('dbo.TenureTypes') AS IdentityAfter;      -- one higher, row is gone

-- A.10 INSERT into a scratch table with OUTPUT (more in Concept D)
DROP TABLE IF EXISTS dbo.Scratch_Notes;
CREATE TABLE dbo.Scratch_Notes (NoteID INT IDENTITY(1,1) PRIMARY KEY, SiteID INT, Note NVARCHAR(200));
INSERT INTO dbo.Scratch_Notes (SiteID, Note)
OUTPUT inserted.NoteID, inserted.SiteID, inserted.Note
VALUES (1, N'Visited'), (2, N'Awaiting planning'), (3, N'Contaminated land - survey due');

-- A.11 Insert a computed result: stall-review list for next quarter
INSERT INTO dbo.Scratch_Notes (SiteID, Note)
SELECT TOP (5) SiteID, N'Stalled with ' + CAST(PlannedHomes AS NVARCHAR(10)) + N' homes planned'
FROM dbo.Sites WHERE IsStalled = 1 AND PlannedHomes > 0 ORDER BY PlannedHomes DESC, SiteID;
SELECT * FROM dbo.Scratch_Notes ORDER BY NoteID;
DROP TABLE dbo.Scratch_Notes;

/* --- Common mistakes (A) -------------------------------------------------------
-- ERROR: explicit value for an IDENTITY column
INSERT INTO dbo.TenureTypes (TenureTypeID, TenureName) VALUES (50, N'x');
-- ERROR: NOT NULL column omitted (TenureName)
INSERT INTO dbo.TenureTypes (Description) VALUES (N'no name');
-- ERROR: more values than columns
INSERT INTO dbo.TenureTypes (TenureName) VALUES (N'a', N'b');
-- ERROR: no column list, so SQL Server expects a value for the IDENTITY column too (3 columns, 2 values)
INSERT INTO dbo.TenureTypes VALUES (N'Name', N'Desc');
-- GOTCHA: 'text' without the N prefix loses non-English characters in NVARCHAR columns
----------------------------------------------------------------------------- */

/* --- Predict the output (A) ---------------------------------------------------
   A.3: a number one higher than the max id. A.4: RowsInserted = 3; inside count is 3 more than after.
   A.9: IdentityAfter = IdentityBefore + 1 even though the row was rolled back.
----------------------------------------------------------------------------- */

-- Try it (A): inside BEGIN TRAN / ROLLBACK insert two new programmes with StartYear 2027
-- (use INSERT ... SELECT with MAX(ProgrammeID) + 1 and + 2) and SELECT them back.


/* ############################################################################
   CONCEPT B : UPDATE
   ############################################################################
   UPDATE changes existing rows: UPDATE table SET col = value WHERE condition.
   FORGET THE WHERE and EVERY row changes. Habit: write the matching SELECT
   first, check the rows, then turn it into an UPDATE.
   ########################################################################## */

-- B.1  Preview with SELECT before updating
SELECT SiteID, SiteName, UnitPrice FROM dbo.Sites WHERE SiteID = 1;

-- B.2  Update one row by key
BEGIN TRAN;
    UPDATE dbo.Sites SET UnitPrice = 55000.00 WHERE SiteID = 1;
    SELECT SiteID, UnitPrice FROM dbo.Sites WHERE SiteID = 1;
ROLLBACK TRAN;

-- B.3  A calculated change on many rows: +5% grant on brownfield sites
BEGIN TRAN;
    UPDATE dbo.Sites SET UnitPrice = UnitPrice * 1.05 WHERE IsBrownfield = 1;
    SELECT @@ROWCOUNT AS SitesUpdated;
ROLLBACK TRAN;

-- B.4  The famous disaster: no WHERE clause (safe here because we ROLL BACK)
BEGIN TRAN;
    UPDATE dbo.Sites SET IsStalled = 1;
    SELECT COUNT(*) AS StalledNow, @@TRANCOUNT AS OpenTrans FROM dbo.Sites WHERE IsStalled = 1;   -- all 500
ROLLBACK TRAN;

-- B.5  Several columns in one UPDATE
BEGIN TRAN;
    UPDATE dbo.Sites SET IsStalled = 1, PlannedHomes = 0 WHERE SiteID IN (1, 2, 3);
    SELECT SiteID, IsStalled, PlannedHomes FROM dbo.Sites WHERE SiteID IN (1, 2, 3);
ROLLBACK TRAN;

-- B.6  CASE inside SET: tiered grant uplift on live (non-stalled) sites; land-only stays 0
BEGIN TRAN;
    UPDATE dbo.Sites
    SET UnitPrice = CASE WHEN UnitPrice = 0     THEN 0
                         WHEN UnitPrice < 50000 THEN UnitPrice * 1.10
                         ELSE                        UnitPrice * 1.03 END
    WHERE IsStalled = 0;
    SELECT MIN(UnitPrice) AS MinGrant, MAX(UnitPrice) AS MaxGrant FROM dbo.Sites;
ROLLBACK TRAN;

-- B.7  A subquery as the new value: give NULL admin fees on withdrawn applications the average fee
BEGIN TRAN;
    UPDATE dbo.Applications
    SET AdminFee = (SELECT AVG(AdminFee) FROM dbo.Applications)
    WHERE AdminFee IS NULL AND Status = 'Withdrawn';
    SELECT @@ROWCOUNT AS Filled;
ROLLBACK TRAN;

-- B.8  Compound assignment: += adds to the existing value
BEGIN TRAN;
    UPDATE dbo.Sites SET PlannedHomes += 10 WHERE Region = 'London' AND IsStalled = 0;
    SELECT @@ROWCOUNT AS LondonSitesUplifted;
ROLLBACK TRAN;

-- B.9  Cleaning data: turn empty-string emails into NULL (NULLIF) and count them first
SELECT COUNT(*) AS EmptyEmails FROM dbo.Applicants WHERE Email = '';
BEGIN TRAN;
    UPDATE dbo.Applicants SET Email = NULLIF(TRIM(Email), '') WHERE Email = '';
    SELECT COUNT(*) AS EmptyEmailsInside FROM dbo.Applicants WHERE Email = '';     -- 0
ROLLBACK TRAN;

-- B.10 Trim stray spaces from names. WARNING: SQL Server ignores TRAILING spaces in comparisons,
--      so  FirstName <> TRIM(FirstName)  misses names that only have trailing spaces. Use DATALENGTH.
SELECT COUNT(*) AS SloppyByComparison FROM dbo.Applicants WHERE FirstName <> TRIM(FirstName);
SELECT COUNT(*) AS SloppyByDatalength FROM dbo.Applicants WHERE DATALENGTH(FirstName) <> DATALENGTH(TRIM(FirstName));
BEGIN TRAN;
    UPDATE dbo.Applicants
    SET FirstName = TRIM(FirstName), LastName = TRIM(LastName)
    WHERE DATALENGTH(FirstName) <> DATALENGTH(TRIM(FirstName))
       OR DATALENGTH(LastName)  <> DATALENGTH(TRIM(LastName));
    SELECT @@ROWCOUNT AS NamesCleaned;
ROLLBACK TRAN;

-- B.11 UPDATE TOP has no ORDER BY - use a CTE to pick WHICH rows: stall the 5 biggest sites
BEGIN TRAN;
    WITH Biggest AS (SELECT TOP (5) * FROM dbo.Sites ORDER BY PlannedHomes DESC, SiteID)
    UPDATE Biggest SET IsStalled = 1;
    SELECT SiteID, SiteName, PlannedHomes, IsStalled FROM dbo.Sites WHERE IsStalled = 1 AND SiteID IN
        (SELECT TOP (5) SiteID FROM dbo.Sites ORDER BY PlannedHomes DESC, SiteID);
ROLLBACK TRAN;

-- B.12 Salary ties: "raise the lowest-paid" hits EVERY tied person
BEGIN TRAN;
    UPDATE dbo.Staff SET Salary = Salary * 1.02 WHERE Salary = (SELECT MIN(Salary) FROM dbo.Staff);
    SELECT @@ROWCOUNT AS PeopleRaised;
ROLLBACK TRAN;

-- B.13 Update to NULL, and why  = NULL  does nothing
BEGIN TRAN;
    UPDATE dbo.Applicants SET AnnualIncome = NULL WHERE ApplicantID = 1;           -- good
    UPDATE dbo.Applicants SET Phone = NULL WHERE Phone = NULL;                       -- 0 rows: = NULL never true
    SELECT @@ROWCOUNT AS RowsFromEqualsNull;
ROLLBACK TRAN;

/* --- Common mistakes (B) -------------------------------------------------------
-- DANGER: UPDATE dbo.Sites SET UnitPrice = 0;                 (no WHERE = every row)
-- ERROR : UPDATE dbo.Sites SET SiteName = NULL WHERE SiteID = 1;   (if SiteName is NOT NULL)
-- ERROR : UPDATE dbo.Sites SET UnitPrice = 'abc';                  (conversion failure)
-- WRONG : UPDATE dbo.Applications SET Status = 'completed';  (violates CHECK / lower-case mismatch)
-- WRONG : WHERE Phone = NULL   instead of   WHERE Phone IS NULL
----------------------------------------------------------------------------- */

/* --- Predict the output (B) ---------------------------------------------------
   B.4: StalledNow = 500. B.12: more than 1 if the lowest salary is tied. B.13: 0 rows.
   B.10: SloppyByDatalength >= SloppyByComparison (trailing-space-only names are missed by <>).
----------------------------------------------------------------------------- */

-- Try it (B): inside BEGIN TRAN / ROLLBACK, cut the PlannedHomes of every stalled site in
-- 'North West' by 20% (rounded down: use CAST to INT) and report how many rows were updated.


/* ############################################################################
   CONCEPT C : DELETE (and TRUNCATE)
   ############################################################################
   DELETE removes rows that match a WHERE. TRUNCATE TABLE empties a whole table
   fast (no WHERE, resets IDENTITY, blocked if another table references it).
   DROP TABLE removes the table itself. Child rows (FundingLines) must go before
   their parents (Applications) or the FOREIGN KEY stops you.
   ########################################################################## */

-- C.1  Delete the unused programme (nothing references it)
BEGIN TRAN;
    DELETE FROM dbo.Programmes
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Applications a WHERE a.ProgrammeID = dbo.Programmes.ProgrammeID);
    SELECT @@ROWCOUNT AS Deleted;                       -- 1: Community Housing Fund
    SELECT ProgrammeName FROM dbo.Programmes;
ROLLBACK TRAN;

-- C.2  A foreign key protects parents: deleting a partner that owns sites FAILS
BEGIN TRY
    BEGIN TRAN;
        DELETE FROM dbo.Partners WHERE PartnerID = 1;
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;     -- 547: conflicted with REFERENCE constraint
END CATCH;

-- C.3  How many future-dated applications (2026 onwards) are there, and do they have funding lines?
SELECT COUNT(DISTINCT a.ApplicationID) AS FutureApps,
       COUNT(DISTINCT f.ApplicationID) AS WithLines
FROM dbo.Applications a
LEFT JOIN dbo.FundingLines f ON f.ApplicationID = a.ApplicationID
WHERE a.ApplicationDate >= '2026-01-01';

-- C.4  Delete future-dated applications: children first, then parents
BEGIN TRAN;
    DELETE f
    FROM dbo.FundingLines AS f
    JOIN dbo.Applications AS a ON a.ApplicationID = f.ApplicationID
    WHERE a.ApplicationDate >= '2026-01-01';
    SELECT @@ROWCOUNT AS LinesDeleted;

    DELETE FROM dbo.Applications WHERE ApplicationDate >= '2026-01-01';
    SELECT @@ROWCOUNT AS ApplicationsDeleted;
ROLLBACK TRAN;

-- C.5  Delete in the wrong order -> FK error (parents first)
BEGIN TRY
    BEGIN TRAN;
        DELETE FROM dbo.Applications WHERE ApplicationDate >= '2026-01-01'
          AND EXISTS (SELECT 1 FROM dbo.FundingLines f WHERE f.ApplicationID = dbo.Applications.ApplicationID);
    ROLLBACK TRAN;
    SELECT 'No future-dated application had funding lines in this build - nothing blocked' AS Result;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- C.6  DELETE TOP (n) - removes n arbitrary rows; fine for batching big clean-ups
BEGIN TRAN;
    DELETE TOP (10) FROM dbo.Applications WHERE Status = 'Rejected' AND NOT EXISTS
        (SELECT 1 FROM dbo.FundingLines f WHERE f.ApplicationID = dbo.Applications.ApplicationID);
    SELECT @@ROWCOUNT AS Deleted;
ROLLBACK TRAN;

-- C.7  Delete never-funded, zero-home sites (nothing references them)
BEGIN TRAN;
    DELETE s
    FROM dbo.Sites AS s
    WHERE s.PlannedHomes = 0
      AND NOT EXISTS (SELECT 1 FROM dbo.FundingLines f WHERE f.SiteID = s.SiteID);
    SELECT @@ROWCOUNT AS SitesDeleted;
ROLLBACK TRAN;

-- C.8  DELETE, TRUNCATE and DROP compared on a scratch copy
DROP TABLE IF EXISTS dbo.Scratch_Sites;
SELECT * INTO dbo.Scratch_Sites FROM dbo.Sites;
SELECT COUNT(*) AS Start FROM dbo.Scratch_Sites;
DELETE FROM dbo.Scratch_Sites WHERE Region = 'London';              -- WHERE allowed, logged row by row
SELECT COUNT(*) AS AfterDelete FROM dbo.Scratch_Sites;
TRUNCATE TABLE dbo.Scratch_Sites;                                   -- all rows gone instantly, no WHERE
SELECT COUNT(*) AS AfterTruncate FROM dbo.Scratch_Sites;
DROP TABLE dbo.Scratch_Sites;                                       -- table gone too
SELECT OBJECT_ID('dbo.Scratch_Sites') AS TableId;                   -- NULL

-- C.9  TRUNCATE is refused on a table that other tables reference
BEGIN TRY
    BEGIN TRAN;
        TRUNCATE TABLE dbo.Partners;
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;      -- 4712
END CATCH;

-- C.10 Preview duplicates before deleting them (never delete blind)
SELECT UPPER(TRIM(FirstName)) AS FirstName, UPPER(TRIM(LastName)) AS LastName, COUNT(*) AS Copies
FROM dbo.Applicants
GROUP BY UPPER(TRIM(FirstName)), UPPER(TRIM(LastName))
HAVING COUNT(*) > 1
ORDER BY Copies DESC, LastName;

/* --- Common mistakes (C) -------------------------------------------------------
-- DANGER: DELETE FROM dbo.Applications;           (no WHERE = whole table)
-- ERROR : DELETE FROM dbo.Sites WHERE SiteID = 1;  (FundingLines reference it -> FK 547)
-- WRONG : DELETE with TOP and expecting the "latest" rows - TOP without ORDER BY is arbitrary
-- WRONG : assuming two applicants with the same name are one person and deleting one
----------------------------------------------------------------------------- */

/* --- Predict the output (C) ---------------------------------------------------
   C.1: Deleted = 1. C.4: LinesDeleted then ApplicationsDeleted ~20 (or the number from C.3).
   C.8: 500, a smaller number, 0, then NULL. C.9: error 4712.
----------------------------------------------------------------------------- */

-- Try it (C): inside BEGIN TRAN / ROLLBACK delete all applications with Status = 'Withdrawn'
-- that have no funding lines. Report how many rows went.


/* ############################################################################
   CONCEPT D : UPDATE / DELETE WITH A JOIN, AND THE OUTPUT CLAUSE
   ############################################################################
   To change rows based on ANOTHER table, name the alias after UPDATE and put the
   join in a FROM clause:  UPDATE s SET ... FROM Sites s JOIN ... .
   OUTPUT shows what changed, using two virtual tables: inserted (new values)
   and deleted (old values). It is an instant audit trail.
   ########################################################################## */

-- D.1  Raise grant 3% for Social Rent sites (join to TenureTypes)
BEGIN TRAN;
    UPDATE s
    SET s.UnitPrice = s.UnitPrice * 1.03
    FROM dbo.Sites AS s
    JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID
    WHERE t.TenureName = N'Social Rent';
    SELECT @@ROWCOUNT AS SitesRaised;
ROLLBACK TRAN;

-- D.2  OUTPUT shows old and new values side by side
BEGIN TRAN;
    UPDATE TOP (5) s
    SET s.UnitPrice = s.UnitPrice * 1.10
    OUTPUT inserted.SiteID, deleted.UnitPrice AS OldGrant, inserted.UnitPrice AS NewGrant
    FROM dbo.Sites AS s
    WHERE s.UnitPrice > 0 AND s.IsBrownfield = 1;
ROLLBACK TRAN;

-- D.3  OUTPUT INTO a table variable, then use it after the update
BEGIN TRAN;
    DECLARE @Audit TABLE (SiteID INT, OldHomes INT, NewHomes INT);
    UPDATE dbo.Sites
    SET PlannedHomes = PlannedHomes + 5
    OUTPUT inserted.SiteID, deleted.PlannedHomes, inserted.PlannedHomes INTO @Audit
    WHERE Region = 'North East' AND IsStalled = 0;
    SELECT COUNT(*) AS RowsAudited, SUM(NewHomes - OldHomes) AS TotalHomesAdded FROM @Audit;
ROLLBACK TRAN;

-- D.4  UPDATE through a derived table: sites of partners in a given type get flagged
BEGIN TRAN;
    UPDATE s
    SET s.IsStalled = 1
    FROM dbo.Sites AS s
    JOIN (SELECT PartnerID FROM dbo.Partners WHERE PartnerType = 'Local Authority') AS p
         ON p.PartnerID = s.PartnerID
    WHERE s.PlannedHomes = 0;
    SELECT @@ROWCOUNT AS Flagged;
ROLLBACK TRAN;

-- D.5  Update from aggregated data: set AdminFee to 0 for applications that have NO funding lines
BEGIN TRAN;
    UPDATE a
    SET a.AdminFee = 0
    OUTPUT inserted.ApplicationID, deleted.AdminFee AS OldFee, inserted.AdminFee AS NewFee
    FROM dbo.Applications AS a
    LEFT JOIN dbo.FundingLines AS f ON f.ApplicationID = a.ApplicationID
    WHERE f.FundingLineID IS NULL AND a.AdminFee IS NULL AND a.ApplicationID <= 3000;
ROLLBACK TRAN;

-- D.6  Update in a CTE: pay rise 3% for staff earning below their office average
BEGIN TRAN;
    WITH Avgs AS (
        SELECT StaffID, Salary,
               AVG(Salary) OVER (PARTITION BY Office) AS OfficeAvg
        FROM dbo.Staff)
    UPDATE Avgs SET Salary = Salary * 1.03 WHERE Salary < OfficeAvg;
    SELECT @@ROWCOUNT AS PeopleRaised;
ROLLBACK TRAN;

-- D.7  DELETE with OUTPUT: see exactly what disappeared
BEGIN TRAN;
    DELETE FROM dbo.Programmes
    OUTPUT deleted.ProgrammeID, deleted.ProgrammeName, deleted.StartYear
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Applications a WHERE a.ProgrammeID = dbo.Programmes.ProgrammeID);
ROLLBACK TRAN;

-- D.8  INSERT with OUTPUT: capture generated IDENTITY values for several rows
BEGIN TRAN;
    INSERT INTO dbo.TenureTypes (TenureName)
    OUTPUT inserted.TenureTypeID, inserted.TenureName
    VALUES (N'Pilot A'), (N'Pilot B');
ROLLBACK TRAN;

-- D.9  Safe pre-check for a join update: does the join multiply rows?
--      If one Site matched several rows, UPDATE FROM would pick ONE of them arbitrarily.
SELECT s.SiteID, COUNT(*) AS Matches
FROM dbo.Sites AS s
JOIN dbo.FundingLines AS f ON f.SiteID = s.SiteID
GROUP BY s.SiteID
HAVING COUNT(*) > 1
ORDER BY Matches DESC, s.SiteID
OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY;     -- one-to-many: do NOT update Sites "from" FundingLines columns

-- D.10 DELETE with JOIN: remove funding lines for rejected applications
BEGIN TRAN;
    DELETE f
    OUTPUT deleted.FundingLineID, deleted.ApplicationID
    FROM dbo.FundingLines AS f
    JOIN dbo.Applications AS a ON a.ApplicationID = f.ApplicationID
    WHERE a.Status = 'Rejected' AND a.ApplicationID <= 200;
ROLLBACK TRAN;

/* --- Common mistakes (D) -------------------------------------------------------
-- ERROR: UPDATE dbo.Sites SET ... FROM dbo.Sites s JOIN ...    (alias s targeted but table name used)
--        Use  UPDATE s SET ... FROM dbo.Sites s JOIN ...
-- WRONG: join to a one-to-many table - the row gets updated by an arbitrary match
-- ERROR: OUTPUT cannot use a column of the joined table that is not in inserted/deleted
--        (in UPDATE ... FROM you CAN reference other tables' columns in OUTPUT, but not in INSERT ... VALUES)
-- WRONG: forgetting the join condition (cross join!) updates every row with an arbitrary value
----------------------------------------------------------------------------- */

/* --- Predict the output (D) ---------------------------------------------------
   D.2: 5 rows with NewGrant = OldGrant * 1.10. D.3: TotalHomesAdded = 5 * RowsAudited.
   D.9: sites that have several funding lines - proof of the one-to-many trap.
----------------------------------------------------------------------------- */

-- Try it (D): inside BEGIN TRAN / ROLLBACK, use UPDATE ... JOIN to add 2 homes to PlannedHomes of every
-- site whose Partner is of type 'SME Builder', with OUTPUT showing old and new PlannedHomes (first 5 rows).


/* ############################################################################
   CONCEPT E : CREATE / ALTER / DROP (SCRATCH TABLES)
   ############################################################################
   DDL (Data Definition Language) designs the structure: CREATE builds a table,
   ALTER changes it, DROP deletes it. We only touch tables named Scratch_*.
   Always DROP TABLE IF EXISTS first so the script can be re-run.
   ########################################################################## */

-- E.1  Create a table
DROP TABLE IF EXISTS dbo.Scratch_SiteReview;
CREATE TABLE dbo.Scratch_SiteReview (
    ReviewID     INT IDENTITY(1,1) NOT NULL,
    SiteID       INT           NOT NULL,
    ReviewedOn   DATE          NOT NULL,
    Reviewer     NVARCHAR(100) NULL,
    HomesAtRisk  INT           NULL
);

-- E.2  Add some data
INSERT INTO dbo.Scratch_SiteReview (SiteID, ReviewedOn, Reviewer, HomesAtRisk)
VALUES (1, '2025-03-31', N'A. Patel', 12), (2, '2025-04-01', N'B. Jones', NULL), (3, '2025-04-01', NULL, 40);
SELECT * FROM dbo.Scratch_SiteReview;

-- E.3  ALTER: add a column (existing rows get NULL)
ALTER TABLE dbo.Scratch_SiteReview ADD RiskLevel NVARCHAR(10) NULL;

-- E.4  ALTER: add a NOT NULL column - needs a DEFAULT so existing rows can be filled
ALTER TABLE dbo.Scratch_SiteReview ADD IsClosed BIT NOT NULL CONSTRAINT DF_SiteReview_IsClosed DEFAULT (0);
SELECT ReviewID, IsClosed FROM dbo.Scratch_SiteReview;

-- E.5  ALTER COLUMN: widen a type
ALTER TABLE dbo.Scratch_SiteReview ALTER COLUMN Reviewer NVARCHAR(200) NULL;

-- E.6  ALTER COLUMN to NOT NULL fails while NULLs exist (caught here so the script continues)
BEGIN TRY
    ALTER TABLE dbo.Scratch_SiteReview ALTER COLUMN Reviewer NVARCHAR(200) NOT NULL;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;     -- 515
END CATCH;

-- E.7  Fix the data first, then it works
UPDATE dbo.Scratch_SiteReview SET Reviewer = N'Unassigned' WHERE Reviewer IS NULL;
ALTER TABLE dbo.Scratch_SiteReview ALTER COLUMN Reviewer NVARCHAR(200) NOT NULL;

-- E.8  Rename a column (sp_rename) and then drop one
EXEC sp_rename 'dbo.Scratch_SiteReview.HomesAtRisk', 'HomesAtRiskCount', 'COLUMN';
ALTER TABLE dbo.Scratch_SiteReview DROP COLUMN RiskLevel;
SELECT * FROM dbo.Scratch_SiteReview;

-- E.9  A computed column: financial year of the review (April-March) calculated automatically
ALTER TABLE dbo.Scratch_SiteReview ADD ReviewFY AS
    (CASE WHEN MONTH(ReviewedOn) >= 4 THEN YEAR(ReviewedOn) ELSE YEAR(ReviewedOn) - 1 END);
SELECT ReviewedOn, ReviewFY FROM dbo.Scratch_SiteReview;      -- 31 Mar 2025 -> 2024, 1 Apr 2025 -> 2025

-- E.10 Inspect the structure
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE, COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Scratch_SiteReview'
ORDER BY ORDINAL_POSITION;

-- E.11 TRUNCATE resets IDENTITY, DELETE does not
DELETE FROM dbo.Scratch_SiteReview;
INSERT INTO dbo.Scratch_SiteReview (SiteID, ReviewedOn, Reviewer) VALUES (9, '2025-05-01', N'X');
SELECT ReviewID AS IdAfterDelete FROM dbo.Scratch_SiteReview;      -- 4
TRUNCATE TABLE dbo.Scratch_SiteReview;
INSERT INTO dbo.Scratch_SiteReview (SiteID, ReviewedOn, Reviewer) VALUES (9, '2025-05-01', N'X');
SELECT ReviewID AS IdAfterTruncate FROM dbo.Scratch_SiteReview;    -- 1

-- E.12 Drop it
DROP TABLE IF EXISTS dbo.Scratch_SiteReview;
SELECT OBJECT_ID('dbo.Scratch_SiteReview') AS TableId;             -- NULL

/* --- Common mistakes (E) -------------------------------------------------------
-- ERROR: CREATE TABLE dbo.Scratch_SiteReview (...)  run twice -> "already an object named"
-- ERROR: ALTER TABLE ... ADD col INT NOT NULL    (no DEFAULT, table has rows)
-- ERROR: ALTER COLUMN to a smaller type than existing data (truncation) or to an incompatible type
-- DANGER: DROP TABLE dbo.Sites;   <- a REAL table. Only ever drop Scratch_ tables.
-- ERROR: ALTER COLUMN fails while a DEFAULT, CHECK or index depends on the column - drop that first
----------------------------------------------------------------------------- */

/* --- Predict the output (E) ---------------------------------------------------
   E.9: ReviewFY 2024 for 2025-03-31 and 2025 for the two 2025-04-01 rows.
   E.11: 4 (identity keeps counting after DELETE) then 1 (restart after TRUNCATE).
----------------------------------------------------------------------------- */

-- Try it (E): create dbo.Scratch_Quarter (QuarterID INT IDENTITY, FinYear CHAR(7), QNo TINYINT, Target INT),
-- insert FY '2024/25' Q1..Q4 targets, add a NOT NULL column Owner with a default of N'TBC', then drop the table.


/* ############################################################################
   CONCEPT F : CONSTRAINTS
   ############################################################################
   Constraints are rules the database enforces so bad data cannot get in:
     NOT NULL     - a value is required
     UNIQUE       - no duplicates (NULL allowed once)
     PRIMARY KEY  - NOT NULL + UNIQUE, identifies each row
     DEFAULT      - value used when you omit the column
     CHECK        - a custom rule (Homes >= 0)
     FOREIGN KEY  - value must exist in the parent table
   Below, each is created, used correctly, then deliberately violated.
   ########################################################################## */

-- F.1  Build parent and child scratch tables with every constraint type
DROP TABLE IF EXISTS dbo.Scratch_Scheme;
DROP TABLE IF EXISTS dbo.Scratch_Region;

CREATE TABLE dbo.Scratch_Region (
    RegionCode CHAR(2)       NOT NULL CONSTRAINT PK_ScratchRegion PRIMARY KEY,
    RegionName NVARCHAR(50)  NOT NULL CONSTRAINT UQ_ScratchRegion_Name UNIQUE
);

CREATE TABLE dbo.Scratch_Scheme (
    SchemeID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ScratchScheme PRIMARY KEY,
    SchemeName   NVARCHAR(100)  NOT NULL,
    RegionCode   CHAR(2)        NOT NULL CONSTRAINT FK_ScratchScheme_Region REFERENCES dbo.Scratch_Region (RegionCode),
    Homes        INT            NOT NULL CONSTRAINT CK_ScratchScheme_Homes CHECK (Homes >= 0),
    GrantPerHome DECIMAL(10,2)  NOT NULL,
    ClawbackRate DECIMAL(4,2)   NOT NULL CONSTRAINT DF_ScratchScheme_Clawback DEFAULT (0)
                                         CONSTRAINT CK_ScratchScheme_Clawback CHECK (ClawbackRate BETWEEN 0 AND 1),
    Status       NVARCHAR(20)   NOT NULL CONSTRAINT DF_ScratchScheme_Status DEFAULT (N'Planned')
                                         CONSTRAINT CK_ScratchScheme_Status CHECK (Status IN (N'Planned', N'Started', N'Completed')),
    CreatedOn    DATETIME2(0)   NOT NULL CONSTRAINT DF_ScratchScheme_Created DEFAULT (SYSDATETIME()),
    CONSTRAINT UQ_ScratchScheme_NameRegion UNIQUE (SchemeName, RegionCode)
);

-- F.2  Valid data goes in; DEFAULTs fill the omitted columns
INSERT INTO dbo.Scratch_Region (RegionCode, RegionName)
VALUES ('NW', N'North West'), ('LN', N'London'), ('NE', N'North East');

INSERT INTO dbo.Scratch_Scheme (SchemeName, RegionCode, Homes, GrantPerHome)
VALUES (N'Canal Basin Phase 1', 'NW', 120, 70000.00);          -- Status, ClawbackRate, CreatedOn defaulted
SELECT * FROM dbo.Scratch_Scheme;

-- F.3  NOT NULL violated (error 515)
BEGIN TRY
    INSERT INTO dbo.Scratch_Scheme (SchemeName, RegionCode, Homes, GrantPerHome) VALUES (NULL, 'NW', 10, 1000);
END TRY
BEGIN CATCH
    SELECT 'NOT NULL' AS ConstraintType, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- F.4  PRIMARY KEY violated (error 2627): RegionCode 'NW' already exists
BEGIN TRY
    INSERT INTO dbo.Scratch_Region (RegionCode, RegionName) VALUES ('NW', N'Another North West');
END TRY
BEGIN CATCH
    SELECT 'PRIMARY KEY' AS ConstraintType, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- F.5  UNIQUE violated (error 2627): region name repeated
BEGIN TRY
    INSERT INTO dbo.Scratch_Region (RegionCode, RegionName) VALUES ('XX', N'London');
END TRY
BEGIN CATCH
    SELECT 'UNIQUE' AS ConstraintType, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- F.6  Composite UNIQUE violated: same SchemeName + RegionCode twice
BEGIN TRY
    INSERT INTO dbo.Scratch_Scheme (SchemeName, RegionCode, Homes, GrantPerHome)
    VALUES (N'Canal Basin Phase 1', 'NW', 5, 1000);
END TRY
BEGIN CATCH
    SELECT 'UNIQUE (composite)' AS ConstraintType, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- F.7  CHECK violated (error 547): negative homes
BEGIN TRY
    INSERT INTO dbo.Scratch_Scheme (SchemeName, RegionCode, Homes, GrantPerHome) VALUES (N'Bad Homes', 'LN', -5, 1000);
END TRY
BEGIN CATCH
    SELECT 'CHECK (Homes)' AS ConstraintType, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- F.8  CHECK violated: ClawbackRate of 150%; and Status not in the list
BEGIN TRY
    INSERT INTO dbo.Scratch_Scheme (SchemeName, RegionCode, Homes, GrantPerHome, ClawbackRate)
    VALUES (N'Bad Clawback', 'LN', 5, 1000, 1.50);
END TRY
BEGIN CATCH
    SELECT 'CHECK (Clawback)' AS ConstraintType, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;
BEGIN TRY
    INSERT INTO dbo.Scratch_Scheme (SchemeName, RegionCode, Homes, GrantPerHome, Status)
    VALUES (N'Bad Status', 'LN', 5, 1000, N'Cancelled');
END TRY
BEGIN CATCH
    SELECT 'CHECK (Status)' AS ConstraintType, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- F.9  FOREIGN KEY violated on INSERT: region code 'ZZ' does not exist in the parent
BEGIN TRY
    INSERT INTO dbo.Scratch_Scheme (SchemeName, RegionCode, Homes, GrantPerHome) VALUES (N'Orphan', 'ZZ', 1, 1000);
END TRY
BEGIN CATCH
    SELECT 'FOREIGN KEY (insert)' AS ConstraintType, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- F.10 FOREIGN KEY violated on DELETE: parent 'NW' still has a child scheme
BEGIN TRY
    DELETE FROM dbo.Scratch_Region WHERE RegionCode = 'NW';
END TRY
BEGIN CATCH
    SELECT 'FOREIGN KEY (delete)' AS ConstraintType, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- F.11 DEFAULT in action, and DEFAULT keyword used explicitly
INSERT INTO dbo.Scratch_Scheme (SchemeName, RegionCode, Homes, GrantPerHome, Status, ClawbackRate)
VALUES (N'Explicit Defaults', 'NE', 30, 60000, DEFAULT, DEFAULT);
SELECT SchemeName, Status, ClawbackRate, CreatedOn FROM dbo.Scratch_Scheme ORDER BY SchemeID;

-- F.12 NULLs and CHECK: a CHECK only rejects FALSE, not UNKNOWN. A nullable column slips through.
DROP TABLE IF EXISTS dbo.Scratch_Check;
CREATE TABLE dbo.Scratch_Check (Fee DECIMAL(10,2) NULL CONSTRAINT CK_ScratchCheck_Fee CHECK (Fee >= 0));
INSERT INTO dbo.Scratch_Check VALUES (NULL);      -- allowed! NULL >= 0 is UNKNOWN, not FALSE
SELECT * FROM dbo.Scratch_Check;
DROP TABLE dbo.Scratch_Check;

-- F.13 Adding a CHECK to a table that already has bad data: ~30 applications have
--      CompletionDate earlier than ApplicationDate. Test on a COPY, never on the real table.
DROP TABLE IF EXISTS dbo.Scratch_Applications;
SELECT * INTO dbo.Scratch_Applications FROM dbo.Applications;
BEGIN TRY
    ALTER TABLE dbo.Scratch_Applications
        ADD CONSTRAINT CK_ScratchApps_Dates CHECK (CompletionDate >= CAST(ApplicationDate AS DATE));
END TRY
BEGIN CATCH
    SELECT 'CHECK on existing data' AS ConstraintType, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- F.14 Find the offending rows, then choose: fix them, or apply the rule to new data only (NOCHECK)
SELECT COUNT(*) AS BadRows FROM dbo.Scratch_Applications WHERE CompletionDate < CAST(ApplicationDate AS DATE);
ALTER TABLE dbo.Scratch_Applications WITH NOCHECK
    ADD CONSTRAINT CK_ScratchApps_Dates CHECK (CompletionDate >= CAST(ApplicationDate AS DATE));
-- new bad rows are now blocked, old ones are tolerated (the constraint is flagged "not trusted")
SELECT name, is_not_trusted FROM sys.check_constraints WHERE name = 'CK_ScratchApps_Dates';

-- F.15 List the constraints on a table
SELECT OBJECT_NAME(parent_object_id) AS TableName, name AS ConstraintName, type_desc
FROM sys.objects
WHERE type IN ('PK','UQ','C','D','F') AND OBJECT_NAME(parent_object_id) IN ('Scratch_Scheme','Scratch_Region','Scratch_Applications')
ORDER BY TableName, type_desc, name;

-- F.16 Drop a constraint (by name)
ALTER TABLE dbo.Scratch_Applications DROP CONSTRAINT CK_ScratchApps_Dates;

/* --- Common mistakes (F) -------------------------------------------------------
-- ERROR: two constraints with the same name in one schema (names must be unique per schema)
-- ERROR: dropping a parent table before its child: DROP TABLE dbo.Scratch_Region; (FK reference) - drop child first
-- WRONG: assuming a CHECK on a nullable column forces a value (it does not; add NOT NULL too)
-- WRONG: CHECK constraints cannot contain subqueries: CHECK (Homes <= (SELECT MAX(...) ...))
-- WRONG: DEFAULT does NOT fix an explicit NULL: INSERT ... VALUES (NULL) puts NULL, not the default
----------------------------------------------------------------------------- */

/* --- Predict the output (F) ---------------------------------------------------
   F.3: 515. F.4/F.5/F.6: 2627. F.7-F.10: 547. F.12 inserts happily. F.13 fails with 547.
   F.14: BadRows around 30; is_not_trusted = 1.
----------------------------------------------------------------------------- */

-- Try it (F): add a CHECK to dbo.Scratch_Scheme so that GrantPerHome is between 0 and 250000,
-- then try to insert 300000 inside TRY...CATCH. (Drop scratch tables in Concept Z.)


/* ############################################################################
   CONCEPT G : VIEWS
   ############################################################################
   A view is a SAVED QUERY with a name. It stores no data - each time you query
   it, SQL Server runs the saved SELECT. Use views to hide complexity (joins),
   to give everyone the same definition of a measure (net funding), and to
   expose only safe columns (no income or email).
   CREATE OR ALTER VIEW must be the first statement in its batch, so each view
   sits between GO lines.
   ########################################################################## */

GO
-- G.1  A view that flattens Sites + Partner + Tenure (LEFT JOIN keeps NULL-tenure sites)
CREATE OR ALTER VIEW dbo.vw_SiteDetail
AS
SELECT s.SiteID, s.SiteName, s.Region, s.LocalAuthority, s.PlannedHomes, s.UnitPrice,
       s.IsBrownfield, s.IsStalled,
       p.PartnerName, p.PartnerType,
       ISNULL(t.TenureName, N'(No tenure)') AS TenureName
FROM dbo.Sites AS s
JOIN dbo.Partners AS p ON p.PartnerID = s.PartnerID
LEFT JOIN dbo.TenureTypes AS t ON t.TenureTypeID = s.TenureTypeID;
GO

-- G.2  A view with a shared definition of net funding per site
CREATE OR ALTER VIEW dbo.vw_SiteNetFunding
AS
SELECT f.SiteID,
       COUNT(*)                                          AS FundingLines,
       SUM(f.Homes)                                      AS Homes,
       SUM(f.Homes * f.GrantPerHome * (1 - f.ClawbackRate)) AS NetFunding
FROM dbo.FundingLines AS f
GROUP BY f.SiteID;
GO

-- G.3  A view that exposes only non-sensitive applicant columns
CREATE OR ALTER VIEW dbo.vw_ApplicantPublic
AS
SELECT ApplicantID, TRIM(FirstName) AS FirstName, TRIM(LastName) AS LastName, City, HouseholdType, RegisteredDate
FROM dbo.Applicants;       -- no Email, Phone or AnnualIncome
GO

-- G.4  A view that calculates the financial year for each application
CREATE OR ALTER VIEW dbo.vw_ApplicationFY
AS
SELECT ApplicationID, ApplicantID, ApplicationDate, Status, PropertyRegion,
       CASE WHEN MONTH(ApplicationDate) >= 4 THEN YEAR(ApplicationDate) ELSE YEAR(ApplicationDate) - 1 END AS FinYearStart,
       CAST(CASE WHEN MONTH(ApplicationDate) >= 4 THEN YEAR(ApplicationDate) ELSE YEAR(ApplicationDate) - 1 END AS CHAR(4))
         + '/' + RIGHT(CAST(CASE WHEN MONTH(ApplicationDate) >= 4 THEN YEAR(ApplicationDate) + 1 ELSE YEAR(ApplicationDate) END AS VARCHAR(4)), 2) AS FinYear
FROM dbo.Applications;
GO

-- G.5  Use the views exactly like tables
SELECT TOP (10) SiteName, Region, TenureName, PartnerName FROM dbo.vw_SiteDetail ORDER BY SiteID;

-- G.6  Filter, aggregate and join views
SELECT d.Region, SUM(n.NetFunding) AS NetFunding
FROM dbo.vw_SiteDetail AS d
JOIN dbo.vw_SiteNetFunding AS n ON n.SiteID = d.SiteID
GROUP BY d.Region
ORDER BY NetFunding DESC;

-- G.7  The FY view: applications per financial year (note the 31 March / 1 April boundary)
SELECT FinYear, COUNT(*) AS Applications FROM dbo.vw_ApplicationFY GROUP BY FinYear ORDER BY FinYear;
SELECT ApplicationID, ApplicationDate, FinYear
FROM dbo.vw_ApplicationFY
WHERE CAST(ApplicationDate AS DATE) IN ('2025-03-31', '2025-04-01') AND ApplicationID % 40 = 0;

-- G.8  Sites not in any funding line: LEFT JOIN a view to find gaps
SELECT COUNT(*) AS SitesWithNoFunding
FROM dbo.vw_SiteDetail AS d
LEFT JOIN dbo.vw_SiteNetFunding AS n ON n.SiteID = d.SiteID
WHERE n.SiteID IS NULL;

-- G.9  See a view's definition
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.vw_ApplicantPublic')) AS ViewSql;
EXEC sp_helptext 'dbo.vw_SiteNetFunding';

GO
-- G.10 A view with WITH CHECK OPTION: updates through it cannot move a row out of the view
CREATE OR ALTER VIEW dbo.vw_StalledSites
AS
SELECT SiteID, SiteName, IsStalled, PlannedHomes
FROM dbo.Sites
WHERE IsStalled = 1
WITH CHECK OPTION;
GO

-- G.11 Updating through a view changes the base table (inside a transaction, then undone)
BEGIN TRAN;
    UPDATE dbo.vw_StalledSites SET PlannedHomes = PlannedHomes + 1 WHERE SiteID IN (SELECT TOP (3) SiteID FROM dbo.vw_StalledSites ORDER BY SiteID);
    SELECT @@ROWCOUNT AS RowsUpdatedThroughView;
ROLLBACK TRAN;

-- G.12 CHECK OPTION blocks changes that would make the row disappear from the view
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.vw_StalledSites SET IsStalled = 0 WHERE SiteID IN (SELECT TOP (1) SiteID FROM dbo.vw_StalledSites ORDER BY SiteID);
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;      -- 550
END CATCH;

GO
-- G.13 Change a view with CREATE OR ALTER (here: add a column), then remove one with DROP
CREATE OR ALTER VIEW dbo.vw_ApplicantPublic
AS
SELECT ApplicantID, TRIM(FirstName) AS FirstName, TRIM(LastName) AS LastName, City, Region, HouseholdType, RegisteredDate
FROM dbo.Applicants;
GO
SELECT TOP (3) * FROM dbo.vw_ApplicantPublic ORDER BY ApplicantID;
DROP VIEW IF EXISTS dbo.vw_StalledSites;

/* --- Common mistakes (G) -------------------------------------------------------
-- ERROR: ORDER BY in a view without TOP/OFFSET. Sort when you SELECT from the view instead.
CREATE VIEW dbo.vw_Bad AS SELECT SiteName FROM dbo.Sites ORDER BY SiteName;
-- ERROR: CREATE VIEW not first in batch (no GO before it)
-- ERROR: two columns with the same name in the view (SiteID from two tables) - alias them
-- GOTCHA: SELECT * in a view freezes the column list at creation time; new table columns don't appear
--         (run EXEC sp_refreshview 'dbo.vw_X'). Name your columns instead.
-- GOTCHA: a view does not make a slow query fast; it just hides the query. (Indexed views are different.)
----------------------------------------------------------------------------- */

/* --- Predict the output (G) ---------------------------------------------------
   G.7: the 31 March 2025 rows show 2024/25 and the 1 April rows 2025/26.
   G.8: ~40 (the never-funded sites). G.12: error 550 (attempted insert/update failed CHECK OPTION).
----------------------------------------------------------------------------- */

-- Try it (G): create dbo.vw_PartnerSummary (PartnerName, PartnerType, Sites, PlannedHomes) using a LEFT JOIN so
-- partners with zero sites still appear, then SELECT the 5 partners with the most planned homes from it.


/* ############################################################################
   CONCEPT H : INDEXES (CLUSTERED vs NONCLUSTERED)
   ############################################################################
   An index is like the index of a book: instead of reading every page (table
   scan) SQL Server jumps straight to the rows it needs (index seek).
   CLUSTERED   : the table itself, sorted by the key. Only ONE per table.
                 (A PRIMARY KEY creates one by default.)
   NONCLUSTERED: a separate sorted list of key values + pointers to the rows.
                 You can have many. INCLUDE columns avoid extra lookups.
   Indexes speed up reads but slow down INSERT/UPDATE/DELETE and use disk.

   *** TIP - READ THE EXECUTION PLAN ***
   In SSMS press Ctrl+M ("Include Actual Execution Plan"), run the query, then
   open the "Execution plan" tab. Look for "Table Scan" / "Clustered Index Scan"
   (reads everything) vs "Index Seek" (jumps to the rows). Fat arrows = many
   rows. Green "Missing Index" text suggests an index. Hover for costs.
   Also try:  SET STATISTICS IO ON;  and read the "logical reads" in Messages.
   ########################################################################## */

-- H.1  Make a scratch copy of Applications with NO index (a "heap")
DROP TABLE IF EXISTS dbo.Scratch_Apps;
SELECT * INTO dbo.Scratch_Apps FROM dbo.Applications;
SELECT i.name, i.type_desc FROM sys.indexes AS i WHERE i.object_id = OBJECT_ID('dbo.Scratch_Apps');   -- HEAP

-- H.2  Turn on IO stats and the plan (Ctrl+M), then run this query: it scans every row
SET STATISTICS IO ON;
SELECT ApplicationID, ApplicationDate, Status FROM dbo.Scratch_Apps WHERE ApplicantID = 5000;

-- H.3  Create a CLUSTERED index (sorts the table by ApplicationID)
CREATE UNIQUE CLUSTERED INDEX CIX_ScratchApps_ApplicationID ON dbo.Scratch_Apps (ApplicationID);
SELECT ApplicationID, ApplicationDate, Status FROM dbo.Scratch_Apps WHERE ApplicationID = 12345;     -- Clustered Index Seek

-- H.4  The ApplicantID query still scans. Add a NONCLUSTERED index on it
CREATE NONCLUSTERED INDEX IX_ScratchApps_ApplicantID ON dbo.Scratch_Apps (ApplicantID);
SELECT ApplicationID, ApplicationDate, Status FROM dbo.Scratch_Apps WHERE ApplicantID = 5000;
-- plan: Index Seek + Key Lookup (fetches ApplicationDate and Status from the clustered index)

-- H.5  Remove the lookup with INCLUDE (a "covering" index)
DROP INDEX IX_ScratchApps_ApplicantID ON dbo.Scratch_Apps;
CREATE NONCLUSTERED INDEX IX_ScratchApps_ApplicantID ON dbo.Scratch_Apps (ApplicantID) INCLUDE (ApplicationDate, Status);
SELECT ApplicationID, ApplicationDate, Status FROM dbo.Scratch_Apps WHERE ApplicantID = 5000;      -- seek only

-- H.6  Sargability: a function on the column stops the index being used
SELECT COUNT(*) FROM dbo.Scratch_Apps WHERE YEAR(ApplicationDate) = 2024;          -- scan
CREATE NONCLUSTERED INDEX IX_ScratchApps_Date ON dbo.Scratch_Apps (ApplicationDate);
SELECT COUNT(*) FROM dbo.Scratch_Apps WHERE YEAR(ApplicationDate) = 2024;          -- still a scan (function on column)
SELECT COUNT(*) FROM dbo.Scratch_Apps WHERE ApplicationDate >= '2024-01-01' AND ApplicationDate < '2025-01-01';   -- seek

-- H.7  Same idea for the financial year 2024/25 - use a half-open range, never BETWEEN on dates with times
SELECT COUNT(*) AS Apps_FY2425
FROM dbo.Scratch_Apps
WHERE ApplicationDate >= '2024-04-01' AND ApplicationDate < '2025-04-01';

-- H.8  Leading wildcard kills seeks; a trailing wildcard is fine
CREATE NONCLUSTERED INDEX IX_ScratchApps_City ON dbo.Scratch_Apps (PropertyCity);
SELECT COUNT(*) FROM dbo.Scratch_Apps WHERE PropertyCity LIKE N'Man%';     -- seek
SELECT COUNT(*) FROM dbo.Scratch_Apps WHERE PropertyCity LIKE N'%chester'; -- scan

-- H.9  Composite index: column ORDER matters (leftmost column must be filtered)
CREATE NONCLUSTERED INDEX IX_ScratchApps_RegionStatus ON dbo.Scratch_Apps (PropertyRegion, Status);
SELECT COUNT(*) FROM dbo.Scratch_Apps WHERE PropertyRegion = N'London' AND Status = 'Completed';   -- seek on both
SELECT COUNT(*) FROM dbo.Scratch_Apps WHERE Status = 'Completed';                                  -- cannot seek (Status is second)

-- H.10 Filtered index: indexes only the rows you query often
CREATE NONCLUSTERED INDEX IX_ScratchApps_Open ON dbo.Scratch_Apps (ApplicationDate) WHERE Status = 'Submitted';

-- H.11 A UNIQUE index enforces a rule AND speeds lookups
BEGIN TRY
    CREATE UNIQUE NONCLUSTERED INDEX UX_ScratchApps_ApplicantDate ON dbo.Scratch_Apps (ApplicantID, ApplicationDate);
    SELECT 'Unique index created - no duplicate applicant/timestamp pairs' AS Result;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;     -- 1505 if duplicates exist
END CATCH;

-- H.12 List the indexes and their sizes
SELECT i.name, i.type_desc, i.is_unique, i.has_filter,
       SUM(ps.used_page_count) * 8 / 1024.0 AS SizeMB
FROM sys.indexes AS i
JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.object_id = OBJECT_ID('dbo.Scratch_Apps')
GROUP BY i.name, i.type_desc, i.is_unique, i.has_filter
ORDER BY i.type_desc, i.name;

-- H.13 Index cost on writes: every extra index must be maintained (compare Messages tab logical writes)
BEGIN TRAN;
    UPDATE dbo.Scratch_Apps SET Status = 'Approved' WHERE ApplicationID <= 5000 AND Status = 'Submitted';
ROLLBACK TRAN;

SET STATISTICS IO OFF;

/* --- Common mistakes (H) -------------------------------------------------------
-- ERROR: a second CLUSTERED index on the same table (only one allowed)
CREATE CLUSTERED INDEX CIX_Again ON dbo.Scratch_Apps (ApplicantID);
-- WRONG: WHERE YEAR(ApplicationDate) = 2024  /  WHERE CONVERT(VARCHAR, ApplicationDate, 23) = '2024-05-01'
-- WRONG: BETWEEN '2025-03-31' AND '2025-03-31'  misses 31 March rows after midnight (the 23:59:59 rows!)
-- WRONG: indexing every column "just in case" - writes get slower and storage balloons
-- WRONG: index on a low-selectivity column such as a BIT (IsStalled): the optimiser will ignore it
-- GOTCHA: the table is not "faster" until the optimiser CHOOSES the index - always check the plan
----------------------------------------------------------------------------- */

/* --- Predict the output (H) ---------------------------------------------------
   H.2: logical reads in the hundreds (whole table). H.5: only a handful of reads.
   H.6: first two queries scan, the range query seeks. H.9: the Status-only query scans.
----------------------------------------------------------------------------- */

-- Try it (H): with Ctrl+M on, write a query for applications from ApplicantID = 100 and 200 using IN,
-- note the operator in the plan, and decide whether the covering index from H.5 helps.


/* ############################################################################
   CONCEPT Z : CLEANUP - run this last so the shared database is left tidy
   ########################################################################## */

DROP TABLE IF EXISTS dbo.Scratch_Apps;
DROP TABLE IF EXISTS dbo.Scratch_Applications;
DROP TABLE IF EXISTS dbo.Scratch_Scheme;       -- child first
DROP TABLE IF EXISTS dbo.Scratch_Region;       -- then parent
DROP TABLE IF EXISTS dbo.Scratch_Check;
DROP TABLE IF EXISTS dbo.Scratch_Notes;
DROP TABLE IF EXISTS dbo.Scratch_SiteReview;
DROP TABLE IF EXISTS dbo.Scratch_Sites;
DROP VIEW IF EXISTS dbo.vw_SiteDetail;
DROP VIEW IF EXISTS dbo.vw_SiteNetFunding;
DROP VIEW IF EXISTS dbo.vw_ApplicantPublic;
DROP VIEW IF EXISTS dbo.vw_ApplicationFY;
DROP VIEW IF EXISTS dbo.vw_StalledSites;
-- TenureTypes is IDENTITY: the rolled-back inserts above still used up id numbers. Reseed so the next real insert gets 13.
DECLARE @maxTenure INT = (SELECT MAX(TenureTypeID) FROM dbo.TenureTypes);
DBCC CHECKIDENT ('dbo.TenureTypes', RESEED, @maxTenure) WITH NO_INFOMSGS;
SELECT @@TRANCOUNT AS OpenTransactions;       -- should be 0

/* ============================================================================
   END OF MODULE 08. Next: module09_advanced.sql
   ============================================================================ */
