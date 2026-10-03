# ارفع هذا إلى مستودعك (بنيتك المسطّحة) — 3 خيارات مرتّبة بالأسهل

المستودع عندك حاليًا **مسطّح**: في الجذر `FieldwatchCore/ · FieldwatchApp/ · docs/ · scripts/ · project.yml`.
لذلك هذه الحزمة **مسطّحة مثلها تمامًا** — كل ملف هنا يذهب إلى مكانه المطابق في الجذر.

> ⚠️ **الفرق عن الحزمة المرتّبة**: لا ترفع مجلدًا اسمه `ios` إلى مستودعك — عندك الملفات في الجذر.
> إن رفعت `ios/` ستتكوّن بنيتان متداخلتان ولن يجد السير ملفاته.

---

## الخيار 1 — ملف واحد فقط (الأسرع على الهاتف، ويكفي لبدء البناء) ⭐

**ارفع ملفًا واحدًا فقط**، والبناء سيُنتج كل شيء (IPA + DEB) لأنه ملف **مكتفٍ بذاته** (لا يحتاج أي سكربت آخر):

1. في مستودعك: **Add file → Create new file**
2. اكتب في خانة الاسم بالكامل:
   ```
   .github/workflows/ios-unsigned-ipa.yml
   ```
   (اكتب الشرطة المائلة بيدك — GitHub ينشئ المجلدات تلقائيًا)
3. **الصق محتوى** `WORKFLOW-SELF-CONTAINED.yml` (الموجود في هذه الحزمة، ومفتوح أمامك في العارض).
4. **Commit changes** ← سيتشغّل البناء وحده خلال ثوانٍ.

الناتج المتوقّع في Artifacts:
| الملف | لمن |
|---|---|
| `Fieldwatch-1.1.17-rootless.deb` | jailbreak حديث — **الخيار الأول** |
| `Fieldwatch-1.1.17-rootful.deb` | jailbreak قديم |
| `Fieldwatch-trollstore.ipa` | TrollStore/AppSync |
| `Fieldwatch-unsigned.ipa` | تثبيت عادي |

> هذا الخيار يكفي فعلًا. باقي الملفات في هذه الحزمة **تحسينات** (شاشة Wi-Fi، وثائق، سكربتات محلية) — أضِفها لاحقًا متى أردت.

---

## الخيار 2 — كل شيء (على حاسوب أو GitHub Desktop)

1. نزّل GitHub Desktop ← **Clone repository** ← اختر مستودعك.
2. افتح مجلد النسخة (Repository → Show in Explorer/Finder).
3. **انسخ محتوى هذه الحزمة** (كل ما تراه هنا) داخل الجذر، مع **دمج** المجلدات واستبدال الملفات المكرّرة.
4. GitHub Desktop ← Summary: `ios port + build workflow` ← **Commit to main** ← **Push origin**.
5. Actions ← *iOS build…* ← Run workflow (أو سيبدأ وحده).

### ما الذي يتغيّر في مستودعك بهذا الخيار؟
| المسار | جديد / تحديث |
|---|---|
| `.github/workflows/ios-unsigned-ipa.yml` | **جديد** (نسخة كاملة: smoke + tests + build؛ تعتمد على السكربتات أدناه) |
| `scripts/build-app.sh` · `build-ipa.sh` · `build-deb.sh` · `build-all.sh` | **جديد** |
| `scripts/build-unsigned-ipa.sh` | **تحديث** (صار مُغلِّفًا ينادي الاثنين) |
| `entitlements/00-none · 10-unsandbox · 20-platform` | **جديد** |
| `FieldwatchApp/Sources/WiFiScanner.swift` | **جديد** |
| `FieldwatchApp/Sources/LiveView.swift` | **تحديث** |
| `Fieldwatch-Jailbreak.entitlements` | **احذفه** (استُبدل بمجلد `entitlements/`) |
| `docs/IPA-vs-DEB-AR.md` · `docs/verification-swift-test.txt` · `docs/workflow-for-ios-layout.yml` | **جديد** |
| `FieldwatchCore/**` (المصادر والاختبارات) | **تحديث** — غيرها بأكملها لضمان التطابق |
| `project.yml` | **تحديث** (يحفظ إعدادك الحالي + تثبيت حزمة XcodeGen) |

---

## الخيار 3 — عميل Git على الهاتف

تطبيق **Working Copy** (متجر آبل) ينسخ المستودع ويحفظ بنية المجلدات (بما فيها `.github`) ثم Commit/Push. مناسب إن أردت البقاء على iPhone بلا حاسوب وبلا إنشاء ملفات يدويًا.

---

## بعد نزول الـ Artifacts

1. نزّل `Fieldwatch-unsigned.ipa` ← ثبّته بـ **TrollStore** أو **AppSync** ← افتح التطبيق ← اضغط **«تشخيص Wi-Fi (probe)»** ← أرسل لي الناتج.
2. تحقق من نوع الـ jailbreak: `ls -d /var/jb` — إن وُجد ⇒ **rootless** (النسخة الأولى)، وإن لم يوجد ⇒ **rootful**.
3. ثبّت الـ deb بـ Sileo/Filza ← تثبيت دائم نظيف. والتفاصيل في `docs/IPA-vs-DEB-AR.md`.

## إن فشل البناء

كل تشغيل يرفع Artifact باسم **`Fieldwatch-build`** يحتوي ما نجح + `fw-tests.log`، وفي صفحة التشغيل **Summary** ملخّص الناتج. أرسل لي آخر 60 سطرًا من السجل كما هو — أصلح وأعيد الحزمة.
