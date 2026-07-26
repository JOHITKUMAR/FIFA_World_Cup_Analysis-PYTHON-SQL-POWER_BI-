-- =====================================================================
-- PHASE 2b: Transform raw_* tables into a conformed star schema
-- Run this entire script in Supabase's SQL Editor (paste all, click Run)
-- Safe to re-run: drops and rebuilds the modeled tables each time,
-- your raw_* tables are never touched.
--
-- PROBLEMS THIS SCRIPT SOLVES (see chat/PDF for full detail):
--   #1 No relationships between any raw tables (flat, unlinked)
--   #2 Two incompatible team ID systems (text codes vs plain integers)
--   #3 Team names don't match between sources (Türkiye vs Turkey, etc.)
--   #4 Men's and women's tournaments are mixed together in one table
--   #5 2026 doesn't exist in the historical tournament list at all
--   #6 2026 stoppage-time minutes stored as unparseable text ("90+3")
--   #7 2026 goals aren't isolated — mixed with cards/assists/VAR events
--   #8 Venues and stage names are structured differently per source
-- =====================================================================

DROP TABLE IF EXISTS fact_goals CASCADE;
DROP TABLE IF EXISTS fact_matches CASCADE;
DROP TABLE IF EXISTS dim_team CASCADE;
DROP TABLE IF EXISTS dim_venue CASCADE;
DROP TABLE IF EXISTS dim_stage CASCADE;
DROP TABLE IF EXISTS dim_tournament CASCADE;
DROP TABLE IF EXISTS dim_confederation CASCADE;
DROP TABLE IF EXISTS team_name_overrides CASCADE;

-- ---------------------------------------------------------------------
-- 1. dim_confederation
--    Fixes part of PROBLEM #1: gives confederations their own real
--    table with a primary key, instead of being a plain text column
--    repeated on every team row.
-- ---------------------------------------------------------------------
CREATE TABLE dim_confederation AS
SELECT DISTINCT confederation_id, confederation_name, confederation_code
FROM raw_jfjelstul_confederations;

ALTER TABLE dim_confederation ADD PRIMARY KEY (confederation_id);

-- ---------------------------------------------------------------------
-- 2. dim_tournament
--    Fixes PROBLEM #4: keeps only men's tournaments (WHERE clause below).
--    Fixes PROBLEM #5: the historical file stops at 2022, so we INSERT
--    one hand-written row for 2026 immediately after.
-- ---------------------------------------------------------------------
CREATE TABLE dim_tournament AS
SELECT
    tournament_id,
    tournament_name,
    year,
    start_date::date AS start_date,
    end_date::date   AS end_date,
    host_country,
    winner,
    count_teams,
    'Men''s' AS competition_type
FROM raw_jfjelstul_tournaments
WHERE tournament_name ILIKE '%Men%' AND tournament_name NOT ILIKE '%Women%';

-- 2026 doesn't exist in the source data yet (problem #5) — add it by hand
INSERT INTO dim_tournament
    (tournament_id, tournament_name, year, start_date, end_date, host_country, winner, count_teams, competition_type)
VALUES
    ('WC-2026', '2026 FIFA World Cup', 2026, '2026-06-11', '2026-07-19',
     'United States / Canada / Mexico', 'Spain', 48, 'Men''s');

ALTER TABLE dim_tournament ADD PRIMARY KEY (tournament_id);

-- ---------------------------------------------------------------------
-- 3. team_name_overrides
--    Fixes PROBLEM #3: a small lookup table mapping every verified
--    2026 spelling difference to the historical dataset's spelling.
--    Only the 5 genuine renames go here; the 5 real debutants
--    (Cabo Verde, Congo DR, Curaçao, Jordan, Uzbekistan) are NOT listed
--    here on purpose — they are new teams, not renamed ones.
-- ---------------------------------------------------------------------
CREATE TABLE team_name_overrides (
    source_name    text PRIMARY KEY,
    canonical_name text NOT NULL
);

INSERT INTO team_name_overrides (source_name, canonical_name) VALUES
    ('IR Iran',          'Iran'),
    ('Türkiye',          'Turkey'),
    ('Côte d''Ivoire',   'Ivory Coast'),
    ('Czechia',          'Czech Republic'),
    ('USA',              'United States'),
    ('West Germany',     'Germany'),
    ('East Germany',     'Germany'),
    ('Zaire',            'Congo DR');
-- Note: West/East Germany are merged deliberately (project decision:
-- "Germany, East or West, counts as one" — a stricter merge than FIFA's
-- own convention, which excludes East Germany; kept as-is on purpose).
-- Zaire -> Congo DR is a straight rename, same country, per FIFA's own
-- record ("DR Congo competed as Zaire in 1974").
-- Czechoslovakia, Soviet Union, and Yugoslavia (and its own successors:
-- FR Yugoslavia, Serbia and Montenegro, Serbia) are intentionally NOT
-- listed here — each dissolved into multiple present-day countries, so
-- every one of them stays its own separate, independent team, and every
-- successor state starts fresh with zero inherited record.

-- dim_tournament.winner was copied as plain text from the raw source
-- BEFORE this overrides table existed, so it still says "West Germany"
-- for 1954/1974/1990 instead of "Germany". Fix it now that overrides exist.
UPDATE dim_tournament dt
SET winner = o.canonical_name
FROM team_name_overrides o
WHERE o.source_name = dt.winner;

-- ---------------------------------------------------------------------
-- 4. dim_team
--    Fixes PROBLEM #1 and #2: gives every team one single surrogate
--    key (team_key), replacing both sources' incompatible native IDs.
--    Uses team_name_overrides (problem #3's fix) so a 2026 team never
--    gets inserted twice under two different spellings.
-- ---------------------------------------------------------------------
CREATE TABLE dim_team (
    team_key           SERIAL PRIMARY KEY,
    team_name          text UNIQUE NOT NULL,
    confederation_name text
);

-- historical men's teams first (problem #4: mens_team = '1' filters out
-- women's-only national teams, same principle as the tournament filter)
INSERT INTO dim_team (team_name, confederation_name)
SELECT DISTINCT team_name, confederation_name
FROM raw_jfjelstul_teams
WHERE mens_team = '1';

-- then only the 2026 teams that are genuinely new, after applying overrides
INSERT INTO dim_team (team_name, confederation_name)
SELECT DISTINCT
    COALESCE(o.canonical_name, t.team_name) AS team_name,
    t.confederation
FROM raw_mominullptr_2026_teams t
LEFT JOIN team_name_overrides o ON o.source_name = t.team_name
WHERE COALESCE(o.canonical_name, t.team_name) NOT IN (SELECT team_name FROM dim_team);

-- ---------------------------------------------------------------------
-- 5. dim_venue
--    Fixes PROBLEM #8: historical stadium data is embedded loose inside
--    the matches table; 2026 has its own separate venues table with
--    different column names. Both get normalized into one shared shape.
-- ---------------------------------------------------------------------
CREATE TABLE dim_venue (
    venue_key    SERIAL PRIMARY KEY,
    stadium_name text,
    city         text,
    country      text,
    UNIQUE (stadium_name, city)
);

INSERT INTO dim_venue (stadium_name, city, country)
SELECT DISTINCT stadium_name, city_name, country_name
FROM raw_jfjelstul_matches
WHERE stadium_name IS NOT NULL
ON CONFLICT (stadium_name, city) DO NOTHING;

INSERT INTO dim_venue (stadium_name, city, country)
SELECT DISTINCT stadium_name, city, country
FROM raw_mominullptr_2026_venues
ON CONFLICT (stadium_name, city) DO NOTHING;

-- ---------------------------------------------------------------------
-- 6. dim_stage
--    Also fixes PROBLEM #8: unifies free-text stage naming (e.g.
--    "group stage", "Round of 16") so both sources point at the same
--    stage rows instead of near-duplicate text values.
-- ---------------------------------------------------------------------
CREATE TABLE dim_stage (
    stage_key   SERIAL PRIMARY KEY,
    stage_name  text UNIQUE,
    is_knockout boolean
);

INSERT INTO dim_stage (stage_name, is_knockout)
SELECT DISTINCT stage_name, (knockout_stage = '1')
FROM raw_jfjelstul_matches
ON CONFLICT (stage_name) DO NOTHING;

INSERT INTO dim_stage (stage_name, is_knockout)
SELECT DISTINCT stage_name, is_knockout
FROM raw_mominullptr_2026_tournament_stages
ON CONFLICT (stage_name) DO NOTHING;

-- ---------------------------------------------------------------------
-- 7. fact_matches — grain: one row per match, both eras unified
--    This is where PROBLEMS #1 and #2 get fully resolved: every match
--    now references dim_team/dim_tournament/dim_venue/dim_stage through
--    proper foreign keys, regardless of which source it came from.
--    Also enforces PROBLEM #4's fix again at the match level (not just
--    the team level), via the WHERE clause in 7a.
-- ---------------------------------------------------------------------
CREATE TABLE fact_matches (
    match_key        SERIAL PRIMARY KEY,
    source            text NOT NULL,      -- 'jfjelstul' or 'mominullptr_2026'
    source_match_id   text NOT NULL,
    tournament_id     text REFERENCES dim_tournament(tournament_id),
    match_date        date,
    stage_key         int REFERENCES dim_stage(stage_key),
    venue_key         int REFERENCES dim_venue(venue_key),
    home_team_key     int REFERENCES dim_team(team_key),
    away_team_key     int REFERENCES dim_team(team_key),
    home_score        int,
    away_score        int,
    extra_time        boolean,
    penalty_shootout  boolean
);

-- 7a. historical matches (1930-2022 men's / 1991-2019 women's in source,
--     but WHERE clause below keeps only men's — problem #4)
INSERT INTO fact_matches
    (source, source_match_id, tournament_id, match_date, stage_key, venue_key,
     home_team_key, away_team_key, home_score, away_score, extra_time, penalty_shootout)
SELECT
    'jfjelstul',
    m.match_id,
    m.tournament_id,
    m.match_date::date,
    s.stage_key,
    v.venue_key,
    ht.team_key,
    at.team_key,
    m.home_team_score::int,
    m.away_team_score::int,
    (m.extra_time = '1'),
    (m.penalty_shootout = '1')
FROM raw_jfjelstul_matches m
LEFT JOIN dim_stage s ON s.stage_name = m.stage_name
LEFT JOIN dim_venue v ON v.stadium_name = m.stadium_name AND v.city = m.city_name
LEFT JOIN dim_team  ht ON ht.team_name = m.home_team_name
LEFT JOIN dim_team  at ON at.team_name = m.away_team_name
WHERE m.tournament_name ILIKE '%Men%' AND m.tournament_name NOT ILIKE '%Women%';

-- 7b. 2026 matches — team names resolved through team_name_overrides
--     (problem #3), since raw team IDs from the two sources are
--     incompatible formats (problem #2) and can't be joined directly.
INSERT INTO fact_matches
    (source, source_match_id, tournament_id, match_date, stage_key, venue_key,
     home_team_key, away_team_key, home_score, away_score, extra_time, penalty_shootout)
SELECT
    'mominullptr_2026',
    m.match_id::text,
    'WC-2026',
    m.date::date,
    s.stage_key,
    v.venue_key,
    ht.team_key,
    at.team_key,
    m.home_score,
    m.away_score,
    NULL,  -- this source doesn't separately flag extra time
    (m.home_penalty_score IS NOT NULL)
FROM raw_mominullptr_2026_matches m
LEFT JOIN raw_mominullptr_2026_tournament_stages ts ON ts.stage_id = m.stage_id
LEFT JOIN dim_stage s ON s.stage_name = ts.stage_name
LEFT JOIN raw_mominullptr_2026_venues rv ON rv.venue_id = m.venue_id
LEFT JOIN dim_venue v ON v.stadium_name = rv.stadium_name AND v.city = rv.city
LEFT JOIN raw_mominullptr_2026_teams ht_raw ON ht_raw.team_id = m.home_team_id
LEFT JOIN team_name_overrides ho ON ho.source_name = ht_raw.team_name
LEFT JOIN dim_team ht ON ht.team_name = COALESCE(ho.canonical_name, ht_raw.team_name)
LEFT JOIN raw_mominullptr_2026_teams at_raw ON at_raw.team_id = m.away_team_id
LEFT JOIN team_name_overrides ao ON ao.source_name = at_raw.team_name
LEFT JOIN dim_team at ON at.team_name = COALESCE(ao.canonical_name, at_raw.team_name);

-- ---------------------------------------------------------------------
-- 8. fact_goals — grain: one row per goal, both eras unified
-- ---------------------------------------------------------------------
CREATE TABLE fact_goals (
    goal_key    SERIAL PRIMARY KEY,
    source      text NOT NULL,
    match_key   int REFERENCES fact_matches(match_key),
    team_key    int REFERENCES dim_team(team_key),
    player_name text,
    minute      int,
    own_goal    boolean,
    penalty     boolean
);

-- 8a. historical goals — straightforward, this source has a dedicated
--     goals table already (no equivalent of problem #7 here)
INSERT INTO fact_goals (source, match_key, team_key, player_name, minute, own_goal, penalty)
SELECT
    'jfjelstul',
    fm.match_key,
    dt.team_key,
    g.given_name || ' ' || g.family_name,
    g.minute_regulation::int,
    (g.own_goal = '1'),
    (g.penalty = '1')
FROM raw_jfjelstul_goals g
JOIN fact_matches fm ON fm.source = 'jfjelstul' AND fm.source_match_id = g.match_id
JOIN dim_team dt ON dt.team_name = g.team_name;

-- 8b. 2026 goals
--     Fixes PROBLEM #7: raw_mominullptr_2026_match_events mixes goals
--     with cards/assists/VAR — the WHERE clause at the bottom isolates
--     just the goal-scoring rows.
--     Fixes PROBLEM #6: raw minute values like "90+3" would crash a
--     direct ::int cast, so the stoppage-time part is split on '+' and
--     added to the base minute instead.
INSERT INTO fact_goals (source, match_key, team_key, player_name, minute, own_goal, penalty)
SELECT
    'mominullptr_2026',
    fm.match_key,
    dt.team_key,
    sp.player_name,
    -- problem #6 fix: "90+3" -> split_part gives "90" and "3" -> 90 + 3 = 93
    (split_part(e.minute, '+', 1)::int + COALESCE(NULLIF(split_part(e.minute, '+', 2), '')::int, 0)),
    FALSE,  -- own goals aren't separately flagged in this source's event_type
    (e.event_type = 'Penalty Shootout Goal')
FROM raw_mominullptr_2026_match_events e
JOIN fact_matches fm ON fm.source = 'mominullptr_2026' AND fm.source_match_id = e.match_id::text
JOIN raw_mominullptr_2026_teams traw ON traw.team_id = e.team_id
LEFT JOIN team_name_overrides o ON o.source_name = traw.team_name
JOIN dim_team dt ON dt.team_name = COALESCE(o.canonical_name, traw.team_name)
LEFT JOIN raw_mominullptr_2026_squads_and_players sp ON sp.player_id = e.player_id
-- problem #7 fix: isolate goal-type events only, out of a table that
-- also contains Yellow Card / Red Card / Assist / VAR Review rows
WHERE e.event_type IN ('Goal', 'Penalty Shootout Goal');

-- =====================================================================
-- Done. Run these separately afterward to sanity-check the results:
--
-- SELECT source, COUNT(*) FROM fact_matches GROUP BY source;
-- SELECT source, COUNT(*) FROM fact_goals GROUP BY source;
-- SELECT team_name FROM dim_team WHERE team_name IN
--   ('Iran','Turkey','Ivory Coast','Czech Republic','United States',
--    'Cabo Verde','Congo DR','Curaçao','Jordan','Uzbekistan');
-- SELECT COUNT(*) FROM fact_matches WHERE home_team_key IS NULL OR away_team_key IS NULL;
-- =====================================================================
