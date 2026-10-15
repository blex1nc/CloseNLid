# CloseNLid

**Coded by Blex** · [English](README.md)

MacBook'un kapağı kapalıyken uyumasını engelleyen bir menü çubuğu uygulaması.
Harici ekran, dock ya da fiş gerekmiyor — çantada, rafta, kapalı kapakla indirme,
render, derleme ve sunucular çalışmaya devam ediyor. Arayüz İngilizce, kod
yorumları Türkçe.

---

## Kurulum

Gereksinim: macOS 14 (Sonoma) veya üstü, Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/blex1nc/CloseNLid.git
cd CloseNLid
./Scripts/bundle.sh && open dist/CloseNLid.app
```

Uygulama menü çubuğuna bir şimşek simgesi olarak yerleşir; Dock'ta görünmez.
Ad-hoc imzalı olduğu için Gatekeeper ilk açılışta uyarabilir — o durumda
uygulamaya **sağ tıkla → Aç**.

Kalıcı kullanım için `dist/CloseNLid.app`'i Applications klasörüne taşı. Girişte
otomatik başlatma yalnızca paketlenmiş `.app` içinden çalışır.

---

## İlk açılış: yetki kuralı

Kapak kapanınca gelen uyku çekirdek düzeyinde bir davranış; engellemek root
istiyor. Her açma/kapamada şifre sormamak için ilk açılışta tek seferlik bir
sudoers kuralı kuruluyor. Uygulama ilk çalıştığında ayarlar penceresini doğrudan
**Access** bölmesinde açar; **Install Rule…** yönetici şifresini bir kez ister ve
şunu yazar:

```
/etc/sudoers.d/closenlid
<kullanıcı-adın> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
```

Kapsam bilerek bu kadar dar: joker yok, yalnızca bu iki tam komut şifresiz
çalışıyor. Dosya `/etc/sudoers.d` içine kopyalanmadan önce `visudo -c` ile
doğrulanıyor — bozuk bir kural makinedeki tüm sudo kullanımını kilitlerdi.

Kaldırmak için **Access → Remove Rule…**, ya da elle:

```bash
sudo rm /etc/sudoers.d/closenlid
```

---

## Özellikler

**Sleep** — ana anahtar ve süre. Süresiz, 30 dakika, 1 saat, 2 saat. Süreli
moddayken kalan zaman menü çubuğunda simgenin yanında sayıyor.

**Status** — kapak açık mı kapalı mı, uyku engelli mi, güç kaynağı ve sıcaklık.
Hepsi root gerektirmeden okunuyor. Dikkat edilmesi gereken bir durum varsa
(pilde çalışıyor, kapalı kapakla ısınmış, engeli başka bir şey açmış) burada
yazıyor.

**Battery** — fişten çekiliyken pil eşiğin altına düşerse uyku engeli
kendiliğinden kapanır ve sebebini söyleyen bir uyarı çıkar. Varsayılan %20.
Kapalı kapakta ekran karanlık olduğu için macOS'un düşük pil uyarısı görünmez;
bu koruma o boşluğu kapatıyor. Eşiğin altındayken anahtar zaten açılmıyor.

**Thermal** — kapak kapalıyken havalandırma kısıtlı olduğu için sıcaklık uyarısı
eşiği ayrı. Uyarı eşiği aşıldığında menü çubuğu simgesi ünlem işaretine dönüşür
ve menüde satır belirir; modal pencere çıkmaz (kapalı kapakta zaten kimse
görmez). İsteğe bağlı olarak kritik sıcaklıkta engeli otomatik kapatabilir —
varsayılan kapalı.

**General** — sürüm, girişte başlat, çıkış davranışı.

---

## Nasıl çalışıyor

İki katman var:

1. **`pmset -a disablesleep 1`** — kapak kapanışıyla gelen uykuyu engelleyen
   asıl ayar. Root ister, sistem genelindedir ve kalıcıdır.
2. **IOPM assertion** (`PreventUserIdleSystemSleep`) — boşta kalma uykusunu
   engeller, yetki istemez ve süreç ölürse kendiliğinden düşer.

Tek başına assertion yetmiyor: kapak kapanışı assertion'ları dinlemiyor. Tek
başına `disablesleep` de yetmiyor değil ama ikinci katman süreç çökerse en
azından boşta uykuyu geri getiriyor.

`pmset` sıfır dönse bile ayarın gerçekten yerleştiği IOPMrootDomain'den geri
okunarak doğrulanıyor; aksi halde arayüz "açık" gösterirken Mac kapak kapanınca
uyurdu.

Ekran uykusuna dokunulmuyor — kapak kapalıyken panel zaten kapanıyor, açık
bırakmanın anlamı yok.

### Ayar kalıcı, uygulama değil

`disablesleep` yeniden başlatmadan sonra da duran bir sistem ayarı. Uygulama
çıkarken normal uyku davranışını geri veriyor. Yine de bir şekilde uygulama
öldürülürse ayar açık kalır; bu yüzden CloseNLid her açılışta sistemin gerçek
durumunu okuyup devralıyor — anahtar açık görünür ve kapatabilirsin.

---

## Menü çubuğu

- `bolt.fill` — uyku engeli açık
- `bolt.slash` — normal uyku
- `exclamationmark.triangle.fill` — engel açık ve sıcaklık eşiği aşıldı

Menüde hızlı anahtar, süre seçimi, canlı durum satırları, ayarlar ve çıkış var.

---

## Geliştirme

```bash
swift build            # derle
swift run CloseNLid    # paketlenmemiş çalıştır (girişte başlat çalışmaz)
./Scripts/bundle.sh    # .app paketle, ikon üret, ad-hoc imzala
```

Sondalar:

```bash
CloseNLid --probe                 # durum çubuğu öğesi gerçekten çizildi mi
CloseNLid --settings battery      # ayarlar penceresini o bölmede aç
CloseNLid --make-icon icon.png    # uygulama ikonunu üret
```

Xcode gerekmiyor, Command Line Tools yetiyor. Universal derleme için tam Xcode
gerekir; yoksa betik bu makinenin mimarisiyle derler.

---

## Simge menü çubuğunda görünmüyorsa

Menü çubuğunda yer kalmadığında macOS öğeyi silmiyor — çentiğin arkasına
koyuyor ve tıklanacak hiçbir şey kalmıyor. Uygulama bunu açılışta fark edip bir
kez uyarıyor. Çözüm: başka bir menü çubuğu simgesini kaldır ya da ⌘ ile
sürükleyerek yerleri değiştir. Durumu doğrudan görmek için:

```bash
dist/CloseNLid.app/Contents/MacOS/CloseNLid --probe
```

---

## Bilinmesi gerekenler

- Kapalı kapakla çalışan bir Mac, klavye yüzeyi bir şeyin üstünde ve
  havalandırması kısıtlı halde ısınır. Yoğun iş için kapağı aralık bırakmak ya
  da sert bir yüzeye koymak fark yaratır.
- Fişte değilken pil koruması açık kalsın; kapalı kapakta pilin bittiğini fark
  etmenin başka yolu yok.
- Uygulama hiçbir yere veri göndermiyor. Yalnızca macOS güç yönetimiyle
  konuşuyor.

---

## Lisans

[MIT](LICENSE) © 2026 Blex
