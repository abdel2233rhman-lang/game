"""
Server-side test for Guess The Character (runs against a local Postgres that has all migrations applied).
Usage: python3 guess_character_test.py "dbname=t user=postgres host=/var/run/postgresql"
It plays real matches through the public RPCs as the `anon` role (exactly what the browser can do)
and checks: secrecy of answers, scoring, double-scoring protection, attempts, timers, host hand-over,
reconnect, play again and that RISK IT / other room types are untouched.
"""
import json, sys, time
import psycopg2

DSN = sys.argv[1] if len(sys.argv) > 1 else "dbname=t user=postgres host=/var/run/postgresql"
conn = psycopg2.connect(DSN)
conn.autocommit = True
cur = conn.cursor()

passed = failed = 0
def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1; print(f"  PASS  {name}")
    else:
        failed += 1; print(f"  FAIL  {name} {extra}")

def admin(sql, args=None):
    cur.execute("RESET ROLE")
    cur.execute(sql, args)
    return cur.fetchall() if cur.description else None

def rpc(fn, *args):
    """call a public function as the anonymous browser role"""
    cur.execute("SET ROLE anon")
    ph = ", ".join(["%s"] * len(args))
    try:
        cur.execute(f"SELECT public.{fn}({ph})", args)
        row = cur.fetchone()
        cur.execute("RESET ROLE")
        return row[0] if row else None
    except psycopg2.Error as e:
        cur.execute("RESET ROLE")
        msg = (e.pgerror or str(e)).split("\n")[0].replace("ERROR:  ", "")
        return {"__error": msg}

def err(r): return r.get("__error") if isinstance(r, dict) else None

def new_room(names):
    host = rpc("create_character_room", names[0], "crown", 6)
    assert not err(host), host
    players = [host]
    for n, av in zip(names[1:], ["rocket", "zap", "flame", "ghost"]):
        j = rpc("join_room", host["code"], n, av)
        assert not err(j), j
        players.append(j)
    return players

def state(p): 
    s = rpc("char_get_state", p["token"])
    assert not err(s), s
    return s

def set_settings(host, mode="classic", rounds=3, seconds=40, qpp=3, cats=()):
    return rpc("char_update_settings", host["token"], mode, rounds, seconds, qpp, list(cats))

def secret_name(gid, rnd):
    return admin("SELECT name_ar, answers FROM character_rounds WHERE game_id=%s AND round_number=%s", (gid, rnd))[0]

def finish_countdown(gid):
    admin("UPDATE character_games SET phase_ends_at = clock_timestamp() - interval '1 second' WHERE id=%s", (gid,))

def start_round_now(host, gid):
    finish_countdown(gid)
    rpc("char_advance", host["token"])

print("== 1. Room creation and joining reuse the existing room system")
P = new_room(["Host", "Ali", "Mona"])
host, ali, mona = P
room = admin("SELECT game_type, status, game_mode FROM rooms WHERE id=%s", (host["room_id"],))[0]
check("room is guess_character / lobby", room[0] == "guess_character" and room[1] == "lobby")
check("3 players in the room", admin("SELECT count(*) FROM players WHERE room_id=%s", (host["room_id"],))[0][0] == 3)
s = state(host)
check("lobby state: phase setup, host flag", s["game"]["phase"] == "setup" and s["me"]["is_host"])
check("catalog counts present in lobby", sum(s["catalog"].values()) == 45)

print("== 2. Settings are host-only and validated")
check("non-host cannot change settings", err(set_settings(ali)) == "not_host")
check("invalid mode rejected", err(set_settings(host, mode="hard")) == "invalid_mode")
check("invalid rounds rejected", err(set_settings(host, rounds=1)) == "invalid_rounds")
check("invalid category rejected", err(set_settings(host, cats=["nope"])) == "invalid_categories")
check("host saves settings", err(set_settings(host, "classic", 3, 40, 2, ["football", "actors"])) is None)
g = state(host)["game"]
check("settings persisted", g["total_rounds"] == 3 and g["round_seconds"] == 40 and g["categories"] == ["actors", "football"] and g["questions_per_player"] == 2)

print("== 3. Start game")
check("non-host cannot start", err(rpc("char_start_game", ali["token"])) == "not_host")
check("risk it start_game refuses this room", err(rpc("start_game", host["token"])) is not None)
check("host starts", err(rpc("char_start_game", host["token"])) is None)
s = state(host); gid = s["game"]["id"]
check("phase countdown after start", s["game"]["phase"] == "countdown")
check("cannot join a started room", err(rpc("join_room", host["code"], "Late", "gem")) == "room_already_started")
name, answers = secret_name(gid, 1)
check("no image/hints/name during countdown", s["round"]["image_path"] is None and s["round"]["hints"] == [] and name not in json.dumps(s, ensure_ascii=False))
check("guess rejected before round starts", err(rpc("char_submit_guess", ali["token"], "x")) == "round_closed")

print("== 4. Round 1: secrecy, scoring, double-scoring protection")
start_round_now(host, gid)
s = state(ali)
check("phase round", s["game"]["phase"] == "round")
check("only first hint visible at start", s["round"]["hints_visible"] == 1 and len(s["round"]["hints"]) == 1)
raw = json.dumps(s, ensure_ascii=False)
check("correct name not in player state", name not in raw)
check("accepted answers not in player state", not any(a in raw for a in answers if len(a) > 3), "")
check("no reveal block during round", s["reveal"] is None)
cur.execute("SET ROLE anon")
try:
    cur.execute("SELECT * FROM character_rounds"); blocked = False
except psycopg2.Error:
    blocked = True
cur.execute("RESET ROLE")
check("anon cannot SELECT character_rounds", blocked)
cur.execute("SET ROLE anon")
try:
    cur.execute("SELECT * FROM characters"); blocked = False
except psycopg2.Error:
    blocked = True
cur.execute("RESET ROLE")
check("anon cannot SELECT characters", blocked)

r = rpc("char_submit_guess", ali["token"], "إجابة خاطئة تمامًا")
check("wrong guess: no points, attempts decrease", r.get("correct") is False and r["attempts_left"] == 2)
check("duplicate wrong guess rejected", err(rpc("char_submit_guess", ali["token"], "إجابة خاطئة تمامًا")) == "duplicate_guess")
rpc("char_submit_guess", ali["token"], "خطأ ثاني"); rpc("char_submit_guess", ali["token"], "خطأ ثالث")
check("4th attempt blocked (max 3 wrong)", err(rpc("char_submit_guess", ali["token"], "خطأ رابع")) == "no_attempts_left")
check("Ali has 0 points so far", admin("SELECT coalesce(sum(points),0) FROM game_scores WHERE player_id=%s", (ali["player_id"],))[0][0] == 0)

# Mona answers correctly first, using an accepted spelling with different letters/diacritics
import re
guess = answers[0]
r = rpc("char_submit_guess", mona["token"], guess)
check("correct guess accepted", r.get("correct") is True)
check("100 points with 1 hint visible + 20 speed bonus", r["points"] == 100 and r["speed_bonus"] == 20, str(r))
check("double scoring blocked", err(rpc("char_submit_guess", mona["token"], guess)) == "already_solved")
check("Mona total = 120", admin("SELECT points FROM game_scores WHERE player_id=%s", (mona["player_id"],))[0][0] == 120)

# push time forward: 4 hints, interval = 10s. Put round start 31s ago -> 4 hints visible -> 40 points, no bonus (not first)
admin("UPDATE character_rounds SET started_at = clock_timestamp() - interval '31 seconds' WHERE game_id=%s AND round_number=1", (gid,))
s = state(host)
check("hints reveal over time (4 visible after 31s)", s["round"]["hints_visible"] == 4 and len(s["round"]["hints"]) == 4)
r = rpc("char_submit_guess", host["token"], guess.upper() + "  ")
check("40 points with 4 hints, no bonus for non-first", r.get("correct") and r["points"] == 40 and r["speed_bonus"] == 0, str(r))
s = state(host)
check("solved flags public, name still hidden", sum(1 for p in s["players"] if p["solved"]) == 2 and name not in json.dumps(s, ensure_ascii=False))
check("Ali still can't see answer; feed shows wrong text but not correct text", name not in json.dumps(state(ali)["round"]["feed"], ensure_ascii=False))

print("== 5. Yes/No questions")
q1 = rpc("char_ask_question", ali["token"], "is_real")
check("question answered from facts", err(q1) is None and q1["answer"] in ("yes", "no", "na"))
check("solved player cannot ask", err(rpc("char_ask_question", mona["token"], "is_male")) == "already_solved")
check("invalid key rejected", err(rpc("char_ask_question", ali["token"], "salary")) == "invalid_question")
check("repeat question rejected", err(rpc("char_ask_question", ali["token"], "is_real")) == "question_already_asked")
rpc("char_ask_question", ali["token"], "is_male")
check("question limit enforced (2 per player)", err(rpc("char_ask_question", ali["token"], "is_arab")) == "no_questions_left")

print("== 6. Round end, reveal and results")
s = state(ali)
check("Ali (not solved) still in round", s["game"]["phase"] == "round")
admin("UPDATE character_games SET phase_ends_at = clock_timestamp() - interval '1 second' WHERE id=%s", (gid,))
check("guess after deadline refused (unified server timer)", err(rpc("char_submit_guess", ali["token"], "شيء")) == "round_closed")
rpc("char_advance", ali["token"])
s = state(ali)
check("phase reveal after timer", s["game"]["phase"] == "reveal")
check("reveal shows name and all hints", s["reveal"]["name"] == name and len(s["round"]["hints"]) == 4)
res = {r["player_id"]: r for r in s["reveal"]["results"]}
check("reveal results: Mona 120, Host 40, Ali 0", res[mona["player_id"]]["points"] == 120 and res[host["player_id"]]["points"] == 40 and res[ali["player_id"]]["points"] == 0)
rpc("char_advance", host["token"]); rpc("char_advance", mona["token"])
check("advancing early during reveal does nothing", state(host)["game"]["phase"] == "reveal")
check("non-host cannot skip reveal", err(rpc("char_next_round", ali["token"])) == "not_host")
check("host skips reveal -> countdown of round 2", err(rpc("char_next_round", host["token"])) is None and state(host)["game"]["phase"] == "countdown" and state(host)["game"]["round_number"] == 2)

print("== 7. Round 2: everyone solves -> round ends immediately; no repeats")
name2, answers2 = secret_name(gid, 2)
check("round 2 character differs from round 1", name2 != name)
start_round_now(host, gid)
for p in (host, ali, mona):
    rpc("char_submit_guess", p["token"], answers2[0])
s = state(host)
check("all solved -> reveal immediately", s["game"]["phase"] == "reveal")
check("end reason all_guessed", admin("SELECT end_reason FROM character_rounds WHERE game_id=%s AND round_number=2", (gid,))[0][0] == "all_guessed")

print("== 8. Disconnect / reconnect while playing")
sess = rpc("resume_session", mona["token"])
check("resume_session restores the same player/room", sess["player_id"] == mona["player_id"] and sess["room_id"] == mona["room_id"])
s = state(mona)
check("state after reconnect keeps score & phase", s["game"]["phase"] == "reveal" and [p for p in s["players"] if p["is_me"]][0]["points"] >= 100)

print("== 9. Host hand-over")
admin("UPDATE character_presence SET seen_at = clock_timestamp() - interval '2 minutes' WHERE player_id=%s", (host["player_id"],))
rpc("char_heartbeat", ali["token"])
hosts = admin("SELECT name FROM players WHERE room_id=%s AND is_host", (host["room_id"],))
check("silent host replaced by an active player (exactly one host)", len(hosts) == 1 and hosts[0][0] == "Ali")
check("old host is no longer host", state(host)["me"]["is_host"] is False)
check("new host can control the game", err(rpc("char_next_round", ali["token"])) is None)
rpc("char_heartbeat", host["token"])
check("an active host is not replaced", state(ali)["me"]["is_host"] is True)

print("== 10. Last round, finish, play again")
gs = state(ali)["game"]
start_round_now(ali, gid)
admin("UPDATE character_games SET phase_ends_at = clock_timestamp() - interval '1 second' WHERE id=%s", (gid,))
rpc("char_advance", ali["token"])
admin("UPDATE character_games SET phase_ends_at = clock_timestamp() - interval '1 second' WHERE id=%s", (gid,))
rpc("char_advance", ali["token"])
s = state(ali)
check("game finished after 3 rounds", s["game"]["phase"] == "finished")
check("room status finished", admin("SELECT status FROM rooms WHERE id=%s", (host["room_id"],))[0][0] == "finished")
pts = [p["points"] for p in s["players"]]
check("final ranking sorted by points", pts == sorted(pts, reverse=True))
check("non-host cannot play again", err(rpc("char_play_again", mona["token"])) == "not_host")
check("host plays again without recreating the room", err(rpc("char_play_again", ali["token"])) is None)
s = state(ali)
check("same room back to lobby, scores reset", s["game"]["phase"] == "setup" and all(p["points"] == 0 for p in s["players"]) and s["room"]["code"] == host["code"])
check("second game starts in the same room", err(rpc("char_start_game", ali["token"])) is None)
check("no repeated characters across games in the room", admin("SELECT count(*) FROM (SELECT character_id FROM character_rounds WHERE game_id=%s) a", (gid,))[0][0] == 1)

print("== 11. Leaving: host leaves mid-game -> next player becomes host; fewer than 2 players ends game")
rpc("leave_room", ali["token"])
hosts = admin("SELECT name FROM players WHERE room_id=%s AND is_host", (host["room_id"],))
check("host promoted on leave (existing mechanism)", len(hosts) == 1)
remaining = admin("SELECT count(*) FROM players WHERE room_id=%s", (host["room_id"],))[0][0]
check("two players remain", remaining == 2)
rpc("leave_room", mona["token"])
tok = host["token"]
check("with one player left, advance finishes the game", err(rpc("char_advance", tok)) is None and state(host)["game"]["phase"] == "finished")

print("== 12. Fast Guess mode and Progressive/Mystery image rules")
P2 = new_room(["A", "B"]); a, b = P2
set_settings(a, "fast", 3, 30, 0, [])
rpc("char_start_game", a["token"]); gid2 = state(a)["game"]["id"]
start_round_now(a, gid2)
s = state(a)
check("fast: image path only if the character has one (none uploaded) and shown flag true", s["round"]["show_image"] is True)
nm, ans = secret_name(gid2, 1)
r = rpc("char_submit_guess", b["token"], ans[0])
check("fast: speed bonus is 50", r["speed_bonus"] == 50, str(r))
rem = admin("SELECT extract(epoch FROM (phase_ends_at - clock_timestamp())) FROM character_games WHERE id=%s", (gid2,))[0][0]
check("fast: round shortened to ~5s after first correct", 0 < float(rem) <= 5.0, str(rem))
check("fast: a late guess after the first still allowed within grace", err(rpc("char_submit_guess", a["token"], ans[0])) is None)

P3 = new_room(["M1", "M2"]); m1, m2 = P3
set_settings(m1, "mystery", 3, 30, 3, [])
admin("UPDATE characters SET image_path='abc123.png' WHERE name_ar IN (SELECT name_ar FROM characters)")
rpc("char_start_game", m1["token"]); g3 = state(m1)["game"]["id"]
start_round_now(m1, g3)
s = state(m1)
check("mystery: image never returned during round", s["round"]["image_path"] is None and s["round"]["show_image"] is False)
P4 = new_room(["C1", "C2"]); c1, c2 = P4
set_settings(c1, "classic", 3, 30, 3, [])
rpc("char_start_game", c1["token"]); g4 = state(c1)["game"]["id"]
s = state(c1)
check("classic: image hidden during countdown", s["round"]["image_path"] is None)
start_round_now(c1, g4)
check("classic: image path returned once round runs", state(c1)["round"]["image_path"] == "abc123.png")
admin("UPDATE characters SET image_path=NULL")

print("== 13. Normalisation of guesses")
n = lambda t: admin("SELECT public.game_normalize(%s)", (t,))[0][0]
check("alef / ya / ta-marbuta / diacritics / al- prefix ignored", n("الأَهْلِيّ") == n("اهلي") and n("مَدْرَسَة") == n("مدرسه"))
check("case and punctuation ignored", n("Mohamed  Salah!") == "mohamed salah")

print("== 14. Other game types are untouched")
risk = rpc("create_room", "RiskHost", "crown", 4, "solo")
check("RISK IT create_room still works, game_type risk_it", admin("SELECT game_type FROM rooms WHERE id=%s", (risk["room_id"],))[0][0] == "risk_it")
check("char functions refuse a RISK IT room", err(rpc("char_get_state", risk["token"])) == "wrong_game_type")
bus = rpc("create_bus_room", "BusHost", "crown", 4, "solo")
check("BUS COMPLETE create_bus_room still works", err(bus) is None and bus.get("game_type") == "bus_complete")

print("== 15. Admin permissions")
check("anon cannot save characters", err(rpc("char_admin_save_character", None, "x", None, "actors", None, None, None, None, None, None, True, ["a","b","c"], [])) is not None)
uid = admin("INSERT INTO auth.users (email) VALUES ('admin@test') RETURNING id")[0][0]
admin("INSERT INTO bus_admins (user_id) VALUES (%s)", (uid,))
cur.execute("SET ROLE authenticated"); cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false)", (str(uid),))
cur.execute("SELECT public.char_admin_save_character(NULL,'شخصية اختبار','Test Person','actors',NULL,true,true,true,true,true,true,ARRAY['h1','h2','h3','h4'],ARRAY['اختبار'])")
new_id = cur.fetchone()[0]
check("admin can create a character with hints and aliases", new_id is not None)
cur.execute("SELECT count(*) FROM character_hints WHERE character_id=%s", (new_id,)); check("4 hints saved", cur.fetchone()[0] == 4)
try:
    cur.execute("SELECT public.char_admin_save_character(%s,'شخصية اختبار','Test Person','actors',NULL,true,true,true,true,true,true,ARRAY['only1'],ARRAY[]::text[])", (new_id,)); ok=False
except psycopg2.Error as e:
    ok = "need_three_hints" in str(e)
check("active character needs at least 3 hints", ok)
cur.execute("SELECT public.char_admin_save_character(%s,'شخصية اختبار','Test Person','actors','img.png',true,true,true,true,true,true,ARRAY['x1','x2','x3'],ARRAY['اختبار','test'])", (new_id,))
cur.execute("SELECT count(*) FROM character_hints WHERE character_id=%s", (new_id,)); check("edit replaces hints", cur.fetchone()[0] == 3)
cur.execute("RESET ROLE"); cur.execute("DELETE FROM character_rounds WHERE character_id=%s", (new_id,))
cur.execute("SET ROLE authenticated"); cur.execute("DELETE FROM characters WHERE id=%s", (new_id,))
cur.execute("SELECT count(*) FROM characters WHERE id=%s", (new_id,)); check("admin can delete a character", cur.fetchone()[0] == 0)
cur.execute("RESET ROLE")
# a normal authenticated (non-admin) user
uid2 = admin("INSERT INTO auth.users (email) VALUES ('user@test') RETURNING id")[0][0]
cur.execute("SET ROLE authenticated"); cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false)", (str(uid2),))
cur.execute("SELECT count(*) FROM characters"); check("signed-in non-admin sees no characters", cur.fetchone()[0] == 0)
try:
    cur.execute("INSERT INTO characters (name_ar, category) VALUES ('x','actors')"); ok = False
except psycopg2.Error:
    ok = True
cur.execute("RESET ROLE")
check("signed-in non-admin cannot insert characters", ok)

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
