import { supabase } from '@/lib/supabase';
import { toError } from '@/lib/roomApi';
import type { AvatarKey } from '@/types/room';

export type CharacterMode = 'classic' | 'mystery' | 'progressive' | 'fast';
export type CharacterPhase = 'setup' | 'countdown' | 'round' | 'reveal' | 'finished';
export type CharacterCategory =
  | 'football'
  | 'arab_artists'
  | 'world_celebrities'
  | 'actors'
  | 'cartoon'
  | 'historical'
  | 'games_movies';
export type QuestionKey = 'is_male' | 'is_alive' | 'is_egyptian' | 'is_arab' | 'is_real';
export type QuestionAnswer = 'yes' | 'no' | 'na';

export interface CharacterPlayer {
  player_id: string;
  name: string;
  avatar: AvatarKey;
  is_host: boolean;
  is_me: boolean;
  joined_at: string;
  points: number;
  correct_count: number;
  fastest_count: number;
  online: boolean;
  solved: boolean;
}

export type FeedItem =
  | { kind: 'guess'; player_id: string; text: string | null; correct: boolean }
  | { kind: 'question'; player_id: string; key: QuestionKey; answer: QuestionAnswer };

export interface RevealResult {
  player_id: string;
  solved: boolean;
  points: number;
  speed_bonus: number;
  hints_visible: number | null;
  elapsed_ms: number | null;
}

export interface CharacterGameInfo {
  id: string;
  phase: CharacterPhase;
  mode: CharacterMode;
  round_number: number;
  total_rounds: number;
  round_seconds: number;
  questions_per_player: number;
  categories: CharacterCategory[];
  phase_ends_at_ms: number | null;
}

export interface CharacterRound {
  round_number: number;
  category: CharacterCategory;
  show_image: boolean;
  image_path: string | null;
  hints_total: number;
  hints_visible: number;
  hints: string[];
  next_hint_at_ms: number | null;
  feed: FeedItem[];
}

export interface CharacterState {
  server_now_ms: number;
  me: {
    player_id: string;
    is_host: boolean;
    solved: boolean;
    attempts_left: number;
    questions_left: number;
    round_points: number;
  };
  room: { code: string; status: string; max_players: number };
  game: CharacterGameInfo;
  catalog: Partial<Record<CharacterCategory, number>> | null;
  round: CharacterRound | null;
  reveal: { name: string; end_reason: string | null; results: RevealResult[] } | null;
  players: CharacterPlayer[];
}

export interface GuessResult {
  correct: boolean;
  attempts_left?: number;
  points?: number;
  speed_bonus?: number;
  hints_visible?: number;
}

export interface CharacterSettings {
  mode: CharacterMode;
  totalRounds: number;
  roundSeconds: number;
  questionsPerPlayer: number;
  categories: CharacterCategory[];
}

type RawRound = Omit<CharacterRound, 'next_hint_at_ms'> & { next_hint_at: string | null };
type RawGame = Omit<CharacterGameInfo, 'phase_ends_at_ms'> & { phase_ends_at: string | null };
interface RawState extends Omit<CharacterState, 'server_now_ms' | 'game' | 'round'> {
  server_now: string;
  game: RawGame;
  round: RawRound | null;
}

function parseTimestampMs(value: string): number {
  const ms = Date.parse(value.replace(/(\.\d{3})\d+/, '$1'));
  if (Number.isNaN(ms)) throw new Error('unknown');
  return ms;
}

function parseState(data: unknown): CharacterState {
  if (!data || typeof data !== 'object') throw new Error('unknown');
  const raw = data as RawState;
  if (typeof raw.server_now !== 'string' || !Array.isArray(raw.players) || !raw.me || !raw.game) {
    throw new Error('unknown');
  }
  const { next_hint_at, ...roundRest } = raw.round ?? ({} as RawRound);
  const { phase_ends_at, ...gameRest } = raw.game;
  return {
    server_now_ms: parseTimestampMs(raw.server_now),
    me: raw.me,
    room: raw.room,
    game: { ...gameRest, phase_ends_at_ms: phase_ends_at ? parseTimestampMs(phase_ends_at) : null },
    catalog: raw.catalog,
    round: raw.round
      ? { ...(roundRest as Omit<RawRound, 'next_hint_at'>), next_hint_at_ms: next_hint_at ? parseTimestampMs(next_hint_at) : null }
      : null,
    reveal: raw.reveal,
    players: raw.players,
  };
}

export async function fetchCharacterState(token: string): Promise<CharacterState> {
  const { data, error } = await supabase.rpc('char_get_state', { p_token: token });
  if (error) throw toError(error);
  return parseState(data);
}

export async function updateCharacterSettings(token: string, settings: CharacterSettings): Promise<void> {
  const { error } = await supabase.rpc('char_update_settings', {
    p_token: token,
    p_mode: settings.mode,
    p_total_rounds: settings.totalRounds,
    p_round_seconds: settings.roundSeconds,
    p_questions_per_player: settings.questionsPerPlayer,
    p_categories: settings.categories,
  });
  if (error) throw toError(error);
}

export async function startCharacterGame(token: string): Promise<void> {
  const { error } = await supabase.rpc('char_start_game', { p_token: token });
  if (error) throw toError(error);
}

export async function submitCharacterGuess(token: string, text: string): Promise<GuessResult> {
  const { data, error } = await supabase.rpc('char_submit_guess', { p_token: token, p_text: text });
  if (error) throw toError(error);
  return data as GuessResult;
}

export async function askCharacterQuestion(token: string, key: QuestionKey): Promise<{ answer: QuestionAnswer }> {
  const { data, error } = await supabase.rpc('char_ask_question', { p_token: token, p_key: key });
  if (error) throw toError(error);
  return data as { answer: QuestionAnswer };
}

export async function advanceCharacterGame(token: string): Promise<void> {
  const { error } = await supabase.rpc('char_advance', { p_token: token });
  if (error) throw toError(error);
}

export async function nextCharacterRound(token: string): Promise<void> {
  const { error } = await supabase.rpc('char_next_round', { p_token: token });
  if (error) throw toError(error);
}

export async function playCharacterAgain(token: string): Promise<void> {
  const { error } = await supabase.rpc('char_play_again', { p_token: token });
  if (error) throw toError(error);
}

export async function characterHeartbeat(token: string): Promise<void> {
  const { error } = await supabase.rpc('char_heartbeat', { p_token: token });
  if (error) throw toError(error);
}

export const CHARACTER_IMAGE_BUCKET = 'character-images';

export function characterImageUrl(path: string): string {
  return supabase.storage.from(CHARACTER_IMAGE_BUCKET).getPublicUrl(path).data.publicUrl;
}
