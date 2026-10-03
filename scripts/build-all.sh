#!/usr/bin/env bash
#
# build-all.sh — يبني كل شيء مرة واحدة من نفس المصدر:
#
#   out/Fieldwatch.app                          (التطبيق)
#   out/Fieldwatch-unsigned.ipa                 (بلا صلاحيات: للتثبيت العادي/AppSync)
#   out/Fieldwatch-trollstore.ipa               (موقّع بـ no-sandbox: TrollStore يحفظها)
#   out/Fieldwatch-trollstore-platform.ipa      (موقّع بـ platform+no-sandbox: لمسار Wi-Fi الخاص)
#   out/Fieldwatch-1.1.17-rootless.deb          (iphoneos-arm64 → /var/jb)
#   out/Fieldwatch-1.1.17-rootful.deb           (iphoneos-arm  → /)
#
# المنطق: نبني التطبيق مرة واحدة، ثم نغيّر الصلاحيات ونعيد التغلّف لكل هدف.
# هكذا لا نبني مرتين ولا تختلف النسخ عن بعضها.
#
# المتطلبات على macOS: xcodegen، واختياريًا ldid (brew install ldid)، و dpkg (brew install dpkg)
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="${ROOT}/out"
ENT_DIR="${ROOT}/entitlements"
SIGN_ENT="${SIGN_ENT:-${ENT_DIR}/10-unsandbox.entitlements}"

echo "═══════════════════════════════════════════════════════════"
echo " 1/5  بناء التطبيق (بلا صلاحيات) — للإصدار العادي"
echo "═══════════════════════════════════════════════════════════"
ENTITLEMENTS="" APP_OUT="${OUT}" bash scripts/build-app.sh
bash scripts/build-ipa.sh --app "${OUT}/Fieldwatch.app" --out "${OUT}/Fieldwatch-unsigned.ipa"

echo
echo "═══════════════════════════════════════════════════════════"
echo " 2/5  بناء التطبيق موقّعًا بصلاحيات (${SIGN_ENT##*/}) — لـ TrollStore و DEB"
echo "═══════════════════════════════════════════════════════════"
ENTITLEMENTS="${SIGN_ENT}" APP_OUT="${OUT}/signed" bash scripts/build-app.sh
bash scripts/build-ipa.sh --app "${OUT}/signed/Fieldwatch.app" --out "${OUT}/Fieldwatch-trollstore.ipa"

echo
echo "═══════════════════════════════════════════════════════════"
echo " 3/5  نسخة ثالثة بصلاحيات platform (تفتح مسار Wi-Fi عبر Apple80211)"
echo "      ملاحظة TrollStore: platform-application له آثار جانبية على الـ sandbox،"
echo "      لذلك تُبنى نسخة منفصلة ولا تُستبدل بها نسخة no-sandbox."
echo "═══════════════════════════════════════════════════════════"
PLATFORM_ENT="${ENT_DIR}/20-platform.entitlements"
if [ -f "${PLATFORM_ENT}" ]; then
  ENTITLEMENTS="${PLATFORM_ENT}" APP_OUT="${OUT}/platform" bash scripts/build-app.sh
  bash scripts/build-ipa.sh --app "${OUT}/platform/Fieldwatch.app" --out "${OUT}/Fieldwatch-trollstore-platform.ipa"
else
  echo "!! لا يوجد ${PLATFORM_ENT} — تخطّي النسخة الثالثة"
fi

echo
echo "═══════════════════════════════════════════════════════════"
echo " 4/5  حزمة DEB للـ jailbreak الحديث (rootless · iphoneos-arm64 · /var/jb)"
echo "═══════════════════════════════════════════════════════════"
bash scripts/build-deb.sh --app "${OUT}/signed/Fieldwatch.app" --variant rootless

echo
echo "═══════════════════════════════════════════════════════════"
echo " 5/5  حزمة DEB للـ jailbreak القديم (rootful · iphoneos-arm · الجذر)"
echo "═══════════════════════════════════════════════════════════"
bash scripts/build-deb.sh --app "${OUT}/signed/Fieldwatch.app" --variant rootful

echo
echo "═══════════════════════════════════════════════════════════"
echo " الناتج:"
echo "═══════════════════════════════════════════════════════════"
ls -lh "${OUT}"/*.ipa "${OUT}"/*.deb 2>/dev/null | awk '{printf "  %-52s %s\n", $9, $5}'
echo
echo "أي ملف تختار؟ انظر: ios/docs/IPA-vs-DEB-AR.md"
