# Panduan Setup Domain Kustom untuk RMS Pro

## **Apa yang Telah Diimplementasi**

✅ **Fitur dalam Aplikasi:**
1. UI untuk input domain kustom dalam menu "Link"
2. Logik simpan domain ke Firestore
3. Semua 4 link menggunakan domain kustom:
   - Borang Booking
   - Borang Pelanggan  
   - Katalog Telefon
   - Bio Link

## **Cara Penggunaan dalam App**

1. **Pergi ke menu "Link"**
2. **Lihat kad "Domain Kustom"** di bahagian atas
3. **Paste domain anda** (contoh: `https://kedaisaya.com`)
4. **Toggle "Gunakan domain kustom"** (optional)
5. **Klik "Simpan"** - domain akan disimpan ke Firestore
6. **Semua link automatik update** dengan domain baru

## **Setting di Penyedia Domain (UNTUK WILDCARD REDIRECT)**

### **Konsep Wildcard Redirect:**
- Main domain: `kedaisaya.com` (dipaste dalam app)
- Semua path/subdomain redirect ke `rmspro.net`
- Contoh:
  - `kedaisaya.com/borang_booking.html` → `rmspro.net/borang_booking.html`
  - `kedaisaya.com/catalog` → `rmspro.net/catalog`
  - `links.kedaisaya.com` → `rmspro.net/links.html`

### **Panduan untuk Provider Berbeza:**

#### **1. CLOUDFLARE (Recommended)**
```
1. Add domain ke Cloudflare
2. DNS Settings → Add Record:
   - Type: CNAME
   - Name: *
   - Content: rmspro.net
   - Proxy status: DNS only
   - TTL: Auto
3. Page Rules (untuk HTTPS):
   - URL: *.kedaisaya.com/*
   - Setting: Forwarding URL
   - Destination: https://rmspro.net/$2
   - Status: 301 Permanent
```

#### **2. CPANEL / STANDARD HOSTING**
**File: .htaccess (Apache)**
```apache
RewriteEngine On
RewriteCond %{HTTP_HOST} ^(.*\.)?kedaisaya\.com$ [NC]
RewriteRule ^(.*)$ https://rmspro.net/$1 [R=301,L]
```

#### **3. NAMECHEAP**
```
1. Domain List → Manage → Advanced DNS
2. Add New Record:
   - Type: URL Redirect
   - Host: @
   - Value: https://rmspro.net
   - Redirect Type: Permanent (301)
3. Untuk wildcard: Host: *
```

#### **4. GODADDY**
```
1. My Products → DNS → Manage
2. Add Record:
   - Type: Forwarding
   - From: @ (atau *)
   - To: https://rmspro.net
   - Forward Type: Permanent (301)
   - Settings: Forward only
```

#### **5. LOCAL PROVIDER (MYNIC, etc.)**
```
1. DNS Management → Add Record
2. Cari "URL Redirect" atau "Web Forwarding"
3. Set:
   - Source: @ (root domain)
   - Destination: https://rmspro.net
   - Type: 301 Permanent
4. Untuk semua subdomain: Source: *
```

## **Testing Setup**

### **Sebelum Setting DNS:**
1. Paste domain dalam app: `https://kedaisaya.com`
2. Link akan kelihatan: `https://kedaisaya.com/borang_booking.html`
3. **TAPI** link akan broken (404) kerana belum di-redirect

### **Setelah Setting DNS:**
1. **Test redirect:** Buka `https://kedaisaya.com`
2. **Test dengan path:** `https://kedaisaya.com/borang_booking.html`
3. **Test dengan parameters:** `https://kedaisaya.com/catalog?owner=ABC&shop=MAIN`
4. Semua harus redirect ke `rmspro.net` dengan path/parameters yang sama

## **Nota Penting**

### **1. SSL/HTTPS**
- Pastikan domain anda ada SSL certificate
- Cloudflare提供免费SSL
- Atau gunakan Let's Encrypt

### **2. Propagation Time**
- DNS changes boleh ambil 24-48 jam
- Gunakan `dig kedaisaya.com` atau `nslookup kedaisaya.com` untuk check

### **3. Path Preservation**
- Pastikan redirect preserve path (`/borang_booking.html`)
- Dan preserve query parameters (`?id=xxx&shop=yyy`)

### **4. Firestore Rules**
```javascript
// firestore.rules
match /saas_dealers/{dealerId} {
  allow read: if true;
  allow write: if request.auth != null && 
               request.auth.uid == dealerId;
}
```

## **Troubleshooting**

### **Problem: Redirect tidak berfungsi**
```
1. Check DNS propagation: dig kedaisaya.com
2. Test dengan curl: curl -I https://kedaisaya.com
3. Pastikan redirect type 301 (bukan 302)
```

### **Problem: Path hilang selepas redirect**
```
1. Pastikan setting "Forward with path" aktif
2. Untuk .htaccess: pastikan $1 dalam RewriteRule
3. Untuk Cloudflare: gunakan $2 dalam Page Rules
```

### **Problem: HTTPS error**
```
1. Pastikan domain ada SSL
2. Cloudflare: aktifkan "Always Use HTTPS"
3. Atau redirect http→https dulu
```

## **Support**

Jika ada masalah:
1. **Provider mana?** (Cloudflare, cPanel, Namecheap, etc.)
2. **Error message apa?**
3. **Screenshot dari DNS settings**

---

**Dibangunkan untuk:** RMS Pro Flutter App  
**Versi:** 1.0  
**Tarikh:** 4 Mac 2026