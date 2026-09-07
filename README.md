# İkinci Beyin

Claude Code için kalıcı hafıza. Her oturumun sonunda ne konuşulduğunu özetler,
her oturumun başında geri yükler. Böylece Claude, bir önceki konuşmayı hatırlar.

**Sorun:** Claude Code her oturumda sıfırdan başlar. Dün ne karar verdiğinizi,
projenizin nerede kaldığını, size kaç kez aynı şeyi anlattığınızı bilmez.

**Çözüm:** Konuşmalarınız otomatik özetlenip Markdown notlarına yazılır. Yeni
oturum açtığınızda son iki oturumun özeti ve açık iş hatlarınız Claude'un
bağlamına girer. Notlar sizin diskinizde, düz Markdown olarak durur —
Obsidian ile açabilir, Git ile yedekleyebilirsiniz.

## Ne yapar

| Ne zaman | Ne olur |
|---|---|
| Oturum açılışı | Son 2 oturum özeti + açık konular + kuralların bağlama yüklenir |
| Her 15 mesajda | Hafızayı güncellemen için kısa hatırlatma |
| Bağlam sıkışınca (`/compact`) | Kaybolmadan önce özet çıkarılır ve saklanır |
| Oturum kapanışı | Konuşma özetlenip günlük rapora yazılır |

Özet beş bölümdür: **Bağlam, Önemli Konuşmalar, Alınan Kararlar, Öğrenilenler,
Yapılacaklar.**

## Gereksinimler

- **Claude Code** — `npm install -g @anthropic-ai/claude-code`
- **python3** (3.9+) — zorunlu, motor bunsuz çalışmaz
- **jq** — `apt install jq` / `brew install jq` / `pacman -S jq`
- **bash** — Linux veya macOS. (Windows'ta WSL kullan.)

## Kurulum

### Yol 1 — Claude'a yaptır

```bash
git clone https://github.com/<kullanıcı>/ikinci-beyin.git
cd ikinci-beyin
claude
```

Sonra Claude'a şunu söyle:

> Bu repodaki README'yi oku ve ikinci beyin sistemini bilgisayarıma kur.

### Yol 2 — Kendin çalıştır

```bash
git clone https://github.com/<kullanıcı>/ikinci-beyin.git
cd ikinci-beyin
./install.sh
```

Vault'un yerini seçmek istersen:

```bash
./install.sh --vault ~/Notlar/Beynim
```

Kurulum **hiçbir mevcut dosyanın üzerine yazmaz.** `~/.claude/settings.json`
değiştirilmeden önce yedeklenir, kendi kancaların korunur. Tekrar çalıştırmak
güvenlidir.

## Kurulumdan sonra

1. **`<...>` alanlarını doldur:** `<vault>/🔮 850-Companion/Core.md` — asistan
   seni buradan tanır. Beş dakikanı ayır, sistemin değerinin yarısı burada.
2. **Claude Code'u yeniden başlat.** Kancalar açılışta yüklenir.
3. **Doğrula:** `./verify.sh`

Bir oturum çalış, kapat, yenisini aç. Açılışta önceki oturumun özetini
göreceksin.

## Nasıl çalışır

```
<vault>/
├── 🔮 850-Companion/          ← asistanın hafızası (motor okur/yazar)
│   ├── Core.md                   sen kimsin, asistan nasıl çalışsın
│   ├── Kurallar.md               verdiğin düzeltmeler
│   ├── Last-Session.md           oturum özetleri, en yeni üstte
│   └── Threads.md                devam eden iş hatları
├── 🏰 300-Projects/
│   └── gunluk-rapor/reports/     otomatik yazılan günlük özetler
├── 📥 000-Inbox/   🧠 500-Knowledge/   📦 900-Archive/
└── .beyin/engine/             ← motor (kancalar + scriptler)
```

Kancalar `~/.claude/settings.json` üzerinden bağlanır ve `<vault>/.beyin/engine/`
içinden çalışır. Vault'u taşırsan `./install.sh --vault <yeni yol>` ile tekrar
kur.

Ayrıntı: [`docs/NASIL-CALISIR.md`](docs/NASIL-CALISIR.md)

## Bağlam maliyeti

Açılışta bağlama giren metin ~1–3 KB'dir ve **katı üst sınırları vardır**
(`session-start.sh` içinde). Notların büyüdükçe bu maliyet artmaz; yalnız
kırpılan kısım artar.

Oturum sonu özeti, `claude` CLI ile ayrı ve araçsız bir çağrıdır. Uzun oturum =
tek özet çağrısı.

## Sorun giderme

| Belirti | Kontrol |
|---|---|
| Açılışta hafıza gelmiyor | `./verify.sh` — kancalar bağlı mı? Claude Code yeniden başlatıldı mı? |
| Oturum sonunda özet yazılmıyor | `claude` CLI PATH'te mi? `<vault>/.beyin/engine/scripts/.state/health.json` ne diyor? |
| "N oturum özeti beklemede" | `python3 <vault>/.beyin/engine/scripts/retry_deferred_flush.py` |
| Kancalar hiç çalışmıyor | `python3 --version` ve `jq --version` çalışıyor mu? |

Motor **hiçbir koşulda oturumu bloklamaz.** Bir şey bozulursa sessizce atlar ve
`health.json` dosyasına yazar.

## Kaldırma

```bash
./uninstall.sh
```

Kancaları söker, motoru siler. **Notlarına dokunmaz.**

## Güvenlik

- Parola, token ve API anahtarını **hiçbir nota yazma.** Vault'u Git'e
  gönderirsen sırlar geçmişe kalıcı olarak işlenir.
- Özetleyiciye giden konuşma metni **güvenilmeyen veri** olarak işaretlenir;
  içindeki talimat benzeri metinler uygulanmaz.
- Özet çağrısı araçsız çalışır (`Bash`, `Write`, `Edit`, `WebFetch` kapalı).
- Motor yalnız vault'a yazar; ev dizininde tek dokunduğu yer
  `~/.claude/settings.json` (yedekli) ve — yoksa — `~/CLAUDE.md`.

## Lisans

MIT — [`LICENSE`](LICENSE)
