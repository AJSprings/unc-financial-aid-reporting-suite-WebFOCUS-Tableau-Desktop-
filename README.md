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


Getting Started

This section shows exactly how to run the project locally with:

PostgreSQL (data + reporting views)

Python (synthetic data generator)

Tableau Desktop / Tableau Public (desktop app) (dashboards)

No real student data is used; all data is synthetic.

1. Prerequisites

You will need:

PostgreSQL (tested with 14+)

Python 3.9+

Tableau Desktop or Tableau Public (desktop)

Recommended local setup:

PostgreSQL running on localhost:5432

A database named postgres

A user named postgres with a known password (examples below use YourPassword123!)

2. Clone the Repository
git clone https://github.com/<your-username>/unc-financial-aid-reporting-suite.git
cd unc-financial-aid-reporting-suite


The key folders for setup are:

db/ – schema, views, and data quality test SQL

data/ – Python script to generate synthetic Banner/ODS-style data

3. Install and Configure PostgreSQL

If you do not already have PostgreSQL:

Download the Windows installer from the official PostgreSQL site.

Run the installer and accept defaults:

Components: PostgreSQL + pgAdmin

Port: 5432

Database: postgres (default)

Set a password for the postgres superuser (example: YourPassword123!).

Verify that PostgreSQL is running (for example via pgAdmin by connecting to localhost with user postgres).

You do not need to create a new database for this project; the default postgres database is sufficient.

4. Install Python Dependencies

From the project’s data folder:

cd data
pip install -r requirements.txt


This installs the PostgreSQL driver (psycopg2-binary) used by the data generator.

5. Configure the Database Connection (FA_DSN)

The data generator uses a standard PostgreSQL DSN string via an environment variable called FA_DSN.

Example DSN (adjust if your credentials differ):

dbname=postgres user=postgres password=YourPassword123! host=localhost port=5432


On Windows PowerShell, you can set it as:

setx FA_DSN "dbname=postgres user=postgres password=YourPassword123! host=localhost port=5432"


Close and reopen your terminal after running setx so the variable is available.

If you skip this step, the script will try to use the default:

dbname=postgres user=postgres password=postgres host=localhost port=5432


(which usually will not match your actual password).

6. Build the Schema and Seed Synthetic Data

From the data folder:

cd <path-to-repo>\unc-financial-aid-reporting-suite\data
python generate_data.py


What this script does:

Connects to PostgreSQL using FA_DSN.

Drops and recreates a schema named fa.

Runs db/schema.sql to create all dimension and fact tables.

Populates them with synthetic data (students, terms, aid years, awards, disbursements, COA, scholarships, etc.).

Runs db/views.sql to create the reporting views used by WebFOCUS/Tableau.

If successful, you should see a message similar to:

Seed complete.
Connect Tableau to schema 'fa' and use views: vw_packaging_status, vw_verification_backlog, ...


You can confirm in pgAdmin:

Database: postgres

Schema: fa

Check that tables and views (e.g., vw_packaging_status) exist and contain rows.

7. Run Data Quality Checks (Optional but Recommended)

To demonstrate data quality and reconciliation:

Open pgAdmin and connect to the postgres database.

Open a new query window.

Paste the contents of db/dq_tests.sql.

Execute the script.

This runs a series of checks (orphan records, negative disbursements, verification date anomalies, overaward flags, etc.). You can reference these checks in documentation or screenshots to show how anomalies are detected.

8. Connect Tableau Desktop / Tableau Public to PostgreSQL

Launch Tableau Desktop or Tableau Public (desktop app).

On the start screen, under To a Server, select PostgreSQL.

Enter connection details:

Server: localhost

Port: 5432

Database: postgres

Username: postgres

Password: YourPassword123!

Click Sign In.

On the Data Source page:

Choose the schema fa from the schema dropdown.

Under Tables, you will see objects from the project.

Drag one of the reporting views to the canvas, for example:

vw_packaging_status

vw_verification_backlog

vw_coa_exceptions

vw_offer_vs_disbursement_recon

vw_scholarship_utilization

Each view is already pre-joined and optimized for a particular reporting need.

9. Build Dashboards in Tableau

You can follow the detailed steps in [tableau/dashboard_build_guide.md], but at a high level:

Example: Packaging Status View

Create a new worksheet using the vw_packaging_status data source.

Add fields such as:

aid_year and college as filters.

package_status on Rows.

Number of Records (or a count of students) as a measure.

days_since_fafsa or days_since_last_package_update as additional context.

Example: Verification Work Queue

Create another worksheet using vw_verification_backlog.

Build a table showing:

PIDM, college, major

docs_missing, days_since_selected, sla_flag, priority_score

Filter by aid_year and sla_flag to highlight overdue cases.

Dashboards

Click the New Dashboard icon.

Drag relevant worksheets onto the dashboard.

Add common filters (e.g., aid_year, college, level) and apply them to multiple sheets.

Recommended dashboards (mirroring Financial Aid use cases):

FA Operations Command Center
– High-level KPIs for packaging, verification backlog, reconciliations, COA exceptions.

Verification Work Queue
– Analyst-facing list of students with verification outstanding, prioritized by SLA and missing documentation.

Scholarship & Budget Stewardship
– Scholarship utilization, restricted funds, overaward risk vs COA.

If you are using Tableau Public, you can publish selected dashboards to your Tableau Public profile and link them from this repository or your résumé.

10. Summary

After completing these steps, you will have:

A running PostgreSQL schema (fa) that simulates Banner/ODS Financial Aid data.

A set of validated SQL views designed for operational and compliance reporting.

Tableau dashboards that demonstrate how a Financial Aid Systems analyst can support leadership, operations, and regulatory needs with accurate, well-documented reporting.

This setup is intentionally lightweight: everything runs locally, and all data is synthetic, making it safe to share as part of your portfolio.
