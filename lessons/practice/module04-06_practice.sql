USE HousingDelivery;
GO
/* ============================================================================
   PRACTICE - MODULES 04 to 06  (functions, grouping, joins)
   10 business questions, easy -> hard. Try each one BEFORE opening its solution.
   To check yourself: highlight only the SOLUTION text, remove the comment marks
   (or copy it out), run it, and compare with your own result.
   Net funding = Homes * GrantPerHome * (1 - ClawbackRate)
   UK financial year (FY) runs 1 April to 31 March: FY 2024/25 = 2024-04-01 to 2025-03-31.
   Several questions hit planted data traps - read the "TRAP" line after trying.
   ============================================================================ */


/* ----------------------------------------------------------------------------
   Q1 (easy) - Admin fee check
   Finance asks: how many applications do we have, for how many do we actually know
   the admin fee, and what is the average admin fee? Also give the average if every
   NULL fee were treated as 0, so they can see the difference.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q1
SELECT COUNT(*)                  AS TotalApplications,
       COUNT(AdminFee)           AS ApplicationsWithFee,
       AVG(AdminFee)             AS AvgAdminFee_KnownOnly,
       AVG(ISNULL(AdminFee, 0))  AS AvgAdminFee_NullAsZero
FROM dbo.Applications;
-- TRAP: AVG silently skips NULLs, so the denominator is smaller than COUNT(*); an AdminFee of 0 is
--       a real value and is included, NULL is not.
*/


/* ----------------------------------------------------------------------------
   Q2 (easy) - Contact list cleanup
   The engagement team wants the first 20 applicants (by ApplicantID) with a clean
   display name "Firstname Lastname" (no stray spaces, first letter capital, rest lower
   case) and an email column that shows 'NO EMAIL' when the email is NULL OR an empty string.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q2
SELECT TOP (20) ApplicantID,
       UPPER(LEFT(TRIM(FirstName), 1)) + LOWER(SUBSTRING(TRIM(FirstName), 2, 50)) + ' ' +
       UPPER(LEFT(TRIM(LastName), 1))  + LOWER(SUBSTRING(TRIM(LastName), 2, 50))  AS DisplayName,
       COALESCE(NULLIF(TRIM(Email), ''), 'NO EMAIL') AS Email
FROM dbo.Applicants
ORDER BY ApplicantID;
-- TRAP: '' is not NULL, so ISNULL(Email,'NO EMAIL') misses empty strings - NULLIF turns '' into NULL
--       first. Names like O'Brien become O'brien with this simple rule (acceptable here).
*/


/* ----------------------------------------------------------------------------
   Q3 (easy-medium) - Homes funded per month in FY 2024/25
   How many homes (Homes > 0 only) were funded on applications dated in each month of
   FY 2024/25 (April 2024 to March 2025)? Show the month as 'yyyy-MM', oldest first.
   Applications made late on 31 March 2025 (e.g. 23:59:59) must be included.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q3
SELECT FORMAT(a.ApplicationDate, 'yyyy-MM') AS YearMonth,
       SUM(fl.Homes)                         AS HomesFunded
FROM dbo.Applications a
JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
WHERE a.ApplicationDate >= '2024-04-01' AND a.ApplicationDate < '2025-04-01'
  AND fl.Homes > 0
GROUP BY FORMAT(a.ApplicationDate, 'yyyy-MM')
ORDER BY YearMonth;
-- TRAP: BETWEEN '2024-04-01' AND '2025-03-31' stops at midnight of 31 March and loses the 23:59:59
--       applications; use a half-open range (>= 1 April, < next 1 April), not the calendar year.
*/


/* ----------------------------------------------------------------------------
   Q4 (medium) - Applicants per country (dirty data)
   The policy team wants the number of applicants per country, biggest first. The
   Country column is inconsistent ('England', 'england', 'UK', 'United Kingdom', maybe
   extra spaces). Report them all as one row 'England' and one row for anything else.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q4
SELECT CASE WHEN UPPER(TRIM(Country)) IN ('ENGLAND', 'UK', 'UNITED KINGDOM') THEN 'England'
            ELSE TRIM(Country) END AS CountryClean,
       COUNT(*) AS Applicants
FROM dbo.Applicants
GROUP BY CASE WHEN UPPER(TRIM(Country)) IN ('ENGLAND', 'UK', 'UNITED KINGDOM') THEN 'England'
              ELSE TRIM(Country) END
ORDER BY Applicants DESC;
-- TRAP: with the default case-insensitive collation 'England' and 'england' already merge, but 'UK'
--       and 'United Kingdom' never do; UPPER/TRIM alone is not enough, you need a CASE mapping.
*/


/* ----------------------------------------------------------------------------
   Q5 (medium) - Net grant by region and tenure
   For applications that are not Withdrawn or Rejected, show net funding by site region
   and tenure (include sites with no tenure, labelled '(no tenure)'). Treat 'North West'
   and 'North-West' as the same region. Also show how many 100%-clawback lines and how many
   reversal lines (negative Homes) each region/tenure had. Biggest net funding first.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q5
SELECT REPLACE(TRIM(s.Region), '-', ' ')                                  AS SiteRegion,
       ISNULL(t.TenureName, '(no tenure)')                                AS Tenure,
       SUM(fl.Homes * fl.GrantPerHome * (1 - fl.ClawbackRate))               AS NetFunding,
       SUM(CASE WHEN fl.ClawbackRate = 1 THEN 1 ELSE 0 END)                AS FullClawbackLines,
       SUM(CASE WHEN fl.Homes < 0 THEN 1 ELSE 0 END)                       AS ReversalLines
FROM dbo.Applications a
JOIN dbo.FundingLines AS fl     ON fl.ApplicationID = a.ApplicationID
JOIN dbo.Sites AS s            ON s.SiteID = fl.SiteID
LEFT JOIN dbo.TenureTypes t ON t.TenureTypeID = s.TenureTypeID
WHERE a.Status NOT IN ('Withdrawn', 'Rejected')
GROUP BY REPLACE(TRIM(s.Region), '-', ' '), ISNULL(t.TenureName, '(no tenure)')
ORDER BY NetFunding DESC;
-- TRAP: an INNER JOIN to TenureTypes silently drops sites with TenureTypeID NULL (their funding vanishes);
--       negative Homes reduce net funding (reversals) and ClawbackRate = 1 lines add 0.
*/


/* ----------------------------------------------------------------------------
   Q6 (medium) - Partners with stalled sites
   Which partners have at least one stalled site (IsStalled = 1)? For each show partner
   name, partner type, total sites, stalled sites, planned homes on stalled sites, and the
   percentage of their sites that are stalled (1 decimal). Most planned homes at risk first.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q6
SELECT pr.PartnerName, pr.PartnerType,
       COUNT(*)                                                   AS TotalSites,
       SUM(CAST(s.IsStalled AS INT))                              AS StalledSites,
       SUM(CASE WHEN s.IsStalled = 1 THEN s.PlannedHomes ELSE 0 END) AS HomesAtRisk,
       CAST(100.0 * SUM(CAST(s.IsStalled AS INT)) / COUNT(*) AS DECIMAL(5,1)) AS PctStalled
FROM dbo.Partners AS pr
JOIN dbo.Sites s ON s.PartnerID = pr.PartnerID
GROUP BY pr.PartnerID, pr.PartnerName, pr.PartnerType
HAVING SUM(CAST(s.IsStalled AS INT)) > 0
ORDER BY HomesAtRisk DESC;
-- TRAP: IsStalled is a BIT, so SUM(IsStalled) fails until you CAST it to INT; 100 * int / int would
--       truncate, so use 100.0; stalled sites keep their PlannedHomes, so filter inside the SUM.
*/


/* ----------------------------------------------------------------------------
   Q7 (medium-hard) - Data completeness dashboard
   In ONE result set (rows stacked), report these counts with a label for each:
   (a) applicants who never made an application, (b) sites never funded (no FundingLines),
   (c) applications that have no FundingLines, (d) applications where CompletionDate is earlier
   than the application date, (e) future-dated applications, (f) online self-service applications
   (no StaffID), (g) programmes never used.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q7
SELECT 'Applicants with no applications' AS Check_, COUNT(*) AS Cnt
FROM dbo.Applicants ap
WHERE NOT EXISTS (SELECT 1 FROM dbo.Applications a WHERE a.ApplicantID = ap.ApplicantID)
UNION ALL
SELECT 'Sites never funded', COUNT(*)
FROM dbo.Sites s
LEFT JOIN dbo.FundingLines AS fl ON fl.SiteID = s.SiteID
WHERE fl.FundingLineID IS NULL
UNION ALL
SELECT 'Applications with no funding lines', COUNT(*)
FROM dbo.Applications a
LEFT JOIN dbo.FundingLines AS fl ON fl.ApplicationID = a.ApplicationID
WHERE fl.FundingLineID IS NULL
UNION ALL
SELECT 'Completed before applied', COUNT(*)
FROM dbo.Applications
WHERE CompletionDate < CAST(ApplicationDate AS DATE)
UNION ALL
SELECT 'Future-dated applications', COUNT(*)
FROM dbo.Applications
WHERE ApplicationDate >= '2026-01-01'
UNION ALL
SELECT 'Online applications (no staff member)', COUNT(*)
FROM dbo.Applications
WHERE StaffID IS NULL
UNION ALL
SELECT 'Programmes never used', COUNT(*)
FROM dbo.Programmes AS pg
WHERE NOT EXISTS (SELECT 1 FROM dbo.Applications a WHERE a.ProgrammeID = pg.ProgrammeID);
-- TRAP: use UNION ALL (UNION would de-duplicate and re-sort the checks, and wastes a sort); a NULL
--       CompletionDate makes the comparison UNKNOWN so those rows are correctly not counted.
*/


/* ----------------------------------------------------------------------------
   Q8 (hard) - Programme performance
   For each programme, show applications handled and the average days between application date
   and completion date, using only applications that have a CompletionDate and whose dates make
   sense (not completed before applied). Include the programme that has never been used
   (show 0 applications and NULL average).
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q8
SELECT pg.ProgrammeID, pg.ProgrammeName,
       COUNT(a.ApplicationID)                                          AS CompletedApplications,
       AVG(DATEDIFF(DAY, a.ApplicationDate, a.CompletionDate) * 1.0)   AS AvgDaysToComplete
FROM dbo.Programmes AS pg
LEFT JOIN dbo.Applications a
       ON  a.ProgrammeID    = pg.ProgrammeID
       AND a.CompletionDate IS NOT NULL
       AND a.CompletionDate >= CAST(a.ApplicationDate AS DATE)
GROUP BY pg.ProgrammeID, pg.ProgrammeName
ORDER BY pg.ProgrammeID;
-- TRAP: the application filters must sit in the ON clause - in WHERE they would remove the unused
--       programme (LEFT JOIN becomes INNER). Also AVG of INT days truncates, so multiply by 1.0.
*/


/* ----------------------------------------------------------------------------
   Q9 (hard) - Org chart report
   For every staff member show: name, job title, manager name ('(none - Chief Executive)' for the
   top person), number of direct reports, and whether they earn more than their manager
   ('Yes'/'No'; for the Chief Executive show 'n/a'). Order by manager name then staff name.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q9
SELECT st.StaffID,
       st.FirstName + ' ' + st.LastName                                  AS StaffName,
       st.JobTitle,
       ISNULL(mgr.FirstName + ' ' + mgr.LastName, '(none - Chief Executive)') AS Manager,
       COUNT(rep.StaffID)                                                AS DirectReports,
       CASE WHEN mgr.StaffID IS NULL THEN 'n/a'
            WHEN st.Salary > mgr.Salary THEN 'Yes'
            ELSE 'No' END                                              AS EarnsMoreThanManager
FROM dbo.Staff AS st
LEFT JOIN dbo.Staff AS mgr ON mgr.StaffID   = st.ManagerID
LEFT JOIN dbo.Staff AS rep ON rep.ManagerID = st.StaffID
GROUP BY st.StaffID, st.FirstName, st.LastName, st.JobTitle, st.Salary,
         mgr.StaffID, mgr.FirstName, mgr.LastName, mgr.Salary
ORDER BY Manager, StaffName;
-- TRAP: the Chief Executive has ManagerID NULL, so an INNER self join drops them; counting rep.StaffID
--       (not COUNT(*)) gives 0 for staff with no reports instead of 1.
*/


/* ----------------------------------------------------------------------------
   Q10 (hard) - Household type scorecard for FY 2024/25
   For each applicant HouseholdType, using applications dated in FY 2024/25 (1 April 2024 to
   31 March 2025) that are not Withdrawn, show: number of applications, applications with no
   funding lines, total admin fee (NULL fee counts as 0), gross funding (lines with Homes > 0),
   the value of reversals (negative Homes lines, shown as a positive number), net funding, and
   the percentage of funding lines that were 100% clawed back (2 decimals). The admin fee must
   NOT be inflated by the funding lines.
   ---------------------------------------------------------------------------- */
-- your answer here


/* SOLUTION Q10
SELECT ap.HouseholdType,
       COUNT(*)                                          AS Applications,
       SUM(CASE WHEN x.Lines IS NULL THEN 1 ELSE 0 END)  AS ApplicationsWithoutLines,
       SUM(ISNULL(a.AdminFee, 0))                        AS TotalAdminFee,
       SUM(ISNULL(x.GrossRev, 0))                        AS GrossFunding,
       -SUM(ISNULL(x.ReversalRev, 0))                    AS ReversalsValue,
       SUM(ISNULL(x.GrossRev, 0) + ISNULL(x.ReversalRev, 0)) AS NetFunding,
       CAST(100.0 * SUM(ISNULL(x.FullClawbackLines, 0)) / NULLIF(SUM(ISNULL(x.Lines, 0)), 0)
            AS DECIMAL(5,2))                             AS PctFullClawbackLines
FROM dbo.Applications a
JOIN dbo.Applicants ap ON ap.ApplicantID = a.ApplicantID
LEFT JOIN (SELECT ApplicationID,
                  COUNT(*) AS Lines,
                  SUM(CASE WHEN ClawbackRate = 1 THEN 1 ELSE 0 END) AS FullClawbackLines,
                  SUM(CASE WHEN Homes > 0 THEN Homes * GrantPerHome * (1 - ClawbackRate) ELSE 0 END) AS GrossRev,
                  SUM(CASE WHEN Homes < 0 THEN Homes * GrantPerHome * (1 - ClawbackRate) ELSE 0 END) AS ReversalRev
           FROM dbo.FundingLines
           GROUP BY ApplicationID) AS x ON x.ApplicationID = a.ApplicationID
WHERE a.ApplicationDate >= '2024-04-01' AND a.ApplicationDate < '2025-04-01'
  AND a.Status <> 'Withdrawn'
GROUP BY ap.HouseholdType
ORDER BY NetFunding DESC;
-- TRAP: joining Applications straight to FundingLines multiplies AdminFee once per line; pre-aggregate the
--       lines per application, LEFT JOIN so applications without lines survive, and use 100.0 / NULLIF
--       to avoid integer division and divide-by-zero.
*/
