#!/bin/bash
[ -n "${BEYIN_INVOKED_BY:-}" ] && exit 0
# Oturum kapanırken son hafıza yazma işlemi hatalıysa uyarır.

BEYIN_HOOK_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$BEYIN_HOOK_DIR/lib.sh" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

BEYIN_HEALTH_FILE="$BEYIN_STATE_DIR/health.json"
BEYIN_HEALTH_ERROR=$(jq -r '.error // empty' "$BEYIN_HEALTH_FILE" 2>/dev/null || :)
if [ -n "$BEYIN_HEALTH_ERROR" ]; then
  beyin_emit SessionEnd "⚠️ Son hafıza yazma işlemi hata gösteriyor: ${BEYIN_HEALTH_ERROR}. Önemli kararları elle 🔮 850-Companion/Last-Session.md dosyasına taşı."
fi
exit 0
