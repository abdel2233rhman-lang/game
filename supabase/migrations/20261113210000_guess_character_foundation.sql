/*
# Guess The Character (خمن الشخصية) - foundation tables

Plain-English summary
This migration prepares the database for the new "Guess The Character" game inside RISK IT. It reuses the existing rooms, players and player_sessions tables (no new room system) and does not change how RISK IT or BUS COMPLETE work. No game logic is added here (functions are in the next migration).

1. Changes to existing tables
- rooms.game_type: the allowed values now also include 'guess_character'. (The column is created if it does not exist yet; existing rooms keep their value.)
- The existing guard that stops a RISK IT game from starting in a room of another game type is re-declared (safe to re-run).

2. New tables
- characters: the character bank (Arabic name, optional English name, category, image path, a few yes/no facts used to answer in-game questions, active flag). Holds the answer, so it is private to the server and admins.
- character_aliases: extra accepted spellings / nicknames for a character.
- character_hints: ordered hints (position 1..6) for a character. Editable from the admin dashboard.
- character_games: one game per room (mode, settings, phase, deadline).
- character_rounds: the character picked for each round. A snapshot of the name, accepted answers, hints and facts is stored here, so editing the bank during a match cannot change a round in progress.
- character_guesses: every guess. A player can have only one correct guess per round, and the same wrong guess cannot be sent twice.
- character_questions: yes/no questions asked during a round (public answers).
- game_scores: running score per player per room and game type (shared with the future Guess The Song game).
- character_presence: last-seen time per player, used for host hand-over.
- character_events: public, non-secret event log used only to trigger real-time refreshes.

3. Security
- RLS is enabled on every new table.
- Only character_events is readable by visitors (it holds no answers and no names).
- characters, character_aliases and character_hints can be read and edited only by allow-listed admins (the same bus_admins allow-list used by BUS COMPLETE: one admin list for the whole platform).
- Everything else is reachable only through server functions that check the player's session token.
- Storage bucket character-images: public read (images are shown to players), upload / replace / delete only for admins. Files are stored under random names so the file name never reveals the answer.

4. Important notes
- Safe to re-run: every statement uses IF NOT EXISTS or DROP ... IF EXISTS before CREATE.
*/

-- 1. Room type -------------------------------------------------------------
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS game_type text NOT NULL DEFAULT 'risk_it';
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_game_type_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_game_type_check
  CHECK (game_type IN ('risk_it', 'bus_complete', 'guess_character'));

CREATE OR REPLACE FUNCTION public.guard_risk_it_game_room()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM rooms WHERE rooms.id = NEW.room_id AND rooms.game_type <> 'risk_it') THEN
    RAISE EXCEPTION 'wrong_game_type';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.guard_risk_it_game_room() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS games_guard_game_type ON games;
CREATE TRIGGER games_guard_game_type
  BEFORE INSERT ON games
  FOR EACH ROW EXECUTE FUNCTION public.guard_risk_it_game_room();

-- 2. Admin allow-list (shared with BUS COMPLETE) ---------------------------
CREATE TABLE IF NOT EXISTS bus_admins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE bus_admins ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON bus_admins TO authenticated;
DROP POLICY IF EXISTS "bus_admins_select_own" ON bus_admins;
CREATE POLICY "bus_admins_select_own" ON bus_admins FOR SELECT
  TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.game_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM bus_admins WHERE bus_admins.user_id = auth.uid())
$$;
REVOKE EXECUTE ON FUNCTION public.game_is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.game_is_admin() TO authenticated;

-- 3. Character bank ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS characters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name_ar text NOT NULL CHECK (char_length(btrim(name_ar)) BETWEEN 1 AND 80),
  name_en text CHECK (name_en IS NULL OR char_length(btrim(name_en)) BETWEEN 1 AND 80),
  category text NOT NULL CHECK (category IN (
    'football', 'arab_artists', 'world_celebrities', 'actors', 'cartoon', 'historical', 'games_movies'
  )),
  image_path text CHECK (image_path IS NULL OR char_length(image_path) <= 200),
  is_male boolean,
  is_alive boolean,
  is_egyptian boolean,
  is_arab boolean,
  is_real boolean,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS characters_name_ar_unique ON characters (lower(btrim(name_ar)));
CREATE INDEX IF NOT EXISTS characters_category_idx ON characters (category) WHERE is_active;

CREATE TABLE IF NOT EXISTS character_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  character_id uuid NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  alias_text text NOT NULL CHECK (char_length(btrim(alias_text)) BETWEEN 1 AND 80)
);
CREATE UNIQUE INDEX IF NOT EXISTS character_aliases_unique ON character_aliases (character_id, lower(btrim(alias_text)));

CREATE TABLE IF NOT EXISTS character_hints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  character_id uuid NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  position integer NOT NULL CHECK (position BETWEEN 1 AND 6),
  text_ar text NOT NULL CHECK (char_length(btrim(text_ar)) BETWEEN 1 AND 160),
  UNIQUE (character_id, position)
);

-- 4. Game tables -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS character_games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL UNIQUE REFERENCES rooms(id) ON DELETE CASCADE,
  mode text NOT NULL DEFAULT 'classic' CHECK (mode IN ('classic', 'mystery', 'progressive', 'fast')),
  phase text NOT NULL DEFAULT 'setup' CHECK (phase IN ('setup', 'countdown', 'round', 'reveal', 'finished')),
  total_rounds integer NOT NULL DEFAULT 5 CHECK (total_rounds BETWEEN 3 AND 10),
  round_seconds integer NOT NULL DEFAULT 45 CHECK (round_seconds BETWEEN 20 AND 90),
  questions_per_player integer NOT NULL DEFAULT 3 CHECK (questions_per_player BETWEEN 0 AND 5),
  categories text[] NOT NULL DEFAULT '{}',
  current_round integer NOT NULL DEFAULT 0 CHECK (current_round BETWEEN 0 AND 10),
  phase_ends_at timestamptz,
  used_character_ids uuid[] NOT NULL DEFAULT '{}',
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS character_rounds (
  game_id uuid NOT NULL REFERENCES character_games(id) ON DELETE CASCADE,
  round_number integer NOT NULL CHECK (round_number BETWEEN 1 AND 10),
  character_id uuid REFERENCES characters(id) ON DELETE SET NULL,
  category text NOT NULL,
  name_ar text NOT NULL,
  image_path text,
  hints jsonb NOT NULL,
  answers text[] NOT NULL,
  facts jsonb NOT NULL,
  started_at timestamptz,
  ended_at timestamptz,
  end_reason text CHECK (end_reason IN ('timer', 'all_guessed', 'players_left')),
  PRIMARY KEY (game_id, round_number)
);
CREATE UNIQUE INDEX IF NOT EXISTS character_rounds_no_repeat
  ON character_rounds (game_id, character_id) WHERE character_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS character_guesses (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_id uuid NOT NULL,
  round_number integer NOT NULL,
  player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  guess_text text NOT NULL,
  normalized text NOT NULL,
  is_correct boolean NOT NULL DEFAULT false,
  hints_visible integer,
  base_points integer NOT NULL DEFAULT 0,
  speed_bonus integer NOT NULL DEFAULT 0,
  elapsed_ms integer,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (game_id, round_number) REFERENCES character_rounds(game_id, round_number) ON DELETE CASCADE
);
-- No double scoring: one correct guess per player per round; no repeated identical guess.
CREATE UNIQUE INDEX IF NOT EXISTS character_guesses_one_correct
  ON character_guesses (game_id, round_number, player_id) WHERE is_correct;
CREATE UNIQUE INDEX IF NOT EXISTS character_guesses_no_duplicate
  ON character_guesses (game_id, round_number, player_id, normalized);

CREATE TABLE IF NOT EXISTS character_questions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_id uuid NOT NULL,
  round_number integer NOT NULL,
  player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  question_key text NOT NULL CHECK (question_key IN ('is_male', 'is_alive', 'is_egyptian', 'is_arab', 'is_real')),
  answer text NOT NULL CHECK (answer IN ('yes', 'no', 'na')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (game_id, round_number) REFERENCES character_rounds(game_id, round_number) ON DELETE CASCADE,
  UNIQUE (game_id, round_number, question_key)
);

CREATE TABLE IF NOT EXISTS game_scores (
  room_id uuid NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  game_type text NOT NULL CHECK (game_type IN ('guess_character', 'guess_song')),
  player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  points integer NOT NULL DEFAULT 0,
  correct_count integer NOT NULL DEFAULT 0,
  fastest_count integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id, game_type, player_id)
);

CREATE TABLE IF NOT EXISTS character_presence (
  player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  seen_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS character_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  room_id uuid NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('phase', 'guess', 'question', 'settings', 'host')),
  player_id uuid,
  round_number integer,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS character_events_room_idx ON character_events (room_id, id);

-- 5. Row level security ------------------------------------------------------
ALTER TABLE characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE character_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE character_hints ENABLE ROW LEVEL SECURITY;
ALTER TABLE character_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE character_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE character_guesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE character_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE character_presence ENABLE ROW LEVEL SECURITY;
ALTER TABLE character_events ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON character_events TO anon, authenticated;
DROP POLICY IF EXISTS "public_select_character_events" ON character_events;
CREATE POLICY "public_select_character_events" ON character_events FOR SELECT
  TO anon, authenticated USING (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON characters, character_aliases, character_hints TO authenticated;
DROP POLICY IF EXISTS "characters_admin_all" ON characters;
CREATE POLICY "characters_admin_all" ON characters FOR ALL
  TO authenticated USING (public.game_is_admin()) WITH CHECK (public.game_is_admin());
DROP POLICY IF EXISTS "character_aliases_admin_all" ON character_aliases;
CREATE POLICY "character_aliases_admin_all" ON character_aliases FOR ALL
  TO authenticated USING (public.game_is_admin()) WITH CHECK (public.game_is_admin());
DROP POLICY IF EXISTS "character_hints_admin_all" ON character_hints;
CREATE POLICY "character_hints_admin_all" ON character_hints FOR ALL
  TO authenticated USING (public.game_is_admin()) WITH CHECK (public.game_is_admin());

-- 6. Realtime ----------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'character_events'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE character_events;
  END IF;
END $$;

-- 7. Image storage -------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('character-images', 'character-images', true, 2097152, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "character_images_admin_insert" ON storage.objects;
CREATE POLICY "character_images_admin_insert" ON storage.objects FOR INSERT
  TO authenticated WITH CHECK (bucket_id = 'character-images' AND public.game_is_admin());
DROP POLICY IF EXISTS "character_images_admin_update" ON storage.objects;
CREATE POLICY "character_images_admin_update" ON storage.objects FOR UPDATE
  TO authenticated USING (bucket_id = 'character-images' AND public.game_is_admin());
DROP POLICY IF EXISTS "character_images_admin_delete" ON storage.objects;
CREATE POLICY "character_images_admin_delete" ON storage.objects FOR DELETE
  TO authenticated USING (bucket_id = 'character-images' AND public.game_is_admin());
