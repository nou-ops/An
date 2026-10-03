# التشخيص النهائي — ولماذا لم يبدأ التشغيل

## السبب مؤكَّد من صورة مستودعك

مستودع `nou-ops/Fieldwatch` (خاص) في الجذر يحتوي:
```
FieldwatchApp/Sources ▸
FieldwatchCore ▸
docs ▸   scripts ▸
project.yml · README-AR.md · UPLOAD-AR.md · PORT-STATUS-AR.md · JAILBREAK-AR.md
Fieldwatch-Jailbreak.entitleme...
```
و**لا يوجد مجلد `.github` إطلاقًا**.

### السبب 1 — المؤكَّد: ملف السير لم يُرفع
متصفح GitHub **يتجاهل المجلدات التي تبدأ بنقطة** (`.github`) عند السحب والإفلات، **وبلا أي رسالة خطأ**. فالمستودع بلا ملف سير ⇒ لا شيء يُشغَّل. هذا كل ما في الأمر.

### السبب 2 — ثانوي: البنية مسطّحة
محتوى مجلد `ios/` رُفع في **جذر** المستودع (لا داخل `ios/`)، لذا مسارات السير القديم (`working-directory: ios`) لا تطابقه. **عالجته**: النسخة الجديدة في هذه الحزمة مضبوطة على بنيتك الحالية بالحرف (بلا `ios/`، والـ IPA يخرج إلى `out/`).

> ملاحظة: المستودع **ليس fork** (0 forks ولا لافتة fork) ⇒ لا حاجة لزر «I understand my workflows». ومهمّة `smoke` ستطبع `project.yml` كي نرى ما عدّلته فيه.

---

## الحل الآن: ملف واحد ينطلق البناء

1. افتح مستودعك ← **Add file → Create new file**.
2. في **خانة اسم الملف** اكتب المسار كاملًا (اكتب الشرطة المائلة `/` بيدك، GitHub يبني المجلدات):
   ```
   .github/workflows/ios-unsigned-ipa.yml
   ```
3. الصق محتوى `.github/workflows/ios-unsigned-ipa.yml` من هذه الحزمة (أو من الملف المعروض في نافذة العرض عندك).
4. **Commit changes** ← ذهب.
5. اذهب إلى **Actions**: سيبدأ التشغيل تلقائيًا (نوعاها `push` و`workflow_dispatch`). إن لم يبدأ، اضغط *iOS unsigned IPA* ← **Run workflow**.

النتيجة المتوقّعة: مهمّة **Smoke** تخضرّ في ثوانٍ وتطبع البنية، ثم مهمّة الاختبارات (41/41)، ثم **بناء IPA** — ومدته 5–10 دقائق. ثم:

**Actions ← آخر تشغيل ← قسم Artifacts (أسفل الصفحة) ← `Fieldwatch-unsigned-ipa`** ⇒ داخله `Fieldwatch-unsigned.ipa`.

---

## إن فشل شيء

| ما تراه | المعنى | ما تفعله |
|---|---|---|
| مهمّة Smoke حمراء أو لا تظهر | السير يعمل فعلًا لكن المسارات مختلفة عمّا في المستودع | أرسل لي سجل Smoke (يطبع البنية و`project.yml`) |
| لا تبويب Actions أو شريط تحذيري | Actions معطّلة على المستودع | Settings → Actions → General → **Allow all actions** |
| رسالة عن Billing/الفواتير | انتهت حصة الدقائق | اجعل المستودع **Public** (macOS مجاني بلا حدود للمستودعات العامة)، أو انتظر التجديد الشهري |
| `xcode-build-log` موجود بعد فشل | خطأ في البناء أو في `project.yml` | أرسل الملف كما هو — أصلحه وأعيد الحزمة |

---

## لاحقًا: ترتيب أنيق (اختياري)

إن أردت إرجاع البنية المرتّبة `ios/…` كما في التوثيق:
1. أنشئ مجلد `ios` في المستودع وانقل إليه: `FieldwatchApp`, `FieldwatchCore`, `docs`, `scripts`, `project.yml`, وكل ملفات `*-AR.md` و`Fieldwatch-Jailbreak.entitlements` (من واجهة GitHub: افتح كل مجلد ← زر `…` ← Rename، وأضف `ios/` قبل الاسم — أو استعمل GitHub Desktop).
2. استبدل محتوى ملف السير بمحتوى `ios/docs/workflow-for-ios-layout.yml`.

**لكن لا تفعل ذلك قبل أن يُنتج البناء الأول ملف IPA** — لا تُغيّر شيئًا يعمل.
