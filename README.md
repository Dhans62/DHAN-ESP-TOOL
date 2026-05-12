# DHAN-ESP-TOOL

> Terminal User Interface (TUI) untuk mengelola siklus pengembangan ESP32 & ESP8266 di Linux.  
> Dioptimalkan untuk SBC/STB dengan sumber daya terbatas.

---

## Versi

| Versi | Keterangan |
|-------|-----------|
| **v7.0-PRO** *(current)* | Telegram exporter, SPIFFS/LittleFS, SHA256, Device Info, Custom Partition, Adaptive UI |
| v5.3-PRO-BIN | Binary export awal |
| v4 | Versi awal publik |

---

## Fitur Utama

### Manajemen Proyek
- **Smart Sync** — sinkronisasi otomatis nama `.ino` terhadap nama folder proyek
- **Project Creator** — buat proyek baru dengan boilerplate standar langsung dari TUI
- **Build Cache Cleaner** — bersihkan artefak kompilasi untuk jaga ruang penyimpanan

### Konfigurasi Board
Mendukung penuh parameter FQBN untuk semua keluarga ESP:

| Board | Chip | Keterangan |
|-------|------|-----------|
| ESP32 Classic | ESP32-D0WD | Dual Core, Xtensa LX6 |
| ESP32-C3 | ESP32-C3 | Single Core, RISC-V |
| ESP32-S2 | ESP32-S2 | Single Core, Xtensa LX7 |
| ESP32-S3 | ESP32-S3 | Dual Core, Xtensa LX7 |
| ESP32-H2 | ESP32-H2 | RISC-V, Zigbee/BT5 |
| ESP32-C6 | ESP32-C6 | RISC-V, WiFi6/BT5 |
| ESP8266 | ESP8266 | NodeMCU v2 |

Parameter yang bisa dikonfigurasi:
- USB CDC On Boot (ESP32-C3/S3)
- Partition Scheme (Default, Huge APP, Min SPIFFS, No OTA, **Custom CSV**)
- CPU Frequency Scaling
- Flash Mode (DIO/QIO) dan Flash Frequency
- Debug Level
- Upload preference (langsung flash / tanya backup dulu)

### Engine Kompilasi
- **Compile Spinner** — animasi braille tanpa teks, bersih dan ringan
- **Parallel Build** — pakai semua core CPU via `-j $(nproc)` untuk kecepatan maksimal
- **Custom Partition CSV** — inject file `.csv` partisi kustom otomatis saat compile
- **Error Terstruktur** — saat gagal, tampilkan file + nomor baris + pesan error
- **Memory Report** — tampilkan penggunaan flash dan RAM setelah compile sukses
- **Log Permanen** — setiap compile tersimpan di `~/log/<project>/`

### Flashing
- **Auto Port Detection** — deteksi `/dev/ttyACM*` dan `/dev/ttyUSB*` otomatis
- **Realtime Upload Log** — progress bar dan log esptool muncul baris per baris
- **Auto Retry sudo** — jika akses port ditolak, otomatis retry dengan `chmod 666`
- **Disconnect Handler** — jika device terputus saat upload, tampilkan opsi reconnect atau kembali

### SPIFFS / LittleFS Upload `[s]`
- Auto-detect `mklittlefs` atau `mkspiffs` dari PATH maupun `~/.arduino15`
- **Offset otomatis** dari partition table — lookup table per chip × per scheme
- **Custom CSV support** — baca offset & size langsung dari file `.csv` kustom
- Validasi ukuran: cek apakah folder `data/` muat di partisi sebelum build
- Warning otomatis jika scheme `huge_app` (FS hanya 192KB)
- Tampilkan usage: `68KB / 192KB (35%)`

### Telegram Exporter `[t]`
Kirim file binary langsung ke Telegram Bot setelah compile.

**File yang dikirim:**
| File | Keterangan |
|------|-----------|
| `SHA256SUMS.txt` | Checksum semua file untuk verifikasi integritas |
| `*.merged.bin` | Firmware all-in-one, flash di offset `0x0` |
| `*.ino.bin` | App binary saja, offset `0x10000` |
| `*.ino.bootloader.bin` | Bootloader, offset per chip |
| `*.ino.partitions.bin` | Partition table, offset `0x8000` |
| `*.spiffs.bin` | Filesystem image, offset dari partition table |

**Mode kirim:**
- `[1]` Semua file
- `[2]` `merged.bin` saja (rekomen untuk end-user)
- `[3]` `merged.bin` + `spiffs.bin`

**Caption tiap file mencantumkan:**
- Flash offset yang tepat
- Flash mode & frequency
- Flash size
- SHA256 checksum
- Instruksi flash untuk ESP32 Flasher (Android)

**Merge binary:**
- Otomatis merge bootloader + partitions + firmware menjadi satu file
- Flash mode dibaca dari FQBN (bukan hardcode)
- File `*.ino.merged.bin` dari arduino-cli otomatis di-exclude (padding 4MB)

### Backup Firmware `[b]`
- Baca full flash dari ESP yang sedang jalan via `esptool read_flash`
- Pilih ukuran flash: 2MB / 4MB / 8MB / 16MB
- SHA256 checksum otomatis
- Metadata tersimpan di `~/esp_backups/<project>/<timestamp>/backup_info.txt`
- Opsi kirim langsung ke Telegram setelah backup

### Device Info `[i]`
Probe langsung ke hardware via `esptool flash_id`:

| Info | Keterangan |
|------|-----------|
| Chip | Nama dan revision chip |
| Core(s) | Jumlah core dan arsitektur |
| Crystal | Frekuensi crystal |
| SRAM | Total RAM dan estimasi heap tersedia |
| Flash | Ukuran flash aktual dari device |
| Flash Mfr | Manufacturer flash chip |
| SPI Mode/Speed | Mode dan kecepatan SPI |
| MAC Address | Alamat MAC WiFi |
| Partition Table | Baca langsung dari flash `0x8000` |

> Flash size dari device akan **override** nilai dari FQBN secara otomatis.  
> Warning muncul jika chip dari device tidak cocok dengan FQBN yang dikonfigurasi.

### Serial Monitor `[3]`
**Mode Read Only:**
- Timestamp per baris `[HH:MM:SS]`
- Warna otomatis: ERROR=merah, WARN=kuning, INFO/OK=hijau, HEAP=cyan

**Mode Interactive:**
- Ketik langsung di terminal → Enter → terkirim ke device
- Menggunakan `python3 -m serial.tools.miniterm`
- `Ctrl+]` untuk keluar

**Baud rate:** 9600 / 57600 / 115200 / 230400 / 921600 / custom

### Auto-Install Dependencies
Saat pertama dijalankan, tools yang belum ada akan diinstall otomatis:
- `arduino-cli`
- `esptool` via pip
- Grup `dialout` untuk akses port USB

---

## Persyaratan Sistem

- **OS:** Linux (Debian/Ubuntu recommended)
- **Dependencies:** `curl`, `nano`, `sudo`, `python3`, `pip3`
- **Hardware:** ARM (STB/SBC) dan x86_64
- **Opsional:** `esptool` untuk merge binary, backup, dan device probe

---

## Instalasi

```bash
# Clone atau download esp.sh
chmod +x esp.sh

# Agar bisa dipanggil dari mana saja (pilih salah satu):

# Cara 1 — symlink ke /usr/local/bin
sudo ln -s $(pwd)/esp.sh /usr/local/bin/esp

# Cara 2 — copy ke ~/.local/bin (tanpa sudo)
cp esp.sh ~/.local/bin/esp
chmod +x ~/.local/bin/esp

# Cara 3 — alias di ~/.zshrc atau ~/.bashrc
echo "alias esp='bash ~/esp.sh'" >> ~/.zshrc
source ~/.zshrc
```

---

## Struktur Direktori

```
~/
├── esp.sh                    # Script utama
├── esp_backups/              # Backup firmware
│   └── <project>/
│       └── <timestamp>/
│           ├── *.bin
│           └── backup_info.txt
├── log/                      # Log compile
│   └── <project>/
│       └── YYYY-MM-DD_HH-MM-SS.log
└── Arduino/
    ├── libraries/
    └── <project>/
        ├── <project>.ino
        ├── data/             # File untuk SPIFFS/LittleFS
        ├── partitions.csv    # Custom partition (opsional)
        ├── build_output/     # Hasil compile
        │   ├── *.bin
        │   ├── *.merged.bin
        │   ├── *.spiffs.bin
        │   └── SHA256SUMS.txt
        └── .esp_config       # Konfigurasi board per-proyek
```

---

## Konfigurasi Telegram Bot

Edit dua baris di awal `esp.sh`:

```bash
BOT_TOKEN="your_bot_token_here"
CHAT_ID="your_chat_id_here"
```

Cara dapat token dan chat ID:
1. Buka [@BotFather](https://t.me/BotFather) → `/newbot` → salin token
2. Kirim pesan ke bot lo, lalu buka `https://api.telegram.org/bot<TOKEN>/getUpdates` → ambil `chat.id`

---

## Custom Partition CSV

Untuk firmware yang melebihi batas partisi default, buat file `partitions.csv` di folder proyek:

```csv
# Name,   Type, SubType, Offset,  Size, Flags
nvs,      data, nvs,     0x9000,  0x5000,
otadata,  data, ota,     0xe000,  0x2000,
app0,     app,  ota_0,   0x10000, 0x1F0000,
spiffs,   data, spiffs,  0x200000,0x1F0000,
coredump, data, coredump,0x3F0000,0x10000,
```

Tabel perbandingan partition scheme bawaan (flash 4MB):

| Scheme | App Size | SPIFFS Size |
|--------|----------|-------------|
| `default` | 1.28MB | 1.4MB |
| `huge_app` | 3MB | 192KB |
| `min_spiffs` | 1.9MB | 640KB |
| `no_ota` | 2MB | 960KB |
| **Custom CSV** | **hingga 1.94MB+** | **sesuai CSV** |

Script akan **auto-detect** file CSV di folder proyek dan inject parameter ke compile otomatis.

---

## Flash via Android (ESP32 Flasher)

Gunakan aplikasi [ESP32 Flash/Erase](https://play.google.com/store/apps/details?id=com.esp_flash.esp_flash_app).

**Setup:**
1. Download `merged.bin` dan `spiffs.bin` dari Telegram
2. Di aplikasi: pilih chip yang sesuai, Compression: OFF
3. Tambah file:
   - `merged.bin` → offset `0x0`
   - `spiffs.bin` → offset sesuai caption Telegram (contoh: `0x200000`)
4. Flash `merged.bin` dulu, lalu `spiffs.bin`

---

## Manajemen Izin Akses

```bash
sudo usermod -a -G dialout $USER
# Logout/login atau restart setelah perintah ini
```

Script akan otomatis menambahkan user ke grup `dialout` saat pertama dijalankan.

---

## Troubleshooting

| Masalah | Kemungkinan Penyebab | Solusi |
|---------|---------------------|--------|
| Device tidak terdeteksi | Kabel data-only, belum dialout | Ganti kabel, restart STB |
| Upload gagal | Port busy, permission denied | Script auto-retry sudo |
| Boot loop setelah flash | Flash mode salah (QIO vs DIO) | Re-config board, ganti Flash Mode |
| SPIFFS mount gagal | Image format tidak cocok (SPIFFS vs LittleFS) | Sesuaikan kode dengan tool yang dipakai |
| Firmware terlalu besar | Partisi default terlalu kecil | Gunakan Custom CSV partition |
| Merge bin gagal | esptool tidak ada | `pip install esptool` |

---

## Changelog

### v7.0-PRO *(2026)*
- Adaptive UI: header auto-resize berdasarkan lebar terminal, `SIGWINCH` trap
- Device Info `[i]`: probe hardware langsung, baca chip/flash/MAC/partition table
- Custom Partition CSV: auto-detect, inject ke compile, baca offset dari CSV
- SPIFFS/LittleFS upload `[s]` dengan offset per-chip per-scheme dari lookup table
- Backup firmware `[b]` via `esptool read_flash` dengan SHA256 dan opsi Telegram
- Telegram exporter: SHA256SUMS.txt, 3 mode kirim, caption lengkap per file
- Serial monitor: timestamp+warna (read-only) dan interactive mode via pyserial
- Compile spinner: animasi braille tanpa teks, cursor hide/show
- Upload realtime via FIFO pipe
- Compile error terstruktur: file + baris + pesan
- Disconnect handler dengan opsi reconnect
- Upload preference (langsung / tanya backup dulu) tersimpan di config
- Auto-install esptool via pip saat startup
- Hapus konfirmasi `yes` sebelum flash

### v5.3-PRO-BIN
- Export binary ke Telegram
- Merge bin via esptool
- Multi-file send dengan caption offset

### v4 *(2026 — versi awal publik)*
- Compile & upload via arduino-cli
- Auto port detection
- Board configurator dengan FQBN
- Library manager
- Serial monitor terintegrasi
- Log compile permanen
- Build cache cleaner
- Smart sync project file

---

## Lisensi

MIT License — bebas digunakan, dimodifikasi, dan didistribusikan ulang selama mencantumkan atribusi.

---

## Disclaimer

Disediakan *"apa adanya"* tanpa jaminan dalam bentuk apapun. Penulis tidak bertanggung jawab atas kerusakan hardware atau kehilangan data. Selalu pastikan tegangan input stabil saat flashing, terutama via STB/Android.

---

**DHAN-ESP-TOOL** | Developed by [Dhann] | 2026
