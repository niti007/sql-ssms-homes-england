USE HousingDelivery;
GO
/* ============================================================================
   MODULE 04 - FUNCTIONS: AGGREGATES, STRINGS, DATES, CONVERSIONS
   Database : HousingDelivery (see SPEC.md)      Target : SQL Server 2019+ / SSMS
   NetFunding  : Homes * GrantPerHome * (1 - ClawbackRate)

   HOW TO USE THIS FILE
   - Highlight ONE example at a time and press F5. (Running the whole file
     works too, but the output tabs get long.)
   - Lines starting with  -- ERROR:  show code that FAILS on purpose. They are
     commented out. Un-comment one, run it, read the error, comment it again.
   - Every "Predict the output" block: write your answer down BEFORE running.

   CONCEPTS
     A. Aggregate functions (MIN MAX SUM AVG COUNT)
     B. NULLs inside aggregates + ISNULL / COALESCE / NULLIF
     C. AVG and integer division
     D. String functions: the core set
     E. LEN vs DATALENGTH, TRIM, and CONCAT vs + with NULL
     F. Date functions
     G. CAST, CONVERT, FORMAT
   ============================================================================ */


/* ############################################################################
   CONCEPT A : AGGREGATE FUNCTIONS
   ############################################################################
   An aggregate function takes MANY rows and returns ONE value.
   COUNT counts rows, SUM adds, AVG averages, MIN/MAX find the smallest/biggest.
   Without GROUP BY (Module 05) the whole table is treated as one big group,
   so you always get exactly one output row.
   ########################################################################## */

-- A.1  Count every row in a table
SELECT COUNT(*) AS TotalApplications FROM dbo.Applications;

-- A.2  Several aggregates in one pass
SELECT COUNT(*)       AS Sites,
       MIN(UnitPrice) AS LowestGrantPerHome,
       MAX(UnitPrice) AS HighestGrantPerHome,
       AVG(UnitPrice) AS AvgGrantPerHome
FROM dbo.Sites;

-- A.3  SUM of a column
SELECT SUM(Homes) AS HomesFunded FROM dbo.FundingLines;

-- A.4  SUM of an expression: total net funding (the official formula)
SELECT SUM(Homes * GrantPerHome * (1 - ClawbackRate)) AS TotalNetFunding
FROM dbo.FundingLines;

-- A.5  Aggregates respect WHERE (WHERE filters rows BEFORE they are aggregated)
SELECT COUNT(*) AS CancelledApplications
FROM dbo.Applications
WHERE Status = 'Withdrawn';

-- A.6  MIN / MAX work on dates and text too
SELECT MIN(ApplicationDate) AS FirstApplication,
       MAX(ApplicationDate) AS LastApplication           -- note: future-dated applications exist!
FROM dbo.Applications;

SELECT MIN(LastName) AS FirstAlphabetically,
       MAX(LastName) AS LastAlphabetically
FROM dbo.Applicants;

-- A.7  COUNT(DISTINCT ...) counts unique values
SELECT COUNT(*)                  AS ApplicationRows,
       COUNT(DISTINCT ApplicantID) AS ApplicantsWhoApplied
FROM dbo.Applications;

-- A.8  SUM(DISTINCT) is rarely what you want - compare
SELECT SUM(UnitPrice)          AS SumAll,
       SUM(DISTINCT UnitPrice) AS SumOfDistinctPrices   -- each price counted once
FROM dbo.Sites;

-- A.9  Aggregate over a filtered set: land-only sites and stalled sites
SELECT COUNT(*) AS LandOnlySites
FROM dbo.Sites
WHERE UnitPrice = 0;

SELECT SUM(PlannedHomes) AS HomesOnStalledSites
FROM dbo.Sites
WHERE IsStalled = 1 AND PlannedHomes > 0;

-- A.10 Total planned grant on live sites (grant per home x planned homes)
SELECT SUM(UnitPrice * PlannedHomes) AS PlannedGrant
FROM dbo.Sites
WHERE IsStalled = 0;

-- A.11 NetFunding of one application (ApplicationID 1) - aggregate + WHERE
SELECT ApplicationID,
       COUNT(*)                                   AS Lines,
       SUM(Homes * GrantPerHome * (1 - ClawbackRate)) AS ApplicationNetFunding
FROM dbo.FundingLines
WHERE ApplicationID = 1
GROUP BY ApplicationID;           -- GROUP BY is previewed here; full lesson in Module 05

-- A.12 Aggregates of an EMPTY set: COUNT gives 0, the others give NULL
SELECT COUNT(*)       AS Cnt,      -- 0
       SUM(AdminFee)   AS SumF,     -- NULL
       MAX(AdminFee)   AS MaxF      -- NULL
FROM dbo.Applications
WHERE ApplicationID < 0;

-- A.13 Mixing aggregate and non-aggregate columns is NOT allowed
-- ERROR: SELECT SiteName, MAX(UnitPrice) FROM dbo.Sites;   -- grant per home
-- "Column 'SiteName' is invalid in the select list because it is not
--  contained in either an aggregate function or the GROUP BY clause."
-- Fix to "which site has the highest grant per home?" with TOP, not with MAX:
SELECT TOP (1) SiteName, UnitPrice
FROM dbo.Sites
ORDER BY UnitPrice DESC;

/* ---- Common mistakes (A) ---------------------------------------------------
   1. Selecting a plain column next to an aggregate without GROUP BY (A.13).
   2. Using WHERE to filter on an aggregate:  WHERE SUM(x) > 10  -> error.
      Aggregates are filtered with HAVING (Module 05).
   3. Forgetting that MAX(ApplicationDate) includes future-dated test applications.
   4. Writing SUM(Homes * GrantPerHome) and forgetting (1 - ClawbackRate).
   5. Thinking COUNT(*) and COUNT(col) are the same (see Concept B).
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (A) ------------------------------------------------
   Q1. How many rows does this return?   SELECT MAX(UnitPrice) FROM dbo.Sites;
   Q2. SELECT COUNT(*) FROM dbo.Applications WHERE 1 = 0;  returns 0 rows or one row?
   Q3. Will  SELECT SUM(DISTINCT Homes) FROM dbo.FundingLines;  be bigger or
       smaller than SUM(Homes)? (Hint: how many different quantities exist?)
   Answers: Q1 one row. Q2 ONE row containing 0. Q3 far smaller.
   ---------------------------------------------------------------------------- */

/* ---- Try it (A) ------------------------------------------------------------
   Return in ONE query: number of applicants, earliest RegisteredDate, latest
   RegisteredDate, and number of active applicants (IsActive = 1).
   Hint: SUM(CAST(IsActive AS INT)) works, or COUNT with a WHERE in a 2nd query.
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT B : NULLs INSIDE AGGREGATES, ISNULL, COALESCE, NULLIF
   ############################################################################
   NULL means "unknown", not zero. Aggregates SKIP NULLs (except COUNT(*)).
   ISNULL(x, fallback) and COALESCE(a, b, c, ...) replace NULL with a value.
   NULLIF(a, b) does the reverse: returns NULL when a equals b.
   Planted data: ~8% Email NULL, some Email = '' (empty, NOT null),
   ~30% Region NULL, some Applications.AdminFee NULL and some 0.
   ########################################################################## */

-- B.1  COUNT(*) vs COUNT(column) on Applicants
SELECT COUNT(*)      AS AllApplicants,
       COUNT(Email)  AS HaveEmail,       -- skips NULL (but counts '' !)
       COUNT(Phone)  AS HavePhone,
       COUNT(Region) AS HaveRegion
FROM dbo.Applicants;

-- B.2  How many are missing each? (two ways)
SELECT COUNT(*) - COUNT(Email) AS MissingEmail_Way1,
       SUM(CASE WHEN Email IS NULL THEN 1 ELSE 0 END) AS MissingEmail_Way2
FROM dbo.Applicants;

-- B.3  The empty-string trap: '' is not NULL
SELECT SUM(CASE WHEN Email IS NULL THEN 1 ELSE 0 END) AS NullEmail,
       SUM(CASE WHEN Email = ''    THEN 1 ELSE 0 END) AS EmptyEmail
FROM dbo.Applicants;

-- B.4  Both kinds of "no email" in one rule, using NULLIF
SELECT COUNT(NULLIF(Email, '')) AS RealEmails       -- '' becomes NULL -> skipped
FROM dbo.Applicants;

-- B.5  AVG skips NULL: the AdminFee trap
SELECT COUNT(*)                    AS Applications,
       COUNT(AdminFee)              AS ApplicationsWithAdminFee,
       AVG(AdminFee)                AS AvgAdminFee_SkipsNull,
       SUM(AdminFee) / COUNT(*)     AS AvgAdminFee_NullAsZero,
       AVG(ISNULL(AdminFee, 0))     AS AvgAdminFee_ViaIsnull
FROM dbo.Applications;
-- Which is "right"? Business decision: is NULL "no fee charged" (=0) or "unknown"?
-- AdminFee = 0 is KNOWN-free; NULL is UNKNOWN. Skipping NULL is usually correct.

-- B.6  SUM over NULLs: skipped, but all-NULL group gives NULL not 0
SELECT SUM(AdminFee)               AS SumAdminFee,
       SUM(ISNULL(AdminFee, 0))    AS SumAdminFeeSafe,
       COALESCE(SUM(AdminFee), 0)  AS SumOrZero           -- wrap the aggregate
FROM dbo.Applications
WHERE AdminFee IS NULL;     -- only NULL rows -> SUM is NULL, wrapped version is 0

-- B.7  ISNULL for display: Region
SELECT TOP (10) ApplicantID, City, ISNULL(Region, 'n/a') AS Region
FROM dbo.Applicants
ORDER BY ApplicantID;

-- B.8  COALESCE with several fallbacks: best contact method
SELECT TOP (15) ApplicantID,
       COALESCE(NULLIF(Email, ''), Phone, 'NO CONTACT') AS BestContact
FROM dbo.Applicants
ORDER BY ApplicantID;

-- B.9  ISNULL vs COALESCE: result type differs!
SELECT ISNULL(CAST(NULL AS VARCHAR(3)), 'abcdefghij') AS A2,   -- truncated to 'abc'
       COALESCE(CAST(NULL AS VARCHAR(3)), 'abcdefghij') AS A3; -- 'abcdefghij'
-- ISNULL takes the type of the FIRST argument; COALESCE uses the highest-precedence type.

-- B.10 COALESCE takes many arguments, ISNULL only two (and ISNULL is T-SQL only)
SELECT COALESCE(NULL, NULL, 3, 4) AS FirstNonNull;

-- B.11 NULLIF to avoid divide-by-zero: grant per planned home
SELECT TOP (10) SiteID, SiteName, UnitPrice, PlannedHomes,
       UnitPrice / NULLIF(PlannedHomes, 0) AS GrantPerPlannedHome   -- NULL, not an error
FROM dbo.Sites
ORDER BY PlannedHomes;
-- ERROR (if some PlannedHomes = 0): UnitPrice / PlannedHomes -> Divide by zero

-- B.12 NULL in arithmetic poisons the result
SELECT TOP (10) ApplicationID, AdminFee,
       AdminFee + 5            AS PlusFive,        -- NULL stays NULL
       ISNULL(AdminFee, 0) + 5 AS PlusFiveSafe
FROM dbo.Applications
ORDER BY AdminFee;             -- NULLs sort first in ascending application

-- B.13 NULL comparisons: = NULL never matches
SELECT COUNT(*) AS WrongWay FROM dbo.Applications WHERE AdminFee = NULL;     -- 0
SELECT COUNT(*) AS RightWay FROM dbo.Applications WHERE AdminFee IS NULL;

-- B.14 Tenure-less sites: COALESCE a lookup column
SELECT COUNT(*) AS SitesNoTenure
FROM dbo.Sites
WHERE TenureTypeID IS NULL;
SELECT TOP (5) SiteName, COALESCE(CAST(TenureTypeID AS VARCHAR(10)), 'No tenure') AS Tenure
FROM dbo.Sites
WHERE TenureTypeID IS NULL;      -- CAST needed so both sides of COALESCE are text

/* ---- Common mistakes (B) ---------------------------------------------------
   1. WHERE col = NULL  (always empty). Use IS NULL / IS NOT NULL.
   2. Assuming AVG(AdminFee) divides by all applications. It divides by non-NULL rows.
   3. Treating '' as NULL. They need different tests (or NULLIF(col,'')).
   4. ISNULL(varchar_col, 'long fallback') silently truncating (B.9).
   5. COALESCE(int_col, 'none') -> conversion error: types must be compatible.
   6. Forgetting that COUNT(*) counts rows with NULLs but COUNT(col) does not.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (B) ------------------------------------------------
   Table T has Score values: 10, 20, NULL, 30.
   Q1. COUNT(*) ?   Q2. COUNT(Score) ?   Q3. AVG(Score) ?
   Q4. SUM(Score) / COUNT(*) ?   Q5. AVG(ISNULL(Score,0)) ?
   Answers: 4 ; 3 ; 20 ; 15 ; 15.
   Q6. SELECT COALESCE(NULL, 'a', 'b')   -> 'a'
   Q7. SELECT NULLIF(5, 5)               -> NULL     SELECT NULLIF(5, 6) -> 5
   ---------------------------------------------------------------------------- */

/* ---- Try it (B) ------------------------------------------------------------
   Report: total applications, applications with AdminFee NULL, applications with AdminFee = 0,
   and average admin fee of applications that have a real positive admin fee.
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT C : AVG AND INTEGER DIVISION
   ############################################################################
   If every input to / or AVG is an INTEGER, SQL Server returns an INTEGER and
   throws the decimals away (truncates, it does NOT round). Fix: make one side
   decimal (multiply by 1.0, or CAST).
   ########################################################################## */

-- C.1  The classic
SELECT 7 / 2      AS IntDivision,      -- 3
       7 / 2.0    AS DecimalDivision,  -- 3.500000
       7 * 1.0 / 2 AS AlsoDecimal;     -- 3.5

-- C.2  Negative numbers truncate toward zero
SELECT -7 / 2 AS NegInt, 7 % 2 AS Remainder;

-- C.3  AVG of an INT column returns INT
SELECT AVG(Homes)       AS AvgQty_Int,       -- truncated!
       AVG(Homes * 1.0) AS AvgQty_Decimal,
       AVG(CAST(Homes AS DECIMAL(10,2))) AS AvgQty_Cast
FROM dbo.FundingLines;

-- C.4  AVG on DECIMAL columns keeps decimals
SELECT AVG(UnitPrice) AS AvgGrantPerHome FROM dbo.Sites;       -- DECIMAL(10,2) -> more scale

-- C.5  Percentage with INTs: the "always 0 or 1" bug
SELECT COUNT(CASE WHEN Status = 'Withdrawn' THEN 1 END) / COUNT(*)        AS WrongPct,   -- 0
       100.0 * COUNT(CASE WHEN Status = 'Withdrawn' THEN 1 END) / COUNT(*) AS WithdrawnPct
FROM dbo.Applications;

-- C.6  Rounding the result nicely
SELECT ROUND(100.0 * SUM(CASE WHEN Status = 'Rejected' THEN 1 ELSE 0 END) / COUNT(*), 2) AS RejectedPct
FROM dbo.Applications;

-- C.7  CEILING / FLOOR / ROUND on a decimal
SELECT CEILING(7 / 2.0) AS Ceil,   -- 4
       FLOOR(7 / 2.0)   AS Fl,     -- 3
       ROUND(2.567, 2)  AS R2,     -- 2.570
       ROUND(1250, -2)  AS R100;   -- 1300

-- C.8  Average planned homes per site, three ways
SELECT AVG(PlannedHomes)                       AS IntAvg,
       AVG(PlannedHomes * 1.0)                 AS DecAvg,
       CAST(AVG(PlannedHomes * 1.0) AS DECIMAL(10,1)) AS Pretty
FROM dbo.Sites;

-- C.9  Average line net funding, ignoring zero-grant, fully clawed-back and reversal lines
SELECT AVG(Homes * GrantPerHome * (1 - ClawbackRate)) AS AvgLineNetFunding
FROM dbo.FundingLines
WHERE Homes > 0 AND ClawbackRate < 1;

-- C.10 Weighted average vs simple average of ClawbackRate (weight = gross grant)
SELECT AVG(ClawbackRate)                                      AS SimpleAvgClawback,
       1 - SUM(Homes * GrantPerHome * (1 - ClawbackRate))
           / NULLIF(SUM(Homes * GrantPerHome), 0)         AS WeightedAvgClawback
FROM dbo.FundingLines
WHERE Homes > 0;

/* ---- Common mistakes (C) ---------------------------------------------------
   1. AVG(int_col) and expecting decimals.
   2. count1 / count2 for a percentage (both INT -> 0).
   3. Casting AFTER the division: CAST(7/2 AS DECIMAL(5,2)) = 3.00 (too late).
   4. Using ROUND when you wanted to cut display decimals only - fine in SELECT,
      but never ROUND inside a SUM unless the business says so.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (C) ------------------------------------------------
   Q1. SELECT 10 / 4;            Q2. SELECT 10 / 4.0;      Q3. SELECT 10 % 4;
   Q4. AVG of the INT values 1, 2 (just those two)?   Q5. SELECT 1 / 3 * 3.0;
   Answers: 2 ; 2.500000 ; 2 ; 1 ; 0.0 (1/3 = 0 first!).
   ---------------------------------------------------------------------------- */

/* ---- Try it (C) ------------------------------------------------------------
   What percent of FundingLines lines have ClawbackRate = 1.00? Show it with
   2 decimals. Then repeat for lines with negative Homes.
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT D : STRING FUNCTIONS - THE CORE SET
   ############################################################################
   Text is messy. These functions clean and slice it:
   UPPER/LOWER, LEFT/RIGHT, SUBSTRING(text, start, length) [1-based!],
   REPLACE, CHARINDEX(find, text) [returns 0 if not found], REVERSE, TRIM.
   ########################################################################## */

-- D.1  Case
SELECT TOP (10) FirstName, UPPER(FirstName) AS Up, LOWER(FirstName) AS Low
FROM dbo.Applicants
ORDER BY ApplicantID;

-- D.2  Find the messy names (leading/trailing spaces, SHOUTING)
SELECT TOP (15) ApplicantID, '[' + FirstName + ']' AS FirstBracketed, LastName
FROM dbo.Applicants
WHERE FirstName <> LTRIM(RTRIM(FirstName))        -- spaces at either end
ORDER BY ApplicantID;

-- D.3  LEFT / RIGHT
SELECT TOP (5) SiteName, LEFT(SiteName, 3) AS First3, RIGHT(SiteName, 3) AS Last3
FROM dbo.Sites
ORDER BY SiteID;

-- D.4  SUBSTRING is 1-based
SELECT SUBSTRING('HomesEngland', 1, 5) AS Homes_,
       SUBSTRING('HomesEngland', 6, 7) AS England_,
       SUBSTRING('HomesEngland', 0, 5) AS StartZero;   -- 'Home' : position 0 eats a character

-- D.5  CHARINDEX finds a position (0 = not found)
SELECT CHARINDEX('@', 'tom@mail.com')  AS AtPos,       -- 4
       CHARINDEX('#', 'tom@mail.com')  AS NotFound;    -- 0

-- D.6  Email domain = SUBSTRING + CHARINDEX
SELECT TOP (10) Email,
       SUBSTRING(Email, CHARINDEX('@', Email) + 1, LEN(Email)) AS Domain
FROM dbo.Applicants
WHERE Email LIKE '%@%'
ORDER BY ApplicantID;

-- D.7  Most common email domains (aggregate on a function result)
SELECT TOP (5)
       SUBSTRING(Email, CHARINDEX('@', Email) + 1, 100) AS Domain,
       COUNT(*) AS Applicants
FROM dbo.Applicants
WHERE Email LIKE '%@%'
GROUP BY SUBSTRING(Email, CHARINDEX('@', Email) + 1, 100)
ORDER BY Applicants DESC;

-- D.8  REPLACE
SELECT REPLACE('555-123-4567', '-', '')    AS Digits,
       REPLACE('a_b_c', '_', ' ')          AS Spaced,
       REPLACE('hello', 'l', '')           AS NoL;

-- D.9  Sites containing a literal % or _
SELECT SiteID, SiteName
FROM dbo.Sites
WHERE CHARINDEX('%', SiteName) > 0 OR CHARINDEX('_', SiteName) > 0;
-- CHARINDEX needs no wildcard escaping - handy where LIKE '%_%' would match everything.

-- D.10 Strip punctuation from phone numbers
SELECT TOP (10) Phone,
       REPLACE(REPLACE(REPLACE(REPLACE(Phone, '-', ''), ' ', ''), '(', ''), ')', '') AS CleanPhone
FROM dbo.Applicants
WHERE Phone IS NOT NULL
ORDER BY ApplicantID;

-- D.11 Proper case for a single word: first letter up, rest down
SELECT TOP (15) ApplicantID,
       UPPER(LEFT(TRIM(FirstName), 1)) + LOWER(SUBSTRING(TRIM(FirstName), 2, 50)) AS CleanFirst
FROM dbo.Applicants
ORDER BY ApplicantID;

-- D.12 REVERSE, REPLICATE, STUFF, STRING lengths
SELECT REVERSE('abc')              AS Rev,
       REPLICATE('ab', 3)          AS Rep,        -- ababab
       STUFF('HomesEngland', 6, 0, '-') AS Stuffed, -- Homes-England
       LEFT('X', 0)                AS EmptyLeft;

-- D.13 Names with an apostrophe
SELECT TOP (10) ApplicantID, FirstName, LastName
FROM dbo.Applicants
WHERE LastName LIKE '%''%'          -- '' inside a string = one apostrophe
ORDER BY ApplicantID;

-- D.14 Extract text before a space: first word of a site name
SELECT TOP (10) SiteName,
       LEFT(SiteName, CHARINDEX(' ', SiteName + ' ') - 1) AS FirstWord
FROM dbo.Sites
ORDER BY SiteID;          -- appending ' ' avoids a -1 length error on one-word names

/* ---- Common mistakes (D) ---------------------------------------------------
   1. SUBSTRING starting at 0 (strings start at 1).
   2. CHARINDEX argument application: CHARINDEX(what_to_find, where_to_look).
   3. Negative length: LEFT(x, CHARINDEX(...) - 1) when the character is
      missing gives -1 -> error "Invalid length parameter".
   4. Using LIKE '%_%' to find an underscore (_ is a wildcard!). Use CHARINDEX
      or LIKE '%[_]%'.
   5. Functions on a column in WHERE (UPPER(col) = 'X') can stop index use.
      Fine for learning, but know the cost on 10,000+ rows.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (D) ------------------------------------------------
   Q1. SUBSTRING('ABCDEF', 2, 3)    Q2. CHARINDEX('C', 'ABCDEF')
   Q3. LEFT('ABCDEF', 2) + RIGHT('ABCDEF', 2)    Q4. REPLACE('banana','an','')
   Q5. UPPER(NULL)
   Answers: BCD ; 3 ; ABEF ; ba ; NULL.
   ---------------------------------------------------------------------------- */

/* ---- Try it (D) ------------------------------------------------------------
   Show each applicant's Initials (e.g. 'J.S.') from cleaned FirstName/LastName,
   for the first 20 applicants.
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT E : LEN vs DATALENGTH, TRIM, CONCAT vs +
   ############################################################################
   LEN = number of characters, IGNORING trailing spaces.
   DATALENGTH = number of BYTES (including trailing spaces). NVARCHAR uses
   2 bytes per character, VARCHAR 1 byte.
   TRIM (2017+) removes spaces from both ends; LTRIM/RTRIM from one end.
   '+' with a NULL gives NULL. CONCAT() treats NULL as empty text.
   ########################################################################## */

-- E.1  LEN ignores trailing spaces
SELECT LEN('abc')       AS L1,   -- 3
       LEN('abc   ')    AS L2,   -- 3  (!)
       LEN('   abc')    AS L3;   -- 6  leading spaces DO count

-- E.2  DATALENGTH counts bytes
SELECT DATALENGTH('abc   ')   AS Varchar6,    -- 6
       DATALENGTH(N'abc   ')  AS Nvarchar12,  -- 12 (2 bytes per char)
       DATALENGTH(N'abc')     AS Nvarchar6;

-- E.3  Real data: names with stray spaces
SELECT TOP (10) ApplicantID, FirstName,
       LEN(FirstName)        AS Len_,
       DATALENGTH(FirstName) AS Bytes
FROM dbo.Applicants
WHERE LEN(FirstName) <> LEN(TRIM(FirstName)) OR DATALENGTH(FirstName) <> DATALENGTH(TRIM(FirstName))
ORDER BY ApplicantID;

-- E.4  Trailing space that LEN cannot see - find it with DATALENGTH
SELECT COUNT(*) AS TrailingSpaceNames
FROM dbo.Applicants
WHERE DATALENGTH(FirstName) <> DATALENGTH(RTRIM(FirstName));

-- E.5  TRIM family
SELECT '[' + TRIM('   hi   ')  + ']' AS T,
       '[' + LTRIM('   hi   ') + ']' AS L,
       '[' + RTRIM('   hi   ') + ']' AS R;

-- E.6  TRIM can also remove chosen characters (2017+)
SELECT TRIM('#' FROM '##tag##') AS HashesGone;

-- E.7  Cleaned full name with +
SELECT TOP (10) ApplicantID, TRIM(FirstName) + ' ' + TRIM(LastName) AS FullName
FROM dbo.Applicants
ORDER BY ApplicantID;

-- E.8  + with NULL gives NULL (Region is ~30% NULL)
SELECT TOP (10) City + ', ' + Region AS CityRegion_Plus,       -- NULL when Region NULL
       CONCAT(City, ', ', Region)    AS CityRegion_Concat       -- 'City, ' (trailing comma)
FROM dbo.Applicants
ORDER BY ApplicantID;

-- E.9  Doing it properly: only add the comma if Region exists
SELECT TOP (10) City + ISNULL(', ' + Region, '') AS CityRegion
FROM dbo.Applicants
ORDER BY ApplicantID;

-- E.10 CONCAT converts numbers automatically; + does not
SELECT CONCAT('Application #', 1001)         AS Ok;
-- ERROR: SELECT 'Application #' + 1001;     -- Conversion failed ('Application #' to int)
SELECT 'Application #' + CAST(1001 AS VARCHAR(10)) AS AlsoOk;

-- E.11 CONCAT_WS: separator-aware, skips NULLs (2017+)
SELECT TOP (10) CONCAT_WS(', ', City, Region, Country) AS Location
FROM dbo.Applicants
ORDER BY ApplicantID;

-- E.12 Email = '' vs NULL in a display column
SELECT TOP (10) ApplicantID,
       COALESCE(NULLIF(TRIM(Email), ''), '(no email)') AS EmailDisplay
FROM dbo.Applicants
ORDER BY ApplicantID DESC;

-- E.13 Max name length per column (sizing a report)
SELECT MAX(LEN(FirstName)) AS LongestFirst,
       MAX(LEN(LastName))  AS LongestLast,
       MAX(LEN(Email))     AS LongestEmail
FROM dbo.Applicants;

-- E.14 Duplicate full names (after cleaning)
SELECT TOP (10) UPPER(TRIM(FirstName)) AS F, UPPER(TRIM(LastName)) AS L, COUNT(*) AS Times
FROM dbo.Applicants
GROUP BY UPPER(TRIM(FirstName)), UPPER(TRIM(LastName))
HAVING COUNT(*) > 1
ORDER BY Times DESC;

/* ---- Common mistakes (E) ---------------------------------------------------
   1. Expecting LEN('abc   ') = 6.
   2. Comparing 'abc' = 'abc   ' : SQL Server IGNORES trailing spaces in '=',
      so this is TRUE. Leading spaces matter.
   3. Using + on a possibly-NULL column and wondering why the whole name vanished.
   4. Using CONCAT and then getting 'City, ' with a dangling comma.
   5. Forgetting NVARCHAR is 2 bytes per char when reading DATALENGTH.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (E) ------------------------------------------------
   Q1. LEN('  x  ')           Q2. DATALENGTH(N'  x  ')
   Q3. 'A' + NULL + 'B'       Q4. CONCAT('A', NULL, 'B')
   Q5. SELECT CASE WHEN 'abc' = 'abc   ' THEN 'same' ELSE 'different' END;
   Answers: 3 ; 10 ; NULL ; AB ; same.
   ---------------------------------------------------------------------------- */

/* ---- Try it (E) ------------------------------------------------------------
   Build "LASTNAME, Firstname" (clean) for 15 applicants and add the Region in
   brackets only when Region is not NULL, e.g. "SMITH, John [West]".
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT F : DATE FUNCTIONS
   ############################################################################
   GETDATE() = now. YEAR/MONTH/DAY pull parts. DATEPART(part, date) is the
   general form; DATENAME gives text ('March', 'Monday').
   DATEADD(part, n, date) moves a date. DATEDIFF(part, start, end) counts
   how many part BOUNDARIES are crossed (not full elapsed units!).
   EOMONTH(date) = last day of that month.
   Applications.ApplicationDate is DATETIME2(0): it has a time. Beware 23:59:59.
   ########################################################################## */

-- F.1  Now
SELECT GETDATE()          AS NowLocal,
       SYSDATETIME()      AS NowPrecise,
       GETUTCDATE()       AS NowUtc,
       CAST(GETDATE() AS DATE) AS TodayOnly;

-- F.2  Pull parts
SELECT TOP (5) ApplicationID, ApplicationDate,
       YEAR(ApplicationDate)  AS Yr,
       MONTH(ApplicationDate) AS Mo,
       DAY(ApplicationDate)   AS Dy
FROM dbo.Applications
ORDER BY ApplicationID;

-- F.3  DATEPART and DATENAME
SELECT TOP (5) ApplicationDate,
       DATEPART(QUARTER, ApplicationDate) AS Qtr,            -- CALENDAR quarter (Jan-Mar = 1); the UK financial-year quarter is (MONTH + 8) % 12 / 3 + 1
       DATEPART(WEEKDAY, ApplicationDate) AS WeekdayNo,   -- depends on DATEFIRST setting
       DATENAME(WEEKDAY, ApplicationDate) AS WeekdayName,
       DATENAME(MONTH, ApplicationDate)   AS MonthName,
       DATEPART(HOUR, ApplicationDate)    AS Hr
FROM dbo.Applications
ORDER BY ApplicationID;

-- F.4  DATEADD
SELECT DATEADD(DAY, 30, '2024-01-31')    AS Plus30d,       -- 2024-03-01 (leap year!)
       DATEADD(MONTH, 1, '2024-01-31')   AS PlusMonth,     -- 2024-02-29 (clamps to month end)
       DATEADD(YEAR, -1, '2024-02-29')   AS MinusYear,     -- 2023-02-28
       DATEADD(HOUR, 5, '2024-12-31 22:00') AS Plus5h;     -- rolls into 2025

-- F.5  DATEDIFF counts boundaries, not elapsed time
SELECT DATEDIFF(YEAR,  '2024-12-31', '2025-01-01') AS Years,   -- 1 (!) one day apart
       DATEDIFF(MONTH, '2024-01-31', '2024-02-01') AS Months,  -- 1
       DATEDIFF(DAY,   '2024-02-28', '2024-03-01') AS Days;    -- 2 (leap year)

-- F.6  Days from application to completion (and spot data errors where it is negative)
SELECT TOP (10) ApplicationID, ApplicationDate, CompletionDate,
       DATEDIFF(DAY, ApplicationDate, CompletionDate) AS DaysToComplete
FROM dbo.Applications
WHERE CompletionDate IS NOT NULL
ORDER BY ApplicationID;

SELECT COUNT(*) AS CompletedBeforeApplied
FROM dbo.Applications
WHERE CompletionDate < CAST(ApplicationDate AS DATE);

-- F.7  EOMONTH
SELECT EOMONTH('2024-02-10')      AS LeapFeb,     -- 2024-02-29
       EOMONTH('2023-02-10')      AS NormalFeb,   -- 2023-02-28
       EOMONTH('2024-02-10', 1)   AS NextMonthEnd,
       EOMONTH(GETDATE(), -1)     AS LastMonthEnd;

-- F.8  First day of month: the classic trick (works on all versions)
SELECT DATEADD(MONTH, DATEDIFF(MONTH, 0, '2024-05-17'), 0) AS FirstOfMonth,
       DATEADD(DAY, 1, EOMONTH('2024-05-17', -1))          AS FirstOfMonth_2;
-- DATETRUNC(MONTH, ...) exists only in SQL Server 2022+.

-- F.9  Applications in 2024 - THE BETWEEN TRAP
SELECT COUNT(*) AS Between_Wrong
FROM dbo.Applications
WHERE ApplicationDate BETWEEN '2024-01-01' AND '2024-12-31';   -- misses Dec 31 after 00:00:00

SELECT COUNT(*) AS HalfOpen_Right
FROM dbo.Applications
WHERE ApplicationDate >= '2024-01-01' AND ApplicationDate < '2025-01-01';  -- always use this shape

SELECT COUNT(*) AS ViaYear              -- correct but cannot use an index on ApplicationDate
FROM dbo.Applications
WHERE YEAR(ApplicationDate) = 2024;

-- F.10 The 23:59:59 applications
SELECT TOP (10) ApplicationID, ApplicationDate
FROM dbo.Applications
WHERE CAST(ApplicationDate AS TIME) = '23:59:59'
ORDER BY ApplicationID;

-- F.11 Leap day application(s)
SELECT ApplicationID, ApplicationDate
FROM dbo.Applications
WHERE ApplicationDate >= '2024-02-29' AND ApplicationDate < '2024-03-01';

-- F.12 Last 30 days, relative to now (expect 0 rows counted: the data stops at the end of 2025),
--      and future-dated applications (the dataset's 'future' = 1 Jan 2026 onwards, whatever today's date)
SELECT COUNT(*) AS Last30Days
FROM dbo.Applications
WHERE ApplicationDate >= DATEADD(DAY, -30, GETDATE()) AND ApplicationDate <= GETDATE();

SELECT COUNT(*) AS FutureApplications, MIN(ApplicationDate) AS Earliest, MAX(ApplicationDate) AS Latest
FROM dbo.Applications
WHERE ApplicationDate >= '2026-01-01';

-- F.13 How long each applicant has been registered
SELECT TOP (5) ApplicantID, RegisteredDate,
       DATEDIFF(DAY, RegisteredDate, GETDATE())   AS DaysSinceRegistered,
       DATEDIFF(YEAR, RegisteredDate, GETDATE())  AS YearsApprox
FROM dbo.Applicants
ORDER BY ApplicantID;

-- F.14 Build a date from parts
SELECT DATEFROMPARTS(2024, 2, 29) AS LeapDay,
       ISDATE('2023-02-29')      AS IsValid0or1;     -- 0

-- F.14b UK financial year (April to March): FY label for each application
--   FY starts on 1 April, so subtract 3 months, then take the year:
--   2025-03-31 -> FY 2024/25 ; 2025-04-01 -> FY 2025/26
SELECT TOP (10) ApplicationDate,
       YEAR(DATEADD(MONTH, -3, ApplicationDate)) AS FYStartYear,
       CONCAT('FY ', YEAR(DATEADD(MONTH, -3, ApplicationDate)), '/',
              RIGHT(CAST(YEAR(DATEADD(MONTH, -3, ApplicationDate)) + 1 AS VARCHAR(4)), 2)) AS FinancialYear
FROM dbo.Applications
WHERE ApplicationDate >= '2025-03-30' AND ApplicationDate < '2025-04-03'
ORDER BY ApplicationDate;      -- watch the rows either side of 31 Mar / 1 Apr

-- F.14c Homes funded per financial year (FY = April to March)
SELECT YEAR(DATEADD(MONTH, -3, a.ApplicationDate)) AS FYStartYear,
       SUM(fl.Homes)                                AS HomesFunded
FROM dbo.Applications a
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
WHERE a.ApplicationDate >= '2022-04-01' AND a.ApplicationDate < '2025-04-01'
GROUP BY YEAR(DATEADD(MONTH, -3, a.ApplicationDate))
ORDER BY FYStartYear;

-- F.15 Year-end / year-start boundaries
SELECT ApplicationDate FROM dbo.Applications
WHERE (MONTH(ApplicationDate) = 12 AND DAY(ApplicationDate) = 31)
   OR (MONTH(ApplicationDate) = 1  AND DAY(ApplicationDate) = 1)
ORDER BY ApplicationDate;     -- lots: skim the first few rows

/* ---- Common mistakes (F) ---------------------------------------------------
   1. BETWEEN '2024-01-01' AND '2024-12-31' on a DATETIME2 (F.9).
   2. Believing DATEDIFF(YEAR, ...) gives full years; it counts Jan-1 crossings.
   3. DATEPART(WEEKDAY) depends on SET DATEFIRST; use DATENAME for text.
   4. Comparing DATETIME to a date literal with '=' : '2024-03-05' means
      midnight, so only midnight rows match. Use a range or CAST(... AS DATE).
   5. Using YEAR(col) = 2024 on huge tables: works, but is not index-friendly.
   6. Mixing d/m/y styles: always write literals as 'YYYY-MM-DD'.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (F) ------------------------------------------------
   Q1. DATEADD(DAY, -1, '2024-03-01')       Q2. EOMONTH('2024-01-15')
   Q3. DATEDIFF(MONTH, '2024-01-31', '2024-03-01')
   Q4. DATEDIFF(DAY, '2025-01-01', '2024-12-25')    Q5. DATENAME(MONTH, '2024-07-04')
   Answers: 2024-02-29 ; 2024-01-31 ; 2 ; -7 ; July.
   ---------------------------------------------------------------------------- */

/* ---- Try it (F) ------------------------------------------------------------
   Count applications per calendar month of 2024 using the half-open pattern for ONE
   chosen month (e.g. March), then compare with FORMAT/MONTH-based counts.
   Bonus: list applications where CompletionDate is more than 14 days after ApplicationDate.
   ---------------------------------------------------------------------------- */
GO


/* ############################################################################
   CONCEPT G : CAST, CONVERT, FORMAT
   ############################################################################
   CAST(x AS type)           - ANSI standard, simple.
   CONVERT(type, x, style)   - T-SQL, has "style" codes for dates (103, 112 ...).
   FORMAT(x, 'pattern')      - .NET-style formatting, returns NVARCHAR,
                               nice but SLOW on big tables: use for display only.
   TRY_CAST / TRY_CONVERT    - return NULL instead of an error.
   ########################################################################## */

-- G.1  CAST basics
SELECT CAST('123' AS INT)             AS ToInt,
       CAST(123 AS VARCHAR(10))       AS ToText,
       CAST(12.987 AS INT)            AS Truncated,       -- 12, not 13
       CAST(12.987 AS DECIMAL(5,1))   AS Rounded;         -- 13.0 (DECIMAL rounds)

-- G.2  Date to text styles with CONVERT
SELECT CONVERT(VARCHAR(10), '2024-03-05', 23)  AS Iso,       -- 2024-03-05
       CONVERT(VARCHAR(10), CAST('2024-03-05' AS DATE), 103) AS BritishDMY,   -- 05/03/2024
       CONVERT(VARCHAR(10), CAST('2024-03-05' AS DATE), 101) AS UsMDY,        -- 03/05/2024
       CONVERT(VARCHAR(8),  CAST('2024-03-05' AS DATE), 112) AS Compact;      -- 20240305

-- G.3  DATETIME2 to DATE strips the time
SELECT TOP (5) ApplicationDate, CAST(ApplicationDate AS DATE) AS ApplicationDay, CAST(ApplicationDate AS TIME(0)) AS ApplicationTime
FROM dbo.Applications
ORDER BY ApplicationID;

-- G.4  Group by day: why CAST AS DATE matters (same-day applications at different times)
SELECT TOP (5) CAST(ApplicationDate AS DATE) AS ApplicationDay, COUNT(*) AS Applications
FROM dbo.Applications
GROUP BY CAST(ApplicationDate AS DATE)
ORDER BY Applications DESC;

-- G.5  Implicit conversion surprises
SELECT '2' + 3        AS TextPlusInt,    -- 5  (text converted to number)
       '2' + '3'      AS TextPlusText;   -- '23'
-- ERROR: SELECT 'abc' + 3;      -- Conversion failed when converting 'abc' to int.

-- G.6  TRY_CAST / TRY_CONVERT
SELECT TRY_CAST('abc' AS INT)            AS Bad,       -- NULL
       TRY_CAST('42' AS INT)             AS Good,
       TRY_CONVERT(DATE, '31/12/2024', 103) AS DmyOk,
       TRY_CAST('2023-02-30' AS DATE)    AS ImpossibleDate;   -- NULL

-- G.7  Are phones numeric once the spaces are removed? (a NULL AsNumber would flag a bad phone)
SELECT TOP (5) Phone,
       TRY_CAST(REPLACE(Phone, ' ', '') AS BIGINT) AS AsNumber
FROM dbo.Applicants
WHERE Phone IS NOT NULL;

-- G.8  FORMAT numbers
SELECT FORMAT(1234567.891, 'N2')           AS Thousands,       -- 1,234,567.89
       FORMAT(0.256, 'P1')                 AS Pct,             -- 25.6 %
       FORMAT(1234.5, 'C', 'en-GB')        AS Pounds,          -- £1,234.50
       FORMAT(42, '00000')                 AS ZeroPadded;      -- 00042

-- G.9  FORMAT dates
SELECT FORMAT(CAST('2024-03-05' AS DATE), 'yyyy-MM')        AS YearMonth,
       FORMAT(CAST('2024-03-05' AS DATE), 'dd MMM yyyy')    AS Pretty,
       FORMAT(CAST('2024-03-05' AS DATE), 'dddd')           AS DayName,
       FORMAT(CAST('2024-03-05' AS DATE), 'dd/MM/yyyy', 'en-GB') AS Uk;

-- G.10 Monthly net funding with a readable month label
SELECT TOP (6)
       FORMAT(a.ApplicationDate, 'yyyy-MM') AS YearMonth,
       FORMAT(SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate)), 'N0') AS NetFunding
FROM dbo.Applications AS a
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
GROUP BY FORMAT(a.ApplicationDate, 'yyyy-MM')
ORDER BY YearMonth;
-- Caution: NetFunding is now TEXT, so it would sort alphabetically. Format last, sort on numbers.

-- G.11 Padded IDs with FORMAT vs RIGHT/REPLICATE
SELECT TOP (3) 'APP-' + FORMAT(ApplicationID, '000000')                         AS Code1,
               'APP-' + RIGHT('000000' + CAST(ApplicationID AS VARCHAR(10)), 6) AS Code2
FROM dbo.Applications
ORDER BY ApplicationID;

-- G.12 CAST decimal to a string with the pound sign
SELECT TOP (5) SiteName, N'£' + CAST(UnitPrice AS NVARCHAR(12)) AS GrantText
FROM dbo.Sites
ORDER BY SiteID;

-- G.13 CONVERT with style for DECIMAL -> text (style 1 adds commas for MONEY)
SELECT CONVERT(VARCHAR(20), CAST(1234567.5 AS MONEY), 1) AS WithCommas;   -- 1,234,567.50

-- G.14 Compare text dates correctly: convert first
SELECT COUNT(*) AS Dec2024
FROM dbo.Applications
WHERE CONVERT(CHAR(7), ApplicationDate, 126) = '2024-12';    -- style 126 = ISO 'yyyy-mm-dd...'

/* ---- Common mistakes (G) ---------------------------------------------------
   1. CAST(12.9 AS INT) = 12: INT conversion truncates.
   2. CAST(x AS VARCHAR) with no length defaults to 30 characters, and a bare
      VARCHAR variable/column defaults to 1. ALWAYS give a length.
   3. Sorting or summing formatted strings (FORMAT returns text).
   4. FORMAT in a big GROUP BY / WHERE: slow. Prefer YEAR/MONTH or date ranges.
   5. Date styles: 101 (mm/dd) vs 103 (dd/mm) swap day and month silently.
   6. Relying on implicit conversion ('2' + 3) - make it explicit.
   ---------------------------------------------------------------------------- */

/* ---- Predict the output (G) ------------------------------------------------
   Q1. CAST(9.99 AS INT)    Q2. TRY_CAST('x1' AS INT)    Q3. FORMAT(5, '000')
   Q4. CONVERT(VARCHAR(8), CAST('2025-01-09' AS DATE), 112)
   Q5. '10' + '20'   vs   10 + 20   vs   '10' + 20
   Answers: 9 ; NULL ; 005 ; 20250109 ; '1020' / 30 / 30.
   ---------------------------------------------------------------------------- */

/* ---- Try it (G) ------------------------------------------------------------
   For 10 applications show: ApplicationID, application date as dd/MM/yyyy (CONVERT 103),
   and AdminFee as text with a £ sign, showing 'n/a' for NULL admin fee.
   ---------------------------------------------------------------------------- */
GO

/* ===================== END OF MODULE 04 =====================
   Next: module05_grouping.sql  (GROUP BY, HAVING, CASE, execution application)
   ============================================================ */
