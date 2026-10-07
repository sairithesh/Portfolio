USE TRIO_SSS;
GO

/* ============================================================
   Identity Matching: link Student Access records to Banner
   records using T Number ONLY.

   Student Access calls this field "School ID" (currently blank
   for most students, since entry isn't required yet). Banner
   calls the same value "T Number" and displays it at the top of
   every student's profile. When a student's School ID has been
   entered in Student Access, it should be the exact same value
   as their Banner T Number - so this is a direct, deterministic
   match. No name or date-of-birth matching is used anymore.

   Two outcomes, nothing in between:
     MATCHED    - Student Access has a T Number on file, and it
                  exists in Banner -> auto-linked, trusted.
     NOT MATCHED - Student Access has no T Number on file yet
                  (or it doesn't exist in Banner) -> cannot link
                  until the T Number is entered/corrected in
                  Student Access. This is a data-entry gap, not
                  something to guess around.
   ============================================================ */

DELETE FROM dbo.StudentIdentityLink;

-- Matched: Student Access T Number exists and is found in Banner
INSERT INTO dbo.StudentIdentityLink (CaseNumber, TNumber, MatchType, ReviewStatus, MatchedDate, Notes)
SELECT s.CaseNumber, s.TNumber, 'TNumber', 'Auto-Linked', CAST(GETDATE() AS DATE), NULL
FROM dbo.Students s
WHERE s.TNumber IS NOT NULL
  AND EXISTS (SELECT 1 FROM dbo.BannerStudentProfile b WHERE b.TNumber = s.TNumber);

-- Not matched: no T Number on file in Student Access, or it doesn't exist in Banner
INSERT INTO dbo.StudentIdentityLink (CaseNumber, TNumber, MatchType, ReviewStatus, MatchedDate, Notes)
SELECT s.CaseNumber, NULL, 'None', 'Needs T Number', CAST(GETDATE() AS DATE),
       CASE
           WHEN s.TNumber IS NULL
               THEN 'No T Number on file in Student Access - enter the student''s T Number (School ID field) to link this record.'
           ELSE 'T Number entered in Student Access does not match any Banner record - verify it was typed correctly.'
       END
FROM dbo.Students s
WHERE NOT EXISTS (SELECT 1 FROM dbo.StudentIdentityLink l WHERE l.CaseNumber = s.CaseNumber);

-- Summary: how the matching turned out
SELECT MatchType, ReviewStatus, COUNT(*) AS RecordCount
FROM dbo.StudentIdentityLink
GROUP BY MatchType, ReviewStatus
ORDER BY MatchType;
