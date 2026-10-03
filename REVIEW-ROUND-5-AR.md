# الجولة الخامسة — التطبيق يعمل على الجهاز، وتشخيص «0 visible / 0 heard»

**التاريخ:** 2026-10-03 · **الحزمة:** `2026-10-03.fix5`

## 1) الخبر الكبير: أنبوب البناء كامل ✓

صورة الجهاز تُثبت أن كل السلسلة نجحت: النواة بُنيت، التطبيق بُني، الـIPA أُنتج، ثُبّت على آيفون
مكسور الحماية، **والتطبيق يفتح ويعمل** (خمس تبويبات · شريط حالة · بحث · قائمة).

## 2) المشكلة الحالية: لا تظهر رديوهات

من الصورة نفسها (بلا تخمين):

| الملاحظة | المعنى |
|---|---|
| الزر مكتوب عليه **Stop** | `isScanning == true` ⇒ `scanForPeripherals` **استُدعي فعلًا** |
| `0 visible / 0 heard` | `scanner.sightings.count == 0` ⇒ **صفر استدعاءات `didDiscover`** |
| «Bluetooth ready» | `centralManagerDidUpdateState` وصلت بحالة `.poweredOn` ⇒ الاستدعاءات الراجعة **تعمل** |
| الواجهة تتحدّث كل ٠٫٥ ث | `refresh()` يُرسل `objectWillChange` ⇒ الأرقام **حيّة** لا قديمة |

**الاستنتاج:** العرض سليم، والمسح مُشغَّل، لكن **النظام لا يسلّم إعلانات BLE إلى التطبيق**.
هذه طبقة أذونات/صلاحيات، وليست طبقة كود.

## 3) المشتبه الأول: صلاحيات التوقيع

IPA الـTrollStore موقّع بـ `entitlements/10-unsandbox.entitlements` وفيه:

```
com.apple.private.security.no-sandbox = true
com.apple.private.security.storage.AppDataContainers = true
com.apple.developer.networking.multicast = true
```

تطبيق يعمل **خارج الـsandbox** قد يعامله iOS كعملية نظام، فلا يُسجَّل في `TCC`
بشكل طبيعي ⇒ **لا يظهر مربع حوار الإذن ولا تُسلَّم نتائج المسح**.

اختبار A/B **مجاني وفوري** بالملفات الموجودة أصلًا عندك:

- `Fieldwatch-trollstore.ipa` ← مُوقَّع (no-sandbox) ← هذا ما ثبّته على الأرجح.
- `Fieldwatch-unsigned.ipa` ← **بلا أي صلاحيات** ← ثبّته عبر TrollStore وقارن.

## 4) المشتبه الثاني: إذن Bluetooth

`Settings → Privacy & Security → Bluetooth` — هل «Fieldwatch» موجود ومُفعّل؟
إن لم يكن موجودًا إطلاقًا ⇒ **لم يُطلَب الإذن أصلًا** (سلوك متوقّع لتطبيق بلا sandbox).

## 5) ما أُضيف في fix5 (تشخيص داخل التطبيق)

1. **عدّادات حيّة:** `discoverCallbacks` · `scanStarts` · `autoRestarts` · `lastDiscoveryAt`.
2. **قراءات النظام:** `CBManager.authorization` (allowedAlways/denied/notDetermined/restricted) · `central.state` · `central.isScanning` (ما يراه النظام، لا ما نظنّه) · إصدار iOS.
3. **سطر في شاشة Live:** `state=… · auth=… · scan#… · callbacks=… · iOS …` ⇒ يكفي لصورة واحدة.
4. **شاشة «تشخيص الراديو»** (Settings → Tools): كل القيم + زر **إعادة بناء الراديو** + زر **افتح إعدادات النظام**.
5. **مراقب تلقائي:** ٦ ثوانٍ بلا إعلان ⇒ إعادة المسح بلا خيارات، ثم إعادة بناء `CBCentralManager` من الصفر (بحدّ ٤ محاولات).
6. **بدء المسح** عند ظهور الشاشة وعند عودة التطبيق من الخلفية (`scenePhase`).

## 6) الإثباتات (منفّذة)

```
swiftc -parse: 11/11 ملفات تطبيق   ·   XCTest: 111/111 (0 failures)
فاحص الوسائط/الدوال: ✅ لا نتائج   ·   PREFLIGHT-OK 2026-10-03.fix5 (53 ملفًا)
```
