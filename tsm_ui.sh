#!/bin/bash

# -------------------------
# 基本配置和路径定义
# -------------------------
script_name=$(basename "$0")
# 存放临时 sudo 权限文件的目录
temp_sudo_dir="/etc/sudoers.d/temp"
# 正式 sudo 配置目录
sudoers_dir="/etc/sudoers.d"
# 用于记录添加时间/at任务id等
log_file="/var/log/sudoers_timed.log"
# 界面标题
TITLE="Sudo Privileges Manager"

# -------------------------
# 初始化环境，确保目录和日志文件存在
# -------------------------
function init_environment() {
    if ! command -v at &> /dev/null; then
        dialog --msgbox "The 'at' command is not installed. Cannot set timed removal." 10 30
        return 1
    fi
    sudo mkdir -p "$temp_sudo_dir"
    sudo touch "$log_file"
    sudo chmod 600 "$log_file"
    sudo chown root:root "$log_file"
}

# -------------------------
# 主菜单逻辑，循环显示操作项
# -------------------------
function main_menu() {
    while true; do
        cmd=$(dialog --clear --stdout \
            --title "$TITLE" \
            --menu "Choose an action:" 15 50 5 \
            "1" "Add temporary sudo privileges" \
            "2" "List current sudo privileges" \
            "3" "Remove sudo privileges" \
            "4" "Initialize environment" \
            "5" "Exit")
        case $cmd in
            1) add_sudo_ui;;
            2) list_sudo_ui;;
            3) del_sudo_ui;;
            4) init_ui;;
            5) clear; exit 0 ;;
            *) dialog --msgbox "Invalid option, try again." 10 30;;
        esac
    done
}

# -------------------------
# 添加 sudo 权限的交互 UI
# 自动列出所有非系统用户供选择
# -------------------------
function add_sudo_ui() {
    # 获取系统中非系统用户（UID >= 1000，排除 nobody）
    local user_list=()
    while IFS=: read -r username _ uid _ _ _ _; do
        if [[ "$uid" -ge 1000 && "$username" != "nobody" ]]; then
            user_list+=("$username" "$username's account")
        fi
    done < /etc/passwd
    if [[ ${#user_list[@]} -eq 0 ]]; then
        dialog --msgbox "No valid users found to assign sudo." 10 40
        return
    fi
    # 用户选择菜单
    local username=$(dialog --clear --stdout \
        --title "Select User" \
        --menu "Choose a user to grant temporary sudo:" 15 50 6 \
        "${user_list[@]}")
    if [[ -z "$username" ]]; then
        dialog --msgbox "Username cannot be empty!" 10 30
        return
    fi
    # 输入时长或永久
    local duration=$(dialog --clear --stdout --inputbox "Enter duration in hours (or 'p' for permanent):" 10 40)
    if [[ -z "$duration" ]]; then
        dialog --msgbox "Duration cannot be empty!" 10 30
        return
    fi
    add_sudo "$username" "$duration" "-c"
    dialog --msgbox "Sudo privileges for $username have been updated." 10 30
}

# -------------------------
# 显示当前已有 sudo 权限的用户及其到期时间
# -------------------------
function list_sudo_ui() {
    sync_permissions
    local list_output=$(list_sudo)
    dialog --msgbox "$list_output" 20 80
}

# -------------------------
# 删除 sudo 权限交互 UI
# 自动列出已有 sudo 权限的用户供选择
# -------------------------
function del_sudo_ui() {
    sync_permissions
    local users=()
    while IFS=' ' read -r username _; do
        users+=("$username" "$username's sudo access")
    done < "$log_file"
    if [[ ${#users[@]} -eq 0 ]]; then
        dialog --msgbox "No users currently have sudo privileges." 10 40
        return
    fi
    local username=$(dialog --clear --stdout \
        --title "Remove sudo privileges" \
        --menu "Select a user to remove:" 15 50 6 \
        "${users[@]}")

    if [[ -z "$username" ]]; then
        dialog --msgbox "No user selected." 10 30
        return
    fi

    del_sudo "$username"
    dialog --msgbox "Sudo privileges for $username have been removed." 10 30
}

# -------------------------
# 初始化：清空日志文件并清理所有临时 sudo 文件
# -------------------------
function init_ui() {
    dialog --yesno "This will clear all logs and temporary sudo privileges. Are you sure?" 10 40
    if [[ $? -eq 0 ]]; then
        init
        dialog --msgbox "Environment initialized." 10 30
    else
        dialog --msgbox "Initialization cancelled." 10 30
    fi
}

# -------------------------
# 添加 sudo 权限的核心逻辑
# 支持临时和永久授权，并自动设置 at 定时任务
# -------------------------
function add_sudo() {
    local username=$1
    local duration=$2
    local check_user=$3

    # -------------------------
    # 输入校验
    # -------------------------
    # 校验用户名合法性（符合 Linux 用户名规则）
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        dialog --msgbox "Invalid username format." 10 30
        return 1
    fi

    # 检查用户是否存在（可选）
    if [[ "$check_user" == "-c" ]]; then
        if ! id "$username" &>/dev/null; then
            dialog --msgbox "Error: User '$username' does not exist." 10 30
            return 1
        fi
    fi

    # 检查 duration 参数（必须是数字或 p）
    if [[ "$duration" != "p" && ! "$duration" =~ ^[0-9]+$ ]]; then
        dialog --msgbox "Invalid duration format. Use number of hours or 'p' for permanent." 10 30
        return 1
    fi

    sync_permissions

    if [[ -z "$username" || -z "$duration" ]]; then
        dialog --msgbox "Error: Username or duration cannot be empty." 10 30
        return 1
    fi

    local user_file="$temp_sudo_dir/sudo_timed_$username"
    local sudoers_link="$sudoers_dir/sudo_timed_$username"

    # -------------------------
    # 清理旧 sudo 配置和 at 任务（如存在）
    # -------------------------
    if grep -q "^$username " "$log_file"; then
        local old_at_job_id=$(grep "^$username " "$log_file" | awk '{print $4}')
        sudo atrm "$old_at_job_id"
        sudo sed -i "/^$username /d" "$log_file"
    fi

    # -------------------------
    # 创建新的 sudoers 文件
    # -------------------------
    echo "$username ALL=(ALL:ALL) ALL" | sudo tee "$user_file" > /dev/null
    sudo chmod 440 "$user_file"
    sudo chown root:root "$user_file"

    # -------------------------
    # 使用 visudo 检查 sudoers 文件合法性
    # -------------------------
    if ! sudo visudo -cf "$user_file"; then
        dialog --msgbox "Invalid sudoers file generated for $username. Aborting." 10 30
        sudo rm -f "$user_file"
        return 1
    fi

    # -------------------------
    # 创建软链接（先删除旧的）
    # -------------------------
    if [[ -L "$sudoers_link" || -f "$sudoers_link" ]]; then
        sudo rm -f "$sudoers_link"
    fi
    sudo ln -sf "$user_file" "$sudoers_link"

    # -------------------------
    # 处理定时删除任务
    # -------------------------
    if [[ "$duration" == "p" ]]; then
        # 永久权限，无需设置 at 任务
        echo "$username p $(date +%s) -" | sudo tee -a "$log_file" > /dev/null
    else
        # 设置 at 任务，在指定小时后删除权限        
        local at_command="sudo rm -f '$user_file' '$sudoers_link' && sudo sed -i '/^$username /d' '$log_file'"
        local at_output=$(echo "$at_command" | sudo at now + ${duration} hours 2>&1)
        local at_job_id=$(echo "$at_output" | grep -oP 'job \K\d+')

        if [[ -z "$at_job_id" ]]; then
            dialog --msgbox "Failed to schedule at job. Check if atd service is running." 10 40
            sudo rm -f "$user_file" "$sudoers_link"
            return 1
        fi
        echo "$username $duration $(date +%s) $at_job_id" | sudo tee -a "$log_file" > /dev/null
    fi
}

# -------------------------
# 列出当前 sudo 权限分配情况
# 包括用户名、授权时间、剩余时间
# -------------------------
function list_sudo() {
    sync_permissions
    local output="| Username        | Granted on          | Expires in       |\n"
    output+="--------------------------------------------------------\n"

    while IFS=' ' read -r username duration timestamp at_job_id; do
        local granted_on=$(date -d "@$timestamp" +"%Y-%m-%d %H:%M:%S")
        if [[ "$duration" == "p" ]]; then
            output+="$username | $granted_on | Permanent\n"
        else
            local now=$(date +%s)
            local total_seconds=$((duration * 3600))
            local elapsed_seconds=$((now - timestamp))
            local remaining_seconds=$((total_seconds - elapsed_seconds))

            if (( remaining_seconds < 0 )); then
                remaining_seconds=0
            fi

            # 计算小时和分钟
            local remaining_hours=$((remaining_seconds / 3600))
            local remaining_minutes=$(( (remaining_seconds % 3600) / 60 ))
        
            output+="$username | $granted_on | ${remaining_hours}h ${remaining_minutes}m\n"
        fi
    done < "$log_file"

    echo -e "$output"
}

# -------------------------
# 删除 sudo 权限的逻辑
# 清除文件、链接、at任务 和日志条目
# -------------------------
function del_sudo() {
    local username=$1
    sync_permissions
    if ! grep -q "^$username " "$log_file"; then
        dialog --msgbox "No sudo privileges exist for $username." 10 30
        return
    fi

    local user_file="$temp_sudo_dir/sudo_timed_$username"
    local sudoers_link="$sudoers_dir/sudo_timed_$username"

    sudo rm -f "$user_file" "$sudoers_link"
    local old_at_job_id=$(grep "^$username " "$log_file" | awk '{print $4}')
    sudo atrm "$old_at_job_id" 2>/dev/null
    sudo sed -i "/^$username /d" "$log_file"
}

# -------------------------
# 初始化 sudo 管理环境：清除所有权限配置和日志
# -------------------------
function init() {
    > "$log_file"
    if [[ -d "$temp_sudo_dir" && "$temp_sudo_dir" == /etc/sudoers.d/temp* ]]; then
        sudo rm -f "$temp_sudo_dir"/*
    fi
}

# -------------------------
# 同步权限逻辑，清理已被删除用户残留的 sudo 文件
# -------------------------
function sync_permissions() {
    local existing_users=()
    while IFS=' ' read -r user _; do
        existing_users+=("$user")
    done < "$log_file"

    for file in "$temp_sudo_dir"/*; do
        if [[ -f "$file" ]]; then
            local base=$(basename "$file")
            local user=${base#sudo_timed_}
            local found=0
            for u in "${existing_users[@]}"; do
                if [[ "$u" == "$user" ]]; then
                    found=1
                    break
                fi
            done
            if [[ "$found" -eq 0 ]]; then
                sudo rm -f "$file" "$sudoers_dir/sudo_timed_$user"
            fi
        fi
    done
}

# 初始化环境并启动 UI
init_environment
main_menu
