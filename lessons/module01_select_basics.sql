USE HousingDelivery;
GO
/*==============================================================================
  MODULE 01 : SELECT BASICS
  Database  : HousingDelivery (SQL Server 2019+, run in SSMS)
  Topics    : 1. SELECT * and choosing columns
              2. Column aliases (and expressions)
              3. DISTINCT
              4. COUNT(*) vs COUNT(col) vs COUNT(DISTINCT col)
              5. TOP, TOP PERCENT, TOP WITH TIES
              6. ORDER BY basics

  HOW TO USE THIS FILE
    - Highlight ONE query at a time in SSMS and press F5 (or Ctrl+E).
    - Read the comment above each example first, guess the result, then run it.
    - "Common mistakes" blocks are commented out on purpose. Un-comment one
      (select the lines, Ctrl+K then Ctrl+U) to see the error or wrong result.
    - "Predict the output" blocks: answer on paper first, then run the query.
      Answers are written at the bottom of each block.
==============================================================================*/


/*##############################################################################
  CONCEPT 1 : SELECT * AND SPECIFIC COLUMNS
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  SELECT tells SQL Server which columns you want. FROM tells it which table.
  SELECT * means "give me every column". It is handy for a quick look at a
  table, but in real work you should name the columns you need: it is faster,
  clearer, and does not break when someone adds a column later.
------------------------------------------------------------------------------*/

-- Example 1.1 : the simplest query. Every column, every row (12 rows).
SELECT * FROM TenureTypes;

-- Example 1.2 : the same idea on a small table (5 programmes).
SELECT * FROM Programmes;

-- Example 1.3 : name the columns you want. Order in SELECT = order in output.
SELECT TenureName, TenureTypeID
FROM TenureTypes;

-- Example 1.4 : only two columns from Partners (40 rows).
SELECT PartnerName, City
FROM Partners;

-- Example 1.5 : a bigger table. SELECT * on 10,000 applicants is slow to show;
-- naming columns keeps the result small and readable.
SELECT FirstName, LastName, City, Country
FROM Applicants;

-- Example 1.6 : Sites. Look at average grant per home and planned homes only.
SELECT SiteName, UnitPrice, PlannedHomes
FROM Sites;

-- Example 1.7 : look at the planted dirty data: some names have spaces / odd case.
-- Scroll the result and notice '  john' or 'SMITH' style values.
SELECT ApplicantID, FirstName, LastName
FROM Applicants;

-- Example 1.8 : SELECT without FROM. SQL Server can calculate things on its own.
SELECT 1 + 1 AS TwoPlusTwo, GETDATE() AS RightNow, 'Hello HousingDelivery' AS Greeting;

-- Example 1.9 : a column listed twice is allowed (rarely useful).
SELECT SiteName, UnitPrice, UnitPrice
FROM Sites;

-- Example 1.10 : mix columns and constants. Every row gets the same literal.
SELECT 'Site' AS RecordType, SiteID, SiteName
FROM Sites;

-- Example 1.11 : schema-qualified table name. dbo is the schema. Good habit.
SELECT TOP 10 SiteID, SiteName
FROM dbo.Sites;

-- Example 1.12 : tricky: a column that allows NULL. NULL is shown as NULL, not blank.
-- Look at the TenureTypeID column: about 5 sites have NULL (no tenure type).
SELECT SiteID, SiteName, TenureTypeID
FROM Sites;

-- Example 1.13 : tricky: Staff has a ManagerID that is NULL for the CEO only.
SELECT StaffID, FirstName, LastName, JobTitle, ManagerID
FROM Staff;

/*---- Common mistakes : CONCEPT 1 ---------------------------------------------
-- Mistake 1: misspelled column name -> Msg 207 Invalid column name 'SiteNam'.
SELECT SiteNam FROM Sites;

-- Mistake 2: forgetting the comma between columns. SQL Server reads
-- "UnitPrice PlannedHomes" as: UnitPrice with the ALIAS PlannedHomes!
-- No error, but a column is missing and the header is wrong.
SELECT SiteName, UnitPrice PlannedHomes FROM Sites;

-- Mistake 3: trailing comma before FROM -> syntax error.
SELECT SiteName, UnitPrice, FROM Sites;

-- Mistake 4: using SELECT * in siteion views/reports. If a column is added,
-- renamed, or reordered, downstream code silently changes.
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 1 ------------------------------------------
Q1. How many rows does  SELECT * FROM TenureTypes;  return?
Q2. How many columns does it return?
Q3. SELECT SiteName, UnitPrice PlannedHomes FROM Sites;  How many columns?
Q4. SELECT 5 * 4 AS Result;  What is the output? (no FROM needed)
ANSWERS: Q1 = 12 rows. Q2 = 3 (TenureTypeID, TenureName, Description).
         Q3 = 2 (the second is UnitPrice, labelled "PlannedHomes").
         Q4 = one row, one column: 20.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 1 ------------------------------------------------------
Write a query that shows PartnerName, City and Phone from Partners.
Then change it to SELECT * and compare. Which result would you rather email?
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 2 : COLUMN ALIASES (AND SIMPLE EXPRESSIONS)
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  An alias gives a column (or a table) a new, friendlier name in the result.
  It does not change the table. Use AS to be clear. If the alias has spaces,
  wrap it in [square brackets] or "double quotes". Aliases are also how you
  name calculated columns, which otherwise have no name at all.
------------------------------------------------------------------------------*/

-- Example 2.1 : rename a column with AS.
SELECT SiteName AS Site, UnitPrice AS AvgGrant
FROM Sites;

-- Example 2.2 : AS is optional (but less readable). Same result as 2.1.
SELECT SiteName Site, UnitPrice AvgGrant
FROM Sites;

-- Example 2.3 : alias with a space needs [brackets].
SELECT SiteName AS [Site Name], UnitPrice AS [Avg Grant per Home (GBP)]
FROM Sites;

-- Example 2.4 : double-quoted alias also works (ANSI style).
SELECT TenureName AS "Tenure type Name"
FROM TenureTypes;

-- Example 2.5 : a calculation with an alias. Total grant envelope = average grant per home x planned homes.
SELECT SiteName,
       UnitPrice,
       PlannedHomes,
       UnitPrice * PlannedHomes AS GrantEnvelope
FROM Sites;

-- Example 2.6 : text concatenation with +. FullName from two columns.
SELECT FirstName + ' ' + LastName AS FullName, City
FROM Applicants;

-- Example 2.7 : CONCAT() is safer: it treats NULL as an empty string.
SELECT CONCAT(FirstName, ' ', LastName, ' (', City, ', ', Country, ')') AS ApplicantLabel
FROM Applicants;

-- Example 2.8 : tricky: + with NULL gives NULL, CONCAT does not.
-- Compare the two columns. Applicants with NULL Region show NULL in the first.
SELECT ApplicantID,
       City + ', ' + Region       AS PlusVersion,
       CONCAT(City, ', ', Region) AS ConcatVersion
FROM Applicants;

-- Example 2.9 : the net-funding formula (Homes x GrantPerHome x (1 - ClawbackRate)), with an alias.
SELECT FundingLineID,
       Homes,
       GrantPerHome,
       ClawbackRate,
       Homes * GrantPerHome * (1 - ClawbackRate) AS NetFunding
FROM FundingLines;

-- Example 2.10 : table aliases. Short names save typing (vital once we join).
SELECT p.SiteName, p.UnitPrice
FROM Sites AS p;

-- Example 2.11 : an alias can be used in ORDER BY (it is evaluated last).
SELECT SiteName, UnitPrice * PlannedHomes AS GrantEnvelope
FROM Sites
ORDER BY GrantEnvelope DESC;

-- Example 2.12 : tricky: percent shown as a number. ClawbackRate 0.25 becomes 25.
SELECT FundingLineID, ClawbackRate, ClawbackRate * 100 AS ClawbackPercent
FROM FundingLines;

-- Example 2.13 : tricky: integer division! 7/2 is 3, not 3.5.
SELECT 7 / 2 AS IntegerDivision, 7 / 2.0 AS DecimalDivision, 7 % 2 AS Remainder;

-- Example 2.14 : tricky: an expression with no alias has NO column name.
-- Run it and look at the header, then fix it with an alias.
SELECT UnitPrice * 1.1 FROM Sites;
SELECT UnitPrice * 1.1 AS GrantWith10PctUplift FROM Sites;

/*---- Common mistakes : CONCEPT 2 ---------------------------------------------
-- Mistake 1: using a SELECT alias in WHERE -> Msg 207 Invalid column name.
-- WHERE runs BEFORE SELECT, so the alias does not exist yet.
SELECT SiteName, UnitPrice * PlannedHomes AS GrantEnvelope
FROM Sites
WHERE GrantEnvelope > 1000;
-- Fix: repeat the expression:  WHERE UnitPrice * PlannedHomes > 1000

-- Mistake 2: single quotes around an alias in some places can be confusing and
-- are deprecated in older syntax forms like  'AvgGrant' = UnitPrice. Prefer AS.

-- Mistake 3: adding a number to text -> conversion error.
SELECT 'Planned homes: ' + PlannedHomes FROM Sites;
-- Fix: 'Planned homes: ' + CAST(PlannedHomes AS VARCHAR(10))  or use CONCAT.

-- Mistake 4: forgetting that + on NULL gives NULL (see Example 2.8).
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 2 ------------------------------------------
Q1. SELECT 10 / 4 AS A, 10 / 4.0 AS B;   What are A and B?
Q2. SELECT 'AB' + NULL AS X, CONCAT('AB', NULL) AS Y;   What are X and Y?
Q3. A site has UnitPrice 12500.00 and PlannedHomes 4. What is GrantEnvelope?
Q4. Can you write  ORDER BY GrantEnvelope  if GrantEnvelope is a SELECT alias?
ANSWERS: Q1 = A is 2 (integer division), B is 2.500000. Q2 = X is NULL, Y is 'AB'.
         Q3 = 50000.00. Q4 = Yes. ORDER BY runs after SELECT, so aliases work there.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 2 ------------------------------------------------------
From Staff, show a column "StaffMember" like  "Jane Doe - Delivery"  (first name,
space, last name, dash, Directorate) plus Salary renamed to [Monthly Salary]
where Monthly Salary is Salary / 12 (hint: watch the decimals).
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 3 : DISTINCT
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  DISTINCT removes duplicate rows from the result. SQL Server compares the
  WHOLE row you selected: DISTINCT applies to all the columns together, not
  just the first one. NULL counts as one value (two NULLs are "the same" for
  DISTINCT). Use it to answer "what different values exist?".
------------------------------------------------------------------------------*/

-- Example 3.1 : which countries do applicants live in?
SELECT DISTINCT Country
FROM Applicants;

-- Example 3.2 : without DISTINCT you get 10,000 rows. Compare to 3.1.
SELECT Country
FROM Applicants;

-- Example 3.3 : the three household types.
SELECT DISTINCT HouseholdType
FROM Applicants;

-- Example 3.4 : the application statuses actually used.
SELECT DISTINCT Status
FROM Applications;

-- Example 3.5 : DISTINCT on two columns = distinct PAIRS.
SELECT DISTINCT Country, HouseholdType
FROM Applicants;

-- Example 3.6 : DISTINCT with ORDER BY to get an alphabetical list.
SELECT DISTINCT Country
FROM Applicants
ORDER BY Country;

-- Example 3.7 : tricky: NULL counts as one distinct value. Region is ~30% NULL.
-- You get ONE row with NULL, not thousands.
SELECT DISTINCT Region
FROM Applicants
ORDER BY Region;

-- Example 3.8 : tricky: dirty country spellings. 'England', 'england', 'UK', 'United Kingdom'.
-- Under SQL Server's default case-insensitive collation 'England' and 'england' collapse
-- into ONE row, but 'UK' and 'United Kingdom' are different strings, so they stay separate.
SELECT DISTINCT Country
FROM Applicants
WHERE Country LIKE 'Eng%' OR Country LIKE 'U%'
ORDER BY Country;

-- Example 3.9 : tricky: stray spaces make values distinct. Compare the counts:
SELECT COUNT(DISTINCT LastName)             AS DistinctRawLastNames,
       COUNT(DISTINCT LTRIM(RTRIM(LastName))) AS DistinctTrimmedLastNames
FROM Applicants;

-- Example 3.10 : which cities and regions do our partners operate in? (40 partners)
SELECT DISTINCT City, Region
FROM Partners
ORDER BY Region, City;

-- Example 3.11 : which sites have actually received funding? (distinct SiteIDs)
SELECT DISTINCT SiteID
FROM FundingLines;

-- Example 3.12 : which applicants have submitted at least one application?
SELECT DISTINCT ApplicantID
FROM Applications;

-- Example 3.13 : tricky: DISTINCT on an expression. Distinct years of applications.
SELECT DISTINCT YEAR(ApplicationDate) AS ApplicationYear
FROM Applications
ORDER BY ApplicationYear;

-- Example 3.14 : DISTINCT applies to the whole SELECT list: this does NOT give
-- one row per country, because HouseholdType is also included.
SELECT DISTINCT Country, HouseholdType, IsActive
FROM Applicants;

/*---- Common mistakes : CONCEPT 3 ---------------------------------------------
-- Mistake 1: thinking DISTINCT applies to one column only.
--   SELECT DISTINCT Country, FirstName FROM Applicants;   -- still thousands of rows!
-- Mistake 2: using DISTINCT to "fix" a wrong join that duplicates rows. It hides
--   the real bug and is slow. Find out WHY rows are duplicated.
-- Mistake 3: ORDER BY a column that is not in the SELECT list of a DISTINCT query
-- -> Msg 145: ORDER BY items must appear in the select list if SELECT DISTINCT.
SELECT DISTINCT Country FROM Applicants ORDER BY City;
-- Mistake 4: forgetting that case-insensitive collation merges 'England' and 'england';
--   you cannot see the dirty spelling with DISTINCT alone.
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 3 ------------------------------------------
Q1. How many rows does  SELECT DISTINCT HouseholdType FROM Applicants;  return?
Q2. SELECT DISTINCT Region FROM Applicants;  If 12 real regions exist, how many
    rows come back given that ~30% of regions are NULL?
Q3. SELECT DISTINCT Status FROM Applications;  How many rows (per SPEC statuses)?
Q4. Does SELECT DISTINCT Country, HouseholdType return more, fewer, or the same number
    of rows as SELECT DISTINCT Country?
ANSWERS: Q1 = 3 (First-time buyer, Key worker, Home mover). Q2 = 13 (12 + one NULL row).
         Q3 = 5. Q4 = more or equal (pairs); equal only if each country has just
         one household type, which is very unlikely.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 3 ------------------------------------------------------
List the distinct Directorate values in Staff, sorted A-Z.
Then list the distinct (Directorate, JobTitle) pairs. How many more rows?
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 4 : COUNT(*) vs COUNT(col) vs COUNT(DISTINCT col)
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  COUNT(*)            counts ROWS, no matter what is inside them.
  COUNT(column)       counts rows where that column is NOT NULL.
  COUNT(DISTINCT col) counts the different NOT NULL values.
  Aggregates like COUNT collapse the table into a single summary row. SQL Server
  may print "Null value is eliminated by an aggregate" in the Messages tab: this
  is a warning, not an error. Empty strings ('') are NOT NULL, so they ARE counted.
------------------------------------------------------------------------------*/

-- Example 4.1 : how many applicants? 10,000.
SELECT COUNT(*) AS TotalApplicants
FROM Applicants;

-- Example 4.2 : how many tenure types / partners / programmes / sites?
SELECT (SELECT COUNT(*) FROM TenureTypes) AS TenureTypes,
       (SELECT COUNT(*) FROM Partners)  AS Partners,
       (SELECT COUNT(*) FROM Programmes)   AS Programmes,
       (SELECT COUNT(*) FROM Sites)   AS Sites;

-- Example 4.3 : COUNT(col) skips NULLs. Applicants with an email value on file.
SELECT COUNT(Email) AS EmailNotNull
FROM Applicants;

-- Example 4.4 : compare the three side by side on Applicants.
SELECT COUNT(*)                AS AllRows,
       COUNT(Email)            AS EmailNotNull,
       COUNT(Phone)            AS PhoneNotNull,
       COUNT(Region)           AS RegionNotNull
FROM Applicants;

-- Example 4.5 : COUNT(DISTINCT) counts different values.
SELECT COUNT(DISTINCT Country) AS DistinctCountries,
       COUNT(DISTINCT City)    AS DistinctCities,
       COUNT(DISTINCT HouseholdType) AS DistinctHouseholdTypes
FROM Applicants;

-- Example 4.6 : all three on one column. Applications per applicant idea:
-- 60,000 applications, but far fewer distinct applicants (300 applicants have none).
SELECT COUNT(*)                     AS ApplicationRows,
       COUNT(ApplicantID)            AS ApplicantIDNotNull,
       COUNT(DISTINCT ApplicantID)   AS ApplicantsWhoApplied
FROM Applications;

-- Example 4.7 : tricky: CompletionDate is NULL for Submitted/Withdrawn/Rejected applications.
SELECT COUNT(*)           AS AllApplications,
       COUNT(CompletionDate) AS ApplicationsWithCompletionDate
FROM Applications;

-- Example 4.8 : tricky: StaffID NULL means an online application (online self-service, no case officer).
-- AllApplications minus ApplicationsWithStaff = number of online applications.
SELECT COUNT(*)          AS AllApplications,
       COUNT(StaffID) AS ApplicationsWithStaff,
       COUNT(*) - COUNT(StaffID) AS OnlineApplications
FROM Applications;

-- Example 4.9 : tricky: empty strings ARE counted by COUNT(Email).
-- Email = '' is a real (empty) value. Compare these three numbers.
SELECT COUNT(*)                                   AS AllApplicants,
       COUNT(Email)                               AS EmailNotNull,
       COUNT(NULLIF(Email, ''))                   AS EmailReallyUsable,
       COUNT(*) - COUNT(NULLIF(Email, ''))        AS NoUsableEmail
FROM Applicants;

-- Example 4.10 : tricky: AdminFee can be NULL or 0. They are different things.
SELECT COUNT(*)        AS AllApplications,
       COUNT(AdminFee)  AS AdminFeeNotNull,
       COUNT(CASE WHEN AdminFee = 0 THEN 1 END) AS ZeroAdminFee
FROM Applications;

-- Example 4.11 : sites with no tenure type (about 5).
SELECT COUNT(*) - COUNT(TenureTypeID) AS SitesWithoutTenureType
FROM Sites;

-- Example 4.12 : COUNT(1) and COUNT(*) behave the same. Use COUNT(*).
SELECT COUNT(1) AS CountOne, COUNT(*) AS CountStar
FROM Sites;

-- Example 4.13 : the dirty-name effect on distinct counts (see Example 3.9).
SELECT COUNT(DISTINCT FirstName + ' ' + LastName)                        AS RawDistinctFullNames,
       COUNT(DISTINCT LTRIM(RTRIM(FirstName)) + ' ' + LTRIM(RTRIM(LastName))) AS CleanDistinctFullNames,
       COUNT(*)                                                          AS Applicants
FROM Applicants;

-- Example 4.14 : COUNT on a big table, with a bigger return type. Fine on 180k rows.
SELECT COUNT(*) AS DetailRows, COUNT_BIG(*) AS DetailRowsBig
FROM FundingLines;

/*---- Common mistakes : CONCEPT 4 ---------------------------------------------
-- Mistake 1: using COUNT(Email) to count applicants. It misses NULLs and wrongly
--   includes ''. For "how many rows" use COUNT(*).
-- Mistake 2: mixing a plain column with an aggregate and no GROUP BY.
--   Msg 8120: column is invalid in the select list because it is not contained
--   in an aggregate function or GROUP BY clause.
SELECT Country, COUNT(*) FROM Applicants;
-- Mistake 3: COUNT(DISTINCT a, b) is not allowed in SQL Server.
SELECT COUNT(DISTINCT Country, HouseholdType) FROM Applicants;
-- Fix: count a derived key, or use a subquery:
--   SELECT COUNT(*) FROM (SELECT DISTINCT Country, HouseholdType FROM Applicants) AS x;
-- Mistake 4: assuming COUNT(*) - COUNT(col) is "0 rows" when empty strings exist;
--   it only counts NULLs, not blanks.
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 4 ------------------------------------------
Q1. Applicants table: COUNT(*) is 10,000 and ~8% of Email is NULL. Roughly what
    is COUNT(Email)?
Q2. Can COUNT(Email) ever be larger than COUNT(*)?
Q3. Applications has 60,000 rows. Is COUNT(DISTINCT ApplicantID) bigger or smaller than
    COUNT(ApplicantID)?
Q4. A column has values: 5, 5, NULL, 7. What are COUNT(*), COUNT(col),
    COUNT(DISTINCT col)?
ANSWERS: Q1 ~ 9,200 (and it still includes the '' rows). Q2 = never.
         Q3 = smaller (applicants place many applications). Q4 = 4, 3, 2.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 4 ------------------------------------------------------
In ONE query on Sites, return: total sites, sites with a TenureTypeID,
distinct TenureTypeIDs used, and how many have UnitPrice = 0 (land-only sites).
Hint: for the last one use COUNT(CASE WHEN UnitPrice = 0 THEN 1 END).
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 5 : TOP, TOP PERCENT, TOP WITH TIES
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  TOP (n) returns only the first n rows. TOP (n) PERCENT returns that percent
  of rows (rounded UP). Without ORDER BY, "first" is meaningless: SQL Server may
  return ANY n rows. WITH TIES adds extra rows that tie with the last row; it
  REQUIRES an ORDER BY. TOP is T-SQL specific; the ANSI alternative is
  OFFSET ... FETCH (shown at the end).
------------------------------------------------------------------------------*/

-- Example 5.1 : any 5 rows, no promise which ones.
SELECT TOP 5 SiteID, SiteName
FROM Sites;

-- Example 5.2 : the 5 sites with the highest average grant per home (ORDER BY gives TOP meaning).
SELECT TOP 5 SiteName, UnitPrice
FROM Sites
ORDER BY UnitPrice DESC;

-- Example 5.3 : brackets are recommended, and required for variables/expressions.
SELECT TOP (3) SiteName, UnitPrice
FROM Sites
ORDER BY UnitPrice DESC;

-- Example 5.4 : the 10 sites with the lowest grant per home. Land-only sites (grant 0) will lead the list!
SELECT TOP (10) SiteName, UnitPrice
FROM Sites
ORDER BY UnitPrice ASC;

-- Example 5.5 : the 10 most recent applications.
SELECT TOP (10) ApplicationID, ApplicantID, ApplicationDate, Status
FROM Applications
ORDER BY ApplicationDate DESC;

-- Example 5.6 : TOP PERCENT: the top 1 percent of 500 sites = 5 rows.
SELECT TOP (1) PERCENT SiteName, UnitPrice
FROM Sites
ORDER BY UnitPrice DESC;

-- Example 5.7 : TOP PERCENT rounds UP. 1 percent of 60,000 applications = 600 rows;
-- 0.01 percent of 500 = 0.05 -> still 1 row.
SELECT TOP (0.01) PERCENT SiteName, UnitPrice
FROM Sites
ORDER BY UnitPrice DESC;

-- Example 5.8 : TOP with a variable. Must use brackets.
DECLARE @HowMany INT = 7;
SELECT TOP (@HowMany) StaffID, FirstName, LastName, Salary
FROM Staff
ORDER BY Salary DESC;
GO

-- Example 5.9 : tricky: TOP 3 by salary. If the 3rd and 4th earn the same,
-- one of them is silently dropped (and which one is random).
SELECT TOP (3) FirstName, LastName, Salary
FROM Staff
ORDER BY Salary DESC;

-- Example 5.10 : fix: WITH TIES keeps everybody who ties with the last row.
-- (Salaries have planted ties, so you may see more than 3 rows.)
SELECT TOP (3) WITH TIES FirstName, LastName, Salary
FROM Staff
ORDER BY Salary DESC;

-- Example 5.11 : another WITH TIES: lowest non-zero grant sites, ties included.
SELECT TOP (5) WITH TIES SiteName, UnitPrice
FROM Sites
ORDER BY UnitPrice ASC;

-- Example 5.12 : tricky: WITH TIES only looks at ORDER BY columns.
-- Here a tie means "same ApplicationDate and time" - rarely a tie. Look carefully.
SELECT TOP (5) WITH TIES ApplicationID, ApplicationDate
FROM Applications
ORDER BY ApplicationDate DESC;

-- Example 5.13 : make TOP deterministic with a tie-breaker column.
SELECT TOP (5) FirstName, LastName, Salary
FROM Staff
ORDER BY Salary DESC, StaffID ASC;

-- Example 5.14 : TOP 0 returns the column structure but no rows.
SELECT TOP (0) * FROM Applicants;

-- Example 5.15 : the ANSI alternative: OFFSET / FETCH (needs ORDER BY).
-- Skip 0 rows, return the next 5.
SELECT SiteName, UnitPrice
FROM Sites
ORDER BY UnitPrice DESC, SiteID
OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY;

/*---- Common mistakes : CONCEPT 5 ---------------------------------------------
-- Mistake 1: TOP without ORDER BY and treating it as "the best/newest".
SELECT TOP 5 SiteName, UnitPrice FROM Sites;   -- arbitrary 5 rows
-- Mistake 2: WITH TIES without ORDER BY -> Msg 1062 error.
SELECT TOP 3 WITH TIES SiteName FROM Sites;
-- Mistake 3: variable without brackets -> syntax error.
DECLARE @n INT = 5;  SELECT TOP @n * FROM Sites;
-- Mistake 4: "10 lowest grant" and forgetting land-only sites (UnitPrice = 0) and
--   stalled items fill the list. Business meaning needs a WHERE (module 2).
-- Mistake 5: expecting TOP PERCENT to round down (it rounds up).
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 5 ------------------------------------------
Q1. How many rows does  SELECT TOP (10) PERCENT * FROM Sites;  return?
Q2. How many rows does  SELECT TOP (1) PERCENT * FROM Programmes;  return?
    (5 programmes; 1 percent = 0.05 rows)
Q3. Salaries (desc): 200, 150, 120, 120, 100. What does TOP (3) return? TOP (3)
    WITH TIES?
Q4. Is  SELECT TOP (3) WITH TIES * FROM Sites  valid without ORDER BY?
ANSWERS: Q1 = 50. Q2 = 1 (rounded up). Q3 = TOP(3) gives 200,150, and ONE of the
         two 120s (random). WITH TIES gives 200,150,120,120 (4 rows).
         Q4 = No, error 1062: WITH TIES needs ORDER BY.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 5 ------------------------------------------------------
1) Show the 5 earliest-hired staff. 2) Redo it with WITH TIES. Did the row
count change? 3) Show the top 2 PERCENT of Applicants by RegisteredDate (newest).
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 6 : ORDER BY BASICS
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  ORDER BY sorts the result. Default is ASC (smallest first, A to Z, oldest
  first). DESC reverses it. Without ORDER BY there is NO guaranteed order, even
  if it looks sorted today. ORDER BY is the very last step of a query, so it can
  use aliases. NULLs sort FIRST in ASC and LAST in DESC in SQL Server.
------------------------------------------------------------------------------*/

-- Example 6.1 : A to Z.
SELECT TenureName
FROM TenureTypes
ORDER BY TenureName;

-- Example 6.2 : Z to A.
SELECT TenureName
FROM TenureTypes
ORDER BY TenureName DESC;

-- Example 6.3 : numbers: lowest grant first (ASC is the default, shown explicitly).
SELECT SiteName, UnitPrice
FROM Sites
ORDER BY UnitPrice ASC;

-- Example 6.4 : highest grant first.
SELECT SiteName, UnitPrice
FROM Sites
ORDER BY UnitPrice DESC;

-- Example 6.5 : dates: oldest applicants first.
SELECT TOP (20) ApplicantID, FirstName, LastName, RegisteredDate
FROM Applicants
ORDER BY RegisteredDate;

-- Example 6.6 : newest first.
SELECT TOP (20) ApplicantID, FirstName, LastName, RegisteredDate
FROM Applicants
ORDER BY RegisteredDate DESC;

-- Example 6.7 : sort by an alias.
SELECT TOP (10) SiteName, UnitPrice * PlannedHomes AS GrantEnvelope
FROM Sites
ORDER BY GrantEnvelope DESC;

-- Example 6.8 : sort by an expression not in the SELECT list (allowed w/o DISTINCT).
SELECT TOP (10) SiteName
FROM Sites
ORDER BY LEN(SiteName) DESC;

-- Example 6.9 : sort by column position (1 = first selected column). Works, but
-- breaks silently if you reorder the SELECT list. Avoid in real code.
SELECT SiteName, UnitPrice
FROM Sites
ORDER BY 2 DESC;

-- Example 6.10 : NULLs first on ASC. CompletionDate is NULL for Submitted/Withdrawn/Rejected.
SELECT TOP (15) ApplicationID, Status, CompletionDate
FROM Applications
ORDER BY CompletionDate ASC;

-- Example 6.11 : NULLs last on DESC.
SELECT TOP (15) ApplicationID, Status, CompletionDate
FROM Applications
ORDER BY CompletionDate DESC;

-- Example 6.12 : tricky: put NULLs last while sorting ASC (CASE trick).
SELECT TOP (15) ApplicationID, Status, CompletionDate
FROM Applications
ORDER BY CASE WHEN CompletionDate IS NULL THEN 1 ELSE 0 END, CompletionDate;

-- Example 6.13 : tricky: text sorting is character by character, not numeric.
-- Phone is text; 1 / 10 / 2 order is alphabetical.
SELECT TOP (15) ApplicantID, Phone
FROM Applicants
WHERE Phone IS NOT NULL
ORDER BY Phone;

-- Example 6.14 : tricky: dirty names. Leading spaces sort BEFORE letters, so
-- '  john' floats to the top. Case does not matter in the default collation.
SELECT TOP (15) ApplicantID, FirstName
FROM Applicants
ORDER BY FirstName;

-- Example 6.15 : sort by a column you do not display.
SELECT SiteName
FROM Sites
ORDER BY PlannedHomes DESC;

/*---- Common mistakes : CONCEPT 6 ---------------------------------------------
-- Mistake 1: relying on "it came out sorted last time" without ORDER BY.
-- Mistake 2: ORDER BY 5 when there are only 3 columns ->
--   Msg 108: ORDER BY position number 5 is out of range.
SELECT SiteName, UnitPrice FROM Sites ORDER BY 5;
-- Mistake 3: ORDER BY in a subquery/view without TOP -> Msg 1033 error.
SELECT * FROM (SELECT SiteName FROM Sites ORDER BY SiteName) AS t;
-- Mistake 4: forgetting DESC needs to be repeated per column (module 2).
-- Mistake 5: expecting NULLs to be last in ASC order (they come first).
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 6 ------------------------------------------
Q1. Where do NULL values appear in  ORDER BY CompletionDate  (ASC)?
Q2. Phone values '9', '10', '2'. Sorted as text ASC, what is the order?
Q3. SELECT SiteName, UnitPrice FROM Sites ORDER BY 2 DESC; sorts by what?
Q4. Can you ORDER BY a column that is not in the SELECT list?
ANSWERS: Q1 = first. Q2 = '10', '2', '9'. Q3 = UnitPrice, high to low.
         Q4 = Yes (unless you use SELECT DISTINCT).
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 6 ------------------------------------------------------
List SiteName, PlannedHomes, Hectares for the 10 sites with the
FEWEST planned homes (above 0). Then change the query so that ties on PlannedHomes are broken by
SiteName A-Z.
----------------------------------------------------------------------------- */
-- Your answer here:

/*==============================================================================
  END OF MODULE 01. Next: module02_filtering.sql (WHERE, AND/OR/NOT, precedence)
==============================================================================*/
