/*
# Guess The Character - real character bank (first set)

Plain-English summary
Adds the first real set of characters (45) with factual hints, accepted spellings and the yes/no facts used for in-game questions. Every character has 4 hints, ordered from general to specific. These are real, factual entries, not placeholders.

Notes
- Images are NOT included (no licensed pictures are bundled). Upload an image for each character from the admin dashboard; until then the game shows a neutral silhouette.
- Safe to re-run: a character whose Arabic name already exists is skipped (so admin edits are never overwritten).
- Uses a helper function that exists only while this script runs and is dropped at the end.
- Facts left empty (NULL) are answered in-game as "can't answer".
*/

CREATE OR REPLACE FUNCTION public.zz_seed_character(
  p_name_ar text, p_name_en text, p_category text,
  p_male boolean, p_alive boolean, p_egyptian boolean, p_arab boolean, p_real boolean,
  p_hints text[], p_aliases text[]
) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM public.characters WHERE lower(btrim(name_ar)) = lower(btrim(p_name_ar))) THEN
    RETURN;
  END IF;
  INSERT INTO public.characters (name_ar, name_en, category, is_male, is_alive, is_egyptian, is_arab, is_real)
  VALUES (p_name_ar, p_name_en, p_category, p_male, p_alive, p_egyptian, p_arab, p_real)
  RETURNING id INTO v_id;
  INSERT INTO public.character_hints (character_id, position, text_ar)
  SELECT v_id, t.ord::integer, t.h FROM unnest(p_hints) WITH ORDINALITY AS t(h, ord);
  INSERT INTO public.character_aliases (character_id, alias_text)
  SELECT v_id, a FROM (SELECT DISTINCT lower(btrim(x)) AS a FROM unnest(p_aliases) AS x) d
  WHERE a <> '' AND a <> lower(btrim(p_name_ar)) AND a <> lower(btrim(coalesce(p_name_en, '')));
END $f$;

SELECT public.zz_seed_character('محمد صلاح', 'Mohamed Salah', 'football', true, true, true, true, true, ARRAY['لاعب كرة قدم', 'مصري الجنسية', 'لعب في الدوري الإنجليزي الممتاز', 'يلعب في مركز الهجوم']::text[], ARRAY['صلاح', 'mohamed salah', 'mo salah', 'salah', 'محمد صلاح']::text[]);
SELECT public.zz_seed_character('ليونيل ميسي', 'Lionel Messi', 'football', true, true, false, false, true, ARRAY['لاعب كرة قدم', 'أرجنتيني الجنسية', 'لعب في برشلونة سنوات طويلة', 'قاد منتخب بلاده للتتويج بكأس العالم 2022']::text[], ARRAY['ميسي', 'ليو ميسي', 'messi', 'leo messi']::text[]);
SELECT public.zz_seed_character('كريستيانو رونالدو', 'Cristiano Ronaldo', 'football', true, true, false, false, true, ARRAY['لاعب كرة قدم', 'برتغالي الجنسية', 'لعب في مانشستر يونايتد وريال مدريد ويوفنتوس', 'أكثر لاعب تسجيلاً للأهداف الدولية في التاريخ']::text[], ARRAY['رونالدو', 'كريستيانو', 'ronaldo', 'cr7']::text[]);
SELECT public.zz_seed_character('محمد أبو تريكة', 'Mohamed Aboutrika', 'football', true, true, true, true, true, ARRAY['لاعب كرة قدم سابق', 'مصري الجنسية', 'لعب في النادي الأهلي المصري', 'لُقّب بـ«الماجيكو»']::text[], ARRAY['ابو تريكة', 'أبو تريكة', 'تريكة', 'aboutrika', 'abou treika', 'magico']::text[]);
SELECT public.zz_seed_character('زين الدين زيدان', 'Zinedine Zidane', 'football', true, true, false, false, true, ARRAY['لاعب كرة قدم سابق ومدرب', 'فرنسي من أصول جزائرية', 'سجّل هدفين في نهائي كأس العالم 1998', 'درّب ريال مدريد وفاز معه بدوري أبطال أوروبا ثلاث مرات متتالية']::text[], ARRAY['زيدان', 'zidane', 'zizou']::text[]);
SELECT public.zz_seed_character('كيليان مبابي', 'Kylian Mbappé', 'football', true, true, false, false, true, ARRAY['لاعب كرة قدم', 'فرنسي الجنسية', 'لعب في باريس سان جيرمان وريال مدريد', 'فاز بكأس العالم 2018 وعمره 19 عامًا']::text[], ARRAY['مبابي', 'كيليان', 'mbappe', 'kylian mbappe']::text[]);
SELECT public.zz_seed_character('نيمار', 'Neymar', 'football', true, true, false, false, true, ARRAY['لاعب كرة قدم', 'برازيلي الجنسية', 'لعب في برشلونة وباريس سان جيرمان', 'لعب في الدوري السعودي مع الهلال']::text[], ARRAY['نيمار جونيور', 'neymar jr', 'neymar']::text[]);
SELECT public.zz_seed_character('عمرو دياب', 'Amr Diab', 'arab_artists', true, true, true, true, true, ARRAY['مطرب مصري', 'يُلقب بـ«الهضبة»', 'من مواليد مدينة بورسعيد', 'غنّى «تملّي معاك»']::text[], ARRAY['عمرو', 'الهضبة', 'amr diab']::text[]);
SELECT public.zz_seed_character('أم كلثوم', 'Umm Kulthum', 'arab_artists', false, false, true, true, true, ARRAY['مطربة عربية من القرن العشرين', 'مصرية الجنسية', 'لُقّبت بـ«كوكب الشرق»', 'غنّت «الأطلال» و«أنت عمري»']::text[], ARRAY['ام كلثوم', 'كوكب الشرق', 'umm kulthum', 'oum kalthoum', 'om kalthoum']::text[]);
SELECT public.zz_seed_character('فيروز', 'Fairuz', 'arab_artists', false, NULL, false, true, true, ARRAY['مطربة عربية', 'لبنانية الجنسية', 'لُقّبت بـ«جارة القمر»', 'غنّت «سألوني الناس» و«زهرة المدائن»']::text[], ARRAY['فيروز', 'fairuz', 'fairouz', 'fayrouz']::text[]);
SELECT public.zz_seed_character('عبد الحليم حافظ', 'Abdel Halim Hafez', 'arab_artists', true, false, true, true, true, ARRAY['مطرب وممثل مصري', 'من نجوم القرن العشرين', 'لُقّب بـ«العندليب الأسمر»', 'غنّى «على حسب وداد قلبي»']::text[], ARRAY['عبدالحليم حافظ', 'عبد الحليم', 'عبدالحليم', 'العندليب', 'العندليب الاسمر', 'abdel halim hafez']::text[]);
SELECT public.zz_seed_character('كاظم الساهر', 'Kadim Al Sahir', 'arab_artists', true, true, false, true, true, ARRAY['مطرب عربي', 'عراقي الجنسية', 'يُلقب بـ«القيصر»', 'غنّى «زيديني عشقًا»']::text[], ARRAY['كاظم', 'القيصر', 'kazem el saher', 'kadim al sahir', 'kazem al saher']::text[]);
SELECT public.zz_seed_character('تامر حسني', 'Tamer Hosny', 'arab_artists', true, true, true, true, true, ARRAY['مطرب وممثل مصري', 'يُلقب بـ«نجم الجيل»', 'قدّم فيلم «عمر وسلمى»', 'اسمه الأول يبدأ بحرف التاء']::text[], ARRAY['تامر', 'نجم الجيل', 'tamer hosny']::text[]);
SELECT public.zz_seed_character('محمد عبد الوهاب', 'Mohamed Abdel Wahab', 'arab_artists', true, false, true, true, true, ARRAY['موسيقار ومطرب عربي', 'مصري الجنسية', 'لُقّب بـ«موسيقار الأجيال»', 'غنّى «الجندول» و«من غير ليه»']::text[], ARRAY['محمد عبدالوهاب', 'عبد الوهاب', 'عبدالوهاب', 'موسيقار الاجيال', 'mohamed abdel wahab']::text[]);
SELECT public.zz_seed_character('مايكل جاكسون', 'Michael Jackson', 'world_celebrities', true, false, false, false, true, ARRAY['مغنٍّ أمريكي', 'لُقّب بـ«ملك البوب»', 'اشتهر بأغنية «Thriller»', 'اشتهر برقصة المشي إلى الخلف «مون ووك»']::text[], ARRAY['مايكل', 'جاكسون', 'michael jackson', 'mj', 'king of pop']::text[]);
SELECT public.zz_seed_character('إيلون ماسك', 'Elon Musk', 'world_celebrities', true, true, false, false, true, ARRAY['رجل أعمال', 'وُلد في جنوب أفريقيا', 'يرأس شركة تيسلا', 'أسّس شركة سبيس إكس']::text[], ARRAY['ايلون ماسك', 'ماسك', 'elon musk', 'musk']::text[]);
SELECT public.zz_seed_character('بيل غيتس', 'Bill Gates', 'world_celebrities', true, true, false, false, true, ARRAY['رجل أعمال أمريكي', 'شارك في تأسيس شركة برمجيات عملاقة', 'شركته أنتجت نظام «ويندوز»', 'أسّس مؤسسة خيرية مع زوجته السابقة']::text[], ARRAY['بيل جيتس', 'غيتس', 'جيتس', 'bill gates', 'gates']::text[]);
SELECT public.zz_seed_character('ستيف جوبز', 'Steve Jobs', 'world_celebrities', true, false, false, false, true, ARRAY['رجل أعمال أمريكي', 'شارك في تأسيس شركة «آبل»', 'قدّم أول «آيفون» عام 2007', 'توفي عام 2011']::text[], ARRAY['جوبز', 'ستيف جابز', 'جابز', 'steve jobs', 'jobs']::text[]);
SELECT public.zz_seed_character('تايلور سويفت', 'Taylor Swift', 'world_celebrities', false, true, false, false, true, ARRAY['مغنية وكاتبة أغانٍ أمريكية', 'وُلدت عام 1989', 'أطلقت جولة «The Eras Tour»', 'من ألبوماتها «1989» و«Folklore»']::text[], ARRAY['تيلور سويفت', 'سويفت', 'taylor swift', 'swift']::text[]);
SELECT public.zz_seed_character('محمد علي كلاي', 'Muhammad Ali', 'world_celebrities', true, false, false, false, true, ARRAY['ملاكم أمريكي', 'بطل العالم للوزن الثقيل', 'اعتنق الإسلام وغيّر اسمه', 'اشتهر بعبارة «أطير كالفراشة وألسع كالنحلة»']::text[], ARRAY['محمد علي', 'كلاي', 'كاسيوس كلاي', 'muhammad ali', 'mohamed ali', 'cassius clay']::text[]);
SELECT public.zz_seed_character('عادل إمام', 'Adel Imam', 'actors', true, true, true, true, true, ARRAY['ممثل مصري', 'يُلقب بـ«الزعيم»', 'قدّم مسرحية «مدرسة المشاغبين»', 'بطل فيلم «الإرهاب والكباب»']::text[], ARRAY['عادل امام', 'الزعيم', 'adel imam', 'adel emam']::text[]);
SELECT public.zz_seed_character('أحمد زكي', 'Ahmed Zaki', 'actors', true, false, true, true, true, ARRAY['ممثل مصري راحل', 'لُقّب بـ«النمر الأسود»', 'جسّد شخصيتي جمال عبد الناصر وأنور السادات', 'بطل فيلم «البريء»']::text[], ARRAY['احمد زكي', 'النمر الاسود', 'ahmed zaki', 'ahmad zaki']::text[]);
SELECT public.zz_seed_character('سعاد حسني', 'Soad Hosny', 'actors', false, false, true, true, true, ARRAY['ممثلة مصرية', 'لُقّبت بـ«سندريلا الشاشة العربية»', 'قدّمت فيلم «خلّي بالك من زوزو»', 'اشتُهرت بالأفلام الاستعراضية']::text[], ARRAY['سعاد', 'سندريلا', 'soad hosny', 'suad hosni', 'souad hosni']::text[]);
SELECT public.zz_seed_character('توم كروز', 'Tom Cruise', 'actors', true, true, false, false, true, ARRAY['ممثل أمريكي', 'بطل سلسلة «Mission: Impossible»', 'جسّد شخصية إيثان هانت', 'شارك في فيلم «Top Gun»']::text[], ARRAY['كروز', 'tom cruise', 'cruise']::text[]);
SELECT public.zz_seed_character('ليوناردو دي كابريو', 'Leonardo DiCaprio', 'actors', true, true, false, false, true, ARRAY['ممثل أمريكي', 'حائز على الأوسكار لأفضل ممثل', 'شارك في فيلم «Titanic»', 'شارك في فيلم «Inception»']::text[], ARRAY['دي كابريو', 'ديكابريو', 'ليوناردو ديكابريو', 'leonardo dicaprio', 'dicaprio']::text[]);
SELECT public.zz_seed_character('محمد هنيدي', 'Mohamed Henedy', 'actors', true, true, true, true, true, ARRAY['ممثل كوميدي مصري', 'بطل فيلم «إسماعيلية رايح جاي»', 'بطل فيلم «صعيدي في الجامعة الأمريكية»', 'شارك في فيلم «همام في أمستردام»']::text[], ARRAY['هنيدي', 'mohamed henedy', 'mohamed henidi', 'henedy']::text[]);
SELECT public.zz_seed_character('ميكي ماوس', 'Mickey Mouse', 'cartoon', true, NULL, false, false, false, ARRAY['شخصية كرتونية', 'فأر', 'من إنتاج شركة والت ديزني', 'صديقته ميني']::text[], ARRAY['ميكي', 'ميكي ماوس', 'mickey mouse', 'mickey']::text[]);
SELECT public.zz_seed_character('سبونج بوب', 'SpongeBob SquarePants', 'cartoon', true, NULL, false, false, false, ARRAY['شخصية كرتونية', 'يعيش تحت الماء', 'يعمل طاهيًا في مطعم «كرستي كراب»', 'صديقه المقرّب باتريك']::text[], ARRAY['سبونج بوب', 'سبونجبوب', 'سبونج بوب سكوير بانتس', 'spongebob', 'spongebob squarepants']::text[]);
SELECT public.zz_seed_character('ناروتو', 'Naruto Uzumaki', 'cartoon', true, NULL, false, false, false, ARRAY['شخصية أنمي', 'نينجا شاب', 'يحلم بأن يصبح «الهوكاجي»', 'بداخله الثعلب ذو الذيول التسعة']::text[], ARRAY['ناروتو اوزوماكي', 'ناروتو أوزوماكي', 'naruto', 'naruto uzumaki']::text[]);
SELECT public.zz_seed_character('بيكاتشو', 'Pikachu', 'cartoon', true, NULL, false, false, false, ARRAY['شخصية كرتونية', 'لونه أصفر', 'من عالم «بوكيمون»', 'يطلق الصعق الكهربائي']::text[], ARRAY['بيكاتشو', 'pikachu', 'بيكاشو']::text[]);
SELECT public.zz_seed_character('كابتن ماجد', 'Captain Tsubasa', 'cartoon', true, NULL, false, false, false, ARRAY['شخصية كرتونية يابانية', 'لاعب كرة قدم', 'اسمه الياباني تسوباسا', 'أحبّه جيل الثمانينيات والتسعينيات في العالم العربي']::text[], ARRAY['ماجد', 'كابتن ماجد', 'captain majid', 'captain tsubasa', 'tsubasa', 'كابتن تسوباسا', 'تسوباسا']::text[]);
SELECT public.zz_seed_character('بوباي', 'Popeye', 'cartoon', true, NULL, false, false, false, ARRAY['شخصية كرتونية', 'بحّار', 'يأكل السبانخ ليقوى', 'حبيبته أوليف']::text[], ARRAY['بوباي', 'popeye', 'popeye the sailor']::text[]);
SELECT public.zz_seed_character('صلاح الدين الأيوبي', 'Saladin', 'historical', true, false, false, NULL, true, ARRAY['قائد عسكري وسلطان مسلم', 'عاش في القرن الثاني عشر الميلادي', 'وحّد مصر والشام تحت حكمه', 'انتصر في معركة حطين']::text[], ARRAY['صلاح الدين', 'صلاح الدين الايوبي', 'saladin', 'salah ad din', 'salahuddin']::text[]);
SELECT public.zz_seed_character('كليوباترا', 'Cleopatra', 'historical', false, false, NULL, NULL, true, ARRAY['ملكة قديمة', 'آخر حكّام الأسرة البطلمية في مصر', 'عاشت في القرن الأول قبل الميلاد', 'ارتبطت بيوليوس قيصر ثم بمارك أنطونيو']::text[], ARRAY['الملكة كليوباترا', 'كليوباتره', 'cleopatra', 'cleopatra vii']::text[]);
SELECT public.zz_seed_character('جمال عبد الناصر', 'Gamal Abdel Nasser', 'historical', true, false, true, true, true, ARRAY['رئيس مصري', 'من قادة ثورة يوليو 1952', 'أمّم قناة السويس', 'توفي عام 1970']::text[], ARRAY['جمال عبدالناصر', 'عبد الناصر', 'عبدالناصر', 'ناصر', 'abdel nasser', 'nasser', 'gamal abdel nasser']::text[]);
SELECT public.zz_seed_character('نابليون بونابرت', 'Napoleon Bonaparte', 'historical', true, false, false, false, true, ARRAY['إمبراطور وقائد عسكري', 'فرنسي وُلد في جزيرة كورسيكا', 'قاد حملة على مصر عام 1798', 'هُزم في معركة واترلو']::text[], ARRAY['نابليون', 'بونابرت', 'napoleon', 'napoleon bonaparte']::text[]);
SELECT public.zz_seed_character('ألبرت أينشتاين', 'Albert Einstein', 'historical', true, false, false, false, true, ARRAY['عالم فيزياء', 'ألماني المولد', 'صاحب النظرية النسبية', 'حصل على جائزة نوبل في الفيزياء']::text[], ARRAY['اينشتاين', 'أينشتاين', 'البرت اينشتاين', 'انشتاين', 'einstein', 'albert einstein']::text[]);
SELECT public.zz_seed_character('محمد علي باشا', 'Muhammad Ali Pasha', 'historical', true, false, NULL, NULL, true, ARRAY['حاكم مصر', 'من أصول ألبانية', 'يُعرف بمؤسس مصر الحديثة', 'تولّى الحكم في مطلع القرن التاسع عشر']::text[], ARRAY['محمد علي', 'محمد علي الكبير', 'muhammad ali pasha', 'mohamed ali pasha']::text[]);
SELECT public.zz_seed_character('طارق بن زياد', 'Tariq ibn Ziyad', 'historical', true, false, false, NULL, true, ARRAY['قائد عسكري مسلم', 'قاد الفتح الإسلامي لشبه الجزيرة الأيبيرية', 'ارتبط اسمه بجبل يحمل اسمه', 'عبر المضيق إلى الأندلس في مطلع القرن الثامن الميلادي']::text[], ARRAY['طارق بن زياد', 'طارق', 'tariq ibn ziyad', 'tariq bin ziyad']::text[]);
SELECT public.zz_seed_character('سوبر ماريو', 'Super Mario', 'games_movies', true, NULL, false, false, false, ARRAY['شخصية ألعاب فيديو', 'سبّاك إيطالي', 'تنتجه شركة نينتندو', 'شقيقه لويجي']::text[], ARRAY['ماريو', 'سوبر ماريو', 'mario', 'super mario']::text[]);
SELECT public.zz_seed_character('باتمان', 'Batman', 'games_movies', true, NULL, false, false, false, ARRAY['شخصية قصص مصورة وسينما', 'بطل خارق بلا قوى خارقة', 'يعيش في مدينة غوثام', 'اسمه الحقيقي بروس واين']::text[], ARRAY['باتمان', 'الرجل الوطواط', 'batman', 'bruce wayne', 'بروس واين']::text[]);
SELECT public.zz_seed_character('سبايدرمان', 'Spider-Man', 'games_movies', true, NULL, false, false, false, ARRAY['بطل خارق', 'يتسلق الجدران', 'لدغه عنكبوت مشعّ', 'اسمه الحقيقي بيتر باركر']::text[], ARRAY['سبايدر مان', 'الرجل العنكبوت', 'spiderman', 'spider man', 'spider-man', 'بيتر باركر', 'peter parker']::text[]);
SELECT public.zz_seed_character('هاري بوتر', 'Harry Potter', 'games_movies', true, NULL, false, false, false, ARRAY['شخصية روائية وسينمائية', 'ساحر صغير', 'يدرس في مدرسة هوغورتس', 'على جبينه ندبة على شكل برق']::text[], ARRAY['هاري بوتر', 'harry potter', 'potter', 'بوتر']::text[]);
SELECT public.zz_seed_character('جاك سبارو', 'Jack Sparrow', 'games_movies', true, NULL, false, false, false, ARRAY['شخصية سينمائية', 'قرصان', 'بطل سلسلة «قراصنة الكاريبي»', 'يقود سفينة «اللؤلؤة السوداء»']::text[], ARRAY['الكابتن جاك سبارو', 'كابتن جاك سبارو', 'جاك سيبارو', 'jack sparrow', 'captain jack sparrow']::text[]);
SELECT public.zz_seed_character('سونيك', 'Sonic the Hedgehog', 'games_movies', true, NULL, false, false, false, ARRAY['شخصية ألعاب فيديو', 'قنفذ أزرق', 'يشتهر بسرعته الفائقة', 'من إنتاج شركة «سيغا»']::text[], ARRAY['سونيك', 'sonic', 'sonic the hedgehog', 'سونيك القنفذ']::text[]);

DROP FUNCTION public.zz_seed_character(text, text, text, boolean, boolean, boolean, boolean, boolean, text[], text[]);
