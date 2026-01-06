-- unc-financial-aid-reporting-suite/db/dq_tests.sql
SET search_path = fa;

-- DQ1: Orphan enrollment (should be zero)
SELECT COUNT(*) AS orphan_enrollment
FROM fact_enrollment e
LEFT JOIN dim_student s ON s.student_key = e.student_key
WHERE s.student_key IS NULL;

-- DQ2: Disbursement without a matching term
SELECT COUNT(*) AS disb_missing_term
FROM fact_disbursement d
LEFT JOIN dim_term t ON t.term_code = d.term_code
WHERE t.term_code IS NULL;

-- DQ3: Negative disbursements not marked Reversed (should be zero)
SELECT COUNT(*) AS invalid_negative_disb
FROM fact_disbursement
WHERE disbursed_amount < 0 AND disbursement_status <> 'Reversed';

-- DQ4: Verification completed before selected (should be zero)
SELECT COUNT(*) AS verification_date_anomaly
FROM fact_verification
WHERE completed_date IS NOT NULL
  AND selected_date IS NOT NULL
  AND completed_date < selected_date;

-- DQ5: Offer records with NOT_STARTED (should be rare; mostly NOT_STARTED should have no offers)
SELECT package_status, COUNT(*) AS cnt
FROM fact_award_offer
GROUP BY package_status
ORDER BY cnt DESC;

-- DQ6: Overaward risk count (for dashboard KPI)
SELECT overaward_flag, COUNT(*) AS cnt
FROM vw_scholarship_utilization
GROUP BY overaward_flag;
