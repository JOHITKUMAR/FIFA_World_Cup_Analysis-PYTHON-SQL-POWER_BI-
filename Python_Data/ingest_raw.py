"""
=============================================================================
 STUDENT GUIDE: ingest_raw.py
=============================================================================
WHAT THIS FILE DOES (in one sentence):
It downloads 32 spreadsheets (CSV files) from two GitHub sources about the
FIFA World Cup, and copies each one, completely untouched, into its own
table inside our cloud database (Supabase Postgres).

WHERE THIS FITS IN THE PROJECT:
    GitHub (raw data)  --->  THIS SCRIPT  --->  Postgres "raw_" tables
                                                        |
                                                        v
                                          (later) SQL scripts clean and
                                          reshape this data into the
                                          final model used in Power BI

WHY WE DON'T CLEAN THE DATA HERE:
This script deliberately does ZERO cleaning or fixing. It just "lands" the
data exactly as published. All cleaning/reshaping happens later, in SQL.
This is called an "ELT" pattern (Extract, Load, THEN Transform) and it's
how real data teams work — it means we always have an untouched original
copy to go back to if a cleaning step turns out to be wrong.

BEFORE YOU RUN THIS FILE — READ "0_setup_guide.md" FIRST:
This script assumes two things already exist. If they don't yet, stop
here and go do 0_setup_guide.md first — it walks through both:
    1. A Supabase account + project already created (this is our cloud
       database — this script has nothing to connect TO without it).
    2. A ".env" file, in this same folder, filled in with YOUR OWN 5
       credential values from that project (see .env.example for the
       format). NEVER share this file, commit it to GitHub, or paste
       its contents into a chat — it holds your database password.
Also install the required libraries once, before your first run:
       pip install pandas sqlalchemy psycopg2-binary python-dotenv

QUICK GLOSSARY — a few terms/syntax used below, if they're new to you:
    DataFrame     pandas' name for "a spreadsheet living in memory" —
                  rows and columns, like an Excel sheet, but inside Python.
    schema        think of it as a "folder" inside a database that groups
                  related tables together. Our tables all live in the
                  default one, called "public".
    dictionary    a Python data structure of {key: value} pairs — we use
                  one below (SOURCES) just to store our list of files in
                  an organized way, not as a database concept.
    f"...{x}..."  an "f-string" — lets us drop a variable's value directly
                  into a piece of text, e.g. f"hello {name}" becomes
                  "hello Rajdeep" if name = "Rajdeep".
    try / except  "attempt this code; if it errors out, don't crash —
                  run this other code instead." Used below so one bad
                  download can't stop all 32 files from loading.
=============================================================================
"""

# -----------------------------------------------------------------------
# IMPORTS — the tools this script borrows from Python's ecosystem
# -----------------------------------------------------------------------

import os
# "os" is a built-in Python library (comes with Python, no install needed).
# We use it here for exactly one job: os.environ lets us read values from
# our .env file (like the database password) as if they were regular
# Python variables, without ever typing the password directly into code.

from dotenv import load_dotenv
# "python-dotenv" is a small third-party library. Its only job is to open
# the .env file and load its contents so that os.environ can see them.
# Without this line, Python would have no idea the .env file exists.

from sqlalchemy import create_engine
from sqlalchemy.engine import URL
# "sqlalchemy" is the library Python uses to talk to databases in general
# (not just Postgres — it also works with MySQL, SQLite, etc).
#   - create_engine(...) builds a live "connection handle" to our database.
#   - URL.create(...) safely builds the connection address piece-by-piece
#     (host, port, username, password) instead of us having to glue a
#     single text string together ourselves, which is where mistakes like
#     forgetting to encode special characters in a password tend to happen.

import pandas as pd
# "pandas" is the most common Python library for working with tabular data
# (rows and columns, like a spreadsheet). We use exactly two of its
# abilities in this file:
#   1. pd.read_csv(url) — downloads a CSV file straight from the internet
#      and loads it into a "DataFrame" (pandas' in-memory spreadsheet).
#   2. DataFrame.to_sql(...) — takes that DataFrame and writes it into a
#      database table automatically, matching up column names and types
#      for us so we don't have to write CREATE TABLE statements by hand.


# -----------------------------------------------------------------------
# STEP 1 — Connect to the database
# -----------------------------------------------------------------------
# load_dotenv() reads the .env file sitting next to this script and makes
# its values available through os.environ. If this file is missing, the
# next block will fail with a clear "key not found" error — that's the
# script telling you to go create the .env file first.
load_dotenv()

# Here we build the actual connection address. Notice we never typed the
# real password anywhere in this file — it's pulled live from .env each
# time the script runs. This is a security best-practice: credentials
# and code stay separate, so this code is safe to share (e.g. with your
# classmates or on GitHub) without leaking your database password.
DB_URL = URL.create(
    drivername="postgresql+psycopg2",   # tells SQLAlchemy which "dialect" of SQL to speak
    username=os.environ["SUPABASE_USER"],
    password=os.environ["SUPABASE_PASSWORD"],
    host=os.environ["SUPABASE_HOST"],
    port=int(os.environ.get("SUPABASE_PORT", 5432)),
    database=os.environ.get("SUPABASE_DB", "postgres"),
)

# create_engine() doesn't connect immediately — think of it as "getting
# the phone ready to dial", not "making the call". The actual connection
# happens automatically, the first time we try to write data (in Step 3).
engine = create_engine(DB_URL)


# -----------------------------------------------------------------------
# STEP 2 — The "shopping list": where every file lives, and its name
# -----------------------------------------------------------------------
# This is just data, not logic — a dictionary describing our two GitHub
# sources. Each source has a base_url (the folder all its files live in)
# and a list of table names (the individual CSV files inside that folder,
# without the ".csv" ending — we add that back in Step 3).
#
# Why store it this way instead of writing out 32 full web addresses by
# hand? Because it's much easier to add a new table later — you just add
# one word to the list below, instead of typing a whole new long URL.
SOURCES = {
    "jfjelstul": {
        # Covers every MEN'S and WOMEN'S World Cup from 1930-2022.
        "base_url": "https://raw.githubusercontent.com/jfjelstul/worldcup/master/data-csv/",
        "tables": [
            "tournaments", "confederations", "host_countries", "teams",
            "matches", "goals", "bookings", "substitutions", "penalty_kicks",
            "players", "squads", "player_appearances", "team_appearances",
            "groups", "group_standings", "awards", "award_winners",
            "managers", "manager_appointments", "manager_appearances",
            "referees", "referee_appointments", "qualified_teams",
        ],
    },
    "mominullptr_2026": {
        # Covers ONLY the 2026 World Cup, but in much richer detail
        # (things like expected goals, player market value, ELO ratings).
        "base_url": "https://raw.githubusercontent.com/mominullptr/FIFA-World-Cup-2026-Dataset/main/",
        "tables": [
            "teams", "venues", "tournament_stages", "referees", "matches",
            "match_events", "match_team_stats", "match_prediction_features",
            "squads_and_players", "match_lineups",
        ],
    },
}


# -----------------------------------------------------------------------
# STEP 3 — The actual work: download each file, then upload it as a table
# -----------------------------------------------------------------------
def ingest_all():
    """
    Loops over every (source, table) pair defined above and, for each one:
      1. Builds the full download link.
      2. Downloads the CSV straight into a pandas DataFrame (in memory —
         it never gets saved as a file on your computer).
      3. Writes that DataFrame into Postgres as a brand-new table named
         raw_<source>_<table>, e.g. raw_jfjelstul_matches.
      4. Prints one line confirming what happened, so you can watch its
         progress as it runs.

    Running this function twice is completely safe: if_exists="replace"
    means each run wipes and rebuilds these raw_ tables fresh, so you can
    always re-run this file with no risk of duplicating data.
    """
    for source_name, config in SOURCES.items():
        for table in config["tables"]:
            url = f"{config['base_url']}{table}.csv"

            try:
                df = pd.read_csv(url)  # download + parse the CSV in one step
            except Exception as e:
                # If a download fails (e.g. no internet, or the file moved),
                # we don't want the whole script to crash and lose all the
                # progress on the other 31 files — we skip this one, print
                # why, and keep going.
                print(f"  SKIPPED {source_name}.{table}: could not download ({e})")
                continue

            target_table = f"raw_{source_name}_{table}"

            df.to_sql(
                target_table,
                engine,
                schema="public",       # the default "folder" tables live in, inside Postgres
                if_exists="replace",   # overwrite this table if it already exists (safe re-run)
                index=False,           # don't add pandas' own row-number column to the table
            )

            print(f"  loaded {target_table:45s} rows={len(df):>6}  cols={len(df.columns)}")

    print("\nDone. Raw tables are now in your Supabase 'public' schema, prefixed 'raw_'.")


# -----------------------------------------------------------------------
# STEP 4 — The "on switch"
# -----------------------------------------------------------------------
# This is a standard Python pattern. In plain English it means:
# "If someone runs this file directly (python ingest_raw.py), then go
# ahead and call ingest_all(). But if someone instead imports this file
# from another script, don't automatically run anything."
# It's a safety habit that keeps this script well-behaved if it's ever
# reused as a building block inside a bigger project.
if __name__ == "__main__":
    ingest_all()
