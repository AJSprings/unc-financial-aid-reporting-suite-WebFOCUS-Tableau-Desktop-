# unc-financial-aid-reporting-suite/data/generate_data.py
import os
import random
from datetime import date, timedelta
import psycopg2

DB_DSN = os.getenv("FA_DSN", "dbname=postgres user=postgres password=postgres host=localhost port=5432")

def daterange(start: date, end: date) -> date:
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, max(delta, 0)))

def main():
    conn = psycopg2.connect(DB_DSN)
    conn.autocommit = True
    cur = conn.cursor()

    # Ensure schema exists
    with open("../db/schema.sql", "r", encoding="utf-8") as f:
        cur.execute(f.read())

    # Seed dimensions
    programs = [
        ("Business", "UG", "BS", "Finance"),
        ("Business", "UG", "BS", "Accounting"),
        ("Engineering", "UG", "BS", "Computer Science"),
        ("Engineering", "UG", "BS", "Mechanical Engineering"),
        ("Arts & Sciences", "UG", "BA", "Psychology"),
        ("Graduate School", "GR", "MS", "Data Science"),
        ("Graduate School", "GR", "MS", "Computer Science"),
    ]
    cur.executemany(
        "INSERT INTO fa.dim_program(college, level, degree, major) VALUES (%s,%s,%s,%s)",
        programs
    )

    terms = [
        ("202501", "Spring 2025", date(2025,1,8), date(2025,1,29), date(2025,5,5), "2024-2025"),
        ("202508", "Fall 2025",   date(2025,8,18), date(2025,9,8),  date(2025,12,10), "2025-2026"),
        ("202601", "Spring 2026", date(2026,1,12), date(2026,2,2),  date(2026,5,6), "2025-2026"),
    ]
    cur.executemany(
        """INSERT INTO fa.dim_term(term_code, term_name, term_start_date, census_date, term_end_date, aid_year)
           VALUES (%s,%s,%s,%s,%s,%s)""",
        terms
    )

    funds = [
        ("PELL", "Federal Pell Grant", "Pell", False),
        ("SUBLN", "Direct Subsidized Loan", "Loan", False),
        ("UNSLN", "Direct Unsubsidized Loan", "Loan", False),
        ("INSTG", "Institutional Grant", "Grant", False),
        ("SCHR1", "Donor Scholarship A", "Scholarship", True),
        ("SCHR2", "Merit Scholarship B", "Scholarship", False),
        ("WS", "Federal Work Study", "WorkStudy", False),
    ]
    cur.executemany(
        "INSERT INTO fa.dim_aid_fund(fund_code, fund_name, fund_type, restricted_flag) VALUES (%s,%s,%s,%s)",
        funds
    )

    # Students
    cur.execute("SELECT program_key, level FROM fa.dim_program")
    program_rows = cur.fetchall()

    n_students = int(os.getenv("FA_N_STUDENTS", "800"))
    pidm_start = 900000

    students = []
    for i in range(n_students):
        program_key, level = random.choice(program_rows)
        residency = random.choices(["In-State","Out-of-State"], weights=[0.75,0.25])[0]
        dependency = random.choices(["Dependent","Independent"], weights=[0.7,0.3])[0]
        first_gen = random.random() < 0.25
        admit_type = random.choices(["First-Year","Transfer","Grad"], weights=[0.55,0.30,0.15])[0]
        cohort_year = random.choice([2023, 2024, 2025, 2026])
        pidm = pidm_start + i
        students.append((pidm, residency, dependency, first_gen, admit_type, cohort_year, program_key))

    cur.executemany(
        """INSERT INTO fa.dim_student(banner_pidm, residency, dependency_status, first_gen_flag, admit_type, cohort_year, program_key)
           VALUES (%s,%s,%s,%s,%s,%s,%s)""",
        students
    )

    # ISIR + Verification
    cur.execute("SELECT student_key FROM fa.dim_student")
    student_keys = [r[0] for r in cur.fetchall()]

    aid_years = ["2024-2025", "2025-2026"]

    isirs = []
    vers = []
    for sk in student_keys:
        for ay in aid_years:
            # FAFSA received dates: earlier for returning AY
            if ay == "2025-2026":
                start = date(2024,10,1)
                end = date(2025,7,15)
            else:
                start = date(2023,10,1)
                end = date(2024,7,15)

            fafsa_dt = daterange(start, end)
            sai = int(max(0, random.gauss(4000, 3000)))  # synthetic SAI/EFC-like
            verification_selected = random.random() < 0.18
            isirs.append((sk, ay, sai, fafsa_dt, verification_selected))

            if verification_selected:
                selected_dt = fafsa_dt + timedelta(days=random.randint(3, 30))
                # completion probability
                completed = random.random() < 0.72
                status = "Complete" if completed else random.choice(["Selected","In Progress"])
                docs_req = random.randint(2, 6)
                if completed:
                    docs_recv = docs_req
                    completed_dt = selected_dt + timedelta(days=random.randint(7, 35))
                else:
                    docs_recv = random.randint(0, docs_req-1)
                    completed_dt = None
                vers.append((sk, ay, status, docs_req, docs_recv, selected_dt, completed_dt, "SYSTEM"))
            else:
                vers.append((sk, ay, "Not Selected", 0, 0, None, None, "SYSTEM"))

    cur.executemany(
        """INSERT INTO fa.fact_isir(student_key, aid_year, sai_efc, fafsa_received_date, verification_selected_flag)
           VALUES (%s,%s,%s,%s,%s)""",
        isirs
    )
    cur.executemany(
        """INSERT INTO fa.fact_verification(student_key, aid_year, status, docs_required_count, docs_received_count, selected_date, completed_date, updated_by)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
        vers
    )

    # Enrollment + COA + Offers + Disbursements + Scholarships
    cur.execute("SELECT term_code, aid_year, term_start_date, census_date, term_end_date FROM fa.dim_term")
    term_rows = cur.fetchall()

    enrollment_rows = []
    coa_rows = []
    offer_rows = []
    disb_rows = []
    scholarship_rows = []

    coa_components = ["TuitionFees","Housing","Meals","Books","Transport","Personal"]
    budget_groups = ["On Campus","Off Campus","With Parents"]

    def base_coa(level: str, budget_group: str) -> float:
        # Synthetic COA patterns by level + budget group
        base = 24000 if level == "UG" else 30000
        if budget_group == "Off Campus":
            base -= 1500
        elif budget_group == "With Parents":
            base -= 6000
        return base

    # fetch student level for COA bands
    cur.execute("""
      SELECT s.student_key, p.level
      FROM fa.dim_student s JOIN fa.dim_program p ON p.program_key = s.program_key
    """)
    student_level = dict(cur.fetchall())

    for sk in student_keys:
        level = student_level[sk]
        for term_code, ay, t_start, census, t_end in term_rows:
            # Enrollment status
            enrolled = random.random() < (0.83 if level == "UG" else 0.78)
            if not enrolled:
                status = random.choice(["Not Enrolled","Withdrawn"])
                attempted = 0.0
                census_credits = 0.0
            else:
                status = "Enrolled"
                attempted = random.choice([12.0, 13.0, 15.0]) if level == "UG" else random.choice([6.0, 9.0])
                # some census drops
                census_credits = max(0.0, attempted - random.choice([0.0, 0.0, 0.0, 3.0]))
            enrollment_rows.append((sk, term_code, attempted, census_credits, status))

            # COA entries: only if enrolled-ish
            if status != "Not Enrolled":
                bg = random.choices(budget_groups, weights=[0.45,0.35,0.20])[0]
                total = base_coa(level, bg) + random.gauss(0, 1200)
                # split across components
                weights = [0.45, 0.20, 0.05, 0.05, 0.05, 0.20]
                for comp, w in zip(coa_components, weights):
                    amt = round(max(0, total * w + random.gauss(0, 150)), 2)
                    # occasional out-of-policy COA overrides for exception reporting
                    updated_by = "USER_OVERRIDE" if random.random() < 0.03 else "SYSTEM"
                    coa_rows.append((sk, term_code, bg, comp, amt, updated_by))

            # Awards/Packaging: only for aid years that match term aid year
            # simulate packaging status driven by FAFSA + verification completion
            if ay in aid_years:
                # package probability
                packaged = random.random() < 0.70
                in_progress = (not packaged) and (random.random() < 0.55)
                if packaged:
                    pkg_status = "PACKAGED"
                elif in_progress:
                    pkg_status = random.choice(["IN_PROGRESS","READY"])
                else:
                    pkg_status = random.choice(["NOT_STARTED","ERROR"])

                # create offers for packaged/in progress/ready
                if pkg_status in ("PACKAGED","IN_PROGRESS","READY"):
                    offer_dt = daterange(t_start - timedelta(days=60), census)
                    # base aid amounts
                    # Pell: more likely low SAI; but keep synthetic and non-sensitive
                    pell = round(max(0, random.gauss(2200, 1400)), 2)
                    subln = round(max(0, random.gauss(1500, 900)), 2)
                    unsln = round(max(0, random.gauss(1200, 800)), 2)
                    instg = round(max(0, random.gauss(900, 600)), 2)

                    for fund_code, amt in [("PELL", pell), ("SUBLN", subln), ("UNSLN", unsln), ("INSTG", instg)]:
                        if amt > 0 and random.random() < 0.85:
                            offer_rows.append((sk, ay, fund_code, amt, offer_dt, pkg_status))

                    # Scholarships: limited and sometimes restricted
                    if random.random() < 0.22:
                        scholarship_code = random.choice(["SCH-A", "SCH-B", "SCH-C"])
                        donor_restricted = random.random() < 0.35
                        renewal = random.random() < 0.40
                        sch_amt = round(max(500, random.gauss(1500, 700)), 2)
                        scholarship_rows.append((sk, ay, scholarship_code, sch_amt, donor_restricted, renewal))
                        # mirror scholarship as an offer fund sometimes
                        offer_rows.append((sk, ay, random.choice(["SCHR1","SCHR2"]), sch_amt, offer_dt, pkg_status))

                # Disbursements: only if enrolled and offers exist (but allow exceptions for recon)
                # We'll disburse about 65% of offered for that term for realism
                # Disbursement date around term start/census
                # Note: disbursements are term-based, offers are aid-year-based
                disb_dt = daterange(t_start, census + timedelta(days=10))
                # We'll insert disb later after offers are inserted (needs offered totals)
                # For simplicity: create some scheduled disb rows now; amount approximate
                if enrolled and pkg_status in ("PACKAGED","READY") and random.random() < 0.60:
                    for fund_code in ["PELL","SUBLN","UNSLN","INSTG"]:
                        if random.random() < 0.55:
                            amt = round(max(0, random.gauss(900, 500)), 2)
                            status = random.choices(["Completed","Scheduled"], weights=[0.78,0.22])[0]
                            disb_rows.append((sk, term_code, fund_code, amt, disb_dt, status))

    cur.executemany(
        """INSERT INTO fa.fact_enrollment(student_key, term_code, credits_attempted, credits_enrolled_census, enrollment_status)
           VALUES (%s,%s,%s,%s,%s)""",
        enrollment_rows
    )
    cur.executemany(
        """INSERT INTO fa.fact_coa(student_key, term_code, budget_group, coa_component, amount, updated_by)
           VALUES (%s,%s,%s,%s,%s,%s)""",
        coa_rows
    )
    cur.executemany(
        """INSERT INTO fa.fact_award_offer(student_key, aid_year, fund_code, offered_amount, offer_date, package_status)
           VALUES (%s,%s,%s,%s,%s,%s)""",
        offer_rows
    )
    cur.executemany(
        """INSERT INTO fa.fact_disbursement(student_key, term_code, fund_code, disbursed_amount, disbursement_date, disbursement_status)
           VALUES (%s,%s,%s,%s,%s,%s)""",
        disb_rows
    )
    cur.executemany(
        """INSERT INTO fa.fact_scholarship(student_key, aid_year, scholarship_code, amount, donor_restricted_flag, renewal_flag)
           VALUES (%s,%s,%s,%s,%s,%s)""",
        scholarship_rows
    )

    # Build views
    with open("../db/views.sql", "r", encoding="utf-8") as f:
        cur.execute(f.read())

    print("Seed complete.")
    print("Connect Tableau to schema 'fa' and use views: vw_packaging_status, vw_verification_backlog, vw_coa_exceptions, vw_offer_vs_disbursement_recon, vw_scholarship_utilization")

    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
