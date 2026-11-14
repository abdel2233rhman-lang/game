import { supabase } from '@/lib/supabase';
import { toError } from '@/lib/roomApi';
import type { AvatarKey, GameMode, RoomStatus } from '@/types/room';

export type GamePhase = 'betting' | 'question' | 'reveal' | 'finished';
export type Difficulty = 'easy' | 'medium' | 'hard' | 'insane';

export interface GamePlayer {
  player_id: string;
  name: string;
  avatar: AvatarKey;
  is_host: boolean;
  is_me: boolean;
  balance: number;
  correct_count: number;
  wrong_count: number;
  timeout_count: number;
  locked: boolean;
  wagered: boolean | null;
  answered: boolean;
}

export interface RoundResult {
  player_id: string;
  bet: number;
  choice: number | null;
  is_correct: boolean;
  delta: number;
}

export interface GameQuestion {
  category: string;
  difficulty: Difficulty;
  kind: string;
  prompt: string | null;
  options: string[] | null;
  image_url: string | null;
  time_limit: number | null;
}

export interface GameState {
  server_now_ms: number;
  me: { player_id: string; bet: number | null; choice: number | null };
  room: { code: string; status: RoomStatus; max_players: number; game_mode: GameMode; question_seconds: number };
  game: {
    id: string;
    status: 'active' | 'finished';
    phase: GamePhase;
    round_number: number;
    total_rounds: number;
    question_seconds: number;
    phase_ends_at_ms: number | null;
  } | null;
  question: GameQuestion | null;
  reveal: { correct_index: number; results: RoundResult[] } | null;
  players: GamePlayer[];
}

interface RawGameState extends Omit<GameState, 'server_now_ms' | 'game'> {
  server_now: string;
  game: (Omit<NonNullable<GameState['game']>, 'phase_ends_at_ms'> & { phase_ends_at: string | null }) | null;
}

function parseTimestampMs(value: string): number {
  const ms = Date.parse(value.replace(/(\.\d{3})\d+/, '$1'));
  if (Number.isNaN(ms)) throw new Error('unknown');
  return ms;
}

function parseGameState(data: unknown): GameState {
  if (!data || typeof data !== 'object') throw new Error('unknown');
  const raw = data as RawGameState;
  if (typeof raw.server_now !== 'string' || !Array.isArray(raw.players) || !raw.me) throw new Error('unknown');
  return {
    server_now_ms: parseTimestampMs(raw.server_now),
    me: raw.me,
    room: raw.room,
    game: raw.game
      ? {
          id: raw.game.id,
          status: raw.game.status,
          phase: raw.game.phase,
          round_number: raw.game.round_number,
          total_rounds: raw.game.total_rounds,
          question_seconds: raw.game.question_seconds,
          phase_ends_at_ms: raw.game.phase_ends_at ? parseTimestampMs(raw.game.phase_ends_at) : null,
        }
      : null,
    question: raw.question,
    reveal: raw.reveal,
    players: raw.players,
  };
}

export async function fetchGameState(token: string): Promise<GameState> {
  const { data, error } = await supabase.rpc('get_game_state', { p_token: token });
  if (error) throw toError(error);
  return parseGameState(data);
}

export async function startGame(token: string): Promise<void> {
  const { error } = await supabase.rpc('start_game', { p_token: token });
  if (error) throw toError(error);
}

export async function setQuestionSeconds(token: string, seconds: number): Promise<void> {
  const { error } = await supabase.rpc('set_question_seconds', { p_token: token, p_seconds: seconds });
  if (error) throw toError(error);
}

export async function placeBet(token: string, amount: number): Promise<void> {
  const { error } = await supabase.rpc('place_bet', { p_token: token, p_amount: amount });
  if (error) throw toError(error);
}

export async function submitAnswer(token: string, choice: number): Promise<void> {
  const { error } = await supabase.rpc('submit_answer', { p_token: token, p_choice: choice });
  if (error) throw toError(error);
}

export async function advanceGame(token: string): Promise<void> {
  const { error } = await supabase.rpc('advance_game', { p_token: token });
  if (error) throw toError(error);
}
