# مراجعة الدمج — حزمة «FULL-PORT» على مشروعنا

> هذا الملف يوثّق **ما تحقّقتُ منه بنفسي** لا ما جاء في وصف الحزمة.
> كل ادّعاء هنا له دليل أمرٍ شُغِّل فعليًا، وكل ما لم يُتحقَّق مكتوب صراحةً في الفقرة الأخيرة.

## 1) ادّعاءات الحزمة — ماذا تأكّدت منها فعلًا

| الادّعاء | النتيجة |
|---|---|
| SHA-256 `7d5e81e0…2e49` | ✅ **مطابق** للملف الذي وصلني |
| «63/63 اختبارًا ناجحًا — 0 أخطاء» | ✅ **صحيح**: بنيت وشغّلت الحزمة كما هي ⇒ `Executed 63 tests, with 0 failures` |
| «49 ملف Swift» | ✅ صحيح (49 ملفًا، 4,087 سطرًا) |
| «تطبيق SwiftUI بـ Live/Device Details/Radar/Candidates/Filters/Signatures/Bookmarks/Hunt/Reports/Settings» | ✅ موجود فعلًا: `RootView` + `ManagementViews` + `FieldwatchStore` (12 شاشة) |
| «Wi-Fi Jailbreak backend معزول» | ⚠️ حرفيًا **ملفاتي أنا** — الملفات الخمسة الأمنية (`WiFiBackend`, `WiFiBackendIOS`, `WiFiBackendJailbreak`, `Geo`, `CodDecoder`, `OpenDroneId`, `WifiIeParser`, `FilterEngine` تقريبًا) **مطابقة بايت ببايت** لما نشرتُه. أي أنه انطلق من حزمتي، لا نقل مستقل. |
| «GitHub Actions + سكربت إنشاء IPA» | ⚠️ ناقص: سير العمل عندهم **يبني فقط** (`xcodebuild build`) بلا `archive` وبلا رفع artifacts ⇒ **لا يُنتج IPA قابلًا للتنزيل**. سكربت واحد فقط، وبلا DEB. |
| «اختبار سلامة الـ ZIP» | ✅ الحزمة سليمة وتُفكّ كاملة |

## 2) عيوب حقيقية اكتشفتها بالتشغيل (لا بالقراءة)

### أ) محرّك التواقيع — خطآن حاسمَين

محرّكهم (53 سطرًا) مُبسّط مقابل `SignatureEngine.kt` (647 سطرًا). شغّلتُ مسبارًا على **الكتالوج الرسمي الكامل** المدمج في حزمتهم:

| الحالة | محرّكهم | سلوك Kotlin | الأثر |
|---|---|---|---|
| مفتاح هاتف Tesla (`021574278B…`) | `[fleet-ibeacon, fleet-tesla]` | `[fleet-tesla]` | وسم خاطئ لسيارة كأنها منارة iBeacon |
| AirTag + بادئة آبل Continuity | `[fleet-airtag, fleet-apple-device]` | `[fleet-apple-device]` | وسم خاطئ لهاتف كأنه AirTag |
| إسقاط Meraki→Cisco | لا يوجد (مُبسّط بالاسم فقط) | موجود | ازدواج وسم |
| بوّابات `DetectionPolicy` / فواصل بروتوكول `00:50:F2` / العناقيد | غير موجودة | موجودة | نتائج مختلفة عند التشغيل الحقيقي |

**الحل**: استبدلت الملف بمحرّكي الكامل (632 سطرًا) بعد تكييفه على أسماء `RuleKind` عندهم (`VENDOR_IE_OUI`, `SERVICE_UUID`, `MANUFACTURER_ID`, `HIDDEN_SSID`) وعلى شكل الاستدعاء `match(_ devices:)`. حالات الإسقاط صارت مُختبَرة على الكتالوج الحقيقي.

### ب) مفكّك حقول التواقيع — سبعة انحرافات

قارنتُ سطرًا بسطر مقابل `SignatureFieldDecoder.kt` (450 سطرًا). الانحرافات المؤثرة:

1. **بيانات المصنّع تُفكّ لأي راديو** — Kotlin يشترط `kind == BLE`.
2. **`SERVICE_DATA` بلا UUID صريح يقبل أي حمولة** — Kotlin يشترط UUID محدد ويقارن بـ `uuidKey`.
3. **لا إزالة للاصقة `INTELLI_ROCKS`** (Govee) ⇒ خرائط H5074/H5075/H510x لا تُفكّ أصلًا.
4. **`BITS` يقرأ بايتًا واحدًا فقط** ويقصّ العرض عند 31 بتة (Kotlin: كل الشريحة حتى 32).
5. `HEX` بلا فواصل، `BOOL` بـ true/false بدل yes/no، `MAC` يقبل أقل من 6 بايتات.
6. **`enumLabels` بمفاتيح `0x..` أو عشرية لا تُطابق** ⇒ قيم الكتالوج تظهر خامًا.
7. `resolvedLength` للبتات وmac خاطئ.

**الحل**: أعدت كتابة الملف نقلًا حرفيًا (منطق Kotlin كاملًا + كاش + `stripIntelliRocks`)، مع تعليق `FIX-01…FIX-07` عند كل موضع، و**11 اختبار تكافؤ** مأخوذة من `SignatureFieldDecoderTest.kt`.

### ج) `MacUtil` و`DetectionPolicy` غير أمينتين

- `MacUtil.normalize` عندهم **يقصّ إلى 12 خانة ويُرجع `""`** للعناوين القصيرة — Kotlin يقسّم أي طول ويُرجع الاسم الأصلي إن كان أقصر من بايتين. استبدلتها بنسختي الأمينة.
- `DetectionPolicy` عندهم حقل واحد `enabled` — Kotlin: أربعة حقول (`ssidKeywords/knownOuis/vendorIes/bleRaven`). استبدلتها بالنقل الأمين.

### د) المرشّحات (`SignatureCandidates`) — منطق مختلف

- `nameGlobOf`: Kotlin يرفض أولًا الأسماء «الشبيهة بالمنازل»، ويشترط قوسًا **مُرسىً**، وبادئة غير مُتجاهَلة، ولاحقة ست عشرية بطول ≥ 6. نسختهم كانت أقرب إلى التسامح.
- `isHouseLikeName`: Kotlin يعمل على **الرمز الأول** مع قاعدة «المنتَج» (مثل `ATT-GUEST-lobby` ⇒ بيتي، `H2O-047bcbd11400` ⇒ ليس بيتيًا)، ونسختهم كانت تبحث عن كلمة داخل الاسم كله.

**الحل**: أعدت كتابة الدوال حرفيًا + أصلحت محاسبة `analyze` (ترتيب الفحص: مُهيكل → عشوائي → بيتي، وإضافة `usable` غير المُجمَّعة إلى `skippedOther`) + **10 اختبارات تكافؤ** بتوقّعات `SignatureCandidatesTest.kt` نصًّا.

### هـ) فجوة الثقة الأكبر: لا IPA من CI

سير العمل عندهم لا يُنتج ملف IPA ولا DEB. أبقيتُ سير العمل وسكربتاتي (المُختبَرة سابقًا: IPA عادي + TrollStore + DEB rootless + rootful) وأضفتُ إليها خطوة **فكّ حزمة الرفع** كي ترفع أنت ملفًا واحدًا من الهاتف.

## 3) ما قبلته كما هو (بعد التحقق من ثوابته)

| الملف | سند القبول |
|---|---|
| `SignatureCatalog.swift` + `Resources/fieldwatch-signatures-v2.json` | الكتالوج الحقيقي (244 توقيعًا، 6,962 قاعدة) — **قرار جيد يجعل الاختبارات على بيانات حقيقية** |
| `Models.kt` ⇒ `RuleKind/MatchRule/FleetDecode/DecodeField/DecodeWhen` | أسماء `RuleKind` ومفاتيح `decode` مطابقة للكتالوج (تحقّقت من 18 توقيعًا و143 حقلًا) |
| `LogReplay` (CSV/JSONL) | الترويسة والمفاتيح مطابقة لصيغة تصدير Fieldwatch |
| `Sit.swift` | الثوابت مطابقة حرفيًا: `NAME_MAX 40`, `RADIO_CAP 6000`, `FORMAT "fieldwatch-sit"`, `FORMAT_VERSION 1` … |
| `AircraftTrail`, `ClassOutline`, `Hunt`, `RadioBookmarks`, `SettingsExchange`, `SignatureExchange`, `GeoExport`, `SitDiff`, `SitExport`, `AdvPayloadDecoder` | تُصرَّف وتُختبَر، لكن **لم تُقارن سطرًا بسطر** بعد — مُدرجة في جدول «قيد التدقيق» أدناه |
| طبقة التطبيق (10 ملفات) | تُحلَّل `swiftc -parse` 10/10، وكل مراجع `store.*` معرّفة فعلًا، والمراجع الثابتة للنواة موجودة |

## 4) قيد التدقيق (لم أتحقّق بعد — لا أدّعي فيه تكافؤًا)

- `AdvPayloadDecoder` مقابل `AdvPayloadDecoder.kt` (653 سطرًا) — قوائم الأدوار والأوزان.
- `LogReplay` مقابل `LogReplay.kt` (1,241 سطرًا) — تحليل صيغة السجل الكاملة.
- `AircraftTrail` / `SitDiff` / `SitExport` / `GeoExport` / `Hunt` / `ClassOutline` / `RadioBookmarks` / `SettingsExchange` / `SignatureExchange`.
- **المرشّحات**: Kotlin يبني العائلات من **بصمات متعددة** (`buildClusters` + `mergeOverlapping` + `idViable`) لا من glob الاسم فقط — موسوم `PORT-TODO(iOS)` في `SignatureCandidates.swift`.
- `sit`/`device`/`config` stores · `DeviceExplain` · `CatalogDecodes` · `DebriefReport` · `DefaultCatalog` · `ApVendorOuis` · `RadioDb` · الواجهة الكاملة (28 ملف Compose) · `DebriefPdf` · `Alerter` · `TakPublish` — **غير منقولة بعد**.

## 5) الحصيلة بعد الدمج

| | قبل الدمج | بعد الدمج |
|---|---|---|
| ملفات Swift | 29 | **52** (نواة 28 · تطبيق 10 · اختبارات 14) |
| أسطر Swift | 4,479 | **6,195** |
| اختبارات XCTest | 61 | **100 — كلها تمر** |
| كتالوج حقيقي مدمج | مقتطف 14KB | **244 توقيعًا / 2.01MB** |
| IPA من CI | ✅ (سير عملنا) | ✅ + رفع ملف واحد من الهاتف |

المقابل الأصلي Kotlin: **37,423 سطرًا** في `app/src/main` + 7,675 سطرًا اختبارات. أي أن النسبة الحقيقية ≈ **سدس النواة المنطقية، ولا شيء من الواجهة الأصلية**. لا نكتب «اكتمال».
