export const AVATAR_KEYS = ['crown', 'rocket', 'zap', 'flame', 'ghost', 'bot', 'target', 'gem'] as const;
export type AvatarKey = (typeof AVATAR_KEYS)[number];

export type GameMode = 'solo' | 'team';
export type GameType = 'risk_it' | 'bus_complete' | 'guess_character';
export type RoomStatus = 'lobby' | 'playing' | 'paused' | 'finished';

export interface Room {
  id: string;
  code: string;
  status: RoomStatus;
  max_players: number;
  game_mode: GameMode;
  game_type: GameType;
  question_seconds: number;
}

export interface Player {
  id: string;
  room_id: string;
  name: string;
  avatar: AvatarKey;
  is_host: boolean;
  joined_at: string;
}

export interface RoomSession {
  roomId: string;
  playerId: string;
  code: string;
  token: string;
}
