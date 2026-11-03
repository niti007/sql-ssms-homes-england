/* HousingDelivery - create database and tables (all data is fictional) */
USE master;
GO
IF DB_ID(N'HousingDelivery') IS NOT NULL
BEGIN
    ALTER DATABASE HousingDelivery SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE HousingDelivery;
END
GO
CREATE DATABASE HousingDelivery;
GO
USE HousingDelivery;
GO

CREATE TABLE dbo.TenureTypes (
    TenureTypeID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TenureTypes PRIMARY KEY,
    TenureName   NVARCHAR(50)  NOT NULL,
    Description  NVARCHAR(200) NULL
);
GO
CREATE TABLE dbo.Partners (
    PartnerID   INT NOT NULL CONSTRAINT PK_Partners PRIMARY KEY,
    PartnerName NVARCHAR(100) NOT NULL,
    PartnerType NVARCHAR(30)  NOT NULL CONSTRAINT CK_Partners_Type CHECK (PartnerType IN (N'Developer', N'Registered Provider', N'Local Authority', N'SME Builder')),
    ContactName NVARCHAR(100) NULL,
    City        NVARCHAR(50)  NOT NULL,
    Region      NVARCHAR(50)  NOT NULL,
    Phone       VARCHAR(30)   NULL
);
GO
CREATE TABLE dbo.Programmes (
    ProgrammeID   INT NOT NULL CONSTRAINT PK_Programmes PRIMARY KEY,
    ProgrammeName NVARCHAR(80) NOT NULL,
    StartYear     INT NOT NULL
);
GO
CREATE TABLE dbo.Sites (
    SiteID         INT NOT NULL CONSTRAINT PK_Sites PRIMARY KEY,
    SiteName       NVARCHAR(100) NOT NULL,
    TenureTypeID   INT NULL CONSTRAINT FK_Sites_TenureTypes REFERENCES dbo.TenureTypes(TenureTypeID),
    PartnerID      INT NOT NULL CONSTRAINT FK_Sites_Partners REFERENCES dbo.Partners(PartnerID),
    LocalAuthority NVARCHAR(60) NOT NULL,
    Region         NVARCHAR(50) NOT NULL,
    UnitPrice      DECIMAL(10,2) NOT NULL,  -- average grant per home, GBP
    PlannedHomes   INT NOT NULL,
    Hectares       DECIMAL(8,2) NOT NULL,
    IsBrownfield   BIT NOT NULL,
    IsStalled      BIT NOT NULL,
    AcquiredDate   DATE NOT NULL
);
GO
CREATE TABLE dbo.Applicants (
    ApplicantID   INT NOT NULL CONSTRAINT PK_Applicants PRIMARY KEY,
    FirstName     NVARCHAR(50)  NOT NULL,
    LastName      NVARCHAR(50)  NOT NULL,
    Email         NVARCHAR(100) NULL,
    Phone         VARCHAR(30)   NULL,
    City          NVARCHAR(50)  NOT NULL,
    Region        NVARCHAR(50)  NULL,
    Country       NVARCHAR(50)  NOT NULL,
    HouseholdType NVARCHAR(20)  NOT NULL CONSTRAINT CK_Applicants_Household CHECK (HouseholdType IN (N'First-time buyer', N'Key worker', N'Home mover')),
    RegisteredDate DATE NOT NULL,
    IsActive      BIT NOT NULL,
    AnnualIncome  DECIMAL(10,2) NULL
);
GO
CREATE TABLE dbo.Staff (
    StaffID     INT NOT NULL CONSTRAINT PK_Staff PRIMARY KEY,
    FirstName   NVARCHAR(50) NOT NULL,
    LastName    NVARCHAR(50) NOT NULL,
    JobTitle    NVARCHAR(60) NOT NULL,
    ManagerID   INT NULL CONSTRAINT FK_Staff_Manager REFERENCES dbo.Staff(StaffID),
    HireDate    DATE NOT NULL,
    Salary      DECIMAL(10,2) NOT NULL,
    Office      NVARCHAR(50) NOT NULL,
    Directorate NVARCHAR(40) NOT NULL
);
GO
CREATE TABLE dbo.Applications (
    ApplicationID   INT NOT NULL CONSTRAINT PK_Applications PRIMARY KEY,
    ApplicantID     INT NOT NULL CONSTRAINT FK_Applications_Applicants REFERENCES dbo.Applicants(ApplicantID),
    StaffID         INT NULL CONSTRAINT FK_Applications_Staff REFERENCES dbo.Staff(StaffID),
    ProgrammeID     INT NULL CONSTRAINT FK_Applications_Programmes REFERENCES dbo.Programmes(ProgrammeID),
    ApplicationDate DATETIME2(0) NOT NULL,
    TargetDate      DATE NOT NULL,
    CompletionDate  DATE NULL,
    Status          NVARCHAR(20) NOT NULL CONSTRAINT CK_Applications_Status CHECK (Status IN (N'Submitted', N'Approved', N'Completed', N'Withdrawn', N'Rejected')),
    PropertyCity    NVARCHAR(50) NOT NULL,
    PropertyRegion  NVARCHAR(50) NOT NULL,
    AdminFee        DECIMAL(10,2) NULL
);
GO
CREATE TABLE dbo.FundingLines (
    FundingLineID INT NOT NULL CONSTRAINT PK_FundingLines PRIMARY KEY,
    ApplicationID INT NOT NULL CONSTRAINT FK_FundingLines_Applications REFERENCES dbo.Applications(ApplicationID),
    SiteID        INT NOT NULL CONSTRAINT FK_FundingLines_Sites REFERENCES dbo.Sites(SiteID),
    Homes         INT NOT NULL,
    GrantPerHome  DECIMAL(10,2) NOT NULL,
    ClawbackRate  DECIMAL(4,2) NOT NULL CONSTRAINT CK_FundingLines_Clawback CHECK (ClawbackRate BETWEEN 0 AND 1)
);
GO
