# 850-Companion — asistan hafızası

Bu dört dosyanın adı motor tarafından bilinir; **yeniden adlandırma veya silme.**

| Dosya | Ne | Oturum başında bağlama girer mi |
|---|---|---|
| `Core.md` | Sen kimsin, asistan nasıl çalışsın | Hayır — asistan gerektiğinde açar |
| `Kurallar.md` | Verdiğin düzeltmeler, kalıcı kurallar | Evet, ilk 60 satır |
| `Last-Session.md` | Oturum özetleri, en yeni üstte | Evet, son 2 kayıt |
| `Threads.md` | Devam eden iş hatları | Evet, yalnız başlık + durum |

Bağlama giren her şeyin **karakter sınırı vardır** (`session-start.sh` içinde).
Dosyalar büyüdükçe bağlam maliyeti artmaz; yalnız kırpılan kısım artar.
