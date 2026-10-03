# ios/ — ماذا في هذا المجلد

> **حالة التحقق:** `swift build` + `swift test` شُغّلا فعلًا على Swift 6.0.3 ⇒ **41 اختبارًا / 0 فشل**.
> المتبقي الوحيد: تصريف طبقة التطبيق وإنتاج الـ IPA، وهو ما يحتاج Xcode على ماك (أو GitHub Actions المرفق).

هذا هيكل بداية (scaffold) لبناء مشروع iOS من نفس منطق Fieldwatch 1.1.17،
مع أدوات تُنتج ملف `.ipa`. **لا شيء هنا بُني أو اختُبر على لينكس** — البناء
يحتاج macOS + Xcode. ما هو مُختبَر فعلًا: النقل (port) نفسه مكتوب سطرًا بسطر
مقابل Kotlin، واختبارات OpenDroneId منقولة كما هي من `app/src/test`.

## المحتويات

| المسار | الوصف |
|---|---|
| `FieldwatchCore/` | Swift Package: منطق الـ domain المنقول — **25 ملفًا / 3,004 سطر / 41 اختبار XCTest**. بلا أي import لأندرويد أو CoreBluetooth (قاعدة الـ handoff). |
| `FieldwatchCore/Sources/FieldwatchCore/Rssi.swift` | نقل 1:1 لـ `Rssi.kt` |
| `FieldwatchCore/Sources/FieldwatchCore/Geo.swift` | `meters / pathLengthM / spanM / cellKey` من `Geo.kt` |
| `FieldwatchCore/Sources/FieldwatchCore/PayloadLocation.swift` | نقل 1:1 لـ `PayloadLocation.kt` (الحقول + `mergeSticky` + `validCoord`) |
| `FieldwatchCore/Sources/FieldwatchCore/OpenDroneId.swift` | نقل 1:1 لـ `OpenDroneId.kt` (BLE FFFA + Wi-Fi FA:0B:BC type 0x0D + message pack) |
| `FieldwatchCore/Sources/FieldwatchCore/Models.swift` | شريحة من `Models.kt` + `RadioFacts` |
| `FieldwatchCore/…/CodDecoder.swift` | نقل 1:1 لـ `CodDecoder.kt` (Class of Device) + 5 اختبارات |
| `FieldwatchCore/…/RadarPlot.swift` | نقل 1:1 لـ `RadarPlot.kt` + 3 اختبارات |
| `FieldwatchCore/…/FilterEngine.swift` | نقل 1:1 لـ `FilterEngine.kt` (بوابات AND/OR + الشرائح الستة) + 9 اختبارات |
| `FieldwatchCore/…/CoTravel.swift` | نقل 1:1 لـ `CoTravel` من `Geo.kt` (withYou + كاش مدعوم بقفل) |
| `FieldwatchCore/…/FastPair.swift` | الجزء المطلوب من `FastPair.kt` (بلا جداول الأسماء — راجع NOTICE) |
| `FieldwatchCore/…/Models.swift` | خطوة A: `Sighting` كاملًا + `FilterState` + `FilterPreset` + `SignatureClass` (21 قيمة) + `TextMatch` + `PayloadFix` + `LiveDecodeChip` |
| `FieldwatchCore/Tests/` | XCTest: **41 اختبارًا منقولة — كلها تمر فعليًا** (`swift test` على Swift 6.0.3)، منقولة من اختبارات Kotlin المقابلة (OpenDroneId بواجهة DJI الحقيقية، WifiIeParser، CodDecoder، RadarPlot، FilterEngine) + Rssi + Geo |
| `FieldwatchApp/` | تطبيق SwiftUI صغير: CoreBluetooth يقرأ BLE، ويستدعي `OpenDroneId.fromFacts` من الـ Core |
| `project.yml` | مواصفة XcodeGen (لا نحتفظ بـ pbxproj في المستودع) |
| `scripts/build-unsigned-ipa.sh` | بناء Release + تغليف `Payload/` في `.ipa` غير موقّع |
| `.github/workflows/ios-unsigned-ipa.yml` | سير CI: يبني حزمة IPA غير موقّعة على منصة macOS runner مجانية (وهو في مكانه الصحيح أصلًا في هذه الحزمة) |

## على ماك

```bash
brew install xcodegen
cd ios

# 1) اختبارات الـ core (سريعة، بلا محاكي)
swift test --package-path FieldwatchCore

# 2) توليد المشروع وفتحه
xcodegen generate && open Fieldwatch.xcodeproj

# 3) IPA غير موقّع (CI-style)
bash scripts/build-unsigned-ipa.sh
```

## عن التوقيع (Signing)

| الطريقة | المدة | التكلفة | ملاحظة |
|---|---|---|---|
| Xcode + Apple ID مجاني | 7 أيام لكل بناء | 0 | يحتاج إعادة التثبيت أسبوعيًا |
| Sideloadly / AltStore + Apple ID مجاني | 7 أيام | 0 | بدون ماك (AltStore يحتاج خادمًا على نفس الشبكة) |
| حساب مطوّر (Developer Program) | سنة | 99$ | TestFlight، حتى 100 جهاز |
| App Store | دائم | 99$ | مراجعة آبل: تطبيقات كشف المتتبعات/المسح تتطلب مبررات قوية |
| Enterprise / Ad Hoc لمجموعة كبيرة | — | 299$ | لا تنشر IPA عامًا (يخالف اتفاقية آبل) |

## ما لا يمكن على iOS (اقرأه قبل أي وعد)

- **لا مسح Wi-Fi محيط**: لا `ScanResult`, لا raw IEs، لا `informationElements`.
  أي `WifiIeParser.kt` / `WifiRadio.kt` لا مقابل له على iOS بدون Jailbreak أو
  private APIs (غير مستقرة) أو راديو خارجي (ESP32 مثلًا) عبر BLE.
- **لا MAC**: `CBPeripheral.identifier` معرّف خاص بالتطبيق، ليس عنوان الجهاز.
- **الخلفية**: لا يوجد Foreground Service. `bluetooth-central` في الخلفية محدود
  جدًا؛ المسح المستمر ساعات كما في أندرويد غير موجود.
- **TAK/CoT**: إرسال multicast UDP يحتاج entitlement من آبل
  (`com.apple.developer.networking.multicast`) — يُطلب من حساب المطوّر.
