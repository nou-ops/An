#!/usr/bin/env bash
#
# build-deb.sh — يبني حزمة .deb لتطبيق iOS (jailbreak) من Fieldwatch.app.
#
#   الاستخدام:
#     bash scripts/build-deb.sh --app out/Fieldwatch.app --variant rootless
#     bash scripts/build-deb.sh --app out/Fieldwatch.app --variant rootful
#
# الفرق بين النسختين (قاعدة إلزامية في عالم الـ jailbreak — لا تُخالَف):
#   rootless (iphoneos-arm64): كل الملفات تحت /var/jb   ← Dopamine / palera1n rootless …
#   rootful  (iphoneos-arm)  : الملفات في جذر النظام    ← odysseyra1n / checkra1n القديمة …
#   إن خالفت القاعدة يرفض Sileo الحزمة برسالة:
#     "Package architecture does not match file prefix"
#
# ملاحظة: إن كنت على jailbreak من نوع "roothide" (بادئة عشوائية) فهذا السكربت
# لا يناسبك — استعمل مسار الـ IPA (TrollStore/AppSync) أو أدوات roothide.
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP="${ROOT}/out/Fieldwatch.app"
VARIANT="rootless"
OUT=""
PKG_ID="app.fieldwatch.ios"
PKG_NAME="Fieldwatch"
VERSION="1.1.17"
MAINTAINER="${MAINTAINER:-nou-ops}"
HOMEPAGE="${HOMEPAGE:-https://github.com/nou-ops/Fieldwatch}"
DESCRIPTION="${DESCRIPTION:-Fieldwatch 1.1.17 — passive Wi-Fi / BLE field viewer (iOS port). Private Wi-Fi scanning requires a jailbroken device.}"

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --variant) VARIANT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --id) PKG_ID="$2"; shift 2 ;;
    --name) PKG_NAME="$2"; shift 2 ;;
    *) echo "وسيط غير معروف: $1" >&2; exit 2 ;;
  esac
done

case "${VARIANT}" in
  rootless) ARCH="iphoneos-arm64"; PREFIX="/var/jb" ;;
  rootful)  ARCH="iphoneos-arm";   PREFIX="" ;;
  *) echo "!! variant يجب أن يكون rootless أو rootful (جاء: ${VARIANT})" >&2; exit 2 ;;
esac

[ -d "${APP}" ] || { echo "!! لا يوجد تطبيق في ${APP}" >&2; exit 1; }
command -v dpkg-deb >/dev/null || {
  echo "!! dpkg-deb غير مثبّت."
  echo "   على macOS:  brew install dpkg     (يوفّر dpkg-deb)"
  exit 1
}

[ -n "${OUT}" ] || OUT="${ROOT}/out/${PKG_NAME}-${VERSION}-${VARIANT}.deb"

EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${APP}/Info.plist" 2>/dev/null || true)"
[ -n "${EXEC_NAME}" ] || EXEC_NAME="Fieldwatch"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

PKGROOT="${WORK}/pkgroot"
APP_DIR="${PKGROOT}${PREFIX}/Applications/${PKG_NAME}.app"
mkdir -p "$(dirname "${APP_DIR}")"
cp -R "${APP}" "${APP_DIR}"

# تنظيف ونِسَب صحيحة (755 للمجلدات والتنفيذي، 644 للبقية)
find "${PKGROOT}" -name '.DS_Store' -delete 2>/dev/null || true
chmod -R go-w "${PKGROOT}" || true
chmod 755 "${PKGROOT}${PREFIX}/Applications" "${APP_DIR}"
chmod 755 "${APP_DIR}/${EXEC_NAME}"

# Installed-Size بالكيلوبايت (مطلوب عمليًا لعرضه في Sileo)
INSTALLED_KB="$(( $(du -sk "${APP_DIR}" | cut -f1) ))"

CONTROL="${PKGROOT}/DEBIAN/control"
mkdir -p "${PKGROOT}/DEBIAN"
cat > "${CONTROL}" <<CONTROL_EOF
Package: ${PKG_ID}
Name: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${ARCH}
Description: ${DESCRIPTION}
Maintainer: ${MAINTAINER}
Author: ${MAINTAINER}
Section: Applications
Priority: optional
Homepage: ${HOMEPAGE}
Depends: firmware (>= 15.0)
Installed-Size: ${INSTALLED_KB}
CONTROL_EOF

# سكربتات dpkg: تحديث أيقونة SpringBoard بعد التثبيت/الإزالة
postinst() {
  cat <<POSTINST_EOF
#!/bin/sh
APP="${PREFIX}/Applications/${PKG_NAME}.app"
uicache_path="\$(command -v uicache 2>/dev/null || true)"
[ -n "\$uicache_path" ] || uicache_path="${PREFIX}/usr/bin/uicache"
if [ -x "\$uicache_path" ]; then
  "\$uicache_path" -p "\$APP" 2>/dev/null || "\$uicache_path" -a 2>/dev/null || true
fi
echo ""
echo "Fieldwatch installed."
echo "  • إن لم تظهر الأيقونة:  uicache -a    (أو sbreload)"
echo "  • ثم افتح التطبيق واضغط: تشخيص Wi-Fi (probe)"
echo ""
exit 0
POSTINST_EOF
}

cat > "${PKGROOT}/DEBIAN/postinst" <<POSTINST_EOF
$(postinst)
POSTINST_EOF
cat > "${PKGROOT}/DEBIAN/postrm" <<POSTRM_EOF
#!/bin/sh
APP="${PREFIX}/Applications/${PKG_NAME}.app"
uicache_path="\$(command -v uicache 2>/dev/null || true)"
[ -n "\$uicache_path" ] || uicache_path="${PREFIX}/usr/bin/uicache"
if [ -x "\$uicache_path" ]; then
  "\$uicache_path" -a 2>/dev/null || true
fi
exit 0
POSTRM_EOF
chmod 755 "${PKGROOT}/DEBIAN/postinst" "${PKGROOT}/DEBIAN/postrm"

mkdir -p "$(dirname "${OUT}")"
rm -f "${OUT}"

# --root-owner-group: في الحزم الجاهزة للتوزيع (dpkg >= 1.19). وإن لم يُدعم، نكمل بدونه.
if ! dpkg-deb --root-owner-group -Zxz --build "${PKGROOT}" "${OUT}" >/dev/null 2>&1; then
  if ! dpkg-deb --root-owner-group --build "${PKGROOT}" "${OUT}" >/dev/null 2>&1; then
    dpkg-deb --build "${PKGROOT}" "${OUT}" >/dev/null
  fi
fi

echo "==> ${OUT}"
echo "    variant: ${VARIANT} | architecture: ${ARCH}"
echo "    install path: ${PREFIX}/Applications/${PKG_NAME}.app"
echo "    size: $(du -h "${OUT}" | cut -f1) | Installed-Size: ${INSTALLED_KB} KB"
