-- Casino Brawyal play telemetry, schema 001.
--
-- One database on the shared voicevikkidb server, owned by a role that can
-- reach nothing else. The game never connects here: it POSTs batches to the
-- ingest service, which is the only thing holding a credential.
--
-- Identity is the install UUID. The IP is recorded alongside it, server-side,
-- from the connection — a desktop client cannot see its own public address,
-- and a client-supplied one would be a claim rather than a fact.

CREATE TABLE IF NOT EXISTS installs (
    install_id      uuid PRIMARY KEY,
    first_seen_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at    timestamptz NOT NULL DEFAULT now(),
    first_ip        inet,
    last_ip         inet,
    last_ip_country text,
    os_name         text,
    os_version      text,
    cpu_name        text,
    cpu_count       int,
    gpu_name        text,
    screen_size     text,
    locale          text,
    play_count      int NOT NULL DEFAULT 0
);

-- One process launch. A play may contain several runs, or none.
CREATE TABLE IF NOT EXISTS plays (
    play_id       uuid PRIMARY KEY,
    install_id    uuid NOT NULL REFERENCES installs(install_id) ON DELETE CASCADE,
    game_version  text,
    started_at    timestamptz,
    ended_at      timestamptz,
    duration_sec  int,
    active_sec    int,
    ended_cleanly boolean NOT NULL DEFAULT false,
    ip            inet NOT NULL,
    ip_country    text,
    received_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS plays_install_idx ON plays (install_id, started_at DESC);
CREATE INDEX IF NOT EXISTS plays_ip_idx ON plays (ip);

CREATE TABLE IF NOT EXISTS runs (
    run_id             uuid PRIMARY KEY,
    play_id            uuid REFERENCES plays(play_id) ON DELETE CASCADE,
    install_id         uuid NOT NULL REFERENCES installs(install_id) ON DELETE CASCADE,
    seed               bigint,
    path_id            text,
    started_at         timestamptz,
    ended_at           timestamptz,
    duration_sec       int,
    outcome            text,            -- victory | defeat | abandoned | in_progress
    final_encounter    int,
    encounters_cleared int,
    final_hp           int,
    max_hp             int,
    coins_earned       int,
    coins_spent        int,
    relic_ids          text[],
    ability_ids        text[],
    ability_tiers      jsonb,
    reels              int,
    resumed_count      int NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS runs_install_idx ON runs (install_id, started_at DESC);
CREATE INDEX IF NOT EXISTS runs_outcome_idx ON runs (outcome, final_encounter);

CREATE TABLE IF NOT EXISTS combats (
    combat_id        uuid PRIMARY KEY,
    run_id           uuid NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
    encounter_number int,
    encounter_type   text,              -- combat | elite | boss
    lineup_id        text,
    enemy_ids        text[],
    combat_seed      bigint,
    started_at       timestamptz,
    ended_at         timestamptz,
    duration_sec     int,
    rounds           int,
    won              boolean,
    hp_before        int,
    hp_after         int,
    damage_dealt     int,
    damage_taken     int,
    block_gained     int,
    chips_spun       int,
    chips_spent      int
);
CREATE INDEX IF NOT EXISTS combats_run_idx ON combats (run_id, encounter_number);
CREATE INDEX IF NOT EXISTS combats_lineup_idx ON combats (lineup_id, won);

-- Every decision the player makes. `(run_id, seq)` is what makes a replayed
-- batch a no-op: the transport is at-least-once, storage is exactly-once.
CREATE TABLE IF NOT EXISTS moves (
    move_id      bigserial PRIMARY KEY,
    run_id       uuid NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
    combat_id    uuid REFERENCES combats(combat_id) ON DELETE CASCADE,
    seq          int NOT NULL,
    at           timestamptz,
    round_number int,
    kind         text NOT NULL,
    detail       jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (run_id, seq)
);
CREATE INDEX IF NOT EXISTS moves_kind_idx ON moves (kind);

-- A batch the ingest service has already accepted. The client resends on any
-- uncertain response; this is what makes that free.
CREATE TABLE IF NOT EXISTS ingest_batches (
    batch_id    uuid PRIMARY KEY,
    install_id  uuid,
    received_at timestamptz NOT NULL DEFAULT now(),
    event_count int,
    ip          inet
);

-- ---------------------------------------------------------------- reporting
-- The questions the designer actually asks, one SELECT away.

CREATE OR REPLACE VIEW v_run_funnel AS
SELECT final_encounter,
       count(*)                                        AS runs,
       count(*) FILTER (WHERE outcome = 'victory')      AS wins,
       count(*) FILTER (WHERE outcome = 'defeat')       AS deaths,
       count(*) FILTER (WHERE outcome = 'abandoned')    AS quits,
       round(avg(duration_sec) / 60.0, 1)               AS avg_minutes
FROM runs
WHERE outcome <> 'in_progress'
GROUP BY final_encounter
ORDER BY final_encounter;

CREATE OR REPLACE VIEW v_enemy_lethality AS
SELECT lineup_id,
       count(*)                                   AS fights,
       count(*) FILTER (WHERE won IS FALSE)       AS losses,
       round(100.0 * count(*) FILTER (WHERE won IS FALSE) / nullif(count(*), 0), 1)
                                                  AS loss_pct,
       round(avg(rounds), 1)                      AS avg_rounds,
       round(avg(damage_taken), 1)                AS avg_damage_taken
FROM combats
GROUP BY lineup_id
ORDER BY loss_pct DESC NULLS LAST;

CREATE OR REPLACE VIEW v_ability_usage AS
SELECT detail ->> 'ability'                       AS ability_id,
       count(*)                                   AS times_fired,
       count(DISTINCT run_id)                     AS runs_used_in
FROM moves
WHERE kind = 'ability_fired' AND detail ? 'ability'
GROUP BY 1
ORDER BY times_fired DESC;

CREATE OR REPLACE VIEW v_session_length AS
SELECT date_trunc('day', started_at)::date        AS day,
       count(*)                                   AS plays,
       count(DISTINCT install_id)                 AS players,
       round(avg(duration_sec) / 60.0, 1)         AS avg_minutes,
       count(*) FILTER (WHERE ended_cleanly IS FALSE) AS unclean_exits
FROM plays
WHERE started_at IS NOT NULL
GROUP BY 1
ORDER BY 1 DESC;

CREATE OR REPLACE VIEW v_path_popularity AS
SELECT path_id,
       count(*)                                   AS runs,
       count(*) FILTER (WHERE outcome = 'victory') AS wins,
       round(avg(final_encounter), 1)             AS avg_depth
FROM runs
WHERE path_id IS NOT NULL
GROUP BY 1
ORDER BY runs DESC;
