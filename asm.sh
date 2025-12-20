#!/bin/bash

# 简单的 Linux 开机自启动项管理脚本（基于 systemd）
# 文件:
#   自启动命令列表: /etc/custom_autostart_cmds.sh
#   systemd 服务:   /etc/systemd/system/custom-autostart.service

AUTOSTART_FILE="/etc/custom_autostart_cmds.sh"
SERVICE_FILE="/etc/systemd/system/custom-autostart.service"
SERVICE_NAME="custom-autostart.service"

# ========= 颜色定义 =========
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
BOLD='\033[1m'
RESET='\033[0m'

cecho() {
    # 用法：cecho "$GREEN" "文字"
    local color="$1"
    shift
    printf "%b%s%b\n" "${color}" "$*" "${RESET}"
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        cecho "$RED" "请用 root 权限运行本脚本，例如：sudo $0"
        exit 1
    fi
}

# 一次性检查并创建/修复环境（sh + service + enable），只询问一次
init_environment_once() {
    local need_file=0
    local need_service=0
    local need_enable=0

    # 检查命令文件
    if [ ! -f "$AUTOSTART_FILE" ]; then
        need_file=1
    fi

    # 检查服务文件 和 启用状态
    if [ ! -f "$SERVICE_FILE" ]; then
        need_service=1
    else
        # 服务文件存在但可能未启用
        if ! systemctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
            need_enable=1
        fi
    fi

    # 都齐全且已启用，就不打扰你
    if [ "$need_file" -eq 0 ] && [ "$need_service" -eq 0 ] && [ "$need_enable" -eq 0 ]; then
        return 0
    fi

    cecho "$YELLOW" "检测到开机自启动环境尚未完全初始化："
    [ "$need_file" -eq 1 ]    && echo "  - 缺少命令文件：$AUTOSTART_FILE"
    [ "$need_service" -eq 1 ] && echo "  - 缺少 systemd 服务：$SERVICE_FILE"
    [ "$need_enable" -eq 1 ]  && echo "  - 服务 $SERVICE_NAME 已存在但未启用"

    read -rp "是否现在一次性创建/修复以上项目？[y/N] " ans
    case "$ans" in
        y|Y|yes|YES)
            # 创建命令文件
            if [ "$need_file" -eq 1 ]; then
                cat > "$AUTOSTART_FILE" <<'EOF'
#!/bin/bash
# 自定义开机启动命令列表
# 每一行是一条要在系统启动时执行的命令
# 例如：
# echo "系统已启动" >> /var/log/custom_boot.log
EOF
                chmod +x "$AUTOSTART_FILE"
                cecho "$GREEN" "已创建命令文件：$AUTOSTART_FILE"
            fi

            # 创建服务文件
            if [ "$need_service" -eq 1 ]; then
                cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Custom startup commands

[Service]
Type=oneshot
ExecStart=/bin/bash $AUTOSTART_FILE

[Install]
WantedBy=multi-user.target
EOF
                cecho "$GREEN" "已创建 systemd 服务文件：$SERVICE_FILE"
            fi

            # 只要服务文件存在，就 daemon-reload + enable 一次
            if [ "$need_service" -eq 1 ] || [ "$need_enable" -eq 1 ]; then
                systemctl daemon-reload
                systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 && \
                    cecho "$GREEN" "已启用开机自启动服务：$SERVICE_NAME"
            fi

            return 0
            ;;
        *)
            cecho "$YELLOW" "已取消初始化操作，不会创建/修改任何文件。"
            return 1
            ;;
    esac
}

list_items() {
    # 列表这里也可以触发一次性初始化（主要是创建 sh，有需要也可以顺便修好 service）
    if ! init_environment_once; then
        # 如果用户拒绝初始化，但命令文件至少存在，我们只读文件；
        # 如果文件都没有，那就没法列出
        if [ ! -f "$AUTOSTART_FILE" ]; then
            cecho "$YELLOW" "当前没有自启动命令文件，无法列出。"
            return
        fi
    fi

    cecho "$CYAN" "当前已配置的自启动命令："
    echo "-----------------------------------"
    local idx=0
    while IFS= read -r line; do
        # 跳过 shebang
        if [[ "$line" =~ ^#!/bin/bash ]]; then
            continue
        fi
        # 跳过注释和空行
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        idx=$((idx + 1))
        printf "%b\n" " ${BOLD}${idx})${RESET} $line"
    done < "$AUTOSTART_FILE"

    if [ "$idx" -eq 0 ]; then
        cecho "$YELLOW" "（暂无任何自启动命令）"
    fi
    echo "-----------------------------------"
}

add_item() {
    # 新增命令时，必须确保环境已经初始化（sh + service）
    if ! init_environment_once; then
        cecho "$RED" "初始化未完成，无法添加自启动命令。"
        return
    fi

    read -rp "请输入要添加的开机自启动命令： " cmd
    if [ -z "$cmd" ]; then
        cecho "$YELLOW" "命令不能为空，已取消添加。"
        return
    fi

    echo "$cmd" >> "$AUTOSTART_FILE"
    cecho "$GREEN" "已添加：$cmd"
    cecho "$BLUE" "提示：命令将在下次系统重启时自动执行（服务 $SERVICE_NAME 已启用）。"
}

remove_item() {
    if [ ! -f "$AUTOSTART_FILE" ]; then
        cecho "$RED" "自启动命令文件不存在：$AUTOSTART_FILE"
        return
    fi

    mapfile -t cmds < <(awk '
        NR==1 {next}                 # 跳过第一行 shebang
        NF && $1 !~ /^#/ {print}
    ' "$AUTOSTART_FILE")

    if [ "${#cmds[@]}" -eq 0 ]; then
        cecho "$YELLOW" "当前没有可删除的自启动命令。"
        return
    fi

    cecho "$CYAN" "可删除的自启动命令："
    echo "-----------------------------------"
    for i in "${!cmds[@]}"; do
        idx=$((i + 1))
        printf "%b\n" " ${BOLD}${idx})${RESET} ${cmds[$i]}"
    done
    echo "-----------------------------------"

    read -rp "请输入要删除的命令编号（数字）： " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        cecho "$RED" "输入不是有效数字，已取消删除。"
        return
    fi

    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#cmds[@]}" ]; then
        cecho "$RED" "编号超出范围，已取消删除。"
        return
    fi

    # 找到实际文件中的行号
    target_line=$(awk -v idx="$choice" '
        NR==1 {next}
        NF && $1 !~ /^#/ {c++; if (c == idx) {print NR}}
    ' "$AUTOSTART_FILE")

    if [ -z "$target_line" ]; then
        cecho "$RED" "内部错误：找不到对应行号。"
        return
    fi

    deleted_cmd=${cmds[$((choice - 1))]}

    sed -i "${target_line}d" "$AUTOSTART_FILE"
    cecho "$GREEN" "已删除：$deleted_cmd"
}

check_status() {
    if [ ! -f "$SERVICE_FILE" ]; then
        cecho "$YELLOW" "服务文件不存在：$SERVICE_FILE"
        echo "你可以在任意菜单操作时选择初始化环境，或手动创建。"
        return
    fi

    cecho "$CYAN" "systemd 服务状态："
    systemctl status "$SERVICE_NAME" --no-pager
}

uninstall_environment() {
    printf "%b\n" "${RED}================ 卸载当前脚本环境 ================${RESET}"
    printf "%b\n" "${YELLOW}此操作将进行以下更改：${RESET}"
    echo "  - 禁用并删除 systemd 服务：$SERVICE_NAME"
    echo "  - 删除自启动命令文件：$AUTOSTART_FILE"
    echo "  - 你的自定义开机任务将不再执行"
    printf "%b\n" "${BOLD}${RED}注意：此操作不可恢复，请确认你已经备份了需要的命令。${RESET}"
    printf "%b\n" "${RED}=================================================${RESET}"

    # 第一次确认
    read -rp "确定要继续卸载吗？[y/N] " ans1
    case "$ans1" in
        y|Y|yes|YES)
            ;;
        *)
            cecho "$GREEN" "已取消卸载。"
            return
            ;;
    esac

    # 第二次确认（更强）
    printf "%b\n" "${YELLOW}危险操作确认：卸载后无法自动恢复当前配置。${RESET}"
    read -rp "如需继续，请输入大写 'UNINSTALL' 以确认： " ans2
    if [ "$ans2" != "UNINSTALL" ]; then
        cecho "$GREEN" "输入不匹配 'UNINSTALL'，已取消卸载。"
        return
    fi

    cecho "$MAGENTA" "开始执行卸载..."

    # 禁用服务（如果存在）
    if systemctl list-unit-files | grep -q "^$SERVICE_NAME"; then
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 && \
            cecho "$GREEN" "已禁用服务：$SERVICE_NAME"
    fi

    # 删除服务文件
    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"
        cecho "$GREEN" "已删除服务文件：$SERVICE_FILE"
    else
        cecho "$YELLOW" "服务文件不存在：$SERVICE_FILE（跳过删除）"
    fi

    # 重新加载 systemd
    systemctl daemon-reload
    cecho "$BLUE" "已执行 systemctl daemon-reload"

    # 删除自启动命令文件
    if [ -f "$AUTOSTART_FILE" ]; then
        rm -f "$AUTOSTART_FILE"
        cecho "$GREEN" "已删除自启动命令文件：$AUTOSTART_FILE"
    else
        cecho "$YELLOW" "自启动命令文件不存在：$AUTOSTART_FILE（跳过删除）"
    fi

    cecho "$GREEN" "卸载完成：系统已撤销由本脚本创建的开机自启动环境。"
    script_path=$(realpath "$0" 2>/dev/null || echo "$0")
    cecho "$YELLOW" "（本脚本文件本身尚未删除，如不再需要请手动删除：$script_path）"
}

main_menu() {
    while true; do
        echo
        printf "%b\n" "${BOLD}${CYAN}===== 开机自启动项管理 =====${RESET}"
        printf "%b\n" " ${BOLD}1)${RESET} 列出自启动命令"
        printf "%b\n" " ${BOLD}2)${RESET} 新增自启动命令"
        printf "%b\n" " ${BOLD}3)${RESET} 删除自启动命令"
        printf "%b\n" " ${BOLD}4)${RESET} 查看 systemd 服务状态"
        printf "%b\n" " ${BOLD}5)${RESET} ${RED}卸载当前脚本环境${RESET}"
        printf "%b\n" " ${BOLD}0)${RESET} 退出"
        read -rp "请选择操作： " choice

        case "$choice" in
            1) list_items ;;
            2) add_item ;;
            3) remove_item ;;
            4) check_status ;;
            5) uninstall_environment ;;
            0) cecho "$GREEN" "已退出。"; break ;;
            *) cecho "$RED" "无效选择，请重新输入。";;
        esac
    done
}

# 主流程
require_root
main_menu
