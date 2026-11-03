# HomesEngland training dataset spec data dictionary
SQL Server (T-SQL), database `HousingDelivery`, schema `dbo`. Learners are Homes England staff/candidates,
so use realistic English housing vocabulary: local authorities, regions of England, brownfield land,
Affordable Homes Programme, Help to Buy / First Homes / Shared Ownership, registered providers, grant, starts on site, completions.
All data is FICTIONAL (fictional people, partner companies and site names; real English local authority / region names are fine).
Money is GBP.

## Tables
TenureTypes(TenureTypeID INT PK IDENTITY, TenureName NVARCHAR(50) NOT NULL, Description NVARCHAR(200) NULL)
  -- 12 rows: Social Rent, Affordable Rent, London Affordable Rent, Shared Ownership, First Homes, Rent to Buy,
  -- Discounted Market Sale, Market Sale, Build to Rent, Specialist Supported, Older Persons, Self/Custom Build.
  -- 1 tenure (Self/Custom Build) has no sites.
Partners(PartnerID INT PK, PartnerName NVARCHAR(100), PartnerType NVARCHAR(30) /* 'Developer','Registered Provider','Local Authority','SME Builder' */, ContactName NVARCHAR(100) NULL, City NVARCHAR(50), Region NVARCHAR(50), Phone VARCHAR(30) NULL) -- 40 rows
Programmes(ProgrammeID INT PK, ProgrammeName NVARCHAR(80), StartYear INT) -- 5 rows:
  -- Affordable Homes Programme 2021-26, Help to Buy Equity Loan, Brownfield Infrastructure and Land Fund,
  -- Levelling Up Home Building Fund, Community Housing Fund (this one is never used).
Sites(SiteID INT PK, SiteName NVARCHAR(100), TenureTypeID INT FK NULL, PartnerID INT FK, LocalAuthority NVARCHAR(60), Region NVARCHAR(50),
  UnitPrice DECIMAL(10,2) /* average grant per home, £ */, PlannedHomes INT, Hectares DECIMAL(8,2), IsBrownfield BIT, IsStalled BIT /* like Discontinued */, AcquiredDate DATE) -- 500 rows
Applicants(ApplicantID INT PK, FirstName NVARCHAR(50), LastName NVARCHAR(50), Email NVARCHAR(100) NULL, Phone VARCHAR(30) NULL,
  City NVARCHAR(50), Region NVARCHAR(50) NULL /* England region */, Country NVARCHAR(50) /* 'England','UK','United Kingdom','england' inconsistencies */,
  HouseholdType NVARCHAR(20) /* 'First-time buyer','Key worker','Home mover' */, RegisteredDate DATE, IsActive BIT, AnnualIncome DECIMAL(10,2) NULL) -- 10,000 rows
Staff(StaffID INT PK, FirstName, LastName, JobTitle NVARCHAR(60), ManagerID INT NULL FK->Staff, HireDate DATE, Salary DECIMAL(10,2), Office NVARCHAR(50) /* Warrington, London, Bristol, Birmingham, Leeds, Newcastle... */, Directorate NVARCHAR(40)) -- 60 rows, 4-level hierarchy, Chief Executive has ManagerID NULL
Applications(ApplicationID INT PK, ApplicantID INT FK, StaffID INT FK NULL /* NULL = online self-service */, ProgrammeID INT FK NULL,
  ApplicationDate DATETIME2(0), TargetDate DATE, CompletionDate DATE NULL,
  Status NVARCHAR(20) /* 'Submitted','Approved','Completed','Withdrawn','Rejected' */, PropertyCity NVARCHAR(50), PropertyRegion NVARCHAR(50), AdminFee DECIMAL(10,2) NULL) -- 60,000 rows, 2022-01-01..2025-12-31 plus ~20 future-dated
FundingLines(FundingLineID INT PK, ApplicationID INT FK, SiteID INT FK, Homes INT, GrantPerHome DECIMAL(10,2), ClawbackRate DECIMAL(4,2) /* 0..1 */) -- ~180,000 rows

Net funding = Homes * GrantPerHome * (1 - ClawbackRate).

## Planted edge cases (same as before, renamed)
- Applicants: ~8% Email NULL, some Email = ''; ~12% Phone NULL; ~30% Region NULL; ~10% AnnualIncome NULL
- Leading/trailing spaces and mixed case in names; apostrophes (O'Brien, D'Souza); a site with literal '%' or '_' ('100% Affordable Scheme', 'Plot_7 Infill')
- Country inconsistency: 'England','england','UK','United Kingdom'; region spelling variants ('North West' vs 'North-West')
- ~300 applicants with no applications; ~40 sites never funded; 1 tenure with no sites; ~5 sites with TenureTypeID NULL; 1 programme never used
- Sites with UnitPrice = 0 (land-only, no grant); stalled sites still with PlannedHomes > 0
- FundingLines: some Homes = 0, a few negative (reversals/clawbacks), some ClawbackRate = 1.00
- Applications: CompletionDate NULL for Submitted/Withdrawn/Rejected; ~30 with CompletionDate < ApplicationDate (data error); ~600 with no FundingLines; StaffID NULL; ~20 future-dated (2026-2027)
- Dates on 2024-02-29, 31 Mar / 1 Apr (UK financial-year boundary!), Dec 31 / Jan 1, some at 23:59:59
- AdminFee NULL for some, 0 for some
- Staff: tied salaries; Chief Executive ManagerID NULL
- Keep duplicate applicant full names to a realistic level (~5%), use a wide name pool.

Lessons should use UK financial year (Apr–Mar) where natural, e.g. "homes funded in FY 2024/25".
