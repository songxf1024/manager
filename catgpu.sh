#!/bin/bash
# catgpu.sh
# Terminal GPU usage & memory usage chart with colors.
# Supports smooth refresh, dual-line chart (GPU util in blue, memory in yellow).

WIDTH=60
INTERVAL=0.5
HEIGHT=20
MARGIN=10
history_util=()
history_mem=()
min_usage=101
max_usage=-1
point_util="_"
point_mem="_"
last_max=-1

# ---- layout ----
HEADER_LINES=4
INFO_TOP=$HEADER_LINES
CHART_TOP=$((HEADER_LINES + 2))
DATA_COL_START=6

GPU_ID=0
while getopts "g:h" opt; do
  case "$opt" in
    g) GPU_ID="$OPTARG" ;;
    h)
      echo "Usage: $0 [-g GPU_ID]"
      exit 0
      ;;
  esac
done

# 采样函数：返回 GPU 利用率 和 显存占用率
get_gpu_usage() {
    read util mem_used mem_total <<< $(nvidia-smi \
        --query-gpu=utilization.gpu,memory.used,memory.total \
        --format=csv,noheader,nounits -i $GPU_ID 2>/dev/null | tr -d ',')
    mem_util=$((100 * mem_used / mem_total))
    echo "$util $mem_util $mem_used $mem_total"
}

cleanup() {
    tput cnorm
    stty echo
    exit
}
trap cleanup INT TERM

# --- draw X axis ---
draw_x_axis() {
    local axis_row=$((CHART_TOP + HEIGHT + 1))
    tput cup "$axis_row" 5; echo -n "└"
    tput cup "$axis_row" 6; printf '%-*s' "$WIDTH" "$(printf '─%.0s' $(seq 1 $WIDTH))"
    tput cup $((axis_row + 1)) 7
    for ((i=0; i<=WIDTH; i+=10)); do
        label=$(awk -v i=$i -v itv=$INTERVAL 'BEGIN {printf "%.1fs", i*itv}')
        printf "%-10s" "$label"
    done
}

tput civis
stty -echo

sleep $INTERVAL

clear
echo  "┌────────────────────────────────────┐"
printf "│  GPU Monitor (refresh %.1fs)        │\n" "$INTERVAL"
echo  "│           xfxuezhang.cn            │"
echo  "└────────────────────────────────────┘"

for ((row=HEIGHT; row>=0; row--)); do printf "     │\n"; done
draw_x_axis

x=0
while true; do
    read usage mem_usage mem_used mem_total < <(get_gpu_usage)

    # 更新历史
    history_util+=($usage)
    history_mem+=($mem_usage)
    if [ ${#history_util[@]} -gt $WIDTH ]; then history_util=("${history_util[@]:1}"); fi
    if [ ${#history_mem[@]}  -gt $WIDTH ]; then history_mem=("${history_mem[@]:1}"); fi

    # 动态 Y 范围
    max_u=$(printf "%s\n" "${history_util[@]}" "${history_mem[@]}" | sort -n | tail -1)
    max=$((max_u+MARGIN)); ((max>100)) && max=100
    scale_den=$((max)); ((scale_den<=0)) && scale_den=1

    # --- header info ---
    tput cup "$INFO_TOP" 0
    printf "GPU usage: \033[34m%3d%%\033[0m   " "$usage"
    printf "Mem usage: \033[33m%3d%%\033[0m (%d/%d MiB)   " "$mem_usage" "$mem_used" "$mem_total"

    # --- Y-axis labels ---
    for ((row=0; row<=HEIGHT; row++)); do
        yval=$(awk -v s=$scale_den -v h=$HEIGHT -v r=$row 'BEGIN {
            v = s*(h-r)/h; printf "%.0f", v
        }')
        tput cup $((CHART_TOP + row)) 0
        printf "%3d%% │" "$yval"
    done

    # --- redraw if Y range changes ---
    if (( max != last_max )); then
        for ((row=0; row<=HEIGHT; row++)); do
            tput cup $((CHART_TOP + row)) $DATA_COL_START
            printf "%-${WIDTH}s" " "
        done
        for ((col=0; col<${#history_util[@]}; col++)); do
            val_u=${history_util[col]}
            ypos_u=$(( val_u*HEIGHT/scale_den ))
            r_u=$((HEIGHT-ypos_u))
            tput cup $((CHART_TOP + r_u)) $((DATA_COL_START + col))
            echo -ne "\033[34m${point_util}\033[0m"

            val_m=${history_mem[col]}
            ypos_m=$(( val_m*HEIGHT/scale_den ))
            r_m=$((HEIGHT-ypos_m))
            tput cup $((CHART_TOP + r_m)) $((DATA_COL_START + col))
            echo -ne "\033[33m${point_mem}\033[0m"
        done
        last_max=$max
        x=${#history_util[@]}; (( x>WIDTH )) && x=$WIDTH
        draw_x_axis
        sleep $INTERVAL
        continue
    fi

    # --- streaming draw ---
    if (( x < WIDTH )); then
        ypos_u=$(( usage*HEIGHT/scale_den ))
        r_u=$((HEIGHT-ypos_u))
        tput cup $((CHART_TOP + r_u)) $((DATA_COL_START + x))
        echo -ne "\033[34m${point_util}\033[0m"

        ypos_m=$(( mem_usage*HEIGHT/scale_den ))
        r_m=$((HEIGHT-ypos_m))
        tput cup $((CHART_TOP + r_m)) $((DATA_COL_START + x))
        echo -ne "\033[33m${point_mem}\033[0m"
        ((x++))
    else
        for ((row=0; row<=HEIGHT; row++)); do
            tput cup $((CHART_TOP + row)) $DATA_COL_START
            printf "%-${WIDTH}s" " "
        done
        for ((col=0; col<WIDTH; col++)); do
            val_u=${history_util[col]}
            ypos_u=$(( val_u*HEIGHT/scale_den ))
            r_u=$((HEIGHT-ypos_u))
            tput cup $((CHART_TOP + r_u)) $((DATA_COL_START + col))
            echo -ne "\033[34m${point_util}\033[0m"

            val_m=${history_mem[col]}
            ypos_m=$(( val_m*HEIGHT/scale_den ))
            r_m=$((HEIGHT-ypos_m))
            tput cup $((CHART_TOP + r_m)) $((DATA_COL_START + col))
            echo -ne "\033[33m${point_mem}\033[0m"
        done
    fi

    draw_x_axis
    sleep $INTERVAL
done
