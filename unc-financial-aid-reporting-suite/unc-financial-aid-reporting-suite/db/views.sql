-- unc-financial-aid-reporting-suite/db/views.sql
SET search_path = fa;

-- 1) Packaging status + aging (aid year)
CREATE OR REPLACE VIEW vw_packaging_status AS
WITH base AS (
  SELECT
    s.student_key,
    s.banner_pidm,
    s.residency,
    s.dependency_status,
    s.first_gen_flag,
    s.admit_type,
    s.cohort_year,
    p.college,
    p.level,
    p.degree,
    p.major,
    i.aid_year,
    i.fafsa_received_date,
    i.verification_selected_flag
  FROM dim_student s
  JOIN dim_program p ON p.program_key = s.program_key
  JOIN fact_isir i ON i.student_key = s.student_key
),
pkg AS (
  SELECT
    student_key,
    aid_year,
    MAX(offer_date) AS last_offer_date,
    -- Take the latest status by offer_date
    (ARRAY_AGG(package_status ORDER BY offer_date DESC))[1] AS package_status
  FROM fact_award_offer
  GROUP BY student_key, aid_year
)
SELECT
  b.*,
  COALESCE(pkg.package_status, 'NOT_STARTED') AS package_status,
  pkg.last_offer_date,
  (CURRENT_DATE - b.fafsa_received_date) AS days_since_fafsa,
  CASE WHEN pkg.last_offer_date IS NULL THEN NULL
       ELSE (CURRENT_DATE - pkg.last_offer_date)
  END AS days_since_last_package_update
FROM base b
LEFT JOIN pkg
  ON pkg.student_key = b.student_key
 AND pkg.aid_year = b.aid_year;

-- 2) Verification backlog worklist
CREATE OR REPLACE VIEW vw_verification_backlog AS
SELECT
  s.student_key,
  s.banner_pidm,
  p.college,
  p.level,
  p.major,
  v.aid_year,
  v.status,
  v.docs_required_count,
  v.docs_received_count,
  (v.docs_required_count - v.docs_received_count) AS docs_missing,
  v.selected_date,
  v.completed_date,
  (CURRENT_DATE - v.selected_date) AS days_since_selected,
  CASE
    WHEN v.status IN ('Selected','In Progress') AND (CURRENT_DATE - v.selected_date) >= 21 THEN 'OVERDUE'
    WHEN v.status IN ('Selected','In Progress') THEN 'OPEN'
    ELSE 'N/A'
  END AS sla_flag,
  -- Priority score (simple): more missing docs + older selection
  (COALESCE(v.docs_required_count - v.docs_received_count,0) * 10)
  + COALESCE((CURRENT_DATE - v.selected_date),0) AS priority_score
FROM fact_verification v
JOIN dim_student s ON s.student_key = v.student_key
JOIN dim_program p ON p.program_key = s.program_key
WHERE v.status IN ('Selected','In Progress');

-- 3) COA totals + exceptions (term)
CREATE OR REPLACE VIEW vw_coa_exceptions AS
WITH coa_totals AS (
  SELECT
    c.student_key,
    s.banner_pidm,
    p.college,
    p.level,
    p.major,
    c.term_code,
    t.term_name,
    t.aid_year,
    c.budget_group,
    SUM(c.amount) AS coa_total,
    MAX(c.updated_ts) AS last_updated_ts,
    (ARRAY_AGG(c.updated_by ORDER BY c.updated_ts DESC))[1] AS last_updated_by
  FROM fact_coa c
  JOIN dim_term t ON t.term_code = c.term_code
  JOIN dim_student s ON s.student_key = c.student_key
  JOIN dim_program p ON p.program_key = s.program_key
  GROUP BY 1,2,3,4,5,6,7,8,9
),
bands AS (
  -- Policy bands (synthetic): you can justify these in business_rules.md
  SELECT
    budget_group,
    p_level AS level,
    min_total,
    max_total
  FROM (VALUES
    ('On Campus','UG', 18000::numeric, 35000::numeric),
    ('Off Campus','UG',16000::numeric, 33000::numeric),
    ('With Parents','UG',12000::numeric, 28000::numeric),
    ('On Campus','GR', 20000::numeric, 42000::numeric),
    ('Off Campus','GR',18000::numeric, 40000::numeric),
    ('With Parents','GR',14000::numeric, 32000::numeric)
  ) AS x(budget_group, p_level, min_total, max_total)
)
SELECT
  ct.*,
  b.min_total,
  b.max_total,
  CASE
    WHEN ct.coa_total < b.min_total OR ct.coa_total > b.max_total THEN 'OUT_OF_POLICY'
    ELSE 'IN_POLICY'
  END AS coa_policy_flag
FROM coa_totals ct
JOIN bands b
  ON b.budget_group = ct.budget_group
 AND b.level = ct.level;

-- 4) Offer vs Disbursement reconciliation (aid year + fund)
CREATE OR REPLACE VIEW vw_offer_vs_disbursement_recon AS
WITH offered AS (
  SELECT student_key, aid_year, fund_code, SUM(offered_amount) AS offered_amt
  FROM fact_award_offer
  GROUP BY student_key, aid_year, fund_code
),
disbursed AS (
  SELECT d.student_key, t.aid_year, d.fund_code, SUM(d.disbursed_amount) AS disbursed_amt
  FROM fact_disbursement d
  JOIN dim_term t ON t.term_code = d.term_code
  WHERE d.disbursement_status <> 'Reversed'
  GROUP BY d.student_key, t.aid_year, d.fund_code
)
SELECT
  COALESCE(o.student_key, x.student_key) AS student_key,
  s.banner_pidm,
  p.college,
  p.level,
  COALESCE(o.aid_year, x.aid_year) AS aid_year,
  COALESCE(o.fund_code, x.fund_code) AS fund_code,
  f.fund_type,
  COALESCE(o.offered_amt, 0) AS offered_amt,
  COALESCE(x.disbursed_amt, 0) AS disbursed_amt,
  (COALESCE(o.offered_amt, 0) - COALESCE(x.disbursed_amt, 0)) AS variance,
  CASE
    WHEN ABS(COALESCE(o.offered_amt, 0) - COALESCE(x.disbursed_amt, 0)) >= 500 THEN 'REVIEW'
    ELSE 'OK'
  END AS recon_status
FROM offered o
FULL OUTER JOIN disbursed x
  ON x.student_key = o.student_key
 AND x.aid_year = o.aid_year
 AND x.fund_code = o.fund_code
JOIN dim_student s
  ON s.student_key = COALESCE(o.student_key, x.student_key)
JOIN dim_program p
  ON p.program_key = s.program_key
JOIN dim_aid_fund f
  ON f.fund_code = COALESCE(o.fund_code, x.fund_code);

-- 5) Scholarship utilization + stacking / overaward risk (simple COA cap)
CREATE OR REPLACE VIEW vw_scholarship_utilization AS
WITH schol AS (
  SELECT
    student_key,
    aid_year,
    SUM(amount) FILTER (WHERE donor_restricted_flag) AS restricted_scholar_amt,
    SUM(amount) AS total_scholar_amt,
    BOOL_OR(renewal_flag) AS any_renewal_flag
  FROM fact_scholarship
  GROUP BY student_key, aid_year
),
aid_total AS (
  SELECT
    student_key,
    aid_year,
    SUM(offered_amount) AS total_offered_aid
  FROM fact_award_offer
  GROUP BY student_key, aid_year
),
coa_ay AS (
  -- approximate aid-year COA total by summing terms in that aid year
  SELECT
    c.student_key,
    t.aid_year,
    SUM(c.amount) AS coa_total_ay
  FROM fact_coa c
  JOIN dim_term t ON t.term_code = c.term_code
  GROUP BY c.student_key, t.aid_year
)
SELECT
  s.student_key,
  s.banner_pidm,
  p.college,
  p.level,
  sc.aid_year,
  COALESCE(sc.restricted_scholar_amt,0) AS restricted_scholar_amt,
  COALESCE(sc.total_scholar_amt,0) AS total_scholar_amt,
  COALESCE(a.total_offered_aid,0) AS total_offered_aid,
  COALESCE(ca.coa_total_ay,0) AS coa_total_ay,
  CASE
    WHEN COALESCE(a.total_offered_aid,0) > COALESCE(ca.coa_total_ay,0) THEN 'OVERAWARD_RISK'
    ELSE 'OK'
  END AS overaward_flag,
  sc.any_renewal_flag
FROM schol sc
JOIN dim_student s ON s.student_key = sc.student_key
JOIN dim_program p ON p.program_key = s.program_key
LEFT JOIN aid_total a
  ON a.student_key = sc.student_key
 AND a.aid_year = sc.aid_year
LEFT JOIN coa_ay ca
  ON ca.student_key = sc.student_key
 AND ca.aid_year = sc.aid_year;
