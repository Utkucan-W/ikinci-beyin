# Nasıl çalışır

## Genel akış

```
Oturum açılır
   └─ SessionStart → session-start.sh
        Last-Session.md (son 2 kayıt) ─┐
        Threads.md (başlık + durum)   ─┼→ Claude'un bağlamı
        Kurallar.md (ilk 60 satır)    ─┘

Sen çalışırsın
   └─ UserPromptSubmit → prompt-counter.sh
        her 15 mesajda hatırlatma

Bağlam dolar
   └─ PreCompact → pre-compact.sh
        flush.py --reason precompact
        özet çıkar, günlük rapora yaz, özeti bağlama geri ver

Oturum kapanır
   └─ SessionEnd → session-end.sh (arka planda flush.py)
        └─ session-continuity.sh (son yazma hatalıysa uyar)
```

## Kancalar

| Dosya | Olay | Süre | İş |
|---|---|---|---|
| `session-start.sh` | SessionStart | 15 sn | Hafızayı bağlama yükler |
| `prompt-counter.sh` | UserPromptSubmit | 5 sn | Mesaj sayar, 15'te bir hatırlatır |
| `pre-compact.sh` | PreCompact | 45 sn | Sıkıştırma öncesi senkron özet |
| `session-end.sh` | SessionEnd | 10 sn | Arka planda özet başlatır |
| `session-continuity.sh` | SessionEnd | 3 sn | Son yazma hatalıysa uyarır |
| `lib.sh` | — | — | Ortak yardımcılar (çağrılmaz, kaynak alınır) |

Kancalar yollarını **kendi konumlarından türetir** (`$0/../../..` = vault kökü).
Hiçbirinde sabit yol yoktur; vault'u taşımak için yalnız `install.sh` yeniden
çalıştırılır.

## Özet üretimi (`flush.py`)

1. Kanca girdisinden `transcript_path` çözülür ve dosyanın gerçekten bu oturuma
   ait olduğu doğrulanır.
2. Son **30 tur**, en çok **15.000 karakter** okunur.
3. Metin `--- BEGIN UNTRUSTED TRANSCRIPT DATA ---` sınırları arasına alınır.
   Talimat biçimli satırlar tespit edilirse `health.json` uyarı yazar.
4. `claude --print` ile **araçsız** tek turluk özet istenir
   (`Bash,Write,Edit,NotebookEdit,WebFetch,WebSearch,Task` kapalı).
   `codex` varsa yedek sağlayıcıdır.
5. Dönen metin beş başlığa karşı doğrulanır. Şema tutmazsa yazılmaz.
6. `🏰 300-Projects/gunluk-rapor/reports/YYYY-AA-GG.md` dosyasına eklenir.

### Sağlayıcı seçimi

```bash
export BEYIN_SUMMARY_PROVIDERS=claude   # yalnız Claude (varsayılan: claude,codex)
export BEYIN_CLAUDE_MODEL=haiku         # varsayılan: sonnet
```

### Kaybolmama garantisi

Tüm sağlayıcılar düşerse döküm yolu `.state/deferred-flush/<anahtar>.json`
altına kuyruğa alınır. Sonra:

```bash
python3 <vault>/.beyin/engine/scripts/retry_deferred_flush.py
```

`./verify.sh` bekleyen kayıt sayısını gösterir.

## Bağlam sınırları

`session-start.sh` içinde sabit:

| Bölüm | Sınır |
|---|---|
| Son oturumlar | 1200 karakter |
| Konular | 600 karakter |
| Kurallar | 1000 karakter |
| Hafıza uyarıları | 400 karakter |
| **Toplam** | **3600 karakter** |

Aşan kısım kırpılır ve yerine "dosyadan oku" notu konur. Bu yüzden hafıza
dosyaların büyüdükçe açılış maliyetin artmaz.

## Durum dosyaları

`<vault>/.beyin/engine/scripts/.state/` — sürümlenmez, silinebilir:

| Dosya | İçerik |
|---|---|
| `health.json` | Son yazma işleminin durumu |
| `prompt_count.<hash>` | Oturum başına mesaj sayacı |
| `session_start_time.<hash>` | Oturum başlangıç zamanı |
| `needs_reflection.<hash>` | "Hafıza güncellenmeden bitti" işareti |
| `deferred-flush/` | Üretilemeyen özetlerin kuyruğu |
| `flush-*.json` | Yinelenen yazmayı önleyen kilit kaydı |

7 günden eski oturum durumu otomatik temizlenir.

## Tasarım kuralları

- **Kanca asla oturumu bloklamaz.** Her script `exit 0` ile biter; hata
  `health.json` dosyasına yazılır.
- **Özyineleme yok.** `BEYIN_INVOKED_BY` değişkeni ayarlıysa her kanca hemen
  çıkar — özet için açılan Claude çağrısı yeni kanca tetiklemez.
- **Yazma atomiktir.** Geçici dosyaya yazılır, doğrulanır, `os.replace` ile
  yerine konur.
- **Motor vault dışına yazmaz.** Tek istisna kurulum anıdır.
