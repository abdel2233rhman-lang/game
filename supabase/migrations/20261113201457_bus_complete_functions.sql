/*
# Bus Complete server functions (game logic, scoring, admin review)

Plain-English summary
This migration adds every server-side action the BUS COMPLETE game needs. Players act through a session token, exactly like RISK IT. The server checks every rule (host only, correct phase, time not expired, letter matches, no duplicate answer in a sheet) and computes scores itself. Clients never write to game tables directly.

1. New player functions (callable with a session token)
- create_bus_room: creates a Bus Complete room in one step. It sets game_type = 'bus_complete' at creation and never touches create_room.
- bus_update_settings: host sets number of rounds, seconds per round, categories per round (lobby only).
- bus_set_categories: host selects the category pool (lobby only).
- bus_set_team: player joins or leaves a team in team mode (lobby only, max two per team).
- bus_start_game: host starts the game after checks (2+ players, 3+ categories, complete teams in team mode).
- bus_submit_answer: saves a player's answer for one category on their sheet during an open round. Validates letter, length and duplicates inside the sheet. Answers are matched to the approved bank now, but points are given only when the round ends.
- bus_press_bus_complete: any player ends the round early.
- bus_advance: idempotent timer step. Ends an expired round, then starts the next round or finishes the game after the results window.
- bus_get_state: returns everything a player may see. Other players' answers are hidden during a round and revealed after it ends.

2. Internal functions (not callable by clients)
- bus_load_player, bus_lock_game, bus_match_answer, bus_begin_round, bus_finish_round, bus_score_round, bus_rescore_sheets.

3. Admin functions (signed-in users listed in bus_admins only)
- bus_admin_pending_submissions: queue of answers waiting for review.
- bus_admin_review_submission: links a submission to an approved bank answer, optionally stores its text as an alias, and recalculates scores of finished rounds.
- bus_admin_reject_submission: rejects a submission and recalculates scores if needed.
- bus_admin_add_answer: adds a bank answer (approved or pending review) with optional aliases, checking for conflicts.
- bus_admin_set_answer_status: approves, sends back to review, or rejects a bank answer and recalculates affected scores.
- bus_admin_add_alias: adds an alias to a bank answer, checking for conflicts.

4. Scoring rules (implemented in bus_score_round)
- A matched answer that only one sheet wrote scores 10 points.
- A matched answer written by two or more sheets (players or teams) scores 5 points for each of them.
- Unmatched answers (Pending Review) and rejected answers score 0 until an admin decides.
- Team mode: one sheet per team, so a team's answer counts once.
- Scores are recalculated from scratch for a round every time, so repeated calls give the same result.

5. Security
- Every function uses SET search_path = public.
- Player functions are granted to anon and authenticated because players have no sign-in; access is controlled by the session token, which is never readable by clients.
- Internal functions are revoked from PUBLIC, anon and authenticated.
- Admin functions are granted to authenticated only, and each one checks bus_is_admin() first.

6. Notes
- Results window (12 seconds) is a fixed value inside bus_finish_round.
- Timers use the database clock (clock_timestamp), never the browser clock.
- This migration does not change create_room, join_room, start_game or any other RISK IT function.
*/

CREATE OR REPLACE FUNCTION public.bus_match_answer(p_category uuid, p_normalized text)
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT x.id FROM (
    SELECT b.id
    FROM bus_answer_bank b
    WHERE b.category_id = p_category AND b.status = 'approved' AND b.normalized = p_normalized
    UNION ALL
    SELECT al.answer_id
    FROM bus_answer_aliases al
    JOIN bus_answer_bank b ON b.id = al.answer_id
    WHERE b.category_id = p_category AND b.status = 'approved' AND al.normalized = p_normalized
  ) x
  ORDER BY x.id
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.bus_load_player(p_token uuid)
RETURNS players
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
BEGIN
  SELECT p.* INTO v_player
  FROM player_sessions s
  JOIN players p ON p.id = s.player_id
  WHERE s.token = p_token;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_session';
  END IF;
  RETURN v_player;
END $$;

CREATE OR REPLACE FUNCTION public.bus_lock_game(p_room_id uuid)
RETURNS bus_games
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_game bus_games%ROWTYPE;
BEGIN
  SELECT g.* INTO v_game
  FROM bus_games g
  JOIN rooms r ON r.id = g.room_id
  WHERE g.room_id = p_room_id AND r.game_type = 'bus_complete'
  FOR UPDATE OF g;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'wrong_game_type';
  END IF;
  RETURN v_game;
END $$;

CREATE OR REPLACE FUNCTION public.bus_score_round(p_game uuid, p_round integer)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE bus_answers a
  SET points = 0
  FROM bus_sheets s
  WHERE s.id = a.sheet_id AND s.game_id = p_game AND s.round_number = p_round;

  UPDATE bus_answers a
  SET points = CASE WHEN c.n = 1 THEN 10 ELSE 5 END
  FROM (
    SELECT x.matched_answer_id, count(DISTINCT x.sheet_id) AS n
    FROM bus_answers x
    JOIN bus_sheets s ON s.id = x.sheet_id
    WHERE s.game_id = p_game AND s.round_number = p_round
      AND x.status = 'matched' AND x.matched_answer_id IS NOT NULL
    GROUP BY x.matched_answer_id
  ) c
  WHERE a.status = 'matched'
    AND a.matched_answer_id = c.matched_answer_id
    AND a.sheet_id IN (SELECT id FROM bus_sheets WHERE game_id = p_game AND round_number = p_round);
END $$;

CREATE OR REPLACE FUNCTION public.bus_rescore_sheets(p_sheet_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_rec record;
BEGIN
  FOR v_rec IN
    SELECT DISTINCT s.game_id, s.round_number
    FROM bus_sheets s
    JOIN bus_rounds r ON r.game_id = s.game_id AND r.round_number = s.round_number
    WHERE s.id = ANY(p_sheet_ids) AND r.ended_at IS NOT NULL
  LOOP
    PERFORM bus_score_round(v_rec.game_id, v_rec.round_number);
    INSERT INTO bus_events (game_id, round_number, kind)
    VALUES (v_rec.game_id, v_rec.round_number, 'review_updated');
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.bus_begin_round(p_game uuid, p_round integer)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_game bus_games%ROWTYPE;
  v_room rooms%ROWTYPE;
  v_cats uuid[];
  v_letter text;
BEGIN
  SELECT * INTO v_game FROM bus_games WHERE id = p_game;
  SELECT * INTO v_room FROM rooms WHERE id = v_game.room_id;

  SELECT coalesce(array_agg(x.category_id ORDER BY x.ord), '{}')
  INTO v_cats
  FROM (
    SELECT gc.category_id,
           row_number() OVER (ORDER BY used.cnt, random()) AS ord
    FROM bus_game_categories gc
    CROSS JOIN LATERAL (
      SELECT count(*) AS cnt
      FROM bus_round_categories rc
      WHERE rc.game_id = gc.game_id AND rc.category_id = gc.category_id
    ) used
    WHERE gc.game_id = p_game
  ) x
  WHERE x.ord <= v_game.categories_per_round;

  SELECT l.letter INTO v_letter
  FROM bus_letters l
  WHERE l.is_enabled
  ORDER BY
    ((SELECT count(DISTINCT b.category_id) FROM bus_answer_bank b
      WHERE b.letter = l.letter AND b.status = 'approved' AND b.category_id = ANY(v_cats))
      = cardinality(v_cats)) DESC,
    EXISTS (SELECT 1 FROM bus_rounds r WHERE r.game_id = p_game AND r.letter = l.letter),
    (SELECT count(DISTINCT b.category_id) FROM bus_answer_bank b
      WHERE b.letter = l.letter AND b.status = 'approved' AND b.category_id = ANY(v_cats)) DESC,
    random()
  LIMIT 1;

  INSERT INTO bus_rounds (game_id, round_number, letter)
  VALUES (p_game, p_round, v_letter);

  INSERT INTO bus_round_categories (game_id, round_number, category_id, position)
  SELECT p_game, p_round, c.id, c.ord::integer
  FROM unnest(v_cats) WITH ORDINALITY AS c(id, ord);

  IF v_room.game_mode = 'team' THEN
    INSERT INTO bus_sheets (game_id, round_number, team_id)
    SELECT p_game, p_round, t.id FROM bus_teams t WHERE t.game_id = p_game;
  ELSE
    INSERT INTO bus_sheets (game_id, round_number, player_id)
    SELECT p_game, p_round, p.id FROM players p WHERE p.room_id = v_room.id;
  END IF;

  UPDATE bus_games
  SET phase = 'round',
      current_round = p_round,
      round_ends_at = clock_timestamp() + make_interval(secs => v_game.round_seconds),
      results_ends_at = NULL
  WHERE id = p_game;

  INSERT INTO bus_events (game_id, round_number, kind)
  VALUES (p_game, p_round, 'round_started');
END $$;

CREATE OR REPLACE FUNCTION public.bus_finish_round(p_game uuid, p_round integer, p_reason text, p_by uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE bus_rounds
  SET ended_at = clock_timestamp(), end_reason = p_reason, ended_by = p_by
  WHERE game_id = p_game AND round_number = p_round AND ended_at IS NULL;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  PERFORM bus_score_round(p_game, p_round);

  UPDATE bus_games
  SET phase = 'results',
      round_ends_at = NULL,
      results_ends_at = clock_timestamp() + make_interval(secs => 12)
  WHERE id = p_game;

  INSERT INTO bus_events (game_id, round_number, kind)
  VALUES (p_game, p_round, 'round_ended');
END $$;

CREATE OR REPLACE FUNCTION public.create_bus_room(p_name text, p_avatar text, p_max_players integer, p_game_mode text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name text;
  v_code text;
  v_room_id uuid;
  v_player_id uuid;
  v_token uuid;
BEGIN
  v_name := assert_player_input(p_name, p_avatar);
  PERFORM assert_room_settings(p_max_players, p_game_mode);

  v_code := generate_room_code();
  INSERT INTO rooms (code, max_players, game_mode, game_type)
  VALUES (v_code, p_max_players, p_game_mode, 'bus_complete')
  RETURNING id INTO v_room_id;

  INSERT INTO players (room_id, name, avatar, is_host)
  VALUES (v_room_id, v_name, p_avatar, true)
  RETURNING id INTO v_player_id;

  INSERT INTO player_sessions (player_id)
  VALUES (v_player_id)
  RETURNING token INTO v_token;

  INSERT INTO bus_games (room_id)
  VALUES (v_room_id);

  RETURN jsonb_build_object(
    'room_id', v_room_id,
    'player_id', v_player_id,
    'token', v_token,
    'code', v_code,
    'game_type', 'bus_complete'
  );
END $$;

CREATE OR REPLACE FUNCTION public.bus_update_settings(p_token uuid, p_total_rounds integer, p_round_seconds integer, p_categories_per_round integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_game bus_games%ROWTYPE;
BEGIN
  v_player := bus_load_player(p_token);
  v_game := bus_lock_game(v_player.room_id);

  IF NOT v_player.is_host THEN
    RAISE EXCEPTION 'not_host';
  END IF;
  IF v_game.phase <> 'setup' THEN
    RAISE EXCEPTION 'game_already_started';
  END IF;
  IF p_total_rounds IS NULL OR p_total_rounds NOT BETWEEN 1 AND 10
     OR p_round_seconds IS NULL OR p_round_seconds NOT BETWEEN 30 AND 180
     OR p_categories_per_round IS NULL OR p_categories_per_round NOT BETWEEN 3 AND 6 THEN
    RAISE EXCEPTION 'invalid_settings';
  END IF;

  UPDATE bus_games
  SET total_rounds = p_total_rounds,
      round_seconds = p_round_seconds,
      categories_per_round = p_categories_per_round
  WHERE id = v_game.id;
END $$;

CREATE OR REPLACE FUNCTION public.bus_set_categories(p_token uuid, p_category_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_game bus_games%ROWTYPE;
BEGIN
  v_player := bus_load_player(p_token);
  v_game := bus_lock_game(v_player.room_id);

  IF NOT v_player.is_host THEN
    RAISE EXCEPTION 'not_host';
  END IF;
  IF v_game.phase <> 'setup' THEN
    RAISE EXCEPTION 'game_already_started';
  END IF;
  IF cardinality(coalesce(p_category_ids, '{}')) > 25 THEN
    RAISE EXCEPTION 'invalid_categories';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(coalesce(p_category_ids, '{}')) AS c(id)
    WHERE NOT EXISTS (SELECT 1 FROM bus_categories bc WHERE bc.id = c.id AND bc.is_active)
  ) THEN
    RAISE EXCEPTION 'invalid_categories';
  END IF;

  DELETE FROM bus_game_categories WHERE game_id = v_game.id;
  INSERT INTO bus_game_categories (game_id, category_id)
  SELECT DISTINCT v_game.id, c.id FROM unnest(coalesce(p_category_ids, '{}')) AS c(id);
END $$;

CREATE OR REPLACE FUNCTION public.bus_set_team(p_token uuid, p_team_position integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_room rooms%ROWTYPE;
  v_game bus_games%ROWTYPE;
  v_team_id uuid;
BEGIN
  v_player := bus_load_player(p_token);
  v_game := bus_lock_game(v_player.room_id);
  SELECT * INTO v_room FROM rooms WHERE id = v_player.room_id;

  IF v_game.phase <> 'setup' THEN
    RAISE EXCEPTION 'game_already_started';
  END IF;
  IF v_room.game_mode <> 'team' THEN
    RAISE EXCEPTION 'not_team_mode';
  END IF;
  IF p_team_position IS NOT NULL AND p_team_position NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'invalid_team';
  END IF;

  DELETE FROM bus_team_members WHERE game_id = v_game.id AND player_id = v_player.id;
  DELETE FROM bus_teams t
  WHERE t.game_id = v_game.id
    AND NOT EXISTS (SELECT 1 FROM bus_team_members m WHERE m.team_id = t.id);

  IF p_team_position IS NULL THEN
    RETURN;
  END IF;

  SELECT t.id INTO v_team_id FROM bus_teams t
  WHERE t.game_id = v_game.id AND t.position = p_team_position;

  IF NOT FOUND THEN
    INSERT INTO bus_teams (game_id, position, name)
    VALUES (v_game.id, p_team_position, 'الفريق ' || p_team_position)
    RETURNING id INTO v_team_id;
  END IF;

  IF (SELECT count(*) FROM bus_team_members m WHERE m.team_id = v_team_id) >= 2 THEN
    RAISE EXCEPTION 'team_full';
  END IF;

  INSERT INTO bus_team_members (game_id, player_id, team_id)
  VALUES (v_game.id, v_player.id, v_team_id);
END $$;

CREATE OR REPLACE FUNCTION public.bus_start_game(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_room rooms%ROWTYPE;
  v_game bus_games%ROWTYPE;
  v_players integer;
  v_categories integer;
BEGIN
  v_player := bus_load_player(p_token);
  v_game := bus_lock_game(v_player.room_id);
  SELECT * INTO v_room FROM rooms WHERE id = v_player.room_id;

  IF NOT v_player.is_host THEN
    RAISE EXCEPTION 'not_host';
  END IF;
  IF v_game.phase <> 'setup' OR v_room.status <> 'lobby' THEN
    RAISE EXCEPTION 'room_already_started';
  END IF;

  SELECT count(*) INTO v_players FROM players WHERE room_id = v_room.id;
  IF v_players < 2 THEN
    RAISE EXCEPTION 'not_enough_players';
  END IF;

  SELECT count(*) INTO v_categories FROM bus_game_categories WHERE game_id = v_game.id;
  IF v_categories < 3 OR v_categories < v_game.categories_per_round THEN
    RAISE EXCEPTION 'not_enough_categories';
  END IF;

  IF v_room.game_mode = 'team' THEN
    IF v_players % 2 <> 0 THEN
      RAISE EXCEPTION 'teams_incomplete';
    END IF;
    IF EXISTS (
      SELECT 1 FROM players p
      WHERE p.room_id = v_room.id
        AND NOT EXISTS (SELECT 1 FROM bus_team_members m WHERE m.game_id = v_game.id AND m.player_id = p.id)
    ) THEN
      RAISE EXCEPTION 'teams_incomplete';
    END IF;
    IF EXISTS (
      SELECT 1 FROM bus_teams t
      WHERE t.game_id = v_game.id
        AND (SELECT count(*) FROM bus_team_members m WHERE m.team_id = t.id) <> 2
    ) THEN
      RAISE EXCEPTION 'teams_incomplete';
    END IF;
  END IF;

  UPDATE rooms SET status = 'playing' WHERE id = v_room.id;
  UPDATE bus_games SET started_at = clock_timestamp() WHERE id = v_game.id;

  PERFORM bus_begin_round(v_game.id, 1);

  INSERT INTO bus_events (game_id, round_number, kind)
  VALUES (v_game.id, NULL, 'game_started');
END $$;

CREATE OR REPLACE FUNCTION public.bus_submit_answer(p_token uuid, p_category_id uuid, p_text text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_room rooms%ROWTYPE;
  v_game bus_games%ROWTYPE;
  v_sheet_id uuid;
  v_letter text;
  v_text text;
  v_norm text;
  v_match uuid;
BEGIN
  v_player := bus_load_player(p_token);
  v_game := bus_lock_game(v_player.room_id);
  SELECT * INTO v_room FROM rooms WHERE id = v_player.room_id;

  IF v_game.phase <> 'round' OR v_game.round_ends_at IS NULL OR clock_timestamp() >= v_game.round_ends_at THEN
    RAISE EXCEPTION 'round_closed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM bus_round_categories rc
    WHERE rc.game_id = v_game.id AND rc.round_number = v_game.current_round AND rc.category_id = p_category_id
  ) THEN
    RAISE EXCEPTION 'invalid_category';
  END IF;

  IF v_room.game_mode = 'team' THEN
    SELECT s.id INTO v_sheet_id
    FROM bus_sheets s
    JOIN bus_team_members m ON m.team_id = s.team_id AND m.game_id = s.game_id
    WHERE s.game_id = v_game.id AND s.round_number = v_game.current_round AND m.player_id = v_player.id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'not_in_team';
    END IF;
  ELSE
    SELECT s.id INTO v_sheet_id
    FROM bus_sheets s
    WHERE s.game_id = v_game.id AND s.round_number = v_game.current_round AND s.player_id = v_player.id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'not_in_game';
    END IF;
  END IF;

  v_text := btrim(coalesce(p_text, ''));
  IF v_text = '' THEN
    DELETE FROM bus_answers WHERE sheet_id = v_sheet_id AND category_id = p_category_id;
    INSERT INTO bus_events (game_id, round_number, kind)
    VALUES (v_game.id, v_game.current_round, 'answer_saved');
    RETURN jsonb_build_object('status', 'cleared');
  END IF;

  IF char_length(v_text) > 60 THEN
    RAISE EXCEPTION 'answer_too_long';
  END IF;

  v_norm := bus_normalize(v_text);
  SELECT r.letter INTO v_letter FROM bus_rounds r
  WHERE r.game_id = v_game.id AND r.round_number = v_game.current_round;
  IF v_norm = '' OR left(v_norm, 1) <> v_letter THEN
    RAISE EXCEPTION 'wrong_letter';
  END IF;

  v_match := bus_match_answer(p_category_id, v_norm);

  IF v_match IS NOT NULL AND EXISTS (
    SELECT 1 FROM bus_answers a
    WHERE a.sheet_id = v_sheet_id AND a.matched_answer_id = v_match AND a.category_id <> p_category_id
  ) THEN
    RAISE EXCEPTION 'duplicate_in_sheet';
  END IF;

  INSERT INTO bus_answers (sheet_id, category_id, answer_text, normalized, matched_answer_id, status, points, submitted_by, updated_at)
  VALUES (
    v_sheet_id, p_category_id, v_text, v_norm, v_match,
    CASE WHEN v_match IS NULL THEN 'pending_review' ELSE 'matched' END,
    0, v_player.id, clock_timestamp()
  )
  ON CONFLICT (sheet_id, category_id) DO UPDATE
  SET answer_text = EXCLUDED.answer_text,
      normalized = EXCLUDED.normalized,
      matched_answer_id = EXCLUDED.matched_answer_id,
      status = EXCLUDED.status,
      points = 0,
      submitted_by = EXCLUDED.submitted_by,
      updated_at = EXCLUDED.updated_at;

  INSERT INTO bus_events (game_id, round_number, kind)
  VALUES (v_game.id, v_game.current_round, 'answer_saved');

  RETURN jsonb_build_object('status', 'saved');
END $$;

CREATE OR REPLACE FUNCTION public.bus_press_bus_complete(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_game bus_games%ROWTYPE;
BEGIN
  v_player := bus_load_player(p_token);
  v_game := bus_lock_game(v_player.room_id);

  IF v_game.phase <> 'round' OR v_game.round_ends_at IS NULL OR clock_timestamp() >= v_game.round_ends_at THEN
    RETURN;
  END IF;

  PERFORM bus_finish_round(v_game.id, v_game.current_round, 'bus_complete', v_player.id);
END $$;

CREATE OR REPLACE FUNCTION public.bus_advance(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_game bus_games%ROWTYPE;
BEGIN
  v_player := bus_load_player(p_token);
  v_game := bus_lock_game(v_player.room_id);

  IF v_game.phase = 'round' AND v_game.round_ends_at IS NOT NULL AND clock_timestamp() >= v_game.round_ends_at THEN
    PERFORM bus_finish_round(v_game.id, v_game.current_round, 'timer', NULL);
    RETURN;
  END IF;

  IF v_game.phase = 'results' AND v_game.results_ends_at IS NOT NULL AND clock_timestamp() >= v_game.results_ends_at THEN
    IF v_game.current_round < v_game.total_rounds THEN
      PERFORM bus_begin_round(v_game.id, v_game.current_round + 1);
    ELSE
      UPDATE bus_games
      SET phase = 'finished', results_ends_at = NULL, finished_at = clock_timestamp()
      WHERE id = v_game.id;
      UPDATE rooms SET status = 'finished' WHERE id = v_game.room_id;
      INSERT INTO bus_events (game_id, round_number, kind)
      VALUES (v_game.id, NULL, 'game_finished');
    END IF;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.bus_get_state(p_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_room rooms%ROWTYPE;
  v_game bus_games%ROWTYPE;
  v_team_id uuid;
  v_sheet_id uuid;
  v_revealed boolean;
BEGIN
  v_player := bus_load_player(p_token);
  SELECT * INTO v_room FROM rooms WHERE id = v_player.room_id;
  IF v_room.game_type <> 'bus_complete' THEN
    RAISE EXCEPTION 'wrong_game_type';
  END IF;
  SELECT * INTO v_game FROM bus_games WHERE room_id = v_room.id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'wrong_game_type';
  END IF;

  v_revealed := v_game.phase IN ('results', 'finished');

  SELECT m.team_id INTO v_team_id
  FROM bus_team_members m
  WHERE m.game_id = v_game.id AND m.player_id = v_player.id;

  IF v_game.current_round > 0 THEN
    IF v_room.game_mode = 'team' THEN
      SELECT s.id INTO v_sheet_id
      FROM bus_sheets s
      WHERE s.game_id = v_game.id AND s.round_number = v_game.current_round AND s.team_id = v_team_id;
    ELSE
      SELECT s.id INTO v_sheet_id
      FROM bus_sheets s
      WHERE s.game_id = v_game.id AND s.round_number = v_game.current_round AND s.player_id = v_player.id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'server_now', floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint,
    'room', jsonb_build_object(
      'code', v_room.code,
      'status', v_room.status,
      'game_mode', v_room.game_mode,
      'max_players', v_room.max_players
    ),
    'me', jsonb_build_object(
      'player_id', v_player.id,
      'is_host', v_player.is_host,
      'team_id', v_team_id,
      'sheet_id', v_sheet_id
    ),
    'game', jsonb_build_object(
      'phase', v_game.phase,
      'total_rounds', v_game.total_rounds,
      'round_seconds', v_game.round_seconds,
      'categories_per_round', v_game.categories_per_round,
      'current_round', v_game.current_round,
      'round_ends_at_ms', floor(extract(epoch FROM v_game.round_ends_at) * 1000)::bigint,
      'results_ends_at_ms', floor(extract(epoch FROM v_game.results_ends_at) * 1000)::bigint
    ),
    'categories', (
      SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name_ar, 'group', c.group_key) ORDER BY c.sort_order), '[]'::jsonb)
      FROM bus_categories c WHERE c.is_active
    ),
    'selected_category_ids', (
      SELECT coalesce(jsonb_agg(gc.category_id), '[]'::jsonb)
      FROM bus_game_categories gc WHERE gc.game_id = v_game.id
    ),
    'round', (
      SELECT jsonb_build_object(
        'number', r.round_number,
        'letter', l.display,
        'categories', (
          SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name_ar, 'group', c.group_key) ORDER BY rc.position), '[]'::jsonb)
          FROM bus_round_categories rc
          JOIN bus_categories c ON c.id = rc.category_id
          WHERE rc.game_id = r.game_id AND rc.round_number = r.round_number
        )
      )
      FROM bus_rounds r
      JOIN bus_letters l ON l.letter = r.letter
      WHERE r.game_id = v_game.id AND r.round_number = v_game.current_round
    ),
    'my_answers', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'category_id', a.category_id,
        'text', a.answer_text,
        'status', CASE WHEN v_revealed THEN a.status ELSE 'saved' END,
        'points', CASE WHEN v_revealed THEN a.points ELSE 0 END
      )), '[]'::jsonb)
      FROM bus_answers a
      WHERE a.sheet_id = v_sheet_id
    ),
    'players', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'avatar', p.avatar,
        'is_host', p.is_host,
        'team_position', t.position
      ) ORDER BY p.joined_at, p.id), '[]'::jsonb)
      FROM players p
      LEFT JOIN bus_team_members m ON m.player_id = p.id AND m.game_id = v_game.id
      LEFT JOIN bus_teams t ON t.id = m.team_id
      WHERE p.room_id = v_room.id
    ),
    'standings', CASE
      WHEN v_room.game_mode = 'team' THEN (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'id', t.id,
          'name', t.name,
          'position', t.position,
          'members', (
            SELECT coalesce(jsonb_agg(p.name ORDER BY p.joined_at), '[]'::jsonb)
            FROM bus_team_members m JOIN players p ON p.id = m.player_id
            WHERE m.team_id = t.id
          ),
          'score', (
            SELECT coalesce(sum(a.points), 0)
            FROM bus_sheets s JOIN bus_answers a ON a.sheet_id = s.id
            WHERE s.team_id = t.id
          )
        ) ORDER BY t.position), '[]'::jsonb)
        FROM bus_teams t WHERE t.game_id = v_game.id
      )
      ELSE (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'id', p.id,
          'name', p.name,
          'avatar', p.avatar,
          'score', (
            SELECT coalesce(sum(a.points), 0)
            FROM bus_sheets s JOIN bus_answers a ON a.sheet_id = s.id
            WHERE s.player_id = p.id
          )
        ) ORDER BY p.joined_at, p.id), '[]'::jsonb)
        FROM players p WHERE p.room_id = v_room.id
      )
    END,
    'history', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'round', r.round_number,
        'letter', l.display,
        'reason', r.end_reason,
        'categories', (
          SELECT coalesce(jsonb_agg(jsonb_build_object(
            'id', c.id,
            'name', c.name_ar,
            'entries', (
              SELECT coalesce(jsonb_agg(jsonb_build_object(
                'owner', coalesce(p.name, t.name),
                'text', a.answer_text,
                'status', a.status,
                'points', a.points
              ) ORDER BY a.points DESC, a.answer_text), '[]'::jsonb)
              FROM bus_sheets s
              JOIN bus_answers a ON a.sheet_id = s.id
              LEFT JOIN players p ON p.id = s.player_id
              LEFT JOIN bus_teams t ON t.id = s.team_id
              WHERE s.game_id = v_game.id AND s.round_number = r.round_number AND a.category_id = c.id
            )
          ) ORDER BY rc.position), '[]'::jsonb)
          FROM bus_round_categories rc
          JOIN bus_categories c ON c.id = rc.category_id
          WHERE rc.game_id = v_game.id AND rc.round_number = r.round_number
        )
      ) ORDER BY r.round_number), '[]'::jsonb)
      FROM bus_rounds r
      JOIN bus_letters l ON l.letter = r.letter
      WHERE r.game_id = v_game.id AND r.ended_at IS NOT NULL
    )
  );
END $$;

CREATE OR REPLACE FUNCTION public.bus_admin_pending_submissions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT bus_is_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id,
      'text', a.answer_text,
      'normalized', a.normalized,
      'category_id', a.category_id,
      'category', c.name_ar,
      'game_id', s.game_id,
      'round', s.round_number,
      'owner', coalesce(p.name, t.name),
      'round_ended', r.ended_at IS NOT NULL
    ) ORDER BY a.updated_at DESC), '[]'::jsonb)
    FROM bus_answers a
    JOIN bus_sheets s ON s.id = a.sheet_id
    JOIN bus_rounds r ON r.game_id = s.game_id AND r.round_number = s.round_number
    JOIN bus_categories c ON c.id = a.category_id
    LEFT JOIN players p ON p.id = s.player_id
    LEFT JOIN bus_teams t ON t.id = s.team_id
    WHERE a.status = 'pending_review'
  );
END $$;

CREATE OR REPLACE FUNCTION public.bus_admin_review_submission(p_submission uuid, p_answer uuid, p_add_alias boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub bus_answers%ROWTYPE;
  v_sheets uuid[];
BEGIN
  IF NOT bus_is_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  SELECT * INTO v_sub FROM bus_answers WHERE id = p_submission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission_not_found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM bus_answer_bank b
    WHERE b.id = p_answer AND b.status = 'approved' AND b.category_id = v_sub.category_id
  ) THEN
    RAISE EXCEPTION 'invalid_answer_link';
  END IF;

  IF p_add_alias AND v_sub.normalized <> (SELECT b.normalized FROM bus_answer_bank b WHERE b.id = p_answer) THEN
    IF EXISTS (
      SELECT 1 FROM bus_answer_bank b
      WHERE b.category_id = v_sub.category_id AND b.normalized = v_sub.normalized AND b.id <> p_answer
    ) THEN
      RAISE EXCEPTION 'alias_conflict';
    END IF;
    INSERT INTO bus_answer_aliases (answer_id, alias_text)
    VALUES (p_answer, v_sub.answer_text)
    ON CONFLICT (answer_id, normalized) DO NOTHING;
  END IF;

  SELECT coalesce(array_agg(a.sheet_id), '{}') INTO v_sheets
  FROM bus_answers a
  WHERE a.category_id = v_sub.category_id AND a.normalized = v_sub.normalized AND a.status = 'pending_review';

  UPDATE bus_answers a
  SET matched_answer_id = p_answer, status = 'matched', updated_at = clock_timestamp()
  WHERE a.category_id = v_sub.category_id AND a.normalized = v_sub.normalized AND a.status = 'pending_review';

  PERFORM bus_rescore_sheets(v_sheets);
END $$;

CREATE OR REPLACE FUNCTION public.bus_admin_reject_submission(p_submission uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub bus_answers%ROWTYPE;
BEGIN
  IF NOT bus_is_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  SELECT * INTO v_sub FROM bus_answers WHERE id = p_submission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission_not_found';
  END IF;

  UPDATE bus_answers
  SET status = 'rejected', matched_answer_id = NULL, points = 0, updated_at = clock_timestamp()
  WHERE id = p_submission;

  PERFORM bus_rescore_sheets(ARRAY[v_sub.sheet_id]);
END $$;

CREATE OR REPLACE FUNCTION public.bus_admin_add_answer(p_category uuid, p_text text, p_status text, p_aliases text[])
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_alias text;
BEGIN
  IF NOT bus_is_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;
  IF p_status NOT IN ('approved', 'pending_review') THEN
    RAISE EXCEPTION 'invalid_status';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM bus_categories WHERE id = p_category) THEN
    RAISE EXCEPTION 'invalid_category';
  END IF;

  BEGIN
    INSERT INTO bus_answer_bank (category_id, answer_text, status, source)
    VALUES (p_category, btrim(p_text), p_status, 'admin')
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_answer';
  END;

  FOREACH v_alias IN ARRAY coalesce(p_aliases, '{}') LOOP
    IF EXISTS (
      SELECT 1 FROM bus_answer_bank b
      WHERE b.category_id = p_category AND b.normalized = bus_normalize(v_alias) AND b.id <> v_id
    ) OR EXISTS (
      SELECT 1 FROM bus_answer_aliases al
      JOIN bus_answer_bank b ON b.id = al.answer_id
      WHERE b.category_id = p_category AND al.normalized = bus_normalize(v_alias) AND al.answer_id <> v_id
    ) THEN
      RAISE EXCEPTION 'alias_conflict';
    END IF;
    INSERT INTO bus_answer_aliases (answer_id, alias_text)
    VALUES (v_id, v_alias)
    ON CONFLICT (answer_id, normalized) DO NOTHING;
  END LOOP;

  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.bus_admin_add_alias(p_answer uuid, p_alias text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_category uuid;
BEGIN
  IF NOT bus_is_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  SELECT b.category_id INTO v_category FROM bus_answer_bank b WHERE b.id = p_answer;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'answer_not_found';
  END IF;

  IF EXISTS (
    SELECT 1 FROM bus_answer_bank b
    WHERE b.category_id = v_category AND b.normalized = bus_normalize(p_alias) AND b.id <> p_answer
  ) OR EXISTS (
    SELECT 1 FROM bus_answer_aliases al
    JOIN bus_answer_bank b ON b.id = al.answer_id
    WHERE b.category_id = v_category AND al.normalized = bus_normalize(p_alias) AND al.answer_id <> p_answer
  ) THEN
    RAISE EXCEPTION 'alias_conflict';
  END IF;

  INSERT INTO bus_answer_aliases (answer_id, alias_text)
  VALUES (p_answer, p_alias)
  ON CONFLICT (answer_id, normalized) DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION public.bus_admin_set_answer_status(p_answer uuid, p_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sheets uuid[];
BEGIN
  IF NOT bus_is_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;
  IF p_status NOT IN ('approved', 'pending_review', 'rejected') THEN
    RAISE EXCEPTION 'invalid_status';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM bus_answer_bank WHERE id = p_answer) THEN
    RAISE EXCEPTION 'answer_not_found';
  END IF;

  UPDATE bus_answer_bank SET status = p_status WHERE id = p_answer;

  IF p_status <> 'approved' THEN
    SELECT coalesce(array_agg(a.sheet_id), '{}') INTO v_sheets
    FROM bus_answers a WHERE a.matched_answer_id = p_answer;

    UPDATE bus_answers
    SET matched_answer_id = NULL, status = 'pending_review', points = 0, updated_at = clock_timestamp()
    WHERE matched_answer_id = p_answer;

    PERFORM bus_rescore_sheets(v_sheets);
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.bus_match_answer(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bus_load_player(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bus_lock_game(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bus_score_round(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bus_rescore_sheets(uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bus_begin_round(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bus_finish_round(uuid, integer, text, uuid) FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.create_bus_room(text, text, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.bus_update_settings(uuid, integer, integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.bus_set_categories(uuid, uuid[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.bus_set_team(uuid, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.bus_start_game(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.bus_submit_answer(uuid, uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.bus_press_bus_complete(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.bus_advance(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.bus_get_state(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_bus_room(text, text, integer, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bus_update_settings(uuid, integer, integer, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bus_set_categories(uuid, uuid[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bus_set_team(uuid, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bus_start_game(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bus_submit_answer(uuid, uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bus_press_bus_complete(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bus_advance(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bus_get_state(uuid) TO anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.bus_admin_pending_submissions() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.bus_admin_review_submission(uuid, uuid, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.bus_admin_reject_submission(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.bus_admin_add_answer(uuid, text, text, text[]) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.bus_admin_add_alias(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.bus_admin_set_answer_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bus_admin_pending_submissions() TO authenticated;
GRANT EXECUTE ON FUNCTION public.bus_admin_review_submission(uuid, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bus_admin_reject_submission(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bus_admin_add_answer(uuid, text, text, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bus_admin_add_alias(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bus_admin_set_answer_status(uuid, text) TO authenticated;
