#!/bin/bash

# 配置文件和目录
script_name=$(basename "$0")
temp_sudo_dir="/etc/sudoers.d/temp"
sudoers_dir="/etc/sudoers.d"
log_file="/var/log/sudoers_timed.log"

# 初始化环境，确保目录和日志文件存在
mkdir -p "$temp_sudo_dir"
touch "$log_file"
chmod 664 "$log_file"

# 界面标题
TITLE="Sudo Privileges Manager"

# 主菜单
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
            1)
                add_sudo_ui
                ;;
            2)
                list_sudo_ui
                ;;
            3)
                del_sudo_ui
                ;;
            4)
                init_ui
                ;;
            5)
                clear
                exit 0
                ;;
            *)
                dialog --msgbox "Invalid option, try again." 10 30
                ;;
        esac
    done
}

# 添加 sudo 权限的 UI
function add_sudo_ui() {
    username=$(dialog --clear --stdout --inputbox "Enter the username:" 10 40)
    if [[ -z "$username" ]]; then
        dialog --msgbox "Username cannot be empty!" 10 30
        return
    fi

    duration=$(dialog --clear --stdout --inputbox "Enter duration in hours (or 'p' for permanent):" 10 40)
    if [[ -z "$duration" ]]; then
        dialog --msgbox "Duration cannot be empty!" 10 30
        return
    fi

    dialog --yesno "Do you want to check if the user exists?" 10 40
    if [[ $? -eq 0 ]]; then
        add_sudo "$username" "$duration" "-c"
    else
        add_sudo "$username" "$duration"
    fi

    dialog --msgbox "Sudo privileges for $username have been updated." 10 30
}

# 列出用户 sudo 权限的 UI
function list_sudo_ui() {
    sync_permissions
    local list_output=$(list_sudo)
    dialog --msgbox "$list_output" 20 80
}

# 删除 sudo 权限的 UI
function del_sudo_ui() {
    username=$(dialog --clear --stdout --inputbox "Enter the username to remove:" 10 40)
    if [[ -z "$username" ]]; then
        dialog --msgbox "Username cannot be empty!" 10 30
        return
    fi

    del_sudo "$username"
    dialog --msgbox "Sudo privileges for $username have been removed." 10 30
}

# 初始化环境的 UI
function init_ui() {
    dialog --yesno "This will clear all logs and temporary sudo privileges. Are you sure?" 10 40
    if [[ $? -eq 0 ]]; then
        init
        dialog --msgbox "Environment initialized." 10 30
    else
        dialog --msgbox "Initialization cancelled." 10 30
    fi
}

# 添加 sudo 权限逻辑
function add_sudo() {
    local username=$1
    local duration=$2
    local check_user=$3

    if [[ "$check_user" == "-c" ]]; then
        if ! id "$username" &>/dev/null; then
            dialog --msgbox "Error: User '$username' does not exist." 10 30
            return 1
        fi
    fi

    sync_permissions

    if [[ -z "$username" || -z "$duration" ]]; then
        dialog --msgbox "Error: Username or duration cannot be empty." 10 30
        return 1
    fi

    local user_file="$temp_sudo_dir/$username"
    local sudoers_link="$sudoers_dir/$username"

    if grep -q "^$username " "$log_file"; then
        local old_at_job_id=$(grep "^$username " "$log_file" | awk '{print $4}')
        sudo atrm "$old_at_job_id"
        sudo sed -i "/^$username /d" "$log_file"
    fi

    echo "$username ALL=(ALL:ALL) ALL" | sudo tee "$user_file" > /dev/null
    sudo ln -sf "$user_file" "$sudoers_link"

    local at_command="sudo rm -f '$user_file' && sudo rm -f '$sudoers_link' && sudo sed -i '/^$username /d' $log_file"
    local at_output=$(echo "$at_command" | sudo at now + ${duration} hours 2>&1)
    local at_job_id=$(echo "$at_output" | grep -oP 'job \K\d+')

    echo "$username $duration $(date +%s) $at_job_id" | sudo tee -a "$log_file" > /dev/null
}

# 列出 sudo 权限逻辑
function list_sudo() {
    sync_permissions
    local output="| Username        | Granted on          | Expires in       |\n"
    output+="--------------------------------------------------------\n"

    while IFS=' ' read -r username duration timestamp at_job_id; do
        local granted_on=$(date -d "@$timestamp" +"%Y-%m-%d %H:%M:%S")
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
    done < "$log_file"

    echo -e "$output"
}


# 删除 sudo 权限逻辑
function del_sudo() {
    local username=$1
    sync_permissions
    if ! grep -q "^$username " "$log_file"; then
        dialog --msgbox "No sudo privileges exist for $username." 10 30
        return
    fi

    local user_file="$temp_sudo_dir/$username"
    local sudoers_link="$sudoers_dir/$username"

    sudo rm -f "$user_file" "$sudoers_link"
    local old_at_job_id=$(grep "^$username " "$log_file" | awk '{print $4}')
    sudo atrm "$old_at_job_id"
    sudo sed -i "/^$username /d" "$log_file"
}

# 初始化逻辑
function init() {
    > "$log_file"
    rm -f "$temp_sudo_dir"/*
}

# 同步权限逻辑
function sync_permissions() {
    local existing_users=()
    while IFS=' ' read -r user _; do
        existing_users+=("$user")
    done < "$log_file"

    for file in "$temp_sudo_dir"/*; do
        if [[ -f "$file" ]]; then
            local user=$(basename "$file")
            if [[ ! " ${existing_users[*]} " =~ " $user " ]]; then
                sudo rm -f "$file" "$sudoers_dir/$user"
            fi
        fi
    done
}

# 启动主菜单
main_menu
