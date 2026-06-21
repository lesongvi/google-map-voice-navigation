#!/usr/bin/env bash
# Script written by @lesongvi for HG Logistics navigation voice mod
# Website: https://truckers.vn
# This script will download the latest version of ts-fmod-plugin.dll and copy it to the ETS2 and ATS game directories.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../configs/conf.ini"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Lỗi: Tệp cấu hình bị thiếu tại $CONFIG_FILE" >&2
    exit 1
fi

Get-IniValue() {
    local key="$1"
    grep -E "^[[:space:]]*$key[[:space:]]*=" "$CONFIG_FILE" | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'"'"']//' -e 's/["'"'"']$//' | tr -d '\r'
}

Get-GameVersion() {
    local game_root="$1"
    local game_code="$2"
    local exe_name
    
    if [ "$game_code" = "ETS2" ]; then
        exe_name="eurotrucks2.exe"
    else
        exe_name="amtrucks.exe"
    fi
    
    local exe_path="$game_root/bin/win_x64/$exe_name"
    
    if [ -f "$exe_path" ]; then
        local full_version=""
        
        # 1. Nếu đang chạy trên Windows (Git Bash), tận dụng PowerShell hệ thống để đọc ProductVersion gốc cực chính xác
        if command -v powershell.exe >/dev/null 2>&1; then
            # Chuyển đổi đường dẫn dạng /d/Steam/... sang D:\Steam\... để PowerShell hiểu
            local win_exe_path
            win_exe_path=$(cygpath -w "$exe_path" 2>/dev/null || echo "$exe_path")
            full_version=$(powershell.exe -NoProfile -Command "(Get-ItemProperty -Path '$win_exe_path').VersionInfo.ProductVersion" 2>/dev/null | tr -d '\r' | awk '{print $1}')
        fi
        
        # 2. Nếu chạy trên Linux thuần hoặc PowerShell trả về rỗng, fallback về quét chuỗi nhị phân bằng grep/awk
        if [ -z "$full_version" ] || [ "$full_version" = "Unknown" ]; then
            # Tìm chuỗi có định dạng số dạng X.XX.X.X hoặc X.XX (nới lỏng regex để nhận diện dễ hơn)
            full_version=$(grep -o -a -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[a-z]?' "$exe_path" 2>/dev/null | head -n 1 || echo "")
        fi
        
        # 3. Định hình lại chuỗi để lấy đúng dạng X.XX (ví dụ: 1.59)
        if [ -n "$full_version" ]; then
            echo "$full_version" | cut -d'.' -f1-2
            return
        fi
    fi
    echo "Unknown"
}

HOST=$(Get-IniValue "host")
VERSION=$(Get-IniValue "version")
ETS2_ROOT=$(Get-IniValue "ets2_root")
ATS_ROOT=$(Get-IniValue "ats_root")
VOLUME=$(printf "%.2f" "$(awk -F '=' '/volume/ {gsub(/[ ]/, "", $2); print $2 / 100}' "$CONFIG_FILE")")

FMOD_PLUGIN_URL="$HOST/plugins/ts-fmod-plugin/$VERSION/ts-fmod-plugin.dll"

install_mod() {
    local game_name="$1"
    local game_root="$2"
    local game_code="$3"
    
    local plugin_dir="$game_root/bin/win_x64/plugins"
    local target_dir="$plugin_dir/ts-fmod-plugin"
    
    echo "----------------------------------------"
    echo "Kiểm tra khả năng tương thích cho $game_name..."
    
    local local_game_ver
    local_game_ver=$(Get-GameVersion "$game_root" "$game_code")
    echo "Phiên bản game hiện tại: $local_game_ver"
    
    local remote_version_url="$HOST/plugins/ts-fmod-plugin/$VERSION/$game_code/version.txt"
    local target_game_ver="$local_game_ver"
    
    if json_response=$(curl -sSL --max-time 5 "$remote_version_url"); then
        local_target=$(echo "$json_response" | grep -o '"version":[^,]*' | cut -d'"' -f4 || echo "")
        if [ -n "$local_target" ]; then
            target_game_ver="$local_target"
            echo "Phiên bản plugin trên server: $target_game_ver"
        fi
    else
        echo "Cảnh báo: Không thể xác minh phiên bản với server. Tiếp tục cài đặt..."
    fi

    if [ "$local_game_ver" != "$target_game_ver" ]; then
        echo "Cảnh báo: Phiên bản không khớp! Game của bạn là $local_game_ver nhưng plugin hỗ trợ $target_game_ver."
        echo "Mod có thể không hoạt động chính xác."
        
        read -rp "Bạn có muốn tiếp tục cài đặt không? (Y/N): " choice
        if [ "$choice" != "Y" ] && [ "$choice" != "y" ]; then
            echo "Cài đặt đã bị hủy bởi người dùng."
            return
        fi
    else
        echo "Kiểm tra phiên bản thành công. Game và plugin khớp hoàn hảo."
    fi
    
    echo "----------------------------------------"
    echo "Đang cài đặt HG Logistics navigation voice mod cho $game_name..."
    
    mkdir -p "$target_dir"
    
    curl -sSL -o "$plugin_dir/ts-fmod-plugin.dll" "$FMOD_PLUGIN_URL"
    curl -sSL -o "$target_dir/master.bank" "$HOST/plugins/ts-fmod-plugin/$VERSION/$game_code/master.bank"
    curl -sSL -o "$target_dir/hg_navigation.bank" "$HOST/plugins/ts-fmod-plugin/$VERSION/hg_navigation.bank"
    curl -sSL -o "$target_dir/hg_navigation.bank.guids" "$HOST/plugins/ts-fmod-plugin/$VERSION/hg_navigation.bank.guids"

    local selected_bank_content
    selected_bank_content=$(curl -sSL "$HOST/plugins/ts-fmod-plugin/$VERSION/selected.bank.txt")
    
    if [ -f "$target_dir/selected.bank.txt" ]; then
        if [ -n "$selected_bank_content" ]; then
            while IFS= read -r line; do
                clean_line=$(echo "$line" | tr -d '\r\n[:space:]')
                if [ -n "$clean_line" ] && ! grep -Fxq "$clean_line" "$target_dir/selected.bank.txt"; then
                    echo "$clean_line" >> "$target_dir/selected.bank.txt"
                fi
            done < <(echo "$selected_bank_content")
        fi
    else
        echo "$selected_bank_content" | tr -d '\r' > "$target_dir/selected.bank.txt"
    fi
    
    if [ -f "$target_dir/sound_levels.txt" ]; then
        sed -i 's/"navigation": [0-9.]\+/"navigation": '"$VOLUME"'/' "$target_dir/sound_levels.txt"
    else
        local sound_levels_content
        sound_levels_content=$(curl -sSL "$HOST/plugins/ts-fmod-plugin/$VERSION/sound_levels.txt")
        echo "$sound_levels_content" | sed 's/"navigation": [0-9.]\+/"navigation": '"$VOLUME"'/' > "$target_dir/sound_levels.txt"
    fi
    
    echo "Cài đặt hoàn tất cho $game_name."
}

if [ -n "$ETS2_ROOT" ] && [ -d "$ETS2_ROOT" ]; then
    install_mod "Euro Truck Simulator 2" "$ETS2_ROOT" "ETS2"
else
    echo "Bỏ qua cài đặt ETS2 (Đường dẫn không tồn tại hoặc trống)."
fi

if [ -n "$ATS_ROOT" ] && [ -d "$ATS_ROOT" ]; then
    install_mod "American Truck Simulator" "$ATS_ROOT" "ATS"
else
    echo "Bỏ qua cài đặt ATS (Đường dẫn không tồn tại hoặc trống)."
fi