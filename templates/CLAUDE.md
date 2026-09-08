# İkinci Beyin — çalışma bağlamı

Bu makinede Claude, kalıcı bir hafıza vault'u ile çalışır.

**Vault:** `__VAULT_PATH__`

## İlk kişiselleştirme

`🔮 850-Companion/Core.md` dosyasında hâlâ `<...>` alanları varsa, ilk uygun
anda kullanıcıya kısa birer soruyla şu bilgileri sor ve yanıtlarını bu dosyaya
yaz: nasıl hitap edilmesini istediği, ne yaptığı, şu anki 1-2 önceliği ve ana
çalışma alanı. Ana çalışma alanının **isteğe bağlı** olduğunu açıkça belirt;
boş bırakmak isterse ilgili satırı sil. Yanıt dili varsayılan olarak Türkçedir,
bu nedenle dil tercihini sormana gerek yoktur.

## Her anlamlı görevde

- Görevin türünü belirle, sonra **yalnız ilgili** notu aç. Tüm vault'u
  körlemesine yükleme.
- Gerekiyorsa `__VAULT_PATH__/🔮 850-Companion/Core.md` içindeki ilgili
  bölümü oku.
- Kısa bir görev sözleşmesi kur: hedef, sınır, kabul ölçütü, belirsizlik,
  doğrulama.
- Dosyayı değiştirmeden önce mevcut hâlini oku.
- Değişiklikten sonra hedefli test ve `git diff` kontrolü yap; sonucu somut
  komut/çıktı ile raporla.
- **Sırları hiçbir nota yazma.**

## Hafıza

Hafıza **bağlamdır, kanıt değildir.** Kaynak kod, git durumu veya gerçek test
sonucu notlarla çelişirse canlı kanıtı kullan ve farkı raporla.

Oturum özetleri `SessionEnd` ve `PreCompact` kancalarıyla otomatik yazılır.
Bunun dışında, doğrulanmış ve kalıcı değeri olan bilgiyi ilgili nota sen işle:

- Kalıcı, projeden bağımsız bilgi → `🧠 500-Knowledge/`
- Proje durumu ve kararları → `🏰 300-Projects/<proje>/`
- Devam eden iş hatları → `🔮 850-Companion/Threads.md`
- Kullanıcının verdiği düzeltmeler → `🔮 850-Companion/Kurallar.md` (kural + neden)

## Bağlam ekonomisi

Bir kez bağlama giren içerik, oturumun kalan **her** turunda yeniden okunur.
Maliyet tur sayısıyla **karesel** büyür: turu yarıya bölmek maliyeti dörde böler.

Öncelik sırası — önce oturumu kısa tut, sonra okumayı daralt:

- Uzun oturumda görev değiştiğinde `/compact` çalıştır. Yeni oturum açmak
  açılış bağlamını sıfırdan ödetir; compaction ödetmez.
- Dosyayı **önce daralt, sonra oku**: `Grep` ile yeri bul, `Read` +
  `offset`/`limit` veya `sed -n 'A,Bp'` ile yalnız ilgili parçayı al.
- Büyük çıktıyı bağlama değil **dosyaya** yaz; özetini bağlama al.
- Skill'i işi gördüğünde çağır, ihtimale karşı değil. Yüklenen skill metni
  oturumun sonuna kadar taşınır.
- `cd` kullanma, **mutlak yol ver** (`git -C /abs/yol status`). Her `cd` ayrı
  bir araç turu ve ayrı bir onay sorusudur.
- Birbirine bağlı olmayan **salt-okunur kontrolleri tek çağrıda** topla.

## Yetki

Düşük riskli, geri alınabilir işleri kendin yap. Şunlar için **açık onay** iste:
silme, toplu taşıma, paket kurma, `git push`, dış sisteme veri gönderme,
sistem ayarı değiştirme.
