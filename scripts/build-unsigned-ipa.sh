#!/usr/bin/env bash
#
# build-unsigned-ipa.sh — مُغلِّف متوافق: يبني التطبيق (بلا صلاحيات) ثم يغلّفه IPA.
# (بقي هذا الاسم كي لا تتعطّل أي خطوة أو وثيقة تشير إليه.)
#
# للتحكّم الكامل استعمل مباشرةً:  scripts/build-all.sh
#
set -euo pipefail
cd "$(dirname "$0")"

ENTITLEMENTS="" bash ./build-app.sh
bash ./build-ipa.sh
