USE HousingDelivery;
GO
/*==============================================================================
  MODULE 02 : FILTERING ROWS WITH WHERE
  Database  : HousingDelivery (SQL Server 2019+, run in SSMS)
  Topics    : 1. WHERE and comparison operators
              2. AND / OR / NOT
              3. Operator precedence and parentheses
              4. ORDER BY with multiple columns (ASC / DESC mix)

  HOW TO USE THIS FILE
    - Highlight ONE query at a time and press F5.
    - Guess the result BEFORE you run it. Then check the row count (bottom
      right of SSMS: "xxx rows") against what you expected.
    - "Common mistakes" blocks are commented out on purpose. Un-comment them
      one at a time (Ctrl+K, Ctrl+U) to see what goes wrong.
==============================================================================*/


/*##############################################################################
  CONCEPT 1 : WHERE AND COMPARISON OPERATORS
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  WHERE keeps only the rows for which the condition is TRUE. Rows where it is
  FALSE or UNKNOWN (that happens with NULL) are thrown away. Operators:
    =  equal        <> or !=  not equal     <  less      >  greater
    <= less or equal            >= greater or equal
  Text and dates go in single quotes. A literal apostrophe is doubled: 'O''Brien'.
  Safest date format is 'YYYYMMDD' (no dashes) because it works in every
  language setting. NULL can never be compared with = (that is module 3).
------------------------------------------------------------------------------*/

-- Example 1.1 : numbers. Sites with an average grant per home of exactly 0 (land-only sites, no grant).
SELECT SiteID, SiteName, UnitPrice
FROM Sites
WHERE UnitPrice = 0;

-- Example 1.2 : greater than.
SELECT SiteName, UnitPrice
FROM Sites
WHERE UnitPrice > 100000;

-- Example 1.3 : greater than or equal. Note the difference from 1.2 at the edge.
SELECT SiteName, UnitPrice
FROM Sites
WHERE UnitPrice >= 100000;

-- Example 1.4 : not equal. Two spellings, same result.
SELECT SiteName, UnitPrice FROM Sites WHERE UnitPrice <> 0;
SELECT SiteName, UnitPrice FROM Sites WHERE UnitPrice != 0;

-- Example 1.5 : text. Applicants in one country.
SELECT ApplicantID, FirstName, LastName, Country
FROM Applicants
WHERE Country = 'England';

-- Example 1.6 : text comparison is case-INsensitive by default collation.
-- 'england', 'ENGLAND' and 'England' all match.
SELECT ApplicantID, Country
FROM Applicants
WHERE Country = 'ENGLAND';

-- Example 1.7 : BIT column. 1 = true, 0 = false. Stalled sites.
SELECT SiteID, SiteName, PlannedHomes, IsStalled
FROM Sites
WHERE IsStalled = 1;

-- Example 1.8 : active applicants only.
SELECT ApplicantID, FirstName, LastName
FROM Applicants
WHERE IsActive = 1;

-- Example 1.9 : dates. Applications on one specific day (a date column, no time part).
-- TargetDate is DATE so equality is safe.
SELECT ApplicationID, ApplicationDate, TargetDate
FROM Applications
WHERE TargetDate = '20240229';

-- Example 1.10 : date ranges using >= and <. Applications from 2025 onward.
SELECT ApplicationID, ApplicantID, ApplicationDate
FROM Applications
WHERE ApplicationDate >= '20250101';

-- Example 1.11 : text comparison with < > works alphabetically.
-- Applicants whose last name sorts before 'C'.
SELECT ApplicantID, LastName
FROM Applicants
WHERE LastName < 'C'
ORDER BY LastName;

-- Example 1.12 : apostrophe in the data. Double the quote inside the string.
SELECT ApplicantID, FirstName, LastName
FROM Applicants
WHERE LastName = 'O''Brien';

-- Example 1.13 : comparing two columns. Applications completed before they were submitted
-- (a planted data error). Cast ApplicationDate to DATE to compare date to date.
SELECT ApplicationID, ApplicationDate, CompletionDate
FROM Applications
WHERE CompletionDate < CAST(ApplicationDate AS DATE);

-- Example 1.14 : comparing with a calculation. Low-density sites: fewer than
-- 5 planned homes per hectare (worth a second look by the planning team).
SELECT SiteID, SiteName, PlannedHomes, Hectares
FROM Sites
WHERE PlannedHomes < Hectares * 5;

-- Example 1.15 : tricky: stalled sites that still have planned homes (planted case).
SELECT SiteID, SiteName, PlannedHomes
FROM Sites
WHERE IsStalled = 1 AND PlannedHomes > 0;

-- Example 1.16 : tricky: negative Homes are reversals/clawbacks, zero is an empty funding line.
SELECT TOP (20) FundingLineID, ApplicationID, SiteID, Homes
FROM FundingLines
WHERE Homes <= 0;

-- Example 1.17 : tricky: a <> comparison silently drops NULL rows.
-- Region <> 'North West' does NOT return applicants whose Region is NULL.
-- Compare the two counts below: they do not add up to 10,000.
SELECT COUNT(*) AS RegionIsNorthWest      FROM Applicants WHERE Region = 'North West';
SELECT COUNT(*) AS RegionIsNotNorthWest   FROM Applicants WHERE Region <> 'North West';
SELECT COUNT(*) AS AllApplicants      FROM Applicants;

/*---- Common mistakes : CONCEPT 1 ---------------------------------------------
-- Mistake 1: using == (not valid in SQL) -> syntax error. SQL uses one =.
SELECT * FROM Sites WHERE UnitPrice == 0;
-- Mistake 2: forgetting quotes around text -> treats England as a column name.
--   Msg 207 Invalid column name 'England'.
SELECT * FROM Applicants WHERE Country = England;
-- Mistake 3: quoting a number is allowed but can force slow implicit conversion.
SELECT * FROM Sites WHERE UnitPrice = '0';
-- Mistake 4: ambiguous date strings like '03/04/2024' (March 4 or April 3?).
--   Use '20240304'.
-- Mistake 5: using = on a DATETIME2 column and expecting a whole day.
--   WHERE ApplicationDate = '20240229' only matches exactly midnight, 00:00:00.
SELECT ApplicationID, ApplicationDate FROM Applications WHERE ApplicationDate = '20240229';
-- Mistake 6: expecting <> to include NULL rows (see Example 1.17).
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 1 ------------------------------------------
Q1. Which is bigger:  COUNT where UnitPrice > 100000   or   COUNT where UnitPrice >= 100000?
Q2. If 3,000 applicants have Region = 'North West' and 3,000 have NULL Region, how many
    does  WHERE Region <> 'North West'  return from 10,000 applicants (assume 4,000 have
    other regions)?
Q3. What does  WHERE Country = 'uk'  return if rows contain 'UK' and 'United Kingdom'?
Q4. WHERE LastName = 'O''Brien'  - what string is being searched for?
ANSWERS: Q1 = the >= count (equal or bigger; same only if no site has a grant of exactly 100,000.00).
         Q2 = 4,000 (NULLs and 'North West' are both excluded). Q3 = the 'UK' rows
         (and 'uk'); NOT the 'United Kingdom' rows. Q4 = O'Brien.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 1 ------------------------------------------------------
1) List Staff in one Directorate (check real Directorate names first
   with SELECT DISTINCT Directorate FROM Staff;).
2) List Applications with AdminFee greater than 100.
3) List Applications where Status is 'Withdrawn'.
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 2 : AND / OR / NOT
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  AND   : both conditions must be true (narrows the result).
  OR    : at least one must be true (widens the result).
  NOT   : flips a condition (true becomes false).
  Think of AND as "and also", OR as "or else", NOT as "except".
  Be careful: NOT and OR with NULL values give UNKNOWN, and UNKNOWN rows are
  dropped by WHERE.
------------------------------------------------------------------------------*/

-- Example 2.1 : AND. Active Key worker applicants.
SELECT ApplicantID, FirstName, LastName, HouseholdType
FROM Applicants
WHERE HouseholdType = 'Key worker' AND IsActive = 1;

-- Example 2.2 : OR. Applications that are Withdrawn or Rejected.
SELECT ApplicationID, Status
FROM Applications
WHERE Status = 'Withdrawn' OR Status = 'Rejected';

-- Example 2.3 : NOT. Every application that is not Completed.
SELECT ApplicationID, Status
FROM Applications
WHERE NOT Status = 'Completed';

-- Example 2.4 : the neater way to write NOT with equality.
SELECT ApplicationID, Status
FROM Applications
WHERE Status <> 'Completed';

-- Example 2.5 : AND on numbers. Mid-range grant: average grant per home between 20,000 and 50,000 GBP.
SELECT SiteName, UnitPrice
FROM Sites
WHERE UnitPrice >= 20000 AND UnitPrice <= 50000;

-- Example 2.6 : three conditions with AND.
SELECT SiteID, SiteName, UnitPrice, PlannedHomes
FROM Sites
WHERE IsStalled = 0 AND PlannedHomes < 20 AND UnitPrice > 0;

-- Example 2.7 : OR on different columns. No planned homes OR already stalled.
SELECT SiteID, SiteName, PlannedHomes, IsStalled
FROM Sites
WHERE PlannedHomes = 0 OR IsStalled = 1;

-- Example 2.8 : NOT with AND. Applicants who are not First-time buyers and are active.
SELECT ApplicantID, HouseholdType, IsActive
FROM Applicants
WHERE NOT HouseholdType = 'First-time buyer' AND IsActive = 1;

-- Example 2.9 : NOT around a whole condition needs brackets.
SELECT ApplicantID, HouseholdType, IsActive
FROM Applicants
WHERE NOT (HouseholdType = 'First-time buyer' OR IsActive = 0);

-- Example 2.10 : date range with AND (half-open: >= start AND < next start).
-- All applications submitted in FY 2024/25 (1 April 2024 to 31 March 2025), at any time of day.
SELECT ApplicationID, ApplicationDate
FROM Applications
WHERE ApplicationDate >= '20240401' AND ApplicationDate < '20250401';

-- Example 2.11 : AND across two tables' worth of ideas in one table. Applications
-- for properties in one region that completed late: CompletionDate after TargetDate.
SELECT ApplicationID, PropertyRegion, TargetDate, CompletionDate
FROM Applications
WHERE CompletionDate > TargetDate AND PropertyRegion = 'North West';

-- Example 2.12 : OR of many equalities (module 3 shows IN, the shorter way).
SELECT ApplicantID, Region
FROM Applicants
WHERE Region = 'North West' OR Region = 'North East' OR Region = 'Yorkshire and The Humber';

-- Example 2.13 : tricky: applications with a waived admin fee OR a missing admin fee.
-- AdminFee = 0 is "waived", AdminFee IS NULL is "unknown". Both matter.
SELECT TOP (30) ApplicationID, AdminFee
FROM Applications
WHERE AdminFee = 0 OR AdminFee IS NULL;

-- Example 2.14 : tricky: "not withdrawn" applications. Status is never NULL per spec,
-- so NOT works, but see what happens with a nullable column:
-- Region <> 'North West' (Example 1.17) lost the NULLs; this keeps them.
SELECT COUNT(*) AS NotWestIncludingUnknown
FROM Applicants
WHERE Region <> 'North West' OR Region IS NULL;

-- Example 2.15 : tricky: online applications (no staff member) that are still Submitted.
SELECT ApplicationID, ApplicationDate, Status, StaffID
FROM Applications
WHERE StaffID IS NULL AND Status = 'Submitted';

/*---- Common mistakes : CONCEPT 2 ---------------------------------------------
-- Mistake 1: writing the column once and listing values (valid in English only).
--   Msg 4145 (non-Boolean expression) or a wrong result.
SELECT * FROM Applications WHERE Status = 'Withdrawn' OR 'Rejected';
-- Mistake 2: using AND when you mean OR.
--   Status = 'Withdrawn' AND Status = 'Rejected' is never true: 0 rows.
SELECT * FROM Applications WHERE Status = 'Withdrawn' AND Status = 'Rejected';
-- Mistake 3: "NOT = 'x'" in a way that drops NULL rows silently.
-- Mistake 4: forgetting that BETWEEN-like ranges must be AND, not OR:
--   ApplicationDate >= '20240101' OR ApplicationDate < '20250101' is ALWAYS true.
SELECT COUNT(*) FROM Applications WHERE ApplicationDate >= '20240101' OR ApplicationDate < '20250101';
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 2 ------------------------------------------
Q1. A=TRUE, B=FALSE. What are A AND B, A OR B, NOT A, NOT B?
Q2. Does adding another  AND  condition make the result bigger or smaller?
Q3. Does adding another  OR  condition make the result bigger or smaller?
Q4. WHERE Status = 'Approved' AND Status = 'Completed' returns how many rows?
ANSWERS: Q1 = FALSE, TRUE, FALSE, TRUE. Q2 = smaller (or equal).
         Q3 = bigger (or equal). Q4 = 0, one cell cannot hold two values.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 2 ------------------------------------------------------
1) Active Home mover applicants.
2) Sites that are IsStalled = 1 OR have PlannedHomes = 0.
3) Applications that are not Withdrawn and have an AdminFee above 50.
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 3 : OPERATOR PRECEDENCE AND PARENTHESES
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  When AND and OR appear together, SQL does NOT read left to right. Order is:
      1) NOT     2) AND     3) OR
  Just like multiplication before addition in maths. So
      A OR B AND C   means   A OR (B AND C)
  Parentheses override the order. ALWAYS use them when mixing AND and OR, even
  when you think you remember the rule. This is the #1 cause of silent wrong
  results in filters.
------------------------------------------------------------------------------*/

-- Example 3.1 : maths warm up. AND is like *, OR is like +.
SELECT 2 + 3 * 4 AS NoBrackets, (2 + 3) * 4 AS WithBrackets;

-- Example 3.2 : WITHOUT brackets. Reads as: Key worker OR (Home mover AND active).
-- It returns ALL Key worker applicants, even inactive ones.
SELECT ApplicantID, HouseholdType, IsActive
FROM Applicants
WHERE HouseholdType = 'Key worker' OR HouseholdType = 'Home mover' AND IsActive = 1;

-- Example 3.3 : WITH brackets. Active applicants who are Key worker or Home mover.
SELECT ApplicantID, HouseholdType, IsActive
FROM Applicants
WHERE (HouseholdType = 'Key worker' OR HouseholdType = 'Home mover') AND IsActive = 1;

-- Example 3.4 : prove the difference with counts.
SELECT
  (SELECT COUNT(*) FROM Applicants
    WHERE HouseholdType = 'Key worker' OR HouseholdType = 'Home mover' AND IsActive = 1) AS NoBrackets,
  (SELECT COUNT(*) FROM Applicants
    WHERE (HouseholdType = 'Key worker' OR HouseholdType = 'Home mover') AND IsActive = 1) AS WithBrackets;

-- Example 3.5 : sites: low grant OR no planned homes, AND not stalled.
SELECT SiteID, SiteName, UnitPrice, PlannedHomes, IsStalled
FROM Sites
WHERE (UnitPrice < 20000 OR PlannedHomes = 0) AND IsStalled = 0;

-- Example 3.6 : the same words without brackets means something different.
SELECT SiteID, SiteName, UnitPrice, PlannedHomes, IsStalled
FROM Sites
WHERE UnitPrice < 20000 OR PlannedHomes = 0 AND IsStalled = 0;

-- Example 3.7 : NOT binds tightest. NOT A AND B = (NOT A) AND B.
SELECT COUNT(*) AS NotSubmittedAndIncomplete
FROM Applications
WHERE NOT Status = 'Submitted' AND CompletionDate IS NULL;

-- Example 3.8 : NOT over a bracketed group flips the whole group.
SELECT COUNT(*) AS Others
FROM Applications
WHERE NOT (Status = 'Submitted' AND CompletionDate IS NULL);

-- Example 3.9 : De Morgan's law. These two are equivalent:
--   NOT (A OR B)  =  NOT A AND NOT B
SELECT COUNT(*) AS V1 FROM Applications WHERE NOT (Status = 'Withdrawn' OR Status = 'Rejected');
SELECT COUNT(*) AS V2 FROM Applications WHERE Status <> 'Withdrawn' AND Status <> 'Rejected';

-- Example 3.10 : financial year and status combination. Brackets make the intent clear.
SELECT ApplicationID, ApplicationDate, Status
FROM Applications
WHERE (Status = 'Withdrawn' OR Status = 'Rejected')
  AND ApplicationDate >= '20240401' AND ApplicationDate < '20250401';

-- Example 3.11 : the same without brackets leaks other financial years' Rejected applications.
SELECT COUNT(*) AS Leaky
FROM Applications
WHERE Status = 'Withdrawn' OR Status = 'Rejected'
  AND ApplicationDate >= '20240401' AND ApplicationDate < '20250401';

-- Example 3.12 : two groups ORed together, each group ANDed inside.
SELECT ApplicantID, Region, HouseholdType, IsActive
FROM Applicants
WHERE (Region = 'London' AND HouseholdType = 'Key worker')
   OR (Region = 'South East' AND HouseholdType = 'First-time buyer');

-- Example 3.13 : a long filter written one condition per line. Easier to read,
-- easier to comment out a line while testing.
SELECT SiteID, SiteName, UnitPrice, PlannedHomes
FROM Sites
WHERE IsStalled = 0
  AND (UnitPrice BETWEEN 10000 AND 80000)
  AND (PlannedHomes > 0 OR Hectares > 1);

-- Example 3.14 : tricky: precedence plus the dirty country spellings.
-- Without brackets this returns ALL 'England' rows (inactive too) plus only the
-- ACTIVE 'United Kingdom' rows.
SELECT ApplicantID, Country, IsActive
FROM Applicants
WHERE Country = 'England' OR Country = 'United Kingdom' AND IsActive = 1;

-- Example 3.15 : tricky: fixed version.
SELECT ApplicantID, Country, IsActive
FROM Applicants
WHERE (Country = 'England' OR Country = 'United Kingdom') AND IsActive = 1;

/*---- Common mistakes : CONCEPT 3 ---------------------------------------------
-- Mistake 1: mixing AND/OR with no brackets (Examples 3.2, 3.6, 3.11, 3.14).
-- Mistake 2: brackets in the wrong place:
--   WHERE HouseholdType = 'Key worker' OR (HouseholdType = 'Home mover' AND IsActive = 1)
--   is the SAME as 3.2 - brackets that match the default order add no safety
--   unless they match what you actually mean.
-- Mistake 3: forgetting to check the row count. Always sanity-check: "does the
--   number make sense for the business question?"
-- Mistake 4: unbalanced parentheses -> Msg 102 Incorrect syntax.
SELECT * FROM Applicants WHERE (HouseholdType = 'Key worker' OR HouseholdType = 'Home mover' AND IsActive = 1;
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 3 ------------------------------------------
Q1. SELECT 2 + 3 * 4;  and  SELECT (2 + 3) * 4;  results?
Q2. TRUE OR FALSE AND FALSE  evaluates to?
Q3. (TRUE OR FALSE) AND FALSE  evaluates to?
Q4. Is  NOT A AND B  the same as  NOT (A AND B)?
ANSWERS: Q1 = 14 and 20. Q2 = TRUE (FALSE AND FALSE first = FALSE; TRUE OR FALSE = TRUE).
         Q3 = FALSE. Q4 = No. The first is (NOT A) AND B.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 3 ------------------------------------------------------
Business question: "Show Withdrawn or Rejected applications submitted in FY 2023/24 (>= 20230401, < 20240401) with
AdminFee over 20." Write it twice - once without brackets, once with. Compare
the row counts and explain the difference.
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 4 : ORDER BY WITH MULTIPLE COLUMNS (ASC / DESC)
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  List several columns after ORDER BY, separated by commas. SQL sorts by the
  first column; rows that tie are sorted by the second; and so on. ASC / DESC
  is set per column, so you can mix them: ORDER BY Country ASC, Salary DESC.
  A DESC applies ONLY to the column right before it.
------------------------------------------------------------------------------*/

-- Example 4.1 : two columns, both ASC. Applicants by country, then city.
SELECT TOP (50) ApplicantID, Country, City, LastName
FROM Applicants
ORDER BY Country, City;

-- Example 4.2 : mixed directions. Country A-Z, but most recently registered first inside.
SELECT TOP (50) ApplicantID, Country, RegisteredDate
FROM Applicants
ORDER BY Country ASC, RegisteredDate DESC;

-- Example 4.3 : three columns.
SELECT TOP (50) ApplicantID, Country, HouseholdType, LastName
FROM Applicants
ORDER BY Country, HouseholdType, LastName;

-- Example 4.4 : staff: directorate A-Z, highest paid first inside each.
SELECT FirstName, LastName, Directorate, Salary
FROM Staff
ORDER BY Directorate ASC, Salary DESC;

-- Example 4.5 : break salary ties with a second sort key (planted tied salaries).
SELECT FirstName, LastName, Salary
FROM Staff
ORDER BY Salary DESC, LastName ASC, FirstName ASC;

-- Example 4.6 : filter AND sort. Active Key worker applicants, sorted.
SELECT TOP (50) ApplicantID, Country, LastName, FirstName
FROM Applicants
WHERE HouseholdType = 'Key worker' AND IsActive = 1
ORDER BY Country, LastName, FirstName;

-- Example 4.7 : sites: tenure type, then highest grant first.
SELECT SiteID, TenureTypeID, SiteName, UnitPrice
FROM Sites
ORDER BY TenureTypeID, UnitPrice DESC;

-- Example 4.8 : tricky: TenureTypeID is NULL for ~5 sites -> they sort FIRST.
-- Scroll the top of the result from Example 4.7.

-- Example 4.9 : tricky: push NULL tenure types to the bottom.
SELECT SiteID, TenureTypeID, SiteName, UnitPrice
FROM Sites
ORDER BY CASE WHEN TenureTypeID IS NULL THEN 1 ELSE 0 END, TenureTypeID, UnitPrice DESC;

-- Example 4.10 : applications newest first, ties on date broken by ApplicationID.
SELECT TOP (30) ApplicationID, ApplicationDate, Status
FROM Applications
ORDER BY ApplicationDate DESC, ApplicationID DESC;

-- Example 4.11 : tricky: sorting by DATE only. ApplicationDate has a time part, so
-- sorting by it alone mixes times. Cast to DATE then apply a second key.
SELECT TOP (30) ApplicationID, ApplicationDate, AdminFee
FROM Applications
ORDER BY CAST(ApplicationDate AS DATE) DESC, AdminFee DESC;

-- Example 4.12 : mixed positions (avoid in real code, but legal).
SELECT TOP (20) Country, City, LastName
FROM Applicants
ORDER BY 1 ASC, 2 DESC;

-- Example 4.13 : sort by a calculated alias, then by name for ties.
SELECT TOP (20) SiteName, UnitPrice * PlannedHomes AS GrantEnvelope
FROM Sites
WHERE IsStalled = 1
ORDER BY GrantEnvelope DESC, SiteName;

-- Example 4.14 : tricky: clean sort of dirty names. '  john' has leading
-- spaces so it floats to the top. Trim inside ORDER BY to fix the order.
SELECT TOP (30) ApplicantID, FirstName, LastName
FROM Applicants
ORDER BY LTRIM(RTRIM(LastName)), LTRIM(RTRIM(FirstName));

/*---- Common mistakes : CONCEPT 4 ---------------------------------------------
-- Mistake 1: thinking one DESC covers all columns.
--   ORDER BY Country, RegisteredDate DESC   -> Country is still ASC!
-- Mistake 2: repeating a column: ORDER BY Country, Country DESC. The second is
--   ignored (and SQL Server raises Msg 169: column specified more than once).
SELECT Country FROM Applicants ORDER BY Country, Country DESC;
-- Mistake 3: sorting on a text-number column and expecting numeric order.
-- Mistake 4: putting ORDER BY before WHERE -> syntax error. Order of clauses:
--   SELECT ... FROM ... WHERE ... ORDER BY.
SELECT * FROM Sites ORDER BY UnitPrice WHERE UnitPrice > 10;
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 4 ------------------------------------------
Q1. ORDER BY Directorate, Salary DESC  : which column decides the order of two
    rows from different directorates?
Q2. Two staff share the same Directorate and Salary. Which key decides
    their order if you add , LastName ?
Q3. In  ORDER BY TenureTypeID, UnitPrice DESC  where do NULL TenureTypeIDs appear?
Q4. In  ORDER BY a DESC, b  is b sorted ascending or descending?
ANSWERS: Q1 = Directorate. Q2 = LastName (A-Z). Q3 = at the top (NULL first in ASC).
         Q4 = ascending (DESC belongs to a only).
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 4 ------------------------------------------------------
List Applications for 2025 (>= 20250101 and < 20260101) sorted by Status A-Z, then by
AdminFee highest first, then by ApplicationID. Show ApplicationID, Status, AdminFee.
Where do NULL admin fees appear inside each status? Move them last with CASE.
----------------------------------------------------------------------------- */
-- Your answer here:

/*==============================================================================
  END OF MODULE 02. Next: module03_more_filters.sql
==============================================================================*/
