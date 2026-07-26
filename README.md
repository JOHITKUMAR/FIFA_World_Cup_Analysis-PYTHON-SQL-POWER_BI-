# FIFA_World_Cup_Analysis-PYTHON-SQL-POWER_BI-
# FIFA World Cup Analytics Dashboard

An end-to-end analytics project covering **90+ years of FIFA World Cup history (1930–2026)**. Raw data is ingested from two independent public sources plus one hand-verified manual dataset, transformed into a unified star schema in PostgreSQL (Supabase), and visualized through a 7-page interactive Power BI dashboard.

---

## 1. Project Architecture

```
GitHub (raw CSV data)  --->  Python (ingest_*.py)  --->  Supabase PostgreSQL (raw_ tables)
                                                                  |
                                                                  v
                                                   SQL transform scripts (1, 2, 3)
                                                                  |
                                                                  v
                                                   Star Schema (dim_ / fact_ tables)
                                                                  |
                                                                  v
                                                        Power BI (.pbix report)
```

This follows an **ELT pattern** (Extract, Load, then Transform): raw data lands untouched first, and all cleaning/reshaping happens afterward in SQL — so there's always an unmodified original to fall back on if a transform step needs revisiting.

---

## 2. Data Sources

| Source | Coverage | Tables | License | Notes |
|---|---|---|---|---|
| `jfjelstul/worldcup` (GitHub) | Men's & Women's World Cups, 1930–2022 | 22 tables (tournaments, matches, goals, bookings, players, managers, referees, awards, etc.) | CC-BY-SA 4.0 (attribution required) | Independently compiled historical backbone — thorough and well cross-checked, but a secondary compilation, not FIFA's own live feed |
| `mominullptr/FIFA-World-Cup-2026-Dataset` (GitHub) | 2026 World Cup only | 10 tables (matches, match_events, match_team_stats, squads_and_players, venues, referees, etc.) | CC0 (public domain, no attribution required) | Far richer than any historical source: expected goals (xG), market value, ELO ratings, possession, shot stats. Because no historical equivalent exists, these fields describe 2026 in isolation — a snapshot, not a trend |
| Manual (hand-verified) | 2026 award winners only | 1 table (`raw_manual_2026_awards`) | — | 6 rows (Golden Ball, Golden Boot, Silver Boot, Bronze Boot, Golden Glove, Best Young Player), cross-checked against Britannica, NBC Sports, Bleacher Report, and Olympics.com — the one genuinely hand-entered table in the project, since neither GitHub source tracks 2026 awards at all |

**What was consulted but never became data:** Wikipedia's FIFA World Cup records page was read once, purely to decide how to handle historical country splits and reunifications (Germany, Czechoslovakia, the Soviet Union, Yugoslavia, Zaire). It informed a modeling decision — no row of data was ever pulled from it into any table. Every number in the final model traces back to only the three sources above.

### Known incompleteness (accepted on purpose)
No football dataset is complete, and this project doesn't hide that:
- **Fouls** exist only for 2026 — older tournaments never tracked them.
- **Cards** exist only from 1970 onward, because the card system itself wasn't introduced before then.
- **Awards vary by year** — FIFA introduced the Golden Ball (1978), Best Young Player (1958), and Golden Glove (1994) at different points, so earlier tournaments correctly show fewer award rows than later ones.
- **Penalty shootouts** only record the outcome (scored/missed) for 2026, not kicking order.

### Filtering decisions already made
- Scoped to **men's tournaments only** — filtered out during the SQL stage.
- Team names are **conformed across both sources** through a verified mapping (e.g. Türkiye→Turkey, IR Iran→Iran, Zaire→Congo DR).
- **West and East Germany are merged** into one team, Germany — a stricter merge than FIFA's own convention.
- Four genuinely new 2026 teams (**Cabo Verde, Curaçao, Jordan, Uzbekistan**) are added as new rows, since they have no historical match to merge into.
- Historical splits (**Czechoslovakia, the Soviet Union, Yugoslavia**) are deliberately left unmerged, so every successor country starts with a clean slate.

---

## 3. Why a Cloud Database (Supabase)?

A database on your own laptop can only ever be reached by your own laptop. **Supabase** provides a real Postgres database running in the cloud, reachable by Python, by Power BI Desktop, and later by anyone who opens the published report. That reachability is what makes the final step of this project — sharing a working report — possible at all.

---

## 4. Setup & Data Import (Command Line)

### Step 1 — Create a Supabase account and organization
1. Go to **supabase.com** and sign up (email, or GitHub/Google sign-in).
2. Create an **organization** first (Supabase requires this before letting you create a project) — this is just how Supabase groups projects together.
3. Choose the **Free plan**.

### Step 2 — Create your project
Inside the organization, click **New project** and fill in:

| Field | What to enter | Why |
|---|---|---|
| Project name | Something clear, e.g. `worldcup-analytics-capstone` | Just a label, easy to rename later |
| Database password | Click **Generate**, then re-generate until it's letters + numbers only | Avoids special characters like `@ # /` needing extra escaping in code later |
| Region | Whichever is closest to you | Affects speed once Power BI is querying the database live |

Before clicking **Create**, set these security options:
- **Automatically expose new tables** → **uncheck**. Tables don't need to be reachable through Supabase's public web API — this project connects directly with a username and password.
- **Enable automatic RLS** → **leave unchecked**. Row Level Security is for apps with untrusted public users; this project is the only one querying the database directly.

Click **Create new project** and wait 1–2 minutes while it provisions.

⚠️ **Copy the database password the moment it's shown — Supabase will not display it again in full.**

### Step 3 — Get your 5 connection values
1. Click the green **Connect** button (top of the project page).
2. Click the **Direct** tab (database icon — not Framework/Server/ORM/MCP).
3. Choose **Session pooler** — not "Direct connection" and not "Transaction pooler".
4. Scroll to where **host, port, database,** and **user** are listed separately — these, plus your saved password, are your 5 values.

> **Why Session pooler specifically?** "Direct connection" defaults to an IPv6 network format that many external tools can't reliably reach — including a published Power BI report later. Session pooler avoids that problem and is what this project is built around.

Write your 5 values down:
```
HOST:     (from the Session pooler screen)
PORT:     5432
DATABASE: postgres
USER:     postgres.<your-own-project-ref>
PASSWORD: (the one saved in Step 2)
```

### Step 4 — Set up your project folder
```bash
mkdir "FIFA World Cup Project"
cd "FIFA World Cup Project"
# place ingest_raw.py, ingest_manual_2026_awards.py, and .env.example inside this folder
```
Rename `.env.example` to `.env`, open it, and replace the placeholders with your 5 values from Step 3:

```
SUPABASE_USER=postgres.your-project-ref
SUPABASE_PASSWORD=your_generated_password
SUPABASE_HOST=your_session_pooler_host
SUPABASE_PORT=5432
SUPABASE_DB=postgres
```

⚠️ **Never share your `.env` file** — not in a group chat, not on GitHub, not pasted into any AI tool. It holds your database password in plain text. Keeping credentials separate from the scripts is what keeps the scripts themselves safe to share — but only if `.env` stays private.

### Step 5 — Open Command Prompt at your project folder
1. Open **File Explorer** and navigate into your project folder.
2. Click once on the **address bar** at the top (selects the full path).
3. Type `cmd` and press **Enter**.
4. A Command Prompt window opens, already pointed at your project folder — the folder path appears right before the blinking cursor.

Every command typed next runs "from" wherever Command Prompt is pointed — this is what lets Python find `.env` and the scripts sitting right next to it without typing full paths each time.

### Step 6 — Install the Python libraries (once per computer)
```bash
pip install pandas sqlalchemy psycopg2-binary python-dotenv
```
This downloads four toolkits: `pandas` (spreadsheet-shaped data), `sqlalchemy` + `psycopg2` (talking to Postgres), and `python-dotenv` (reading `.env`). You'll see "Successfully installed" lines when done. This only needs to run once per computer, not once per project.

### Step 7 — Run the raw ingestion script
This downloads all 32 CSVs from both GitHub sources and lands them as `raw_*` tables in Supabase, untouched.

```bash
python ingest_raw.py
```

**Expected output** — one line per table (real confirmed run, all 32 tables, no errors):
```
loaded raw_jfjelstul_tournaments                    rows=   38  cols=18
loaded raw_jfjelstul_confederations                 rows=    6  cols=5
loaded raw_jfjelstul_host_countries                 rows=   31  cols=7
loaded raw_jfjelstul_teams                          rows=   88  cols=14
loaded raw_jfjelstul_matches                        rows= 1248  cols=37
loaded raw_jfjelstul_goals                          rows= 3637  cols=27
loaded raw_jfjelstul_bookings                       rows= 3178  cols=26
loaded raw_jfjelstul_substitutions                  rows=10222  cols=24
loaded raw_jfjelstul_penalty_kicks                   rows=  396  cols=19
loaded raw_jfjelstul_players                        rows=10401  cols=13
loaded raw_jfjelstul_squads                         rows=13843  cols=12
loaded raw_jfjelstul_player_appearances              rows=27432  cols=21
loaded raw_jfjelstul_team_appearances                rows= 2496  cols=36
loaded raw_jfjelstul_groups                         rows=  159  cols=7
loaded raw_jfjelstul_group_standings                rows=  626  cols=19
loaded raw_jfjelstul_awards                         rows=    8  cols=5
loaded raw_jfjelstul_award_winners                  rows=  200  cols=12
loaded raw_jfjelstul_managers                       rows=  475  cols=7
loaded raw_jfjelstul_manager_appointments            rows=  637  cols=8
loaded raw_jfjelstul_manager_appearances             rows= 2538  cols=17
loaded raw_jfjelstul_referees                       rows=  493  cols=10
loaded raw_jfjelstul_referee_appointments            rows=  668  cols=10
loaded raw_jfjelstul_qualified_teams                rows=  625  cols=8
loaded raw_mominullptr_2026_teams                   rows=   48  cols=8
loaded raw_mominullptr_2026_venues                  rows=   16  cols=8
loaded raw_mominullptr_2026_tournament_stages        rows=    7  cols=3
loaded raw_mominullptr_2026_referees                 rows=   28  cols=4
loaded raw_mominullptr_2026_matches                  rows=  104  cols=17
loaded raw_mominullptr_2026_match_events             rows=  834  cols=6
loaded raw_mominullptr_2026_match_team_stats          rows=  208  cols=12
loaded raw_mominullptr_2026_match_prediction_features rows=  104  cols=66
loaded raw_mominullptr_2026_squads_and_players        rows= 1248  cols=10
loaded raw_mominullptr_2026_match_lineups             rows= 5408  cols=7

Done. Raw tables are now in your Supabase 'public' schema, prefixed 'raw_'.
```

This script is **safe to re-run** — `if_exists="replace"` means every run wipes and rebuilds the raw tables fresh with no duplication risk.

> **If something goes wrong here**, it's almost always one of two things: your `.env` file has a typo in one of the 5 values, or the database password wasn't saved correctly. Double-check both against Supabase's connection screen before retrying.

### Step 8 — Run the manual 2026 awards ingestion script
This loads the hand-verified 2026 award winners (Golden Ball, Golden Boot, etc.) that don't exist in either GitHub source. It follows the exact same `.env`/connection pattern as Step 7 — it just writes 6 hand-typed rows instead of downloading a CSV.

```bash
python ingest_manual_2026_awards.py
```

**Expected output:**
```
Loaded raw_manual_2026_awards: 6 rows
```

Once this prints, the database holds everything the project needs in raw form: **32 tables from GitHub + 1 hand-verified table = 33 raw tables total.**

### ✅ Checkpoint — folder structure
Before moving to SQL, the project folder should contain exactly these 4 items:
```
FIFA World Cup Project/
├── .env                              (your filled-in credentials)
├── ingest_raw.py
├── ingest_manual_2026_awards.py
└── setup_guide.pdf                   (kept for reference)
```

---

## 5. SQL Transformation — From Raw to Modeled

### Where we left off
At this point, 33 raw tables sit in Supabase — all prefixed `raw_`, and all still messy: the two GitHub sources don't agree on team names, one mixes men's and women's tournaments, and neither is shaped for direct reporting. This is expected — landing data raw first, then cleaning it visibly in SQL, is the whole point of the ELT approach.

### The story: what's actually wrong with this data
These two GitHub datasets were built independently, years apart, for different purposes — never designed to be joined. Combining them takes deliberate work:

| Problem | Description |
|---|---|
| **No relationships at all** | Every raw table is flat — no primary/foreign keys connecting anything |
| **Two incompatible ID systems** | Historical source uses text codes (e.g. `"T-01"`); 2026 source uses plain integers. No formula converts one to the other — matching has to happen by team **name** instead |
| **Same country, different names** | 2026 data says "Türkiye", historical says "Turkey" (also Iran, Ivory Coast, Czech Republic, USA) — left unresolved, a name match would treat these as 8 countries instead of 4 |
| **Two competitions mixed into one** | The historical file contains men's and women's World Cups in a single table, distinguished only by a text label — this project filters to men's only, consistently, everywhere (matches, goals, cards, awards) |
| **2026 doesn't exist yet in the historical table** | The historical dataset was published before 2022 stopped — no row represents "2026" until one is added by hand |
| **Stoppage time as text, not numbers** | 2026 event data records goals like `"90+3"` — direct arithmetic fails until this text is parsed |
| **Everything mixed into one event log** | The 2026 dataset logs goals, cards, assists, and VAR reviews in one shared table — counting "goals" without filtering that label would silently include other event types |
| **Rich 2026 data with nowhere to put it** | xG, market value, ELO, possession have no historical equivalent — can't be added as columns onto historical tables without 92 years of empty values and unfair "highest xG ever" comparisons |
| **Bare IDs with no names attached** | Referee and "player of the match" in the 2026 match data are plain ID numbers pointing at nothing — no lookup table exists yet |
| **Two gaps needing two different fixes** | No dataset records 2026 award winners (added by hand); cards are structured completely differently per source (dedicated table historically vs. buried in the event log for 2026) |

### Same country, different era — the project's own call
History doesn't always draw clean lines around "one team." Rather than quietly inherit FIFA's own inconsistent approach (FIFA merges West Germany into Germany, but keeps East Germany separate), this project makes its own explicit, documented decisions:
- **Germany's two halves are merged** into one team — deliberately simpler than FIFA's own rule.
- **Zaire is merged into Congo DR** — a straight rename of the same country, not a split.
- **Czechoslovakia, the Soviet Union, and Yugoslavia stay separate** — every successor state (Czech Republic, Slovakia, Russia, Ukraine, Serbia, Croatia, etc.) starts fresh with zero inherited history.

None of this happens invisibly — every decision lives as a plain, readable row in `team_name_overrides`.

### A bug worth knowing (the lesson generalizes)
`dim_tournament` stores its winner as plain text, copied straight from the historical source. When West Germany and Zaire were merged, that text column wasn't automatically updated — it still said **"West Germany"** for 1954, 1974, and 1990, long after `dim_team` stopped having a row by that name. Any measure comparing a tournament's winner against a team's name would have silently missed those titles. **The fix:** a second-pass `UPDATE` statement runs after `team_name_overrides` exists, re-mapping the winner text through the same overrides used everywhere else.

> **General lesson:** any column that duplicates a name elsewhere in your model has to be kept in sync by hand whenever that name changes — it never updates itself just because the "real" table did.

### The three SQL scripts, what each solves

| File | Builds | Solves |
|---|---|---|
| `1_transform_star_schema.sql` | 6 core tables: `dim_team`, `dim_tournament`, `dim_venue`, `dim_stage`, `fact_matches`, `fact_goals` | Reconciles team names, filters to men's-only, adds 2026 to the tournament list, fixes broken minute formatting |
| `2_transform_2026_deepdive.sql` | 7 tables: 2026 team/venue/referee/player detail, match stats, full event log | Adds rich 2026-only detail (xG, market value, ELO, possession) without forcing it onto historical data |
| `3_transform_awards_bookings.sql` | `fact_awards`, `fact_bookings` | Fills the 2026 awards gap; unifies yellow/red cards across both eras |

Each script also carries its own detailed problem list as comments at the top — worth reading before running.

### Why the order matters
Each script needs tables the previous one built: File 2 looks for `dim_team` and `fact_matches` (only exist after File 1); File 3 looks for `fact_match_events_2026` (only exists after File 2). Running out of order fails with a `"relation does not exist"` error — that error almost always means a numbered step got skipped.

### Step 9 — Run the SQL transform scripts (in Supabase SQL Editor)
For each of the 3 files, in order:
1. Open Supabase project → **SQL Editor** → click **+** for a new query.
2. Open the `.sql` file, select all, copy.
3. Paste into the query editor.
4. Rename the query tab to match the filename.
5. Click **Run**.
6. Run the sanity-check queries in the comment block at the bottom of that same file.

> `"Success. No rows returned"` is normal — these scripts are `CREATE TABLE`/`INSERT` statements, not `SELECT`s, so there's nothing to display until the separate sanity checks are run.

All three scripts are **safe to re-run** — each drops and rebuilds its own tables at the start, without touching the `raw_*` tables underneath.

### Step 10 — Verify each file with its sanity checks

| After running… | Run this check | Expect |
|---|---|---|
| `1_transform_star_schema.sql` | `SELECT source, COUNT(*) FROM fact_matches GROUP BY source;` | ~964 (jfjelstul), 104 (mominullptr_2026) |
| | `SELECT COUNT(*) FROM fact_matches WHERE home_team_key IS NULL OR away_team_key IS NULL;` | 0 |
| | `SELECT team_name FROM dim_team WHERE team_name IN ('Germany','Congo DR','West Germany','Zaire');` | Germany, Congo DR only |
| | `SELECT DISTINCT winner FROM dim_tournament WHERE winner ILIKE '%germany%';` | Germany only |
| `2_transform_2026_deepdive.sql` | `SELECT COUNT(*) FROM dim_player_2026;` | 1248 |
| `3_transform_awards_bookings.sql` | `SELECT source, COUNT(*) FROM fact_awards GROUP BY source;` | manual_2026 = 6 |

If a number doesn't match, fix it before moving to the next file.

### ✅ Final checkpoint before Power BI
Open Supabase's **Table Editor** and confirm **15 new tables without the `raw_` prefix**, alongside the 33 raw ones:
- `dim_team`, `dim_tournament`, `dim_venue`, `dim_stage`, `fact_matches`, `fact_goals`
- `dim_team_2026_attributes`, `dim_venue_2026_attributes`, `dim_referee_2026`, `dim_player_2026`, `fact_matches_2026_detail`, `fact_match_team_stats_2026`, `fact_match_events_2026`
- `fact_awards`, `fact_bookings`

This is the real finish line for the database side of the project — every later step (Power BI, DAX, the published report) only ever reads from these 15 tables, never from the raw ones again.

### Step 11 — Connect Power BI to Supabase
1. Open Power BI Desktop → **Get Data** → **PostgreSQL database**
2. Enter your Supabase host and database name
3. Authenticate with your Supabase username/password
4. Select all `dim_*` and `fact_*` tables (skip `raw_*` tables — they're only needed at the transform stage)
5. Load, then build/refresh your report

---

## 6. Data Model Summary

| Layer | Tables |
|---|---|
| **Dimensions** | `dim_team`, `dim_tournament`, `dim_venue`, `dim_stage`, `dim_player_2026`, `dim_referee_2026`, `dim_team_2026_attributes`, `dim_venue_2026_attributes` |
| **Facts** | `fact_matches`, `fact_goals`, `fact_bookings`, `fact_awards`, `fact_matches_2026_detail`, `fact_match_team_stats_2026`, `fact_match_events_2026` |

---

## 7. Dashboard Pages

The Power BI report is organized into **7 pages**, each with a distinct analytical focus.

### Page 1 — Tournament Overview
Whole-history view with no team filter applied — sets the scene before drilling into specifics.

| Visual | Type | Fields Used |
|---|---|---|
| KPI cards | Card | `Total Matches Played`, `Total Goals Scored`, `Total Yellow Cards (1970–2026)`, `Total Second Yellow Cards (1970–2026)` |
| Goals over time | Line chart | X: `dim_tournament[year]`, Y: `Total Goals Scored` |
| Top teams by wins | Bar chart | Y: `dim_team[team_name]`, X: `Total Wins` |
| Matches by host | Map / column chart | `dim_tournament[host_country]` |

---

### Page 2 — Team Deep-Dive
A Team slicer (`dim_team[team_name]`) drives every visual on this page.

| Visual | Type | Fields Used |
|---|---|---|
| Summary cards | Card | `Total Wins`, `Total Draws`, `Total Losses`, `Total Matches Played`, `Title Wins` |
| Win/Draw/Loss split | Donut chart | Values: `Total Wins`, `Total Draws`, `Total Losses` |
| Editions won | Matrix | Rows: `dim_tournament[year]`, filtered to years the selected team won |
| Team card tooltip | Report-page tooltip | Same 5 measures, condensed on a small tooltip page linked to Page 1's bar chart |

---

### Page 3 — Penalties & Shootouts
Highlights how penalty-taking has evolved between the historical era and 2026.

| Visual | Type | Fields Used |
|---|---|---|
| In-play vs shootout goals | Cards (side by side) | `In-Play Penalty Goals (1930–2022)`, `Shootout Goals (2026 Only)` |
| Shootout appearances by team | Clustered bar chart | Y: `dim_team[team_name]` (Top 10), X: `Penalty Shootout Matches` |
| Penalty goals trend | Line chart | X: `dim_tournament[year]`, Y: `In-Play Penalty Goals (1930–2022)` & `Shootout Goals (2026 Only)` |

> ⚠️ **Known issue flagged during build:** `Penalty Shootout Matches` and `Penalty Shootout Matches (All Editions)` contain identical DAX. One should be renamed or deleted to avoid confusing report consumers.

---

### Page 4 — Discipline (Cards)
Covers yellow/red card trends across both data sources.

| Visual | Type | Fields Used |
|---|---|---|
| Cards by year | Stacked column chart | X: `dim_tournament[year]`, Y: `Total Yellow Cards (1970–2026)` & `Total Second Yellow Cards (1970–2026)` |
| Cards by team | Bar chart | Y: `dim_team[team_name]`, Legend: `fact_bookings[card_type]`, X: `Total Cards` |
| Cards by source | Stacked column chart | Legend: `fact_bookings[source]` — visually shows the 1970 cutoff between historical and 2026 card data |
| Overall card distribution | Donut chart | Values: `Total Yellow Cards`, `Total Second Yellow Cards`, `Total Red Cards (1970–2026)` |

---

### Page 5 — 2026 Spotlight
A dedicated "This Year's Tournament" page, filtered entirely to `WC-2026`.

| Visual | Type | Fields Used |
|---|---|---|
| 2026 award winners | Table | `fact_awards[award_name]`, `player_name`, `dim_team[team_name]`, filtered to `source = "manual_2026"` |
| Shootout goals (2026) | Card | `Shootout Goals (2026 Only)` (copied from Page 3) |
| Matches played (2026) | Card | `Total Matches Played (2026)` |
| Page-level filter | Filter pane | `dim_tournament[tournament_id] = "WC-2026"` applied to the whole page |

---

### Page 6 — 2026 Deep Dive
Puts the richest, 2026-exclusive tables to use — data that has no historical equivalent.

| Visual | Type | Fields Used |
|---|---|---|
| Match quality stats | Cards | `Avg Possession %`, `Avg Shots Per Match`, `Avg xG Per Match` |
| xG vs actual goals | Scatter chart | X: `Total xG`, Y: `Total Actual Goals`, Detail: `fact_matches[match_key]` |
| Top players by market value | Table | `dim_player_2026[player_name]`, `market_value_eur`, `team_name` (Top 15) |
| Referees by avg cards/game | Bar chart | Y: `dim_referee_2026[referee_name]`, X: `avg_cards_per_game` |
| Venue details | Table | `dim_venue[stadium_name]`, `city`, `dim_venue_2026_attributes[capacity]`, `elevation_meters` |
| Venue bubble map | Map | Lat/Long: `dim_venue_2026_attributes`, Bubble size: `capacity` |

---

### Page 7 — Match Explorer
A drill-through page for match-level detail — the "match center" of the dashboard.

| Visual | Type | Fields Used |
|---|---|---|
| Match info card | Card | `dim_team[team_name]` (home/away), `Match Score` measure |
| Event timeline | Table | `fact_match_events_2026[minute]`, `event_type`, `dim_player_2026[player_name]`, `dim_team[team_name]` |
| Team stats comparison | Matrix | Rows: `dim_team[team_name]`, Values: `possession_pct`, `total_shots`, `shots_on_target`, `corners` |
| Referee & POTM | Card | `dim_referee_2026[referee_name]`, `dim_player_2026[player_name]` |

Drill-through is configured on `fact_matches[match_key]`; right-clicking any match-level data point on other pages surfaces a "Drill through → Match Explorer" option.

---

## 8. Key DAX Measures

| Measure | Purpose |
|---|---|
| `Total Matches Played` | Matches played by the selected team |
| `Total Wins` / `Total Draws` / `Total Losses` | Win/draw/loss counts for the selected team |
| `Title Wins` | Number of World Cups won by the selected team |
| `Total Goals Scored` | All non-own-goals across both eras |
| `In-Play Penalty Goals (1930–2022)` | Penalty goals scored in normal play, historical era only |
| `Shootout Goals (2026 Only)` | Penalty shootout goals, 2026 only |
| `Penalty Shootout Matches` | Matches decided by a shootout, involving the selected team |
| `Total Yellow Cards (1970–2026)` / `Total Second Yellow Cards (1970–2026)` | Card counts spanning both sources |
| `Avg Possession %` / `Avg Shots Per Match` / `Avg xG Per Match` | 2026-only match quality metrics |

---

## 9. Tech Stack

- **Python** — `pandas`, `sqlalchemy`, `psycopg2`, `python-dotenv` for ELT ingestion
- **PostgreSQL (Supabase)** — cloud data warehouse and SQL transform layer
- **Power BI** — star-schema semantic model, DAX measures, and interactive reporting
- **Data sources** — two open-source GitHub datasets + one manually verified 2026 awards dataset
