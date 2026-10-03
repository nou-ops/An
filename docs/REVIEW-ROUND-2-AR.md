# مراجعة الدفعة الثانية (PARITY-NEXT) — ما تحقّقت منه وما أصلحته

> القاعدة نفسها: لا أُصدّق وصفًا، أُشغّل الكود. كل سطر هنا له أمرٌ نُفِّذ.

## 1) ادّعاءاتك — كلها **صحيحة** (تحقّقت منها بنفسي)

| الادّعاء | النتيجة |
|---|---|
| SHA-256 `e9bd9f49…479` | ✅ مطابق |
| `swift test` ⇒ **104/104 · 0 فشل** | ✅ أكّدتُه: `Executed 104 tests, with 0 failures` |
| 53 ملف Swift | ✅ صحيح |
| `continue-on-error: false` في CI | ✅ صحيح — والبناء الآن `needs: [smoke, tests]` ⇒ **فشل الاختبارات يمنع الـIPA فعلًا** |
| Geo مضاف: `PathLeg/legs/screenCoord/redactCoordsIn/hopPlausible/despikePath/append/capSpread` | ✅ و**نقل أمين**: قارنتُه دالة بدالة بـ `Geo.kt` (44–260) — الثوابت (`SPIKE_MAX_SPEED_MPS 42.0`, `SPIKE_MIN_HOP_M 40.0`, `SPIKE_MIN_DT_MS 800`, نافذة stays 40m/40s، سقف 10 أقدام، `capSpread` بخطوة `(i*last)/(cap-1)`) كلها مطابقة |
| AdvPayloadDecoder موسّع | ✅ موسّع فعلًا وبإخلاص: تحقّقت أن **كل** جداول Kotlin موجودة بنصوصها: `airPodsModelName` (27 طرازًا)، `airPodsStatus` (11)، `airPodsColor` (13)، `nearbyActionName` (15)، `appleTypeName` (17) — صفر انحراف |

**خلاصة**: انتقلت من «تقرير طرف ثالث» إلى مراجعة أدلّة. ما قلتَه عن المتبقي كان دقيقًا أيضًا.

## 2) لكن وجدت فجوتين بقيتا في `AdvPayloadDecoder` — وأصلحتهما

### FIX-AD1 · Target / Atrius iBeacon (كان مفقودًا)

Kotlin يفرّق **ثلاث** حالات داخل TLV `0x02`، ونسختك تعرف اثنتين:

| الحالة | مصدر Kotlin | عندك قبل | الآن |
|---|---|---|---|
| Tesla phone-as-key | `TESLA_IBEACON_MFG_PREFIX` (`DefaultCatalog.kt:10`) | ✅ `vehicle` وزن 8 | يبقى |
| **Target / Atrius basket tag** | `TARGET_ATRIUS_IBEACON_MFG_PREFIX` (`DefaultCatalog.kt:17` = `02155993A94C7D974DF79ABFE493BFD5D000`) | ❌ يقع في «iBeacon عام» وزن 7 | ✅ `beacon` وزن 8 بنص Kotlin |
| iBeacon عام | — | ✅ وزن 7 | يبقى |

### FIX-AD2 · أسماء طرازات Fast Pair (كانت مُثبَّتة على معرّف واحد)

- `decodeFastPair` عندك: `id == 6 ? "Google Pixel Buds" : "0x%06X (local name list may be unavailable)"` — معرّف واحد مكتوب يدويًا.
- Kotlin: `FastPairModels.name(id)` من **جدول 110 طرازًا** (`FastPairModels.kt`)، والنص البديل `"0x%06X (not in the local name list)"`.
- كذلك `roleHints`: Kotlin يمنح **وزن 8** للطراز المعروف و6 للمجهول، ويعرض الاسم في الوسم — نسختك كانت وزن 6 دائمًا ونصًا عامًا.

**ما فعلته**: ولّدتُ `FastPairModels.swift` **آليًا** من ملف Kotlin (110 طرازات، لا نسخ يدوي)، وربطت الدالتين به.

## 3) اختبارات التكافؤ الجديدة (7 اختبارات)

`AdvPayloadDecoderParityTests.swift`:
- Tesla ⇒ `vehicle` / وزن 8 / النص الحرفي.
- **Atrius ⇒ `beacon` / وزن 8** (يفشل قبل الإصلاح).
- iBeacon عادي يبقى عامًا بوزن 7 (شاهد مضاد حتى لا يكون الفرع مفتوحًا للجميع).
- Fast Pair: معرّف معروف (`0x000006` ⇒ Google Pixel Buds، وزن 8) ومعرّف مجهول (`0xFFFEFD` ⇒ نص عام، وزن 6).
- نصوص `decodeFastPair` الحرفية: `"Google Pixel Buds  (0x000006)"` (بمسافتين) و`"0xFFFEFD (not in the local name list)"`.
- حجم الجدول = 110 + تقنيع 24 بتة (`name(0xFF000006) == name(0x000006)`).

## 4) حالة الشجرة بعد الدمج

| | PARITY-NEXT (عندك) | بعد الدمج |
|---|---|---|
| ملفات Swift | 53 | **54** (+`FastPairModels`) |
| أسطر Swift | ~6,221 | **6,612** |
| اختبارات XCTest | 104 | **111 — كلها تمر** |
| ملفات التطبيق `swiftc -parse` | 10/10 | 10/10 |
| فجوة Atrius | مفتوحة | مُغلقة ومُختبَرة |
| فجوة Fast Pair | مفتوحة | مُغلقة ومُختبَرة |

## 5) ما يبقى (متفق عليه معك)

1. **`SignatureCandidates`**: توليد العائلات من بصمات متعددة (`buildClusters` + `mergeOverlapping` + `idViable`) — موسوم `PORT-TODO(iOS)`.
2. **`SignatureEngine.suggestFleet`** (نسخة المحرّك) غير منقولة.
3. **`DeviceExplain`** وربطه بـ`Sit`/`LogStore`.
4. **`WiFiBackendJailbreak` على جهاز حقيقي** — لا يُثبت على لينكس.
5. قيد التدقيق سطرًا بسطر: `LogReplay` (1,241 سطرًا)، `AircraftTrail`، `SitDiff/SitExport/GeoExport`، `Hunt`، `ClassOutline`، `RadioBookmarks`، `SettingsExchange`، `SignatureExchange`.

> ملاحظة صغيرة على عدّاد الاختبارات: عدد دوال `test` عندك كان 104 لأن `LogReplayCandidatesTests` و`SitTests` أُضيفا؛ أرقامي أعلاه كلها من تشغيل فعلي لا من عدّ نصي.
