/*
# RISK IT - Phase 2: question bank part 2

1. Data added
- 72 more questions for math, puzzles and logic, visual challenges (image questions), speed challenges, funny challenges, and crazy challenges. Each category has 3 questions per difficulty.
- Visual challenges use real photo URLs returned by the image search. Each photo is used once.

2. Fix
- Corrects one answer option in part 1 that was typed with mixed alphabets.

3. Safety
- Idempotent: prompts are unique and existing rows are skipped.
*/

UPDATE questions SET options = '["ألماتي","أستانا","طشقند","بيشكيك"]'::jsonb
WHERE prompt = 'ما عاصمة كازاخستان الحالية؟';

INSERT INTO questions (category, difficulty, kind, prompt, options, answer_index, image_url, time_limit) VALUES
('math', 'easy', 'multiple_choice', 'كم يساوي 7 × 8؟', '["56","54","58","48"]', 0, NULL, NULL),
('math', 'easy', 'multiple_choice', 'ما ناتج 15 + 27؟', '["42","41","43","52"]', 0, NULL, NULL),
('math', 'easy', 'true_false', 'العدد 2 هو العدد الأولي الزوجي الوحيد.', '["صح","خطأ"]', 0, NULL, NULL),
('math', 'medium', 'multiple_choice', 'ما قيمة 12 تربيع؟', '["144","124","156","134"]', 0, NULL, NULL),
('math', 'medium', 'multiple_choice', 'ما الجذر التربيعي للعدد 225؟', '["15","25","13","18"]', 0, NULL, NULL),
('math', 'medium', 'true_false', 'مجموع زوايا المثلث يساوي 180 درجة.', '["صح","خطأ"]', 0, NULL, NULL),
('math', 'hard', 'multiple_choice', 'كم قيمة 2 أس 10؟', '["1024","512","2048","1000"]', 0, NULL, NULL),
('math', 'hard', 'multiple_choice', 'ما قيمة π تقريبًا إلى منزلتين عشريتين؟', '["3.14","3.41","3.12","3.16"]', 0, NULL, NULL),
('math', 'hard', 'multiple_choice', 'كم عدد أضلاع الشكل السداسي؟', '["6","7","8","5"]', 0, NULL, NULL),
('math', 'insane', 'multiple_choice', 'ما مجموع الأعداد من 1 إلى 100؟', '["5050","5000","4950","5150"]', 0, NULL, NULL),
('math', 'insane', 'multiple_choice', 'ما قيمة 0! (صفر مضروب)؟', '["1","0","غير معرّف","10"]', 0, NULL, NULL),
('math', 'insane', 'multiple_choice', 'ما المشتقة الأولى للدالة x²؟', '["2x","x","2","x²"]', 0, NULL, NULL),

('puzzles', 'easy', 'riddle', 'ما الشيء الذي كلما أخذت منه كبر؟', '["الحفرة","الكرة","الماء","الظل"]', 0, NULL, NULL),
('puzzles', 'easy', 'riddle', 'ما الشيء الذي له أسنان ولا يعض؟', '["المشط","المنشار","السمكة","الشوكة"]', 0, NULL, NULL),
('puzzles', 'easy', 'true_false', 'إذا كانت أ أكبر من ب، وكانت ب أكبر من ج، فإن أ أكبر من ج.', '["صح","خطأ"]', 0, NULL, NULL),
('puzzles', 'medium', 'riddle', 'ما الشيء الذي يمشي بلا أرجل ويبكي بلا عيون؟', '["السحاب","النهر","الريح","الحجر"]', 0, NULL, NULL),
('puzzles', 'medium', 'multiple_choice', 'إذا احتاجت 3 قطط إلى 3 دقائق لاصطياد 3 فئران، فكم دقيقة تحتاج 100 قطة لاصطياد 100 فأر؟', '["3","100","33","1"]', 0, NULL, NULL),
('puzzles', 'medium', 'true_false', 'إذا كانت كل القطط حيوانات، وكل الحيوانات تتنفس، فإن كل القطط تتنفس.', '["صح","خطأ"]', 0, NULL, NULL),
('puzzles', 'hard', 'multiple_choice', 'ما العدد التالي في المتتالية: 2، 6، 12، 20، ...؟', '["30","28","32","26"]', 0, NULL, NULL),
('puzzles', 'hard', 'multiple_choice', 'أب وابنه عمرهما معًا 60 عامًا، والأب أكبر من الابن بثلاثين عامًا، فكم عمر الابن؟', '["15","30","20","10"]', 0, NULL, NULL),
('puzzles', 'hard', 'multiple_choice', 'ما العدد التالي في المتتالية: 1، 1، 2، 3، 5، 8، ...؟', '["11","12","13","14"]', 2, NULL, NULL),
('puzzles', 'insane', 'multiple_choice', 'لديك 12 كرة متطابقة، واحدة منها أثقل قليلًا. ما أقل عدد وزنات بميزان ذي كفتين يكفي لمعرفتها؟', '["1","2","3","4"]', 2, NULL, NULL),
('puzzles', 'insane', 'riddle', 'ما الشيء الذي يعيش ما دام يُطعم، ويموت إذا سُقي؟', '["النار","الشجرة","الحيوان","الزهرة"]', 0, NULL, NULL),
('puzzles', 'insane', 'multiple_choice', 'كل الصناديق الثلاثة معنونة خطأ. أي صندوق تسحب منه قطعة واحدة لتعرف محتوى الصناديق كلها؟', '["الصندوق المعنون مختلط","الصندوق المعنون تفاح","الصندوق المعنون برتقال","أي صندوق لا فرق"]', 0, NULL, NULL),

('visual', 'easy', 'image', 'ما المعلم الظاهر في الصورة؟', '["أهرامات الجيزة","معبد الكرنك","البتراء","الكولوسيوم"]', 0, 'https://images.pexels.com/photos/31133003/pexels-photo-31133003.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),
('visual', 'easy', 'image', 'ما المعلم الظاهر في الصورة؟', '["برج إيفل","برج بيزا","تمثال الحرية","برج لندن"]', 0, 'https://images.pexels.com/photos/16496484/pexels-photo-16496484.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),
('visual', 'easy', 'image', 'ما الحيوان الظاهر في الصورة؟', '["أسد","نمر","فهد","دب"]', 0, 'https://images.pexels.com/photos/7343161/pexels-photo-7343161.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),
('visual', 'medium', 'image', 'في أي دولة يقع هذا المعلم؟', '["مصر","الأردن","إيطاليا","المكسيك"]', 0, 'https://images.pexels.com/photos/28013729/pexels-photo-28013729.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),
('visual', 'medium', 'image', 'في أي مدينة يقع هذا المعلم؟', '["باريس","روما","لندن","مدريد"]', 0, 'https://images.pexels.com/photos/929313/pexels-photo-929313.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),
('visual', 'medium', 'image', 'في أي موطن يعيش هذا الحيوان غالبًا؟', '["السافانا والسهول العشبية","الغابات الاستوائية المطيرة","الصحراء القطبية","أعماق المحيطات"]', 0, 'https://images.pexels.com/photos/12118194/pexels-photo-12118194.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),
('visual', 'hard', 'image', 'ما الحيوان الظاهر في الصورة بجانب الأهرامات؟', '["الجمل","الحصان","الفيل","الزرافة"]', 0, 'https://images.pexels.com/photos/15127142/pexels-photo-15127142.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),
('visual', 'hard', 'image', 'في أي عام اكتمل بناء هذا البرج لمعرض باريس العالمي؟', '["1889","1900","1850","1920"]', 0, 'https://images.pexels.com/photos/5976924/pexels-photo-5976924.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),
('visual', 'hard', 'image', 'إلى أي عائلة حيوانية ينتمي هذا الحيوان؟', '["السنوريات (القطط)","الكلاب","الدببة","الثعالب"]', 0, 'https://images.pexels.com/photos/20335124/pexels-photo-20335124.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),
('visual', 'insane', 'image', 'في أي فترة تقريبًا بُني هرم خوفو؟', '["الألفية الثالثة قبل الميلاد","الألفية الأولى الميلادية","القرن الخامس عشر الميلادي","القرن الثاني الميلادي"]', 0, 'https://images.pexels.com/photos/35549794/pexels-photo-35549794.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),
('visual', 'insane', 'image', 'ما اسم المهندس الذي يُنسب إليه تصميم هذا البرج؟', '["غوستاف إيفل","غوستاف كليمت","غوستاف فلوبير","غوستاف مايلر"]', 0, 'https://images.pexels.com/photos/31482953/pexels-photo-31482953.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),
('visual', 'insane', 'image', 'ما الاسم العلمي لهذا الحيوان؟', '["Panthera leo","Felis leo","Canis leo","Leo maximus"]', 0, 'https://images.pexels.com/photos/15289215/pexels-photo-15289215.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', NULL),

('speed', 'easy', 'speed', 'بسرعة: 9 + 6 = ؟', '["15","14","16","13"]', 0, NULL, 8),
('speed', 'easy', 'speed', 'أي عدد هو الأكبر؟', '["999","1001","990","1010"]', 3, NULL, 8),
('speed', 'easy', 'speed', 'ما عكس كلمة "أمام"؟', '["خلف","يمين","يسار","فوق"]', 0, NULL, 6),
('speed', 'medium', 'speed', 'ما ناتج 12 × 11؟', '["132","121","144","122"]', 0, NULL, 8),
('speed', 'medium', 'speed', 'أي حرف يأتي بعد حرف "ج" في الأبجدية العربية؟', '["د","ح","ه","ب"]', 1, NULL, 6),
('speed', 'medium', 'speed', 'ما عاصمة إيطاليا؟', '["روما","ميلانو","نابولي","فلورنسا"]', 0, NULL, 6),
('speed', 'hard', 'speed', 'كم ناتج 17 × 3؟', '["51","41","61","53"]', 0, NULL, 6),
('speed', 'hard', 'speed', 'أي عنصر رمزه Na؟', '["الصوديوم","النيتروجين","النيكل","النيون"]', 0, NULL, 6),
('speed', 'hard', 'speed', 'ما أسرع حيوان على اليابسة؟', '["الفهد","الأسد","الحصان","الغزال"]', 0, NULL, 6),
('speed', 'insane', 'speed', 'بسرعة: 2 أس 8 = ؟', '["256","128","512","64"]', 0, NULL, 5),
('speed', 'insane', 'speed', 'كم عدد ألوان قوس قزح المعروفة؟', '["7","5","6","8"]', 0, NULL, 5),
('speed', 'insane', 'speed', 'كم ثانية في الساعة الواحدة؟', '["3600","60","1440","360"]', 0, NULL, 5),

('funny', 'easy', 'multiple_choice', 'ما الحيوان الذي ينام واقفًا غالبًا؟', '["الحصان","الدب","القط","البطريق"]', 0, NULL, NULL),
('funny', 'easy', 'multiple_choice', 'أي حيوان يستطيع تحريك عينيه في اتجاهين مختلفين في وقت واحد؟', '["الحرباء","البومة","الزرافة","القنفذ"]', 0, NULL, NULL),
('funny', 'easy', 'true_false', 'القطط لا تستطيع تذوق الحلويات.', '["صح","خطأ"]', 0, NULL, NULL),
('funny', 'medium', 'multiple_choice', 'أي حيوان ينام غالبًا حوالي ساعتين فقط في اليوم؟', '["الزرافة","الأسد","الكسلان","القط"]', 0, NULL, NULL),
('funny', 'medium', 'multiple_choice', 'ما الكائن الذي له ثلاثة قلوب؟', '["الأخطبوط","القط","الفيل","الدجاجة"]', 0, NULL, NULL),
('funny', 'medium', 'true_false', 'الدجاج يستطيع الطيران لمسافات طويلة.', '["صح","خطأ"]', 1, NULL, NULL),
('funny', 'hard', 'multiple_choice', 'كم عدد أرجل النحلة؟', '["4","6","8","10"]', 1, NULL, NULL),
('funny', 'hard', 'multiple_choice', 'أي طائر يستطيع الطيران إلى الخلف؟', '["الطائر الطنان","البطريق","النعامة","الدجاجة"]', 0, NULL, NULL),
('funny', 'hard', 'multiple_choice', 'ما الحيوان الذي تنمو أسنانه طوال حياته؟', '["الأرنب","القط","البطريق","الحوت الأزرق"]', 0, NULL, NULL),
('funny', 'insane', 'true_false', 'الدلافين تنام بنصف دماغها في كل مرة.', '["صح","خطأ"]', 0, NULL, NULL),
('funny', 'insane', 'multiple_choice', 'كم عدد الأدمغة لدى الأخطبوط؟', '["9","1","3","5"]', 0, NULL, NULL),
('funny', 'insane', 'multiple_choice', 'ما أطول عظم في جسم الإنسان؟', '["الفخذ","العضد","الساق","الظهر"]', 0, NULL, NULL),

('crazy', 'easy', 'true_false', 'هل يستطيع الإنسان التنفس تحت الماء بدون أي أداة؟', '["صح","خطأ"]', 1, NULL, NULL),
('crazy', 'easy', 'multiple_choice', 'كم عدد الأسنان لدى الإنسان البالغ عادةً؟', '["32","28","36","30"]', 0, NULL, NULL),
('crazy', 'easy', 'multiple_choice', 'أي حيوان هو الأسرع في الماء؟', '["السمكة الشراعية","الدولفين","التمساح","الحوت"]', 0, NULL, NULL),
('crazy', 'medium', 'multiple_choice', 'أي حيوان يستطيع تغيير لون جلده؟', '["الحرباء","الدب","الزرافة","الفيل"]', 0, NULL, NULL),
('crazy', 'medium', 'multiple_choice', 'كم قلبًا لدى الديدان الأرضية؟', '["5","1","2","3"]', 0, NULL, NULL),
('crazy', 'medium', 'true_false', 'الشمس نجم.', '["صح","خطأ"]', 0, NULL, NULL),
('crazy', 'hard', 'multiple_choice', 'ما الحيوان الذي ينام أحيانًا بعينين مفتوحتين؟', '["السمك","الدب","القط","البط"]', 0, NULL, NULL),
('crazy', 'hard', 'multiple_choice', 'ما أكبر عضو داخلي في جسم الإنسان؟', '["الكبد","الرئة","الأمعاء","القلب"]', 0, NULL, NULL),
('crazy', 'hard', 'multiple_choice', 'كم عينًا لدى العنكبوت العادي؟', '["8","6","2","10"]', 0, NULL, NULL),
('crazy', 'insane', 'multiple_choice', 'كم مرة يرمش الإنسان تقريبًا في اليوم الواحد؟', '["نحو 15 ألف مرة","نحو 500 مرة","نحو 50 ألف مرة","نحو مليون مرة"]', 0, NULL, NULL),
('crazy', 'insane', 'multiple_choice', 'ما الحيوان الأطول في العالم؟', '["الزرافة","الفيل","الجمل","الدب القطبي"]', 0, NULL, NULL),
('crazy', 'insane', 'multiple_choice', 'ما الجسم السماوي الأكبر في المجموعة الشمسية؟', '["المشتري","زحل","الشمس","الأرض"]', 2, NULL, NULL)
ON CONFLICT (prompt) DO NOTHING;
