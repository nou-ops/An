#!/usr/bin/env bash
#
# build-app.sh — يبني Fieldwatch.app لجهاز iOS (بلا توقيع آبل) ويوقّعه اختياريًا
# بـ ldid إذا مرّرت ملف صلاحيات. الناتج: <out>/Fieldwatch.app
#
# المتطلبات على macOS: Xcode + xcodegen  (brew install xcodegen)
#                       واختياريًا ldid للتوقيع بالصلاحيات (brew install ldid)
#
# المتغيّرات:
#   APP_OUT       مجلد الإخراج (افتراضي: out)
#   CONFIG        Release | Debug (افتراضي: Release)
#   ENTITLEMENTS  مسار ملف .entitlements — إن مُرِّر، يُوقَّع التنفيذي بـ ldid
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_OUT="${APP_OUT:-$ROOT/out}"
CONFIG="${CONFIG:-Release}"
DERIVED="${DERIVED:-$ROOT/build}"
SCHEME="${SCHEME:-Fieldwatch}"
ENTITLEMENTS="${ENTITLEMENTS:-}"

echo "==> xcodegen"
command -v xcodegen >/dev/null || { echo "!! xcodegen غير مثبّت: brew install xcodegen"; exit 1; }
xcodegen generate

echo "==> xcodebuild (unsigned, device, ${CONFIG})"
xcodebuild \
  -project "${ROOT}/Fieldwatch.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

BUILT="${DERIVED}/Build/Products/${CONFIG}-iphoneos/Fieldwatch.app"
[ -d "${BUILT}" ] || { echo "!! لم يُعثر على ${BUILT}" >&2; exit 1; }

rm -rf "${APP_OUT}"
mkdir -p "${APP_OUT}"
cp -R "${BUILT}" "${APP_OUT}/Fieldwatch.app"
APP="${APP_OUT}/Fieldwatch.app"

# إزالة مخلفات لا معنى لها في الحزمة
find "${APP}" -name '.DS_Store' -delete 2>/dev/null || true

EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${APP}/Info.plist" 2>/dev/null || echo Fieldwatch)"
BIN="${APP}/${EXEC_NAME}"
chmod 755 "${BIN}" || true

# ── التوقيع بـ ldid (اختياري لكنه مهم لمسار الصلاحيات) ───────────────────────
if [ -n "${ENTITLEMENTS}" ] && [ -f "${ENTITLEMENTS}" ]; then
  if command -v ldid >/dev/null 2>&1; then
    echo "==> ldid -S${ENTITLEMENTS}"
    ldid -S"${ENTITLEMENTS}" "${BIN}"
    echo "    صلاحيات مثبَّتة في توقيع التنفيذي:"
    ldid -e "${BIN}" | sed 's/^/      /' || true
  else
    echo "!! ldid غير موجود — تخطّي التوقيع بالصلاحيات."
    echo "   على الجهاز يمكنك التوقيع لاحقًا:  ldid -S<file> Fieldwatch.app/Fieldwatch"
    echo "   أو ثبّته على الماك: brew install ldid"
  fi
fi

echo "==> الناتج: ${APP}"
