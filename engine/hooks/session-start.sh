#!/bin/bash
[ -n "${BEYIN_INVOKED_BY:-}" ] && exit 0
# Yeni oturumu yönlendirmek için gereken küçük, görevler-arası hafızayı enjekte eder.
# Proje notları ve tam politikalar, bir görev onları gerektirene kadar diskte kalır;
# hepsini her oturuma taşımak görev bağlamını seyreltir.

BEYIN_HOOK_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$BEYIN_HOOK_DIR/lib.sh" 2>/dev/null || exit 0

BEYIN_MEMORY_DIR="$BEYIN_PROJECT_DIR/🔮 850-Companion"
mkdir -p "$BEYIN_STATE_DIR" 2>/dev/null || :
beyin_cleanup_session_state

BEYIN_SESSION_KEY=$(beyin_session_key 2>/dev/null || :)
if [ -n "$BEYIN_SESSION_KEY" ]; then
  BEYIN_SESSION_START_FILE="$BEYIN_STATE_DIR/session_start_time.$BEYIN_SESSION_KEY"
  BEYIN_PROMPT_COUNT_FILE="$BEYIN_STATE_DIR/prompt_count.$BEYIN_SESSION_KEY"
  date '+%s' > "$BEYIN_SESSION_START_FILE" 2>/dev/null || :
  printf '%s\n' 0 > "$BEYIN_PROMPT_COUNT_FILE" 2>/dev/null || :
fi

BEYIN_LAST_SESSION=""
if [ -f "$BEYIN_MEMORY_DIR/Last-Session.md" ]; then
  BEYIN_LAST_SESSION=$(awk '
    /^## Session:/ { count++; if (count > 2) exit; active = 1 }
    active { print }
  ' "$BEYIN_MEMORY_DIR/Last-Session.md" 2>/dev/null | sed -n '1,50p')
fi

BEYIN_THREADS=""
if [ -f "$BEYIN_MEMORY_DIR/Threads.md" ]; then
  BEYIN_THREADS=$(sed -n '/^## Active/,/^## Closed/p' "$BEYIN_MEMORY_DIR/Threads.md" 2>/dev/null \
    | grep -E '^### |^\*\*Status:\*\*' 2>/dev/null \
    | sed -n '1,12p')
fi

BEYIN_RULES=""
if [ -f "$BEYIN_MEMORY_DIR/Kurallar.md" ]; then
  BEYIN_RULES=$(sed -n '1,60p' "$BEYIN_MEMORY_DIR/Kurallar.md" 2>/dev/null)
fi

BEYIN_NL='
'
BEYIN_REFLECTION=""
for BEYIN_REFLECTION_FILE in \
  "$BEYIN_STATE_DIR/needs_reflection" \
  "$BEYIN_STATE_DIR"/needs_reflection.*
do
  [ -f "$BEYIN_REFLECTION_FILE" ] || continue
  BEYIN_REFLECTION_DETAIL=$(sed -n '1p' "$BEYIN_REFLECTION_FILE" 2>/dev/null || :)
  if [ -n "$BEYIN_REFLECTION_DETAIL" ]; then
    [ -n "$BEYIN_REFLECTION" ] && BEYIN_REFLECTION="${BEYIN_REFLECTION}${BEYIN_NL}"
    BEYIN_REFLECTION="${BEYIN_REFLECTION}⚠️ Önceki oturum hafıza güncellemeden bitti: ${BEYIN_REFLECTION_DETAIL}. Anlamlı bir şey olduysa 🔮 850-Companion dosyalarını güncelle."
  fi
  rm -f "$BEYIN_REFLECTION_FILE" 2>/dev/null || :
done

# Katı bölüm sınırları, açılış özetini kanca bağlam limitinin altında tutar.
# Ayrıntılı geçmiş buraya enjekte edilmez; adı geçen dosyalardan okunur.
beyin_cap_section() {
  BEYIN_CAP_VALUE=$1
  BEYIN_CAP_LIMIT=$2
  BEYIN_CAP_NOTE=$3
  if [ "${#BEYIN_CAP_VALUE}" -le "$BEYIN_CAP_LIMIT" ]; then
    printf '%s' "$BEYIN_CAP_VALUE"
    return 0
  fi

  BEYIN_CAP_KEEP=$((BEYIN_CAP_LIMIT - ${#BEYIN_CAP_NOTE} - 1))
  [ "$BEYIN_CAP_KEEP" -gt 0 ] || BEYIN_CAP_KEEP=0
  printf '%s\n%s' "${BEYIN_CAP_VALUE:0:$BEYIN_CAP_KEEP}" "$BEYIN_CAP_NOTE"
}

BEYIN_LAST_SESSION=$(beyin_cap_section "$BEYIN_LAST_SESSION" 1200 \
  '[not: son oturum özeti kırpıldı; gerekirse dosyadan oku]')
BEYIN_THREADS=$(beyin_cap_section "$BEYIN_THREADS" 600 \
  '[not: aktif konu listesi kırpıldı; gerekirse dosyadan oku]')
BEYIN_RULES=$(beyin_cap_section "$BEYIN_RULES" 1000 \
  '[not: kurallar kırpıldı; gerekirse dosyadan oku]')
BEYIN_REFLECTION=$(beyin_cap_section "$BEYIN_REFLECTION" 400 \
  '[not: hafıza uyarıları kırpıldı; gerekirse dosyadan oku]')

BEYIN_TRUNCATED=0
BEYIN_CONTEXT_LIMIT=3600
BEYIN_CLOSING='[Hafıza yönlendirmesi] Süreklilik senin sorumluluğun. Anlamlı görevde önce 🔮 850-Companion/Core.md ve görevle ilgili en dar proje/bilgi notunu oku. Görev sözleşmesini (hedef, sınırlar, kabul ölçütü, belirsizlik, doğrulama) kur; ayrıntılı indeks ve politikaları yalnız gerektiğinde aç.'
BEYIN_TRUNCATION_NOTE='[not: başlangıç özeti kırpıldı; ilgili dosyayı aç]'
BEYIN_CAP_DIAGNOSTIC='Beyin uyarısı: Oturum başlangıç özeti bağlam limitini aştı. Bölüm limitlerini kontrol et.'

beyin_build_context() {
  BEYIN_CONTEXT=""
  [ -n "$BEYIN_REFLECTION" ] && BEYIN_CONTEXT="${BEYIN_CONTEXT}${BEYIN_REFLECTION}${BEYIN_NL}${BEYIN_NL}"
  if [ -n "$BEYIN_LAST_SESSION$BEYIN_THREADS" ]; then
    BEYIN_CONTEXT="${BEYIN_CONTEXT}[Hafıza: Süreklilik]${BEYIN_NL}${BEYIN_LAST_SESSION}${BEYIN_NL}${BEYIN_THREADS}${BEYIN_NL}${BEYIN_NL}"
  fi
  [ -n "$BEYIN_RULES" ] && BEYIN_CONTEXT="${BEYIN_CONTEXT}[Hafıza: Kurallar]${BEYIN_NL}${BEYIN_RULES}${BEYIN_NL}${BEYIN_NL}"
  [ "$BEYIN_TRUNCATED" -eq 1 ] && BEYIN_CONTEXT="${BEYIN_CONTEXT}${BEYIN_TRUNCATION_NOTE}${BEYIN_NL}${BEYIN_NL}"
  BEYIN_CONTEXT="${BEYIN_CONTEXT}${BEYIN_CLOSING}"
}

beyin_build_context
if [ "${#BEYIN_CONTEXT}" -gt "$BEYIN_CONTEXT_LIMIT" ]; then
  BEYIN_TRUNCATED=1
  beyin_build_context

  BEYIN_OVER=$(( ${#BEYIN_CONTEXT} - BEYIN_CONTEXT_LIMIT ))
  if [ "$BEYIN_OVER" -gt 0 ] && [ -n "$BEYIN_REFLECTION" ]; then
    if [ "$BEYIN_OVER" -ge "${#BEYIN_REFLECTION}" ]; then
      BEYIN_REFLECTION=""
    else
      BEYIN_KEEP=$(( ${#BEYIN_REFLECTION} - BEYIN_OVER ))
      BEYIN_REFLECTION=${BEYIN_REFLECTION:0:$BEYIN_KEEP}
    fi
    beyin_build_context
  fi
fi

if [ "${#BEYIN_CONTEXT}" -gt "$BEYIN_CONTEXT_LIMIT" ]; then
  BEYIN_CONTEXT=$BEYIN_CAP_DIAGNOSTIC
fi

[ -n "$BEYIN_LAST_SESSION$BEYIN_THREADS" ] && BEYIN_SOURCE_COUNT=1 || BEYIN_SOURCE_COUNT=0
[ -n "$BEYIN_RULES" ] && BEYIN_SOURCE_COUNT=$((BEYIN_SOURCE_COUNT + 1))
BEYIN_CONTEXT_TS=$(date --iso-8601=seconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || :)
printf '{"timestamp":"%s","context_chars_loaded":%s,"context_sources_count":%s,"truncated":%s}\n' \
  "$BEYIN_CONTEXT_TS" "${#BEYIN_CONTEXT}" "$BEYIN_SOURCE_COUNT" "$BEYIN_TRUNCATED" \
  >> "$BEYIN_STATE_DIR/context-loads.jsonl" 2>/dev/null || :

[ -n "$BEYIN_CONTEXT" ] && beyin_emit SessionStart "$BEYIN_CONTEXT"
exit 0
