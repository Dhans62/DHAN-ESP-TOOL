#!/bin/bash

# --- WARNA & UI ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# --- KONFIGURASI PATH ---
CLI_PATH=$(which arduino-cli)
[ -z "$CLI_PATH" ] && CLI_PATH="$HOME/.local/bin/arduino-cli"
ARDUINO_DIR="$HOME/Arduino"
DATA_DIR="$HOME/.arduino15"

# --- FUNGSI ALTERNATIVE SCREEN ---
open_alt_screen() { echo -ne "\033[?1049h\033[H"; }
close_alt_screen() { echo -ne "\033[?1049l"; }
trap 'close_alt_screen; exit' SIGINT SIGTERM

# --- UI COMPONENT ---
draw_line() { echo -e "${BLUE}---------------------------------------------------------${NC}"; }

display_header() {
    clear
    echo -e "${CYAN}  _____  _    _          _   _     ______  _____ _____  ${NC}"
    echo -e "${CYAN} |  __ \| |  | |   /\   | \ | |   |  ____|/ ____|  __ \ ${NC}"
    echo -e "${CYAN} | |  | | |__| |  /  \  |  \| |   | |__  | (___ | |__) |${NC}"
    echo -e "${CYAN} | |  | |  __  | / /\ \ | . \` |   |  __|  \___ \|  ___/ ${NC}"
    echo -e "${CYAN} | |__| | |  | |/ ____ \| |\  |   | |____ ____) | |     ${NC}"
    echo -e "${CYAN} |_____/|_|  |_/_/    \_\_| \_|   |______|_____/|_|     ${NC}"
    echo -e "${YELLOW}       >>> Advanced TUI for ESP | v5.0 <<<${NC}"
    draw_line
}

# --- VALIDASI ENGINE ---
check_engine() {
    if [ ! -f "$CLI_PATH" ]; then
        echo -e "${RED} [!] arduino-cli tidak ditemukan.${NC}"
        curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh
        mkdir -p "$HOME/.local/bin"
        mv bin/arduino-cli "$HOME/.local/bin/"
        CLI_PATH="$HOME/.local/bin/arduino-cli"
    fi
}

ensure_core() {
    local core_name=$1
    if ! $CLI_PATH core list | grep -q "$core_name"; then
        echo -e "${YELLOW} [i] Mengunduh Core $core_name...${NC}"
        $CLI_PATH core install "$core_name"
    fi
}

# --- SYNC PROJECT FILE ---
sync_project_file() {
    local folder_name=$(basename "$PROJECT_PATH")
    local expected_ino="$PROJECT_PATH/$folder_name.ino"
    if [ ! -f "$expected_ino" ]; then
        local found_ino=$(ls "$PROJECT_PATH"/*.ino 2>/dev/null | head -n 1)
        if [ -n "$found_ino" ]; then
            mv "$found_ino" "$expected_ino"
        else
            $CLI_PATH sketch new "$PROJECT_PATH" > /dev/null
        fi
    fi
}

# --- CONFIGURATOR ---
setup_new_config() {
    display_header
    echo -e "${GREEN}--- STEP 1: PILIH BOARD ---${NC}"
    echo -e " [1] ESP32-C3 (RISC-V)     [2] ESP32 Classic (Dual Core)"
    echo -e " [3] ESP8266 (NodeMCU/v2)  [4] Cari Manual (FQBN)"
    read -p " Pilihan: " b_choice
    case $b_choice in
        1) FQBN_BASE="esp32:esp32:esp32c3"; ensure_core "esp32:esp32" ;;
        2) FQBN_BASE="esp32:esp32:esp32"; ensure_core "esp32:esp32" ;;
        3) FQBN_BASE="esp8266:esp8266:nodemcuv2"; ensure_core "esp8266:esp8266" ;;
        *) read -p " Paste FQBN: " FQBN_BASE ;;
    esac

    echo -e "\n${GREEN}--- STEP 2: PARAMETER SETTING (ENTER UNTUK DEFAULT) ---${NC}"
    echo -ne "${CYAN} > USB CDC On Boot? (y/n) [Default n]: ${NC}"
    read cdc_q
    [[ "$cdc_q" =~ ^[Yy]$ ]] && CONF_CDC="CDCOnBoot=cdc" || CONF_CDC="CDCOnBoot=default"
    echo -e " > CPU Freq: [1] 160MHz [2] 80MHz [3] 240MHz"
    read -p "   Pilihan [Default 1]: " cpu_q
    case $cpu_q in 2) CONF_CPU="CPUFreq=80" ;; 3) CONF_CPU="CPUFreq=240" ;; *) CONF_CPU="CPUFreq=160" ;; esac
    echo -e " > Partisi: [1] Default [2] Huge APP [3] Min SPIFFS"
    read -p "   Pilihan [Default 1]: " part_q
    case $part_q in 2) CONF_PART="PartitionScheme=huge_app" ;; 3) CONF_PART="PartitionScheme=min_spiffs" ;; *) CONF_PART="PartitionScheme=default" ;; esac
    echo -e " > Flash: [1] DIO 40MHz [2] QIO 80MHz"
    read -p "   Pilihan [Default 1]: " flash_q
    case $flash_q in 2) CONF_FLASH="FlashMode=qio,FlashFreq=80" ;; *) CONF_FLASH="FlashMode=dio,FlashFreq=40" ;; esac
    echo -e " > Debug: [1] None [2] Info [3] Verbose"
    read -p "   Pilihan [Default 1]: " dbg_q
    case $dbg_q in 2) CONF_DBG="DebugLevel=info" ;; 3) CONF_DBG="DebugLevel=verbose" ;; *) CONF_DBG="DebugLevel=none" ;; esac

    FQBN="${FQBN_BASE}:${CONF_CDC},${CONF_CPU},${CONF_PART},${CONF_FLASH},${CONF_DBG}"
    echo "FQBN=\"$FQBN\"" > "$CONFIG_FILE"
    echo -e "${GREEN} [!] Konfigurasi Disimpan!${NC}"
    sleep 1
}

# --- COMPILER & FLASHING ---
smart_compile_upload() {
    display_header
    echo -e "${YELLOW} [STEP 1/2] MENGOMPILASI...${NC}"
    echo -e "${PURPLE} [INFO] Menggunakan 2 Core STB untuk stabilitas daya.${NC}"
    draw_line
    local log_file=$(mktemp)
    $CLI_PATH compile --fqbn "$FQBN" -j 2 "$PROJECT_PATH" > "$log_file" 2>&1 &
    local pid=$!
    while kill -0 $pid 2>/dev/null; do
        local last_line=$(tail -n 1 "$log_file" | cut -c1-100)
        echo -ne "  ${CYAN}➜${NC} $last_line\033[K\r"
        sleep 0.1
    done
    wait $pid
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo -e "\n${GREEN} [V] KOMPILASI BERHASIL!${NC}"
        draw_line
        echo -e "${YELLOW} [STEP 2/2] FLASHING...${NC}"
        PORT=$(ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -n 1)
        if [ -n "$PORT" ]; then
            sudo chmod 666 "$PORT" 2>/dev/null
            $CLI_PATH upload -p "$PORT" --fqbn "$FQBN" "$PROJECT_PATH"
            echo -e "${GREEN} [V] SEMUA PROSES SELESAI!${NC}"
        else
            echo -e "${RED} [!] PORT TIDAK DITEMUKAN!${NC}"
        fi
    else
        echo -e "\n${RED} [X] KOMPILASI GAGAL! Detail Error:${NC}"
        cat "$log_file"
    fi
    rm -f "$log_file"
    read -p " Tekan ENTER untuk kembali..."
}

# --- [UPDATE] LIBRARY MANAGER PRO ---
manage_libraries() {
    while true; do
        display_header
        echo -e "${GREEN}--- LIBRARY MANAGER ---${NC}"
        echo -e " [1] Cari & Install    [2] List Terpasang"
        echo -e " [3] Update Database   [4] Kembali"
        draw_line
        read -e -p " Pilih Aksi: " lib_act
        case $lib_act in
            1) 
                read -p " Masukkan Nama Library/Keyword: " kw
                echo -e "${YELLOW} [..] Mencari library...${NC}"
                # Ambil daftar nama library
                mapfile -t lib_list < <($CLI_PATH lib search "$kw" | grep "Name:" | sed 's/Name: //g' | tr -d '"' | head -n 15)
                
                if [ ${#lib_list[@]} -eq 0 ]; then
                    echo -e "${RED} [!] Library tidak ditemukan.${NC}"
                    sleep 2; continue
                fi

                display_header
                echo -e "${GREEN}HASIL PENCARIAN (Top 15):${NC}"
                for i in "${!lib_list[@]}"; do
                    echo -e " [${CYAN}$((i+1))${NC}] ${lib_list[$i]}"
                done
                draw_line
                read -p " Pilih nomor untuk Detail (atau 'q' batal): " lib_sel
                [[ "$lib_sel" == "q" ]] && continue
                
                selected_name="${lib_list[$((lib_sel-1))]}"
                [ -z "$selected_project" ] && continue

                # Tampilkan Detail
                display_header
                echo -e "${YELLOW}--- DETAIL LIBRARY ---${NC}"
                $CLI_PATH lib search "$selected_name" | grep -E "Name:|Author:|Maintainer:|Sentence:|Paragraph:|Website:|Versions:" | sed 's/^  //'
                draw_line
                read -p " Instal library ini? (y/n): " inst_q
                if [[ "$inst_q" =~ ^[Yy]$ ]]; then
                    echo -e "${CYAN} [..] Mengunduh & Menginstal...${NC}"
                    $CLI_PATH lib install "$selected_name"
                    echo -e "${GREEN} [V] Berhasil diinstal!${NC}"
                    sleep 2
                fi
                ;;
            2) $CLI_PATH lib list; read -p " Enter..." ;;
            3) echo -e "${YELLOW} [..] Memperbarui index library...${NC}"; $CLI_PATH lib update-index; echo -e "${GREEN} [V] Selesai.${NC}"; sleep 1 ;;
            4) break ;;
        esac
    done
}

# --- MAIN LOOP ---
open_alt_screen
check_engine
mkdir -p "$ARDUINO_DIR"

while true; do
    display_header
    cd "$ARDUINO_DIR" || exit
    echo -e "${YELLOW}DAFTAR PROYEK DI ~/Arduino:${NC}"
    # FIX BUG: Filter folder 'libraries' agar tidak muncul di daftar
    projects=($(ls -d */ 2>/dev/null | grep -v "libraries/" | sed 's/\///'))
    
    for i in "${!projects[@]}"; do
        echo -e " [${CYAN}$((i+1))${NC}] ${projects[$i]}"
    done
    echo -e " [${GREEN}n${NC}] Buat Proyek Baru  [${RED}q${NC}] Keluar"
    draw_line
    read -p " Pilih >> " p_choice

    if [[ "$p_choice" == "q" ]]; then close_alt_screen; exit 0; fi
    if [[ "$p_choice" == "n" ]]; then
        read -p " Nama Proyek: " new_p
        new_p=${new_p// /_}
        $CLI_PATH sketch new "$new_p" > /dev/null
        selected_project="$new_p"
    else
        selected_project="${projects[$((p_choice-1))]}"
    fi

    [ -z "$selected_project" ] && continue
    PROJECT_PATH="$ARDUINO_DIR/$selected_project"
    CONFIG_FILE="$PROJECT_PATH/.esp_config"
    
    sync_project_file
    [ ! -f "$CONFIG_FILE" ] && setup_new_config
    source "$CONFIG_FILE"

    while true; do
        display_header
        echo -e " ${PURPLE}ACTIVE PROJECT :${NC} ${GREEN}$selected_project${NC}"
        echo -e " ${PURPLE}ACTIVE BOARD   :${NC} ${CYAN}$FQBN${NC}"
        draw_line
        echo -e " [1] ${YELLOW}Edit Code (.ino)${NC}    [2] ${GREEN}Compile & Upload${NC}"
        echo -e " [3] ${CYAN}Serial Monitor${NC}      [4] ${PURPLE}Re-Config Board${NC}"
        echo -e " [5] Library Manager       [6] Ganti Proyek"
        echo -e " [c] ${RED}Clean Build Cache${NC}"
        read -p " Menu >> " action

        case $action in
            1) 
                display_header
                echo -e "${GREEN}DAFTAR FILE:${NC}"
                files=($(ls "$PROJECT_PATH" | grep -v ".esp_config"))
                for i in "${!files[@]}"; do echo -e " [$((i+1))] ${files[$i]}"; done
                read -p " Pilih nomor: " f_num
                target_file="${files[$((f_num-1))]}"
                [ -n "$target_file" ] && nano "$PROJECT_PATH/$target_file" 
                ;;
            2) smart_compile_upload ;;
            3) 
                PORT=$(ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -n 1)
                if [ -n "$PORT" ]; then
                    $CLI_PATH monitor -p "$PORT" -c baudrate=115200
                else
                    echo -e "${RED} [!] Port Tidak Ditemukan!${NC}"
                    sleep 1
                fi
                ;;
            4) setup_new_config; source "$CONFIG_FILE" ;;
            5) manage_libraries ;;
            6) break ;;
            c) 
                echo -e "${YELLOW} [..] Membersihkan cache kompilasi...${NC}"
                rm -rf "$PROJECT_PATH/build"
                echo -e "${GREEN} [V] Cache Dihapus.${NC}"
                sleep 1 ;;
        esac
    done
done
