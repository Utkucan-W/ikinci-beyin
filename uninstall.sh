#!/usr/bin/env bash
# Kancaları söker ve motoru kaldırır. Notlarına DOKUNMAZ.
set -euo pipefail

VAULT_PATH="${HOME}/IkinciBeyin"
SETTINGS="${HOME}/.claude/settings.json"
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT_PATH=$2; shift 2 ;;
    --vault=*) VAULT_PATH=${1#--vault=}; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --help|-h) echo "Kullanım: ./uninstall.sh [--vault <yol>] [--yes]"; exit 0 ;;
    *) echo "Bilinmeyen seçenek: $1"; exit 2 ;;
  esac
done

echo ""
echo "İkinci Beyin kaldırma"
echo "─────────────────────"
echo ""
echo "Kaldırılacak:"
echo "  • ${SETTINGS} içindeki ikinci-beyin kancaları"
echo "  • ${VAULT_PATH}/.beyin/ (motor ve çalışma durumu)"
echo ""
echo "KORUNACAK:"
echo "  • Tüm notların ve klasörlerin"
echo "  • ~/CLAUDE.md"
echo ""

if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
  printf 'Devam edilsin mi? [e/H] '
  read -r reply
  case "$reply" in
    [Ee]|[Ee][Vv][Ee][Tt]) ;;
    *) echo "İptal edildi."; exit 0 ;;
  esac
fi

if [ -f "$SETTINGS" ]; then
  SETTINGS="$SETTINGS" python3 <<'PYTHON'
import json, os, shutil, sys, time
from pathlib import Path
path = Path(os.environ["SETTINGS"])
MARKER = "/.beyin/engine/hooks/"
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    sys.exit(f"  settings.json okunamadı ({exc}); elle temizle.")

backup = path.with_name(f"{path.name}.bak-ikinci-beyin-{time.strftime('%Y%m%d%H%M%S')}")
shutil.copy2(path, backup)

def ours(entry):
    """Daha önce bu kurulumun eklediği bir kanca girdisi mi?

    Yalnız `command` alanına bakılır. Tüm JSON'da arama yapmak, kullanıcının
    kendi kancasının herhangi bir alanında bu dizge geçtiğinde onu yanlışlıkla
    bizim sayıp silmeye yol açardı.
    """
    if not isinstance(entry, dict):
        return False
    command = entry.get("command")
    return isinstance(command, str) and MARKER in command

hooks = data.get("hooks") or {}
removed = 0
for event, groups in list(hooks.items()):
    if not isinstance(groups, list):
        continue
    kept = []
    for group in groups:
        if not isinstance(group, dict) or "hooks" not in group:
            kept.append(group); continue
        inner = group.get("hooks") or []
        survivors = [h for h in inner if not ours(h)]
        removed += len(inner) - len(survivors)
        if survivors:
            group["hooks"] = survivors
            kept.append(group)
        elif not inner:
            kept.append(group)
    if kept:
        hooks[event] = kept
    else:
        del hooks[event]
if not hooks:
    data.pop("hooks", None)

temporary = path.with_name(f".{path.name}.ikinci-beyin.tmp")
temporary.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
json.loads(temporary.read_text(encoding="utf-8"))
os.replace(temporary, path)
print(f"  \033[32m✓\033[0m {removed} kanca söküldü (yedek: {backup.name})")
PYTHON
else
  echo "  ! settings.json yok, atlanıyor"
fi

if [ -d "${VAULT_PATH}/.beyin" ]; then
  rm -rf "${VAULT_PATH}/.beyin"
  printf '  \033[32m✓\033[0m motor kaldırıldı\n'
else
  echo "  ! ${VAULT_PATH}/.beyin yok, atlanıyor"
fi

echo ""
echo "Bitti. Notların ${VAULT_PATH} içinde duruyor."
echo ""
