#!/bin/bash
#
# 批量启动/停止 sys_logger.sh 并收集日志（支持 CSV 转 Excel）
#
# 功能:
#   - 在多台服务器上启动 sys_logger.sh，采集 CPU/GPU/内存/网卡 数据
#   - 管理机按 Ctrl+C 停止时，自动结束远程采集，并下载日志到本地
#   - 本地日志可选地转换为 Excel (.xlsx)
#
# 使用示例:
#   ./multi_logger.sh
#       → 日志保存到 ./logs/
#
#   ./multi_logger.sh exp1
#       → 日志保存到 ./logs_exp1/
#
#   ./multi_logger.sh exp2 --no-excel
#       → 日志保存到 ./logs_exp2/，仅保留 CSV，不转换 Excel
#
# 注意事项:
#   1. 需要安装 sshpass（apt install sshpass）
#   2. 如果需要 Excel 转换，管理机需安装 Python3 + pandas + openpyxl
#   3. 脚本里密码是明文存储 ⚠️ 有安全风险，仅推荐测试环境使用
#

# ===== 配置区 =====
SERVERS=("user@ip1" "user@ip2")   # 改成你的服务器地址
PASSWORD="xxxx"                                 # ⚠️ 明文存储密码（有安全风险）
REMOTE_SCRIPT="/tmp/sys_logger.sh"                    # 分发到远程的路径
REMOTE_FILE="/tmp/sys_log.csv"                        # 远程日志文件
BASE_DIR="./logs"                                     # 本地保存目录
INTERVAL=1                                            # 采样间隔（秒）
NETDEV="eno1"                                         # 网卡名
# ==================

# ===== 参数处理 =====
FOLDER_SUFFIX=""
NO_EXCEL=false
for arg in "$@"; do
    case $arg in
        --no-excel) NO_EXCEL=true ;;
        *) FOLDER_SUFFIX="$arg" ;;
    esac
done

if [ -n "$FOLDER_SUFFIX" ]; then
    LOCAL_DIR="$BASE_DIR/$FOLDER_SUFFIX"
else
    LOCAL_DIR="$BASE_DIR"
fi
mkdir -p "$LOCAL_DIR"
echo ">>> 日志目录: $LOCAL_DIR"
echo ">>> 是否导出 Excel: $([ "$NO_EXCEL" = true ] && echo "否" || echo "是")"

# ====== 本地依赖检查 ======
echo ">>> 检查本地依赖..."
if ! command -v python3 >/dev/null; then
    echo ">>> 未找到 python3，请先安装 Python3"
    exit 1
fi
if ! python3 -c "import pandas, openpyxl" 2>/dev/null; then
    echo ">>> 缺少 pandas/openpyxl，尝试安装..."
    pip3 install --user pandas openpyxl || {
        echo ">>> 安装依赖失败，请手动安装：pip install pandas openpyxl"
        exit 1
    }
fi
echo ">>> 本地依赖检查完成 ✅"

# ===== sys_logger.sh 内容 =====
SYS_LOGGER_CONTENT=$(cat <<'EOF'
#!/bin/bash
# ./sys_logger.sh 1 sys_log.csv eth0

INTERVAL=${1:-1}
OUTFILE=${2:-sys_log.csv}
NETDEV=${3:-eno1}

if ! command -v nvidia-smi >/dev/null; then
    echo "错误: 未找到 nvidia-smi，请确认已安装 NVIDIA 驱动"
    exit 1
fi
gpu_count=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)

cleanup() {
    echo ""
    echo ">>> 采样结束，日志已保存到: $OUTFILE"
    exit 0
}
trap cleanup INT

echo ">>> 开始记录 CPU+内存+GPU+网卡，每 $INTERVAL 秒采样一次"
echo ">>> 输出文件: $OUTFILE"
echo ">>> 网卡: $NETDEV"
echo ">>> 按 Ctrl+C 停止"

# 表头
{
    echo -n "timestamp,step,CPU_util(%),Mem_used(MB),Mem_total(MB),Mem_util(%)"
    for ((i=0; i<gpu_count; i++)); do
        echo -n ",GPU${i}_util(%),GPU${i}_mem_used(MB),GPU${i}_mem_total(MB),GPU${i}_mem_util(%),GPU${i}_rx_pcie(MB/s),GPU${i}_tx_pcie(MB/s)"
    done
    echo -n ",${NETDEV}_rx(KB/s),${NETDEV}_tx(KB/s)"
    echo
} > "$OUTFILE"

# CPU 初始值
read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
prev_idle=$((idle+iowait))
prev_total=$((user+nice+system+idle+iowait+irq+softirq+steal))

# 网卡初始值
prev_rx=$(cat /sys/class/net/$NETDEV/statistics/rx_bytes)
prev_tx=$(cat /sys/class/net/$NETDEV/statistics/tx_bytes)

step=0
while true; do
    ts=$(date +"%Y-%m-%d %H:%M:%S.%3N")
    line="$ts,$step"

    # CPU 使用率
    read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    cur_idle=$((idle+iowait))
    cur_total=$((user+nice+system+idle+iowait+irq+softirq+steal))
    diff_idle=$((cur_idle-prev_idle))
    diff_total=$((cur_total-prev_total))
    cpu_util=$(( (100 * (diff_total-diff_idle)) / diff_total ))
    prev_idle=$cur_idle
    prev_total=$cur_total

    # 内存占用
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_avail=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_used=$((mem_total - mem_avail))
    mem_util=$((100 * mem_used / mem_total))
    mem_total_mb=$((mem_total / 1024))
    mem_used_mb=$((mem_used / 1024))
    line="$line,$cpu_util,$mem_used_mb,$mem_total_mb,$mem_util"

    # GPU 数据
    gpu_stats=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits)
    # 一次性采集 PCIe 流量 (每行一个 GPU，列分别是 rx tx)
    # mapfile -t pcie_stats < <(nvidia-smi dmon -s t -c 1 --format=csv,noheader | tail -n +2)
    mapfile -t pcie_stats < <(nvidia-smi dmon -s t -c 1 | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1","$2","$3}')
    gpu_idx=0
    while IFS=',' read -r util mem_used mem_total; do
        util=$(echo "$util" | xargs)
        mem_used=$(echo "$mem_used" | xargs)
        mem_total=$(echo "$mem_total" | xargs)
        if [ "$mem_total" -gt 0 ] 2>/dev/null; then
            mem_util_gpu=$((100 * mem_used / mem_total))
        else
            mem_util_gpu=0
        fi

        # 从 dmon 输出里取 PCIe 数据
        pcie_rx=$(echo "${pcie_stats[$gpu_idx]}" | cut -d, -f2)
        pcie_tx=$(echo "${pcie_stats[$gpu_idx]}" | cut -d, -f3)

        line="$line,$util,$mem_used,$mem_total,$mem_util_gpu,$pcie_rx,$pcie_tx"
        gpu_idx=$((gpu_idx+1))
    done <<< "$gpu_stats"

    # 网卡数据
    cur_rx=$(cat /sys/class/net/$NETDEV/statistics/rx_bytes)
    cur_tx=$(cat /sys/class/net/$NETDEV/statistics/tx_bytes)
    rx_rate=$(( (cur_rx - prev_rx) / (1024 * INTERVAL) ))
    tx_rate=$(( (cur_tx - prev_tx) / (1024 * INTERVAL) ))
    prev_rx=$cur_rx
    prev_tx=$cur_tx

    line="$line,$rx_rate,$tx_rate"

    echo "$line" >> "$OUTFILE"
    step=$((step+1))
    sleep $INTERVAL
done
EOF
)
# ===== 结束 sys_logger.sh =====

# 清理函数
cleanup() {
    echo ""
    echo ">>> 停止远程脚本并收集日志..."
    for srv in "${SERVERS[@]}"; do
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $srv "pkill -f $REMOTE_SCRIPT" 2>/dev/null
        host=$(echo $srv | cut -d@ -f2)
        echo ">>> 下载 $srv 的日志"
        if [ -n "$FOLDER_SUFFIX" ]; then
            LOCAL_FILE="${LOCAL_DIR}/${host}_${FOLDER_SUFFIX}_sys_log.csv"
        else
            LOCAL_FILE="${LOCAL_DIR}/${host}_sys_log.csv"
        fi
        sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no $srv:$REMOTE_FILE "$LOCAL_FILE" 2>/dev/null
    done
    if [ "$NO_EXCEL" = false ]; then
      echo ">>> 合并为单个 Excel 文件（每台服务器一个 Sheet）..."
      python3 - <<PYCODE
import pandas as pd
import glob
import os

log_dir = "${LOCAL_DIR}"
suffix = "${FOLDER_SUFFIX}" if "${FOLDER_SUFFIX}" else "default"
files = glob.glob(os.path.join(log_dir, "*_sys_log.csv"))
if not files:
    print("未找到日志文件")
else:
    out_excel = os.path.join(log_dir, f"all_servers_logs_{suffix}.xlsx")
    with pd.ExcelWriter(out_excel, engine="openpyxl") as writer:
        for f in files:
            try:
                df = pd.read_csv(f)
                sheet_name = os.path.basename(f).split("_")[0]  # 取 host/IP 作为 sheet 名
                df.to_excel(writer, index=False, sheet_name=sheet_name[:30])
                print(f"已写入 sheet: {sheet_name}")
            except Exception as e:
                print(f"处理 {f} 失败: {e}")
    print(f"合并完成: {out_excel}")
PYCODE
    fi
    echo ">>> 全部完成 ✅"
    exit 0
}
trap cleanup INT

# 分发脚本
echo ">>> 分发 sys_logger.sh 到远程..."
for srv in "${SERVERS[@]}"; do
    echo ">>> $srv"
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $srv "cat > $REMOTE_SCRIPT && chmod +x $REMOTE_SCRIPT" <<< "$SYS_LOGGER_CONTENT"
done

# 启动日志采集
echo ">>> 启动日志采集..."
for srv in "${SERVERS[@]}"; do
    echo ">>> $srv"
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $srv "nohup $REMOTE_SCRIPT $INTERVAL $REMOTE_FILE $NETDEV > /dev/null 2>&1 &"
done

echo ">>> 所有服务器已启动日志采集，按 Ctrl+C 停止并收集日志"
while true; do sleep 60; done
