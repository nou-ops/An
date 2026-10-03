# ارفع هذا إلى المستودع، وشغّل البناء

> **اقرأ أولًا إن لم يبدأ التشغيل:** الملف المجاور `WHY-NOT-RUNNING-AR.md`.

الحزمة مبنية **بنية مستودع**: فُكّها في جذر مستودعك (أو الصق محتواها فيه). الشكل الصحيح:

```
مستودعك/
├── .github/workflows/ios-unsigned-ipa.yml   ← ملف السير (مجلد بنقطة!)
├── ios/                                     ← كل شيء آخر
└── (بقية مستودع أندرويد كما هو: app/, dist/, …)
```

---

## الطريقة أ — GitHub Desktop (الأضمن، موصى بها)

فخّ سحب-وإفلات في صفحة GitHub هو أنه **يتجاهل المجلدات التي تبدأ بنقطة** مثل `.github` — لذلك يستحيل عمليًا رفع ملف السير من المتصفح بالسحب.

1. نزّل **GitHub Desktop** من `desktop.github.com` وسجّل الدخول.
2. **File → Clone repository** ← اختر مستودعك ← Clone.
3. افتح مجلد النسخة (من `Repository → Show in Explorer`)، وفُكّ فيه محتوى `Fieldwatch-ios-port.zip` (مجلدا `ios` و`.github`).
4. ارجع إلى GitHub Desktop: ستجد التغييرات مسرودة ← اكتب في **Summary**: `add ios port` ← **Commit to main** ← **Push origin**.
5. اذهب إلى **Actions** في المستودع ← ستجد التشغيل بدأ وحده خلال ثوانٍ.
   (أو: تبويب Actions ← *iOS unsigned IPA* ← **Run workflow**.)

> إن كان هذا نسخة مفرّعة (fork) ولم تظهر أي Actions: اضغط الزر الأزرق **«I understand my workflows, go ahead and enable them»** في تبويب Actions — هذه سياسة GitHub، لا خطأ في السير.

---

## الطريقة ب — رفع من المتصفح (بلا برامج)

1. **Add file → Create new file**.
2. في خانة الاسم اكتب **بالمسار الكامل**:
   ```
   .github/workflows/ios-unsigned-ipa.yml
   ```
   (GitHub ينشئ المجلدات تلقائيًا) والصق محتوى الملف، ثم **Commit changes**.
3. أعد الكرّة لباقي الملفات: أسهل طريق هو رفع مجلد `ios/` كاملًا بـ **Add file → Upload files** (مجلد `ios` لا يبدأ بنقطة، فيُقبل بالسحب)، ثم إنشاء ملفات `ios/` الفرعية إن سقط بعضها.
4. تحقّق من المسار بمفتاح واحد (بدّل الاسمين):
   ```
   https://github.com/<اسمك>/<المستودع>/blob/main/.github/workflows/ios-unsigned-ipa.yml
   ```
   إن ظهرت صفحة الـ YAML ⇒ الملف في مكانه. إن ظهر **404** ⇒ لم يُرفع.

---

## التحقق السريع من كل شيء

| الرابط (بدّل الاسمين) | يجب أن ترى |
|---|---|
| `…/blob/main/.github/workflows/ios-unsigned-ipa.yml` | صفحة الـ YAML |
| `…/tree/main/ios/FieldwatchCore` | `Package.swift` + `Sources` + `Tests` |
| `…/actions` | سير باسم **iOS unsigned IPA** (وشغّل **Run workflow** إن لم يبدأ وحده) |

## أين ملف الـ IPA؟

Actions ← التشغيل الأخير ← قسم **Artifacts** في أسفل الصفحة ← نزّل **`Fieldwatch-unsigned-ipa`** ⇒ داخله `Fieldwatch-unsigned.ipa` ← ثبّته على جهازك (TrollStore / AppSync كما في `JAILBREAK-AR.md`) ← ثم شغّل `probe()`.

## متى تفشل مهمّة البناء

يُرفع تلقائيًا **`xcode-build-log`** في قسم Artifacts لنفس التشغيل. أرسل لي ذلك الملف كما هو — أصلح الخطأ وأعيد لك الحزمة. ولن تُحجب عنك الـ IPA: مهمّة البناء تعمل بـ `if: always()`، وتسجّل الاختبارات على حدة في `core-test-log`.


---

## 🆕 للمستودع الحالي (بنيتك المسطّحة): ما الجديد الذي يجب رفعه

مستودعك الآن فيه الجذر: `FieldwatchCore/ · FieldwatchApp/ · docs/ · scripts/ · project.yml`.
أضف/استبدل هذه الملفات فقط:

| المسار في مستودعك | جديد أم تحديث |
|---|---|
| `.github/workflows/ios-unsigned-ipa.yml` | **جديد** — أنشئه بـ Create new file (اكتب المسار كاملًا) |
| `entitlements/00-none.entitlements` | **جديد** |
| `entitlements/10-unsandbox.entitlements` | **جديد** |
| `entitlements/20-platform.entitlements` | **جديد** |
| `scripts/build-app.sh` | **جديد** |
| `scripts/build-ipa.sh` | **جديد** |
| `scripts/build-deb.sh` | **جديد** |
| `scripts/build-all.sh` | **جديد** |
| `scripts/build-unsigned-ipa.sh` | **تحديث** (صار مُغلِّفًا) |
| `Fieldwatch-Jailbreak.entitlements` | **احذفه** (استُبدل بمجلد `entitlements/`) |
| `FieldwatchApp/Sources/WiFiScanner.swift` | **جديد** (شاشة Wi-Fi + زر probe) |
| `FieldwatchApp/Sources/LiveView.swift` | **تحديث** |

**نسخة احتياطية مريحة:** ارفع الملفات الأربعة داخل `scripts/` ومجلد `entitlements/` عبر رفع مجلد (ليس مخفيًا، فيُقبل بالسحب)، ثم ملف السير يدويًا كما في الأعلى.

بعد الرفع: **Actions ← iOS build (IPA + DEB) ← Run workflow**.
الناتج أربعة:
| Artifact | لمن |
|---|---|
| `Fieldwatch-deb-rootless` | jailbreak حديث (Dopamine/palera1n rootless) ← **الخيار الأول** |
| `Fieldwatch-deb-rootful` | jailbreak قديم (checkra1n) |
| `Fieldwatch-trollstore-ipa` | TrollStore/AppSync — تثبيت بنقرة مع حفظ الصلاحيات |
| `Fieldwatch-unsigned-ipa` | تثبيت عادي بلا صلاحيات خاصة |

فشل البناء؟ يُرفع `build-log-and-info` (السجل + أي حزمة بُنيت جزئيًا) — أرسله لي. والمقارنة الكاملة بين المسارين في `docs/IPA-vs-DEB-AR.md`.
