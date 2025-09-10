#!/bin/bash
# catcpu.sh
# Terminal CPU usage chart with colors, min/max, load average.
# Smooth refresh, no flicker; X-axis preserved; rescale-safe.

WIDTH=60
INTERVAL=0.5
HEIGHT=20
MARGIN=10
history=()
min_usage=101
max_usage=-1
point="."
last_max=-1   # last Y-axis top (to detect rescale)

# ---- layout ----
HEADER_LINES=4                  # lines used by the title box
INFO_TOP=$HEADER_LINES          # first info line ("CPU usage")
CHART_TOP=$((HEADER_LINES + 2)) # chart starts after 2 info lines
DATA_COL_START=6                # first column for plotted data

# command-line options: -p <char> to set the plotting point
while getopts "p:h" opt; do
  case "$opt" in
    p) point="$OPTARG" ;;
    h)
      echo "Usage: $0 [-p CHAR]   # set point char, e.g. -p '*'"
      exit 0
      ;;
  esac
done

# use only the first character (defensive if a string is passed)
point="${point:0:1}"

get_cpu_usage() {
    # read /proc/stat and compute idle/total ticks
    cpu_line=($(grep '^cpu ' /proc/stat))
    idle=${cpu_line[4]}
    total=0
    for val in "${cpu_line[@]:1}"; do total=$((total+val)); done
    echo "$idle $total"
}

cleanup() {
    tput cnorm
    stty echo
    exit
}
trap cleanup INT TERM

# --- draw X axis (idempotent) ---
draw_x_axis() {
    local axis_row=$((CHART_TOP + HEIGHT + 1))  # one row below chart
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

read idle1 total1 < <(get_cpu_usage)
sleep $INTERVAL

clear
echo  "┌────────────────────────────────────┐"
printf "│  CPU Usage Monitor (refresh %.1fs)  │\n" "$INTERVAL"
echo  "│           xfxuezhang.cn            │"
echo  "└────────────────────────────────────┘"

# prefill chart area (HEIGHT+1 rows; bottom is 0% line)
for ((row=HEIGHT; row>=0; row--)); do printf "     │\n"; done
draw_x_axis

x=0
while true; do
    # --- sample CPU ---
    read idle2 total2 < <(get_cpu_usage)
    idle_diff=$((idle2-idle1))
    total_diff=$((total2-total1))
    usage=$((100*(total_diff-idle_diff)/total_diff))
    idle1=$idle2
    total1=$total2

    # track global min/max
    (( usage < min_usage )) && min_usage=$usage
    (( usage > max_usage )) && max_usage=$usage

    # push into history (ring)
    history+=($usage)
    if [ ${#history[@]} -gt $WIDTH ]; then history=("${history[@]:1}"); fi

    # --- dynamic Y range: 0 .. (max+MARGIN) capped at 100 ---
    min=0
    max=$(printf "%s\n" "${history[@]}" | sort -n | tail -1)
    max=$((max+MARGIN)); ((max>100)) && max=100
    scale_den=$((max-min)); ((scale_den<=0)) && scale_den=1

    # --- header info: usage/min-max/load ---
    loadavg=$(awk '{print $1, $2, $3}' /proc/loadavg)

    tput cup "$INFO_TOP" 0
    printf "CPU usage: "
    if (( usage < 50 )); then
        echo -ne "\033[32m${usage}%%\033[0m   "
    elif (( usage < 80 )); then
        echo -ne "\033[33m${usage}%%\033[0m   "
    else
        echo -ne "\033[31m${usage}%%\033[0m   "
    fi
    printf "Min: %d%%  Max: %d%%   " "$min_usage" "$max_usage"

    tput cup $((INFO_TOP + 1)) 0
    printf "Load average: %s   " "$loadavg"

    # --- Y-axis labels (rounded to avoid duplicates) ---
    for ((row=0; row<=HEIGHT; row++)); do
        yval=$(awk -v s=$scale_den -v h=$HEIGHT -v r=$row 'BEGIN {
            v = s*(h-r)/h; printf "%.0f", v
        }')
        tput cup $((CHART_TOP + row)) 0
        printf "%3d%% │" "$yval"
    done

    # map current value to row (0% at bottom chart row)
    y=$(( (usage-min)*HEIGHT/scale_den ))
    rowpos=$((HEIGHT-y))

    # color for the current point
    if (( usage < 50 )); then color="\033[32m"
    elif (( usage < 80 )); then color="\033[33m"
    else color="\033[31m"; fi

    # --- full redraw when Y range changes ---
    if (( max != last_max )); then
        for ((row=0; row<=HEIGHT; row++)); do
            tput cup $((CHART_TOP + row)) $DATA_COL_START
            printf "%-${WIDTH}s" " "
        done
        for ((col=0; col<${#history[@]}; col++)); do
            val=${history[col]}
            ypos=$(( (val-min)*HEIGHT/scale_den ))
            r=$((HEIGHT-ypos))
            if (( val < 50 )); then c="\033[32m"
            elif (( val < 80 )); then c="\033[33m"
            else c="\033[31m"; fi
            tput cup $((CHART_TOP + r)) $((DATA_COL_START + col))
            echo -ne "${c}${point}\033[0m"
        done
        last_max=$max
        x=${#history[@]}; (( x>WIDTH )) && x=$WIDTH
        draw_x_axis
        sleep $INTERVAL
        continue
    fi

    # --- streaming draw ---
    if (( x < WIDTH )); then
        tput cup $((CHART_TOP + rowpos)) $((DATA_COL_START + x))
        echo -ne "${color}${point}\033[0m"
        ((x++))
    else
        # right edge reached -> clear & redraw (keep X-axis)
        for ((row=0; row<=HEIGHT; row++)); do
            tput cup $((CHART_TOP + row)) $DATA_COL_START
            printf "%-${WIDTH}s" " "
        done
        for ((col=0; col<WIDTH; col++)); do
            val=${history[col]}
            ypos=$(( (val-min)*HEIGHT/scale_den ))
            r=$((HEIGHT-ypos))
            if (( val < 50 )); then c="\033[32m"
            elif (( val < 80 )); then c="\033[33m"
            else c="\033[31m"; fi
            tput cup $((CHART_TOP + r)) $((DATA_COL_START + col))
            echo -ne "${c}${point}\033[0m"
        done
    fi

    draw_x_axis
    sleep $INTERVAL
done
