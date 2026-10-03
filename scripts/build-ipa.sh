#!/usr/bin/env bash
#
# build-ipa.sh — يغلّف Fieldwatch.app في ملف .ipa غير موقّع بتوقيع آبل.
#
#   الاستخدام:  bash scripts/build-ipa.sh [--app <path>] [--out <file.ipa>]
#
# إن كان التطبيق موقّعًا مسبقًا بـ ldid مع صلاحيات (انظر build-app.sh)، فالتوقيع
# يُحفظ داخل الـ IPA — وهذا بالضبط ما يجعله صالحًا لـ TrollStore (يحفظ الصلاحيات).
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP="${ROOT}/out/Fieldwatch.app"
IPA="${ROOT}/out/Fieldwatch-unsigned.ipa"

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --out) IPA="$2"; shift 2 ;;
    *) echo "وسيط غير معروف: $1" >&2; exit 2 ;;
  esac
done

[ -d "${APP}" ] || { echo "!! لا يوجد تطبيق في ${APP}" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/Payload"
cp -R "${APP}" "${WORK}/Payload/"

mkdir -p "$(dirname "${IPA}")"
rm -f "${IPA}"
( cd "${WORK}" && zip -qry "${IPA}" Payload )

echo "==> ${IPA}"
ls -lh "${IPA}" | awk '{print "    الحجم:", $5}'
