-- =====================================================================
-- PHASE 2d: fact_awards + fact_bookings
-- Run after transform_star_schema.sql and after ingest_manual_2026_awards.py
-- Safe to re-run.
--
-- PROBLEMS THIS SCRIPT SOLVES:
--   #1 No 2026 award data exists in either GitHub source at all
--   #2 Award types were introduced at different points in history
--      (Golden Ball 1978, Best Young Player 1958, Golden Glove 1994) —
--      not a data gap, just fewer award rows for earlier tournaments
--   #3 Cards live in two structurally different places per source —
--      a dedicated table historically, buried inside a general events
--      table for 2026 — so they need different extraction logic each
--   #4 Fouls only exist for 2026 — deliberately excluded rather than
--      half-populated
-- =====================================================================

DROP TABLE IF EXISTS fact_bookings CASCADE;
DROP TABLE IF EXISTS fact_awards CASCADE;

-- ---------------------------------------------------------------------
-- 1. fact_awards — historical award_winners + verified 2026 rows.
--    Fixes PROBLEM #1: the 6 rows from raw_manual_2026_awards (loaded
--    by ingest_manual_2026_awards.py) fill the gap no GitHub source covers.
--    Fixes PROBLEM #2 implicitly: joining to dim_tournament naturally
--    excludes women's-only awards, same trick used in the core script,
--    and simply returns whatever awards existed for that tournament year
--    — no attempt is made to force every award type onto every edition.
-- ---------------------------------------------------------------------
CREATE TABLE fact_awards (
    award_key      SERIAL PRIMARY KEY,
    source          text NOT NULL,
    tournament_id   text REFERENCES dim_tournament(tournament_id),
    award_name      text,
    player_name     text,
    team_key        int REFERENCES dim_team(team_key)
);

-- 1a. historical awards (however many award types existed at the time —
--     problem #2, this is expected to vary by year, not a bug).
--     Joins through team_name_overrides too — same gap as the core
--     script had for matches/goals: West Germany, East Germany, and
--     Zaire only ever appear under their old names in this raw table.
INSERT INTO fact_awards (source, tournament_id, award_name, player_name, team_key)
SELECT
    'jfjelstul',
    aw.tournament_id,
    aw.award_name,
    aw.given_name || ' ' || aw.family_name,
    dt.team_key
FROM raw_jfjelstul_award_winners aw
JOIN dim_tournament dtn ON dtn.tournament_id = aw.tournament_id
LEFT JOIN team_name_overrides o ON o.source_name = aw.team_name
JOIN dim_team dt ON dt.team_name = COALESCE(o.canonical_name, aw.team_name);

-- 1b. 2026 awards — fixes problem #1 directly: this is the hand-verified
--     data with no GitHub source, loaded via its own small Python script
INSERT INTO fact_awards (source, tournament_id, award_name, player_name, team_key)
SELECT
    'manual_2026',
    m.tournament_id,
    m.award_name,
    m.player_name,
    dt.team_key
FROM raw_manual_2026_awards m
JOIN dim_team dt ON dt.team_name = m.team_name;

-- ---------------------------------------------------------------------
-- 2. fact_bookings — yellow/red cards, unified across both eras.
--    Fixes PROBLEM #3: historical and 2026 cards come from two
--    differently-shaped sources, so each gets its own INSERT below
--    with its own extraction logic, converging on the same output shape.
--    Fixes PROBLEM #4: fouls are deliberately NOT a column here at all
--    — only cards, since fouls have no historical equivalent.
-- ---------------------------------------------------------------------
CREATE TABLE fact_bookings (
    booking_key   SERIAL PRIMARY KEY,
    source         text NOT NULL,
    match_key      int REFERENCES fact_matches(match_key),
    team_key       int REFERENCES dim_team(team_key),
    player_name    text,
    minute         int,
    card_type      text   -- 'Yellow', 'Second Yellow', or 'Red'
);

-- 2a. historical bookings — problem #3's historical side: this source
--     has explicit yellow_card/red_card/second_yellow_card/sending_off
--     flag columns, collapsed here into one card_type value.
--     (Joining to fact_matches also auto-excludes women's matches,
--     same filter reused from the core script.)
-- 2a. historical bookings (joining to fact_matches auto-excludes women's matches).
--     Joins through team_name_overrides too, same gap as 1a above.
INSERT INTO fact_bookings (source, match_key, team_key, player_name, minute, card_type)
SELECT
    'jfjelstul',
    fm.match_key,
    dt.team_key,
    b.given_name || ' ' || b.family_name,
    b.minute_regulation::int,
    CASE
        WHEN b.sending_off = '1' OR b.red_card = '1' THEN 'Red'
        WHEN b.second_yellow_card = '1' THEN 'Second Yellow'
        WHEN b.yellow_card = '1' THEN 'Yellow'
    END
FROM raw_jfjelstul_bookings b
JOIN fact_matches fm ON fm.source = 'jfjelstul' AND fm.source_match_id = b.match_id
LEFT JOIN team_name_overrides o ON o.source_name = b.team_name
JOIN dim_team dt ON dt.team_name = COALESCE(o.canonical_name, b.team_name);

-- 2b. 2026 bookings — problem #3's 2026 side: cards aren't in their own
--     table here, so they're pulled out of fact_match_events_2026
--     (already built in the deep-dive script) by filtering event_type
--     down to just the two card types, ignoring goals/assists/VAR.
INSERT INTO fact_bookings (source, match_key, team_key, player_name, minute, card_type)
SELECT
    'mominullptr_2026',
    e.match_key,
    e.team_key,
    p.player_name,
    e.minute,
    CASE WHEN e.event_type = 'Red Card' THEN 'Red' ELSE 'Yellow' END
FROM fact_match_events_2026 e
LEFT JOIN dim_player_2026 p ON p.player_key = e.player_key
WHERE e.event_type IN ('Yellow Card', 'Red Card');

-- =====================================================================
-- Sanity checks — run after:
--
-- SELECT source, COUNT(*) FROM fact_awards GROUP BY source;
--   expect 'manual_2026' = 6, 'jfjelstul' = a few hundred
--
-- SELECT source, card_type, COUNT(*) FROM fact_bookings GROUP BY source, card_type;
--   2026 Yellow should be 253, 2026 Red should be 15 (matches your earlier check)
-- =====================================================================
