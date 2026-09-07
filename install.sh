#!/usr/bin/env bash
# İkinci Beyin kurulumu — Claude Code için kalıcı hafıza.
# Idempotent: tekrar çalıştırmak güvenlidir. Mevcut dosyaların üzerine yazmaz.
set -euo pipefail

REPO_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VAULT_PATH="${HOME}/IkinciBeyin"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS="${CLAUDE_DIR}/settings.json"
ASSUME_YES=0

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[31mHATA:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Kullanım: ./install.sh [seçenekler]

  --vault <yol>   Vault dizini (varsayılan: ~/IkinciBeyin)
  --yes           Soru sorma, doğrudan kur
  --help          Bu yardımı göster

Kurulum hiçbir mevcut dosyanın üzerine yazmaz. ~/.claude/settings.json
değiştirilmeden önce yedeklenir.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) [ $# -ge 2 ] || die "--vault bir yol bekliyor"; VAULT_PATH=$2; shift 2 ;;
    --vault=*) VAULT_PATH=${1#--vault=}; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Bilinmeyen seçenek: $1 (--help)" ;;
  esac
done

case "$VAULT_PATH" in
  "~/"*) VAULT_PATH="${HOME}/${VAULT_PATH#\~/}" ;;
  /*) ;;
  *) VAULT_PATH="$(pwd)/${VAULT_PATH}" ;;
esac

ENGINE_DEST="${VAULT_PATH}/.beyin/engine"

# ---------------------------------------------------------------- 1. bağımlılık
say ""
say "İkinci Beyin kurulumu"
say "─────────────────────"
say ""
say "1/5  Bağımlılıklar"

command -v python3 >/dev/null 2>&1 || die "python3 bulunamadı. Hafıza motoru python3 olmadan çalışmaz."
ok "python3 $(python3 --version 2>&1 | awk '{print $2}')"

if command -v jq >/dev/null 2>&1; then
  ok "jq"
else
  warn "jq bulunamadı. Kurulum tamamlanır ama bazı kancalar sessizce atlanır."
  warn "Kurmak için:  Debian/Ubuntu: sudo apt install jq  |  macOS: brew install jq  |  Arch: sudo pacman -S jq"
fi

if command -v claude >/dev/null 2>&1; then
  ok "claude CLI"
else
  warn "claude CLI PATH'te yok. Oturum özetleri üretilemez."
  warn "Kurmak için:  npm install -g @anthropic-ai/claude-code"
fi

# ------------------------------------------------------------------- 2. özet
say ""
say "2/5  Yapılacaklar"
say "     Vault           : ${VAULT_PATH}"
say "     Motor           : ${ENGINE_DEST}"
say "     Kanca ayarı     : ${SETTINGS}"
say "     Çalışma kuralı  : ${HOME}/CLAUDE.md"
say ""

if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
  printf 'Devam edilsin mi? [E/h] '
  read -r reply
  case "$reply" in
    ''|[Ee]|[Ee][Vv][Ee][Tt]) ;;
    *) say "İptal edildi."; exit 0 ;;
  esac
fi

# -------------------------------------------------------------------- 3. vault
say ""
say "3/5  Vault"
mkdir -p "$VAULT_PATH"

copied=0
skipped=0
while IFS= read -r relative; do
  source_file="${REPO_DIR}/vault-template/${relative}"
  target_file="${VAULT_PATH}/${relative}"
  mkdir -p "$(dirname "$target_file")"
  if [ -e "$target_file" ]; then
    skipped=$((skipped + 1))
  else
    cp "$source_file" "$target_file"
    copied=$((copied + 1))
  fi
done < <(cd "${REPO_DIR}/vault-template" && find . -type f -not -name '.gitkeep' | sed 's|^\./||')

mkdir -p "${VAULT_PATH}/🏰 300-Projects/gunluk-rapor/reports"
ok "${copied} dosya oluşturuldu, ${skipped} mevcut dosya korundu"

if [ ! -f "${VAULT_PATH}/.gitignore" ]; then
  cat > "${VAULT_PATH}/.gitignore" <<'EOF'
# Motor çalışma durumu — sürümlenmez
.beyin/engine/scripts/.state/
.beyin/engine/**/__pycache__/

# Obsidian gürültüsü
.obsidian/workspace*
.obsidian/cache
.DS_Store
EOF
  ok ".gitignore oluşturuldu"
fi

# -------------------------------------------------------------------- 4. motor
say ""
say "4/5  Motor"
mkdir -p "${ENGINE_DEST}/hooks" "${ENGINE_DEST}/scripts/.state"
cp "${REPO_DIR}"/engine/hooks/*.sh "${ENGINE_DEST}/hooks/"
cp "${REPO_DIR}"/engine/scripts/*.py "${ENGINE_DEST}/scripts/"
chmod +x "${ENGINE_DEST}"/hooks/*.sh "${ENGINE_DEST}"/scripts/*.py
chmod 700 "${ENGINE_DEST}/scripts/.state"
ok "6 kanca + 2 script kuruldu"

if ! "${ENGINE_DEST}/hooks/session-start.sh" </dev/null >/dev/null 2>&1; then
  warn "session-start.sh deneme çalıştırmasında sıfırdan farklı kod döndü (kancalar yine de oturumu bloklamaz)"
else
  ok "kancalar çalıştırılabilir"
fi

# -------------------------------------------------------------------- 5. ayar
say ""
say "5/5  Claude Code kancaları"
mkdir -p "$CLAUDE_DIR"

VAULT_PATH="$VAULT_PATH" SETTINGS="$SETTINGS" python3 <<'PYTHON'
import json, os, shutil, sys, time
from pathlib import Path

settings_path = Path(os.environ["SETTINGS"])
hooks_dir = Path(os.environ["VAULT_PATH"]) / ".beyin" / "engine" / "hooks"

WIRING = {
    "SessionStart":     [("session-start.sh", 15)],
    "UserPromptSubmit": [("prompt-counter.sh", 5)],
    "SessionEnd":       [("session-end.sh", 10), ("session-continuity.sh", 3)],
    "PreCompact":       [("pre-compact.sh", 45)],
}
MARKER = "/.beyin/engine/hooks/"

settings = {}
if settings_path.exists():
    raw = settings_path.read_text(encoding="utf-8")
    try:
        settings = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError as exc:
        sys.exit(f"  {settings_path} geçerli JSON değil ({exc}). Elle düzelt, sonra tekrar dene.")
    if not isinstance(settings, dict):
        sys.exit(f"  {settings_path} bir JSON nesnesi değil. Elle düzelt, sonra tekrar dene.")
    backup = settings_path.with_name(
        f"{settings_path.name}.bak-ikinci-beyin-{time.strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(settings_path, backup)
    print(f"  \033[32m✓\033[0m yedek: {backup.name}")

hooks = settings.setdefault("hooks", {})
if not isinstance(hooks, dict):
    sys.exit("  settings.json içindeki 'hooks' bir nesne değil. Elle düzelt, sonra tekrar dene.")

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

added = removed = 0
for event, scripts in WIRING.items():
    groups = hooks.get(event) or []
    if not isinstance(groups, list):
        sys.exit(f"  settings.json içindeki hooks.{event} bir dizi değil. Elle düzelt.")
    # Önceki kurulumdan kalan girdileri at; kullanıcının kendi kancalarına dokunma.
    kept = []
    for group in groups:
        if not isinstance(group, dict) or "hooks" not in group:
            kept.append(group)          # tanımadığımız biçim — olduğu gibi bırak
            continue
        inner = group.get("hooks") or []
        survivors = [h for h in inner if not ours(h)]
        removed += len(inner) - len(survivors)
        if survivors:
            group["hooks"] = survivors  # karma grup: yalnız bizimkini çıkar
            kept.append(group)
        elif not inner:
            kept.append(group)          # zaten boştu, bizim değil
        # tamamen bizim olan grup düşer
    entries = []
    for name, timeout in scripts:
        entries.append({
            "type": "command",
            "command": f'"{hooks_dir / name}"',
            "timeout": timeout,
        })
        added += 1
    kept.append({"hooks": entries})
    hooks[event] = kept

temporary = settings_path.with_name(f".{settings_path.name}.ikinci-beyin.tmp")
temporary.write_text(json.dumps(settings, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
json.loads(temporary.read_text(encoding="utf-8"))  # yazmadan önce doğrula
os.replace(temporary, settings_path)
print(f"  \033[32m✓\033[0m {added} kanca bağlandı, {removed} eski girdi temizlendi")
PYTHON

# CLAUDE.md
if [ -f "${HOME}/CLAUDE.md" ]; then
  warn "${HOME}/CLAUDE.md zaten var — dokunulmadı."
  warn "Şablonu görmek için: ${REPO_DIR}/templates/CLAUDE.md"
else
  sed "s|__VAULT_PATH__|${VAULT_PATH}|g" "${REPO_DIR}/templates/CLAUDE.md" > "${HOME}/CLAUDE.md"
  ok "${HOME}/CLAUDE.md oluşturuldu"
fi

say ""
say "─────────────────────"
say "Kurulum tamam."
say ""
say "Sırada:"
say "  1. ${VAULT_PATH}/🔮 850-Companion/Core.md dosyasındaki <...> alanlarını doldur."
say "  2. Claude Code'u yeniden başlat. Açılışta hafıza bağlamı yüklenecek."
say "  3. Doğrula:  ./verify.sh --vault \"${VAULT_PATH}\""
say ""
say "Kaldırmak için: ./uninstall.sh --vault \"${VAULT_PATH}\""
say ""
