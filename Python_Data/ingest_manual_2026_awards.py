"""
Manually inject the 2026 World Cup award winners.

This data isn't in either GitHub source — it's hand-verified from news
coverage after the tournament, cross-checked across multiple outlets.
Lands as its own raw table, same landing-zone pattern as everything else,
so the SQL transform step can pick it up identically to the other sources.

Requires the same .env file as ingest_raw.py (same folder).
"""

import os
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import URL
import pandas as pd

load_dotenv()

DB_URL = URL.create(
    drivername="postgresql+psycopg2",
    username=os.environ["SUPABASE_USER"],
    password=os.environ["SUPABASE_PASSWORD"],
    host=os.environ["SUPABASE_HOST"],
    port=int(os.environ.get("SUPABASE_PORT", 5432)),
    database=os.environ.get("SUPABASE_DB", "postgres"),
)
engine = create_engine(DB_URL)

# Verified against multiple independent sources (Britannica, NBC Sports,
# Bleacher Report, Olympics.com) as of the days following the 2026 final.
awards_2026 = pd.DataFrame([
    {"award_name": "Golden Ball",       "player_name": "Rodri",           "team_name": "Spain"},
    {"award_name": "Golden Boot",       "player_name": "Kylian Mbappe",   "team_name": "France"},
    {"award_name": "Silver Boot",       "player_name": "Lionel Messi",    "team_name": "Argentina"},
    {"award_name": "Bronze Boot",       "player_name": "Jude Bellingham", "team_name": "England"},
    {"award_name": "Golden Glove",      "player_name": "Unai Simon",      "team_name": "Spain"},
    {"award_name": "Best Young Player", "player_name": "Pau Cubarsi",     "team_name": "Spain"},
])
awards_2026["tournament_id"] = "WC-2026"

awards_2026.to_sql(
    "raw_manual_2026_awards",
    engine,
    schema="public",
    if_exists="replace",
    index=False,
)

print(f"Loaded raw_manual_2026_awards: {len(awards_2026)} rows")
