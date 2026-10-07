USE TRIO_SSS;
GO

/* ============================================================
   TRIO SSS Student Success Database - v2
   Schema matching the actual Student Access APR Required Fields
   Checklist (Permanent Information + Year Information + Required
   Services + Competitive Preferences) plus Banner/Ellucian data
   and the identity-matching layer that links the two.
   Dialect: T-SQL (Microsoft SQL Server / SSMS)
   ============================================================ */

-- Drop in dependency order: things that reference other tables
-- get dropped BEFORE the tables they reference.
IF OBJECT_ID('dbo.StudentIdentityLink', 'U') IS NOT NULL DROP TABLE dbo.StudentIdentityLink;
IF OBJECT_ID('dbo.BannerGrades', 'U') IS NOT NULL DROP TABLE dbo.BannerGrades;
IF OBJECT_ID('dbo.BannerTermHours', 'U') IS NOT NULL DROP TABLE dbo.BannerTermHours;
IF OBJECT_ID('dbo.BannerRegisteredCourses', 'U') IS NOT NULL DROP TABLE dbo.BannerRegisteredCourses;
IF OBJECT_ID('dbo.BannerStudentProfile', 'U') IS NOT NULL DROP TABLE dbo.BannerStudentProfile;
IF OBJECT_ID('dbo.CompetitivePreferences', 'U') IS NOT NULL DROP TABLE dbo.CompetitivePreferences;
IF OBJECT_ID('dbo.StudentServicesReceived', 'U') IS NOT NULL DROP TABLE dbo.StudentServicesReceived;
IF OBJECT_ID('dbo.RequiredServices', 'U') IS NOT NULL DROP TABLE dbo.RequiredServices;
IF OBJECT_ID('dbo.YearlyRecords', 'U') IS NOT NULL DROP TABLE dbo.YearlyRecords;
IF OBJECT_ID('dbo.Students', 'U') IS NOT NULL DROP TABLE dbo.Students;
IF OBJECT_ID('dbo.ProgramYears', 'U') IS NOT NULL DROP TABLE dbo.ProgramYears;

/* ---------- Reference: Program Years ---------- */
CREATE TABLE dbo.ProgramYears (
    ProgramYearID     INT           PRIMARY KEY,
    ProgramYearLabel  VARCHAR(20)   NOT NULL,
    StartDate         DATE          NOT NULL,
    EndDate           DATE          NOT NULL
);

/* ============================================================
   PERMANENT INFORMATION
   ============================================================ */
CREATE TABLE dbo.Students (
    StudentID                          INT IDENTITY(1,1) PRIMARY KEY,

    CaseNumber                         CHAR(9)       NOT NULL UNIQUE,  -- Student Access's own ID (also called SID)
    TNumber                            CHAR(9)       NULL,             -- Institutional ID, IF Student Access captures it (optional today). Uniqueness enforced via filtered index below.
    LastName                           VARCHAR(50)   NOT NULL,
    FirstName                          VARCHAR(50)   NOT NULL,
    MiddleName                         VARCHAR(50)   NULL,
    NameChangeFlag                     BIT           NOT NULL DEFAULT 0,

    DateOfBirth                        DATE          NOT NULL,
    Gender                             VARCHAR(20)   NOT NULL,

    HispanicEthnicityFlag              BIT           NOT NULL DEFAULT 0,
    RaceAmericanIndianAlaskanNative     BIT           NOT NULL DEFAULT 0,
    RaceAsian                          BIT           NOT NULL DEFAULT 0,
    RaceBlackAfricanAmerican           BIT           NOT NULL DEFAULT 0,
    RaceWhite                          BIT           NOT NULL DEFAULT 0,
    RaceNativeHawaiianPacificIslander  BIT           NOT NULL DEFAULT 0,

    EligibilityCategory                VARCHAR(50)   NOT NULL,
    StudentDisabilityFlag              BIT           NOT NULL DEFAULT 0,
    AcademicNeedFlag                   BIT           NOT NULL DEFAULT 0,

    CohortYear                         INT           NOT NULL,
    InstitutionEntryDate               DATE          NOT NULL,
    ProgramEntryLevel                  VARCHAR(20)   NOT NULL,
    ProgramEntryEnrollmentStatus       VARCHAR(20)   NOT NULL,

    FirstServiceDate                   DATE          NOT NULL,
    LastServiceDate                    DATE          NULL,
    UndergraduateCompletionDate        DATE          NULL,
    DegreeCompletedStatus              VARCHAR(30)   NULL,
    FieldOfStudyDegreeEarned           VARCHAR(100)  NULL
);

-- Filtered unique index: TNumber must be unique WHEN PRESENT, but any number
-- of students can have TNumber = NULL (true for all of them today).
CREATE UNIQUE INDEX UQ_Students_TNumber ON dbo.Students(TNumber) WHERE TNumber IS NOT NULL;

/* ============================================================
   YEAR INFORMATION
   ============================================================ */
CREATE TABLE dbo.YearlyRecords (
    YearlyRecordID          INT IDENTITY(1,1) PRIMARY KEY,
    StudentID                INT           NOT NULL REFERENCES dbo.Students(StudentID),
    ProgramYearID              INT         NOT NULL REFERENCES dbo.ProgramYears(ProgramYearID),

    ParticipantStatus            VARCHAR(30) NOT NULL,
    EnrollmentStatus               VARCHAR(30) NOT NULL,
    AcademicStanding                  VARCHAR(30) NOT NULL,
    EndingCumulativeGPA                  DECIMAL(3,2) NULL,
    CollegeGradeLevelStart                 VARCHAR(20) NOT NULL,
    CollegeGradeLevelEnd                     VARCHAR(20) NOT NULL,
    ReasonForWithdrawal                        VARCHAR(50) NULL,
    TransferStatus                               VARCHAR(30) NULL,
    FuturePersistenceStatus                        VARCHAR(30) NULL,

    FinancialAidReceivedFlag                          BIT NOT NULL DEFAULT 0,
    GrantAidAmount                                       DECIMAL(9,2) NULL,

    -- From Student Access "Term Info" tab (not APR-required, but useful for internal dashboard)
    BeginningGPA                                           DECIMAL(3,2) NULL,
    TermCreditsAttempted                                      DECIMAL(4,1) NULL,
    TermCreditsCompleted                                         DECIMAL(4,1) NULL,
    EndEnrollmentStatus                                             VARCHAR(30) NULL,
    CommentsForTerm                                                    VARCHAR(500) NULL,

    CONSTRAINT UQ_Student_ProgramYear UNIQUE (StudentID, ProgramYearID)
);

/* ============================================================
   REQUIRED SERVICES (APR Section I, Part 2)
   ============================================================ */
CREATE TABLE dbo.RequiredServices (
    ServiceCode          INT           PRIMARY KEY,
    ServiceDescription   VARCHAR(200)  NOT NULL
);

INSERT INTO dbo.RequiredServices (ServiceCode, ServiceDescription) VALUES
(1, 'Academic Tutoring'),
(2, 'Advice and assistance in postsecondary course selection'),
(3, 'Education/counseling to improve financial and economic literacy'),
(4, 'Information on applying for Federal Student Aid'),
(5, 'Assistance completing and applying for Federal Student Aid'),
(6, 'Assistance applying for admission to Graduate School and obtaining Federal Student Aid'),
(7, 'Assistance applying for admission to a 4-Year Institution and obtaining Federal Student Aid');

CREATE TABLE dbo.StudentServicesReceived (
    RecordID          INT IDENTITY(1,1) PRIMARY KEY,
    StudentID          INT   NOT NULL REFERENCES dbo.Students(StudentID),
    ProgramYearID        INT NOT NULL REFERENCES dbo.ProgramYears(ProgramYearID),
    ServiceCode            INT NOT NULL REFERENCES dbo.RequiredServices(ServiceCode),
    ReceivedFlag              BIT NOT NULL DEFAULT 0,
    CONSTRAINT UQ_Student_Year_Service UNIQUE (StudentID, ProgramYearID, ServiceCode)
);

/* ============================================================
   COMPETITIVE PREFERENCE PRIORITIES (APR Section I, Part 3)
   ============================================================ */
CREATE TABLE dbo.CompetitivePreferences (
    StudentID                            INT NOT NULL REFERENCES dbo.Students(StudentID),
    ProgramYearID                          INT NOT NULL REFERENCES dbo.ProgramYears(ProgramYearID),
    CompetitivePreferencePriority1Flag        BIT NOT NULL DEFAULT 0,
    CompetitivePreferencePriority2Flag          BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_CompetitivePreferences PRIMARY KEY (StudentID, ProgramYearID)
);

/* ============================================================
   BANNER / ELLUCIAN - INSTITUTIONAL SYSTEM OF RECORD
   ============================================================
   Second, independent source system. Looked up one student at a
   time via self-service (no bulk export available to TRIO staff).
   Joined to dbo.Students via dbo.StudentIdentityLink, NOT a direct
   foreign key - the two systems share no common ID today.
   ============================================================ */

CREATE TABLE dbo.BannerStudentProfile (
    TNumber                CHAR(9)       PRIMARY KEY,   -- Banner's own ID - NOT shared with Student Access
    LastName                 VARCHAR(50)  NOT NULL,
    FirstName                  VARCHAR(50) NOT NULL,
    Email                    VARCHAR(100) NULL,
    Phone                      VARCHAR(20) NULL,
    Gender                       VARCHAR(20) NULL,
    DateOfBirthMonthDay            VARCHAR(5) NULL,      -- Banner self-service masks birth year; 'MM/DD' only
    EthnicityHispanicLatino          VARCHAR(30) NULL,   -- 'Hispanic or Latino' / 'Not Hispanic or Latino'
    Race                                VARCHAR(50) NULL,
    CitizenFlag                           VARCHAR(5) NULL,
    CitizenshipType                          VARCHAR(30) NULL,
    EmergencyContact                            VARCHAR(100) NULL,
    EmergencyPhone                                 VARCHAR(20) NULL,

    Level                     VARCHAR(20) NULL,
    ClassLevel                  VARCHAR(20) NULL,
    EnrollmentStatusBanner         VARCHAR(20) NULL,
    StudentType                       VARCHAR(20) NULL,
    Residency                            VARCHAR(50) NULL,
    Campus                                  VARCHAR(50) NULL,
    FirstTermAttended                          VARCHAR(20) NULL,
    MatriculatedTerm                              VARCHAR(20) NULL,
    LastTermAttended                                 VARCHAR(20) NULL,
    LeaveOfAbsence                                      VARCHAR(30) NULL,
    GraduationApplicationStatus                            VARCHAR(30) NULL,

    -- From the dashboard header - real, authoritative, NOT calculated from course data
    OverallGPA                 DECIMAL(3,2) NULL,
    OverallHours                  DECIMAL(5,1) NULL,
    AcademicStandingAsOf             VARCHAR(20) NULL,  -- e.g. 'Summer 2026' - the term this standing reflects

    LastRefreshedDate         DATE NULL
);

CREATE TABLE dbo.BannerRegisteredCourses (
    RecordID          INT IDENTITY(1,1) PRIMARY KEY,
    TNumber             CHAR(9)      NOT NULL REFERENCES dbo.BannerStudentProfile(TNumber),
    Term                  VARCHAR(20) NOT NULL,
    CourseTitle              VARCHAR(100) NOT NULL,
    CRN                         CHAR(5)   NOT NULL,
    Hours                          DECIMAL(3,1) NOT NULL,
    RegistrationStatus                VARCHAR(20) NOT NULL,
    Instructor                           VARCHAR(80) NULL
);

CREATE TABLE dbo.BannerTermHours (
    TNumber           CHAR(9)      NOT NULL REFERENCES dbo.BannerStudentProfile(TNumber),
    Term                VARCHAR(20) NOT NULL,
    RegisteredHours       DECIMAL(4,1) NOT NULL,
    BillingHours             DECIMAL(4,1) NOT NULL,
    CEUHours                    DECIMAL(4,1) NOT NULL DEFAULT 0,
    MinHours                       DECIMAL(4,1) NOT NULL DEFAULT 0,
    MaxHours                          DECIMAL(4,1) NOT NULL,
    CONSTRAINT PK_BannerTermHours PRIMARY KEY (TNumber, Term)
);

CREATE TABLE dbo.BannerGrades (
    RecordID          INT IDENTITY(1,1) PRIMARY KEY,
    TNumber             CHAR(9)      NOT NULL REFERENCES dbo.BannerStudentProfile(TNumber),
    Term                  VARCHAR(20) NOT NULL,
    CRN                     CHAR(5)   NOT NULL,
    Subject                    VARCHAR(10) NOT NULL,
    CourseTitle                   VARCHAR(100) NOT NULL,
    MidtermGrade                     VARCHAR(5) NULL,
    AttemptedHours                      DECIMAL(3,1) NOT NULL,
    EarnedHours                            DECIMAL(3,1) NOT NULL,
    GPAHours                                  DECIMAL(3,1) NOT NULL,
    QualityPoints                                DECIMAL(5,2) NOT NULL
);

/* ============================================================
   STUDENT IDENTITY LINK
   ============================================================
   Resolves identity between Student Access (CaseNumber) and
   Banner (TNumber), since they share no common ID today. Built
   by 06_identity_matching.sql. See that file for full logic.
   ============================================================ */
CREATE TABLE dbo.StudentIdentityLink (
    LinkID             INT IDENTITY(1,1) PRIMARY KEY,
    CaseNumber           CHAR(9)      NULL REFERENCES dbo.Students(CaseNumber),
    TNumber                CHAR(9)   NULL REFERENCES dbo.BannerStudentProfile(TNumber),
    MatchType                VARCHAR(10) NOT NULL,
    ReviewStatus                VARCHAR(20) NOT NULL DEFAULT 'Auto-Linked',
    MatchedDate                    DATE NOT NULL,
    Notes                             VARCHAR(300) NULL
);
