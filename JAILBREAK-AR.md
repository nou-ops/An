# جهاز Jailbreak: كيف يعمل الملف كله معًا

أنت اخترت هدف **جهاز مكسور الحماية (Jailbreak)**. هذا يغيّر ثلاثة أشياء جوهرية:

| البند | جهاز عادي (بدون jailbreak) | جهازك (Jailbreak) |
|---|---|---|
| مسح Wi‑Fi المحيط | مستحيل — آبل لا تسمح لأي تطبيق | **ممكن** عبر `Apple80211` خلف `WiFiBackend` |
| Wi‑Fi Remote ID (FA:0B:BC/0x0D) | مستحيل | **ممكن** — نفس مسار أندرويد بالحرف |
| التثبيت | Apple ID مجاني (7 أيام) أو 99$/سنة | **دائم بلا حساب** (TrollStore / AppSync / ldid) |
| متطلبات البناء | macOS + Xcode | نفسها — استخدم CI المرفق |
| متجر آبل | ممكن نظريًا | خارج النطاق تمامًا |
| الاستقرار | مستقر وموثّق | مرهون بإصدار iOS وبالـ jailbreak: **لا تحدّث iOS قبل أن تتحقق** |

## ما بنيته لهذا الهدف (وهو جاهز في المجلد)

| الملف | الدور |
|---|---|
| `FieldwatchCore/…/WifiIeParser.swift` | نقل 1:1 لـ `parseIes` من `WifiIeParser.kt`: يفكّ **الـ IE الخام** إلى `rates` / `security` / `vendorIes` / `channelFromDs`. مع 10 اختبارات منقولة + اختبار End-to-End يثبت أن IE خام `FA:0B:BC` نوع 13 يخرج منه `lat/lon/heading/speed`. |
| `FieldwatchApp/Sources/WiFiBackend.swift` | العقد `WiFiBackend` + `WiFiScanResult` + جسر التحويل إلى `RadioFacts` (نفس دور `WifiRadio.toObservation`) + `WiFiBackendSelector`. |
| `FieldwatchApp/Sources/WiFiBackendIOS.swift` | `iOSNativeWiFiBackend` — ما تسمح به آبل: الشبكة المتصلة فقط، بلا مسح وبلا IEs. يبقى موجودًا ليعمل التطبيق حتى لو لم يكن الجهاز مكسور الحماية. |
| `FieldwatchApp/Sources/WiFiBackendJailbreak.swift` | `JailbreakWiFiBackend` — `dlopen` + `dlsym` لرموز `Apple80211Open/BindToInterface/Scan/Close`، قراءة مفتاح الـ IE الخام، و`probe()` للتشخيص على الجهاز. يفشل بهدوء (`isAvailable = false`) على جهاز عادي. |
| `entitlements/00-none · 10-unsandbox · 20-platform` | ثلاث درجات صلاحيات متدرّجة (ابدأ من الأولى) — التفصيل في `docs/IPA-vs-DEB-AR.md` |
| `scripts/build-deb.sh` + `build-all.sh` | بناء حزم `.deb` للـ jailbreak (rootless/rootful) + الـ IPA معًا من نفس البناء |

## الخطوات على جهازك

1. **بناء بلا توقيع** على CI: ارفع الحزمة (الـ workflow في مكانه الصحيح) ⇒ Actions ← *iOS unsigned IPA* ← Run workflow ⇒ تحصل على `Fieldwatch-unsigned.ipa` كـ artifact. (لا يوجد ماك؟ لا مشكلة.)
2. **التثبيت** — اختر ما يناسب جهازك (التفصيل الكامل: `docs/IPA-vs-DEB-AR.md`):
   - **حزمة DEB (الموصى بها أساسًا)**: `Fieldwatch-1.1.17-rootless.deb` ← Sileo/Filza، أو `dpkg -i` ثم `uicache -a`.
   - **TrollStore**: ثبّت `Fieldwatch-trollstore.ipa` (موقّعة بالصلاحيات، وTrollStore يحفظها) — دائم بلا شهادة ولا حساب.
   - **AppSync Unified**: يقبل أي IPA (استعمل `Fieldwatch-unsigned.ipa`).
3. **إن رفض الـ sandbox الـ private APIs**: الجدول التالي بالترتيب — ولا تتخطَّ درجة قبل تجربتها:
   | الدرجة | الملف | متى |
   |---|---|---|
   | 1 | `entitlements/00-none.entitlements` | **ابدأ هنا** — كثير من الأجهزة تعمل بلا صلاحيات |
   | 2 | `entitlements/10-unsandbox.entitlements` | إن فشل `dlopen` (وهو **الافتراضي** في البناء الآلي) |
   | 3 | `entitlements/20-platform.entitlements` | آخر حل: له آثار جانبية على الـ sandbox |
   إعادة التوقيع على الجهاز بلا إعادة بناء:
   ```sh
   ldid -S/var/mobile/10-unsandbox.entitlements /var/jb/Applications/Fieldwatch.app/Fieldwatch && uicache -a
   ```
4. **التشخيص**: شغّل `JailbreakWiFiBackend().probe()` وانسخ الناتج. إن فشل المسح أو لم يظهر مفتاح الـ IE، يخبرك الناتج:
   - هل حُمّلت المكتبة ومن أي مسار،
   - هل الرموز موجودة،
   - **ما أسماء المفاتيح الفعلية** في نتائج المسح على إصدار iOS عندك (هنا نضبط `"IE"` بدقة في دقيقتين).

## ما يجب أن تتوقعه بصراحة

- **ليست واجهة برمجية موثّقة.** `Apple80211` خاصة، وتغيّرت بين إصدارات iOS. الكود مكتوب ليفشل بهدوء ويعطيك تقريرًا بدل أن ينهار.
- **بديل لو لم تعمل**: `MobileWiFi.framework` (`WiFiManagerClientCreate` / `WiFiManagerClientScanNetworks` / `WiFiNetworkGetProperty(..., "IE")`) — نفس الفكرة، اسم آخر، ويوضع خلف **نفس** البروتوكول. غيّر `requestScan` فقط ولن يتأثر أي شيء آخر.
- **الخلفية**: على جهاز مكسور الحماية يمكنك تجاوز قيود الخلفية (helper/daemon أو entitlements)، لكن ذلك يزيد الهشاشة. ابدأ بماسح يعمل والتطبيق في المقدمة، ثم قرّر.
- **TAK / CoT**: إرسال multicast على الجهاز المكسور الحماية ممكن؛ أضف `com.apple.developer.networking.multicast` في الـ entitlements (القالب يذكره).
- **الأمان والمسؤولية**: جهاز مكسور الحماية + تطبيق بصلاحيات خاصة = مسؤوليتك أنت. لا تنشر IPA موقّعًا هذا التوقيع لأشخاص آخرين، ولا تضع الجهاز في شبكات لا تملكها بلا إذن.
