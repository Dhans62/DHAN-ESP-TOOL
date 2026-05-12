#!/bin/bash
# ================================================================
#  DHAN ESP FLASHER  —  v7.0-PRO
#  Compile · Upload · Debug · Telegram · Backup · SHA256
# ================================================================

BOT_TOKEN="xxxxx:xxxxx"
CHAT_ID="xxxxx"

# ── Warna ────────────────────────────────────────────────────────
R=$'\033[0;31m'   G=$'\033[0;32m'   Y=$'\033[1;33m'
B=$'\033[0;34m'   C=$'\033[0;36m'   P=$'\033[0;35m'
W=$'\033[1;37m'   D=$'\033[0;90m'   N=$'\033[0m'
BLD=$'\033[1m'    DIM=$'\033[2m'

# ── Path ─────────────────────────────────────────────────────────
CLI_PATH=$(which arduino-cli 2>/dev/null)
[[ -z "$CLI_PATH" ]] && CLI_PATH="$HOME/.local/bin/arduino-cli"
ARDUINO_DIR="$HOME/Arduino"
LOG_BASE="$HOME/log"
BACKUP_BASE="$HOME/esp_backups"

# ── esptool auto-detect ──────────────────────────────────────────
if   command -v esptool   &>/dev/null; then ESPTOOL="esptool"
elif command -v esptool.py &>/dev/null; then ESPTOOL="esptool.py"
else ESPTOOL=""; fi

# ── Alt screen ───────────────────────────────────────────────────
open_alt()  { printf '\033[?1049h\033[H'; }
close_alt() { printf '\033[?1049l'; }
trap 'close_alt; exit' SIGINT SIGTERM EXIT

# ================================================================
# UI PRIMITIVES
# ================================================================

# Baca dimensi terminal — dipanggil ulang tiap hdr() agar responsive
_update_dims() {
    W_COLS=$(tput cols  2>/dev/null || echo 60)
    W_ROWS=$(tput lines 2>/dev/null || echo 24)
    # batas bawah agar UI tidak pecah
    (( W_COLS < 40 )) && W_COLS=40
    LINE=$(printf '%*s' "$W_COLS" '' | tr ' ' '─')
}

# SIGWINCH = terminal di-resize → update dims, tidak perlu redraw paksa
# (redraw terjadi natural saat user navigasi berikutnya)
trap '_update_dims' SIGWINCH

_update_dims   # inisialisasi awal

hr()  { printf "${B}%s${N}\n" "$LINE"; }
clr() { printf '\033[2J\033[H'; }

# Header adaptif berdasarkan lebar terminal
hdr() {
    _update_dims   # selalu fresh tiap halaman
    clr

    if (( W_COLS >= 68 )); then
        # Full block-art (butuh ~68 kolom)
        printf "${C}${BLD}"
        printf '  ██████  ██   ██  █████  ███    ██     ███████ ███████ ██████  \n'
        printf '  ██   ██ ██   ██ ██   ██ ████   ██     ██      ██      ██   ██ \n'
        printf '  ██   ██ ███████ ███████ ██ ██  ██     █████   ███████ ██████  \n'
        printf '  ██   ██ ██   ██ ██   ██ ██  ██ ██     ██           ██ ██      \n'
        printf '  ██████  ██   ██ ██   ██ ██   ████     ███████ ███████ ██      \n'
        printf "${N}"
        local sub=">>> Advanced TUI for ESP  |  v7.0-PRO <<<"
        local pad=$(( (W_COLS - ${#sub}) / 2 ))
        (( pad < 0 )) && pad=0
        printf "${Y}%*s%s${N}\n" "$pad" '' "$sub"

    elif (( W_COLS >= 44 )); then
        # Compact ASCII
        printf "${C}${BLD}"
        printf '  ██████╗ ██╗  ██╗ █████╗ ███╗\n'
        printf '  ██╔══██╗██║  ██║██╔══██╗████╗\n'
        printf '  ██║  ██║███████║███████║██╔██╗\n'
        printf '  ██████╔╝██║  ██║██║  ██║██║ ██╗\n'
        printf "${N}"
        printf "${Y}  ESP Flasher  v7.0-PRO${N}\n"

    else
        # Minimal — hanya teks
        printf "${C}${BLD}  DHAN ESP FLASHER  v7.0${N}\n"
    fi

    hr
}

# Status bar device
device_bar() {
    local port; port=$(detect_port)
    if [[ -n "$port" ]]; then
        local desc
        desc=$(lsusb 2>/dev/null             | grep -i "cp210\|ch340\|ft232\|ftdi\|prolific"             | head -n1 | sed 's/.*ID [^ ]* //')
        [[ -z "$desc" ]] && desc="Serial Device"

        if (( W_COLS >= 60 )); then
            printf "  ${G}● CONNECTED${N}  ${D}%s${N}  ${W}%s${N}\n" "$port" "$desc"
        else
            printf "  ${G}●${N} ${W}%s${N}\n" "$port"
        fi
    else
        if (( W_COLS >= 60 )); then
            printf "  ${R}○ NO DEVICE${N}  ${D}Tidak ada ESP terdeteksi${N}\n"
        else
            printf "  ${R}○ NO DEVICE${N}\n"
        fi
    fi
    hr
}

# ================================================================
# HELPERS
# ================================================================
detect_port() {
    ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -n1
}

# ── Partition table lengkap semua chip & scheme ──────────────────
# Format per entry: "boot_offset app_offset spiffs_offset spiffs_size flash_min"
declare -A _PT
# ESP32 Classic
_PT["esp32:default"]="0x1000 0x10000 0x290000 0x170000 4MB"
_PT["esp32:huge_app"]="0x1000 0x10000 0x3D0000 0x30000 4MB"
_PT["esp32:min_spiffs"]="0x1000 0x10000 0x360000 0xA0000 4MB"
_PT["esp32:no_ota"]="0x1000 0x10000 0x310000 0xF0000 4MB"
_PT["esp32:default_8MB"]="0x1000 0x10000 0x670000 0x190000 8MB"
_PT["esp32:rainmaker"]="0x1000 0x10000 0x3D0000 0x30000 4MB"
# ESP32-C3
_PT["esp32c3:default"]="0x0 0x10000 0x290000 0x170000 4MB"
_PT["esp32c3:huge_app"]="0x0 0x10000 0x3B0000 0x30000 4MB"
_PT["esp32c3:min_spiffs"]="0x0 0x10000 0x360000 0xA0000 4MB"
_PT["esp32c3:no_ota"]="0x0 0x10000 0x310000 0xF0000 4MB"
# ESP32-S2
_PT["esp32s2:default"]="0x1000 0x10000 0x290000 0x170000 4MB"
_PT["esp32s2:huge_app"]="0x1000 0x10000 0x3D0000 0x30000 4MB"
_PT["esp32s2:min_spiffs"]="0x1000 0x10000 0x360000 0xA0000 4MB"
# ESP32-S3
_PT["esp32s3:default"]="0x0 0x10000 0x290000 0x170000 4MB"
_PT["esp32s3:huge_app"]="0x0 0x10000 0x3D0000 0x30000 4MB"
_PT["esp32s3:min_spiffs"]="0x0 0x10000 0x360000 0xA0000 4MB"
_PT["esp32s3:default_8MB"]="0x0 0x10000 0x670000 0x190000 8MB"
# ESP32-H2
_PT["esp32h2:default"]="0x0 0x10000 0x290000 0x170000 4MB"
_PT["esp32h2:huge_app"]="0x0 0x10000 0x3B0000 0x30000 4MB"
# ESP32-C6
_PT["esp32c6:default"]="0x0 0x10000 0x290000 0x170000 4MB"
_PT["esp32c6:huge_app"]="0x0 0x10000 0x3B0000 0x30000 4MB"

# Lookup partition info → set global vars dari tabel
_apply_partition_table() {
    local chip="$1" scheme="$2"
    local key="${chip}:${scheme}"
    # fallback ke default jika scheme tidak ada di tabel
    [[ -z "${_PT[$key]+x}" ]] && key="${chip}:default"
    [[ -z "${_PT[$key]+x}" ]] && key="esp32:default"  # ultimate fallback
    read -r BOOT_OFFSET _APP_OFFSET SPIFFS_OFFSET SPIFFS_SIZE _FL_MIN \
        <<< "${_PT[$key]}"
}

# Baca offset & size dari custom CSV jika ada
# Set: SPIFFS_OFFSET, SPIFFS_SIZE, BOOT_OFFSET, CUSTOM_APP_SIZE_BYTES
_apply_csv_partition() {
    local csv="$1"
    [[ ! -f "$csv" ]] && return 1

    # Parse CSV — skip baris komentar dan kosong
    SPIFFS_OFFSET=""
    SPIFFS_SIZE=""
    local app_offset="" app_size=""

    while IFS=',' read -r name type subtype offset size _rest; do
        # trim whitespace
        name="${name// /}"; name="${name##\#*}"
        [[ -z "$name" ]] && continue
        type="${type// /}"
        subtype="${subtype// /}"
        offset="${offset// /}"
        size="${size// /}"

        case "$subtype" in
            spiffs|littlefs|fat)
                SPIFFS_OFFSET="$offset"
                SPIFFS_SIZE="$size"
                ;;
            ota_0|factory)
                app_offset="$offset"
                app_size="$size"
                ;;
        esac
    done < "$csv"

    # Konversi size hex → bytes untuk validasi
    if [[ -n "$SPIFFS_SIZE" ]]; then
        local hex="${SPIFFS_SIZE#0x}"
        SPIFFS_SIZE_BYTES=$(( 16#$hex ))
    fi
    if [[ -n "$app_size" ]]; then
        local hex="${app_size#0x}"
        CUSTOM_APP_SIZE_BYTES=$(( 16#$hex ))
    fi

    [[ -n "$SPIFFS_OFFSET" && -n "$SPIFFS_SIZE" ]]
}

# ── Baca chip & flash size langsung dari device (jika connect) ───
# Output: sets PROBED_CHIP, PROBED_FLASH_SIZE, PROBED_MAC
probe_device() {
    local port="$1"
    PROBED_CHIP=""
    PROBED_FLASH_SIZE=""
    PROBED_MAC=""
    [[ -z "$port" || -z "$ESPTOOL" ]] && return 1

    local probe_out
    probe_out=$($ESPTOOL --port "$port" flash_id 2>&1)
    [[ $? -ne 0 ]] && return 1

    # Parse chip name
    local raw_chip
    raw_chip=$(printf '%s' "$probe_out" | grep -i "Chip is" | head -1 | \
        sed 's/.*Chip is //' | tr '[:upper:]' '[:lower:]' | \
        sed 's/[[:space:]].*//')
    # Normalize ke nama esptool standard
    case "$raw_chip" in
        *esp32-c3*|*esp32c3*) PROBED_CHIP="esp32c3" ;;
        *esp32-s2*|*esp32s2*) PROBED_CHIP="esp32s2" ;;
        *esp32-s3*|*esp32s3*) PROBED_CHIP="esp32s3" ;;
        *esp32-h2*|*esp32h2*) PROBED_CHIP="esp32h2" ;;
        *esp32-c6*|*esp32c6*) PROBED_CHIP="esp32c6" ;;
        *esp32*)               PROBED_CHIP="esp32"   ;;
        *esp8266*)             PROBED_CHIP="esp8266" ;;
        *)                     PROBED_CHIP="$raw_chip" ;;
    esac

    # Parse flash size dari "Detected flash size: 4MB"
    PROBED_FLASH_SIZE=$(printf '%s' "$probe_out" | \
        grep -i "Detected flash size" | grep -oE "[0-9]+MB" | head -1)

    # Parse MAC
    PROBED_MAC=$(printf '%s' "$probe_out" | \
        grep -i "MAC:" | grep -oE "([0-9a-f]{2}:){5}[0-9a-f]{2}" | head -1)

    [[ -n "$PROBED_CHIP" ]]
}

get_chip_info() {
    # 1. Chip dari FQBN
    case "$FQBN" in
        *esp32c3*) CHIP_NAME="esp32c3" ;;
        *esp32s2*) CHIP_NAME="esp32s2" ;;
        *esp32s3*) CHIP_NAME="esp32s3" ;;
        *esp32h2*) CHIP_NAME="esp32h2" ;;
        *esp32c6*) CHIP_NAME="esp32c6" ;;
        *esp32*)   CHIP_NAME="esp32"   ;;
        *esp8266*) CHIP_NAME="esp8266" ;;
        *)         CHIP_NAME="unknown" ;;
    esac

    # 2. Flash mode
    if   [[ "$FQBN" == *"FlashMode=qio"* ]]; then FLASH_MODE="qio"
    elif [[ "$FQBN" == *"FlashMode=dio"* ]]; then FLASH_MODE="dio"
    elif [[ "$CHIP_NAME" == "esp8266" ]];    then FLASH_MODE="dio"
    else FLASH_MODE="qio"; fi

    # 3. Flash freq
    if   [[ "$FQBN" == *"FlashFreq=80"* ]]; then FLASH_FREQ="80m"
    else FLASH_FREQ="40m"; fi

    # 4. Flash size — dari FQBN, akan di-override probe jika connect
    if   [[ "$FQBN" == *"FlashSize=2M"*  ]]; then FLASH_SIZE="2MB"
    elif [[ "$FQBN" == *"FlashSize=8M"*  ]]; then FLASH_SIZE="8MB"
    elif [[ "$FQBN" == *"FlashSize=16M"* ]]; then FLASH_SIZE="16MB"
    else FLASH_SIZE="4MB"; fi

    # 5. Partition scheme dari FQBN
    local scheme="default"
    if   [[ "$FQBN" == *"PartitionScheme=huge_app"*    ]]; then scheme="huge_app"
    elif [[ "$FQBN" == *"PartitionScheme=min_spiffs"*  ]]; then scheme="min_spiffs"
    elif [[ "$FQBN" == *"PartitionScheme=no_ota"*      ]]; then scheme="no_ota"
    elif [[ "$FQBN" == *"PartitionScheme=default_8MB"* ]]; then scheme="default_8MB"
    elif [[ "$FQBN" == *"PartitionScheme=rainmaker"*   ]]; then scheme="rainmaker"
    fi
    PARTITION_SCHEME="$scheme"

    # 6. Cek custom CSV — prioritas tertinggi, override lookup table
    local csv="${CUSTOM_PARTITION_CSV:-}"
    # Auto-detect di folder project jika tidak ada di config
    if [[ -z "$csv" && -n "${PROJECT_PATH:-}" ]]; then
        for _f in "$PROJECT_PATH/partitions.csv" \
                  "$PROJECT_PATH/${selected_project:-}.csv" \
                  "$PROJECT_PATH/partition.csv"; do
            [[ -f "$_f" ]] && csv="$_f" && break
        done
    fi

    if [[ -n "$csv" ]] && _apply_csv_partition "$csv"; then
        PARTITION_SCHEME="custom:$(basename "$csv")"
        # BOOT_OFFSET tetap dari chip — CSV tidak tentukan ini
        case "$CHIP_NAME" in
            esp32c3|esp32s3|esp32h2|esp32c6|esp32s2) BOOT_OFFSET="0x0"    ;;
            *)                                         BOOT_OFFSET="0x1000" ;;
        esac
    else
        # Fallback ke lookup table
        _apply_partition_table "$CHIP_NAME" "$scheme"
    fi
}


# Probe + tampilkan info device lengkap
# Dipanggil dari upload_spiffs dan send_to_telegram
probe_and_show() {
    local port; port=$(detect_port)
    PROBED_CHIP=""; PROBED_FLASH_SIZE=""; PROBED_MAC=""
    FLASH_SIZE_SOURCE="FQBN"

    if [[ -n "$port" && -n "$ESPTOOL" ]]; then
        printf "${D} [i] Membaca info device dari %s...${N}
" "$port"
        if probe_device "$port"; then
            FLASH_SIZE_SOURCE="Device"
            # Override flash size dengan nilai aktual dari device
            [[ -n "$PROBED_FLASH_SIZE" ]] && FLASH_SIZE="$PROBED_FLASH_SIZE"
            # Re-apply partition table dengan flash size baru
            _apply_partition_table "$CHIP_NAME" "$PARTITION_SCHEME"

            printf "  ${G}● Device terdeteksi${N}\n"
            printf "  ${D}Chip     :${N} ${W}%s${N}\n" "$PROBED_CHIP"
            printf "  ${D}Flash    :${N} ${W}%s${N} ${G}(dibaca dari device)${N}\n" "$FLASH_SIZE"
            [[ -n "$PROBED_MAC" ]] &&                 printf "  ${D}MAC      :${N} ${W}%s${N}\n" "$PROBED_MAC"

            # Peringatan jika chip dari device tidak cocok dengan FQBN
            if [[ -n "$PROBED_CHIP" && "$PROBED_CHIP" != "$CHIP_NAME" ]]; then
                printf "\n  ${R}⚠ WARNING: Chip device (%s) != FQBN (%s)${N}\n" \
                    "$PROBED_CHIP" "$CHIP_NAME"
                printf "  ${Y}  Disarankan re-config board sebelum lanjut${N}\n"
            fi
        else
            printf "  ${Y}● Device connect tapi probe gagal (mode normal, bukan bootloader)${N}
"
            printf "  ${D}  Menggunakan nilai dari FQBN${N}
"
        fi
    else
        printf "  ${Y}○ Device tidak connect — menggunakan nilai dari FQBN${N}
"
    fi

    printf "  ${D}Chip     :${N} ${C}%s${N} ${D}(FQBN)${N}\n" "$CHIP_NAME"
    printf "  ${D}Flash    :${N} ${C}%s${N} ${D}(%s)${N}\n" "$FLASH_SIZE" "$FLASH_SIZE_SOURCE"
    printf "  ${D}Scheme   :${N} ${C}%s${N}\n" "$PARTITION_SCHEME"
    printf "  ${D}FS Offset:${N} ${C}%s${N}\n" "$SPIFFS_OFFSET"

    local fs_kb=$(( 16#${SPIFFS_SIZE#0x} / 1024 ))
    printf "  ${D}FS Size  :${N} ${C}%s${N} ${D}(%d KB)${N}\n" "$SPIFFS_SIZE" "$fs_kb"

    # Warning kalau partisi FS terlalu kecil untuk web asset
    if [[ "$PARTITION_SCHEME" == "huge_app" && -d "${PROJECT_PATH}/data" ]]; then
        local data_kb
        data_kb=$(du -sk "${PROJECT_PATH}/data" 2>/dev/null | cut -f1)
        local usage_pct=$(( data_kb * 100 / fs_kb ))
        if (( fs_kb < 256 )); then
            printf "\n  ${Y}⚠ huge_app: FS hanya %dKB — mepet untuk web asset${N}\n" "$fs_kb"
            printf "  ${D}  Penggunaan saat ini: %dKB / %dKB (%d%%)${N}\n" \
                "$data_kb" "$fs_kb" "$usage_pct"
            printf "  ${D}  Ganti ke 'default' scheme untuk FS 1.4MB jika perlu lebih${N}\n"
        fi
    fi
}

ensure_core() {
    $CLI_PATH core list 2>/dev/null | grep -q "$1" || {
        printf "${Y} [i] Core %s tidak ada, mengunduh...${N}\n" "$1"
        $CLI_PATH core install "$1"
    }
}

sync_project_file() {
    local fn; fn=$(basename "$PROJECT_PATH")
    local exp="$PROJECT_PATH/$fn.ino"
    [[ -f "$exp" ]] && return
    local found; found=$(ls "$PROJECT_PATH"/*.ino 2>/dev/null | head -n1)
    if [[ -n "$found" ]]; then mv "$found" "$exp"
    else $CLI_PATH sketch new "$PROJECT_PATH" &>/dev/null; fi
}

confirm_action() {
    printf "${Y} [?] %s${N}\n" "$1"
    read -rp "     Ketik 'yes' untuk lanjut: " _c
    [[ "$_c" == "yes" ]]
}

pause() { read -rp " ${D}Tekan ENTER untuk kembali...${N}"; }

# ================================================================
# DEVICE DISCONNECT HANDLER
# ================================================================
wait_reconnect() {
    # Dipanggil ketika device hilang di tengah proses
    hdr
    printf "\n  ${R}${BLD}! DEVICE TERPUTUS${N}\n\n"
    printf "  ${Y}[1]${N} Reconnect & scan ulang\n"
    printf "  ${Y}[2]${N} Keluar ke menu project\n"
    hr
    while true; do
        read -rp "  Pilih: " dc_choice
        case "$dc_choice" in
            1)
                printf "\n  ${Y}Menunggu device...${N}  "
                local i=0
                local sp=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
                while true; do
                    local p; p=$(detect_port)
                    if [[ -n "$p" ]]; then
                        printf "\r  ${G}● Device ditemukan: %s${N}          \n" "$p"
                        sleep 0.5
                        return 0   # reconnect OK
                    fi
                    printf "\r  ${Y}%s${N} Menunggu device...  " "${sp[$((i % 10))]}"
                    i=$((i+1)); sleep 0.15
                done
                ;;
            2) return 1 ;;   # keluar ke caller
        esac
    done
}

# ================================================================
# DEVICE INFO — full chip probe + RAM/Flash breakdown
# ================================================================
device_info() {
    hdr
    printf "${C}${BLD} DEVICE INFO${N}
"
    device_bar

    local port; port=$(detect_port)
    if [[ -z "$port" ]]; then
        printf "${R} [!] Tidak ada device terhubung.${N}
"
        printf "${D}     Hubungkan ESP dan coba lagi.${N}
"
        pause; return
    fi

    if [[ -z "$ESPTOOL" ]]; then
        printf "${R} [!] esptool tidak ada — tidak bisa probe device.${N}
"
        pause; return
    fi

    printf "${Y} [i] Membaca info dari %s...${N}\n\n" "$port"

    # ── Jalankan flash_id probe ──────────────────────────────────
    local raw; raw=$($ESPTOOL --port "$port" flash_id 2>&1)
    local eec=$?

    if [[ $eec -ne 0 ]] || echo "$raw" | grep -qi "failed\|error\|could not"; then
        # Coba dengan baud lebih rendah
        raw=$($ESPTOOL --port "$port" --baud 115200 flash_id 2>&1)
        eec=$?
    fi

    if [[ $eec -ne 0 ]]; then
        printf "${R} [✗] Probe gagal. Pastikan ESP dalam mode normal (bukan deep sleep).${N}\n"
        printf "${D}     Output esptool:\n"
        printf '%s\n' "$raw" | head -10 | sed "s/^/     /"
        printf "${N}\n"
        pause; return
    fi

    # ── Parse semua field ────────────────────────────────────────
    local chip_desc mac_addr flash_size flash_mfr crystal_freq chip_features
    local chip_rev spi_mode spi_speed

    chip_desc=$(printf '%s' "$raw" | grep -i "Chip is"        | sed 's/.*Chip is //')
    mac_addr=$(printf '%s' "$raw"  | grep -i "MAC:"           | grep -oE "([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}" | head -1)
    flash_size=$(printf '%s' "$raw"| grep -i "Detected flash" | grep -oE "[0-9]+MB" | head -1)
    flash_mfr=$(printf '%s' "$raw" | grep -i "Manufacturer:"  | sed 's/.*Manufacturer: //')
    crystal_freq=$(printf '%s' "$raw" | grep -i "Crystal"     | grep -oE "[0-9]+MHz" | head -1)
    chip_features=$(printf '%s' "$raw" | grep -i "Features:"  | sed 's/.*Features: //')
    chip_rev=$(printf '%s' "$raw"  | grep -i "revision"       | grep -oE "v?[0-9]+\.[0-9]+" | head -1)
    spi_mode=$(printf '%s' "$raw"  | grep -i "Flash mode"     | sed 's/.*Flash mode: //')
    spi_speed=$(printf '%s' "$raw" | grep -i "Flash speed"    | sed 's/.*Flash speed: //')

    # ── Derive chip name untuk lookup RAM ───────────────────────
    local chip_key
    case "${chip_desc,,}" in
        *esp32-c3*|*esp32c3*) chip_key="esp32c3" ;;
        *esp32-s2*|*esp32s2*) chip_key="esp32s2" ;;
        *esp32-s3*|*esp32s3*) chip_key="esp32s3" ;;
        *esp32-h2*|*esp32h2*) chip_key="esp32h2" ;;
        *esp32-c6*|*esp32c6*) chip_key="esp32c6" ;;
        *esp32*)               chip_key="esp32"   ;;
        *esp8266*)             chip_key="esp8266" ;;
        *)                     chip_key="unknown" ;;
    esac

    # RAM specs per chip (SRAM total, usable heap estimasi)
    # Source: Espressif datasheet
    local ram_total ram_heap ram_cores
    case "$chip_key" in
        esp32)   ram_total="520KB"; ram_heap="~320KB"; ram_cores="2 (Xtensa LX6 240MHz)" ;;
        esp32c3) ram_total="400KB"; ram_heap="~320KB"; ram_cores="1 (RISC-V 160MHz)"     ;;
        esp32s2) ram_total="320KB"; ram_heap="~240KB"; ram_cores="1 (Xtensa LX7 240MHz)" ;;
        esp32s3) ram_total="512KB"; ram_heap="~400KB"; ram_cores="2 (Xtensa LX7 240MHz)" ;;
        esp32h2) ram_total="320KB"; ram_heap="~256KB"; ram_cores="1 (RISC-V 96MHz)"      ;;
        esp32c6) ram_total="512KB"; ram_heap="~400KB"; ram_cores="1 (RISC-V 160MHz)"     ;;
        esp8266) ram_total="160KB"; ram_heap="~80KB";  ram_cores="1 (Xtensa L106 80MHz)" ;;
        *)       ram_total="?";     ram_heap="?";      ram_cores="?"                      ;;
    esac

    # ── Tampilkan semua info ─────────────────────────────────────
    hr
    printf "${W}${BLD} ▌ CHIP${N}
"
    printf "  %-18s ${W}%s${N}
"     "Chip"       "${chip_desc:-unknown}"
    printf "  %-18s ${C}%s${N}
"     "Revision"   "${chip_rev:-unknown}"
    printf "  %-18s ${C}%s${N}
"     "Core(s)"    "$ram_cores"
    printf "  %-18s ${C}%s${N}
"     "Crystal"    "${crystal_freq:-unknown}"
    [[ -n "$chip_features" ]] &&     printf "  %-18s ${D}%s${N}
"     "Features"   "$chip_features"
    hr

    printf "${W}${BLD} ▌ MEMORY${N}
"
    printf "  %-18s ${G}%s${N}
"     "SRAM Total"  "$ram_total"
    printf "  %-18s ${G}%s${N}
"     "Heap (est)"  "$ram_heap"
    printf "  %-18s ${G}%s${N}
"     "Flash"       "${flash_size:-unknown}"
    [[ -n "$flash_mfr" ]] &&     printf "  %-18s ${D}%s${N}
"     "Flash Mfr"   "$flash_mfr"
    printf "  %-18s ${D}%s${N}
"     "SPI Mode"    "${spi_mode:-unknown}"
    printf "  %-18s ${D}%s${N}
"     "SPI Speed"   "${spi_speed:-unknown}"
    hr

    printf "${W}${BLD} ▌ NETWORK${N}
"
    printf "  %-18s ${C}%s${N}
"     "MAC Address" "${mac_addr:-unknown}"
    hr

    # ── Partition table dari device ──────────────────────────────
    printf "${W}${BLD} ▌ PARTITION TABLE${N}
"
    local pt_raw
    pt_raw=$($ESPTOOL --port "$port" read_flash 0x8000 0x1000 /tmp/_esp_pt.bin 2>/dev/null &&              python3 -c "
import struct, sys
data = open('/tmp/_esp_pt.bin','rb').read()
# ESP partition magic = 0xAA50
entries = []
for i in range(0, min(len(data), 0xC00), 32):
    chunk = data[i:i+32]
    if len(chunk) < 32: break
    magic, ptype, subtype, offset, size = struct.unpack_from('<HBBII', chunk)
    if magic != 0xAA50: continue
    name = chunk[12:28].rstrip(b'\x00').decode('utf-8','ignore')
    type_str = {0:'app',1:'data'}.get(ptype, str(ptype))
    entries.append((name, type_str, offset, size))
for name, t, off, sz in entries:
    kb = sz // 1024
    mb = sz / (1024*1024)
    label = f'{mb:.2f}MB' if kb >= 1024 else f'{kb}KB'
    print(f'  {name:<12} {t:<6} 0x{off:06X}   {label}')
" 2>/dev/null)
    rm -f /tmp/_esp_pt.bin

    if [[ -n "$pt_raw" ]]; then
        printf "${D}  %-12s %-6s %-10s %s${N}
" "Name" "Type" "Offset" "Size"
        printf '%s
' "$pt_raw" | while IFS= read -r line; do
            # warnai baris app hijau, data abu
            if printf '%s' "$line" | grep -q " app "; then
                printf "${G}%s${N}
" "$line"
            else
                printf "${D}%s${N}
" "$line"
            fi
        done
    else
        printf "  ${Y}Tidak bisa baca partition table (perlu mode bootloader)${N}
"
        printf "  ${D}Tahan BOOT+RST lalu coba lagi, atau lihat di FQBN config${N}
"
    fi
    hr

    # ── Warning mismatch dengan FQBN ────────────────────────────
    if [[ -n "$flash_size" && -n "$FLASH_SIZE" && "$flash_size" != "$FLASH_SIZE" ]]; then
        printf "${R} ⚠ Flash device (%s) != config FQBN (%s)${N}
"             "$flash_size" "$FLASH_SIZE"
        printf "${Y}   Jalankan Re-config board untuk sinkronisasi${N}
"
        hr
    fi

    pause
}

# ================================================================
# COMPILE SPINNER  (animasi saja, tanpa teks stage)
# ================================================================
_compile_spinner() {
    local log="$1" pid="$2"
    # Braille spinner frames
    local sp=('⣾' '⣽' '⣻' '⢿' '⡿' '⣟' '⣯' '⣷')
    local i=0

    # sembunyikan kursor
    printf '\033[?25l'

    printf "\n"   # 1 baris reserved

    while kill -0 "$pid" 2>/dev/null; do
        printf '\033[1A\033[K'
        printf "  ${C}%s${N}\n" "${sp[$((i % 8))]}"
        i=$((i+1))
        sleep 0.07
    done

    # bersihkan baris spinner
    printf '\033[1A\033[K'
    # tampilkan kursor kembali
    printf '\033[?25h'
}

# ================================================================
# CONFIGURATOR
# ================================================================
setup_new_config() {
    hdr
    printf "${G}${BLD} KONFIGURASI BOARD${N}\n"; hr

    printf " ${W}Pilih Board:${N}\n"
    printf "  ${C}[1]${N} ESP32-C3 (RISC-V)    ${C}[2]${N} ESP32 Classic\n"
    printf "  ${C}[3]${N} ESP8266 NodeMCU       ${C}[4]${N} ESP32-S3\n"
    printf "  ${C}[5]${N} ESP32-S2              ${C}[6]${N} Manual FQBN\n"
    hr
    read -rp " Pilihan: " b_choice
    HAS_CDC=false
    case $b_choice in
        1) FQBN_BASE="esp32:esp32:esp32c3";       ensure_core "esp32:esp32"; HAS_CDC=true  ;;
        2) FQBN_BASE="esp32:esp32:esp32";         ensure_core "esp32:esp32"                ;;
        3) FQBN_BASE="esp8266:esp8266:nodemcuv2"; ensure_core "esp8266:esp8266"            ;;
        4) FQBN_BASE="esp32:esp32:esp32s3";       ensure_core "esp32:esp32"; HAS_CDC=true  ;;
        5) FQBN_BASE="esp32:esp32:esp32s2";       ensure_core "esp32:esp32"                ;;
        *) read -rp " Paste FQBN: " FQBN_BASE ;;
    esac

    CONF_CDC=""
    if $HAS_CDC; then
        read -rp " > USB CDC On Boot? (y/n) [y]: " cdc_q
        [[ "$cdc_q" =~ ^[Nn]$ ]] && CONF_CDC="CDCOnBoot=default," || CONF_CDC="CDCOnBoot=cdc,"
    fi

    printf " > CPU Freq: ${C}[1]${N} 160MHz  ${C}[2]${N} 80MHz  ${C}[3]${N} 240MHz\n"
    read -rp "   [1]: " cpu_q
    case $cpu_q in 2) CONF_CPU="CPUFreq=80" ;; 3) CONF_CPU="CPUFreq=240" ;; *) CONF_CPU="CPUFreq=160" ;; esac

    printf " > Partisi:\n"
    printf "   ${C}[1]${N} Default (app 1.28MB, spiffs 1.4MB)\n"
    printf "   ${C}[2]${N} Huge APP (app 3MB, spiffs 192KB)\n"
    printf "   ${C}[3]${N} Min SPIFFS (app 1.9MB, spiffs 640KB)\n"
    printf "   ${C}[4]${N} No OTA (app 2MB, spiffs 960KB)\n"
    printf "   ${C}[5]${N} Custom CSV (arahkan ke file .csv)\n"
    read -rp "   [1]: " part_q
    CUSTOM_PARTITION_CSV=""
    case $part_q in
        2) CONF_PART="PartitionScheme=huge_app"   ;;
        3) CONF_PART="PartitionScheme=min_spiffs"  ;;
        4) CONF_PART="PartitionScheme=no_ota"      ;;
        5)
            # Cek apakah ada CSV di folder project
            local auto_csv=""
            for _csv in "$PROJECT_PATH/partitions.csv"                         "$PROJECT_PATH/${selected_project}.csv"                         "$PROJECT_PATH/partition.csv"; do
                [[ -f "$_csv" ]] && auto_csv="$_csv" && break
            done
            if [[ -n "$auto_csv" ]]; then
                printf "   ${G}[✓] Ditemukan: %s${N}\n" "$(basename "$auto_csv")"
                read -rp "   Gunakan file ini? (y/n) [y]: " _use_auto
                if [[ ! "$_use_auto" =~ ^[Nn]$ ]]; then
                    CUSTOM_PARTITION_CSV="$auto_csv"
                fi
            fi
            if [[ -z "$CUSTOM_PARTITION_CSV" ]]; then
                read -rp "   Path ke .csv: " _csv_path
                if [[ -f "$_csv_path" ]]; then
                    CUSTOM_PARTITION_CSV="$_csv_path"
                    printf "   ${G}[✓] CSV diterima${N}\n"
                else
                    printf "   ${R}[✗] File tidak ditemukan, fallback ke default${N}\n"
                fi
            fi
            # Hitung max app size dari CSV untuk inject ke compile
            if [[ -n "$CUSTOM_PARTITION_CSV" ]]; then
                local _app_size
                _app_size=$(grep -E "^app0|ota_0" "$CUSTOM_PARTITION_CSV" 2>/dev/null |                     grep -oE "0x[0-9a-fA-F]+" | tail -1)
                if [[ -n "$_app_size" ]]; then
                    CUSTOM_APP_SIZE=$(( 16#${_app_size#0x} ))
                    printf "   ${D}App size dari CSV: %d bytes (%.2fMB)${N}\n"                         "$CUSTOM_APP_SIZE" "$(echo "scale=2; $CUSTOM_APP_SIZE/1048576" | bc)"
                fi
            fi
            CONF_PART="PartitionScheme=default"  # base FQBN, override via build-property
            ;;
        *) CONF_PART="PartitionScheme=default"    ;;
    esac

    printf " > Flash: ${C}[1]${N} QIO 80MHz (default)  ${C}[2]${N} DIO 40MHz\n"
    read -rp "   [1]: " flash_q
    case $flash_q in
        2) CONF_FLASH="FlashMode=dio,FlashFreq=40" ;;
        *) CONF_FLASH="FlashMode=qio,FlashFreq=80" ;;
    esac

    printf " > Debug: ${C}[1]${N} None  ${C}[2]${N} Info  ${C}[3]${N} Verbose\n"
    read -rp "   [1]: " dbg_q
    case $dbg_q in
        2) CONF_DBG="DebugLevel=info"    ;;
        3) CONF_DBG="DebugLevel=verbose" ;;
        *) CONF_DBG="DebugLevel=none"    ;;
    esac

    FQBN="${FQBN_BASE}:${CONF_CDC}${CONF_CPU},${CONF_PART},${CONF_FLASH},${CONF_DBG}"

    printf " > Sebelum upload: ${C}[1]${N} Langsung flash  ${C}[2]${N} Tanya backup dulu\n"
    read -rp "   [1]: " upref_q
    case $upref_q in
        2) UPLOAD_PREF="backup" ;;
        *) UPLOAD_PREF="direct" ;;
    esac

    {
        printf 'FQBN="%s"\n' "$FQBN"
        printf 'UPLOAD_PREF="%s"\n' "$UPLOAD_PREF"
        [[ -n "$CUSTOM_PARTITION_CSV" ]] &&             printf 'CUSTOM_PARTITION_CSV="%s"\n' "$CUSTOM_PARTITION_CSV"
        [[ -n "$CUSTOM_APP_SIZE" ]] &&             printf 'CUSTOM_APP_SIZE="%s"\n' "$CUSTOM_APP_SIZE"
    } > "$CONFIG_FILE"
    printf "\n${G} [✓] Konfigurasi disimpan.${N}\n"
    sleep 1
}

# ================================================================
# SHA256
# ================================================================
generate_checksum_file() {
    local bin_dir="$1"
    local cs="$bin_dir/SHA256SUMS.txt"
    printf "${C} [i] Menghitung SHA256...${N}\n"
    > "$cs"
    while IFS= read -r -d '' f; do
        local fn; fn=$(basename "$f")
        local h;  h=$(sha256sum "$f" | awk '{print $1}')
        printf "%s  %s\n" "$h" "$fn" >> "$cs"
        printf "  ${D}%s${N}\n" "$fn"
    done < <(find "$bin_dir" -maxdepth 1 -name "*.bin" -print0 | sort -z)
    printf "${G} [✓] SHA256SUMS.txt siap${N}\n"
    echo "$cs"
}

# ================================================================
# BACKUP FIRMWARE
# ================================================================
backup_firmware() {
    hdr
    printf "${P}${BLD} BACKUP FIRMWARE DARI ESP${N}\n"; hr

    [[ -z "$ESPTOOL" ]] && {
        printf "${R} [!] esptool tidak ada. Install: pip install esptool${N}\n"
        pause; return; }

    local port; port=$(detect_port)
    [[ -z "$port" ]] && {
        printf "${R} [!] Device tidak terdeteksi!${N}\n"
        pause; return; }

    get_chip_info

    printf "  Port  : ${G}%s${N}\n  Chip  : ${G}%s${N}\n" "$port" "$CHIP_NAME"
    hr

    printf " Flash size: ${C}[1]${N} 4MB  ${C}[2]${N} 2MB  ${C}[3]${N} 8MB  ${C}[4]${N} 16MB\n"
    read -rp " [1]: " fsc
    local fsb fsl
    case $fsc in
        2) fsb="0x200000"; fsl="2MB"  ;;
        3) fsb="0x800000"; fsl="8MB"  ;;
        4) fsb="0x1000000";fsl="16MB" ;;
        *) fsb="0x400000"; fsl="4MB"  ;;
    esac

    local ts; ts=$(date +'%Y-%m-%d_%H-%M-%S')
    local bdir="$BACKUP_BASE/$selected_project/$ts"
    mkdir -p "$bdir"
    local bfile="$bdir/${selected_project}_${fsl}_${ts}.bin"

    printf "\n${Y} [i] Membaca flash %s dari %s...${N}\n" "$fsl" "$port"
    printf "${D} Output: %s${N}\n\n" "$bfile"

    $ESPTOOL --chip "$CHIP_NAME" --port "$port" --baud 460800 \
        read_flash 0x0 "$fsb" "$bfile" 2>&1

    if [[ $? -eq 0 && -f "$bfile" ]]; then
        local fsz; fsz=$(du -h "$bfile" | cut -f1)
        local h;   h=$(sha256sum "$bfile" | awk '{print $1}')
        printf "\n${G}${BLD} [✓] BACKUP BERHASIL${N}\n"; hr
        printf "  File   : %s\n  Size   : %s\n  SHA256 : %s\n" \
            "$(basename "$bfile")" "$fsz" "$h"
        cat > "$bdir/backup_info.txt" <<EOF
Project : $selected_project
Board   : $FQBN
Chip    : $CHIP_NAME
Port    : $port
Flash   : $fsl
Date    : $ts
File    : $(basename "$bfile")
SHA256  : $h
EOF
        hr
        printf " Kirim ke Telegram? ${C}[1]${N} Ya  ${C}[2]${N} Tidak\n"
        read -rp " [2]: " sc
        if [[ "$sc" == "1" ]]; then
            local cap
            cap="💾 *BACKUP FIRMWARE*

🚀 *Project:* \`$selected_project\`
🛠 *Board:* \`$FQBN\`
📊 *Size:* \`$fsz\`
💾 *Flash:* \`$fsl\`
📅 *Date:* \`$ts\`

🔐 *SHA256:*
\`$h\`

⚠️ Flash di offset \`0x0\`"
            local resp
            resp=$(curl -s -F chat_id="$CHAT_ID" \
                -F document=@"$bfile" \
                -F caption="$cap" \
                -F parse_mode="Markdown" \
                "https://api.telegram.org/bot$BOT_TOKEN/sendDocument")
            [[ "$resp" == *'"ok":true'* ]] \
                && printf "${G} [✓] Terkirim${N}\n" \
                || printf "${R} [✗] Gagal kirim${N}\n"
        fi
    else
        printf "${R} [✗] BACKUP GAGAL!${N}\n"
        printf "${R}     Coba tahan BOOT lalu RST sebelum backup.${N}\n"
        rm -rf "$bdir"
    fi
    pause
}

# ================================================================
# SPIFFS / LittleFS UPLOAD
# ================================================================
upload_spiffs() {
    hdr
    printf "${P}${BLD} SPIFFS / LittleFS UPLOAD${N}\n"
    device_bar

    local data_dir="$PROJECT_PATH/data"
    if [[ ! -d "$data_dir" || -z "$(ls -A "$data_dir" 2>/dev/null)" ]]; then
        printf "${R} [!] Folder data/ tidak ada atau kosong.${N}\n"
        printf "${D}     Buat folder: %s/data/${N}\n" "$PROJECT_PATH"
        printf "${D}     Isi dengan file HTML/JSON/gambar yang akan diupload ke ESP.${N}\n"
        pause; return
    fi

    get_chip_info
    local port; port=$(detect_port)

    printf "  ${D}Project${N}  : ${G}%s${N}\n" "$selected_project"
    hr
    probe_and_show
    hr

    # Tampilkan isi data/
    printf "${D} Isi data/:${N}\n"
    find "$data_dir" -type f | sort | while read -r f; do
        printf "  ${D}%-40s %s${N}\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
    done
    hr

    # Cek tool mkspiffs / mklittlefs
    local fs_tool=""
    local fs_type=""
    if command -v mklittlefs &>/dev/null; then
        fs_tool="mklittlefs"; fs_type="LittleFS"
    elif command -v mkspiffs &>/dev/null; then
        fs_tool="mkspiffs"; fs_type="SPIFFS"
    else
        # Cari di arduino15 — harus file executable, bukan direktori
        # Pattern: .arduino15/packages/esp32/tools/mklittlefs/x.x.x/mklittlefs
        local arduino_littlefs arduino_spiffs
        arduino_littlefs=$(find "$HOME/.arduino15/packages"             -type f -name "mklittlefs" -executable 2>/dev/null |             sort -V | tail -1)
        arduino_spiffs=$(find "$HOME/.arduino15/packages"             -type f -name "mkspiffs" -executable 2>/dev/null |             sort -V | tail -1)

        if [[ -n "$arduino_littlefs" ]]; then
            fs_tool="$arduino_littlefs"; fs_type="LittleFS"
        elif [[ -n "$arduino_spiffs" ]]; then
            fs_tool="$arduino_spiffs"; fs_type="SPIFFS"
        fi
    fi

    if [[ -z "$fs_tool" ]]; then
        printf "${R} [!] mklittlefs / mkspiffs tidak ditemukan.${N}\n"
        printf "${D}     Install: pip install littlefs-python${N}\n"
        printf "${D}     Atau pastikan Arduino ESP32 core sudah ter-install.${N}\n"
        pause; return
    fi

    printf "${G} [i] Menggunakan: %s (%s)${N}\n" "$fs_tool" "$fs_type"

    # Ukuran partisi — sudah dihitung oleh probe_and_show via _apply_partition_table
    local spiffs_size="$SPIFFS_SIZE"

    # Validasi: cek apakah total data/ muat di partisi
    local data_total_bytes
    data_total_bytes=$(du -sb "$data_dir" 2>/dev/null | cut -f1)
    local spiffs_size_bytes=$(( 16#${spiffs_size#0x} ))
    if [[ "$data_total_bytes" -ge "$spiffs_size_bytes" ]]; then
        printf "\n${R} ⚠ PERINGATAN: Data folder (%s) melebihi kapasitas partisi (%s)!${N}\n" \
            "$(du -sh "$data_dir" | cut -f1)" "$spiffs_size"
        printf "${Y}   Pertimbangkan ganti PartitionScheme ke 'default' atau 'min_spiffs'${N}\n"
        printf "   Lanjut tetap build? "
        read -rp "${C}[y/N]${N}: " _oversize
        [[ "$_oversize" != "y" && "$_oversize" != "Y" ]] && return
    fi

    local fs_image="$PROJECT_PATH/build_output/${selected_project}.spiffs.bin"
    mkdir -p "$PROJECT_PATH/build_output"

    printf "${Y} [i] Membuat filesystem image...${N}\n"
    "$fs_tool" -c "$data_dir" -s "$spiffs_size" -p 256 -b 4096 "$fs_image" 2>&1

    if [[ $? -ne 0 || ! -f "$fs_image" ]]; then
        printf "${R} [✗] Gagal membuat filesystem image!${N}\n"
        pause; return
    fi

    local img_size; img_size=$(du -h "$fs_image" | cut -f1)
    printf "${G} [✓] Image OK: %s (%s)${N}\n" "$(basename "$fs_image")" "$img_size"
    hr

    # Cek/tunggu device
    port=$(detect_port)
    if [[ -z "$port" ]]; then
        printf "${R} [!] Device tidak ditemukan!${N}\n"
        printf "  ${C}[1]${N} Reconnect\n  ${C}[2]${N} Kembali\n"
        read -rp "  Pilih: " dc_opt
        case "$dc_opt" in
            1) wait_reconnect && port=$(detect_port) || { return; } ;;
            *) return ;;
        esac
    fi

    printf "${Y} [i] Upload %s ke %s offset %s...${N}\n" "$fs_type" "$port" "$SPIFFS_OFFSET"
    hr

    $ESPTOOL --chip "$CHIP_NAME" --port "$port" --baud 460800 \
        --before default_reset --after hard_reset \
        write_flash "$SPIFFS_OFFSET" "$fs_image" 2>&1 | \
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if   printf '%s' "$line" | grep -qi "writing\|erasing"; then
                printf "  ${C}%s${N}\n" "$line"
            elif printf '%s' "$line" | grep -qi "leaving\|done\|100%"; then
                printf "  ${G}%s${N}\n" "$line"
            elif printf '%s' "$line" | grep -qi "error\|failed"; then
                printf "  ${R}%s${N}\n" "$line"
            else
                printf "  ${D}%s${N}\n" "$line"
            fi
        done

    local uec=${PIPESTATUS[0]}
    hr
    if [[ $uec -eq 0 ]]; then
        printf "${G}${BLD} [✓] SPIFFS/LittleFS UPLOAD SELESAI${N}\n"
    else
        printf "${R}${BLD} [✗] UPLOAD GAGAL${N}\n"
        printf "${D}     Cek kabel dan coba tahan BOOT+RST saat upload${N}\n"
    fi
    pause
}

# ================================================================
# TELEGRAM EXPORTER
# ================================================================
send_to_telegram() {
    hdr
    printf "${B}${BLD} TELEGRAM EXPORTER${N}\n"; hr

    local bin_dir="$PROJECT_PATH/build_output"
    [[ ! -d "$bin_dir" || -z "$(ls "$bin_dir"/*.bin 2>/dev/null)" ]] && {
        printf "${R} [!] File .bin tidak ada. Compile dulu.${N}\n"
        pause; return; }

    [[ -z "$ESPTOOL" ]] && printf "${Y} [!] esptool tidak ada, merge dilewati.${N}\n"

    local base_bin; base_bin=$(ls "$bin_dir"/*.ino.bin 2>/dev/null | head -n1)
    [[ -z "$base_bin" ]] && {
        printf "${R} [!] .ino.bin tidak ditemukan!${N}\n"; pause; return; }

    local base_name; base_name=$(basename "$base_bin" .ino.bin)
    local merged="$bin_dir/${base_name}.merged.bin"
    local boot="$bin_dir/${base_name}.ino.bootloader.bin"
    local part="$bin_dir/${base_name}.ino.partitions.bin"
    local app="$bin_dir/${base_name}.ino.bin"
    local spiffs_img="$bin_dir/${base_name}.spiffs.bin"

    get_chip_info

    printf "  Project   : ${G}%s${N}\n" "$base_name"
    probe_and_show
    hr

    # ── MERGE ───────────────────────────────────────────────────
    if [[ -n "$ESPTOOL" && "$CHIP_NAME" != "esp8266" && "$CHIP_NAME" != "unknown" ]]; then
        if [[ -f "$boot" && -f "$part" && -f "$app" ]]; then
            printf "${Y} [i] Merging firmware (%s mode:%s freq:%s size:%s)...${N}\n" \
                "$CHIP_NAME" "$FLASH_MODE" "$FLASH_FREQ" "$FLASH_SIZE"

            # Hapus merged lama supaya tidak kirim stale
            rm -f "$merged"

            $ESPTOOL --chip "$CHIP_NAME" merge-bin -o "$merged" \
                --flash-mode "$FLASH_MODE" \
                --flash-freq "$FLASH_FREQ" \
                --flash-size "$FLASH_SIZE" \
                "$BOOT_OFFSET" "$boot" \
                0x8000 "$part" \
                0x10000 "$app" 2>&1 | grep -v '^$'

            if [[ $? -eq 0 && -f "$merged" ]]; then
                local msz; msz=$(du -h "$merged" | cut -f1)
                printf "${G} [✓] merged.bin OK (%s) — flash di offset 0x0${N}\n" "$msz"
            else
                printf "${R} [✗] Merge gagal — cek esptool output di atas${N}\n"
                rm -f "$merged"
            fi
        else
            printf "${R} [!] File part tidak lengkap, merge dilewati${N}\n"
            printf "${D}     Dibutuhkan: bootloader + partitions + app .bin${N}\n"
        fi
    fi
    hr

    # ── SHA256 ──────────────────────────────────────────────────
    local csfile; csfile=$(generate_checksum_file "$bin_dir")
    hr

    # ── MODE KIRIM ──────────────────────────────────────────────
    printf " Mode kirim:\n"
    printf "  ${C}[1]${N} Semua file .bin\n"
    printf "  ${C}[2]${N} merged.bin saja (rekomen untuk end-user)\n"
    printf "  ${C}[3]${N} merged.bin + spiffs (jika ada)\n"
    read -rp " [1]: " smode
    hr
    printf "${P}${BLD} Mengirim ke Telegram...${N}\n"

    # ── Kumpulkan file yang akan dikirim ────────────────────────
    local -a to_send=()
    case "$smode" in
        2)
            [[ -f "$merged" ]] && to_send+=("$merged") ;;
        3)
            [[ -f "$merged" ]]     && to_send+=("$merged")
            [[ -f "$spiffs_img" ]] && to_send+=("$spiffs_img") ;;
        *)
            # Semua file — tapi EXCLUDE *.ino.merged.bin (padding 4MB dari arduino-cli)
            while IFS= read -r -d '' f; do
                local _fn; _fn=$(basename "$f")
                # skip arduino-cli auto-generated merged (ada padding besar)
                [[ "$_fn" == *.ino.merged.bin ]] && continue
                to_send+=("$f")
            done < <(find "$bin_dir" -maxdepth 1 -name "*.bin" -print0 | sort -z)
            ;;
    esac

    if [[ ${#to_send[@]} -eq 0 ]]; then
        printf "${R} [!] Tidak ada file untuk dikirim.${N}\n"; pause; return
    fi

    # ── Kirim SHA256SUMS dulu ────────────────────────────────────
    if [[ -f "$csfile" ]]; then
        local cap_cs
        cap_cs="🔐 *SHA256 Checksum*

🚀 *Project:* \`$base_name\`
🛠 *Board:* \`$FQBN\`
🔲 *Chip:* \`$CHIP_NAME\`  *Flash:* \`$FLASH_SIZE\`

Verifikasi integritas file sebelum flash"
        printf "  ${Y}→${N} SHA256SUMS.txt... "
        local r; r=$(curl -s -F chat_id="$CHAT_ID" \
            -F document=@"$csfile" \
            -F caption="$cap_cs" \
            -F parse_mode="Markdown" \
            "https://api.telegram.org/bot$BOT_TOKEN/sendDocument")
        [[ "$r" == *'"ok":true'* ]] \
            && printf "${G}OK${N}\n" || printf "${R}GAGAL${N}\n"
    fi

    # ── Kirim tiap file ──────────────────────────────────────────
    for fp in "${to_send[@]}"; do
        local fn; fn=$(basename "$fp")
        local fsz; fsz=$(du -h "$fp" | cut -f1)
        local h;   h=$(sha256sum "$fp" | awk '{print $1}')

        # Tentukan offset dan instruksi per tipe file
        local finfo flash_note=""
        if [[ "$fn" == *.merged.bin ]]; then
            finfo="⚡ *Flash offset:* \`0x0\` \(firmware all-in-one\)
✅ *Cara flash:* pilih file ini saja, offset \`0x0\`"
            flash_note="⚠️ Flash size board harus *${FLASH_SIZE}*"
        elif [[ "$fn" == *.spiffs.bin ]]; then
            finfo="⚡ *Flash offset:* \`${SPIFFS_OFFSET}\` \(filesystem\)
✅ *Cara flash:* offset \`${SPIFFS_OFFSET}\`, jangan timpa firmware"
            flash_note="📁 Berisi file dari folder data/"
        elif [[ "$fn" == *.ino.bootloader.bin ]]; then
            finfo="⚡ *Flash offset:* \`$BOOT_OFFSET\`
⚠️ File PART — butuh 3 file sekaligus"
        elif [[ "$fn" == *.ino.partitions.bin ]]; then
            finfo="⚡ *Flash offset:* \`0x8000\`
⚠️ File PART — butuh 3 file sekaligus"
        elif [[ "$fn" == *.ino.bin ]]; then
            finfo="⚡ *Flash offset:* \`0x10000\`
⚠️ File PART — butuh 3 file sekaligus"
        else
            finfo="⚡ *Flash offset:* tidak diketahui"
        fi

        local cap
        cap="📦 *File:* \`$fn\`
📊 *Size:* \`$fsz\`
🚀 *Project:* \`$base_name\`
🔲 *Chip:* \`$CHIP_NAME\`  *Flash:* \`$FLASH_SIZE\`
⚙️ *Mode:* \`$FLASH_MODE\`  *Freq:* \`$FLASH_FREQ\`
$finfo
${flash_note}

🔐 *SHA256:*
\`$h\`

📱 ESP32 Flasher \(Android\)"

        printf "  ${Y}→${N} %-42s " "$fn"
        local resp
        resp=$(curl -s -F chat_id="$CHAT_ID" \
            -F document=@"$fp" \
            -F caption="$cap" \
            -F parse_mode="Markdown" \
            "https://api.telegram.org/bot$BOT_TOKEN/sendDocument")

        if [[ "$resp" == *'"ok":true'* ]]; then
            printf "${G}OK${N}  %s\n" "$fsz"
        else
            local emsg
            emsg=$(printf '%s' "$resp" | python3 -c \
                'import sys,json; print(json.load(sys.stdin).get("description","?"))' 2>/dev/null)
            printf "${R}GAGAL${N}  %s\n" "$emsg"
        fi
    done

    hr
    printf "${G} [✓] Selesai.${N}\n"
    [[ "$smode" != "2" ]] && \
        printf "${D} tip: gunakan %s.merged.bin di offset 0x0${N}\n" "$base_name"
    pause
}

# ================================================================
# COMPILE & UPLOAD
# ================================================================

# Upload realtime — output langsung muncul baris per baris
_do_upload() {
    local port="$1" fqbn="$2" bin_dir="$3" proj="$4"
    local ulog; ulog=$(mktemp)
    local fifo; fifo=$(mktemp -u)
    mkfifo "$fifo"

    # Jalankan upload, output ke fifo + file sekaligus
    $CLI_PATH upload -p "$port" --fqbn "$fqbn" \
        --input-dir "$bin_dir" "$proj" 2>&1 | tee "$ulog" > "$fifo" &
    local tee_pid=$!

    # Baca fifo realtime, tampilkan dengan warna
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if   printf '%s' "$line" | grep -qi "writing\|uploading\|flashing"; then
            printf "  ${C}%s${N}\n" "$line"
        elif printf '%s' "$line" | grep -qi "leaving\|hard resetting\|done\|100%"; then
            printf "  ${G}%s${N}\n" "$line"
        elif printf '%s' "$line" | grep -qi "error\|failed"; then
            printf "  ${R}%s${N}\n" "$line"
        elif printf '%s' "$line" | grep -qi "chip\|flash\|compressed\|configuring"; then
            printf "  ${W}%s${N}\n" "$line"
        else
            printf "  ${D}%s${N}\n" "$line"
        fi
    done < "$fifo"

    wait "$tee_pid" 2>/dev/null
    rm -f "$fifo"

    # exit code dari arduino-cli (baris terakhir tee)
    local uec
    grep -qi "error\|failed" "$ulog" && uec=1 || uec=0
    # cek lebih akurat: kalau ada "leaving" atau "done" = sukses
    grep -qi "leaving\|done\|hard resetting" "$ulog" && uec=0
    rm -f "$ulog"
    return $uec
}

smart_compile_upload() {
    hdr
    printf "${Y}${BLD} COMPILE & UPLOAD${N}\n"
    device_bar

    local port; port=$(detect_port)
    local bin_dir="$PROJECT_PATH/build_output"
    mkdir -p "$bin_dir"

    # Baca preferensi upload dari config (default: direct)
    local upref="${UPLOAD_PREF:-direct}"

    # ── Info panel ───────────────────────────────────────────────
    printf "  ${D}Project${N} : ${G}%s${N}\n" "$selected_project"
    printf "  ${D}Board${N}   : ${C}%s${N}\n" "$FQBN"
    printf "  ${D}Output${N}  : ${D}%s${N}\n" "$bin_dir"
    if [[ -n "$port" ]]; then
        printf "  ${D}Device${N}  : ${G}%s  ● terhubung${N}\n" "$port"
    else
        printf "  ${D}Device${N}  : ${Y}belum terdeteksi${N}\n"
    fi
    printf "  ${D}Upload${N}  : ${D}%s${N}\n" "$upref"
    hr

    # ═══════════════════════════════════════════════════════
    # STEP 1 — COMPILE
    # ═══════════════════════════════════════════════════════
    printf "${Y}${BLD}▶ STEP 1/2  COMPILE${N}\n\n"

    local log; log=$(mktemp)
    local jobs; jobs=$(nproc 2>/dev/null || echo 4)

    # Build compile flags — inject custom partition jika ada
    local -a compile_flags=()
    compile_flags+=(--fqbn "$FQBN")
    compile_flags+=(--output-dir "$bin_dir")
    compile_flags+=(-j "$jobs")

    # Custom partition CSV support
    local csv_path="${CUSTOM_PARTITION_CSV:-}"
    # Auto-detect CSV di folder project (prioritas lebih tinggi dari config)
    for _f in "$PROJECT_PATH/partitions.csv"                "$PROJECT_PATH/${selected_project}.csv"                "$PROJECT_PATH/partition.csv"; do
        [[ -f "$_f" ]] && csv_path="$_f" && break
    done

    if [[ -n "$csv_path" && -f "$csv_path" ]]; then
        printf "  ${Y}[i] Custom partition: %s${N}\n" "$(basename "$csv_path")"
        # Copy CSV ke build dir dengan nama yang dikenali arduino-cli
        cp "$csv_path" "$bin_dir/partitions.csv"
        # Inject build properties
        compile_flags+=(--build-property "build.partitions=$(basename "${csv_path%.csv}")")
        if [[ -n "${CUSTOM_APP_SIZE:-}" ]]; then
            compile_flags+=(--build-property "upload.maximum_size=${CUSTOM_APP_SIZE}")
        fi
    fi

    $CLI_PATH compile "${compile_flags[@]}" "$PROJECT_PATH" >"$log" 2>&1 &
    local cpid=$!

    _compile_spinner "$log" "$cpid"
    wait "$cpid"; local ec=$?

    # Simpan log permanen
    local logdir="$LOG_BASE/$selected_project"
    mkdir -p "$logdir"
    local logfile="$logdir/$(date +'%Y-%m-%d_%H-%M-%S').log"
    cp "$log" "$logfile"

    if [[ $ec -ne 0 ]]; then
        printf "${R}${BLD} ✗ COMPILE GAGAL${N}\n"; hr

        # ── Tampilkan error terstruktur: file + baris + pesan ──
        printf "${D} Log lengkap: %s${N}\n\n" "$logfile"

        # Parse: /path/file.ino:baris:kolom: error: pesan
        local err_count=0
        while IFS= read -r line; do
            # ambil baris yang mengandung error: atau fatal error:
            if printf '%s' "$line" | grep -qE ":[0-9]+:[0-9]+: (error|fatal error):"; then
                local src_file; src_file=$(printf '%s' "$line" | sed 's/:\([0-9]*\):.*//' | sed 's|.*/||')
                local src_line; src_line=$(printf '%s' "$line" | grep -oE ":[0-9]+:" | head -1 | tr -d ':')
                local msg;      msg=$(printf '%s' "$line" | sed 's/.*error: //')
                printf "  ${R}✗${N} ${W}%s${N}${D}:%s${N}\n" "$src_file" "$src_line"
                printf "    ${R}%s${N}\n" "$msg"
                err_count=$((err_count+1))
                [[ $err_count -ge 20 ]] && break
            fi
        done < "$log"

        # Jika format berbeda (linker error dll), tampilkan raw
        if [[ $err_count -eq 0 ]]; then
            grep -i "error\|undefined\|cannot" "$log" | tail -15 | while IFS= read -r line; do
                printf "  ${R}%s${N}\n" "$line"
            done
        fi

        local warn_count; warn_count=$(grep -c "warning:" "$log" 2>/dev/null || echo 0)
        [[ "$warn_count" -gt 0 ]] && \
            printf "\n  ${Y}⚠ %d warning(s) — lihat log untuk detail${N}\n" "$warn_count"

        rm -f "$log"; pause; return
    fi

    # ── Compile sukses ────────────────────────────────────────
    printf "${G}${BLD} ✓ COMPILE SELESAI${N}\n"
    hr

    local mem_sketch; mem_sketch=$(grep -i "Sketch uses" "$log" | tail -1)
    local mem_global; mem_global=$(grep -i "Global variables" "$log" | tail -1)
    [[ -n "$mem_sketch" ]] && printf "  ${D}%s${N}\n" "$mem_sketch"
    [[ -n "$mem_global" ]] && printf "  ${D}%s${N}\n" "$mem_global"

    printf "\n  ${D}Output:${N}\n"
    find "$bin_dir" -maxdepth 1 -name "*.bin" | sort | while read -r f; do
        printf "  ${D}  %-45s %s${N}\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
    done
    printf "  ${D}  Log: %s${N}\n" "$logfile"
    hr

    # ═══════════════════════════════════════════════════════
    # STEP 2 — UPLOAD
    # ═══════════════════════════════════════════════════════
    printf "${Y}${BLD}▶ STEP 2/2  UPLOAD${N}\n"

    # ── Backup preference ─────────────────────────────────
    if [[ "$upref" == "backup" ]]; then
        printf "\n${C} Backup firmware sebelum flash?${N}\n"
        printf "  ${C}[1]${N} Ya, backup dulu\n"
        printf "  ${C}[2]${N} Langsung flash\n"
        read -rp "  [2]: " bak_choice
        if [[ "$bak_choice" == "1" ]]; then
            backup_firmware
            hdr
            printf "${Y}${BLD}▶ STEP 2/2  UPLOAD (lanjut)${N}\n"
            hr
        fi
    fi

    # ── Cek / tunggu device ───────────────────────────────
    port=$(detect_port)

    if [[ -z "$port" ]]; then
        printf "\n${R}${BLD} ✗ Device tidak ditemukan!${N}\n"
        printf "${D}   .bin tersedia di: %s${N}\n" "$bin_dir"
        printf "${D}   Gunakan [t] Telegram atau flash manual\n${N}"
        hr
        printf "  ${C}[1]${N} Reconnect — scan ulang device\n"
        printf "  ${C}[2]${N} Kembali ke dashboard\n"
        hr
        read -rp "  Pilih: " dc_opt
        case "$dc_opt" in
            1)
                wait_reconnect && port=$(detect_port) || { rm -f "$log"; return; }
                ;;
            *) rm -f "$log"; return ;;
        esac
    fi

    printf "  ${D}Port${N}  : ${G}%s${N}\n" "$port"
    printf "  ${D}Board${N} : ${C}%s${N}\n" "$FQBN"
    hr

    _do_upload "$port" "$FQBN" "$bin_dir" "$PROJECT_PATH"
    local uec=$?

    # Retry sudo jika gagal
    if [[ $uec -ne 0 ]]; then
        printf "\n${Y} [!] Retry dengan sudo chmod...${N}\n"; hr
        sudo chmod 666 "$port" 2>/dev/null
        _do_upload "$port" "$FQBN" "$bin_dir" "$PROJECT_PATH"
        uec=$?
    fi

    # Cek device setelah upload — ESP normal hilang sebentar saat reset
    sleep 0.6
    local port_after; port_after=$(detect_port)
    if [[ -z "$port_after" && $uec -ne 0 ]]; then
        wait_reconnect || { rm -f "$log"; return; }
    fi

    hr
    if [[ $uec -eq 0 ]]; then
        printf "${G}${BLD} ✓ UPLOAD SELESAI${N}\n"
        printf "${D}   ESP restart otomatis${N}\n"
    else
        printf "${R}${BLD} ✗ UPLOAD GAGAL${N}\n"
        printf "${D}   Cek kabel & coba tahan BOOT+RST saat upload\n${N}"
        printf "${D}   Log: %s${N}\n" "$logfile"
    fi

    rm -f "$log"
    pause
}

# ================================================================
# DEBUG MONITOR
# ================================================================
interactive_debug() {
    hdr
    printf "${C}${BLD} SERIAL MONITOR${N}\n"
    device_bar

    local port; port=$(detect_port)
    if [[ -z "$port" ]]; then
        printf "${R} [!] Device tidak terdeteksi!${N}\n"
        printf "  ${C}[1]${N} Reconnect\n  ${C}[2]${N} Kembali\n"
        read -rp "  Pilih: " _dc
        case "$_dc" in
            1) wait_reconnect && port=$(detect_port) || return ;;
            *) return ;;
        esac
    fi

    # ── Pilih baud rate ─────────────────────────────────────────
    printf "  Port : ${G}%s${N}\n" "$port"
    printf "\n  Baud rate:\n"
    printf "  ${C}[1]${N} 115200 (default)\n"
    printf "  ${C}[2]${N} 9600\n"
    printf "  ${C}[3]${N} 57600\n"
    printf "  ${C}[4]${N} 230400\n"
    printf "  ${C}[5]${N} 921600\n"
    printf "  ${C}[6]${N} Custom\n"
    read -rp "  [1]: " baud_choice
    local baud
    case "$baud_choice" in
        2) baud=9600    ;;
        3) baud=57600   ;;
        4) baud=230400  ;;
        5) baud=921600  ;;
        6) read -rp "  Baud: " baud ;;
        *) baud=115200  ;;
    esac

    # ── Pilih mode ───────────────────────────────────────────────
    printf "\n  Mode:\n"
    printf "  ${C}[1]${N} Monitor saja (read only)\n"
    printf "  ${C}[2]${N} Monitor + kirim teks (interactive)\n"
    read -rp "  [1]: " mon_mode
    hr

    if [[ "$mon_mode" == "2" ]]; then
        # ── Interactive mode: read + send ────────────────────────
        # Pakai python3 miniterm yang support input dua arah
        printf "${G} SERIAL MONITOR — INTERACTIVE${N}\n"
        printf "${D} Port: %s  Baud: %s${N}\n" "$port" "$baud"
        printf "${D} Ctrl+]  = keluar${N}\n"
        printf "${D} Ketik pesan lalu Enter untuk kirim ke device${N}\n"
        hr

        # Cek python3 miniterm tersedia
        if python3 -m serial.tools.miniterm --version &>/dev/null 2>&1 ||            python3 -c "import serial" &>/dev/null 2>&1; then
            python3 -m serial.tools.miniterm                 --raw                 --eol LF                 "$port" "$baud"
        else
            printf "${Y} [!] pyserial tidak ada, install dulu:${N}\n"
            printf "${D}     pip install pyserial${N}\n"
            printf "${Y} [i] Fallback ke mode read-only...${N}\n"
            sleep 2
            hr
            printf "${G} SERIAL MONITOR — READ ONLY${N}\n"
            printf "${D} Port: %s  Baud: %s${N}\n" "$port" "$baud"
            printf "${D} Ctrl+C = keluar${N}\n"
            hr
            $CLI_PATH monitor -p "$port" -c baudrate="$baud"
        fi
    else
        # ── Read only mode ───────────────────────────────────────
        printf "${G} SERIAL MONITOR — READ ONLY${N}\n"
        printf "${D} Port: %s  Baud: %s${N}\n" "$port" "$baud"
        printf "${D} Ctrl+C = keluar${N}\n"
        hr

        # Timestamp per baris + warna berdasarkan log level
        $CLI_PATH monitor -p "$port" -c baudrate="$baud" 2>/dev/null |         while IFS= read -r line; do
            local ts; ts=$(date +'%H:%M:%S')
            if   printf '%s' "$line" | grep -qE "\[E\]|ERROR|error|FAIL|fail"; then
                printf "${D}[%s]${N} ${R}%s${N}\n" "$ts" "$line"
            elif printf '%s' "$line" | grep -qE "\[W\]|WARN|warn"; then
                printf "${D}[%s]${N} ${Y}%s${N}\n" "$ts" "$line"
            elif printf '%s' "$line" | grep -qE "\[I\]|INFO|OK|ok|✓"; then
                printf "${D}[%s]${N} ${G}%s${N}\n" "$ts" "$line"
            elif printf '%s' "$line" | grep -qE "HEAP|heap|free|Free"; then
                printf "${D}[%s]${N} ${C}%s${N}\n" "$ts" "$line"
            else
                printf "${D}[%s]${N} %s\n" "$ts" "$line"
            fi
        done
    fi
}

# ================================================================
# LIBRARY MANAGER
# ================================================================
manage_libraries() {
    while true; do
        hdr
        printf "${G}${BLD} LIBRARY MANAGER${N}\n"; hr
        printf "  ${C}[1]${N} Cari & Install\n"
        printf "  ${C}[2]${N} List terpasang\n"
        printf "  ${C}[3]${N} Update index\n"
        printf "  ${C}[q]${N} Kembali\n"; hr
        read -rp " Pilih: " la
        case $la in
            1)
                read -rp " Keyword: " kw
                mapfile -t ll < <($CLI_PATH lib search "$kw" \
                    | grep "Name:" | sed 's/Name: //;s/"//g' | head -15)
                [[ ${#ll[@]} -eq 0 ]] && {
                    printf "${R} Tidak ditemukan.${N}\n"; sleep 2; continue; }
                hdr
                for i in "${!ll[@]}"; do
                    printf "  ${C}[%d]${N} %s\n" "$((i+1))" "${ll[$i]}"
                done
                hr
                read -rp " Nomor (q batal): " ls
                [[ "$ls" == "q" ]] && continue
                $CLI_PATH lib install "${ll[$((ls-1))]}"
                sleep 2 ;;
            2) $CLI_PATH lib list; pause ;;
            3) $CLI_PATH lib update-index; pause ;;
            q) break ;;
        esac
    done
}

# ================================================================
# LIST BACKUP
# ================================================================
list_backups() {
    hdr
    printf "${P}${BLD} BACKUP — %s${N}\n" "$selected_project"; hr
    local bdir="$BACKUP_BASE/$selected_project"
    [[ ! -d "$bdir" || -z "$(ls -A "$bdir" 2>/dev/null)" ]] && {
        printf "${Y} Belum ada backup untuk proyek ini.${N}\n"
        pause; return; }

    local -a bdirs=()
    local i=0
    while IFS= read -r -d '' d; do
        bdirs+=("$d")
        local ts; ts=$(basename "$d")
        local chip=""; [[ -f "$d/backup_info.txt" ]] && \
            chip=$(awk -F': ' '/Chip/{print $2}' "$d/backup_info.txt")
        printf "  ${C}[%d]${N} %s  ${D}[%s]${N}\n" "$((i+1))" "$ts" "$chip"
        i=$((i+1))
    done < <(find "$bdir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -rz)

    printf "  ${R}[q]${N} Kembali\n"; hr
    read -rp " Detail nomor: " bs
    [[ "$bs" == "q" ]] && return
    local sd="${bdirs[$((bs-1))]}"
    [[ -n "$sd" && -d "$sd" ]] && {
        printf "\n"
        cat "$sd/backup_info.txt" 2>/dev/null
        hr
        ls -lh "$sd"/*.bin 2>/dev/null
    }
    pause
}

# ================================================================
# CHECK ENGINE (startup)
# ================================================================
_tool_install_msg() {
    printf "${Y} [↓] %-20s${N} " "$1"
}
_tool_ok()   { printf "${G}OK${N}\n"; }
_tool_fail() { printf "${R}GAGAL — %s${N}\n" "$1"; }

check_engine() {
    printf "${W}${BLD} Memeriksa dependensi...${N}\n"; hr

    # ── arduino-cli ──────────────────────────────────────────────
    if [[ ! -f "$CLI_PATH" ]]; then
        _tool_install_msg "arduino-cli"
        if curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh &>/dev/null; then
            mkdir -p "$HOME/.local/bin"
            mv bin/arduino-cli "$HOME/.local/bin/" 2>/dev/null
            CLI_PATH="$HOME/.local/bin/arduino-cli"
            _tool_ok
        else
            _tool_fail "gagal download, install manual"
        fi
    else
        printf "  ${G}✓${N}  arduino-cli       ${D}%s${N}\n" "$($CLI_PATH version 2>/dev/null | awk '{print $3}' || echo '?')"
    fi

    # ── esptool ──────────────────────────────────────────────────
    if [[ -z "$ESPTOOL" ]]; then
        _tool_install_msg "esptool"
        # coba pip3 dulu, fallback pip
        if command -v pip3 &>/dev/null; then
            pip3 install esptool --quiet --break-system-packages 2>/dev/null                 || pip3 install esptool --quiet 2>/dev/null
        elif command -v pip &>/dev/null; then
            pip install esptool --quiet --break-system-packages 2>/dev/null                 || pip install esptool --quiet 2>/dev/null
        fi
        # re-detect setelah install
        if   command -v esptool    &>/dev/null; then ESPTOOL="esptool";    _tool_ok
        elif command -v esptool.py &>/dev/null; then ESPTOOL="esptool.py"; _tool_ok
        else _tool_fail "pip tidak tersedia, install manual: pip install esptool"
        fi
    else
        printf "  ${G}✓${N}  esptool           ${D}%s${N}\n" "$($ESPTOOL version 2>/dev/null | head -1 | awk '{print $2}' || echo '?')"
    fi

    # ── dialout group ────────────────────────────────────────────
    if ! groups | grep -q '\bdialout\b'; then
        _tool_install_msg "dialout group"
        sudo usermod -aG dialout "$USER" 2>/dev/null && _tool_ok             || _tool_fail "jalankan manual: sudo usermod -aG dialout $USER"
        printf "${D}  (efektif setelah restart/re-login)${N}\n"
    else
        printf "  ${G}✓${N}  dialout group     ${D}OK${N}\n"
    fi

    hr
    sleep 0.8
}

# ================================================================
# MAIN
# ================================================================
open_alt
check_engine
mkdir -p "$ARDUINO_DIR" "$LOG_BASE" "$BACKUP_BASE"

# ── Project selector ─────────────────────────────────────────────
while true; do
    hdr
    device_bar
    cd "$ARDUINO_DIR" || exit 1
    mapfile -t projects < <(
        find "$ARDUINO_DIR" -mindepth 1 -maxdepth 1 -type d \
        ! -name "libraries" ! -name "build" -printf '%f\n' | sort
    )

    printf "${W} Proyek di ~/Arduino:${N}\n"
    for i in "${!projects[@]}"; do
        printf "  ${C}[%d]${N} %s\n" "$((i+1))" "${projects[$i]}"
    done
    printf "\n  ${G}[n]${N} Proyek baru   ${R}[q]${N} Keluar\n"; hr
    read -rp " Pilih >> " pchoice

    case "$pchoice" in
        q) close_alt; exit 0 ;;
        n)
            read -rp " Nama proyek: " np
            $CLI_PATH sketch new "$ARDUINO_DIR/$np" &>/dev/null
            selected_project="$np" ;;
        *)
            selected_project="${projects[$((pchoice-1))]}" ;;
    esac

    [[ -z "$selected_project" ]] && continue

    PROJECT_PATH="$ARDUINO_DIR/$selected_project"
    CONFIG_FILE="$PROJECT_PATH/.esp_config"
    sync_project_file
    [[ ! -f "$CONFIG_FILE" ]] && setup_new_config
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    # ── Project menu ─────────────────────────────────────────────
    while true; do
        hdr
        device_bar
        printf "  ${P}Project${N} : ${G}%s${N}\n" "$selected_project"
        printf "  ${P}Board${N}   : ${C}%s${N}\n" "$FQBN"
        hr
        # Deteksi apakah ada folder data/ untuk SPIFFS indicator
        local _has_data=""
        [[ -d "$PROJECT_PATH/data" && -n "$(ls -A "$PROJECT_PATH/data" 2>/dev/null)" ]] \
            && _has_data="${G}●${N}" || _has_data="${D}○${N}"

        printf "  ${C}[1]${N} Edit kode           ${C}[2]${N} Compile & Upload\n"
        printf "  ${C}[3]${N} Serial Monitor       ${C}[t]${N} Kirim ke Telegram\n"
        printf "  ${C}[4]${N} Re-config board      ${C}[5]${N} Library Manager\n"
        printf "  ${C}[b]${N} Backup firmware      ${C}[v]${N} Lihat backup\n"
        printf "  ${C}[s]${N} SPIFFS/LittleFS %b      ${C}[6]${N} Ganti proyek\n" "$_has_data"
        printf "  ${C}[i]${N} Device Info             ${C}[c]${N} ${R}Clean cache${N}\n"
        hr
        read -rp " Menu >> " action

        case "$action" in
            1)
                mapfile -t files < <(ls "$PROJECT_PATH" | grep -vE '\.esp_config|^build')
                hdr
                for i in "${!files[@]}"; do
                    printf "  ${C}[%d]${N} %s\n" "$((i+1))" "${files[$i]}"
                done
                hr
                read -rp " Nomor: " fn
                tf="${files[$((fn-1))]}"
                [[ -n "$tf" ]] && nano "$PROJECT_PATH/$tf"
                ;;
            2)  smart_compile_upload ;;
            3)  interactive_debug ;;
            4)  setup_new_config; source "$CONFIG_FILE" ;;
            5)  manage_libraries ;;
            6)  break ;;
            b)  backup_firmware ;;
            v)  list_backups ;;
            s)  upload_spiffs ;;
            i)  device_info ;;
            t)  send_to_telegram ;;
            c)
                if confirm_action "Hapus build cache $selected_project?"; then
                    rm -rf "$PROJECT_PATH/build" "$PROJECT_PATH/build_output"
                    printf "${G} [✓] Cache dihapus.${N}\n"; sleep 1
                fi ;;
        esac
    done
done
