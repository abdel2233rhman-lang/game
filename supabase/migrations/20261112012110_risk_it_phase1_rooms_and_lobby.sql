/*
# RISK IT - Phase 1: rooms, players and lobby functions

1. New Tables
- `rooms`: one row per game room. Holds the 6-character room code, status (lobby/playing/paused/finished), max players (2-8) and game mode (solo/team).
- `players`: one row per player in a room. Holds display name, avatar key, whether the player is the host, and join time.
- `player_sessions`: private secret token per player. Used to prove who you are when acting in a room. Nobody can read this table from the browser.

2. Security
- Row Level Security is enabled on all three tables.
- `rooms` and `players` are readable by visitors (needed for the live lobby list). Nobody can insert, update or delete them directly.
- `player_sessions` has no grants and no policies, so the browser can never read tokens.
- All changes go through server functions (RPC) that validate input and check the session token:
  create_room, join_room, update_room_settings, leave_room, resume_session.
- Internal helpers are not callable from the browser.

3. Realtime
- `rooms` and `players` are added to the realtime publication so every player sees lobby changes instantly.
- REPLICA IDENTITY FULL lets realtime deliver delete events with their room information.

4. Important notes
- Room codes use a set of unambiguous characters (no 0/O/1/I).
- The host is always the earliest joiner when the host leaves; an empty room is removed automatically.
- Only one host per room is enforced by a unique index.
*/

CREATE TABLE IF NOT EXISTS rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'lobby' CHECK (status IN ('lobby', 'playing', 'paused', 'finished')),
  max_players integer NOT NULL DEFAULT 4 CHECK (max_players BETWEEN 2 AND 8),
  game_mode text NOT NULL DEFAULT 'solo' CHECK (game_mode IN ('solo', 'team')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 16),
  avatar text NOT NULL CHECK (avatar IN ('crown', 'rocket', 'zap', 'flame', 'ghost', 'bot', 'target', 'gem')),
  is_host boolean NOT NULL DEFAULT false,
  joined_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS players_room_id_idx ON players (room_id);
CREATE UNIQUE INDEX IF NOT EXISTS players_unique_name_per_room ON players (room_id, lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS players_one_host_per_room ON players (room_id) WHERE is_host;

CREATE TABLE IF NOT EXISTS player_sessions (
  player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  token uuid NOT NULL UNIQUE DEFAULT gen_random_uuid()
);

ALTER TABLE rooms REPLICA IDENTITY FULL;
ALTER TABLE players REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'rooms') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE rooms;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'players') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE players;
  END IF;
END $$;

ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_sessions ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON rooms, players TO anon, authenticated;

DROP POLICY IF EXISTS "public_select_rooms" ON rooms;
CREATE POLICY "public_select_rooms" ON rooms FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "public_select_players" ON players;
CREATE POLICY "public_select_players" ON players FOR SELECT
  TO anon, authenticated USING (true);

CREATE OR REPLACE FUNCTION generate_room_code()
RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  v_attempts integer := 0;
BEGIN
  LOOP
    v_code := '';
    FOR i IN 1..6 LOOP
      v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::integer, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM rooms WHERE rooms.code = v_code);
    v_attempts := v_attempts + 1;
    IF v_attempts > 20 THEN
      RAISE EXCEPTION 'code_generation_failed';
    END IF;
  END LOOP;
  RETURN v_code;
END $$;

CREATE OR REPLACE FUNCTION assert_player_input(p_name text, p_avatar text)
RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_name text := btrim(coalesce(p_name, ''));
BEGIN
  IF char_length(v_name) < 1 OR char_length(v_name) > 16 THEN
    RAISE EXCEPTION 'invalid_name';
  END IF;
  IF p_avatar IS NULL OR p_avatar NOT IN ('crown', 'rocket', 'zap', 'flame', 'ghost', 'bot', 'target', 'gem') THEN
    RAISE EXCEPTION 'invalid_avatar';
  END IF;
  RETURN v_name;
END $$;

CREATE OR REPLACE FUNCTION assert_room_settings(p_max_players integer, p_game_mode text)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF p_max_players IS NULL OR p_max_players NOT BETWEEN 2 AND 8 THEN
    RAISE EXCEPTION 'invalid_max_players';
  END IF;
  IF p_game_mode IS NULL OR p_game_mode NOT IN ('solo', 'team') THEN
    RAISE EXCEPTION 'invalid_game_mode';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION create_room(p_name text, p_avatar text, p_max_players integer, p_game_mode text)
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
  INSERT INTO rooms (code, max_players, game_mode)
  VALUES (v_code, p_max_players, p_game_mode)
  RETURNING id INTO v_room_id;

  INSERT INTO players (room_id, name, avatar, is_host)
  VALUES (v_room_id, v_name, p_avatar, true)
  RETURNING id INTO v_player_id;

  INSERT INTO player_sessions (player_id)
  VALUES (v_player_id)
  RETURNING token INTO v_token;

  RETURN jsonb_build_object(
    'room_id', v_room_id,
    'player_id', v_player_id,
    'token', v_token,
    'code', v_code
  );
END $$;

CREATE OR REPLACE FUNCTION join_room(p_code text, p_name text, p_avatar text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name text;
  v_room rooms%ROWTYPE;
  v_count integer;
  v_player_id uuid;
  v_token uuid;
BEGIN
  v_name := assert_player_input(p_name, p_avatar);

  SELECT * INTO v_room
  FROM rooms
  WHERE rooms.code = upper(btrim(coalesce(p_code, '')))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'room_not_found';
  END IF;
  IF v_room.status <> 'lobby' THEN
    RAISE EXCEPTION 'room_already_started';
  END IF;

  SELECT count(*) INTO v_count FROM players WHERE players.room_id = v_room.id;
  IF v_count >= v_room.max_players THEN
    RAISE EXCEPTION 'room_full';
  END IF;

  IF EXISTS (
    SELECT 1 FROM players
    WHERE players.room_id = v_room.id AND lower(players.name) = lower(v_name)
  ) THEN
    RAISE EXCEPTION 'name_taken';
  END IF;

  INSERT INTO players (room_id, name, avatar, is_host)
  VALUES (v_room.id, v_name, p_avatar, false)
  RETURNING id INTO v_player_id;

  INSERT INTO player_sessions (player_id)
  VALUES (v_player_id)
  RETURNING token INTO v_token;

  RETURN jsonb_build_object(
    'room_id', v_room.id,
    'player_id', v_player_id,
    'token', v_token,
    'code', v_room.code
  );
END $$;

CREATE OR REPLACE FUNCTION resume_session(p_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'room_id', r.id,
    'player_id', p.id,
    'code', r.code
  ) INTO v_result
  FROM player_sessions s
  JOIN players p ON p.id = s.player_id
  JOIN rooms r ON r.id = p.room_id
  WHERE s.token = p_token;

  RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION update_room_settings(p_token uuid, p_max_players integer, p_game_mode text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_room rooms%ROWTYPE;
  v_count integer;
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

  PERFORM assert_room_settings(p_max_players, p_game_mode);

  SELECT * INTO v_room FROM rooms WHERE rooms.id = v_player.room_id FOR UPDATE;
  IF v_room.status <> 'lobby' THEN
    RAISE EXCEPTION 'room_already_started';
  END IF;

  SELECT count(*) INTO v_count FROM players WHERE players.room_id = v_room.id;
  IF p_max_players < v_count THEN
    RAISE EXCEPTION 'max_below_players';
  END IF;

  UPDATE rooms
  SET max_players = p_max_players, game_mode = p_game_mode
  WHERE rooms.id = v_room.id;
END $$;

CREATE OR REPLACE FUNCTION leave_room(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_next_host uuid;
BEGIN
  SELECT p.* INTO v_player
  FROM player_sessions s
  JOIN players p ON p.id = s.player_id
  WHERE s.token = p_token;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  DELETE FROM players WHERE players.id = v_player.id;

  IF NOT EXISTS (SELECT 1 FROM players WHERE players.room_id = v_player.room_id) THEN
    DELETE FROM rooms WHERE rooms.id = v_player.room_id;
  ELSIF v_player.is_host THEN
    SELECT p.id INTO v_next_host
    FROM players p
    WHERE p.room_id = v_player.room_id
    ORDER BY p.joined_at, p.id
    LIMIT 1;
    UPDATE players SET is_host = true WHERE players.id = v_next_host;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION generate_room_code() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION assert_player_input(text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION assert_room_settings(integer, text) FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION create_room(text, text, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION join_room(text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION resume_session(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION update_room_settings(uuid, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION leave_room(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION create_room(text, text, integer, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION join_room(text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION resume_session(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION update_room_settings(uuid, integer, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION leave_room(uuid) TO anon, authenticated;
