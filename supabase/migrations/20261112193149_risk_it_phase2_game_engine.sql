/*
# RISK IT - Phase 2: game engine (betting, questions, timers, scoring)

1. New Tables
- `questions`: question bank (12 categories x 4 difficulties). Holds the correct answer, so it is private to the server.
- `games`: one active game per room. Holds phase (betting / question / reveal / finished), round number, and phase deadline.
- `game_players`: each player's balance and result counters inside a game.
- `game_rounds`: which question was used in each round (prevents repeats inside one match).
- `round_actions`: each player's bet and answer for a round. Private: bets and answers are never readable from the browser.
- `game_events`: public, non-secret event log (bet placed, answer locked, phase changed). Used for real-time updates.

2. Modified Tables
- `rooms.question_seconds`: question time chosen by the host (default 20 seconds).

3. Security
- RLS is enabled on every new table.
- Only `game_events` is readable by visitors (for real-time). All other tables are reachable only through functions.
- Public functions (start_game, place_bet, submit_answer, advance_game, get_game_state, set_question_seconds) validate the player's session token.
- Internal helpers (pick_round_question, settle_round, finish_game) cannot be called from the browser.
- get_game_state hides the correct answer until the reveal phase, and hides other players' bets until the reveal.

4. Scoring rules (on the server)
- Correct answer: +bet x difficulty multiplier (Easy x1, Medium x1.5, Hard x2, Insane x3).
- Wrong answer or timeout after betting: -bet.
- No bet (skipped or no action): no change.

5. Important notes
- Phase timers use server time (clock_timestamp), so every device follows the same deadline.
- Any player's device may request advance_game; the server only moves the phase when its condition is met, and the row lock prevents double transitions.
- If fewer than 2 players remain, the game finishes.
*/

ALTER TABLE rooms ADD COLUMN IF NOT EXISTS question_seconds integer NOT NULL DEFAULT 20;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rooms_question_seconds_range') THEN
    ALTER TABLE rooms ADD CONSTRAINT rooms_question_seconds_range CHECK (question_seconds BETWEEN 10 AND 60);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text NOT NULL CHECK (category IN ('general', 'football', 'movies', 'science', 'geography', 'history', 'math', 'puzzles', 'visual', 'speed', 'funny', 'crazy')),
  difficulty text NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard', 'insane')),
  kind text NOT NULL CHECK (kind IN ('multiple_choice', 'true_false', 'image', 'speed', 'riddle')),
  language text NOT NULL DEFAULT 'ar' CHECK (language IN ('ar', 'en')),
  prompt text NOT NULL UNIQUE,
  options jsonb NOT NULL CHECK (jsonb_typeof(options) = 'array' AND jsonb_array_length(options) BETWEEN 2 AND 4),
  answer_index integer NOT NULL,
  image_url text,
  time_limit integer CHECK (time_limit IS NULL OR time_limit BETWEEN 3 AND 60),
  is_active boolean NOT NULL DEFAULT true,
  CHECK (answer_index >= 0 AND answer_index < jsonb_array_length(options))
);

CREATE INDEX IF NOT EXISTS questions_category_difficulty_idx ON questions (category, difficulty) WHERE is_active;

CREATE TABLE IF NOT EXISTS games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL UNIQUE REFERENCES rooms(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'finished')),
  phase text NOT NULL DEFAULT 'betting' CHECK (phase IN ('betting', 'question', 'reveal', 'finished')),
  round_number integer NOT NULL DEFAULT 1 CHECK (round_number BETWEEN 1 AND 10),
  total_rounds integer NOT NULL DEFAULT 10,
  question_seconds integer NOT NULL CHECK (question_seconds BETWEEN 10 AND 60),
  phase_ends_at timestamptz NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz
);

CREATE TABLE IF NOT EXISTS game_players (
  game_id uuid NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  balance integer NOT NULL DEFAULT 1000 CHECK (balance >= 0),
  correct_count integer NOT NULL DEFAULT 0,
  wrong_count integer NOT NULL DEFAULT 0,
  timeout_count integer NOT NULL DEFAULT 0,
  PRIMARY KEY (game_id, player_id)
);

CREATE TABLE IF NOT EXISTS game_rounds (
  game_id uuid NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  round_number integer NOT NULL CHECK (round_number BETWEEN 1 AND 10),
  question_id uuid NOT NULL REFERENCES questions(id),
  category text NOT NULL,
  difficulty text NOT NULL,
  kind text NOT NULL,
  PRIMARY KEY (game_id, round_number),
  UNIQUE (game_id, question_id)
);

CREATE TABLE IF NOT EXISTS round_actions (
  game_id uuid NOT NULL,
  round_number integer NOT NULL,
  player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  bet integer NOT NULL CHECK (bet IN (0, 100, 200, 300, 500, 700, 1000)),
  choice integer CHECK (choice IS NULL OR choice >= 0),
  is_correct boolean NOT NULL DEFAULT false,
  delta integer NOT NULL DEFAULT 0,
  answered_at timestamptz,
  PRIMARY KEY (game_id, round_number, player_id),
  FOREIGN KEY (game_id, round_number) REFERENCES game_rounds(game_id, round_number) ON DELETE CASCADE,
  FOREIGN KEY (game_id, player_id) REFERENCES game_players(game_id, player_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS game_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_id uuid NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('phase', 'bet', 'answer')),
  player_id uuid,
  round_number integer,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS game_events_game_idx ON game_events (game_id, id);

ALTER TABLE questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE games ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE round_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_events ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON game_events TO anon, authenticated;

DROP POLICY IF EXISTS "public_select_game_events" ON game_events;
CREATE POLICY "public_select_game_events" ON game_events FOR SELECT
  TO anon, authenticated USING (true);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'game_events') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE game_events;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION pick_round_question(p_game_id uuid, p_round integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_band text[];
  v_question questions%ROWTYPE;
BEGIN
  IF p_round <= 3 THEN
    v_band := ARRAY['easy', 'medium'];
  ELSIF p_round <= 7 THEN
    v_band := ARRAY['medium', 'hard'];
  ELSE
    v_band := ARRAY['hard', 'insane'];
  END IF;

  SELECT q.* INTO v_question
  FROM questions q
  WHERE q.is_active
    AND q.difficulty = ANY(v_band)
    AND NOT EXISTS (SELECT 1 FROM game_rounds gr WHERE gr.game_id = p_game_id AND gr.question_id = q.id)
    AND NOT EXISTS (SELECT 1 FROM game_rounds gr WHERE gr.game_id = p_game_id AND gr.category = q.category)
  ORDER BY random()
  LIMIT 1;

  IF NOT FOUND THEN
    SELECT q.* INTO v_question
    FROM questions q
    WHERE q.is_active
      AND NOT EXISTS (SELECT 1 FROM game_rounds gr WHERE gr.game_id = p_game_id AND gr.question_id = q.id)
      AND NOT EXISTS (SELECT 1 FROM game_rounds gr WHERE gr.game_id = p_game_id AND gr.category = q.category)
    ORDER BY random()
    LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    SELECT q.* INTO v_question
    FROM questions q
    WHERE q.is_active
      AND NOT EXISTS (SELECT 1 FROM game_rounds gr WHERE gr.game_id = p_game_id AND gr.question_id = q.id)
    ORDER BY random()
    LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'question_pool_exhausted';
  END IF;

  INSERT INTO game_rounds (game_id, round_number, question_id, category, difficulty, kind)
  VALUES (p_game_id, p_round, v_question.id, v_question.category, v_question.difficulty, v_question.kind);
END $$;

CREATE OR REPLACE FUNCTION settle_round(p_game_id uuid, p_round integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_question questions%ROWTYPE;
  v_multiplier_x2 integer;
BEGIN
  SELECT q.* INTO v_question
  FROM game_rounds gr
  JOIN questions q ON q.id = gr.question_id
  WHERE gr.game_id = p_game_id AND gr.round_number = p_round;

  v_multiplier_x2 := CASE v_question.difficulty
    WHEN 'easy' THEN 2
    WHEN 'medium' THEN 3
    WHEN 'hard' THEN 4
    ELSE 6
  END;

  UPDATE round_actions ra SET
    is_correct = COALESCE(ra.bet > 0 AND ra.choice = v_question.answer_index, false),
    delta = CASE
      WHEN ra.bet = 0 THEN 0
      WHEN ra.choice = v_question.answer_index THEN ra.bet * v_multiplier_x2 / 2
      ELSE -ra.bet
    END
  WHERE ra.game_id = p_game_id AND ra.round_number = p_round;

  UPDATE game_players gp SET
    balance = gp.balance + ra.delta,
    correct_count = gp.correct_count + CASE WHEN ra.is_correct THEN 1 ELSE 0 END,
    wrong_count = gp.wrong_count + CASE WHEN ra.bet > 0 AND ra.choice IS NOT NULL AND NOT ra.is_correct THEN 1 ELSE 0 END,
    timeout_count = gp.timeout_count + CASE WHEN ra.bet > 0 AND ra.choice IS NULL THEN 1 ELSE 0 END
  FROM round_actions ra
  WHERE ra.game_id = gp.game_id
    AND ra.player_id = gp.player_id
    AND ra.game_id = p_game_id
    AND ra.round_number = p_round;

  UPDATE games SET phase = 'reveal', phase_ends_at = clock_timestamp() + interval '10 seconds'
  WHERE id = p_game_id;

  INSERT INTO game_events (game_id, kind, round_number) VALUES (p_game_id, 'phase', p_round);
END $$;

CREATE OR REPLACE FUNCTION finish_game(p_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_id uuid;
BEGIN
  UPDATE games SET status = 'finished', phase = 'finished', finished_at = clock_timestamp(), phase_ends_at = clock_timestamp()
  WHERE id = p_game_id
  RETURNING room_id INTO v_room_id;

  UPDATE rooms SET status = 'finished' WHERE id = v_room_id;

  INSERT INTO game_events (game_id, kind) VALUES (p_game_id, 'phase');
END $$;

CREATE OR REPLACE FUNCTION start_game(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_room rooms%ROWTYPE;
  v_game_id uuid;
  v_members integer;
BEGIN
  SELECT p.* INTO v_player
  FROM player_sessions s
  JOIN players p ON p.id = s.player_id
  WHERE s.token = p_token;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found';
  END IF;
  IF NOT v_player.is_host THEN
    RAISE EXCEPTION 'not_host';
  END IF;

  SELECT * INTO v_room FROM rooms WHERE id = v_player.room_id FOR UPDATE;
  IF v_room.status <> 'lobby' THEN
    RAISE EXCEPTION 'room_already_started';
  END IF;

  SELECT count(*) INTO v_members FROM players WHERE room_id = v_room.id;
  IF v_members < 2 THEN
    RAISE EXCEPTION 'not_enough_players';
  END IF;

  INSERT INTO games (room_id, question_seconds, phase_ends_at)
  VALUES (v_room.id, v_room.question_seconds, clock_timestamp() + interval '15 seconds')
  RETURNING id INTO v_game_id;

  INSERT INTO game_players (game_id, player_id)
  SELECT v_game_id, p.id FROM players p WHERE p.room_id = v_room.id;

  UPDATE rooms SET status = 'playing' WHERE id = v_room.id;

  PERFORM pick_round_question(v_game_id, 1);

  INSERT INTO game_events (game_id, kind, round_number) VALUES (v_game_id, 'phase', 1);
END $$;

CREATE OR REPLACE FUNCTION set_question_seconds(p_token uuid, p_seconds integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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
  IF NOT v_player.is_host THEN
    RAISE EXCEPTION 'not_host';
  END IF;
  IF p_seconds IS NULL OR p_seconds NOT BETWEEN 10 AND 60 THEN
    RAISE EXCEPTION 'invalid_question_seconds';
  END IF;

  UPDATE rooms SET question_seconds = p_seconds
  WHERE id = v_player.room_id AND status = 'lobby';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'room_already_started';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION place_bet(p_token uuid, p_amount integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_game games%ROWTYPE;
  v_balance integer;
BEGIN
  SELECT p.* INTO v_player
  FROM player_sessions s
  JOIN players p ON p.id = s.player_id
  WHERE s.token = p_token;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found';
  END IF;

  SELECT * INTO v_game FROM games WHERE room_id = v_player.room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status <> 'active' THEN
    RAISE EXCEPTION 'no_active_game';
  END IF;
  IF v_game.phase <> 'betting' OR clock_timestamp() >= v_game.phase_ends_at THEN
    RAISE EXCEPTION 'betting_closed';
  END IF;
  IF p_amount IS NULL OR p_amount NOT IN (0, 100, 200, 300, 500, 700, 1000) THEN
    RAISE EXCEPTION 'invalid_bet';
  END IF;

  SELECT gp.balance INTO v_balance
  FROM game_players gp
  WHERE gp.game_id = v_game.id AND gp.player_id = v_player.id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_in_game';
  END IF;
  IF p_amount > v_balance THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  IF EXISTS (
    SELECT 1 FROM round_actions ra
    WHERE ra.game_id = v_game.id AND ra.round_number = v_game.round_number AND ra.player_id = v_player.id
  ) THEN
    RAISE EXCEPTION 'bet_already_placed';
  END IF;

  INSERT INTO round_actions (game_id, round_number, player_id, bet)
  VALUES (v_game.id, v_game.round_number, v_player.id, p_amount);

  INSERT INTO game_events (game_id, kind, player_id, round_number)
  VALUES (v_game.id, 'bet', v_player.id, v_game.round_number);
END $$;

CREATE OR REPLACE FUNCTION submit_answer(p_token uuid, p_choice integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_game games%ROWTYPE;
  v_bet integer;
  v_choice integer;
  v_options_count integer;
BEGIN
  SELECT p.* INTO v_player
  FROM player_sessions s
  JOIN players p ON p.id = s.player_id
  WHERE s.token = p_token;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found';
  END IF;

  SELECT * INTO v_game FROM games WHERE room_id = v_player.room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status <> 'active' THEN
    RAISE EXCEPTION 'no_active_game';
  END IF;
  IF v_game.phase <> 'question' OR clock_timestamp() >= v_game.phase_ends_at THEN
    RAISE EXCEPTION 'question_closed';
  END IF;

  SELECT ra.bet, ra.choice INTO v_bet, v_choice
  FROM round_actions ra
  WHERE ra.game_id = v_game.id AND ra.round_number = v_game.round_number AND ra.player_id = v_player.id
  FOR UPDATE;
  IF NOT FOUND OR v_bet = 0 THEN
    RAISE EXCEPTION 'not_betting';
  END IF;

  SELECT jsonb_array_length(q.options) INTO v_options_count
  FROM game_rounds gr
  JOIN questions q ON q.id = gr.question_id
  WHERE gr.game_id = v_game.id AND gr.round_number = v_game.round_number;

  IF p_choice IS NULL OR p_choice < 0 OR p_choice >= v_options_count THEN
    RAISE EXCEPTION 'invalid_choice';
  END IF;
  IF v_choice IS NOT NULL THEN
    RAISE EXCEPTION 'already_answered';
  END IF;

  UPDATE round_actions SET choice = p_choice, answered_at = clock_timestamp()
  WHERE game_id = v_game.id AND round_number = v_game.round_number AND player_id = v_player.id;

  INSERT INTO game_events (game_id, kind, player_id, round_number)
  VALUES (v_game.id, 'answer', v_player.id, v_game.round_number);
END $$;

CREATE OR REPLACE FUNCTION advance_game(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_game games%ROWTYPE;
  v_now timestamptz := clock_timestamp();
  v_members integer;
  v_locked integer;
  v_time_limit integer;
  v_has_bettors boolean;
  v_pending_answers boolean;
BEGIN
  SELECT p.* INTO v_player
  FROM player_sessions s
  JOIN players p ON p.id = s.player_id
  WHERE s.token = p_token;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found';
  END IF;

  SELECT * INTO v_game FROM games WHERE room_id = v_player.room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status = 'finished' THEN
    RETURN;
  END IF;

  SELECT count(*) INTO v_members FROM players WHERE room_id = v_game.room_id;
  IF v_members < 2 THEN
    PERFORM finish_game(v_game.id);
    RETURN;
  END IF;

  IF v_game.phase = 'betting' THEN
    SELECT count(*) INTO v_locked
    FROM round_actions
    WHERE game_id = v_game.id AND round_number = v_game.round_number;

    IF v_now < v_game.phase_ends_at AND v_locked < v_members THEN
      RETURN;
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM round_actions
      WHERE game_id = v_game.id AND round_number = v_game.round_number AND bet > 0
    ) INTO v_has_bettors;

    IF v_has_bettors THEN
      SELECT q.time_limit INTO v_time_limit
      FROM game_rounds gr
      JOIN questions q ON q.id = gr.question_id
      WHERE gr.game_id = v_game.id AND gr.round_number = v_game.round_number;

      UPDATE games SET phase = 'question',
        phase_ends_at = v_now + make_interval(secs => COALESCE(v_time_limit, v_game.question_seconds))
      WHERE id = v_game.id;

      INSERT INTO game_events (game_id, kind, round_number) VALUES (v_game.id, 'phase', v_game.round_number);
    ELSE
      PERFORM settle_round(v_game.id, v_game.round_number);
    END IF;

  ELSIF v_game.phase = 'question' THEN
    SELECT EXISTS (
      SELECT 1 FROM round_actions
      WHERE game_id = v_game.id AND round_number = v_game.round_number AND bet > 0 AND choice IS NULL
    ) INTO v_pending_answers;

    IF v_now < v_game.phase_ends_at AND v_pending_answers THEN
      RETURN;
    END IF;

    PERFORM settle_round(v_game.id, v_game.round_number);

  ELSIF v_game.phase = 'reveal' THEN
    IF v_now < v_game.phase_ends_at THEN
      RETURN;
    END IF;

    IF v_game.round_number < v_game.total_rounds THEN
      UPDATE games SET round_number = round_number + 1, phase = 'betting',
        phase_ends_at = v_now + interval '15 seconds'
      WHERE id = v_game.id;

      PERFORM pick_round_question(v_game.id, v_game.round_number + 1);

      INSERT INTO game_events (game_id, kind, round_number)
      VALUES (v_game.id, 'phase', v_game.round_number + 1);
    ELSE
      PERFORM finish_game(v_game.id);
    END IF;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION get_game_state(p_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_room rooms%ROWTYPE;
  v_game games%ROWTYPE;
  v_question questions%ROWTYPE;
  v_my_bet integer;
  v_my_choice integer;
  v_game_json jsonb := NULL;
  v_question_json jsonb := NULL;
  v_reveal_json jsonb := NULL;
  v_players_json jsonb := '[]'::jsonb;
BEGIN
  SELECT p.* INTO v_player
  FROM player_sessions s
  JOIN players p ON p.id = s.player_id
  WHERE s.token = p_token;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found';
  END IF;

  SELECT * INTO v_room FROM rooms WHERE id = v_player.room_id;

  SELECT * INTO v_game FROM games WHERE room_id = v_room.id;
  IF FOUND THEN
    SELECT q.* INTO v_question
    FROM game_rounds gr
    JOIN questions q ON q.id = gr.question_id
    WHERE gr.game_id = v_game.id AND gr.round_number = v_game.round_number;

    SELECT ra.bet, ra.choice INTO v_my_bet, v_my_choice
    FROM round_actions ra
    WHERE ra.game_id = v_game.id AND ra.round_number = v_game.round_number AND ra.player_id = v_player.id;

    v_game_json := jsonb_build_object(
      'id', v_game.id,
      'status', v_game.status,
      'phase', v_game.phase,
      'round_number', v_game.round_number,
      'total_rounds', v_game.total_rounds,
      'question_seconds', v_game.question_seconds,
      'phase_ends_at', v_game.phase_ends_at
    );

    v_question_json := jsonb_build_object(
      'category', v_question.category,
      'difficulty', v_question.difficulty,
      'kind', v_question.kind,
      'prompt', CASE WHEN v_game.phase = 'betting' THEN NULL ELSE v_question.prompt END,
      'options', CASE WHEN v_game.phase = 'betting' THEN NULL ELSE v_question.options END,
      'image_url', CASE WHEN v_game.phase = 'betting' THEN NULL ELSE v_question.image_url END,
      'time_limit', v_question.time_limit
    );

    IF v_game.phase IN ('reveal', 'finished') THEN
      v_reveal_json := jsonb_build_object(
        'correct_index', v_question.answer_index,
        'results', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'player_id', ra.player_id,
            'bet', ra.bet,
            'choice', ra.choice,
            'is_correct', ra.is_correct,
            'delta', ra.delta
          )), '[]'::jsonb)
          FROM round_actions ra
          WHERE ra.game_id = v_game.id AND ra.round_number = v_game.round_number
        )
      );
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'player_id', p.id,
      'name', p.name,
      'avatar', p.avatar,
      'is_host', p.is_host,
      'balance', gp.balance,
      'correct_count', gp.correct_count,
      'wrong_count', gp.wrong_count,
      'timeout_count', gp.timeout_count,
      'locked', ra.player_id IS NOT NULL,
      'answered', ra.choice IS NOT NULL,
      'wagered', CASE WHEN v_game.phase = 'betting' THEN NULL ELSE COALESCE(ra.bet > 0, false) END,
      'is_me', p.id = v_player.id
    ) ORDER BY gp.balance DESC, p.joined_at), '[]'::jsonb)
    INTO v_players_json
    FROM game_players gp
    JOIN players p ON p.id = gp.player_id
    LEFT JOIN round_actions ra
      ON ra.game_id = gp.game_id AND ra.player_id = gp.player_id AND ra.round_number = v_game.round_number
    WHERE gp.game_id = v_game.id;
  END IF;

  RETURN jsonb_build_object(
    'server_now', clock_timestamp(),
    'me', jsonb_build_object('player_id', v_player.id, 'bet', v_my_bet, 'choice', v_my_choice),
    'room', jsonb_build_object(
      'code', v_room.code,
      'status', v_room.status,
      'max_players', v_room.max_players,
      'game_mode', v_room.game_mode,
      'question_seconds', v_room.question_seconds
    ),
    'game', v_game_json,
    'question', v_question_json,
    'reveal', v_reveal_json,
    'players', v_players_json
  );
END $$;

REVOKE EXECUTE ON FUNCTION pick_round_question(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION settle_round(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION finish_game(uuid) FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION start_game(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION set_question_seconds(uuid, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION place_bet(uuid, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION submit_answer(uuid, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION advance_game(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_game_state(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION start_game(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION set_question_seconds(uuid, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION place_bet(uuid, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION submit_answer(uuid, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION advance_game(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_game_state(uuid) TO anon, authenticated;
