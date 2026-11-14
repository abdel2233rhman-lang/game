import { supabase } from '@/lib/supabase';
import type { AvatarKey, GameMode, Player, Room, RoomSession } from '@/types/room';

export interface RoomSnapshot {
  room: Room | null;
  players: Player[];
}

export interface CreatedRoomSession extends RoomSession {
  token: string;
}

const ERROR_MESSAGES: Record<string, string> = {
  invalid_name: 'اكتب اسمًا من 1 إلى 16 حرفًا.',
  invalid_avatar: 'اختر صورة رمزية من القائمة.',
  invalid_max_players: 'عدد اللاعبين يجب أن يكون بين 2 و 8.',
  invalid_game_mode: 'نظام اللعب غير صحيح.',
  room_not_found: 'لم نجد غرفة بهذا الكود.',
  room_already_started: 'بدأت المباراة بالفعل، لا يمكن الانضمام الآن.',
  room_full: 'الغرفة مكتملة.',
  name_taken: 'هذا الاسم مستخدم داخل الغرفة، اختر اسمًا آخر.',
  session_not_found: 'انتهت جلستك في هذه الغرفة.',
  not_host: 'فقط المضيف يستطيع تغيير إعدادات الغرفة.',
  max_below_players: 'لا يمكن تقليل العدد أقل من عدد اللاعبين الموجودين.',
  code_generation_failed: 'تعذر إنشاء كود للغرفة، حاول مرة أخرى.',
  not_enough_players: 'تحتاج الغرفة إلى لاعبين اثنين على الأقل لبدء المباراة.',
  not_in_game: 'لست جزءًا من هذه المباراة.',
  no_active_game: 'لا توجد مباراة نشطة في هذه الغرفة.',
  invalid_bet: 'اختر قيمة رهان صالحة.',
  insufficient_balance: 'رصيدك لا يكفي لهذا الرهان.',
  bet_already_placed: 'تم تأكيد رهانك بالفعل ولا يمكن تغييره.',
  betting_closed: 'انتهى وقت الرهان لهذه الجولة.',
  not_betting: 'لم تراهن في هذه الجولة، لذلك لا يمكنك الإجابة.',
  invalid_choice: 'اختيار الإجابة غير صالح.',
  already_answered: 'أجبت على هذا السؤال بالفعل.',
  question_closed: 'انتهى وقت الإجابة.',
  invalid_question_seconds: 'وقت السؤال يجب أن يكون بين 10 و 60 ثانية.',
  wrong_game_type: 'هذه الغرفة مخصصة للعبة أخرى.',
  invalid_mode: 'وضع اللعب غير صحيح.',
  invalid_rounds: 'عدد الجولات يجب أن يكون بين 3 و 10.',
  invalid_round_seconds: 'وقت الجولة يجب أن يكون بين 20 و 90 ثانية.',
  invalid_questions: 'عدد الأسئلة يجب أن يكون بين 0 و 5.',
  invalid_categories: 'تصنيف غير صحيح.',
  not_enough_characters: 'عدد الشخصيات المتاحة في التصنيفات المختارة أقل من عدد الجولات.',
  round_closed: 'انتهى وقت الجولة أو لم تبدأ بعد.',
  invalid_guess: 'اكتب إجابة من 1 إلى 80 حرفًا.',
  already_solved: 'أجبت إجابة صحيحة في هذه الجولة بالفعل.',
  no_attempts_left: 'استهلكت محاولاتك الخاطئة في هذه الجولة.',
  duplicate_guess: 'أرسلت هذه الإجابة من قبل.',
  invalid_question: 'السؤال غير صالح.',
  no_questions_left: 'استهلكت أسئلتك في هذه الجولة.',
  question_already_asked: 'تم طرح هذا السؤال بالفعل في هذه الجولة.',
  game_not_finished: 'المباراة لم تنتهِ بعد.',
  not_admin: 'هذا الحساب ليس لديه صلاحية الإدارة.',
  need_three_hints: 'الشخصية المفعّلة تحتاج 3 تلميحات على الأقل.',
  too_many_hints: 'الحد الأقصى 6 تلميحات.',
  character_exists: 'توجد شخصية بنفس الاسم بالفعل.',
  character_not_found: 'الشخصية غير موجودة.',
};

const GENERIC_ERROR = 'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى.';

export function getErrorMessage(error: unknown): string {
  if (error instanceof Error && ERROR_MESSAGES[error.message]) {
    return ERROR_MESSAGES[error.message];
  }
  return GENERIC_ERROR;
}

export function toError(raw: { message: string }): Error {
  const key = raw.message.trim();
  return new Error(ERROR_MESSAGES[key] ? key : 'unknown');
}

function isSessionPayload(value: unknown): value is { room_id: string; player_id: string; code: string; token: string } {
  if (!value || typeof value !== 'object') return false;
  const candidate = value as Record<string, unknown>;
  return (
    typeof candidate.room_id === 'string' &&
    typeof candidate.player_id === 'string' &&
    typeof candidate.code === 'string' &&
    typeof candidate.token === 'string'
  );
}

function toSession(data: unknown): CreatedRoomSession {
  if (!isSessionPayload(data)) throw new Error('unknown');
  return {
    roomId: data.room_id,
    playerId: data.player_id,
    code: data.code,
    token: data.token,
  };
}

export async function createRoom(input: {
  name: string;
  avatar: AvatarKey;
  maxPlayers: number;
  gameMode: GameMode;
}): Promise<CreatedRoomSession> {
  const { data, error } = await supabase.rpc('create_room', {
    p_name: input.name,
    p_avatar: input.avatar,
    p_max_players: input.maxPlayers,
    p_game_mode: input.gameMode,
  });
  if (error) throw toError(error);
  return toSession(data);
}

export async function joinRoom(input: { code: string; name: string; avatar: AvatarKey }): Promise<CreatedRoomSession> {
  const { data, error } = await supabase.rpc('join_room', {
    p_code: input.code,
    p_name: input.name,
    p_avatar: input.avatar,
  });
  if (error) throw toError(error);
  return toSession(data);
}

export async function resumeSession(token: string): Promise<RoomSession | null> {
  const { data, error } = await supabase.rpc('resume_session', { p_token: token });
  if (error) throw toError(error);
  if (data === null) return null;
  if (!isSessionPayload(data)) throw new Error('unknown');
  return { roomId: data.room_id, playerId: data.player_id, code: data.code, token };
}

export async function updateRoomSettings(input: { token: string; maxPlayers: number; gameMode: GameMode }): Promise<void> {
  const { error } = await supabase.rpc('update_room_settings', {
    p_token: input.token,
    p_max_players: input.maxPlayers,
    p_game_mode: input.gameMode,
  });
  if (error) throw toError(error);
}

export async function leaveRoom(token: string): Promise<void> {
  const { error } = await supabase.rpc('leave_room', { p_token: token });
  if (error) throw toError(error);
}

export async function fetchRoomSnapshot(roomId: string): Promise<RoomSnapshot> {
  const [roomResult, playersResult] = await Promise.all([
    supabase.from('rooms').select('id, code, status, max_players, game_mode, game_type, question_seconds').eq('id', roomId).maybeSingle(),
    supabase
      .from('players')
      .select('id, room_id, name, avatar, is_host, joined_at')
      .eq('room_id', roomId)
      .order('joined_at', { ascending: true }),
  ]);

  if (roomResult.error) throw new Error('unknown');
  if (playersResult.error) throw new Error('unknown');

  return {
    room: (roomResult.data as Room | null) ?? null,
    players: (playersResult.data as Player[] | null) ?? [],
  };
}

export async function createCharacterRoom(input: {
  name: string;
  avatar: AvatarKey;
  maxPlayers: number;
}): Promise<CreatedRoomSession> {
  const { data, error } = await supabase.rpc('create_character_room', {
    p_name: input.name,
    p_avatar: input.avatar,
    p_max_players: input.maxPlayers,
  });
  if (error) throw toError(error);
  return toSession(data);
}
