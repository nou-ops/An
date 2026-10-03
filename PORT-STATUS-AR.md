# حالة النقل — Fieldwatch 1.1.17 → iOS (بعد دمج حزمة FULL-PORT)

> ## قراءة سريعة للأرقام (لا تُقرأ كنسبة اكتمال)
> | | |
> |---|---|
> | **كود Swift** | **52 ملفًا / 6,195 سطرًا** — نواة 28 ملفًا/3,700 سطرًا · تطبيق 10/1,167 · اختبارات 14/1,328 |
> | **مقابل Kotlin** | **37,423 سطرًا** في `app/src/main` (86 ملفًا) + 7,675 سطرًا اختبارات (33 ملفًا) |
> | اختبارات XCTest | **100 — كلها تمر** (`swift test`) |
> | حالة التصريف | ✅ `swift build` + `swift test` على Swift 6.0.3 ⇒ **100/0** · و10/10 ملفات التطبيق تجتاز `swiftc -parse` |
> | الكتالوج | **الرسمي الكامل مدمج في الحزمة**: 244 توقيعًا / 6,962 قاعدة / 2.01MB (catalogVersion 88 = نسخة 1.1.17) |
> | ما لا يمكن التحقق منه هنا | تصريف SwiftUI/CoreBluetooth وإنتاج الـ IPA — يحتاج macOS/Xcode (سير العمل يفعلها) |

## ✅ ما دخل في هذا الدمج (بعد تحقّق فعلي)

1. **محرّك تواقيع كامل** (632 سطرًا) بدل نسخة مُبسّطة من 53 سطرًا — أصلح خطأين حاسمين: مفتاح هاتف Tesla كان يُوسم iBeacon، وAirTag كان يبقى موسومًا مع منتج آبل آخر.
2. **مفكّك حقول التواقيع** نقلًا حرفيًا + سبعة إصلاحات (`FIX-01…FIX-07`) + 11 اختبار تكافؤ من `SignatureFieldDecoderTest.kt`.
3. **مرشّحات (`SignatureCandidates`)**: دوال حاكمة منقولة حرفيًا (`nameGlobOf`/`isHouseLikeName`/`isOverbroadCreateName`) + إصلاح محاسبة `analyze` + 10 اختبارات بتوقّعات `SignatureCandidatesTest.kt`.
4. **`MacUtil` و`DetectionPolicy`** أُعيدا إلى النسخة الأمينة لـ `Models.kt`.
5. **الكتالوج الرسمي** مدمج في الحزمة (كان مقتطفًا 14KB).
6. **12 شاشة SwiftUI** + `FieldwatchStore` (حفظ محلي للأسماء/المراجع/التواقيع).
7. **نواة إضافية**: `AircraftTrail`, `ClassOutline`, `GeoExport`, `Hunt`, `LogReplay`, `RadioBookmarks`, `SettingsExchange`, `SignatureExchange`, `Sit`, `SitDiff`, `SitExport`, `AdvPayloadDecoder` — تُصرَّف وتُختبَر (قيد التدقيق التفصيلي، انظر `docs/MERGE-REVIEW-AR.md`).
8. **رفع من الهاتف بملف واحد**: سير العمل يفكّ `fieldwatch-payload.zip` فوق المستودع قبل البناء.

## ⚠️ ماذا يُنتج البناء فعلًا؟

تطبيق **يعمل**: مسح BLE + مسح Wi-Fi (jailbreak) + `probe()` + Live/Radar/Candidates/Filters/Signatures/Bookmarks/Hunt/Reports/Settings + محرّك التواقيع على الكتالوج الكامل + فكّ حقول 18 توقيعًا.
**ليس** Fieldwatch كاملة: لا `DeviceExplain`/`DebriefReport`/`DefaultCatalog`/`ApVendorOuis`/`RadioDb`، ولا الواجهة الأصلية (28 ملف Compose = 12.5k سطرًا)، ولا `DebriefPdf`/`Alerter`/`TakPublish`.

## PORT-TODO المفتوحة (مكتوبة عند مواضعها في الكود أيضًا)

- `SignatureCandidates.swift`: عائلات Kotlin تُبنى من **بصمات متعددة** (`buildClusters` + `mergeOverlapping` + `idViable`) لا من glob الاسم + vendor IE.
- `SignatureEngine.swift`: `suggestFleet` المبني على الجهاز (Kotlin `SignatureEngine.suggestFleet`) مقابل `SignatureCandidates.suggestFleet` الموجود.
- قيد التدقيق سطرًا بسطر: `AdvPayloadDecoder`, `LogReplay`, `AircraftTrail`, `SitDiff`, `SitExport`, `GeoExport`, `Hunt`, `ClassOutline`, `RadioBookmarks`, `SettingsExchange`, `SignatureExchange`.

## بوابة التحقق

```
$ swift test --package-path FieldwatchCore
Executed 100 tests, with 0 failures (0 unexpected)
```
السجل الكامل في `docs/verification-swift-test.txt`، وتفصيل الدمج في `docs/MERGE-REVIEW-AR.md`.
