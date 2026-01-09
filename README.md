# UNC Financial Aid Reporting Suite (WebFOCUS + Tableau Desktop)

This project simulates a Banner/ODS-style Financial Aid reporting environment using PostgreSQL and synthetic FERPA-safe data. It delivers:
- Validated SQL reporting views (awarding/packaging, verification, COA, scholarships, reconciliation)
- WebFOCUS-style parameterized procedures (FEX) and ReportCaster scheduling specs
- Tableau Desktop dashboards for leadership and operational work queues

## Why this exists
Financial Aid reporting requires high accuracy across complex data domains: awarding/packaging, estimated COA, verification, enrollment/census, scholarships, and compliance-style audits. This repo demonstrates end-to-end capability from data modeling to validated reporting outputs and distribution patterns.

## Data Model (Banner/ODS-inspired)
Schema: `fa`
- Dimensions: students, programs, terms, aid funds
- Facts: ISIR/FAFSA, verification, awards/offers, disbursements, COA, scholarships, enrollment

## Key Reporting Views (connect Tableau to these)
- `vw_packaging_status` — packaging status + aging since FAFSA / last update
- `vw_verification_backlog` — verification worklist with SLA + priority scoring
- `vw_coa_exceptions` — COA totals with policy band exception flags
- `vw_offer_vs_disbursement_recon` — offered vs disbursed reconciliation with REVIEW flags
- `vw_scholarship_utilization` — restricted utilization + overaward risk indicator

## WebFOCUS Artifacts
- `/webfocus/fex` contains parameter-driven procedures mapping to the SQL views
- `/webfocus/reportcaster/schedules.yml` documents schedule + bursting logic
- `/webfocus/report_central` documents a self-service folder + access model

## Run Locally
### 1) Create database objects + seed synthetic data
- Create a local Postgres instance
- Set DSN in an environment variable:

```bash
export FA_DSN="dbname=postgres user=postgres password=postgres host=localhost port=5432"

pip install -r data/requirements.txt

cd data
python generate_data.py

