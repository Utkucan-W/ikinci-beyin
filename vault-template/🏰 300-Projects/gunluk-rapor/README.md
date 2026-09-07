# Günlük Rapor

Oturum özetleri buraya, `reports/YYYY-AA-GG.md` biçiminde **otomatik** yazılır.

Yazan: `.beyin/engine/scripts/flush.py`
Tetikleyen: oturum kapanışı (`SessionEnd`) ve bağlam sıkıştırması (`PreCompact`).

Her kayıt beş bölümdür: Bağlam, Önemli Konuşmalar, Alınan Kararlar,
Öğrenilenler, Yapılacaklar.

Bu klasörü elle düzenlemene gerek yok. Kalıcı değeri olan bir şey görürsen
`🧠 500-Knowledge` veya ilgili proje notuna taşı.
