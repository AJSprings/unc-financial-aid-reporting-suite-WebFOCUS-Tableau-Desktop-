-- unc-financial-aid-reporting-suite/db/schema.sql
-- PostgreSQL schema simulating Banner/ODS-style Financial Aid reporting (synthetic, FERPA-safe)

DROP SCHEMA IF EXISTS fa CASCADE;
CREATE SCHEMA fa;
SET search_path = fa;

-- ==============
-- DIMENSIONS
-- ==============

CREATE TABLE dim_term (
  term_code        VARCHAR(6) PRIMARY KEY, -- e.g., 202501 (Spring), 202508 (Fall)
  term_name        TEXT NOT NULL,
  term_start_date  DATE NOT NULL,
  census_date      DATE NOT NULL,
  term_end_date    DATE NOT NULL,
  aid_year         VARCHAR(9) NOT NULL      -- e.g., 2025-2026
);

CREATE TABLE dim_program (
  program_key  SERIAL PRIMARY KEY,
  college      TEXT NOT NULL,
  level        TEXT NOT NULL,     -- UG/GR
  degree       TEXT NOT NULL,     -- BS/BA/MS/etc.
  major        TEXT NOT NULL
);

CREATE TABLE dim_student (
  student_key        SERIAL PRIMARY KEY,
  banner_pidm        INT UNIQUE NOT NULL,
  residency          TEXT NOT NULL,         -- In-State / Out-of-State
  dependency_status  TEXT NOT NULL,         -- Dependent / Independent
  first_gen_flag     BOOLEAN NOT NULL,
  admit_type         TEXT NOT NULL,         -- First-Year / Transfer / Grad
  cohort_year        INT NOT NULL,
  program_key        INT NOT NULL REFERENCES dim_program(program_key)
);

CREATE TABLE dim_aid_fund (
  fund_code        TEXT PRIMARY KEY,
  fund_name        TEXT NOT NULL,
  fund_type        TEXT NOT NULL, -- Pell / Loan / Scholarship / Grant / WorkStudy
  restricted_flag  BOOLEAN NOT NULL
);

-- ==============
-- FACTS
-- ==============

CREATE TABLE fact_enrollment (
  enrollment_id          BIGSERIAL PRIMARY KEY,
  student_key            INT NOT NULL REFERENCES dim_student(student_key),
  term_code              VARCHAR(6) NOT NULL REFERENCES dim_term(term_code),
  credits_attempted      NUMERIC(4,1) NOT NULL,
  credits_enrolled_census NUMERIC(4,1) NOT NULL,
  enrollment_status      TEXT NOT NULL, -- Enrolled / Withdrawn / Not Enrolled
  updated_ts             TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE fact_isir (
  isir_id                BIGSERIAL PRIMARY KEY,
  student_key            INT NOT NULL REFERENCES dim_student(student_key),
  aid_year               VARCHAR(9) NOT NULL,
  sai_efc                INT NOT NULL,
  fafsa_received_date    DATE NOT NULL,
  verification_selected_flag BOOLEAN NOT NULL
);

CREATE TABLE fact_verification (
  verification_id        BIGSERIAL PRIMARY KEY,
  student_key            INT NOT NULL REFERENCES dim_student(student_key),
  aid_year               VARCHAR(9) NOT NULL,
  status                 TEXT NOT NULL, -- Not Selected / Selected / In Progress / Complete
  docs_required_count    INT NOT NULL,
  docs_received_count    INT NOT NULL,
  selected_date          DATE,
  completed_date         DATE,
  updated_by             TEXT NOT NULL DEFAULT 'SYSTEM'
);

CREATE TABLE fact_coa (
  coa_id         BIGSERIAL PRIMARY KEY,
  student_key    INT NOT NULL REFERENCES dim_student(student_key),
  term_code      VARCHAR(6) NOT NULL REFERENCES dim_term(term_code),
  budget_group   TEXT NOT NULL,          -- On Campus / Off Campus / With Parents
  coa_component  TEXT NOT NULL,          -- TuitionFees / Housing / Meals / Books / Transport / Personal
  amount         NUMERIC(10,2) NOT NULL,
  updated_by     TEXT NOT NULL DEFAULT 'SYSTEM',
  updated_ts     TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE fact_award_offer (
  offer_id        BIGSERIAL PRIMARY KEY,
  student_key     INT NOT NULL REFERENCES dim_student(student_key),
  aid_year        VARCHAR(9) NOT NULL,
  fund_code       TEXT NOT NULL REFERENCES dim_aid_fund(fund_code),
  offered_amount  NUMERIC(10,2) NOT NULL,
  offer_date      DATE NOT NULL,
  package_status  TEXT NOT NULL -- NOT_STARTED / IN_PROGRESS / READY / PACKAGED / ERROR
);

CREATE TABLE fact_disbursement (
  disb_id             BIGSERIAL PRIMARY KEY,
  student_key         INT NOT NULL REFERENCES dim_student(student_key),
  term_code           VARCHAR(6) NOT NULL REFERENCES dim_term(term_code),
  fund_code           TEXT NOT NULL REFERENCES dim_aid_fund(fund_code),
  disbursed_amount    NUMERIC(10,2) NOT NULL,
  disbursement_date   DATE NOT NULL,
  disbursement_status TEXT NOT NULL  -- Scheduled / Completed / Reversed
);

CREATE TABLE fact_scholarship (
  scholarship_id        BIGSERIAL PRIMARY KEY,
  student_key           INT NOT NULL REFERENCES dim_student(student_key),
  aid_year              VARCHAR(9) NOT NULL,
  scholarship_code      TEXT NOT NULL,
  amount                NUMERIC(10,2) NOT NULL,
  donor_restricted_flag BOOLEAN NOT NULL,
  renewal_flag          BOOLEAN NOT NULL
);

-- Helpful indexes for reporting performance
CREATE INDEX idx_enroll_student_term ON fact_enrollment(student_key, term_code);
CREATE INDEX idx_isir_student_ay ON fact_isir(student_key, aid_year);
CREATE INDEX idx_offer_student_ay ON fact_award_offer(student_key, aid_year);
CREATE INDEX idx_disb_student_term ON fact_disbursement(student_key, term_code);
CREATE INDEX idx_coa_student_term ON fact_coa(student_key, term_code);
