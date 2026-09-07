#!/bin/bash
[ -n "${BEYIN_INVOKED_BY:-}" ] && exit 0
# Persist a short summary before compaction and return it as continuity context.
# A bounded synchronous wait avoids pruning the only copy before recovery data
# exists, while a failed summarization never blocks the compaction itself.

BEYIN_HOOK_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$BEYIN_HOOK_DIR/lib.sh" 2>/dev/null || exit 0

BEYIN_HOOK_INPUT="$BEYIN_STATE_DIR/hookin-$$.json"
umask 077
if ! cat > "$BEYIN_HOOK_INPUT" 2>/dev/null; then
  rm -f "$BEYIN_HOOK_INPUT" 2>/dev/null || :
  BEYIN_HOOK_INPUT=""
fi

if [ -z "$BEYIN_HOOK_INPUT" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  beyin_mark_python_missing
  rm -f "$BEYIN_HOOK_INPUT" 2>/dev/null || :
  beyin_emit PreCompact 'Beyin sıkıştırma öncesi özeti alınamadı: python3 bulunamadı. Kritik kararları compaction sonrası doğrula.'
  exit 0
fi

# Hook sözleşmesi kısa kalır; özet çağrısı 35 saniyede sonlanır ve Claude
# komut kancası için tanımlı 45 saniyelik üst sınırın içinde kalır.
BEYIN_FLUSH_RESULT=$(python3 "$BEYIN_PROJECT_DIR/.beyin/engine/scripts/flush.py" \
  --hook-input "$BEYIN_HOOK_INPUT" --reason precompact \
  --max-summary-chars 1200 --summary-timeout-seconds 35 --emit-result 2>/dev/null)
BEYIN_FLUSH_RC=$?

if [ "$BEYIN_FLUSH_RC" -ne 0 ]; then
  beyin_emit PreCompact 'Beyin sıkıştırma öncesi özeti zamanında alınamadı; compaction devam ediyor. Kritik kararları sonraki bağlamda doğrula.'
  exit 0
fi

BEYIN_FLUSH_STATUS=$(printf '%s' "$BEYIN_FLUSH_RESULT" | jq -r '.status // empty' 2>/dev/null || :)
BEYIN_FLUSH_SUMMARY=$(printf '%s' "$BEYIN_FLUSH_RESULT" | jq -r '.summary // empty' 2>/dev/null || :)

case "$BEYIN_FLUSH_STATUS" in
  appended)
    # Hard-cap the returned context even if the summarizer ignores its limit.
    if [ "${#BEYIN_FLUSH_SUMMARY}" -gt 1200 ]; then
      BEYIN_FLUSH_SUMMARY="${BEYIN_FLUSH_SUMMARY:0:1140}
[not: devam özeti 1200 karaktere kırpıldı; tam kayıt günlük raporda]"
    fi
    if [ -n "$BEYIN_FLUSH_SUMMARY" ]; then
      beyin_emit PreCompact "[Hafıza: Compaction Öncesi Devam Özeti]
$BEYIN_FLUSH_SUMMARY

Bu özet günlük rapora kaydedildi. Compaction sonrası açık kararları ve yapılacakları bu bağlamla sürdür."
    fi
    ;;
  fail)
    beyin_emit PreCompact 'Beyin sıkıştırma öncesi özeti üretilemedi; compaction devam ediyor. Kritik kararları sonraki bağlamda doğrula.'
    ;;
esac
exit 0
