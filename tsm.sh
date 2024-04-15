#!/bin/bash

# 脚本文件名
script_name=$0

# 临时 sudo 权限目录
temp_sudo_dir="/etc/sudoers.d/temp"
# 主 sudoers 目录
sudoers_dir="/etc/sudoers.d"

# 日志文件位置
log_file="/var/log/sudoers_timed.log"

# 确保临时目录和日志文件存在，如果不存在则创建它们。
mkdir -p $temp_sudo_dir
touch $log_file
chmod 664 $log_file

# 定义函数 echo_green，用于以绿色字体输出信息。
function echo_green {
    echo -e "\e[32m>> $1\e[0m"
}

# 定义函数 echo_red，用于以红色字体输出信息。
function echo_red {
    echo -e "\e[31m>> $1\e[0m"
}

# 初始化函数，用于清空日志文件和临时目录下的文件。
# 如果文件或目录已存在，则询问用户是否确认要删除。
init() {
    local log_exists_nonempty=false
    local dir_exists_nonempty=false

    # 检查日志文件是否存在且非空
    if [ -s "$log_file" ]; then
        log_exists_nonempty=true
    fi

    # 检查目录是否存在且非空
    if [ "$(ls -A $temp_sudo_dir)" ]; then
        dir_exists_nonempty=true
    fi

    # 如果日志文件或目录非空，提示用户确认是否继续
    if $log_exists_nonempty || $dir_exists_nonempty; then
        echo_green "This will clear all sudo privileges from the log and temp directory."
        read -p "Are you sure you want to continue? (y/n): " confirm
        case "$confirm" in
            [yY][eE][sS]|[yY])
                echo_green "Clearing log and temp directory..."
                ;;
            *)
                echo_green "Initialization canceled."
                return
                ;;
        esac
    else
        echo_green "Log file and temp directory are already empty."
    fi

    # 执行清空操作
    > "$log_file" || { echo_red "Failed to clear log file"; return 1; }
    rm -f ${temp_sudo_dir}/* || { echo_red "Failed to clear temp directory"; return 1; }
    echo_green "Initialization complete."
}

# 同步权限函数，确保日志文件中的用户信息与临时sudo目录中的一致。
function sync_permissions {
    # 清理无效的 sudo 文件和链接
    local existing_users=()
    local logged_user
    while IFS=' ' read -r logged_user _; do
        existing_users+=("$logged_user")
    done < $log_file

    # 检查 /etc/sudoers.d/temp 目录中的每个文件是否在日志中有记录
    for entry in $temp_sudo_dir/*; do
        if [ -f "$entry" ]; then
            local file_user=$(basename "$entry")
            local link_path="$sudoers_dir/$file_user"
            if [[ ! " ${existing_users[*]} " =~ " $file_user " ]]; then
                echo_red "Removing unauthorized sudo file for $file_user."
                sudo rm -f "$entry"
                sudo rm -f "$link_path"  # 确保同时删除软链接
            fi
        fi
    done

    # 检查 /etc/sudoers.d 中的软链接是否有效
    for link in $sudoers_dir/*; do
        if [ -L "$link" ]; then  # 只关心软链接
            local target_file=$(readlink -f "$link")
            local link_user=$(basename "$link")
            if [[ ! -f "$target_file" || ! " ${existing_users[*]} " =~ " $link_user " ]]; then
                echo_red "Removing broken or unauthorized sudo link for $link_user."
                sudo rm -f "$link"
            fi
        fi
    done
}


# 新增临时授权的用户，若存在则更新时间
function add_sudo {
    local username=$1
    local duration=$2
    local check_user=$3

    if [[ "$check_user" == "-c" ]]; then
        if ! id "$username" &>/dev/null; then
            echo_red "Error: No such user '$username' found on this system."
            return 1
        fi
    fi

    sync_permissions

    if [[ -z "$username" || -z "$duration" ]]; then
        echo_red "Error: Username or duration cannot be empty."
        return 1
    fi

    local user_file="$temp_sudo_dir/$username"
    local sudoers_link="$sudoers_dir/$username"
    local update=false
    if grep -q "^$username " $log_file; then
        update=true
        local old_at_job_id=$(grep "^$username " $log_file | awk '{print $4}')
        sudo atrm $old_at_job_id || { echo "Failed to remove old at job for $username"; return 1; }
        sudo sed -i "/^$username /d" $log_file || echo "Failed to update log file for $username"
    fi

    if $update; then
        echo_green "Updating sudo privileges for $username"
    else
        echo_green "Adding sudo privileges to $username"
    fi

    echo "$username ALL=(ALL:ALL) ALL" | sudo tee "$user_file" > /dev/null
    sudo ln -sf "$user_file" "$sudoers_link" || { echo_red "Failed to create symlink for $username"; return 1; }
    local at_command="sudo rm -f '$user_file' && sudo rm -f '$sudoers_link' && sudo sed -i '/^$username /d' $log_file"
    local at_output=$(echo "$at_command" | sudo at now + ${duration} hours 2>&1)
    local at_job_id=$(echo "$at_output" | grep -oP 'job \K\d+')
    echo "$username $duration $(date +%s) $at_job_id" | sudo tee -a $log_file > /dev/null
    echo_green "Sudo privileges (re)granted to $username for $duration hours."
}



# 时间美化函数，将分钟数转换为年月日时分的格式。
function format_duration {
    local total_minutes=$1
    local minutes=$((total_minutes % 60))
    local total_hours=$((total_minutes / 60))
    local hours=$((total_hours % 24))
    local total_days=$((total_hours / 24))
    local days=$((total_days % 30))
    local total_months=$((total_days / 30))
    local months=$((total_months % 12))
    local years=$((total_months / 12))

    local result=""
    [[ $years -gt 0 ]] && result+="${years}Y"
    [[ $months -gt 0 ]] && result+="${months}M"
    [[ $days -gt 0 ]] && result+="${days}d"
    [[ $hours -gt 0 ]] && result+="${hours}h"
    [[ $minutes -gt 0 ]] && result+="${minutes}m"

    echo "$result"
}

# 列出临时授权的用户函数，包括总时长和剩余时间。
function list_sudo {
    sync_permissions
    local header_format="| %-15s | %-30s | %-24s | %-30s |\n"
    local line_format="| %-15s | %-30s | %-24s | %-30s |\n"
    local divider="|-----------------|--------------------------------|--------------------------|--------------------------------|\n"

    # 打印表格头部和分割线
    echo -e "\e[32m"
    printf "$divider"
    printf "$header_format" "Username" "Granted for" "Granted on" "Expires in"
    printf "$divider"
    echo -e "\e[0m"

    while IFS=' ' read -r username duration timestamp at_job_id; do
        if [[ -z "$username" || -z "$duration" || -z "$timestamp" ]]; then
            echo "Skipping incomplete or corrupted entry."
            continue
        fi

        if ! granted_on=$(date -d "@$timestamp" +"%Y-%m-%d %H:%M:%S"); then
            echo "Error processing date for entry with username '$username' and timestamp '$timestamp'"
            continue
        fi

        local now=$(date +%s)
        local granted_seconds=$((duration * 3600))
        local remaining_seconds=$((granted_seconds - (now - timestamp)))
        local remaining_minutes=$((remaining_seconds / 60))

        local formatted_duration=$(format_duration $((duration * 60)))
        local formatted_remaining=$(format_duration $remaining_minutes)

        # 格式化输出每行数据
        printf "$line_format" "$username" "$formatted_duration" "$granted_on" "$formatted_remaining"
    done < $log_file

    # 输出底部分割线
    echo -e "\e[32m"
    printf "$divider"
    echo -e "\e[0m"
}

# 删除临时授权的用户函数
function del_sudo {
    local username=$1
    sync_permissions
    if ! grep -q "^$username " $log_file; then
        echo_green "No sudo privileges exist for $username. Nothing to remove."
        return
    fi
    local user_file="$temp_sudo_dir/$username"
    local sudoers_link="$sudoers_dir/$username"
    if [[ -f "$sudoers_link" || -f "$user_file" ]]; then
        sudo rm -f "$user_file"
        sudo rm -f "$sudoers_link"
        echo_green "Sudo privileges removed from $username."
    else
        echo_red "Failed to find sudo files for $username."
        return 1
    fi
    local old_at_job_id=$(grep "^$username " $log_file | awk '{print $4}')
    if [[ -n "$old_at_job_id" ]]; then
        sudo atrm $old_at_job_id || echo_red "Failed to remove at job with ID $old_at_job_id"
    fi
    sudo sed -i "/^$username /d" $log_file
}


# 显示脚本用法和各命令的详细说明的函数
function show_usage {
    echo -e "\e[32mUsage: $script_name {add|list|del|init} [options]\e[0m"
    echo ""
    echo "Commands:"
    echo "  add <username> <duration_in_hours> [-c]  Add temporary sudo privileges to a user for a specified duration in hours."
    echo "                                          If -c is specified, check for user existence before adding."
    echo "                                          If -p is specified instead of duration, grant permanent sudo privileges."
    echo "  list                                     List all users with current sudo privileges, including duration and expiration."
    echo "  del <username>                           Remove sudo privileges for a specified user."
    echo "  init                                     Initialize the environment by clearing the log file and temporary sudo directory."
    echo "                                          If files exist, user confirmation will be requested before deletion."
    echo ""
    echo "Options:"
    echo "  -p                                       Use with the 'add' command to grant permanent sudo privileges."
    echo "  -c                                       Use with the 'add' command to check user existence before adding."
    echo ""
    echo "Examples:"
    echo "  $script_name add username 6             Add 6 hours of sudo privileges to 'username'."
    echo "  $script_name add username -p            Grant permanent sudo privileges to 'username'."
    echo "  $script_name add username 6 -c          Check if 'username' exists, then add 6 hours of sudo privileges."
    echo "  $script_name list                       Display all active sudo privileges."
    echo "  $script_name del username               Remove sudo privileges from 'username'."
    echo "  $script_name init                       Clear all logs and temporary files after confirmation."
    echo ""
}

# 主逻辑处理参数和命令
case "$1" in
    add)
        if [[ "$3" == "-p" ]]; then
            if [ "$#" -ne 3 ]; then
                echo "Usage: $script_name add username -p"
                exit 1
            fi
            add_sudo $2 "876000"
        elif [[ "$4" == "-c" ]]; then
            if [ "$#" -ne 4 ]; then
                echo "Usage: $script_name add username duration_in_hours -c"
                exit 1
            fi
            add_sudo $2 $3 "-c"
        else
            if [ "$#" -ne 3 ]; then
                echo "Usage: $script_name add username duration_in_hours"
                exit 1
            fi
            add_sudo $2 $3
        fi
        ;;
    list)
        if [ "$#" -ne 1 ]; then
            echo -e "Usage: $script_name list\nExample: sh $script_name list"
            exit 1
        fi
        list_sudo
        ;;
    del)
        if [ "$#" -ne 2 ]; then
            echo -e "Usage: $script_name del username\nExample: sh $script_name del username"
            exit 1
        fi
        del_sudo $2
        ;;
    init)
        init
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
