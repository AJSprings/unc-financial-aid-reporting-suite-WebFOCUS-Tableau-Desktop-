# Tableau Desktop Build Guide

## Connection
- Connect to PostgreSQL
- Schema: `fa`
- Use these views as sources:
  - `vw_packaging_status`
  - `vw_verification_backlog`
  - `vw_coa_exceptions`
  - `vw_offer_vs_disbursement_recon`
  - `vw_scholarship_utilization`

## Dashboard 1: FA Operations Command Center (Director)
KPIs:
- Packaging completion rate = % package_status = PACKAGED (filter by aid_year)
- Verification backlog count = count of vw_verification_backlog
- Recon review count = count where recon_status = REVIEW
- COA out-of-policy count = count where coa_policy_flag = OUT_OF_POLICY

Filters:
- aid_year, college, level

## Dashboard 2: Verification Work Queue (Analyst)
Primary sheet: table with PIDM, docs_missing, days_since_selected, sla_flag, priority_score
Sort by priority_score descending.
Add filter: college, major, sla_flag.

## Dashboard 3: Scholarship & Budget Stewardship
- Restricted vs total scholarship amounts by college
- Overaward_flag count by college/level
- Renewal prevalence by college
