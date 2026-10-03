# IPA أم DEB؟ — الجواب لحالتك تحديدًا

## السؤال كان: نبني ملف IPA أم ملف DEB؟

**الجواب: الاثنان — لكن لكل واحد وظيفة مختلفة، وليس أحدهما بديلًا عن الآخر.**

| | **DEB** | **IPA** |
|---|---|---|
| **ما هو** | حزمة نظام يُديرها Sileo/Zebra (dpkg) | تطبيق مستخدم يُثبَّت بنقرة/سحب |
| **أين يُثبَّت** | `Applications/` كتطبيق نظام *(rootless: `/var/jb/Applications`)* | حاوية تطبيق عادي |
| **الدوام** | دائم، بلا انتهاء، ويبقى بعد إعادة التشغيل | دائم مع TrollStore/AppSync · **7 أيام** مع Apple ID مجاني |
| **الصلاحيات الخاصة والـ sandbox** | تُثبَّت في توقيع التنفيذي بـ `ldid`، والـ jailbreak يسمح بها | تُثبَّت بنفس الطريقة، وTrollStore **يحفظها** عند التثبيت |
| **الإدارة** | Sileo: تحديث/إزالة نظيفة، وسجل التغييرات | تُحذف كأي تطبيق |
| **إضافات لاحقة** | يمكن إضافة launch daemon (مفيد لمسح في الخلفية) | لا يمكن (TrollStore لا يشغّل daemons) |
| **المشاركة** | يحتاج نفس نوع الـ jailbreak (rootless/rootful) | يُعطى لأي أحد (TrollStore/AppSync) |
| **التعقيد** | يحتاج `dpkg-deb` + control + سكربتات (بنيتها لك) | أبسط ملف ممكن |
| **خطر الرفض** | معماريّة لا تطابق البادئة ⇒ رفض الحزمة | صلاحيات ممنوعة على A12+ ⇒ سقوط عند الإقلاع |

## توصيتي الصريحة

> **الأساس = DEB (rootless). والـ IPA = الاحتياطي السريع.**
> سبب اختيار DEB أساسًا: تطبيقك يحتاج `Apple80211` (إطار خاص) وتجاوز قيود الـ sandbox. الـ DEB يضع التطبيق كتطبيق نظام في `Applications/` — وهو المسار التقليدي والأوثق لهذه الحاجة — مع إدارة نظيفة بـ Sileo، وباب مفتوح لاحقًا لإضافة daemon للخلفية (وهو ما لا يستطيعه TrollStore).
> ويبقى الـ IPA ضروريًا لأن: تجربته أسرع (نقرة واحدة)، ويصلح للمشاركة، ويصلح لو لم تكن متأكدًا من نوع الـ jailbreak.

**الترتيب العملي المقترح:**
1. ثبّت **`Fieldwatch-unsigned.ipa`** بـ TrollStore/AppSync أولًا — أسرع طريق لرؤية التطبيق يعمل.
2. افتح التطبيق ← اضغط **«تشخيص Wi-Fi (probe)»** ← أرسل لي الناتج (هل حُمّلت مكتبة Apple80211؟ ما أسماء مفاتيح نتائج المسح؟).
3. بعد ذلك ثبّت **`-rootless.deb`** ليصبح التثبيت دائمًا ونظيفًا وتُدار التحديثات من Sileo.

---

## أي نسخة DEB أحتاج؟ (حدّد بنفسك في 10 ثوانٍ)

| نوع الـ jailbreak | العلامة | الحزمة الصحيحة |
|---|---|---|
| **rootless** (Dopamine، palera1n rootless، Unc0ver الحديثة) | يوجد مجلد `/var/jb` | `Fieldwatch-1.1.17-rootless.deb` · `iphoneos-arm64` |
| **rootful** (checkra1n، odysseyra1n) | لا يوجد `/var/jb` | `Fieldwatch-1.1.17-rootful.deb` · `iphoneos-arm` |
| **roothide** (Dopamine 2 roothide) | بادئة عشوائية، `/var/jb` غير ثابت | **استعمل الـ IPA** (TrollStore/AppSync) — هذا السكربت لا يناسب roothide |

**كيف تتحقق على جهازك** (NewTerm أو Filza):
```sh
ls -d /var/jb && echo "rootless" || echo "rootful"
dpkg --print-architecture        # سيطبع iphoneos-arm64 أو iphoneos-arm
```
> القاعدة الحاكمة (من وثائق Chariz): حزمة `iphoneos-arm64` **يجب** أن تضع كل ملفاتها تحت `/var/jb`، وحزمة `iphoneos-arm` في الجذر. مخالفة ذلك ⇒ «Package architecture does not match file prefix». سكربت البناء عندك يضبط هذا تلقائيًا، **وقد تحققت من ذلك بفتح الحزمتين**: مسارات rootless تبدأ بـ `./var/jb/…` ومسارات rootful بـ `./Applications/…`.

---

## التثبيت خطوة بخطوة

### أ) عبر Sileo/Zebra (الأسهل)
1. انقل ملف `.deb` إلى الهاتف (AirDrop/Share من الـ CI كـ ZIP ثم Filza).
2. افتحه بـ **Sileo** ← Install (أو في Filza: اضغط الملف ← Install).
3. بعد التثبيت أعد تحميل الأيقونات إن لزم: `uicache -a` (سكربت postinst يحاول ذلك تلقائيًا).

### ب) عبر الطرفية (الأدق للتشخيص)
```sh
dpkg -i /var/mobile/Downloads/Fieldwatch-1.1.17-rootless.deb
uicache -a
# للتحقق:
dpkg -l | grep fieldwatch
ls -l /var/jb/Applications/Fieldwatch.app
```

### ج) عن طريق IPA
- **TrollStore**: افتح الـ IPA منه ← Install. (استعمل النسخة `-trollstore.ipa` لأنها موقّعة بالصلاحيات وTrollStore يحفظها.)
- **AppSync Unified** (jailbreak): افتح الـ IPA بـ Filza ← Install، أو `filza` → «Open in» → AppSync.

---

## درجات الصلاحيات (ابدأ من الأولى ولا تتخطَّ)

| الدرجة | الملف | متى |
|---|---|---|
| 1 | `entitlements/00-none.entitlements` | **ابدأ هنا.** كثير من أجهزة الـ jailbreak تعمل بلا أي صلاحية خاصة |
| 2 | `entitlements/10-unsandbox.entitlements` | إن فشل `probe()` في `dlopen`. **وهو الافتراضي في البناء الآلي** |
| 3 | `entitlements/20-platform.entitlements` | آخر حل — له آثار جانبية (تُضيّق أجزاء من الـ sandbox) |

إعادة التوقيع على الجهاز (بلا إعادة بناء):
```sh
ldid -S/var/mobile/10-unsandbox.entitlements /var/jb/Applications/Fieldwatch.app/Fieldwatch
uicache -a
```
> صلاحيات ممنوعة نهائيًا على iOS 15+ مع معالج A12+ (تُسقط التطبيق فورًا): `com.apple.private.cs.debugger` · `dynamic-codesigning` · `com.apple.private.skip-library-validation`.

---

## الأعطال وحلولها

| العَرَض | السبب | الحل |
|---|---|---|
| Sileo: «Package architecture does not match file prefix» | نسخة deb خاطئة لنوع jailbreak | جرّب الـ deb الأخرى (rootless ↔ rootful) |
| لا تظهر أيقونة بعد التثبيت | ذاكرة أيقونات SpringBoard | `uicache -a` أو `sbreload` |
| التطبيق يسقط فورًا عند الفتح | صلاحية ممنوعة (انظر القائمة أعلاه) | انزل درجة: استعمل `10-unsandbox` ثم `00-none` |
| `probe()` يقول `isAvailable=false` | فشل تحميل Apple80211 (sandbox/اسم رمز مختلف) | ارفع درجة الصلاحيات، أو جرّب مسار `MobileWiFi.framework` (نفس البروتوكول، غيّر `requestScan` فقط) |
| `probe()` نجح والمسح أعاد 0 شبكات | المسح نفسه محجوب أو المفتاح مختلف | أرسل لي ناتج probe (مهمة: أسماء مفاتيح النتائج على إصدار iOS عندك) — نضبطها بدقة |

---

## ما تحقّق منه فعلًا (وليس ادّعاءً)

| الفحص | النتيجة |
|---|---|
| `swift build` + `swift test` للنواة على Swift 6.0.3 | ✅ **41 اختبارًا / 0 فشل** |
| بنية حزمة rootless: `Architecture: iphoneos-arm64` + مسارات `./var/jb/…` | ✅ بُنيت وفحصت بـ `dpkg-deb -I` و`-c` |
| بنية حزمة rootful: `Architecture: iphoneos-arm` + مسارات `./Applications/…` | ✅ كذلك |
| `control` (12 حقلًا) و`postinst`/`postrm` بصلاحية 755 | ✅ كذلك |
| تصريف طبقة التطبيق على iOS + إخراج IPA فعليًا | ⏳ يحتاج Xcode على ماك (أو GitHub Actions) — لا يمكن على لينكس |
| عمل Apple80211 على إصدار iOS عندك | ⏳ يحتاج جهازك + `probe()` |

**بصراحة:** لم أستطع تثبيت أي شيء على جهاز فعلي، ولا تشغيل Xcode. كل ما هو مذكور أعلاه تحققتُ منه بنفسي، والخطوات المتبقية تحتاج ماك وجهازك.
