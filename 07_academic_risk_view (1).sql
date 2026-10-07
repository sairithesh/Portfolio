USE TRIO_SSS;
GO

/* ============================================================
   Academic Risk Flagging
   ============================================================
   Purpose: flag students showing academic warning signs, using
   ONLY academic data (GPA, standing, grades) - no engagement,
   enrollment-status, or cross-system checks yet. Those are
   separate, deliberate future additions, not oversights.

   Five independent flags, each a simple yes/no rule:
     1. Low cumulative GPA on file in Student Access (< 2.0)
     2. Currently on Academic Probation (Student Access)
     3. GPA dropped significantly within the term (Beginning -> Ending)
     4. Low CURRENT term GPA per Banner (the live, authoritative source)
     5. Withdrew from a course in the most recent Banner term (a 'W' grade)

   Flags 4 and 5 use Banner data, so they ONLY apply to students
   with a CONFIRMED identity match (StudentIdentityLink.ReviewStatus
   = 'Auto-Linked'). For students still flagged 'Needs Review' in
   that table, we deliberately do NOT guess which Banner record is
   theirs - they simply won't get flags 4/5 until a human confirms
   the match. This is the same "don't guess" principle from Phase 1,
   applied here instead of skipped.

   RiskLevel is just a count of how many flags fired:
     0 flags -> Not Flagged
     1 flag  -> Low Risk
     2 flags -> Medium Risk
     3+ flags -> High Risk
   ============================================================ */

IF OBJECT_ID('dbo.vw_AcademicRisk', 'V') IS NOT NULL DROP VIEW dbo.vw_AcademicRisk;
GO

CREATE VIEW dbo.vw_AcademicRisk AS
WITH

-- Each student's most recent Student Access year-on-file
LatestYearlyRecord AS (
    SELECT yr.*
    FROM dbo.YearlyRecords yr
    INNER JOIN (
        SELECT StudentID, MAX(ProgramYearID) AS MaxProgramYearID
        FROM dbo.YearlyRecords
        GROUP BY StudentID
    ) latest ON latest.StudentID = yr.StudentID AND latest.MaxProgramYearID = yr.ProgramYearID
),

-- Only students whose Banner identity is CONFIRMED - never guess on the rest
ConfirmedLinks AS (
    SELECT CaseNumber, TNumber
    FROM dbo.StudentIdentityLink
    WHERE ReviewStatus = 'Auto-Linked' AND TNumber IS NOT NULL
),

-- Hardcoded chronological order for the terms this database knows about.
-- (In production this would live as a TermSequence column on a real Terms
-- table - hardcoded here only because this prototype's Banner tables don't
-- have one yet.)
TermOrder AS (
    SELECT * FROM (VALUES
        ('Fall 2023', 1), ('Winter 2024', 2),
        ('Fall 2024', 3), ('Winter 2025', 4),
        ('Fall 2025', 5), ('Winter 2026', 6)
    ) AS t(Term, TermSeq)
),

-- Each confirmed-linked student's most recent Banner term
LatestBannerTerm AS (
    SELECT cl.CaseNumber, g.TNumber, g.Term, o.TermSeq
    FROM dbo.BannerGrades g
    JOIN TermOrder o ON o.Term = g.Term
    JOIN ConfirmedLinks cl ON cl.TNumber = g.TNumber
    INNER JOIN (
        SELECT g2.TNumber, MAX(o2.TermSeq) AS MaxTermSeq
        FROM dbo.BannerGrades g2
        JOIN TermOrder o2 ON o2.Term = g2.Term
        GROUP BY g2.TNumber
    ) latest ON latest.TNumber = g.TNumber AND latest.MaxTermSeq = o.TermSeq
    GROUP BY cl.CaseNumber, g.TNumber, g.Term, o.TermSeq
),

-- Banner-computed GPA and withdrawal check for that latest term only
BannerTermStats AS (
    SELECT
        lbt.CaseNumber,
        lbt.TNumber,
        lbt.Term,
        CASE WHEN SUM(g.GPAHours) > 0
             THEN SUM(g.QualityPoints) / SUM(g.GPAHours)
             ELSE NULL END AS BannerTermGPA,
        MAX(CASE WHEN g.MidtermGrade = 'W' THEN 1 ELSE 0 END) AS HasWithdrawalFlag
    FROM LatestBannerTerm lbt
    JOIN dbo.BannerGrades g ON g.TNumber = lbt.TNumber AND g.Term = lbt.Term
    GROUP BY lbt.CaseNumber, lbt.TNumber, lbt.Term
)

SELECT
    s.StudentID,
    s.CaseNumber,
    s.LastName,
    s.FirstName,

    -- Flag 1: low cumulative GPA on file
    CASE WHEN lyr.EndingCumulativeGPA IS NOT NULL AND lyr.EndingCumulativeGPA < 2.0
         THEN 1 ELSE 0 END AS Flag_LowCumulativeGPA,

    -- Flag 2: currently on academic probation
    CASE WHEN lyr.AcademicStanding = 'Academic Probation'
         THEN 1 ELSE 0 END AS Flag_AcademicProbation,

    -- Flag 3: GPA dropped 0.3+ points within the term
    CASE WHEN lyr.BeginningGPA IS NOT NULL AND lyr.EndingCumulativeGPA IS NOT NULL
              AND (lyr.BeginningGPA - lyr.EndingCumulativeGPA) >= 0.3
         THEN 1 ELSE 0 END AS Flag_GPADeclining,

    -- Flag 4: low CURRENT term GPA per Banner (only for confirmed matches)
    CASE WHEN bts.BannerTermGPA IS NOT NULL AND bts.BannerTermGPA < 2.0
         THEN 1 ELSE 0 END AS Flag_LowBannerTermGPA,

    -- Flag 5: withdrew from a course in the latest Banner term
    CASE WHEN bts.HasWithdrawalFlag = 1
         THEN 1 ELSE 0 END AS Flag_RecentWithdrawal,

    -- Whether Banner-based flags 4/5 could even be checked for this student
    CASE WHEN bts.TNumber IS NOT NULL THEN 1 ELSE 0 END AS BannerDataAvailable,

    lyr.EndingCumulativeGPA AS StudentAccessGPA,
    bp.OverallGPA AS BannerOverallGPA,
    bts.BannerTermGPA,
    lyr.AcademicStanding,

    -- Data-quality check, kept SEPARATE from the risk score on purpose:
    -- a mismatch here means the two systems disagree, not that the
    -- student is struggling. Different problem, different owner.
    -- Banner is the authoritative GPA; if Student Access doesn't match
    -- it EXACTLY, that's a caution flag telling staff to update it.
    CASE WHEN bp.OverallGPA IS NOT NULL AND lyr.EndingCumulativeGPA IS NOT NULL
              AND bp.OverallGPA <> lyr.EndingCumulativeGPA
         THEN 1 ELSE 0 END AS Flag_GPADataMismatch,

    -- Combined score and plain-English risk level
    (CASE WHEN lyr.EndingCumulativeGPA IS NOT NULL AND lyr.EndingCumulativeGPA < 2.0 THEN 1 ELSE 0 END
   + CASE WHEN lyr.AcademicStanding = 'Academic Probation' THEN 1 ELSE 0 END
   + CASE WHEN lyr.BeginningGPA IS NOT NULL AND lyr.EndingCumulativeGPA IS NOT NULL
               AND (lyr.BeginningGPA - lyr.EndingCumulativeGPA) >= 0.3 THEN 1 ELSE 0 END
   + CASE WHEN bts.BannerTermGPA IS NOT NULL AND bts.BannerTermGPA < 2.0 THEN 1 ELSE 0 END
   + CASE WHEN bts.HasWithdrawalFlag = 1 THEN 1 ELSE 0 END) AS RiskFlagCount,

    CASE
        WHEN (CASE WHEN lyr.EndingCumulativeGPA IS NOT NULL AND lyr.EndingCumulativeGPA < 2.0 THEN 1 ELSE 0 END
            + CASE WHEN lyr.AcademicStanding = 'Academic Probation' THEN 1 ELSE 0 END
            + CASE WHEN lyr.BeginningGPA IS NOT NULL AND lyr.EndingCumulativeGPA IS NOT NULL
                        AND (lyr.BeginningGPA - lyr.EndingCumulativeGPA) >= 0.3 THEN 1 ELSE 0 END
            + CASE WHEN bts.BannerTermGPA IS NOT NULL AND bts.BannerTermGPA < 2.0 THEN 1 ELSE 0 END
            + CASE WHEN bts.HasWithdrawalFlag = 1 THEN 1 ELSE 0 END) >= 3 THEN 'High Risk'
        WHEN (CASE WHEN lyr.EndingCumulativeGPA IS NOT NULL AND lyr.EndingCumulativeGPA < 2.0 THEN 1 ELSE 0 END
            + CASE WHEN lyr.AcademicStanding = 'Academic Probation' THEN 1 ELSE 0 END
            + CASE WHEN lyr.BeginningGPA IS NOT NULL AND lyr.EndingCumulativeGPA IS NOT NULL
                        AND (lyr.BeginningGPA - lyr.EndingCumulativeGPA) >= 0.3 THEN 1 ELSE 0 END
            + CASE WHEN bts.BannerTermGPA IS NOT NULL AND bts.BannerTermGPA < 2.0 THEN 1 ELSE 0 END
            + CASE WHEN bts.HasWithdrawalFlag = 1 THEN 1 ELSE 0 END) = 2 THEN 'Medium Risk'
        WHEN (CASE WHEN lyr.EndingCumulativeGPA IS NOT NULL AND lyr.EndingCumulativeGPA < 2.0 THEN 1 ELSE 0 END
            + CASE WHEN lyr.AcademicStanding = 'Academic Probation' THEN 1 ELSE 0 END
            + CASE WHEN lyr.BeginningGPA IS NOT NULL AND lyr.EndingCumulativeGPA IS NOT NULL
                        AND (lyr.BeginningGPA - lyr.EndingCumulativeGPA) >= 0.3 THEN 1 ELSE 0 END
            + CASE WHEN bts.BannerTermGPA IS NOT NULL AND bts.BannerTermGPA < 2.0 THEN 1 ELSE 0 END
            + CASE WHEN bts.HasWithdrawalFlag = 1 THEN 1 ELSE 0 END) = 1 THEN 'Low Risk'
        ELSE 'Not Flagged'
    END AS RiskLevel

FROM dbo.Students s
LEFT JOIN LatestYearlyRecord lyr ON lyr.StudentID = s.StudentID
LEFT JOIN ConfirmedLinks cl2 ON cl2.CaseNumber = s.CaseNumber
LEFT JOIN dbo.BannerStudentProfile bp ON bp.TNumber = cl2.TNumber
LEFT JOIN BannerTermStats bts ON bts.CaseNumber = s.CaseNumber;
GO

-- Quick look: how many students land in each risk level
SELECT RiskLevel, COUNT(*) AS StudentCount
FROM dbo.vw_AcademicRisk
GROUP BY RiskLevel
ORDER BY
    CASE RiskLevel WHEN 'High Risk' THEN 1 WHEN 'Medium Risk' THEN 2 WHEN 'Low Risk' THEN 3 ELSE 4 END;
