#!/usr/bin/env bash
# Kurulumu salt-okunur doğrular. Hiçbir şeyi değiştirmez.
set -uo pipefail

VAULT_PATH="${HOME}/IkinciBeyin"
SETTINGS="${HOME}/.claude/settings.json"
FAIL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT_PATH=$2; shift 2 ;;
    --vault=*) VAULT_PATH=${1#--vault=}; shift ;;
    --help|-h) echo "Kullanım: ./verify.sh [--vault <yol>]"; exit 0 ;;
    *) echo "Bilinmeyen seçenek: $1"; exit 2 ;;
  esac
done

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

echo ""
echo "İkinci Beyin doğrulaması"
echo "────────────────────────"
echo ""
echo "Bağımlılıklar"
command -v python3 >/dev/null 2>&1 && ok "python3" || bad "python3 yok — motor çalışmaz"
command -v jq      >/dev/null 2>&1 && ok "jq"      || warn "jq yok — bazı kancalar sessizce atlanır"
command -v claude  >/dev/null 2>&1 && ok "claude CLI" || warn "claude CLI yok — özet üretilemez"

echo ""
echo "Vault: ${VAULT_PATH}"
[ -d "$VAULT_PATH" ] && ok "dizin var" || bad "dizin yok"
for f in Core.md Kurallar.md Last-Session.md Threads.md; do
  [ -f "${VAULT_PATH}/🔮 850-Companion/${f}" ] && ok "850-Companion/${f}" || bad "850-Companion/${f} eksik"
done
[ -d "${VAULT_PATH}/🏰 300-Projects/gunluk-rapor/reports" ] \
  && ok "günlük rapor dizini" || bad "günlük rapor dizini eksik"

echo ""
echo "Motor"
ENGINE="${VAULT_PATH}/.beyin/engine"
for h in lib.sh session-start.sh session-end.sh session-continuity.sh pre-compact.sh prompt-counter.sh; do
  if [ -x "${ENGINE}/hooks/${h}" ]; then ok "hooks/${h}"
  elif [ -f "${ENGINE}/hooks/${h}" ]; then bad "hooks/${h} çalıştırılabilir değil (chmod +x)"
  else bad "hooks/${h} eksik"; fi
done
for s in flush.py retry_deferred_flush.py; do
  if [ -f "${ENGINE}/scripts/${s}" ]; then
    python3 -m py_compile "${ENGINE}/scripts/${s}" 2>/dev/null \
      && ok "scripts/${s}" || bad "scripts/${s} derlenmiyor"
  else
    bad "scripts/${s} eksik"
  fi
done

PENDING=$(find "${ENGINE}/scripts/.state/deferred-flush" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
if [ "${PENDING:-0}" -gt 0 ]; then
  warn "${PENDING} oturum özeti üretilemedi ve beklemede"
  warn "İşlemek için: python3 \"${ENGINE}/scripts/retry_deferred_flush.py\""
else
  ok "bekleyen özet yok"
fi

echo ""
echo "Kanca bağlantısı: ${SETTINGS}"
if [ ! -f "$SETTINGS" ]; then
  bad "settings.json yok"
else
  SETTINGS="$SETTINGS" VAULT_PATH="$VAULT_PATH" python3 <<'PYTHON'
import json, os, sys
from pathlib import Path
path = Path(os.environ["SETTINGS"])
marker = str(Path(os.environ["VAULT_PATH"]) / ".beyin" / "engine" / "hooks")
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    print(f"  \033[31m✗\033[0m settings.json okunamadı: {exc}"); sys.exit(1)
hooks = data.get("hooks") or {}
expected = {
    "SessionStart": ["session-start.sh"],
    "UserPromptSubmit": ["prompt-counter.sh"],
    "SessionEnd": ["session-end.sh", "session-continuity.sh"],
    "PreCompact": ["pre-compact.sh"],
}
failed = False
for event, names in expected.items():
    wired = json.dumps(hooks.get(event, []), ensure_ascii=False)
    for name in names:
        if f"{marker}/{name}" in wired:
            print(f"  \033[32m✓\033[0m {event} → {name}")
        else:
            print(f"  \033[31m✗\033[0m {event} → {name} bağlı değil"); failed = True
sys.exit(1 if failed else 0)
PYTHON
  [ $? -eq 0 ] || FAIL=1
fi

echo ""
echo "Çalışma kuralı"
if [ -f "${HOME}/CLAUDE.md" ]; then
  grep -qF "$VAULT_PATH" "${HOME}/CLAUDE.md" \
    && ok "~/CLAUDE.md vault yolunu gösteriyor" \
    || warn "~/CLAUDE.md var ama bu vault'u göstermiyor"
else
  warn "~/CLAUDE.md yok — Claude çalışma kurallarını görmez"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mHer şey yerinde.\033[0m Claude Code'"'"'u yeniden başlat.\n\n'
else
  printf '\033[31mEksikler var.\033[0m ./install.sh --vault "%s" ile tekrar dene.\n\n' "$VAULT_PATH"
fi
exit "$FAIL"
