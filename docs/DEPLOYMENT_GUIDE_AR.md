# دليل النشر الكامل: RISK IT + خمن الشخصية (Vercel + Supabase)

> مكتوب لشخص ليس لديه خبرة كبيرة في النشر. نفّذ الخطوات بالترتيب ولا تتخطَّ أي خطوة.
> أسماء القوائم في Supabase وVercel قد تتغير قليلًا مع تحديث واجهتيهما؛ المعنى يبقى واحدًا.

## 0) ملخص سريع

| السؤال | الإجابة |
|---|---|
| هل أرفع المشروع على Vercel مباشرة؟ | **نعم**، بشرط ثلاثة أشياء: (1) تشغيل الـ3 Migrations على Supabase أولًا، (2) إضافة متغيّرَي البيئة على Vercel، (3) رفع الكود عبر GitHub (أو Vercel CLI). لا تحتاج أي تعديل في الكود. |
| هل يحتاج ملف `vercel.json`؟ | **لا**. المشروع Vite عادي، ولا يستخدم صفحات/مسارات داخلية (يعتمد على `?room=` و`?admin=` في الرابط)، فلا حاجة لقواعد إعادة توجيه. |
| هل يحتاج Backend منفصل؟ | **لا**. كل المنطق داخل Supabase (قاعدة البيانات + الدوال + Realtime + Storage). |
| هل تغيير الـ Environment Variables يكفي؟ | **لا**، بعد أي تغيير لازم **Redeploy**؛ لأن متغيرات `VITE_` تُدمج داخل الملفات وقت البناء. |

**ترتيب العمل الصحيح:** Supabase (النسخة الاحتياطية → الـ Migrations → الأدمن) ثم GitHub ثم Vercel ثم الاختبار.

---

## 1) ما الذي ستحتاجه
1. حساب **Supabase** ومشروع RISK IT الحالي (أو مشروع جديد للتجربة، وهذا هو الأفضل أولًا، انظر الخطوة 2).
2. حساب **GitHub** (مجاني).
3. حساب **Vercel** (مجاني، سجّل الدخول بحساب GitHub).
4. (اختياري للتجربة المحلية) **Node.js 22** على جهازك.

> ⚠️ **تنبيه أمان:** ملف المشروع المضغوط يحتوي ملف `.env` فيه رابط ومفتاح Supabase. لا ترفع ملف `.env` إلى GitHub ولا تشارك الـ zip علنًا. ملف `.gitignore` في المشروع يستثني `.env` تلقائيًا، لكن تأكد (الخطوة 6-أ).

---

## 2) قبل أي تعديل: نسخة احتياطية وبيئة تجربة
**أنا (Claude) لم أُغيّر أي شيء في قاعدة بياناتك الحقيقية، ولا أملك وصولًا إليها.** كل الاختبارات تمت على قاعدة Postgres محلية مؤقتة.

الأفضل (موصى به بشدة):
1. أنشئ مشروع Supabase **جديدًا مجانيًا للتجربة** (Staging).
2. شغّل عليه كل ملفات `supabase/migrations/` القديمة ثم الـ3 الجديدة، وجرّب كل شيء.
3. بعدها فقط كرر نفس الخطوات على المشروع الحقيقي.

وقبل تشغيل أي Migration على المشروع الحقيقي:
- من Supabase: **Database → Backups** وتأكد من وجود نسخة حديثة (التوفّر يعتمد على خطتك). 
- أو خذ نسخة بنفسك (اختياري، تحتاج `pg_dump` وسلسلة اتصال قاعدة البيانات من **Project Settings → Database**):
  ```bash
  pg_dump "postgresql://postgres:كلمة_السر@db.xxxx.supabase.co:5432/postgres" --schema=public -f backup-before-guess-character.sql
  ```
- شغّل الـ Migrations **في وقت لا يلعب فيه أحد** (تأخذ ثوانٍ، لكنها تُقفل جدول `rooms` لحظيًا).

---

## 3) فحص الجاهزية (قراءة فقط، لا يغيّر شيئًا)
في Supabase: **SQL Editor → New query**، الصق ثم اضغط **Run**:

```sql
select
  to_regclass('public.rooms')           is not null as rooms,
  to_regclass('public.players')         is not null as players,
  to_regclass('public.player_sessions') is not null as player_sessions,
  to_regclass('public.games')           is not null as games,
  exists(select 1 from pg_proc where proname = 'generate_room_code')   as generate_room_code,
  exists(select 1 from pg_proc where proname = 'assert_player_input')  as assert_player_input,
  exists(select 1 from pg_proc where proname = 'assert_room_settings') as assert_room_settings;
```
**كل الأعمدة يجب أن تكون `true`.** إن ظهر `false` فمعناه أن Migrations RISK IT القديمة (في نفس المجلد) لم تُشغَّل بعد؛ شغّلها أولًا بترتيب أسماء الملفات.

التقط "لقطة قبل" لأعداد الصفوف (قراءة فقط). احفظ الأرقام لمقارنتها بعد الـ Migrations:
```sql
select 'rooms' as t, count(*) from rooms
union all select 'players', count(*) from players
union all select 'games', count(*) from games
union all select 'game_players', count(*) from game_players
union all select 'questions', count(*) from questions;
-- لو عندك جداول Bus Complete أضف مثلها، وإن أعطى سطر خطأ لعدم وجود الجدول فاحذفه.
```

---

## 4) تشغيل الـ 3 Migrations (الأهم)
الملفات في `supabase/migrations/` (وأيضًا مرفقة منفصلة):
1. `20261113210000_guess_character_foundation.sql`
2. `20261113210100_guess_character_functions.sql`
3. `20261113210200_guess_character_seed.sql`

لكل ملف **بالترتيب**:
1. افتح الملف بأي محرر نصوص، **انسخ كامل المحتوى** (Ctrl+A ثم Ctrl+C).
2. Supabase → **SQL Editor → New query** → الصق → **Run**.
3. قد تظهر نافذة تحذير "destructive operations" لأن الملفات تحتوي `DROP ... IF EXISTS` (تُستخدم لإعادة التعريف الآمن لسياسات/قيود تخصّ الجداول الجديدة والـ guard). هذا متوقع؛ اختر **Run this query**.
4. النتيجة الصحيحة: **Success** بلا أخطاء حمراء.
   - إن ظهر خطأ: **توقف**، انسخ نص الخطأ كاملًا، ولا تشغّل الملف التالي.
   - الملفات **آمنة لإعادة التشغيل** (idempotent)، فتكرار تشغيل نفس الملف لا يضر.

شرح كل ملف والمخاطر في `docs/MIGRATIONS_AR.md`.

### التحقق بعد التشغيل (قراءة فقط)
```sql
-- 1) الشخصيات: المتوقع 45
select count(*) from characters;

-- 2) الدوال الجديدة: المتوقع 21 (create_character_room + 20 دالة char_...)
select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and (p.proname like 'char\_%' or p.proname = 'create_character_room');

-- 3) القيد على نوع الغرفة يجب أن يحتوي guess_character
select conname, pg_get_constraintdef(oid) from pg_constraint
where conrelid = 'public.rooms'::regclass and contype = 'c';

-- 4) حاوية الصور
select id, public from storage.buckets where id = 'character-images';

-- 5) الـ Realtime: يجب أن يظهر character_events
select tablename from pg_publication_tables
where pubname = 'supabase_realtime' and tablename = 'character_events';

-- 6) أعداد الصفوف القديمة يجب أن تساوي "اللقطة قبل" (راجع الخطوة 3)
select 'rooms' as t, count(*) from rooms
union all select 'players', count(*) from players
union all select 'games', count(*) from games;
```
النتيجة (3) تعرض عدة قيود على جدول `rooms`؛ المهم أن يوجد **قيد واحد فقط** يذكر `game_type` (اسمه `rooms_game_type_check`) وفيه `'risk_it'` و`'bus_complete'` و`'guess_character'`. لو رأيت قيدًا آخر قديمًا باسم مختلف يحتوي قيمتين فقط، **أرسله لي قبل أي لعب**.

---

## 5) إعداد Supabase للواجهة (المفاتيح)
1. Supabase → **Project Settings → API** (أو **API Keys** في الواجهة الأحدث).
2. انسخ:
   - **Project URL** (يبدو `https://xxxxxxxx.supabase.co`) ← هذا `VITE_SUPABASE_URL`
   - **anon public key** (أو **publishable key** في الواجهة الحديثة) ← هذا `VITE_SUPABASE_ANON_KEY`
3. ❌ **لا تستخدم أبدًا** مفتاح `service_role` أو `secret` في الواجهة أو في Vercel بمتغير يبدأ بـ `VITE_`؛ هذا المفتاح يتجاوز كل قواعد الأمان.
4. تأكد أن **Realtime** مفعّل للمشروع (مفعّل افتراضيًا). الجدول `character_events` يضيفه الـ Migration تلقائيًا.

ملف `.env` للتجربة المحلية (اختياري) في جذر المشروع:
```
VITE_SUPABASE_URL=https://xxxxxxxx.supabase.co
VITE_SUPABASE_ANON_KEY=eyJ...المفتاح_العام...
```
تشغيل محلي للتأكد قبل Vercel:
```bash
npm install
npm run dev
```
ثم افتح الرابط الذي يظهر (عادة `http://localhost:5173`).

---

## 6) إنشاء حساب Admin ورفع الصور
### أ) إنشاء مستخدم
1. Supabase → **Authentication → Users → Add user → Create new user**.
2. اكتب بريدك وكلمة مرور **قوية**، وفعّل **Auto Confirm User**.

### ب) إضافته لقائمة المسؤولين
SQL Editor:
```sql
insert into public.bus_admins (user_id)
select id from auth.users where email = 'ضع_بريدك_هنا@example.com'
on conflict do nothing;

select * from public.bus_admins;  -- يجب أن يظهر مستخدمك
```
> قائمة `bus_admins` هي قائمة المسؤولين الوحيدة للمنصة (يستخدمها Bus Complete أيضًا). كل من فيها يستطيع إدارة الشخصيات.

### ج) (موصى به) إيقاف التسجيل العام
**Authentication → Sign In / Providers → إيقاف "Allow new users to sign up"** بعد إنشاء حسابك. اللاعبون لا يستخدمون تسجيل الدخول أصلًا، فلن يتأثروا.

### د) الدخول للوحة التحكم
افتح: `https://رابط-موقعك/?admin=characters` ← سجّل الدخول ببريدك وكلمة المرور.
- لو ظهرت "ليس ضمن قائمة المسؤولين": راجع خطوة (ب).

### هـ) رفع صور الشخصيات
1. اضغط ✏️ بجانب الشخصية → **رفع صورة** → اختر الملف → **حفظ الشخصية**.
2. الشروط: JPG أو PNG أو WEBP، حتى **2 ميجابايت**، يفضّل مربعة (تُعرض مربعة).
3. ارفع فقط صورًا **لديك حق استخدامها** (مثل صور مرخّصة أو ملكك).
4. الصور تُخزَّن باسم عشوائي في حاوية `character-images`، فلا يكشف اسم الملف الإجابة.
5. بدون صورة: يعرض الوضع Classic شكلًا رماديًا محايدًا، وMystery لا يحتاج صورًا.

### و) إضافة شخصية جديدة
**شخصية جديدة** ← الاسم بالعربية، التصنيف، **3 تلميحات على الأقل** (من الأعم للأخص)، إجابات بديلة (كل واحدة بسطر)، حقائق نعم/لا ← **حفظ**.

---

## 7) النشر على Vercel من الصفر
### أ) تجهيز الكود
1. فك ضغط `risk-it-guess-character.zip` فيظهر مجلد `project`.
2. (مهم) تأكد أن `.env` لن يُرفع: الملف `.gitignore` يحتوي السطر `.env` ✅ (موجود).

### ب) رفعه إلى GitHub
1. على github.com: **New repository** → اسمه مثل `risk-it` → اختر **Private** → Create.
2. من الطرفية داخل مجلد `project`:
   ```bash
   git init
   git add .
   git status        # تأكد أن .env و node_modules و dist غير موجودة في القائمة
   git commit -m "RISK IT + Guess The Character"
   git branch -M main
   git remote add origin https://github.com/اسمك/risk-it.git
   git push -u origin main
   ```
   (بدون خبرة بـ Git: استخدم تطبيق **GitHub Desktop**: File → Add local repository → اختر مجلد `project` → Commit → Publish repository. ولا تستخدم رفع الملفات من المتصفح لأن عدد الملفات كبير.)

### ج) الاستيراد في Vercel
1. vercel.com → **Add New → Project** → **Import** للمستودع.
2. الإعدادات (Vercel يكتشفها غالبًا تلقائيًا):
   - **Framework Preset:** Vite
   - **Build Command:** `npm run build`
   - **Output Directory:** `dist`
   - **Install Command:** الافتراضي
3. افتح **Environment Variables** وأضف (لكل البيئات Production/Preview/Development):

   | الاسم | القيمة |
   |---|---|
   | `VITE_SUPABASE_URL` | Project URL من الخطوة 5 |
   | `VITE_SUPABASE_ANON_KEY` | مفتاح anon/publishable العام |
4. اضغط **Deploy** وانتظر دقيقة تقريبًا. تحصل على رابط مثل `https://risk-it.vercel.app`.

### د) بعد النشر
- لو غيّرت أي متغير بيئة لاحقًا: **Deployments → ⋯ → Redeploy**.
- **Settings → General → Node.js Version:** اختر 22.x إذا فشل البناء برسالة عن إصدار Node (Vite 7 يحتاج Node 20.19+ أو 22.12+).
- (اختياري) نطاق خاص: **Settings → Domains**.
- (اختياري) Supabase → **Authentication → URL Configuration → Site URL** = رابط Vercel.

### بديل بلا GitHub (Vercel CLI)
```bash
npm i -g vercel
cd project
vercel            # اتبع الأسئلة
vercel env add VITE_SUPABASE_URL
vercel env add VITE_SUPABASE_ANON_KEY
vercel --prod
```

> المشروع كان مجهزًا سابقًا لـ Cloudflare Pages (ملف `_redirects` داخل `dist`). هذا الملف **غير لازم** على Vercel، والمجلد `dist` لا يُرفع أصلًا لأن Vercel يبنيه بنفسه.

---

## 8) أعطال شائعة وحلولها

| العَرَض | السبب المرجّح | الحل |
|---|---|---|
| صفحة بيضاء أو خطأ `supabaseUrl is required` | متغيرات البيئة غير مضافة أو بأسماء خاطئة | أضفها بالاسم الدقيق ثم **Redeploy** |
| "تعذر الاتصال بالخادم" عند إنشاء غرفة خمن الشخصية | الـ Migrations لم تُشغَّل | نفّذ الخطوة 4 وراجع التحقق |
| إنشاء الغرفة يفشل بخطأ قيد `rooms_game_type_check` | قيد قديم بقيمتين فقط | أرسل لي نتيجة استعلام التحقق رقم 3 |
| لا تظهر الصور | الحاوية غير عامة أو لم تُرفع صورة | تحقق من استعلام الحاوية (`public = true`) وأعد رفع الصورة |
| "ليس ضمن قائمة المسؤولين" | لم تُضف لـ `bus_admins` | نفّذ الخطوة 6-ب |
| الشاشات لا تتحدث لحظيًا عند أحد اللاعبين | انقطاع Realtime أو الشبكة | الواجهة تعيد المحاولة وتعمل تحديث احتياطي كل ~6 ثوانٍ؛ تحقق من الاستعلام رقم 5 |
| فشل البناء على Vercel | إصدار Node | اضبط Node 22.x |
| المشروع المجاني متوقف | Supabase يوقف المشاريع الخاملة | افتحه من لوحة Supabase واضغط Restore |

---

## 9) بعد النشر
نفّذ قائمة الاختبارات في `docs/TEST_CHECKLIST_AR.md` من **جهازين مختلفين** قبل دعوة الأصدقاء.
