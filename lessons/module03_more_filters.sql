USE HousingDelivery;
GO
/*==============================================================================
  MODULE 03 : MORE FILTERS - IN, BETWEEN, LIKE, NULL, DIRTY DATA
  Database  : HousingDelivery (SQL Server 2019+, run in SSMS)
  Topics    : 1. IN / NOT IN (and the NOT IN + NULL trap)
              2. BETWEEN (and the DATETIME 23:59:59 trap)
              3. LIKE, wildcards % _ [ ] [^], and ESCAPE
              4. IS NULL / IS NOT NULL  vs  = NULL
              5. Empty string vs NULL
              6. TRIM / LTRIM / RTRIM / LOWER / UPPER for dirty data

  HOW TO USE THIS FILE
    - Highlight ONE query at a time and press F5.
    - These are the filters that make beginners get WRONG numbers without an
      error message. After each query ask: "is this row count believable?"
    - "Common mistakes" blocks are commented out. Un-comment to experiment.
==============================================================================*/


/*##############################################################################
  CONCEPT 1 : IN / NOT IN
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  IN checks a value against a list: Region IN ('North West','North East') is a short
  way to write Region = 'North West' OR Region = 'North East'. NOT IN is the opposite.
  The list can also come from a subquery (a SELECT in brackets).
  DANGER: if the list contains even ONE NULL, NOT IN returns NO rows at all.
  Reason: x NOT IN (1, NULL) means x<>1 AND x<>NULL, and x<>NULL is UNKNOWN.
------------------------------------------------------------------------------*/

-- Example 1.1 : IN with text.
SELECT ApplicantID, Region
FROM Applicants
WHERE Region IN ('North West', 'North East', 'Yorkshire and The Humber');

-- Example 1.2 : IN with numbers.
SELECT TenureTypeID, TenureName
FROM TenureTypes
WHERE TenureTypeID IN (1, 3, 5, 7);

-- Example 1.3 : NOT IN with a plain list.
SELECT ApplicationID, Status
FROM Applications
WHERE Status NOT IN ('Completed', 'Approved');

-- Example 1.4 : IN and AND together. Brackets are not needed here; IN is a
-- single condition.
SELECT ApplicantID, HouseholdType, Country
FROM Applicants
WHERE HouseholdType IN ('Key worker', 'Home mover') AND IsActive = 1;

-- Example 1.5 : IN with dates.
SELECT ApplicationID, TargetDate
FROM Applications
WHERE TargetDate IN ('20240229', '20250331', '20250401');

-- Example 1.6 : IN with a subquery. Sites delivered by partners based in one region.
SELECT SiteID, SiteName, PartnerID
FROM Sites
WHERE PartnerID IN (SELECT PartnerID FROM Partners WHERE Region = 'North West');

-- Example 1.7 : subquery on another table. Applicants who have submitted an application.
SELECT ApplicantID, FirstName, LastName
FROM Applicants
WHERE ApplicantID IN (SELECT ApplicantID FROM Applications);

-- Example 1.8 : NOT IN with a subquery. Applicants who never applied (~300).
-- This one is SAFE because Applications.ApplicantID can never be NULL.
SELECT ApplicantID, FirstName, LastName
FROM Applicants
WHERE ApplicantID NOT IN (SELECT ApplicantID FROM Applications);

-- Example 1.9 : sites never funded (~40). FundingLines.SiteID is not null.
SELECT SiteID, SiteName
FROM Sites
WHERE SiteID NOT IN (SELECT SiteID FROM FundingLines);

-- Example 1.10 : THE TRAP. Which tenure types have no sites? We know exactly
-- one does. But Sites.TenureTypeID has NULLs (~5 rows), so NOT IN returns
-- ZERO rows. No error. Just a wrong answer.
SELECT TenureTypeID, TenureName
FROM TenureTypes
WHERE TenureTypeID NOT IN (SELECT TenureTypeID FROM Sites);

-- Example 1.11 : fix A: remove the NULLs from the list.
SELECT TenureTypeID, TenureName
FROM TenureTypes
WHERE TenureTypeID NOT IN (SELECT TenureTypeID FROM Sites WHERE TenureTypeID IS NOT NULL);

-- Example 1.12 : fix B: NOT EXISTS (preferred, NULL-safe).
SELECT c.TenureTypeID, c.TenureName
FROM TenureTypes AS c
WHERE NOT EXISTS (SELECT 1 FROM Sites AS p WHERE p.TenureTypeID = c.TenureTypeID);

-- Example 1.13 : the same trap on staff. Who has taken no applications?
-- Applications.StaffID has NULLs (online applications), so this returns 0 rows.
SELECT StaffID, FirstName, LastName
FROM Staff
WHERE StaffID NOT IN (SELECT StaffID FROM Applications);

-- Example 1.14 : fixed.
SELECT StaffID, FirstName, LastName
FROM Staff
WHERE StaffID NOT IN (SELECT StaffID FROM Applications WHERE StaffID IS NOT NULL);

-- Example 1.15 : tricky: a literal NULL in a list. Prove the trap in isolation.
SELECT CASE WHEN 5 IN (1, 5, NULL)     THEN 'row kept' ELSE 'row dropped' END AS InWithNull,
       CASE WHEN 5 NOT IN (1, 2, NULL) THEN 'row kept' ELSE 'row dropped' END AS NotInWithNull;

-- Example 1.16 : tricky: IN never matches NULL. Region IN (NULL) finds nothing.
SELECT COUNT(*) AS ShouldBeManyButIsZero
FROM Applicants
WHERE Region IN (NULL);

/*---- Common mistakes : CONCEPT 1 ---------------------------------------------
-- Mistake 1: NOT IN against a column that may contain NULL (Examples 1.10, 1.13).
-- Mistake 2: subquery returns two columns -> Msg 116.
SELECT * FROM Applicants WHERE ApplicantID IN (SELECT ApplicantID, ApplicationID FROM Applications);
-- Mistake 3: putting quotes around a list as one string: IN ('North West, North East')
--   searches for ONE value named "North West, North East" -> 0 rows.
SELECT * FROM Applicants WHERE Region IN ('North West, North East');
-- Mistake 4: expecting IN (NULL) to find NULL rows. Use IS NULL.
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 1 ------------------------------------------
Q1. How many rows does  WHERE 3 NOT IN (1, 2, 4)  keep? (think of it as a SELECT 1 test)
Q2. And  WHERE 3 NOT IN (1, 2, NULL) ?
Q3. Which of the following can contain NULL and break NOT IN: Applications.ApplicantID,
    Applications.StaffID, Sites.TenureTypeID, Sites.PartnerID?
Q4. Example 1.10 returns how many rows, and how many SHOULD it return?
ANSWERS: Q1 = 1 (kept). Q2 = 0 (dropped: UNKNOWN). Q3 = StaffID and TenureTypeID
         (per spec ApplicantID and PartnerID are not NULL). Q4 = 0 returned, 1 should be.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 1 ------------------------------------------------------
1) List sites whose TenureTypeID is in (2, 4, 6) and that are not stalled.
2) List programmes never used by any application. Applications.ProgrammeID can be NULL - write it
   so that it is safe. (Use NOT EXISTS or IS NOT NULL inside the subquery.)
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 2 : BETWEEN (AND THE 23:59:59 TRAP)
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  x BETWEEN a AND b  means  x >= a AND x <= b. BOTH ends are INCLUDED. It works
  for numbers, text and dates. NOT BETWEEN is the opposite.
  The date trap: '2025-03-31' means '2025-03-31 00:00:00'. So
  ApplicationDate BETWEEN '20240401' AND '20250331' MISSES every application submitted on
  31 March (the last day of FY 2024/25) after midnight (for example 23:59:59). For date-times always use a
  half-open range:  >= start AND < start of the day AFTER the end.
------------------------------------------------------------------------------*/

-- Example 2.1 : numbers, both ends included.
SELECT SiteName, UnitPrice
FROM Sites
WHERE UnitPrice BETWEEN 20000 AND 40000
ORDER BY UnitPrice;

-- Example 2.2 : same as writing it out.
SELECT SiteName, UnitPrice
FROM Sites
WHERE UnitPrice >= 20000 AND UnitPrice <= 40000
ORDER BY UnitPrice;

-- Example 2.3 : NOT BETWEEN. Very low or very high grant per home.
SELECT SiteName, UnitPrice
FROM Sites
WHERE UnitPrice NOT BETWEEN 5000 AND 150000;

-- Example 2.4 : text range. Last names starting A through C (up to 'C' only,
-- so 'Chen' is NOT included because 'Chen' > 'C').
SELECT ApplicantID, LastName
FROM Applicants
WHERE LastName BETWEEN 'A' AND 'C'
ORDER BY LastName;

-- Example 2.5 : dates in a DATE column - BETWEEN is safe here (no time part).
SELECT ApplicantID, RegisteredDate
FROM Applicants
WHERE RegisteredDate BETWEEN '20240401' AND '20250331';   -- FY 2024/25; safe because RegisteredDate is a DATE

-- Example 2.6 : acquisition dates of sites in the last quarter of FY 2023/24 (Jan-Mar 2024).
SELECT SiteID, SiteName, AcquiredDate
FROM Sites
WHERE AcquiredDate BETWEEN '20240101' AND '20240331';

-- Example 2.7 : leap day boundary: 2024-02-29 is included.
SELECT COUNT(*) AS ApplicationsInFeb2024Wrong
FROM Applications
WHERE ApplicationDate BETWEEN '20240201' AND '20240229';

-- Example 2.8 : the correct February count (half-open range).
SELECT COUNT(*) AS ApplicationsInFeb2024Right
FROM Applications
WHERE ApplicationDate >= '20240201' AND ApplicationDate < '20240301';

-- Example 2.9 : THE TRAP on a whole year. Compare the two counts. The BETWEEN
-- version loses every 31 March 2025 application with a time after 00:00:00.
SELECT COUNT(*) AS Wrong_Between
FROM Applications
WHERE ApplicationDate BETWEEN '20240401' AND '20250331';

SELECT COUNT(*) AS Right_HalfOpen
FROM Applications
WHERE ApplicationDate >= '20240401' AND ApplicationDate < '20250401';

-- Example 2.10 : find exactly the applications the BETWEEN version missed.
SELECT ApplicationID, ApplicationDate
FROM Applications
WHERE ApplicationDate >= '20250331' AND ApplicationDate < '20250401'
  AND ApplicationDate > '20250331';

-- Example 2.11 : the 23:59:59 applications specifically (planted edge case).
SELECT ApplicationID, ApplicationDate
FROM Applications
WHERE CAST(ApplicationDate AS TIME(0)) = '23:59:59';

-- Example 2.12 : "fix" with 23:59:59 works for DATETIME2(0) but is fragile
-- (breaks if the column ever stores fractions of seconds). Avoid.
SELECT COUNT(*) AS FragileFix
FROM Applications
WHERE ApplicationDate BETWEEN '20240401 00:00:00' AND '20250331 23:59:59';

-- Example 2.13 : another safe way: compare only the date part. Easy to read but
-- slower on big tables because it wraps the column in a function.
SELECT COUNT(*) AS CastVersion
FROM Applications
WHERE CAST(ApplicationDate AS DATE) BETWEEN '20240401' AND '20250331';

-- Example 2.14 : tricky: BETWEEN with reversed bounds returns nothing.
SELECT COUNT(*) AS ReversedBounds
FROM Sites
WHERE UnitPrice BETWEEN 40000 AND 20000;

-- Example 2.15 : tricky: the 31 March / 1 April financial-year boundary done correctly.
SELECT ApplicationID, ApplicationDate
FROM Applications
WHERE ApplicationDate >= '20240331' AND ApplicationDate < '20240402'
ORDER BY ApplicationDate;

-- Example 2.16 : tricky: future-dated applications (2026-2027) are outside all history.
SELECT ApplicationID, ApplicationDate, Status
FROM Applications
WHERE ApplicationDate >= '20260101'
ORDER BY ApplicationDate;

/*---- Common mistakes : CONCEPT 2 ---------------------------------------------
-- Mistake 1: BETWEEN with a DATETIME column and an end date with no time.
SELECT COUNT(*) FROM Applications WHERE ApplicationDate BETWEEN '20250301' AND '20250331';
-- Mistake 2: assuming BETWEEN excludes the end values. It includes both.
-- Mistake 3: smaller value must come FIRST. BETWEEN 40000 AND 20000 gives 0 rows.
-- Mistake 4: ending a range at '20250331 23:59:59.999' on DATETIME2 and being
--   off by a fraction. Use < next day instead.
-- Mistake 5: BETWEEN on text expecting a prefix match: 'A' AND 'C' stops BEFORE 'Ca'.
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 2 ------------------------------------------
Q1. Does  UnitPrice BETWEEN 20000 AND 40000  include a site with a grant of exactly 40000.00?
Q2. An application is submitted 2025-03-31 14:30:00. Is it in
    ApplicationDate BETWEEN '20240401' AND '20250331'?
Q3. Is the same application in  ApplicationDate >= '20240401' AND ApplicationDate < '20250401'?
Q4. How many rows come back for  BETWEEN 40000 AND 20000?
ANSWERS: Q1 = Yes. Q2 = No (the end means 00:00:00 on 31 March). Q3 = Yes.
         Q4 = 0.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 2 ------------------------------------------------------
Count applications submitted in Q4 of FY 2023/24 (1 Jan - 31 Mar 2024) correctly. Then write the
wrong BETWEEN version and see how many applications it misses.
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 3 : LIKE AND WILDCARDS (% _ [ ] [^]) AND ESCAPE
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  LIKE matches TEXT PATTERNS. Wildcards:
     %        any number of characters (including none)
     _        exactly ONE character
     [abc]    one character from the set (also ranges like [a-f], [0-9])
     [^abc]   one character NOT in the set
  Matching is case-insensitive in the default collation. A leading % ('%abc')
  cannot use an index, so it is slow on big tables. To search for a literal %
  or _ either wrap it in brackets ([%], [_]) or declare an ESCAPE character.
------------------------------------------------------------------------------*/

-- Example 3.1 : starts with. Sites whose name begins with 'Plot'.
SELECT SiteID, SiteName
FROM Sites
WHERE SiteName LIKE 'Plot%';

-- Example 3.2 : ends with. Last names ending in 'son'.
SELECT ApplicantID, LastName
FROM Applicants
WHERE LastName LIKE '%son';

-- Example 3.3 : contains.
SELECT SiteID, SiteName
FROM Sites
WHERE SiteName LIKE '%Infill%';

-- Example 3.4 : _ = exactly one character. 5-letter first names starting with J.
SELECT ApplicantID, FirstName
FROM Applicants
WHERE FirstName LIKE 'J____';

-- Example 3.5 : _ in the middle. Matches 'Smith', 'Smyth' but not 'Smth'.
SELECT ApplicantID, LastName
FROM Applicants
WHERE LastName LIKE 'Sm_th';

-- Example 3.6 : [set]. Last names starting with M, N or O.
SELECT ApplicantID, LastName
FROM Applicants
WHERE LastName LIKE '[MNO]%'
ORDER BY LastName;

-- Example 3.7 : [range]. Last names that start with A through F.
SELECT ApplicantID, LastName
FROM Applicants
WHERE LastName LIKE '[A-F]%'
ORDER BY LastName;

-- Example 3.8 : [^set]. Names that do NOT start with a vowel.
SELECT ApplicantID, FirstName
FROM Applicants
WHERE FirstName LIKE '[^AEIOU]%';

-- Example 3.9 : prefixes. Phone numbers that start with the UK mobile prefix '+44 7'
-- (every stored phone starts with '+44 ', so a [0-9]% pattern would match nothing).
SELECT ApplicantID, Phone
FROM Applicants
WHERE Phone LIKE '+44 7%';

-- Example 3.10 : NOT LIKE.
SELECT PartnerID, PartnerName
FROM Partners
WHERE PartnerName NOT LIKE '%Ltd%';

-- Example 3.11 : apostrophes in the data: O'Brien, D'Souza.
SELECT ApplicantID, FirstName, LastName
FROM Applicants
WHERE LastName LIKE '%''%';

-- Example 3.12 : LIKE with a pattern held in a variable.
DECLARE @pattern NVARCHAR(50) = N'S%';
SELECT TOP (20) ApplicantID, LastName FROM Applicants WHERE LastName LIKE @pattern;
GO

-- Example 3.13 : THE TRAP. The site '100% Affordable Scheme' contains a literal %.
-- This search for "contains a percent sign" matches EVERY site, because
-- '%%%' is just three wildcards.
SELECT COUNT(*) AS WrongCount
FROM Sites
WHERE SiteName LIKE '%%%';

-- Example 3.14 : fix 1: wrap the wildcard in brackets so it is a literal.
SELECT SiteID, SiteName
FROM Sites
WHERE SiteName LIKE '%[%]%';

-- Example 3.15 : fix 2: ESCAPE. Choose a character, put it before the literal.
SELECT SiteID, SiteName
FROM Sites
WHERE SiteName LIKE '%\%%' ESCAPE '\';

-- Example 3.16 : the underscore trap. 'Plot_7 Infill' contains a literal _.
-- '%_%' matches every non-empty name. Brackets or ESCAPE find the real one.
SELECT COUNT(*) AS WrongCount FROM Sites WHERE SiteName LIKE '%_%';
SELECT SiteID, SiteName FROM Sites WHERE SiteName LIKE '%[_]%';
SELECT SiteID, SiteName FROM Sites WHERE SiteName LIKE '%!_%' ESCAPE '!';

-- Example 3.17 : exact literal: names that start with '100%'.
SELECT SiteID, SiteName
FROM Sites
WHERE SiteName LIKE '100[%]%';

-- Example 3.18 : tricky: [ itself. Search for a literal opening bracket.
SELECT COUNT(*) AS NamesWithBracket
FROM Sites
WHERE SiteName LIKE '%[[]%';

-- Example 3.19 : tricky: LIKE is NOT case-sensitive by default, but you can
-- force case-sensitivity with a collation.
SELECT TOP (10) ApplicantID, LastName
FROM Applicants
WHERE LastName LIKE 'Smith' COLLATE Latin1_General_CS_AS;   -- finds only exactly-cased 'Smith' (try 'smith': 0 rows)

-- Example 3.20 : tricky: LIKE treats trailing spaces as significant (unlike =).
-- Compare = and LIKE on the same value.
SELECT 'equal' AS Test WHERE 'abc ' = 'abc'
UNION ALL
SELECT 'like'  WHERE 'abc ' LIKE 'abc';

/*---- Common mistakes : CONCEPT 3 ---------------------------------------------
-- Mistake 1: using * as the wildcard (that is Windows/Excel, not SQL).
SELECT * FROM Sites WHERE SiteName LIKE 'Plot*';
-- Mistake 2: using = with a wildcard: WHERE SiteName = 'Plot%'  -> 0 rows.
-- Mistake 3: searching for % or _ without escaping (Examples 3.13, 3.16).
-- Mistake 4: '%abc' on millions of rows is a full scan (slow); prefer 'abc%'.
-- Mistake 5: forgetting the quote inside the pattern: LIKE '%'%' -> syntax error.
--   Write it as '%''%'.
-- Mistake 6: forgetting ESCAPE after using the escape character, so \ is read
--   as a normal character.
SELECT * FROM Sites WHERE SiteName LIKE '%\%%';
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 3 ------------------------------------------
Q1. Which names match  LIKE 'a_c' : 'abc', 'ac', 'abbc', 'ABC'?
Q2. Which match  LIKE '[^a]%' : 'apple', 'Banana', 'avocado'?
Q3. What does  LIKE '%[%]'  find?
Q4. Does  LIKE '%_%'  match an empty string ''?
ANSWERS: Q1 = 'abc' and 'ABC' (one char between; case-insensitive).
         Q2 = 'Banana' only. Q3 = text that ENDS with a percent sign.
         Q4 = No (needs at least one character); it matches everything else.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 3 ------------------------------------------------------
1) Find partners whose name has exactly two words: hint: LIKE '% %' AND NOT LIKE '% % %'.
2) Find applicants whose last name starts with D and has an apostrophe as 2nd char.
3) Find sites whose name contains a literal underscore, using ESCAPE.
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 4 : IS NULL / IS NOT NULL  vs  = NULL
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  NULL means "unknown / missing". It is not zero, not an empty string, not a
  space. Any comparison with NULL (=, <>, <, >) gives UNKNOWN, and WHERE only
  keeps TRUE rows. So  col = NULL  never matches anything, even NULL rows.
  The only correct tests are  IS NULL  and  IS NOT NULL.
  HousingDelivery NULLs: Applicants.Email (~8%), Phone (~12%), Region (~30%);
  Applications.CompletionDate, StaffID, ProgrammeID, AdminFee; Sites.TenureTypeID.
------------------------------------------------------------------------------*/

-- Example 4.1 : the correct test. Applicants with no region.
SELECT ApplicantID, City, Country, Region
FROM Applicants
WHERE Region IS NULL;

-- Example 4.2 : the opposite.
SELECT ApplicantID, City, Country, Region
FROM Applicants
WHERE Region IS NOT NULL;

-- Example 4.3 : THE WRONG WAY: = NULL returns zero rows, no error.
SELECT COUNT(*) AS WrongEqualsNull
FROM Applicants
WHERE Region = NULL;

-- Example 4.4 : <> NULL is also wrong.
SELECT COUNT(*) AS WrongNotEqualsNull
FROM Applicants
WHERE Region <> NULL;

-- Example 4.5 : prove it: IS NULL + IS NOT NULL = all rows.
SELECT
  (SELECT COUNT(*) FROM Applicants WHERE Region IS NULL)     AS NullRegion,
  (SELECT COUNT(*) FROM Applicants WHERE Region IS NOT NULL) AS HasRegion,
  (SELECT COUNT(*) FROM Applicants)                          AS Total;

-- Example 4.6 : applications not yet completed (CompletionDate is NULL).
SELECT TOP (30) ApplicationID, ApplicationDate, Status, CompletionDate
FROM Applications
WHERE CompletionDate IS NULL;

-- Example 4.7 : status and NULL completion together: which statuses have no completion date?
SELECT Status, COUNT(*) AS Applications, COUNT(CompletionDate) AS WithCompletionDate
FROM Applications
GROUP BY Status;

-- Example 4.8 : data-quality check: Completed applications that STILL have no CompletionDate.
-- Expected result: 0 rows (the data is clean here; an empty result is the good news).
SELECT ApplicationID, ApplicationDate, Status, CompletionDate
FROM Applications
WHERE Status = 'Completed' AND CompletionDate IS NULL;

-- Example 4.9 : online applications: StaffID IS NULL.
SELECT COUNT(*) AS OnlineApplications
FROM Applications
WHERE StaffID IS NULL;

-- Example 4.10 : AdminFee NULL vs 0. Three different groups. NULL is not waived.
SELECT
  SUM(CASE WHEN AdminFee IS NULL THEN 1 ELSE 0 END) AS AdminFeeUnknown,
  SUM(CASE WHEN AdminFee = 0     THEN 1 ELSE 0 END) AS AdminFeeWaived,
  SUM(CASE WHEN AdminFee > 0     THEN 1 ELSE 0 END) AS AdminFeeCharged
FROM Applications;

-- Example 4.11 : tricky: "AdminFee < 10" silently excludes NULL admin fees.
SELECT COUNT(*) AS Under10_ExcludesNulls FROM Applications WHERE AdminFee < 10;
SELECT COUNT(*) AS Under10_OrUnknown     FROM Applications WHERE AdminFee < 10 OR AdminFee IS NULL;

-- Example 4.12 : tricky: sites with no tenure type and applicants' missing phones
-- in one list (UNION ALL stacks result sets).
SELECT 'Site without tenure type' AS Problem, CAST(SiteID AS VARCHAR(20)) AS RecordID
FROM Sites WHERE TenureTypeID IS NULL
UNION ALL
SELECT 'Applicant without phone', CAST(ApplicantID AS VARCHAR(20))
FROM Applicants WHERE Phone IS NULL;

-- Example 4.13 : replace NULL with a label for display (ISNULL / COALESCE).
SELECT TOP (20) ApplicantID, ISNULL(Region, 'No region') AS RegionLabel, COALESCE(Phone, Email, 'no contact') AS BestContact
FROM Applicants;

-- Example 4.14 : tricky: IS NULL with OR. Applicants with NO email AND NO phone.
SELECT ApplicantID, FirstName, LastName
FROM Applicants
WHERE Email IS NULL AND Phone IS NULL;

-- Example 4.15 : the ISNULL-in-WHERE pattern works but hides indexes; fine to learn.
SELECT COUNT(*) AS RegionNullOrUnknown
FROM Applicants
WHERE ISNULL(Region, 'Unknown') = 'Unknown';

/*---- Common mistakes : CONCEPT 4 ---------------------------------------------
-- Mistake 1: WHERE col = NULL (always 0 rows). Use IS NULL.
-- Mistake 2: WHERE col <> 'x' expecting NULL rows to appear (they do not).
--   Add:  OR col IS NULL.
-- Mistake 3: treating NULL as 0 in maths: 5 + NULL = NULL. AdminFee NULL makes
--   total = NULL. Use ISNULL(AdminFee, 0).
-- Mistake 4: COUNT(col) vs COUNT(*) confusion (Module 1).
-- Mistake 5: writing IS NULL as IS 'NULL' or = 'NULL' (that is the TEXT 'NULL').
SELECT COUNT(*) FROM Applicants WHERE Region = 'NULL';
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 4 ------------------------------------------
Q1. SELECT CASE WHEN NULL = NULL THEN 'same' ELSE 'not same' END;   result?
Q2. SELECT 10 + NULL;   result?
Q3. 3,000 of 10,000 applicants have Region NULL. How many does Region <> 'North West'
    return if 2,000 have Region = 'North West'?
Q4. What does  SELECT ISNULL(NULL, 5) + ISNULL(2, 9);  return?
ANSWERS: Q1 = 'not same' (UNKNOWN is not TRUE). Q2 = NULL. Q3 = 5,000
         (10,000 - 3,000 - 2,000). Q4 = 7.
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 4 ------------------------------------------------------
1) How many Submitted applications have a non-NULL CompletionDate (impossible?). Check.
2) List applicants who have a Phone but no Email.
3) List applications with AdminFee above 0 OR AdminFee NULL, newest 20.
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 5 : EMPTY STRING vs NULL
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  '' (empty string) is a real value with length 0. NULL is "no value at all".
  Data entry forms often save '' where a user left a field blank, so the same
  business fact ("no email") is stored two ways. HousingDelivery has both: ~8% NULL
  Emails PLUS some Email = ''. A filter must handle both. NULLIF(x, '') turns
  an empty string into NULL, which makes the cleanup easy.
------------------------------------------------------------------------------*/

-- Example 5.1 : emails that are NULL.
SELECT COUNT(*) AS EmailIsNull FROM Applicants WHERE Email IS NULL;

-- Example 5.2 : emails that are empty strings.
SELECT COUNT(*) AS EmailIsEmptyString FROM Applicants WHERE Email = '';

-- Example 5.3 : the two groups are different. Neither query finds the other.
SELECT
  SUM(CASE WHEN Email IS NULL THEN 1 ELSE 0 END) AS NullCount,
  SUM(CASE WHEN Email = ''    THEN 1 ELSE 0 END) AS EmptyCount,
  SUM(CASE WHEN Email IS NOT NULL AND Email <> '' THEN 1 ELSE 0 END) AS RealEmail
FROM Applicants;

-- Example 5.4 : "no usable email" = NULL OR ''. The right filter.
SELECT ApplicantID, FirstName, LastName, Email
FROM Applicants
WHERE Email IS NULL OR Email = '';

-- Example 5.5 : the same with NULLIF (empty becomes NULL, then one test).
SELECT ApplicantID, FirstName, LastName, Email
FROM Applicants
WHERE NULLIF(Email, '') IS NULL;

-- Example 5.6 : "has a usable email". Both NULL and '' must be excluded.
SELECT COUNT(*) AS Reachable
FROM Applicants
WHERE Email IS NOT NULL AND Email <> '';

-- Example 5.7 : LEN of empty string is 0; LEN of NULL is NULL.
SELECT LEN('') AS LenEmpty, LEN(NULL) AS LenNull, DATALENGTH('') AS BytesEmpty;

-- Example 5.8 : tricky: a string of only spaces equals '' in SQL Server!
-- Trailing spaces are ignored in = comparisons.
SELECT CASE WHEN '   ' = '' THEN 'equal' ELSE 'different' END AS SpacesVsEmpty;

-- Example 5.9 : so Email = '' also catches values of only spaces. To catch
-- those in every case, trim first.
SELECT COUNT(*) AS BlankOrSpaces
FROM Applicants
WHERE LTRIM(RTRIM(Email)) = '';

-- Example 5.10 : empty string vs NULL when concatenating.
SELECT '' + 'abc' AS EmptyPlus, NULL + 'abc' AS NullPlus, CONCAT(NULL, 'abc') AS ConcatNull;

-- Example 5.11 : COALESCE only fills NULL, not ''. Combine with NULLIF.
SELECT TOP (30) ApplicantID,
       COALESCE(Email, 'missing')                AS OnlyFillsNull,
       COALESCE(NULLIF(Email, ''), 'missing')    AS FillsBoth
FROM Applicants
WHERE Email IS NULL OR Email = '';

-- Example 5.12 : counts: COUNT(Email) includes '' rows.
SELECT COUNT(Email) AS CountEmail, COUNT(NULLIF(Email, '')) AS CountUsableEmail
FROM Applicants;

-- Example 5.13 : tricky: Phone has NULLs but may also carry blank values.
SELECT COUNT(*) AS PhoneNull,
       SUM(CASE WHEN Phone = '' THEN 1 ELSE 0 END) AS PhoneBlank
FROM Applicants
WHERE Phone IS NULL OR Phone = '';

-- Example 5.14 : tricky: leave out applicants who can't be emailed, but keep the
-- phone-only ones for a call list.
SELECT ApplicantID, FirstName, LastName, Phone
FROM Applicants
WHERE NULLIF(LTRIM(RTRIM(Email)), '') IS NULL
  AND NULLIF(LTRIM(RTRIM(Phone)), '') IS NOT NULL;

/*---- Common mistakes : CONCEPT 5 ---------------------------------------------
-- Mistake 1: WHERE Email IS NULL  to find "no email" - misses the '' rows.
-- Mistake 2: WHERE Email = ''  - misses the NULL rows.
-- Mistake 3: WHERE Email <> ''  to find "has email" - drops NULLs by accident
--   (fine here) but people forget it is the NULLs being dropped, not matched.
-- Mistake 4: assuming ' ' (a space) is different from '' in = tests.
-- Mistake 5: using LEN to detect trailing-space differences (LEN ignores them).
--   Use DATALENGTH for bytes.
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 5 ------------------------------------------
Q1. Is  Email = ''  true when Email is NULL?
Q2. SELECT NULLIF('', '');   result?   SELECT NULLIF('a', '');   result?
Q3. SELECT LEN(' a ');   result? (trailing space not counted)
Q4. SELECT COALESCE('', 'x');   result?
ANSWERS: Q1 = No (UNKNOWN). Q2 = NULL, then 'a'. Q3 = 2 (leading space counted,
         trailing ignored). Q4 = '' (empty string is not NULL, so it wins).
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 5 ------------------------------------------------------
Produce a call list: First-time buyer applicants who are IsActive = 1, whose Email is NULL or
blank, and who DO have a real Phone. Show ApplicantID, FirstName, LastName, Phone.
----------------------------------------------------------------------------- */
-- Your answer here:



/*##############################################################################
  CONCEPT 6 : TRIM / LOWER / UPPER FOR DIRTY DATA
##############################################################################*/
/*------------------------------------------------------------------------------
  WHAT IS IT?
  Real data has stray spaces ('  john'), inconsistent case ('SMITH') and
  different spellings ('England', 'UK', 'United Kingdom'). Clean before you compare:
    LTRIM(x) / RTRIM(x)  remove spaces on the left / right
    TRIM(x)              both sides (SQL Server 2017+)
    LOWER(x) / UPPER(x)  change case
  The default collation is case-INsensitive, so LOWER() is not needed for = or
  LIKE, but it matters for display, for case-sensitive databases, and for
  grouping/reporting. Leading spaces always matter; trailing spaces are ignored
  by = but not by LIKE. Wrapping a column in a function stops index use, so
  clean the data at the source when you can.
------------------------------------------------------------------------------*/

-- Example 6.1 : spot the dirty names. Names whose length changes after trimming.
SELECT ApplicantID, FirstName, LastName,
       LEN(FirstName) AS LenRaw, LEN(TRIM(FirstName)) AS LenTrimmed
FROM Applicants
WHERE FirstName <> TRIM(FirstName);

-- Example 6.2 : leading spaces break equality. Compare these two counts.
SELECT COUNT(*) AS ExactJohn          FROM Applicants WHERE FirstName = 'john';
SELECT COUNT(*) AS TrimmedJohn        FROM Applicants WHERE TRIM(FirstName) = 'john';

-- Example 6.3 : TRIM is the same as LTRIM(RTRIM()).
SELECT TOP (10) ApplicantID, '[' + FirstName + ']' AS Raw,
       '[' + TRIM(FirstName) + ']' AS Trimmed,
       '[' + LTRIM(RTRIM(FirstName)) + ']' AS TrimmedOld
FROM Applicants
WHERE FirstName LIKE ' %' OR FirstName LIKE '% ';

-- Example 6.4 : case differences. 'SMITH' vs 'smith' are equal in the default
-- collation, but you still want consistent display.
SELECT TOP (20) ApplicantID, LastName, LOWER(LastName) AS Lowered, UPPER(LastName) AS Uppered
FROM Applicants
WHERE LastName = 'smith';

-- Example 6.5 : proper case, simple version: first letter upper, rest lower.
SELECT TOP (20) ApplicantID,
       UPPER(LEFT(TRIM(FirstName), 1)) + LOWER(SUBSTRING(TRIM(FirstName), 2, 100)) AS CleanFirstName
FROM Applicants;

-- Example 6.6 : filter on cleaned values. All Smiths however they were typed.
SELECT ApplicantID, FirstName, LastName
FROM Applicants
WHERE LOWER(TRIM(LastName)) = 'smith';

-- Example 6.7 : the raw filter misses spaced values (compare with 6.6).
SELECT COUNT(*) AS RawSmith     FROM Applicants WHERE LastName = 'Smith';
SELECT COUNT(*) AS CleanSmith   FROM Applicants WHERE LOWER(TRIM(LastName)) = 'smith';

-- Example 6.8 : leading AND trailing space: LIKE keeps trailing spaces, = ignores them.
SELECT COUNT(*) AS EqualsTrailing FROM Applicants WHERE LastName = 'Smith';
SELECT COUNT(*) AS LikeTrailing   FROM Applicants WHERE LastName LIKE 'Smith';

-- Example 6.9 : messy country values: find all spellings of England.
SELECT Country, COUNT(*) AS Applicants
FROM Applicants
WHERE LOWER(TRIM(Country)) IN ('england', 'uk', 'united kingdom')
GROUP BY Country
ORDER BY Applicants DESC;

-- Example 6.9b : region spelling variants: 'North West' vs 'North-West'.
-- Normalise by trimming, lower-casing and swapping the hyphen for a space.
SELECT TOP (20) ApplicantID, Region
FROM Applicants
WHERE REPLACE(LOWER(TRIM(Region)), '-', ' ') = 'north west';

-- Example 6.10 : standardise on the fly with CASE. One clean value for reporting.
SELECT TOP (30) ApplicantID, Country,
       CASE WHEN LOWER(TRIM(Country)) IN ('england', 'uk', 'united kingdom') THEN 'England'
            ELSE TRIM(Country) END AS CleanCountry
FROM Applicants
WHERE LOWER(TRIM(Country)) IN ('england', 'uk', 'united kingdom');

-- Example 6.11 : count applicants per cleaned country (one England row, not several).
SELECT CASE WHEN LOWER(TRIM(Country)) IN ('england', 'uk', 'united kingdom') THEN 'England'
            ELSE TRIM(Country) END AS CleanCountry,
       COUNT(*) AS Applicants
FROM Applicants
GROUP BY CASE WHEN LOWER(TRIM(Country)) IN ('england', 'uk', 'united kingdom') THEN 'England'
              ELSE TRIM(Country) END
ORDER BY Applicants DESC;

-- Example 6.12 : case-SENSITIVE matching with a collation. Finds only 'England'
-- typed with a capital E (not 'england').
SELECT COUNT(*) AS OnlyCapitalisedEngland
FROM Applicants
WHERE Country = 'England' COLLATE Latin1_General_CS_AS;

-- Example 6.13 : duplicate full names exist (planted). After cleaning there are
-- more duplicates than before cleaning.
SELECT TOP (20)
       LOWER(TRIM(FirstName)) + ' ' + LOWER(TRIM(LastName)) AS CleanFullName,
       COUNT(*) AS Copies
FROM Applicants
GROUP BY LOWER(TRIM(FirstName)) + ' ' + LOWER(TRIM(LastName))
HAVING COUNT(*) > 1
ORDER BY Copies DESC, CleanFullName;

-- Example 6.14 : TRIM with a custom character set (SQL Server 2017+):
-- remove dots and spaces from both ends.
SELECT TRIM('. ' FROM '  ..Hello World..  ') AS Cleaned;

-- Example 6.15 : combine everything: active applicants named O'Brien in any case or spacing.
SELECT ApplicantID, FirstName, LastName, IsActive
FROM Applicants
WHERE LOWER(TRIM(LastName)) = 'o''brien' AND IsActive = 1;

/*---- Common mistakes : CONCEPT 6 ---------------------------------------------
-- Mistake 1: comparing without trimming when data entry is messy (Example 6.2).
-- Mistake 2: trimming only one side. ' a ' needs LTRIM and RTRIM, or TRIM.
-- Mistake 3: LOWER(col) = 'ENGLAND'  never matches (lowered text vs capitals) if
--   the database collation is case sensitive. Lower BOTH sides, or use a
--   consistent literal.
-- Mistake 4: forgetting that TRIM(NULL) is NULL (no error, no match).
-- Mistake 5: applying a function to a column in WHERE of a huge table and
--   wondering why it is slow (indexes cannot be used).
-- Mistake 6: thinking the dirty-data fix changes the table. SELECT never
--   modifies data; it only cleans the output.
----------------------------------------------------------------------------- */

/*---- Predict the output : CONCEPT 6 ------------------------------------------
Q1. SELECT TRIM('  hi  ');   what remains, and what is its LEN?
Q2. SELECT LOWER('SmItH') = 'smith';   (use CASE in practice) true or false in
    a case-insensitive database?
Q3. SELECT '[' + LTRIM('  x') + ']';   result?
Q4. Do 'England', 'england' and 'United Kingdom' count as 1, 2 or 3 distinct values
    under the default collation?
ANSWERS: Q1 = 'hi', 2. Q2 = true (and it would also be true without LOWER).
         Q3 = '[x]'. Q4 = 2 ('England' and 'england' are the same; 'United Kingdom' differs).
----------------------------------------------------------------------------- */

/*---- Try it : CONCEPT 6 ------------------------------------------------------
Count applicants per cleaned (TRIM + LOWER) HouseholdType. Then list applicants whose
cleaned first name is 'john', showing the raw value in square brackets so
you can see the spaces.
----------------------------------------------------------------------------- */
-- Your answer here:

/*==============================================================================
  END OF MODULE 03. Next: practice/module01-03_practice.sql
==============================================================================*/
