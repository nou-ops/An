#!/bin/bash
# فحص ما قبل البناء — يمنع بناء حزمة قديمة أو ناقصة.
# يُشغّله Xcode تلقائيًا (preBuildScripts) ويمكن تشغيله يدويًا:  bash scripts/preflight.sh
set -u
cd "${SRCROOT:-$(dirname "$0")/..}" 2>/dev/null || true

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; NC='\033[0m'
fail=0

VER="$(sed -n 's/^الإصدار:[[:space:]]*//p' PAYLOAD-VERSION.txt 2>/dev/null | head -1)"
echo "────────────────────────────────────────────────────────"
echo " فحص الحزمة قبل البناء — PREFLIGHT"
echo " الإصدار: ${VER:-لا يوجد PAYLOAD-VERSION.txt}"
echo " الـcommit: $(git log -1 --format='%h %ci %s' 2>/dev/null || echo '(مستودع بلا .git أو نسخة مضغوطة)')"
echo "────────────────────────────────────────────────────────"

# 1) بصمة الإصدار: يجب أن تكون fix3 أو أحدث (تحوي إصلاحات طبقة التطبيق)
case "${VER}" in
  *fix9*) : ;;
  "")  echo -e "${RED}✗ الحزمة قديمة: لا يوجد PAYLOAD-VERSION.txt${NC}"; fail=1 ;;
  *)   echo -e "${RED}✗ الحزمة قديمة: الإصدار '${VER}' أقدم من fix9 (اختيار أحدث حزمة + بصمة استراتيجية)${NC}"; fail=1 ;;
esac

# 2) علامات الإصلاح الأساسية
check() { # $1=وصف  $2=ملف  $3=نص يجب وجوده
  if [ ! -f "$2" ]; then echo -e "${RED}✗ ناقص: $2${NC}"; fail=1; return; fi
  if grep -qF "$3" "$2"; then echo -e "${GRN}✓${NC} $1"
  else echo -e "${RED}✗ الحزمة قديمة: '$2' لا يحوي '$3'${NC}"; fail=1; fi
}
check 'وسائط LogRadio بأسمائها الصحيحة (hits:)' FieldwatchApp/Sources/FieldwatchStore.swift 'hits: $0.hitCount'
check 'Sighting من النواة يحقق Identifiable'      FieldwatchCore/Sources/FieldwatchCore/Models.swift 'extension Sighting: Identifiable'
check 'لا تعارض أسماء: النوع المحلي BleRow'        FieldwatchApp/Sources/BleScanner.swift      'struct BleRow'
check 'إصلاح count(where:) — Swift 5 على CI'       FieldwatchCore/Sources/FieldwatchCore/SignatureCandidates.swift 'usable.filter'
check 'تشخيص الراديو: عدّاد didDiscover (fix5)'      FieldwatchApp/Sources/BleScanner.swift      'discoverCallbacks'
check 'شاشة تشخيص الراديو (fix5)'                    FieldwatchApp/Sources/RadioDiagnosticsView.swift 'إذن Bluetooth'
check 'Wi-Fi مدمج في قائمة الرديوهات (fix6)'         FieldwatchApp/Sources/FieldwatchStore.swift 'wifiSightings'
check 'شاشة شبكات Wi-Fi (fix6)'                       FieldwatchApp/Sources/WiFiView.swift 'امسح الشبكات الآن'
check 'نسخة platform للـ Wi-Fi في البناء (fix6)'      scripts/build-all.sh 'Fieldwatch-trollstore-platform.ipa'
check 'مسار MobileWiFi في الـ backend (fix7)'        FieldwatchApp/Sources/WiFiBackendJailbreak.swift 'WiFiManagerClientCreate'
check 'إصلاح CFRunLoopMode→CFString (fix8)'         FieldwatchApp/Sources/WiFiBackendJailbreak.swift 'kCFRunLoopDefaultMode as! CFString'
check 'Identifiable داخل النواة لا في التطبيق (fix8)' FieldwatchCore/Sources/FieldwatchCore/Models.swift 'extension Sighting: Identifiable'
check 'صلاحية Wi-Fi في التوقيع (fix7)'               entitlements/20-platform.entitlements 'com.apple.wifi.manager-access'
check 'صلاحية Wi-Fi في نسخة TrollStore (fix7)'       entitlements/10-unsandbox.entitlements 'com.apple.wifi.manager-access'

# 3) مطابقة البصمة الرقمية لكل ملف (تكشف رفعًا ناقصًا أو مختلطًا)
if [ -f PAYLOAD-MANIFEST.sha256 ]; then
  if shasum -a 256 -c PAYLOAD-MANIFEST.sha256 > /tmp/preflight-manifest.log 2>&1; then
    echo -e "${GRN}✓${NC} بصمة كل ملفات الحزمة مطابقة ($(grep -c . PAYLOAD-MANIFEST.sha256) ملفًا)"
  else
    echo -e "${RED}✗ ملفات الحزمة لا تطابق البصمة — الرفع ناقص أو مختلط:${NC}"
    grep -v ': OK$' /tmp/preflight-manifest.log | head -12 | sed 's/^/    /'
    echo    "── تشخيص (يُطبع مرة واحدة لمعرفة السبب بدقة) ──"
    echo    "   ملفات scripts/ الموجودة فعلًا:"; ls -la scripts/ 2>/dev/null | sed 's/^/     /'
    for z in *.zip; do
      [ -f "$z" ] || continue
      echo "   الحزمة $z — عدد العناصر: $(unzip -l "$z" 2>/dev/null | tail -1 | awk '{print $2}')"
      unzip -l "$z" 2>/dev/null | grep 'scripts/' | sed 's/^/     /'
    done
    fail=1
  fi
else
  echo -e "${YEL}⚠ لا يوجد PAYLOAD-MANIFEST.sha256 (لن أتحقق من تطابق الملفات)${NC}"
fi

echo "────────────────────────────────────────────────────────"
if [ "$fail" -ne 0 ]; then
  echo -e "${RED}✗✗ فشل فحص الحزمة: هذه ليست الحزمة الصحيحة.${NC}"
  echo    "    ارفع fieldwatch-payload.zip الأحدث إلى جذر المستودع ثم شغّل من الـcommit الجديد."
  echo    "    (تأكد أن الحزمة القديمة حُذفت/استُبدلت وأنك لا تعيد تشغيل commit قديم)"
  echo "PREFLIGHT-FAILED"
  exit 1
fi
echo -e "${GRN}✓✓ الحزمة الصحيحة. متابعة البناء.${NC}"
echo "PREFLIGHT-OK ${VER}"
exit 0
