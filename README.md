# SQL for Homes England: SSMS course (basic → advanced)

A hands-on T-SQL course built on **HousingDelivery**, a fictional but realistic housing-delivery
database: applicants, Help to Buy / Affordable Homes applications, sites, partners, funding lines and staff.
About 250,000 rows in total, with deliberate data-quality traps (NULLs, blank emails, inconsistent spellings,
negative reversals, future-dated records, 31 Mar / 1 Apr financial-year boundaries).

All people, partners and site names are invented. English local authority and region names are real.

## 1. Setup (once per machine)
Requires SQL Server 2019+ (Developer or Express edition is fine) and SSMS.

| Step | Script | Notes |
|---|---|---|
| 1 | `00_setup/01_create_database.sql` | Open in SSMS, F5. Drops and recreates `HousingDelivery`. |
| 2 | `00_setup/02_insert_data.sql` | 16 MB. SSMS can struggle to open it, so run it from a terminal instead: `sqlcmd -S localhost -E -i 00_setup\02_insert_data.sql` (use `-U sa -P ...` for SQL login). This takes 1–3 minutes. |
| 3 | `00_setup/03_verify.sql` | Should show Applications = 60,000 and FundingLines ≈ 179k, plus the counts of each planted edge case. |

To reset the data at any time, re-run steps 1–2. `generate_data.py` (Python 3, fixed seed) regenerates an identical step 2.

## 2. Course path
Teach a lesson by running it one example at a time (highlight a query and press F5).
After each block, learners do the practice set.

| # | Lesson | Topics |
|---|---|---|
| 1 | `module01_select_basics.sql` | SELECT *, columns, aliases, DISTINCT, COUNT, TOP, ORDER BY |
| 2 | `module02_filtering.sql` | WHERE, comparison operators, AND / OR / NOT, precedence |
| 3 | `module03_more_filters.sql` | IN, BETWEEN, LIKE and wildcards, IS NULL, '' vs NULL, dirty text |
| ✍ | `practice/module01-03_practice.sql` | 10 questions |
| 4 | `module04_functions.sql` | Aggregates, NULL handling, string, date, CAST/CONVERT |
| 5 | `module05_grouping.sql` | GROUP BY, HAVING, CASE, pivots, financial-year grouping |
| 6 | `module06_joins.sql` | INNER / LEFT / RIGHT / FULL / CROSS / self join, UNION |
| ✍ | `practice/module04-06_practice.sql` | 10 questions |
| 7 | `module07_subqueries.sql` | Subqueries, correlated, EXISTS vs NOT IN, ANY/ALL, SELECT INTO |
| 8 | `module08_dml_ddl.sql` | INSERT / UPDATE / DELETE (always rolled back), constraints, views, indexes |
| ✍ | `practice/module07-08_practice.sql` | 10 questions |
| 9 | `module09_advanced.sql` | CTEs, recursive org chart, window functions, running totals, functions, stored procedures |
| ✍ | `practice/module09_practice.sql` | 10 questions (run module 9 section H first: it creates `dbo.fn_FinancialYear`) |

## 3. How the practice files work
Each question is followed by its solution, commented out:
```sql
-- Q5. How many applications were submitted in FY 2024/25?
/* SOLUTION Q5
SELECT COUNT(*) FROM Applications
WHERE ApplicationDate >= '2024-04-01' AND ApplicationDate < '2025-04-01';
-- TRAP: BETWEEN '2024-04-01' AND '2025-03-31' misses applications at 31 Mar 23:59:59.
*/
```
Learners write their own query first, then highlight the solution's contents and run it to compare.
Most questions have a **trap**: the obvious query gives a plausible but wrong answer.

## 4. Notes for the trainer
- Module 8 wraps every change in `BEGIN TRAN … ROLLBACK`, and its last section drops all scratch objects, so the shared data stays intact.
- Module 9 leaves its functions and `usp_*` procedures in place, because practice 9 uses them.
- "Financial year" means the UK FY, April to March. FY label: `YEAR(DATEADD(MONTH,-3,ApplicationDate))`.
- The full data dictionary and the list of planted edge cases are in `DATASET.md`.
