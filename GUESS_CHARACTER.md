# Guess The Character (خمن الشخصية) — integration notes

> للنشر والاختبار: راجع مجلد `docs/` (ابدأ بـ `docs/README_AR.md`).

## What was added (nothing existing was removed or changed in behaviour)
**Database** (`supabase/migrations/`, apply in order, all idempotent)
1. `20261113210000_guess_character_foundation.sql` — tables, RLS, realtime, `character-images` storage bucket.
2. `20261113210100_guess_character_functions.sql` — server-side game logic (RPCs).
3. `20261113210200_guess_character_seed.sql` — 45 real characters (4 factual hints + accepted spellings each). **No images are bundled.**

**Frontend**
- `src/lib/characterApi.ts`, `characterConstants.ts`, `sfx.ts`, `src/hooks/useCharacterSync.ts`
- `src/components/character/*` (lobby/settings, countdown, round, reveal, final results, live leaderboard, sound toggle)
- `src/components/admin/CharacterAdmin.tsx` — open `/?admin=characters`
- Small edits: `Lobby.tsx` (routes `guess_character` rooms to the new screens), `CreateRoomForm.tsx` (game picker), `App.tsx` (admin route), `roomApi.ts` / `types/room.ts` (game_type + error texts), `FinalResults.tsx` (exported `Confetti`).

## Same room system
Create → `create_character_room` (same `rooms` / `players` / `player_sessions`, `game_type = 'guess_character'`). Join / leave / resume / host-on-leave still use `join_room`, `leave_room`, `resume_session`.

## Rules enforced on the server
- Answer, accepted spellings and not-yet-visible hints never reach the browser; image only when the mode shows it.
- Points: 100/80/60/40/30/20 by hints visible (hints reveal evenly over the round) + speed bonus for the first correct guess (+20, Fast Guess +50). Max 3 wrong guesses per round, no repeated guess, one correct guess per player per round.
- One server clock for every phase; any device may call `char_advance`, a row lock prevents double transitions.
- Host silent for 45 s → an active player becomes host. Reconnect restores state from the stored token.
- Play again resets the same room to the lobby (same code), characters are not repeated across games when enough exist.

## Admin setup (one time)
1. Supabase → Authentication → create a user (email + password).
2. SQL editor: `insert into bus_admins (user_id) values ('<that user id>');` (the one platform-wide admin list; BUS COMPLETE uses it too).
3. Open `/?admin=characters`, sign in, upload an image for each character (only images you have rights to use).

## Tests
`python3 supabase/tests/guess_character_test.py "<postgres dsn>"` plays full matches through the public RPCs as the `anon` role (89 checks).
Not covered: real browsers / real Supabase Realtime across devices.
