/*
# Guess The Character - server functions

Plain-English summary
All game logic runs on the server. The browser never receives the correct answer, the accepted spellings or the hidden hints before the server decides they are visible, and it never sends points: points are computed here from the server clock.

1. Public functions (callable with the player's private session token)
- create_character_room: creates a room of type guess_character (same rooms / players / sessions tables as RISK IT). Joining, leaving, resuming and host hand-over on leave keep using join_room, resume_session and leave_room.
- char_update_settings: host only, lobby only (mode, rounds, seconds, questions per player, categories).
- char_start_game: host only, needs 2+ players and enough characters.
- char_submit_guess: validates the guess on the server, scores it, blocks double scoring and repeated guesses, limits wrong attempts to 3 per round.
- char_ask_question: public yes/no question about the character (answered from stored facts), limited per player.
- char_advance: any player's device may call it; the server only moves the phase when its deadline or condition is reached. A row lock makes double transitions impossible.
- char_next_round: host skips the reveal pause.
- char_play_again: host resets to the lobby without recreating the room (scores reset, room code kept).
- char_heartbeat: marks the player as online and hands the host role over if the host has been silent for 45 seconds.
- char_get_state: everything one player is allowed to see right now.
- char_admin_save_character: admin only, saves a character with its hints and aliases in one step.

2. Scoring (server side)
- Correct guess: 100 / 80 / 60 / 40 / 30 / 20 points depending on how many hints were visible at that moment (hints are revealed evenly over the round time).
- First correct guess of the round: speed bonus +20 (+50 in Fast Guess mode).
- Wrong guess: no points. A player can send at most 3 wrong guesses per round, never the same guess twice, and only one correct guess per round.

3. Modes
- classic: image shown from the start.
- mystery: image never shown during the round.
- progressive: image starts heavily blurred and sharpens with each hint.
- fast: image shown, bigger speed bonus, and the round ends 5 seconds after the first correct guess.

4. Security
- Internal helpers cannot be called from the browser.
- Image path is only returned when the mode shows the image and the round is running (or during the reveal).
*/

-- Helpers ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.game_normalize(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT btrim(regexp_replace(
    regexp_replace(
      regexp_replace(
        lower(translate(
          regexp_replace(coalesce(p_text, ''), '[\u064B-\u0652\u0640]', '', 'g'),
          'أإآٱىةؤئ',
          'اااايهوي'
        )),
        '[[:punct:]،؛؟«»“”‘’]', ' ', 'g'
      ),
      '(^| )ال(?=[^ ]{2,})', '\1', 'g'
    ),
    '\s+', ' ', 'g'
  ))
$$;

CREATE OR REPLACE FUNCTION public.char_hint_points(p_visible integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (ARRAY[100, 80, 60, 40, 30, 20])[greatest(1, least(coalesce(p_visible, 1), 6))]
$$;

CREATE OR REPLACE FUNCTION public.char_hints_visible(p_total integer, p_started timestamptz, p_seconds integer, p_now timestamptz)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_started IS NULL OR p_total < 1 THEN 0
    ELSE least(
      p_total,
      1 + floor(greatest(0, extract(epoch FROM (p_now - p_started))) / (p_seconds::numeric / p_total))::integer
    )
  END
$$;

CREATE OR REPLACE FUNCTION public.char_load_player(p_token uuid)
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
    RAISE EXCEPTION 'session_not_found';
  END IF;
  RETURN v_player;
END $$;

CREATE OR REPLACE FUNCTION public.char_lock_game(p_room_id uuid)
RETURNS character_games
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_game character_games%ROWTYPE;
BEGIN
  SELECT g.* INTO v_game
  FROM character_games g
  JOIN rooms r ON r.id = g.room_id
  WHERE g.room_id = p_room_id AND r.game_type = 'guess_character'
  FOR UPDATE OF g;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'wrong_game_type';
  END IF;
  RETURN v_game;
END $$;

CREATE OR REPLACE FUNCTION public.char_emit(p_room uuid, p_kind text, p_player uuid, p_round integer)
RETURNS void
LANGUAGE sql
SET search_path = public
AS $$
  INSERT INTO character_events (room_id, kind, player_id, round_number) VALUES (p_room, p_kind, p_player, p_round)
$$;

-- Presence and host hand-over --------------------------------------------------------
CREATE OR REPLACE FUNCTION public.char_touch(p_player uuid, p_room uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_host players%ROWTYPE;
  v_seen timestamptz;
BEGIN
  INSERT INTO character_presence (player_id, seen_at) VALUES (p_player, clock_timestamp())
  ON CONFLICT (player_id) DO UPDATE SET seen_at = EXCLUDED.seen_at
  WHERE character_presence.seen_at < clock_timestamp() - interval '5 seconds';

  SELECT * INTO v_host FROM players WHERE room_id = p_room AND is_host;
  IF NOT FOUND OR v_host.id = p_player THEN
    RETURN;
  END IF;

  v_seen := coalesce((SELECT seen_at FROM character_presence WHERE player_id = v_host.id), v_host.joined_at);
  IF v_seen >= clock_timestamp() - interval '45 seconds' THEN
    RETURN;
  END IF;

  PERFORM 1 FROM rooms WHERE id = p_room FOR UPDATE;
  SELECT * INTO v_host FROM players WHERE room_id = p_room AND is_host;
  IF FOUND AND v_host.id <> p_player THEN
    v_seen := coalesce((SELECT seen_at FROM character_presence WHERE player_id = v_host.id), v_host.joined_at);
    IF v_seen < clock_timestamp() - interval '45 seconds' THEN
      UPDATE players SET is_host = false WHERE id = v_host.id;
      UPDATE players SET is_host = true WHERE id = p_player;
      PERFORM char_emit(p_room, 'host', p_player, NULL);
    END IF;
  END IF;
END $$;

-- Round engine ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.char_eligible_count(p_categories text[])
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT count(*)::integer
  FROM characters c
  WHERE c.is_active
    AND (cardinality(p_categories) = 0 OR c.category = ANY (p_categories))
    AND (SELECT count(*) FROM character_hints h WHERE h.character_id = c.id) >= 3
$$;

CREATE OR REPLACE FUNCTION public.char_begin_round(p_game uuid, p_round integer)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  g character_games%ROWTYPE;
  c characters%ROWTYPE;
BEGIN
  SELECT * INTO g FROM character_games WHERE id = p_game;

  SELECT ch.* INTO c
  FROM characters ch
  WHERE ch.is_active
    AND (cardinality(g.categories) = 0 OR ch.category = ANY (g.categories))
    AND (SELECT count(*) FROM character_hints h WHERE h.character_id = ch.id) >= 3
    AND NOT (ch.id = ANY (g.used_character_ids))
    AND NOT EXISTS (SELECT 1 FROM character_rounds r WHERE r.game_id = g.id AND r.character_id = ch.id)
  ORDER BY random()
  LIMIT 1;

  IF NOT FOUND THEN
    -- Everything was used in earlier games of this room: allow repeats from earlier games only.
    SELECT ch.* INTO c
    FROM characters ch
    WHERE ch.is_active
      AND (cardinality(g.categories) = 0 OR ch.category = ANY (g.categories))
      AND (SELECT count(*) FROM character_hints h WHERE h.character_id = ch.id) >= 3
      AND NOT EXISTS (SELECT 1 FROM character_rounds r WHERE r.game_id = g.id AND r.character_id = ch.id)
    ORDER BY random()
    LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_enough_characters';
  END IF;

  INSERT INTO character_rounds (game_id, round_number, character_id, category, name_ar, image_path, hints, answers, facts)
  VALUES (
    g.id,
    p_round,
    c.id,
    c.category,
    c.name_ar,
    c.image_path,
    (SELECT coalesce(jsonb_agg(h.text_ar ORDER BY h.position), '[]'::jsonb)
       FROM character_hints h WHERE h.character_id = c.id),
    (SELECT coalesce(array_agg(DISTINCT x.n), '{}')
       FROM (
         SELECT game_normalize(c.name_ar) AS n
         UNION SELECT game_normalize(c.name_en)
         UNION SELECT game_normalize(a.alias_text) FROM character_aliases a WHERE a.character_id = c.id
       ) x
       WHERE x.n <> ''),
    jsonb_build_object(
      'is_male', c.is_male,
      'is_alive', c.is_alive,
      'is_egyptian', c.is_egyptian,
      'is_arab', c.is_arab,
      'is_real', c.is_real
    )
  );

  UPDATE character_games
  SET current_round = p_round,
      phase = 'countdown',
      phase_ends_at = clock_timestamp() + interval '4 seconds',
      used_character_ids = array_append(used_character_ids, c.id)
  WHERE id = g.id;

  PERFORM char_emit(g.room_id, 'phase', NULL, p_round);
END $$;

CREATE OR REPLACE FUNCTION public.char_finish_game(p_game uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  g character_games%ROWTYPE;
BEGIN
  SELECT * INTO g FROM character_games WHERE id = p_game;
  UPDATE character_games SET phase = 'finished', phase_ends_at = NULL, finished_at = clock_timestamp() WHERE id = g.id;
  UPDATE rooms SET status = 'finished' WHERE id = g.room_id;
  PERFORM char_emit(g.room_id, 'phase', NULL, g.current_round);
END $$;

-- Moves the game forward when its deadline/condition is reached. The caller holds the game row lock.
CREATE OR REPLACE FUNCTION public.char_step(p_game uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  g character_games%ROWTYPE;
  v_now timestamptz := clock_timestamp();
  v_players integer;
  v_solved integer;
BEGIN
  SELECT * INTO g FROM character_games WHERE id = p_game;
  IF g.phase IN ('setup', 'finished') THEN
    RETURN;
  END IF;

  SELECT count(*) INTO v_players FROM players WHERE room_id = g.room_id;
  IF v_players < 2 THEN
    UPDATE character_rounds
    SET ended_at = v_now, end_reason = 'players_left'
    WHERE game_id = g.id AND round_number = g.current_round AND ended_at IS NULL;
    PERFORM char_finish_game(g.id);
    RETURN;
  END IF;

  IF g.phase = 'countdown' THEN
    IF v_now >= g.phase_ends_at THEN
      UPDATE character_rounds SET started_at = v_now WHERE game_id = g.id AND round_number = g.current_round;
      UPDATE character_games
      SET phase = 'round', phase_ends_at = v_now + make_interval(secs => g.round_seconds)
      WHERE id = g.id;
      PERFORM char_emit(g.room_id, 'phase', NULL, g.current_round);
    END IF;

  ELSIF g.phase = 'round' THEN
    SELECT count(DISTINCT player_id) INTO v_solved
    FROM character_guesses
    WHERE game_id = g.id AND round_number = g.current_round AND is_correct;

    IF v_now >= g.phase_ends_at OR v_solved >= v_players THEN
      UPDATE character_rounds
      SET ended_at = v_now,
          end_reason = CASE WHEN v_solved >= v_players THEN 'all_guessed' ELSE 'timer' END
      WHERE game_id = g.id AND round_number = g.current_round;
      UPDATE character_games SET phase = 'reveal', phase_ends_at = v_now + interval '10 seconds' WHERE id = g.id;
      PERFORM char_emit(g.room_id, 'phase', NULL, g.current_round);
    END IF;

  ELSIF g.phase = 'reveal' THEN
    IF v_now >= g.phase_ends_at THEN
      IF g.current_round < g.total_rounds THEN
        PERFORM char_begin_round(g.id, g.current_round + 1);
      ELSE
        PERFORM char_finish_game(g.id);
      END IF;
    END IF;
  END IF;
END $$;

-- Public functions --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_character_room(p_name text, p_avatar text, p_max_players integer)
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
  PERFORM assert_room_settings(p_max_players, 'solo');

  v_code := generate_room_code();
  INSERT INTO rooms (code, max_players, game_mode, game_type)
  VALUES (v_code, p_max_players, 'solo', 'guess_character')
  RETURNING id INTO v_room_id;

  INSERT INTO players (room_id, name, avatar, is_host)
  VALUES (v_room_id, v_name, p_avatar, true)
  RETURNING id INTO v_player_id;

  INSERT INTO player_sessions (player_id)
  VALUES (v_player_id)
  RETURNING token INTO v_token;

  INSERT INTO character_games (room_id) VALUES (v_room_id);
  INSERT INTO character_presence (player_id) VALUES (v_player_id);

  RETURN jsonb_build_object(
    'room_id', v_room_id,
    'player_id', v_player_id,
    'token', v_token,
    'code', v_code,
    'game_type', 'guess_character'
  );
END $$;

CREATE OR REPLACE FUNCTION public.char_update_settings(
  p_token uuid,
  p_mode text,
  p_total_rounds integer,
  p_round_seconds integer,
  p_questions_per_player integer,
  p_categories text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_game character_games%ROWTYPE;
  v_categories text[] := coalesce(p_categories, '{}');
BEGIN
  v_player := char_load_player(p_token);
  v_game := char_lock_game(v_player.room_id);

  IF NOT v_player.is_host THEN
    RAISE EXCEPTION 'not_host';
  END IF;
  IF v_game.phase <> 'setup' THEN
    RAISE EXCEPTION 'room_already_started';
  END IF;
  IF p_mode IS NULL OR p_mode NOT IN ('classic', 'mystery', 'progressive', 'fast') THEN
    RAISE EXCEPTION 'invalid_mode';
  END IF;
  IF p_total_rounds IS NULL OR p_total_rounds NOT BETWEEN 3 AND 10 THEN
    RAISE EXCEPTION 'invalid_rounds';
  END IF;
  IF p_round_seconds IS NULL OR p_round_seconds NOT BETWEEN 20 AND 90 THEN
    RAISE EXCEPTION 'invalid_round_seconds';
  END IF;
  IF p_questions_per_player IS NULL OR p_questions_per_player NOT BETWEEN 0 AND 5 THEN
    RAISE EXCEPTION 'invalid_questions';
  END IF;
  IF NOT (v_categories <@ ARRAY['football', 'arab_artists', 'world_celebrities', 'actors', 'cartoon', 'historical', 'games_movies']) THEN
    RAISE EXCEPTION 'invalid_categories';
  END IF;

  UPDATE character_games
  SET mode = p_mode,
      total_rounds = p_total_rounds,
      round_seconds = p_round_seconds,
      questions_per_player = p_questions_per_player,
      categories = (SELECT coalesce(array_agg(DISTINCT x ORDER BY x), '{}') FROM unnest(v_categories) AS x)
  WHERE id = v_game.id;

  PERFORM char_emit(v_player.room_id, 'settings', v_player.id, NULL);
END $$;

CREATE OR REPLACE FUNCTION public.char_start_game(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_game character_games%ROWTYPE;
  v_room rooms%ROWTYPE;
  v_players integer;
BEGIN
  v_player := char_load_player(p_token);
  v_game := char_lock_game(v_player.room_id);
  SELECT * INTO v_room FROM rooms WHERE id = v_player.room_id FOR UPDATE;

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
  IF char_eligible_count(v_game.categories) < v_game.total_rounds THEN
    RAISE EXCEPTION 'not_enough_characters';
  END IF;

  INSERT INTO game_scores (room_id, game_type, player_id)
  SELECT v_room.id, 'guess_character', p.id FROM players p WHERE p.room_id = v_room.id
  ON CONFLICT (room_id, game_type, player_id)
  DO UPDATE SET points = 0, correct_count = 0, fastest_count = 0, updated_at = now();

  UPDATE rooms SET status = 'playing' WHERE id = v_room.id;
  UPDATE character_games SET started_at = clock_timestamp(), finished_at = NULL WHERE id = v_game.id;

  PERFORM char_begin_round(v_game.id, 1);
END $$;

CREATE OR REPLACE FUNCTION public.char_submit_guess(p_token uuid, p_text text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  g character_games%ROWTYPE;
  r character_rounds%ROWTYPE;
  v_now timestamptz := clock_timestamp();
  v_text text := btrim(coalesce(p_text, ''));
  v_norm text;
  v_wrong integer;
  v_correct boolean;
  v_visible integer;
  v_base integer;
  v_bonus integer := 0;
  v_first boolean;
BEGIN
  v_player := char_load_player(p_token);
  g := char_lock_game(v_player.room_id);

  IF g.phase <> 'round' OR v_now >= g.phase_ends_at THEN
    RAISE EXCEPTION 'round_closed';
  END IF;

  IF char_length(v_text) < 1 OR char_length(v_text) > 80 THEN
    RAISE EXCEPTION 'invalid_guess';
  END IF;
  v_norm := game_normalize(v_text);
  IF v_norm = '' THEN
    RAISE EXCEPTION 'invalid_guess';
  END IF;

  SELECT * INTO r FROM character_rounds WHERE game_id = g.id AND round_number = g.current_round;

  IF EXISTS (
    SELECT 1 FROM character_guesses
    WHERE game_id = g.id AND round_number = g.current_round AND player_id = v_player.id AND is_correct
  ) THEN
    RAISE EXCEPTION 'already_solved';
  END IF;

  SELECT count(*) INTO v_wrong
  FROM character_guesses
  WHERE game_id = g.id AND round_number = g.current_round AND player_id = v_player.id AND NOT is_correct;
  IF v_wrong >= 3 THEN
    RAISE EXCEPTION 'no_attempts_left';
  END IF;

  IF EXISTS (
    SELECT 1 FROM character_guesses
    WHERE game_id = g.id AND round_number = g.current_round AND player_id = v_player.id AND normalized = v_norm
  ) THEN
    RAISE EXCEPTION 'duplicate_guess';
  END IF;

  v_correct := v_norm = ANY (r.answers);

  IF NOT v_correct THEN
    INSERT INTO character_guesses (game_id, round_number, player_id, guess_text, normalized, is_correct)
    VALUES (g.id, g.current_round, v_player.id, v_text, v_norm, false);
    PERFORM char_emit(g.room_id, 'guess', v_player.id, g.current_round);
    RETURN jsonb_build_object('correct', false, 'attempts_left', 3 - v_wrong - 1);
  END IF;

  v_visible := char_hints_visible(jsonb_array_length(r.hints), r.started_at, g.round_seconds, v_now);
  v_base := char_hint_points(v_visible);
  v_first := NOT EXISTS (
    SELECT 1 FROM character_guesses
    WHERE game_id = g.id AND round_number = g.current_round AND is_correct
  );
  IF v_first THEN
    v_bonus := CASE WHEN g.mode = 'fast' THEN 50 ELSE 20 END;
  END IF;

  INSERT INTO character_guesses (
    game_id, round_number, player_id, guess_text, normalized, is_correct,
    hints_visible, base_points, speed_bonus, elapsed_ms
  )
  VALUES (
    g.id, g.current_round, v_player.id, v_text, v_norm, true,
    v_visible, v_base, v_bonus,
    (extract(epoch FROM (v_now - r.started_at)) * 1000)::integer
  );

  INSERT INTO game_scores (room_id, game_type, player_id, points, correct_count, fastest_count)
  VALUES (g.room_id, 'guess_character', v_player.id, v_base + v_bonus, 1, CASE WHEN v_first THEN 1 ELSE 0 END)
  ON CONFLICT (room_id, game_type, player_id) DO UPDATE
  SET points = game_scores.points + EXCLUDED.points,
      correct_count = game_scores.correct_count + 1,
      fastest_count = game_scores.fastest_count + EXCLUDED.fastest_count,
      updated_at = now();

  IF v_first AND g.mode = 'fast' THEN
    UPDATE character_games
    SET phase_ends_at = least(phase_ends_at, v_now + interval '5 seconds')
    WHERE id = g.id;
  END IF;

  PERFORM char_emit(g.room_id, 'guess', v_player.id, g.current_round);
  PERFORM char_step(g.id);

  RETURN jsonb_build_object(
    'correct', true,
    'points', v_base,
    'speed_bonus', v_bonus,
    'hints_visible', v_visible
  );
END $$;

CREATE OR REPLACE FUNCTION public.char_ask_question(p_token uuid, p_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  g character_games%ROWTYPE;
  r character_rounds%ROWTYPE;
  v_answer text;
  v_used integer;
BEGIN
  v_player := char_load_player(p_token);
  g := char_lock_game(v_player.room_id);

  IF g.phase <> 'round' OR clock_timestamp() >= g.phase_ends_at THEN
    RAISE EXCEPTION 'round_closed';
  END IF;
  IF p_key IS NULL OR p_key NOT IN ('is_male', 'is_alive', 'is_egyptian', 'is_arab', 'is_real') THEN
    RAISE EXCEPTION 'invalid_question';
  END IF;
  IF EXISTS (
    SELECT 1 FROM character_guesses
    WHERE game_id = g.id AND round_number = g.current_round AND player_id = v_player.id AND is_correct
  ) THEN
    RAISE EXCEPTION 'already_solved';
  END IF;

  SELECT count(*) INTO v_used
  FROM character_questions
  WHERE game_id = g.id AND round_number = g.current_round AND player_id = v_player.id;
  IF v_used >= g.questions_per_player THEN
    RAISE EXCEPTION 'no_questions_left';
  END IF;

  IF EXISTS (
    SELECT 1 FROM character_questions
    WHERE game_id = g.id AND round_number = g.current_round AND question_key = p_key
  ) THEN
    RAISE EXCEPTION 'question_already_asked';
  END IF;

  SELECT * INTO r FROM character_rounds WHERE game_id = g.id AND round_number = g.current_round;
  v_answer := CASE
    WHEN r.facts ->> p_key IS NULL THEN 'na'
    WHEN (r.facts ->> p_key)::boolean THEN 'yes'
    ELSE 'no'
  END;

  INSERT INTO character_questions (game_id, round_number, player_id, question_key, answer)
  VALUES (g.id, g.current_round, v_player.id, p_key, v_answer);

  PERFORM char_emit(g.room_id, 'question', v_player.id, g.current_round);

  RETURN jsonb_build_object('answer', v_answer, 'questions_left', g.questions_per_player - v_used - 1);
END $$;

CREATE OR REPLACE FUNCTION public.char_advance(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  g character_games%ROWTYPE;
BEGIN
  v_player := char_load_player(p_token);
  PERFORM char_touch(v_player.id, v_player.room_id);
  g := char_lock_game(v_player.room_id);
  PERFORM char_step(g.id);
END $$;

CREATE OR REPLACE FUNCTION public.char_next_round(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  g character_games%ROWTYPE;
BEGIN
  v_player := char_load_player(p_token);
  g := char_lock_game(v_player.room_id);
  IF NOT v_player.is_host THEN
    RAISE EXCEPTION 'not_host';
  END IF;
  IF g.phase = 'reveal' THEN
    UPDATE character_games SET phase_ends_at = clock_timestamp() WHERE id = g.id;
    PERFORM char_step(g.id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.char_play_again(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  g character_games%ROWTYPE;
BEGIN
  v_player := char_load_player(p_token);
  g := char_lock_game(v_player.room_id);
  IF NOT v_player.is_host THEN
    RAISE EXCEPTION 'not_host';
  END IF;
  IF g.phase <> 'finished' THEN
    RAISE EXCEPTION 'game_not_finished';
  END IF;

  DELETE FROM character_rounds WHERE game_id = g.id;
  UPDATE game_scores
  SET points = 0, correct_count = 0, fastest_count = 0, updated_at = now()
  WHERE room_id = g.room_id AND game_type = 'guess_character';
  UPDATE character_games
  SET phase = 'setup', current_round = 0, phase_ends_at = NULL, started_at = NULL, finished_at = NULL
  WHERE id = g.id;
  UPDATE rooms SET status = 'lobby' WHERE id = g.room_id;

  PERFORM char_emit(g.room_id, 'phase', v_player.id, 0);
END $$;

CREATE OR REPLACE FUNCTION public.char_heartbeat(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
BEGIN
  v_player := char_load_player(p_token);
  PERFORM char_touch(v_player.id, v_player.room_id);
END $$;

CREATE OR REPLACE FUNCTION public.char_get_state(p_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  g character_games%ROWTYPE;
  r character_rounds%ROWTYPE;
  v_room rooms%ROWTYPE;
  v_now timestamptz := clock_timestamp();
  v_total integer;
  v_visible integer := 0;
  v_show_image boolean;
  v_round jsonb := NULL;
  v_reveal jsonb := NULL;
  v_next_hint timestamptz := NULL;
  v_wrong integer := 0;
  v_asked integer := 0;
  v_solved boolean := false;
  v_my_points integer := 0;
  v_catalog jsonb := NULL;
BEGIN
  v_player := char_load_player(p_token);
  SELECT * INTO v_room FROM rooms WHERE id = v_player.room_id;
  SELECT * INTO g FROM character_games WHERE room_id = v_player.room_id;
  IF NOT FOUND OR v_room.game_type <> 'guess_character' THEN
    RAISE EXCEPTION 'wrong_game_type';
  END IF;

  PERFORM char_touch(v_player.id, v_player.room_id);
  -- the host may have changed during char_touch
  SELECT * INTO v_player FROM players WHERE id = v_player.id;

  v_show_image := g.mode IN ('classic', 'progressive', 'fast');

  IF g.current_round > 0 THEN
    SELECT * INTO r FROM character_rounds WHERE game_id = g.id AND round_number = g.current_round;
  END IF;

  IF r.game_id IS NOT NULL AND g.phase IN ('countdown', 'round', 'reveal') THEN
    v_total := jsonb_array_length(r.hints);
    IF g.phase = 'round' THEN
      v_visible := char_hints_visible(v_total, r.started_at, g.round_seconds, v_now);
      IF v_visible < v_total THEN
        v_next_hint := r.started_at + make_interval(secs => (g.round_seconds::numeric / v_total) * v_visible);
      END IF;
    ELSIF g.phase = 'reveal' THEN
      v_visible := v_total;
    END IF;

    SELECT count(*) FILTER (WHERE NOT cg.is_correct), coalesce(bool_or(cg.is_correct), false),
           coalesce(sum(cg.base_points + cg.speed_bonus) FILTER (WHERE cg.is_correct), 0)
      INTO v_wrong, v_solved, v_my_points
    FROM character_guesses cg
    WHERE cg.game_id = g.id AND cg.round_number = g.current_round AND cg.player_id = v_player.id;

    SELECT count(*) INTO v_asked
    FROM character_questions q
    WHERE q.game_id = g.id AND q.round_number = g.current_round AND q.player_id = v_player.id;

    v_round := jsonb_build_object(
      'round_number', g.current_round,
      'category', r.category,
      'show_image', v_show_image,
      'image_path', CASE WHEN g.phase = 'reveal' OR (g.phase = 'round' AND v_show_image) THEN r.image_path ELSE NULL END,
      'hints_total', v_total,
      'hints_visible', v_visible,
      'hints', (
        SELECT coalesce(jsonb_agg(x.t ORDER BY x.ord), '[]'::jsonb)
        FROM jsonb_array_elements_text(r.hints) WITH ORDINALITY AS x(t, ord)
        WHERE x.ord <= v_visible
      ),
      'next_hint_at', v_next_hint,
      'started_at', r.started_at,
      'feed', (
        SELECT coalesce(jsonb_agg(f.item ORDER BY f.at), '[]'::jsonb)
        FROM (
          SELECT * FROM (
            SELECT jsonb_build_object(
                     'kind', 'guess',
                     'player_id', cg.player_id,
                     'text', CASE WHEN cg.is_correct THEN NULL ELSE cg.guess_text END,
                     'correct', cg.is_correct
                   ) AS item,
                   cg.created_at AS at
            FROM character_guesses cg
            WHERE cg.game_id = g.id AND cg.round_number = g.current_round
            UNION ALL
            SELECT jsonb_build_object(
                     'kind', 'question',
                     'player_id', q.player_id,
                     'key', q.question_key,
                     'answer', q.answer
                   ),
                   q.created_at
            FROM character_questions q
            WHERE q.game_id = g.id AND q.round_number = g.current_round
          ) u
          ORDER BY u.at DESC
          LIMIT 40
        ) f
      )
    );

    IF g.phase = 'reveal' THEN
      v_reveal := jsonb_build_object(
        'name', r.name_ar,
        'end_reason', r.end_reason,
        'results', (
          SELECT coalesce(jsonb_agg(jsonb_build_object(
            'player_id', p.id,
            'solved', cg.id IS NOT NULL,
            'points', coalesce(cg.base_points + cg.speed_bonus, 0),
            'speed_bonus', coalesce(cg.speed_bonus, 0),
            'hints_visible', cg.hints_visible,
            'elapsed_ms', cg.elapsed_ms
          ) ORDER BY coalesce(cg.base_points + cg.speed_bonus, 0) DESC, cg.elapsed_ms NULLS LAST, p.joined_at), '[]'::jsonb)
          FROM players p
          LEFT JOIN character_guesses cg
            ON cg.game_id = g.id AND cg.round_number = g.current_round AND cg.player_id = p.id AND cg.is_correct
          WHERE p.room_id = g.room_id
        )
      );
    END IF;
  END IF;

  IF g.phase = 'setup' THEN
    SELECT coalesce(jsonb_object_agg(x.category, x.cnt), '{}'::jsonb) INTO v_catalog
    FROM (
      SELECT c.category, count(*) AS cnt
      FROM characters c
      WHERE c.is_active AND (SELECT count(*) FROM character_hints h WHERE h.character_id = c.id) >= 3
      GROUP BY c.category
    ) x;
  END IF;

  RETURN jsonb_build_object(
    'server_now', v_now,
    'me', jsonb_build_object(
      'player_id', v_player.id,
      'is_host', v_player.is_host,
      'solved', v_solved,
      'attempts_left', greatest(0, 3 - v_wrong),
      'questions_left', greatest(0, g.questions_per_player - v_asked),
      'round_points', v_my_points
    ),
    'room', jsonb_build_object(
      'code', v_room.code,
      'status', v_room.status,
      'max_players', v_room.max_players
    ),
    'game', jsonb_build_object(
      'id', g.id,
      'phase', g.phase,
      'mode', g.mode,
      'round_number', g.current_round,
      'total_rounds', g.total_rounds,
      'round_seconds', g.round_seconds,
      'questions_per_player', g.questions_per_player,
      'categories', to_jsonb(g.categories),
      'phase_ends_at', g.phase_ends_at
    ),
    'catalog', v_catalog,
    'round', v_round,
    'reveal', v_reveal,
    'players', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'player_id', p.id,
        'name', p.name,
        'avatar', p.avatar,
        'is_host', p.is_host,
        'is_me', p.id = v_player.id,
        'joined_at', p.joined_at,
        'points', coalesce(s.points, 0),
        'correct_count', coalesce(s.correct_count, 0),
        'fastest_count', coalesce(s.fastest_count, 0),
        'online', coalesce(pr.seen_at, p.joined_at) > v_now - interval '30 seconds',
        'solved', EXISTS (
          SELECT 1 FROM character_guesses cg
          WHERE cg.game_id = g.id AND cg.round_number = g.current_round AND cg.player_id = p.id AND cg.is_correct
        ) AND g.phase IN ('round', 'reveal')
      ) ORDER BY coalesce(s.points, 0) DESC, p.joined_at, p.id), '[]'::jsonb)
      FROM players p
      LEFT JOIN game_scores s ON s.room_id = p.room_id AND s.game_type = 'guess_character' AND s.player_id = p.id
      LEFT JOIN character_presence pr ON pr.player_id = p.id
      WHERE p.room_id = v_player.room_id
    )
  );
END $$;

-- Admin ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.char_admin_save_character(
  p_id uuid,
  p_name_ar text,
  p_name_en text,
  p_category text,
  p_image_path text,
  p_is_male boolean,
  p_is_alive boolean,
  p_is_egyptian boolean,
  p_is_arab boolean,
  p_is_real boolean,
  p_is_active boolean,
  p_hints text[],
  p_aliases text[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid := p_id;
  v_hints text[];
  v_aliases text[];
BEGIN
  IF NOT public.game_is_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;
  IF char_length(btrim(coalesce(p_name_ar, ''))) < 1 THEN
    RAISE EXCEPTION 'invalid_name';
  END IF;

  SELECT coalesce(array_agg(btrim(h) ORDER BY ord), '{}') INTO v_hints
  FROM unnest(coalesce(p_hints, '{}')) WITH ORDINALITY AS t(h, ord)
  WHERE btrim(h) <> '';
  IF cardinality(v_hints) > 6 THEN
    RAISE EXCEPTION 'too_many_hints';
  END IF;
  IF coalesce(p_is_active, true) AND cardinality(v_hints) < 3 THEN
    RAISE EXCEPTION 'need_three_hints';
  END IF;

  SELECT coalesce(array_agg(DISTINCT btrim(a)), '{}') INTO v_aliases
  FROM unnest(coalesce(p_aliases, '{}')) AS a
  WHERE btrim(a) <> '';

  IF v_id IS NULL THEN
    INSERT INTO characters (name_ar, name_en, category, image_path, is_male, is_alive, is_egyptian, is_arab, is_real, is_active)
    VALUES (btrim(p_name_ar), nullif(btrim(coalesce(p_name_en, '')), ''), p_category, nullif(p_image_path, ''),
            p_is_male, p_is_alive, p_is_egyptian, p_is_arab, p_is_real, coalesce(p_is_active, true))
    RETURNING id INTO v_id;
  ELSE
    UPDATE characters
    SET name_ar = btrim(p_name_ar),
        name_en = nullif(btrim(coalesce(p_name_en, '')), ''),
        category = p_category,
        image_path = nullif(p_image_path, ''),
        is_male = p_is_male,
        is_alive = p_is_alive,
        is_egyptian = p_is_egyptian,
        is_arab = p_is_arab,
        is_real = p_is_real,
        is_active = coalesce(p_is_active, true),
        updated_at = now()
    WHERE id = v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'character_not_found';
    END IF;
  END IF;

  DELETE FROM character_hints WHERE character_id = v_id;
  INSERT INTO character_hints (character_id, position, text_ar)
  SELECT v_id, t.ord::integer, t.h FROM unnest(v_hints) WITH ORDINALITY AS t(h, ord);

  DELETE FROM character_aliases WHERE character_id = v_id;
  INSERT INTO character_aliases (character_id, alias_text)
  SELECT v_id, a FROM unnest(v_aliases) AS a;

  RETURN v_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'character_exists';
END $$;

-- Permissions ---------------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.game_normalize(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.char_hint_points(integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.char_hints_visible(integer, timestamptz, integer, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.char_load_player(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.char_lock_game(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.char_emit(uuid, text, uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.char_touch(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.char_eligible_count(text[]) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.char_begin_round(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.char_finish_game(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.char_step(uuid) FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.create_character_room(text, text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.char_update_settings(uuid, text, integer, integer, integer, text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.char_start_game(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.char_submit_guess(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.char_ask_question(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.char_advance(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.char_next_round(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.char_play_again(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.char_heartbeat(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.char_get_state(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_character_room(text, text, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.char_update_settings(uuid, text, integer, integer, integer, text[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.char_start_game(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.char_submit_guess(uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.char_ask_question(uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.char_advance(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.char_next_round(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.char_play_again(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.char_heartbeat(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.char_get_state(uuid) TO anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.char_admin_save_character(uuid, text, text, text, text, boolean, boolean, boolean, boolean, boolean, boolean, text[], text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.char_admin_save_character(uuid, text, text, text, text, boolean, boolean, boolean, boolean, boolean, boolean, text[], text[]) TO authenticated;
