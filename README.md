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

| Source | Coverage | Tables | Notes |
|---|---|---|---|
| `jfjelstul/worldcup` (GitHub) | Men's & Women's World Cups, 1930–2022 | 22 tables (tournaments, matches, goals, bookings, players, etc.) | Historical backbone of the model |
| `mominullptr/FIFA-World-Cup-2026-Dataset` (GitHub) | 2026 World Cup only | 10 tables (matches, match_events, team_stats, squads, venues, etc.) | Rich detail: xG, ELO, market value, possession |
| Manual (hand-verified) | 2026 award winners only | 1 table (`raw_manual_2026_awards`) | Cross-checked against Britannica, NBC Sports, Bleacher Report, Olympics.com — not available in either GitHub source |

---

## 3. Setup & Data Import (Command Line)

### Step 1 — Prerequisites
- Python 3.9+
- A Supabase account with a project already created (this is the cloud PostgreSQL database)
- pip installed

### Step 2 — Clone/download the project files
```bash
mkdir fifa-worldcup-project
cd fifa-worldcup-project
# copy ingest_raw.py, ingest_manual_2026_awards.py, the 3 .sql files, and .env into this folder
```

### Step 3 — Install required Python libraries
```bash
pip install pandas sqlalchemy psycopg2-binary python-dotenv
```

### Step 4 — Create the `.env` file
In the same folder, create a file named `.env` with your Supabase credentials:

```
SUPABASE_USER=your_supabase_username
SUPABASE_PASSWORD=your_supabase_password
SUPABASE_HOST=your_project.supabase.co
SUPABASE_PORT=5432
SUPABASE_DB=postgres
```

⚠️ **Never commit `.env` to GitHub or share it** — it holds your database password.

### Step 5 — Run the raw ingestion script
This downloads all 32 CSVs from both GitHub sources and lands them as `raw_*` tables in Supabase, untouched.

```bash
python ingest_raw.py
```

Expected output (one line per table):
```
loaded raw_jfjelstul_tournaments                    rows=  22  cols=9
loaded raw_jfjelstul_matches                        rows= 964  cols=15
...
loaded raw_mominullptr_2026_matches                 rows= 104  cols=12
Done. Raw tables are now in your Supabase 'public' schema, prefixed 'raw_'.
```

This script is **safe to re-run** — `if_exists="replace"` means every run wipes and rebuilds the raw tables fresh with no duplication risk.

### Step 6 — Run the manual 2026 awards ingestion script
This loads the hand-verified 2026 award winners (Golden Ball, Golden Boot, etc.) that don't exist in either GitHub source.

```bash
python ingest_manual_2026_awards.py
```

Expected output:
```
Loaded raw_manual_2026_awards: 6 rows
```

### Step 7 — Run the SQL transform scripts (in Supabase SQL Editor)
Open your Supabase project → **SQL Editor**, and run each script **in this exact order** (paste the whole file, click Run):

```
1_transform_star_schema.sql        -- builds dim_team, dim_tournament, fact_matches, fact_goals, etc.
2_transform_2026_deepdive.sql      -- builds 2026-only satellite tables (xG, players, referees, venues)
3_transform_awards_bookings.sql    -- builds fact_awards and fact_bookings
```

All three scripts are **safe to re-run** — each drops and rebuilds its own tables at the start, without touching the `raw_*` tables underneath.

### Step 8 — Verify the load (optional sanity checks)
Run these directly in the Supabase SQL Editor:
```sql
SELECT source, COUNT(*) FROM fact_matches GROUP BY source;
SELECT source, COUNT(*) FROM fact_goals GROUP BY source;
SELECT source, COUNT(*) FROM fact_awards GROUP BY source;
SELECT source, card_type, COUNT(*) FROM fact_bookings GROUP BY source, card_type;
```

### Step 9 — Connect Power BI to Supabase
1. Open Power BI Desktop → **Get Data** → **PostgreSQL database**
2. Enter your Supabase host and database name
3. Authenticate with your Supabase username/password
4. Select all `dim_*` and `fact_*` tables (skip `raw_*` tables — they're only needed at the transform stage)
5. Load, then build/refresh your report

---

## 4. Data Model Summary

| Layer | Tables |
|---|---|
| **Dimensions** | `dim_team`, `dim_tournament`, `dim_venue`, `dim_stage`, `dim_player_2026`, `dim_referee_2026`, `dim_team_2026_attributes`, `dim_venue_2026_attributes` |
| **Facts** | `fact_matches`, `fact_goals`, `fact_bookings`, `fact_awards`, `fact_matches_2026_detail`, `fact_match_team_stats_2026`, `fact_match_events_2026` |

---

## 5. Dashboard Pages

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

## 6. Key DAX Measures

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

## 7. Tech Stack

- **Python** — `pandas`, `sqlalchemy`, `psycopg2`, `python-dotenv` for ELT ingestion
- **PostgreSQL (Supabase)** — cloud data warehouse and SQL transform layer
- **Power BI** — star-schema semantic model, DAX measures, and interactive reporting
- **Data sources** — two open-source GitHub datasets + one manually verified 2026 awards dataset
