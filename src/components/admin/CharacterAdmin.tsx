import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { ImagePlus, Loader2, LogOut, Pencil, Plus, Search, Trash2, UserRound } from 'lucide-react';
import type { Session } from '@supabase/supabase-js';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Logo } from '@/components/ui/Logo';
import { CHARACTER_IMAGE_BUCKET, characterImageUrl, type CharacterCategory } from '@/lib/characterApi';
import { CATEGORY_LABEL, CHARACTER_CATEGORIES } from '@/lib/characterConstants';
import { getErrorMessage, toError } from '@/lib/roomApi';
import { supabase } from '@/lib/supabase';

type Fact = boolean | null;

interface CharacterRow {
  id: string;
  name_ar: string;
  name_en: string | null;
  category: CharacterCategory;
  image_path: string | null;
  is_male: Fact;
  is_alive: Fact;
  is_egyptian: Fact;
  is_arab: Fact;
  is_real: Fact;
  is_active: boolean;
  character_hints: { position: number; text_ar: string }[];
  character_aliases: { alias_text: string }[];
}

interface Draft {
  id: string | null;
  nameAr: string;
  nameEn: string;
  category: CharacterCategory;
  imagePath: string | null;
  facts: Record<'is_male' | 'is_alive' | 'is_egyptian' | 'is_arab' | 'is_real', Fact>;
  hints: string[];
  aliases: string;
  active: boolean;
}

const FACT_LABELS: { key: keyof Draft['facts']; label: string }[] = [
  { key: 'is_real', label: 'شخصية حقيقية' },
  { key: 'is_male', label: 'ذكر' },
  { key: 'is_alive', label: 'على قيد الحياة' },
  { key: 'is_egyptian', label: 'مصرية' },
  { key: 'is_arab', label: 'عربية' },
];

const emptyDraft = (): Draft => ({
  id: null,
  nameAr: '',
  nameEn: '',
  category: 'football',
  imagePath: null,
  facts: { is_real: true, is_male: true, is_alive: true, is_egyptian: false, is_arab: false },
  hints: ['', '', '', ''],
  aliases: '',
  active: true,
});

const toDraft = (row: CharacterRow): Draft => {
  const hints = [...row.character_hints].sort((a, b) => a.position - b.position).map((h) => h.text_ar);
  while (hints.length < 4) hints.push('');
  return {
    id: row.id,
    nameAr: row.name_ar,
    nameEn: row.name_en ?? '',
    category: row.category,
    imagePath: row.image_path,
    facts: { is_real: row.is_real, is_male: row.is_male, is_alive: row.is_alive, is_egyptian: row.is_egyptian, is_arab: row.is_arab },
    hints,
    aliases: row.character_aliases.map((a) => a.alias_text).join('\n'),
    active: row.is_active,
  };
};

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

function FactSelect({ value, onChange }: { value: Fact; onChange: (v: Fact) => void }) {
  return (
    <select
      className="field !py-2 text-sm"
      value={value === null ? 'null' : value ? 'yes' : 'no'}
      onChange={(e) => onChange(e.target.value === 'null' ? null : e.target.value === 'yes')}
    >
      <option value="yes">نعم</option>
      <option value="no">لا</option>
      <option value="null">لا ينطبق / غير معروف</option>
    </select>
  );
}

function Editor({ draft, onChange, onSaved, onClose }: { draft: Draft; onChange: (d: Draft) => void; onSaved: () => void; onClose: () => void }) {
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function upload(file: File) {
    setError(null);
    if (!ALLOWED_TYPES.includes(file.type)) return setError('الصيغ المسموحة: JPG أو PNG أو WEBP.');
    if (file.size > 2 * 1024 * 1024) return setError('حجم الصورة يجب ألا يتجاوز 2 ميجابايت.');
    setUploading(true);
    try {
      const ext = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
      // random file name: the path never reveals the answer to players
      const path = `${crypto.randomUUID()}.${ext}`;
      const { error: upErr } = await supabase.storage.from(CHARACTER_IMAGE_BUCKET).upload(path, file, { contentType: file.type });
      if (upErr) throw new Error('upload');
      onChange({ ...draft, imagePath: path });
    } catch {
      setError('تعذر رفع الصورة. تأكد أنك مسجّل كمسؤول.');
    } finally {
      setUploading(false);
    }
  }

  async function save(event: FormEvent) {
    event.preventDefault();
    setError(null);
    if (!draft.nameAr.trim()) return setError('اكتب اسم الشخصية بالعربية.');
    const hints = draft.hints.map((h) => h.trim()).filter(Boolean);
    if (draft.active && hints.length < 3) return setError('الشخصية المفعّلة تحتاج 3 تلميحات على الأقل.');
    setSaving(true);
    const { error: rpcErr } = await supabase.rpc('char_admin_save_character', {
      p_id: draft.id,
      p_name_ar: draft.nameAr,
      p_name_en: draft.nameEn,
      p_category: draft.category,
      p_image_path: draft.imagePath,
      p_is_male: draft.facts.is_male,
      p_is_alive: draft.facts.is_alive,
      p_is_egyptian: draft.facts.is_egyptian,
      p_is_arab: draft.facts.is_arab,
      p_is_real: draft.facts.is_real,
      p_is_active: draft.active,
      p_hints: hints,
      p_aliases: draft.aliases.split(/[\n,،]/).map((a) => a.trim()).filter(Boolean),
    });
    setSaving(false);
    if (rpcErr) return setError(getErrorMessage(toError(rpcErr)));
    onSaved();
    onClose();
  }

  return (
    <form onSubmit={save} className="flex flex-col gap-5" noValidate>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className="label" htmlFor="name-ar">الاسم بالعربية</label>
          <input id="name-ar" className="field" value={draft.nameAr} maxLength={80} onChange={(e) => onChange({ ...draft, nameAr: e.target.value })} />
        </div>
        <div>
          <label className="label" htmlFor="name-en">الاسم بالإنجليزية (اختياري)</label>
          <input id="name-en" dir="ltr" className="field" value={draft.nameEn} maxLength={80} onChange={(e) => onChange({ ...draft, nameEn: e.target.value })} />
        </div>
      </div>

      <div>
        <label className="label" htmlFor="category">التصنيف</label>
        <select id="category" className="field" value={draft.category} onChange={(e) => onChange({ ...draft, category: e.target.value as CharacterCategory })}>
          {CHARACTER_CATEGORIES.map((c) => (
            <option key={c.key} value={c.key}>{c.label}</option>
          ))}
        </select>
      </div>

      <div>
        <span className="label">الصورة (JPG / PNG / WEBP، حتى 2 ميجا)</span>
        <div className="flex items-center gap-4">
          <div className="flex h-20 w-20 shrink-0 items-center justify-center overflow-hidden rounded-2xl border border-white/15 bg-ink-800">
            {draft.imagePath ? <img src={characterImageUrl(draft.imagePath)} alt="" className="h-full w-full object-cover" /> : <UserRound className="h-8 w-8 text-ink-400" />}
          </div>
          <label className="inline-flex cursor-pointer items-center gap-2 rounded-xl border border-white/15 bg-white/[0.04] px-4 py-2 text-sm font-bold transition hover:border-neon-400/60">
            {uploading ? <Loader2 className="h-4 w-4 animate-spin" /> : <ImagePlus className="h-4 w-4" />}
            {draft.imagePath ? 'استبدال الصورة' : 'رفع صورة'}
            <input type="file" accept={ALLOWED_TYPES.join(',')} className="sr-only" disabled={uploading} onChange={(e) => e.target.files?.[0] && void upload(e.target.files[0])} />
          </label>
          {draft.imagePath && (
            <button type="button" className="text-sm text-rose-300 hover:underline" onClick={() => onChange({ ...draft, imagePath: null })}>
              إزالة
            </button>
          )}
        </div>
        <p className="mt-2 text-xs text-ink-400">ارفع فقط صورًا لديك حق استخدامها.</p>
      </div>

      <div>
        <span className="label">التلميحات (من الأعم إلى الأخص، 3 على الأقل، حتى 6)</span>
        <div className="flex flex-col gap-2">
          {draft.hints.map((hint, i) => (
            <div key={i} className="flex items-center gap-2">
              <span className="w-6 text-center font-display text-sm text-gold-300">{i + 1}</span>
              <input className="field !py-2" value={hint} maxLength={160} onChange={(e) => onChange({ ...draft, hints: draft.hints.map((h, j) => (j === i ? e.target.value : h)) })} />
            </div>
          ))}
          {draft.hints.length < 6 && (
            <button type="button" className="w-fit text-sm font-bold text-neon-300 hover:underline" onClick={() => onChange({ ...draft, hints: [...draft.hints, ''] })}>
              + إضافة تلميح
            </button>
          )}
        </div>
      </div>

      <div>
        <label className="label" htmlFor="aliases">إجابات بديلة مقبولة (كل واحدة في سطر أو مفصولة بفاصلة)</label>
        <textarea id="aliases" rows={3} className="field" value={draft.aliases} onChange={(e) => onChange({ ...draft, aliases: e.target.value })} />
      </div>

      <div>
        <span className="label">حقائق لأسئلة نعم / لا</span>
        <div className="grid gap-3 sm:grid-cols-2">
          {FACT_LABELS.map(({ key, label }) => (
            <div key={key} className="flex items-center justify-between gap-3">
              <span className="text-sm text-ink-200">{label}</span>
              <div className="w-48"><FactSelect value={draft.facts[key]} onChange={(v) => onChange({ ...draft, facts: { ...draft.facts, [key]: v } })} /></div>
            </div>
          ))}
        </div>
      </div>

      <label className="flex items-center gap-3 text-sm font-bold text-ink-100">
        <input type="checkbox" className="h-4 w-4 accent-purple-500" checked={draft.active} onChange={(e) => onChange({ ...draft, active: e.target.checked })} />
        الشخصية مفعّلة (تظهر في اللعب)
      </label>

      {error && <p role="alert" className="rounded-xl border border-red-400/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">{error}</p>}

      <Button type="submit" disabled={saving || uploading} icon={saving ? <Loader2 className="h-5 w-5 animate-spin" /> : undefined} className="w-full">
        حفظ الشخصية
      </Button>
    </form>
  );
}

function Manager({ onSignOut }: { onSignOut: () => void }) {
  const [rows, setRows] = useState<CharacterRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState<CharacterCategory | 'all'>('all');
  const [draft, setDraft] = useState<Draft | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<CharacterRow | null>(null);

  const load = useCallback(async () => {
    const { data, error: err } = await supabase
      .from('characters')
      .select('*, character_hints(position, text_ar), character_aliases(alias_text)')
      .order('category')
      .order('name_ar');
    if (err) setError('تعذر تحميل الشخصيات.');
    else {
      setRows(data as CharacterRow[]);
      setError(null);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const filtered = useMemo(
    () =>
      (rows ?? []).filter(
        (r) =>
          (category === 'all' || r.category === category) &&
          (!query.trim() || r.name_ar.includes(query.trim()) || (r.name_en ?? '').toLowerCase().includes(query.trim().toLowerCase())),
      ),
    [rows, query, category],
  );

  async function toggleActive(row: CharacterRow) {
    if (!row.is_active && row.character_hints.length < 3) return setError('أضف 3 تلميحات على الأقل قبل التفعيل.');
    const { error: err } = await supabase.from('characters').update({ is_active: !row.is_active, updated_at: new Date().toISOString() }).eq('id', row.id);
    if (err) setError('تعذر تحديث الحالة.');
    else void load();
  }

  async function remove(row: CharacterRow) {
    const { error: err } = await supabase.from('characters').delete().eq('id', row.id);
    if (err) setError('تعذر الحذف.');
    else {
      if (row.image_path) await supabase.storage.from(CHARACTER_IMAGE_BUCKET).remove([row.image_path]);
      void load();
    }
    setConfirmDelete(null);
  }

  return (
    <main className="relative z-10 mx-auto w-full max-w-6xl px-4 py-6 sm:px-6 sm:py-10">
      <header className="flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-4">
          <Logo />
          <span className="rounded-full border border-gold-400/40 bg-gold-500/10 px-3 py-1 text-xs font-bold text-gold-200">إدارة خمن الشخصية</span>
        </div>
        <div className="flex gap-3">
          <Button onClick={() => setDraft(emptyDraft())} icon={<Plus className="h-4 w-4" />} className="px-4 py-2 text-sm">شخصية جديدة</Button>
          <Button variant="ghost" onClick={onSignOut} icon={<LogOut className="h-4 w-4" />} className="px-4 py-2 text-sm">خروج</Button>
        </div>
      </header>

      <div className="mt-8 flex flex-wrap gap-3">
        <div className="relative min-w-[14rem] flex-1">
          <Search className="pointer-events-none absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-400" />
          <input className="field !ps-10" placeholder="ابحث بالاسم" value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
        <select className="field !w-auto" value={category} onChange={(e) => setCategory(e.target.value as CharacterCategory | 'all')}>
          <option value="all">كل التصنيفات</option>
          {CHARACTER_CATEGORIES.map((c) => <option key={c.key} value={c.key}>{c.label}</option>)}
        </select>
      </div>

      {error && <p role="alert" className="mt-4 rounded-xl border border-amber-400/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">{error}</p>}

      {rows === null ? (
        <p className="mt-10 flex items-center gap-3 text-ink-300"><Loader2 className="h-5 w-5 animate-spin" /> جاري التحميل...</p>
      ) : (
        <>
          <p className="mt-6 text-sm text-ink-400">{filtered.length} شخصية</p>
          <ul className="mt-3 grid gap-3 md:grid-cols-2">
            {filtered.map((row) => (
              <li key={row.id} className={`glass flex items-center gap-4 p-4 ${row.is_active ? '' : 'opacity-60'}`}>
                <div className="flex h-14 w-14 shrink-0 items-center justify-center overflow-hidden rounded-xl border border-white/10 bg-ink-800">
                  {row.image_path ? <img src={characterImageUrl(row.image_path)} alt="" className="h-full w-full object-cover" /> : <UserRound className="h-6 w-6 text-ink-400" />}
                </div>
                <div className="min-w-0 flex-1">
                  <p className="truncate font-bold text-white">{row.name_ar}</p>
                  <p className="text-xs text-ink-400">{CATEGORY_LABEL[row.category]} · {row.character_hints.length} تلميحات</p>
                </div>
                <label className="flex items-center gap-2 text-xs text-ink-300">
                  <input type="checkbox" className="h-4 w-4 accent-purple-500" checked={row.is_active} onChange={() => void toggleActive(row)} />
                  مفعّلة
                </label>
                <button type="button" aria-label="تعديل" className="rounded-lg border border-white/10 p-2 hover:border-neon-400/60" onClick={() => setDraft(toDraft(row))}><Pencil className="h-4 w-4" /></button>
                <button type="button" aria-label="حذف" className="rounded-lg border border-white/10 p-2 text-rose-300 hover:border-rose-400/60" onClick={() => setConfirmDelete(row)}><Trash2 className="h-4 w-4" /></button>
              </li>
            ))}
          </ul>
        </>
      )}

      <Modal open={draft !== null} title={draft?.id ? 'تعديل شخصية' : 'شخصية جديدة'} onClose={() => setDraft(null)}>
        {draft && <Editor draft={draft} onChange={setDraft} onSaved={() => void load()} onClose={() => setDraft(null)} />}
      </Modal>

      <Modal open={confirmDelete !== null} title="تأكيد الحذف" onClose={() => setConfirmDelete(null)}>
        <p className="text-ink-200">هل تريد حذف «{confirmDelete?.name_ar}» نهائيًا؟ المباريات السابقة لن تتأثر.</p>
        <div className="mt-6 flex gap-3">
          <Button variant="ghost" className="flex-1" onClick={() => setConfirmDelete(null)}>إلغاء</Button>
          <Button className="flex-1 !from-rose-500 !to-rose-600" onClick={() => confirmDelete && void remove(confirmDelete)}>حذف</Button>
        </div>
      </Modal>
    </main>
  );
}

export function CharacterAdmin() {
  const [session, setSession] = useState<Session | null>(null);
  const [isAdmin, setIsAdmin] = useState<boolean | null>(null);
  const [ready, setReady] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setReady(true);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => setSession(next));
    return () => sub.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session) {
      setIsAdmin(null);
      return;
    }
    void supabase.rpc('game_is_admin').then(({ data, error: err }) => setIsAdmin(err ? false : data === true));
  }, [session]);

  async function signIn(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    const { error: err } = await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (err) setError('البريد أو كلمة المرور غير صحيحة.');
  }

  const signOut = () => void supabase.auth.signOut();

  if (!ready || (session && isAdmin === null)) {
    return <div className="flex min-h-screen items-center justify-center gap-3 text-ink-300"><Loader2 className="h-5 w-5 animate-spin text-neon-300" /> جاري التحقق...</div>;
  }
  if (session && isAdmin) return <Manager onSignOut={signOut} />;

  return (
    <main className="relative z-10 mx-auto flex min-h-screen w-full max-w-md flex-col justify-center px-4 py-12">
      <div className="glass flex flex-col gap-6 p-8 shadow-neon">
        <Logo />
        <h1 className="font-display text-xl font-black tracking-wider gold-text">لوحة إدارة خمن الشخصية</h1>
        {session && !isAdmin ? (
          <>
            <p role="alert" className="rounded-xl border border-amber-400/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">هذا الحساب ليس ضمن قائمة المسؤولين.</p>
            <Button variant="ghost" onClick={signOut}>تسجيل الخروج</Button>
          </>
        ) : (
          <form onSubmit={signIn} className="flex flex-col gap-4">
            <div>
              <label className="label" htmlFor="admin-email">البريد الإلكتروني</label>
              <input id="admin-email" dir="ltr" type="email" className="field" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="username" />
            </div>
            <div>
              <label className="label" htmlFor="admin-pass">كلمة المرور</label>
              <input id="admin-pass" dir="ltr" type="password" className="field" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" />
            </div>
            {error && <p role="alert" className="rounded-xl border border-red-400/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">{error}</p>}
            <Button type="submit" disabled={busy || !email || !password} icon={busy ? <Loader2 className="h-5 w-5 animate-spin" /> : undefined}>دخول</Button>
          </form>
        )}
      </div>
    </main>
  );
}
