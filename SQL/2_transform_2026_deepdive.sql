-- =====================================================================
-- PHASE 2c: 2026 deep-dive layer
-- Adds the rich, 2026-only metrics that don't exist for historical
-- tournaments. Shares dim_team and dim_venue with the main model so
-- both report pages stay cross-filterable.
-- Run in Supabase SQL Editor, after transform_star_schema.sql.
-- Safe to re-run.
--
-- PROBLEMS THIS SCRIPT SOLVES:
--   #1 2026's richest metrics (xG, ELO, market value, possession,
--      referee stats) have no historical equivalent — can't be added
--      to the core dim/fact tables without forcing NULLs pre-2026
--      and inviting unfair cross-era comparisons
--   #2 The team-name mapping problem recurs across 5 different raw
--      tables (teams, players, stats, events, matches)
--   #3 Referee and "player of the match" are bare IDs with no
--      dimension table to look them up against
--   #4 Team stats have a different grain (2 rows/match) than
--      fact_matches (1 row/match) — can't bolt on directly
--   #5 This layer needs to KEEP every event type (goals, cards,
--      assists, VAR) — unlike fact_goals, which filters down to
--      goals only so it can span both eras
--   #6 The "90+3" stoppage-time text problem reappears here too
-- =====================================================================

DROP TABLE IF EXISTS fact_match_events_2026 CASCADE;
DROP TABLE IF EXISTS fact_match_team_stats_2026 CASCADE;
DROP TABLE IF EXISTS fact_matches_2026_detail CASCADE;
DROP TABLE IF EXISTS dim_player_2026 CASCADE;
DROP TABLE IF EXISTS dim_referee_2026 CASCADE;
DROP TABLE IF EXISTS dim_team_2026_attributes CASCADE;
DROP TABLE IF EXISTS dim_venue_2026_attributes CASCADE;

-- ---------------------------------------------------------------------
-- helper view: resolves a raw 2026 team_id straight to the shared
-- dim_team key in one place.
-- Fixes PROBLEM #2: instead of repeating the same override-join logic
-- in 5 separate places below, every table just joins to this view once.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_2026_team_lookup AS
SELECT
    t.team_id AS raw_team_id_2026,
    dt.team_key
FROM raw_mominullptr_2026_teams t
LEFT JOIN team_name_overrides o ON o.source_name = t.team_name
JOIN dim_team dt ON dt.team_name = COALESCE(o.canonical_name, t.team_name);

-- ---------------------------------------------------------------------
-- 1. dim_team_2026_attributes
--    Fixes PROBLEM #1: rather than widen dim_team itself with columns
--    that would be NULL for every 1930-2022 team, these 2026-only
--    attributes live in their own satellite table, linked 1-to-1
--    back to dim_team by team_key.
-- ---------------------------------------------------------------------
CREATE TABLE dim_team_2026_attributes (
    team_key                    int PRIMARY KEY REFERENCES dim_team(team_key),
    fifa_code                   text,
    group_letter                text,
    fifa_ranking_pre_tournament int,
    elo_rating                  int,
    manager_name                text
);

INSERT INTO dim_team_2026_attributes (team_key, fifa_code, group_letter, fifa_ranking_pre_tournament, elo_rating, manager_name)
SELECT lk.team_key, t.fifa_code, t.group_letter, t.fifa_ranking_pre_tournament, t.elo_rating, t.manager_name
FROM raw_mominullptr_2026_teams t
JOIN v_2026_team_lookup lk ON lk.raw_team_id_2026 = t.team_id;

-- ---------------------------------------------------------------------
-- 2. dim_venue_2026_attributes
--    Also fixes PROBLEM #1: capacity/coordinates/elevation only exist
--    for 2026 venues, so they satellite off dim_venue the same way.
-- ---------------------------------------------------------------------
CREATE TABLE dim_venue_2026_attributes (
    venue_key        int PRIMARY KEY REFERENCES dim_venue(venue_key),
    capacity          int,
    latitude          numeric,
    longitude         numeric,
    elevation_meters  int
);

INSERT INTO dim_venue_2026_attributes (venue_key, capacity, latitude, longitude, elevation_meters)
SELECT v.venue_key, rv.capacity, rv.latitude, rv.longitude, rv.elevation_meters
FROM raw_mominullptr_2026_venues rv
JOIN dim_venue v ON v.stadium_name = rv.stadium_name AND v.city = rv.city;

-- ---------------------------------------------------------------------
-- 3. dim_referee_2026
--    Fixes PROBLEM #3: turns a bare referee_id sitting inside the raw
--    matches table into an actual, nameable dimension.
-- ---------------------------------------------------------------------
CREATE TABLE dim_referee_2026 (
    referee_key         SERIAL PRIMARY KEY,
    raw_referee_id       int UNIQUE,
    referee_name          text,
    country               text,
    avg_cards_per_game    numeric
);

INSERT INTO dim_referee_2026 (raw_referee_id, referee_name, country, avg_cards_per_game)
SELECT referee_id, name, country, avg_cards_per_game
FROM raw_mominullptr_2026_referees;

-- ---------------------------------------------------------------------
-- 4. dim_player_2026
--    Also fixes PROBLEM #3: "player of the match" needs a real player
--    dimension to point at, not just a bare integer ID. Built here
--    since it's also needed by fact_match_events_2026 below (problem #5).
-- ---------------------------------------------------------------------
CREATE TABLE dim_player_2026 (
    player_key       SERIAL PRIMARY KEY,
    raw_player_id     int UNIQUE,
    team_key          int REFERENCES dim_team(team_key),
    player_name       text,
    position          text,
    club_team         text,
    market_value_eur  bigint,
    caps              int,
    date_of_birth     date,
    height_cm         int,
    career_goals      int
);

INSERT INTO dim_player_2026 (raw_player_id, team_key, player_name, position, club_team, market_value_eur, caps, date_of_birth, height_cm, career_goals)
SELECT
    sp.player_id,
    lk.team_key,
    sp.player_name,
    sp.position,
    sp.club_team,
    sp.market_value_eur,
    sp.caps,
    sp.date_of_birth::date,
    sp.height_cm,
    sp.goals
FROM raw_mominullptr_2026_squads_and_players sp
JOIN v_2026_team_lookup lk ON lk.raw_team_id_2026 = sp.team_id;

-- ---------------------------------------------------------------------
-- 5. fact_matches_2026_detail — one row per 2026 match
--    Fixes the rest of PROBLEM #1 and #3: extends fact_matches (via a
--    1-to-1 join on match_key) with xG, penalties, referee and POTM,
--    now that dim_referee_2026 / dim_player_2026 exist to reference.
-- ---------------------------------------------------------------------
CREATE TABLE fact_matches_2026_detail (
    match_key             int PRIMARY KEY REFERENCES fact_matches(match_key),
    home_xg                numeric,
    away_xg                numeric,
    home_penalty_score     int,
    away_penalty_score     int,
    status                 text,
    result_type            text,
    referee_key            int REFERENCES dim_referee_2026(referee_key),
    player_of_the_match_key int REFERENCES dim_player_2026(player_key)
);

INSERT INTO fact_matches_2026_detail (match_key, home_xg, away_xg, home_penalty_score, away_penalty_score, status, result_type, referee_key, player_of_the_match_key)
SELECT
    fm.match_key,
    m.home_xg,
    m.away_xg,
    m.home_penalty_score,
    m.away_penalty_score,
    m.status,
    m.result_type,
    ref.referee_key,
    potm.player_key
FROM raw_mominullptr_2026_matches m
JOIN fact_matches fm ON fm.source = 'mominullptr_2026' AND fm.source_match_id = m.match_id::text
LEFT JOIN dim_referee_2026 ref ON ref.raw_referee_id = m.referee_id
LEFT JOIN dim_player_2026 potm ON potm.raw_player_id = m.player_of_the_match_id;

-- ---------------------------------------------------------------------
-- 6. fact_match_team_stats_2026
--    Fixes PROBLEM #4: possession/shots/corners are one row per team
--    per match (208 rows = 104 matches x 2 teams), a different grain
--    than fact_matches, so they get their own fact table rather than
--    being squeezed onto fact_matches as extra columns.
-- ---------------------------------------------------------------------
CREATE TABLE fact_match_team_stats_2026 (
    stat_key           SERIAL PRIMARY KEY,
    match_key           int REFERENCES fact_matches(match_key),
    team_key            int REFERENCES dim_team(team_key),
    possession_pct       numeric,
    total_shots           int,
    shots_on_target       int,
    corners                int,
    fouls                  int,
    offsides                int,
    saves                    int,
    was_player_of_the_match boolean,
    data_source              text
);

INSERT INTO fact_match_team_stats_2026 (match_key, team_key, possession_pct, total_shots, shots_on_target, corners, fouls, offsides, saves, was_player_of_the_match, data_source)
SELECT
    fm.match_key,
    lk.team_key,
    s.possession_pct,
    s.total_shots,
    s.shots_on_target,
    s.corners,
    s.fouls,
    s.offsides,
    s.saves,
    (s.player_of_the_match IS NOT NULL AND s.player_of_the_match != ''),
    s.data_source
FROM raw_mominullptr_2026_match_team_stats s
JOIN fact_matches fm ON fm.source = 'mominullptr_2026' AND fm.source_match_id = s.match_id::text
JOIN v_2026_team_lookup lk ON lk.raw_team_id_2026 = s.team_id;

-- ---------------------------------------------------------------------
-- 7. fact_match_events_2026 — grain: one row per event, ALL types
--    Fixes PROBLEM #5: unlike fact_goals (which filters down to goals
--    only, in the core script), this table deliberately keeps every
--    event type — goals, cards, assists, VAR reviews — since richness
--    is the entire point of this 2026-only layer.
--    Fixes PROBLEM #6: same "90+3" stoppage-time split-and-sum fix
--    used earlier, needed again here for the same reason.
-- ---------------------------------------------------------------------
CREATE TABLE fact_match_events_2026 (
    event_key   SERIAL PRIMARY KEY,
    match_key    int REFERENCES fact_matches(match_key),
    team_key     int REFERENCES dim_team(team_key),
    player_key   int REFERENCES dim_player_2026(player_key),
    minute        int,
    event_type    text
);

INSERT INTO fact_match_events_2026 (match_key, team_key, player_key, minute, event_type)
SELECT
    fm.match_key,
    lk.team_key,
    dp.player_key,
    -- problem #6 fix, same pattern as the core script:
    -- "90+3" -> split into "90" and "3" -> 90 + 3 = 93
    (split_part(e.minute, '+', 1)::int + COALESCE(NULLIF(split_part(e.minute, '+', 2), '')::int, 0)),
    e.event_type
    -- note: NO WHERE clause filtering event_type here (unlike fact_goals)
    -- this is intentional — problem #5, keep every event type
FROM raw_mominullptr_2026_match_events e
JOIN fact_matches fm ON fm.source = 'mominullptr_2026' AND fm.source_match_id = e.match_id::text
JOIN v_2026_team_lookup lk ON lk.raw_team_id_2026 = e.team_id
LEFT JOIN dim_player_2026 dp ON dp.raw_player_id = e.player_id;

-- =====================================================================
-- Sanity checks — run after the script:
--
-- SELECT COUNT(*) FROM dim_team_2026_attributes;       -- expect 48
-- SELECT COUNT(*) FROM dim_venue_2026_attributes;       -- expect 16
-- SELECT COUNT(*) FROM dim_player_2026;                 -- expect 1248
-- SELECT COUNT(*) FROM fact_matches_2026_detail;        -- expect 104
-- SELECT COUNT(*) FROM fact_match_team_stats_2026;      -- expect 208 (2 rows/match)
-- SELECT event_type, COUNT(*) FROM fact_match_events_2026 GROUP BY event_type;
-- =====================================================================
