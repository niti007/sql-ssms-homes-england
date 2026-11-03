USE HousingDelivery;
GO
/*==============================================================================
  PRACTICE SET : MODULES 01-03   (Homes England housing delivery data)
  10 business questions, easy -> hard. Several have a TRAP: the obvious query
  runs without error but returns a WRONG answer. Write your own query under
  each question, run it, and ask "does this number make sense?" BEFORE you
  open the SOLUTION block.

  To open a solution: select the lines inside the /* SOLUTION ... */ block
  and un-comment the query (or copy it out below the block).
  UK financial year (FY) runs 1 April to 31 March: FY 2024/25 = 1 Apr 2024 to
  31 Mar 2025.
==============================================================================*/


/*------------------------------------------------------------------------------
  Q1 (easy)  Applicant register snapshot
  The engagement team asks: "How many applicants are on the register, how many
  have an email address we can actually use, and how many different values
  appear in the Country column?" Return one row with three numbers.
------------------------------------------------------------------------------*/
-- Your answer here:


/* SOLUTION Q1
SELECT COUNT(*)                          AS TotalApplicants,
       COUNT(NULLIF(Email, ''))          AS UsableEmails,
       COUNT(DISTINCT Country)           AS DistinctCountryValues
FROM Applicants;
-- TRAP: COUNT(Email) skips NULLs but still counts '' (blank) emails, so it
-- overstates usable emails; and Country holds 'England', 'UK', 'United Kingdom'
-- spellings for the same place, so the distinct count is not "number of countries".
*/


/*------------------------------------------------------------------------------
  Q2 (easy)  Sites in the North West
  "How many sites are in the North West?" Give the count, and also the count
  of those that are brownfield. Note that region names can be typed
  'North West' or 'North-West'.
------------------------------------------------------------------------------*/
-- Your answer here:


/* SOLUTION Q2
SELECT COUNT(*)                                          AS SitesNorthWest,
       SUM(CASE WHEN IsBrownfield = 1 THEN 1 ELSE 0 END) AS Brownfield
FROM Sites
WHERE REPLACE(LOWER(TRIM(Region)), '-', ' ') = 'north west';
-- TRAP: Region = 'North West' alone misses the 'North-West' spelling variant
-- (73 sites instead of 74); IsBrownfield is a BIT so compare to 1, not to text.
*/


/*------------------------------------------------------------------------------
  Q3 (easy-medium)  Lowest-grant live sites
  "Show me the 5 live sites with the LOWEST average grant per home: grant above
  zero (not land-only) and not stalled. If several sites tie for 5th lowest
  grant, show them all." Columns: SiteName, UnitPrice.
------------------------------------------------------------------------------*/
-- Your answer here:


/* SOLUTION Q3
SELECT TOP (5) WITH TIES SiteName, UnitPrice
FROM Sites
WHERE UnitPrice > 0
  AND IsStalled = 0
ORDER BY UnitPrice ASC;
-- TRAP: plain TOP 5 ASC returns the land-only sites (grant 0) and cuts ties
-- randomly; you need the WHERE filter plus WITH TIES (which requires ORDER BY).
*/


/*------------------------------------------------------------------------------
  Q4 (medium)  First-time buyers we cannot email
  The engagement team needs a list of First-time buyer applicants who have NO
  usable email (the field is missing OR blank), showing ApplicantID, FirstName,
  LastName, Phone. Sort by LastName, FirstName, ApplicantID. Also: how many?
------------------------------------------------------------------------------*/
-- Your answer here:


/* SOLUTION Q4
SELECT ApplicantID, FirstName, LastName, Phone
FROM Applicants
WHERE HouseholdType = 'First-time buyer'
  AND (Email IS NULL OR Email = '')
ORDER BY LastName, FirstName, ApplicantID;

-- count version:
SELECT COUNT(*) AS FirstTimeBuyersNoUsableEmail
FROM Applicants
WHERE HouseholdType = 'First-time buyer'
  AND (Email IS NULL OR Email = '');
-- TRAP: "Email = NULL" returns 0 rows, "Email IS NULL" alone misses the blank
-- '' emails, and without brackets the OR escapes the HouseholdType filter.
*/


/*------------------------------------------------------------------------------
  Q5 (medium)  Applications in FY 2024/25
  Finance asks: "How many applications were submitted in FY 2024/25 (1 April
  2024 to 31 March 2025)?" Give the correct number, and also the number of
  applications that a careless BETWEEN '20240401' AND '20250331' filter would
  LOSE.
------------------------------------------------------------------------------*/
-- Your answer here:


/* SOLUTION Q5
SELECT
  (SELECT COUNT(*) FROM Applications
    WHERE ApplicationDate >= '20240401' AND ApplicationDate < '20250401')  AS ApplicationsFY2425,
  (SELECT COUNT(*) FROM Applications
    WHERE ApplicationDate BETWEEN '20240401' AND '20250331')               AS BetweenVersion,
  (SELECT COUNT(*) FROM Applications
    WHERE ApplicationDate > '20250331' AND ApplicationDate < '20250401')   AS LostOn31March;
-- TRAP: ApplicationDate is DATETIME2, so '20250331' means 00:00:00 and every
-- application submitted later on 31 March (including 23:59:59) is silently dropped.
*/


/*------------------------------------------------------------------------------
  Q6 (medium-hard)  Priority applicants in the North West
  Allocations wants ACTIVE applicants in England whose HouseholdType is Key
  worker or First-time buyer and whose Region is the North West. Remember the
  Country is spelled inconsistently ('England', 'england', 'UK', 'United
  Kingdom'), the region may be typed 'North-West', and some values may have
  stray spaces. Show ApplicantID, FirstName, LastName, Region, HouseholdType;
  most recently registered first, then ApplicantID.
------------------------------------------------------------------------------*/
-- Your answer here:


/* SOLUTION Q6
SELECT ApplicantID, FirstName, LastName, Region, HouseholdType
FROM Applicants
WHERE LOWER(TRIM(Country)) IN ('england', 'uk', 'united kingdom')
  AND REPLACE(LOWER(TRIM(Region)), '-', ' ') = 'north west'
  AND HouseholdType IN ('Key worker', 'First-time buyer')
  AND IsActive = 1
ORDER BY RegisteredDate DESC, ApplicantID;
-- TRAP: Country = 'England' misses 'UK' and 'United Kingdom'; NULL regions never
-- match (correct here); and "A OR B AND IsActive = 1" without brackets lets
-- inactive applicants through.
*/


/*------------------------------------------------------------------------------
  Q7 (medium-hard)  Sites with special characters in the name
  The data team is cleaning site names. List every site whose name contains a
  LITERAL percent sign (%) or a LITERAL underscore (_). Show SiteID and
  SiteName. (Expect things like '100% Affordable Scheme' and 'Plot_7 Infill'.)
------------------------------------------------------------------------------*/
-- Your answer here:


/* SOLUTION Q7
SELECT SiteID, SiteName
FROM Sites
WHERE SiteName LIKE '%[%]%'
   OR SiteName LIKE '%[_]%'
ORDER BY SiteName;
-- Alternative: LIKE '%!%%' ESCAPE '!' OR LIKE '%!_%' ESCAPE '!'.
-- TRAP: LIKE '%%%' or '%_%' treat % and _ as wildcards, so every site matches.
*/


/*------------------------------------------------------------------------------
  Q8 (hard)  Tenure types with no sites
  Which tenure types have no sites at all? Show TenureTypeID and TenureName.
  Hint: the Sites table has a handful of rows where TenureTypeID is NULL.
------------------------------------------------------------------------------*/
-- Your answer here:


/* SOLUTION Q8
SELECT TenureTypeID, TenureName
FROM TenureTypes
WHERE TenureTypeID NOT IN (SELECT TenureTypeID FROM Sites WHERE TenureTypeID IS NOT NULL);

-- or, NULL-safe by design:
SELECT t.TenureTypeID, t.TenureName
FROM TenureTypes AS t
WHERE NOT EXISTS (SELECT 1 FROM Sites AS s WHERE s.TenureTypeID = t.TenureTypeID);
-- TRAP: NOT IN (SELECT TenureTypeID FROM Sites) returns ZERO rows because the
-- list contains NULL; the query runs fine but gives a wrong (empty) answer.
-- Expected answer: Self/Custom Build.
*/


/*------------------------------------------------------------------------------
  Q9 (hard)  Find the Smiths and O'Briens
  Applicant services has a list of priority contacts: active applicants whose
  last name is Smith or O'Brien, however it was typed ('SMITH', ' smith ',
  "o'brien"). Return ApplicantID, a cleaned FullName (first + space + last,
  trimmed and in one consistent case of your choice), and RegisteredDate; most
  recently registered first, then ApplicantID.
------------------------------------------------------------------------------*/
-- Your answer here:


/* SOLUTION Q9
SELECT ApplicantID,
       LOWER(TRIM(FirstName)) + ' ' + LOWER(TRIM(LastName)) AS FullName,
       RegisteredDate
FROM Applicants
WHERE LOWER(TRIM(LastName)) IN ('smith', 'o''brien')
  AND IsActive = 1
ORDER BY RegisteredDate DESC, ApplicantID;
-- TRAP: the apostrophe must be doubled ('o''brien'); and NOT trimming/standardising
-- case leaves dirty names in the output (FirstName has stray leading/trailing
-- spaces and mixed case, so FirstName + ' ' + LastName looks wrong). The filter on
-- LastName happens to survive because = ignores trailing spaces and the default
-- collation is case-insensitive, but you should not rely on that.
*/


/*------------------------------------------------------------------------------
  Q10 (hard)  Application data-quality report
  Operations wants a list of suspicious HISTORICAL applications (ApplicationDate
  before 2026-01-01, ignore future-dated test records) where EITHER
     (a) the application was completed BEFORE it was submitted (CompletionDate
         earlier than the date of ApplicationDate), OR
     (b) the status is 'Submitted' but no case officer has been assigned
         (StaffID is missing).
  Show ApplicationID, ApplicationDate, CompletionDate, Status and a column
  Problem saying which rule failed ('Completed before submitted' or 'No case
  officer assigned'). Newest applications first, then ApplicationID. Limit to
  the first 50 rows, keeping ties on the last row.
------------------------------------------------------------------------------*/
-- Your answer here:


/* SOLUTION Q10
SELECT TOP (50) WITH TIES
       ApplicationID, ApplicationDate, CompletionDate, Status,
       CASE WHEN CompletionDate < CAST(ApplicationDate AS DATE) THEN 'Completed before submitted'
            ELSE 'No case officer assigned' END AS Problem
FROM Applications
WHERE ApplicationDate < '20260101'
  AND ( CompletionDate < CAST(ApplicationDate AS DATE)
        OR (Status = 'Submitted' AND StaffID IS NULL) )
ORDER BY CAST(ApplicationDate AS DATE) DESC;
-- TRAP: without brackets, AND binds tighter than OR and future-dated Submitted
-- records with no StaffID leak in; "StaffID = NULL" finds nothing, so rule (b)
-- needs IS NULL. Cast ApplicationDate to DATE before comparing it with a DATE
-- (same-day completions would otherwise be flagged). WITH TIES needs the ORDER BY,
-- and ties are on the DATE only, so you may see a few more than 50 rows.
*/

/*==============================================================================
  END OF PRACTICE SET (modules 01-03)
==============================================================================*/
