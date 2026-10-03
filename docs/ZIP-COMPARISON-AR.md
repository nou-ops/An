# مقارنة الحزمتين بالدليل — `fieldwatch-payload.zip` مقابل `Fieldwatch-iOS-PARITY-NEXT.zip`

> نتيجة الفحص الفعلي لبايتات الحزمتين، لا لتوصيف الأسماء. أمر التنفيذ: مقارنة ملف-بملف + تشغيل `swift test` على كل منهما.

## 1) الخلاصة

**`fieldwatch-payload.zip` يحتوي كل ما في `PARITY-NEXT` — وزيادة.** لا يوجد ملف واحد في PARITY-NEXT غير موجود فيه.

| القياس | PARITY-NEXT | fieldwatch-payload |
|---|---|---|
| ملفات Swift | 53 | **55** |
| ملفات ZIP | 97 | **99** |
| دوال اختبار XCTest | **104 — كلها تمر** | **111 — كلها تمر** |
| بنية المسارات | متداخلة تحت `payload/` ⚠️ | **مسطّحة تطابق جذر المستودع** ✅ |
| يقبل الرفع-ثم-البناء في CI | ❌ المسارات ستكون `payload/FieldwatchCore/...` | ✅ |

## 2) مقارنة ملف-بملف (53 ملف Swift عندهم)

```
مفقود من حزمتي : 0
مطابق بايت-ببايت : 51
مختلف            : 2  — وكلاهما «ملفهم + إصلاحي الموثّق»
```

### الفرق الأول: `SignatureEngine.swift`
```
626a627,628
> /// DefaultCatalog.kt:17 — وسم Target/Atrius لسلال التسوّق (iBeacon بنفس بادئة آبل).
> public static let targetAtriusIBeaconMfgPrefix = "02155993A94C7D974DF79ABFE493BFD5D000"
```
أي أن محرّكي نفسه، مضافًا إليه الثابت المفقود.

### الفرق الثاني: `AdvPayloadDecoder.swift`
```
+ FIX-AD1: فرع Target/Atrius (bucket "beacon"، وزن 8، النص الحرفي من Kotlin)
+ FIX-AD2: Fast Pair يستدعي FastPairModels.name — وزن 8 للطراز المعروف، 6 للمجهول
- (عندهم) id == 6 ? "Google Pixel Buds" : نص عام
```
وهذان هما الفجوتان الموثّقتان في `docs/REVIEW-ROUND-2-AR.md`.

## 3) ملفات حصرية في `fieldwatch-payload`

1. `FieldwatchCore/Sources/FieldwatchCore/FastPairModels.swift` — 110 طرازات، **مولَّد آليًا** من `FastPairModels.kt`.
2. `FieldwatchCore/Tests/FieldwatchCoreTests/AdvPayloadDecoderParityTests.swift` — 7 اختبارات تكافؤ.
3. `docs/MERGE-REVIEW-AR.md` · `docs/REVIEW-ROUND-2-AR.md` · `docs/ZIP-COMPARISON-AR.md`.

## 4) لماذا جاء تقييم الطرف الثالث مخالفًا للواقع؟

التقييم بنى حكمه على تسمية الملف لا على فتحه: كلمة «payload» تُوحي بـ«حزمة بيانات خام». وكل بند ذكره كخصائص حصرية لـPARITY-NEXT موجود في `fieldwatch-payload` فعلًا:

| ما قيل إنه ينقص `fieldwatch-payload` | الواقع في الحزمة |
|---|---|
| `WiFiBackendIOS.swift` + `WiFiBackendJailbreak.swift` | ✓ موجودان |
| `scripts/build-deb.sh` + `build-unsigned-ipa.sh` | ✓ موجودان (وأيضًا `build-all.sh`, `build-app.sh`, `build-ipa.sh`) |
| `docs-FIELDWATCH-KOTLIN-SOURCE.txt` | ✓ موجود |
| اختبارات `FieldwatchCoreTests` | ✓ 15 ملفًا / 111 اختبارًا (أكثر من 14 ملفًا / 104 عندهم) |
| `ios-unsigned-ipa.yml` | ✓ موجود، وبنسخة **أقوى**: أربعة نواتج (IPA + TrollStore + DEB rootless + rootful)، و`continue-on-error: false`، وخطوة فكّ حزمة الرفع تلقائيًا |
| `PORT-STATUS-AR.md` + `IPA-vs-DEB-AR.md` | ✓ موجودان |
| أدوات التجميع التلقائي | ✓ موجودة |

**نقطة إنصاف**: كانت عبارة «PARITY-NEXT أكمل» **صحيحة لحظة صدورها** — قبل أن أدمجها. `fieldwatch-payload` الحالي = PARITY-NEXT + إصلاحات FIX-AD1/FIX-AD2 + اختباراتها. لا تعارض إذن؛ الطرف الثالث نصح باستخدام الأساس، وأنا بنيت على الأساس نفسه ثم أكملت الناقص.

## 5) التوصية

ارفع **`fieldwatch-payload.zip`** إلى جذر المستودع (استخدم `UPLOAD-ONE-FILE-AR.md`). إن رفعت PARITY-NEXT بدلًا منه فالبناء سيفشل لأن كل شيء بداخله متداخل تحت `payload/`، وسيحتاج نقلًا يدويًا — بلا أي مقابل: لا ملف إضافي واحد.
