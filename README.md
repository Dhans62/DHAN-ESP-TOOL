# DHAN-ESP-TOOL V4

DHAN-ESP-TOOL adalah antarmuka berbasis teks (Terminal User Interface - TUI) yang dirancang untuk mengelola siklus pengembangan perangkat lunak pada mikrokontroler keluarga ESP32 dan ESP8266 melalui lingkungan Linux Terminal. 

Alat ini dioptimalkan khusus untuk dijalankan pada perangkat Single Board Computer (SBC) atau Set-Top Box (STB) yang memiliki keterbatasan sumber daya, dengan menerapkan manajemen daya melalui pembatasan penggunaan core prosesor saat kompilasi.

## Fitur Utama

### 1. Manajemen Proyek Otomatis
* **Smart Sync**: Menjamin integritas struktur folder Arduino dengan menyelaraskan nama file `.ino` utama terhadap nama folder proyek secara otomatis.
* **Project Creator**: Memungkinkan pembuatan proyek baru dengan boilerplate standar langsung dari antarmuka TUI.

### 2. Konfigurasi Board Komprehensif
* Mendukung penuh parameter FQBN (Fully Qualified Board Name).
* Pengaturan parameter internal meliputi:
    * USB CDC On Boot (Penting untuk keluarga ESP32-C3/S3).
    * Pemilihan Partition Scheme (Default, Huge APP, Minimal SPIFFS).
    * CPU Frequency Scaling.
    * Core Debug Level untuk keperluan debugging mendalam.
    * Flash Mode (DIO/QIO) dan Flash Frequency.

### 3. Engine Kompilasi Teroptimasi
* **Resource Management**: Menggunakan instruksi `-j 2` untuk membatasi beban kerja CPU, mencegah kegagalan sistem akibat lonjakan daya atau panas berlebih pada perangkat host.
* **Live Log Monitoring**: Menampilkan baris aktif dari proses kompilasi secara real-time untuk memastikan transparansi status proses tanpa membebani memori terminal.
* **Build Cache Cleaner**: Fitur manual untuk membersihkan artefak kompilasi guna menjaga ketersediaan ruang penyimpanan pada perangkat host.

### 4. Komunikasi & Flashing
* **Auto Port Detection**: Mendeteksi secara dinamis port `/dev/ttyACM*` atau `/dev/ttyUSB*`.
* **High-Speed Flashing**: Menggunakan protokol `esptool` dengan optimasi baud rate hingga 921600 bps untuk efisiensi transfer data.
* **Integrated Serial Monitor**: Monitor komunikasi serial terintegrasi dengan standar baud rate 115200.

## Persyaratan Sistem
* Sistem Operasi: Linux (Distro berbasis Debian/Ubuntu direkomendasikan).
* Dependencies: `curl`, `nano`, `sudo`.
* Hardware: Mendukung arsitektur ARM (STB/SBC) dan x86.

## Struktur Direktori
Alat ini mengikuti standar hirarki folder berikut:
```text
~/
├── esp.sh             # Script utama (TUI)
└── Arduino/           # Folder induk proyek
    ├── libraries/     # Library mikrokontroler
    └── [Nama_Proyek]/ # Folder proyek individu
        ├── [Nama].ino # Entry point kode
        └── .esp_config # File konfigurasi board spesifik proyek
