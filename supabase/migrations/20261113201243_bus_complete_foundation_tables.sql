/*
# Bus Complete foundation: room type, admin allowlist, answer bank tables

Plain-English summary
This migration prepares the database for the new BUS COMPLETE game without changing how RISK IT works. It adds a room type marker, a guard that stops RISK IT games from starting in Bus Complete rooms, the admin allowlist, the answer bank (with aliases and review status), and all Bus Complete game tables with their access rules. No game logic (functions that play the game) is added here.

1. Changes to existing tables
- rooms: new column game_type (text, default 'risk_it', allowed values 'risk_it' and 'bus_complete'). Existing rows and the create_room function are unchanged; they keep 'risk_it'.
- games: a BEFORE INSERT trigger rejects a RISK IT game for any room whose game_type is not 'risk_it'.

2. New tables (all prefixed bus_)
- bus_admins: user ids (Supabase Auth) allowed to review answers. Admins are added manually by the project owner, never by the frontend.
- bus_letters: the 28 Arabic letters used for rounds (normalized form plus display form).
- bus_categories: the 25 selectable categories grouped in Football, Series & Movies, Celebrities.
- bus_answer_bank: canonical answers per category, with letter, normalized text and status (approved, pending_review, rejected). Only approved entries are used for automatic validation.
- bus_answer_aliases: alternative spellings for a bank answer.
- bus_games: one Bus Complete game per room (phase, settings, current round, timers).
- bus_game_categories: categories the host selected for the game.
- bus_teams / bus_team_members: team mode pairs (exactly two players per team, enforced by RPCs at start).
- bus_rounds / bus_round_categories: round letter, chosen categories, end reason.
- bus_sheets: one answer sheet per player (solo) or per team (team mode) per round.
- bus_answers: submitted answers per sheet and category, with match status and points.
- bus_events: non-sensitive activity feed used for realtime refresh.

3. Security
- Every new table has row level security enabled.
- Answer bank, aliases, sheets, answers, teams and games are NOT readable by anonymous or signed-in players directly. Players read game data only through a server function that checks their session token.
- bus_admins: a signed-in user can read only their own row.
- bus_categories: public read of active categories only.
- bus_letters: public read.
- bus_events: public read (contains no answers or identities), needed for realtime.
- Answer bank and aliases: readable only by allowlisted admins.
- Player tokens remain in player_sessions and are never granted to clients.

4. Important notes
- Normalization (removing diacritics, unifying alef/ya/ta-marbuta forms, ignoring punctuation and extra spaces) is done by the bus_normalize function and applied automatically by triggers.
- Functions are added in a separate migration.
- This migration is safe to re-run: every statement uses IF NOT EXISTS, or DROP ... IF EXISTS before CREATE.
*/

-- 1. Room type marker
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS game_type text NOT NULL DEFAULT 'risk_it';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.rooms'::regclass AND conname = 'rooms_game_type_check'
  ) THEN
    ALTER TABLE rooms ADD CONSTRAINT rooms_game_type_check
      CHECK (game_type IN ('risk_it', 'bus_complete'));
  END IF;
END $$;

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

-- 2. Normalization used for answer matching
CREATE OR REPLACE FUNCTION public.bus_normalize(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT btrim(regexp_replace(
    regexp_replace(
      lower(translate(
        regexp_replace(coalesce(p_text, ''), '[\u064B-\u0652\u0640]', '', 'g'),
        'أإآٱىةؤئ',
        'اااايهوي'
      )),
      '[[:punct:]،؛؟«»]', ' ', 'g'
    ),
    '\s+', ' ', 'g'
  ))
$$;

REVOKE EXECUTE ON FUNCTION public.bus_normalize(text) FROM PUBLIC, anon, authenticated;

-- 3. Admin allowlist
CREATE TABLE IF NOT EXISTS bus_admins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE bus_admins ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON bus_admins TO authenticated;

DROP POLICY IF EXISTS "bus_admins_select_own" ON bus_admins;
CREATE POLICY "bus_admins_select_own" ON bus_admins FOR SELECT
  TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.bus_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM bus_admins WHERE bus_admins.user_id = auth.uid())
$$;

REVOKE EXECUTE ON FUNCTION public.bus_is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bus_is_admin() TO authenticated;

-- 4. Letters
CREATE TABLE IF NOT EXISTS bus_letters (
  letter text PRIMARY KEY CHECK (char_length(letter) = 1),
  display text NOT NULL,
  sort_order integer NOT NULL,
  is_enabled boolean NOT NULL DEFAULT true
);

INSERT INTO bus_letters (letter, display, sort_order) VALUES
  ('ا', 'أ', 1), ('ب', 'ب', 2), ('ت', 'ت', 3), ('ث', 'ث', 4), ('ج', 'ج', 5),
  ('ح', 'ح', 6), ('خ', 'خ', 7), ('د', 'د', 8), ('ذ', 'ذ', 9), ('ر', 'ر', 10),
  ('ز', 'ز', 11), ('س', 'س', 12), ('ش', 'ش', 13), ('ص', 'ص', 14), ('ض', 'ض', 15),
  ('ط', 'ط', 16), ('ظ', 'ظ', 17), ('ع', 'ع', 18), ('غ', 'غ', 19), ('ف', 'ف', 20),
  ('ق', 'ق', 21), ('ك', 'ك', 22), ('ل', 'ل', 23), ('م', 'م', 24), ('ن', 'ن', 25),
  ('ه', 'ه', 26), ('و', 'و', 27), ('ي', 'ي', 28)
ON CONFLICT (letter) DO NOTHING;

ALTER TABLE bus_letters ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON bus_letters TO anon, authenticated;

DROP POLICY IF EXISTS "bus_letters_select" ON bus_letters;
CREATE POLICY "bus_letters_select" ON bus_letters FOR SELECT
  TO anon, authenticated USING (true);

-- 5. Categories
CREATE TABLE IF NOT EXISTS bus_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  group_key text NOT NULL CHECK (group_key IN ('football', 'series_movies', 'celebrities')),
  name_ar text NOT NULL,
  sort_order integer NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE bus_categories ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON bus_categories TO anon, authenticated;

DROP POLICY IF EXISTS "bus_categories_select_active" ON bus_categories;
CREATE POLICY "bus_categories_select_active" ON bus_categories FOR SELECT
  TO anon, authenticated USING (is_active);

-- 6. Answer bank and aliases
CREATE TABLE IF NOT EXISTS bus_answer_bank (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES bus_categories(id) ON DELETE CASCADE,
  answer_text text NOT NULL CHECK (char_length(btrim(answer_text)) BETWEEN 1 AND 80),
  normalized text NOT NULL,
  letter text NOT NULL REFERENCES bus_letters(letter),
  status text NOT NULL DEFAULT 'pending_review' CHECK (status IN ('approved', 'pending_review', 'rejected')),
  source text NOT NULL DEFAULT 'manual',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (category_id, normalized)
);

CREATE INDEX IF NOT EXISTS bus_answer_bank_lookup_idx ON bus_answer_bank (category_id, status, letter);

CREATE TABLE IF NOT EXISTS bus_answer_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  answer_id uuid NOT NULL REFERENCES bus_answer_bank(id) ON DELETE CASCADE,
  alias_text text NOT NULL CHECK (char_length(btrim(alias_text)) BETWEEN 1 AND 80),
  normalized text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (answer_id, normalized)
);

CREATE INDEX IF NOT EXISTS bus_answer_aliases_normalized_idx ON bus_answer_aliases (normalized);

CREATE OR REPLACE FUNCTION public.bus_answer_bank_prepare()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.normalized := public.bus_normalize(NEW.answer_text);
  IF NEW.normalized = '' THEN
    RAISE EXCEPTION 'invalid_answer';
  END IF;
  NEW.letter := left(NEW.normalized, 1);
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.bus_alias_prepare()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.normalized := public.bus_normalize(NEW.alias_text);
  IF NEW.normalized = '' THEN
    RAISE EXCEPTION 'invalid_alias';
  END IF;
  RETURN NEW;
END $$;

REVOKE EXECUTE ON FUNCTION public.bus_answer_bank_prepare() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bus_alias_prepare() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS bus_answer_bank_prepare_trg ON bus_answer_bank;
CREATE TRIGGER bus_answer_bank_prepare_trg
  BEFORE INSERT OR UPDATE OF answer_text ON bus_answer_bank
  FOR EACH ROW EXECUTE FUNCTION public.bus_answer_bank_prepare();

DROP TRIGGER IF EXISTS bus_alias_prepare_trg ON bus_answer_aliases;
CREATE TRIGGER bus_alias_prepare_trg
  BEFORE INSERT OR UPDATE OF alias_text ON bus_answer_aliases
  FOR EACH ROW EXECUTE FUNCTION public.bus_alias_prepare();

ALTER TABLE bus_answer_bank ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_answer_aliases ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON bus_answer_bank, bus_answer_aliases TO authenticated;

DROP POLICY IF EXISTS "bus_answer_bank_select_admin" ON bus_answer_bank;
CREATE POLICY "bus_answer_bank_select_admin" ON bus_answer_bank FOR SELECT
  TO authenticated USING (EXISTS (SELECT 1 FROM bus_admins WHERE bus_admins.user_id = auth.uid()));

DROP POLICY IF EXISTS "bus_answer_aliases_select_admin" ON bus_answer_aliases;
CREATE POLICY "bus_answer_aliases_select_admin" ON bus_answer_aliases FOR SELECT
  TO authenticated USING (EXISTS (SELECT 1 FROM bus_admins WHERE bus_admins.user_id = auth.uid()));

-- 7. Game tables (accessed only through server functions; no client grants)
CREATE TABLE IF NOT EXISTS bus_games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL UNIQUE REFERENCES rooms(id) ON DELETE CASCADE,
  phase text NOT NULL DEFAULT 'setup' CHECK (phase IN ('setup', 'round', 'results', 'finished')),
  total_rounds integer NOT NULL DEFAULT 5 CHECK (total_rounds BETWEEN 1 AND 10),
  round_seconds integer NOT NULL DEFAULT 60 CHECK (round_seconds BETWEEN 30 AND 180),
  categories_per_round integer NOT NULL DEFAULT 4 CHECK (categories_per_round BETWEEN 3 AND 6),
  current_round integer NOT NULL DEFAULT 0 CHECK (current_round BETWEEN 0 AND 10),
  round_ends_at timestamptz,
  results_ends_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bus_game_categories (
  game_id uuid NOT NULL REFERENCES bus_games(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES bus_categories(id) ON DELETE CASCADE,
  PRIMARY KEY (game_id, category_id)
);

CREATE TABLE IF NOT EXISTS bus_teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL REFERENCES bus_games(id) ON DELETE CASCADE,
  position integer NOT NULL CHECK (position BETWEEN 1 AND 4),
  name text NOT NULL,
  UNIQUE (game_id, position)
);

CREATE TABLE IF NOT EXISTS bus_team_members (
  game_id uuid NOT NULL REFERENCES bus_games(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES bus_teams(id) ON DELETE CASCADE,
  PRIMARY KEY (game_id, player_id)
);

CREATE TABLE IF NOT EXISTS bus_rounds (
  game_id uuid NOT NULL REFERENCES bus_games(id) ON DELETE CASCADE,
  round_number integer NOT NULL CHECK (round_number BETWEEN 1 AND 10),
  letter text NOT NULL REFERENCES bus_letters(letter),
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  end_reason text CHECK (end_reason IN ('timer', 'bus_complete')),
  ended_by uuid REFERENCES players(id) ON DELETE SET NULL,
  PRIMARY KEY (game_id, round_number)
);

CREATE TABLE IF NOT EXISTS bus_round_categories (
  game_id uuid NOT NULL,
  round_number integer NOT NULL,
  category_id uuid NOT NULL REFERENCES bus_categories(id) ON DELETE CASCADE,
  position integer NOT NULL CHECK (position >= 1),
  PRIMARY KEY (game_id, round_number, category_id),
  UNIQUE (game_id, round_number, position),
  FOREIGN KEY (game_id, round_number) REFERENCES bus_rounds(game_id, round_number) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS bus_sheets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL,
  round_number integer NOT NULL,
  player_id uuid REFERENCES players(id) ON DELETE CASCADE,
  team_id uuid REFERENCES bus_teams(id) ON DELETE CASCADE,
  CHECK ((player_id IS NULL) <> (team_id IS NULL)),
  FOREIGN KEY (game_id, round_number) REFERENCES bus_rounds(game_id, round_number) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS bus_sheets_player_key ON bus_sheets (game_id, round_number, player_id) WHERE player_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS bus_sheets_team_key ON bus_sheets (game_id, round_number, team_id) WHERE team_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS bus_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sheet_id uuid NOT NULL REFERENCES bus_sheets(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES bus_categories(id) ON DELETE CASCADE,
  answer_text text NOT NULL CHECK (char_length(btrim(answer_text)) BETWEEN 1 AND 60),
  normalized text NOT NULL,
  matched_answer_id uuid REFERENCES bus_answer_bank(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending_review' CHECK (status IN ('matched', 'pending_review', 'rejected')),
  points integer NOT NULL DEFAULT 0 CHECK (points >= 0),
  submitted_by uuid REFERENCES players(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (sheet_id, category_id)
);

CREATE INDEX IF NOT EXISTS bus_answers_matched_idx ON bus_answers (matched_answer_id);

CREATE TABLE IF NOT EXISTS bus_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_id uuid NOT NULL REFERENCES bus_games(id) ON DELETE CASCADE,
  round_number integer,
  kind text NOT NULL CHECK (kind IN ('game_started', 'round_started', 'answer_saved', 'round_ended', 'review_updated', 'game_finished')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS bus_events_game_idx ON bus_events (game_id, id);

ALTER TABLE bus_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_game_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_round_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_sheets ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON bus_games, bus_game_categories, bus_teams, bus_team_members, bus_rounds, bus_round_categories, bus_sheets, bus_answers FROM anon, authenticated;

GRANT SELECT ON bus_events TO anon, authenticated;

DROP POLICY IF EXISTS "bus_events_select" ON bus_events;
CREATE POLICY "bus_events_select" ON bus_events FOR SELECT
  TO anon, authenticated USING (true);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'bus_events'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE bus_events;
  END IF;
END $$;
