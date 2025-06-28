#!/bin/bash
## 放在 /etc/profile.d/ 下，用于统一为所有用户设置一些环境

## 仅对交互式 shell 生效
[[ $- != *i* ]] && return

## 定义颜色
BLACK="\033[0;30m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[0;37m"
RESET="\033[0m"


## 设置别名和颜色
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi


## conda 设置
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/sxf/anaconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/sxf/anaconda3/etc/profile.d/conda.sh" ]; then
        . "/home/sxf/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/sxf/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup


## CUDA 设置
export CUDA_VERSION=12.1
export PATH=/usr/local/cuda-$CUDA_VERSION/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-$CUDA_VERSION/lib64:$LD_LIBRARY_PATH
export CMAKE_CUDA_COMPILER=/usr/local/cuda-$CUDA_VERSION/bin/nvcc
export CUDA_HOME=/usr/local/cuda-$CUDA_VERSION
# export PATH=$PATH:/snap/bin


## 万能解压命令
extract () {
        if [[ -z "$1" ]] ; then
               print -P "usage: \e[1;36mex\e[1;0m < filename >"
               print -P "       Extract the file specified based on the extension"
        elif [[ -f $1 ]] ; then
           case $1 in
             *.tar)       tar xvf  $1    ;;
             *.tbz2)      tar xvf  $1    ;;
             *.tgz)       tar xvf  $1    ;;
             *.tar.bz2)   tar xvf  $1    ;;
             *.tar.gz)    tar xvf  $1    ;;
             *.tar.xz)    tar xvf  $1    ;;
             *.tar.Z)     tar xvf  $1    ;;
             *.bz2)       bunzip2v $1    ;;
             *.rar)       rar x $1       ;;
             *.gz)        gunzip $1      ;;
             *.zip)       unzip $1       ;;
             *.Z)         uncompress $1  ;;
             *.xz)        xz -d $1       ;;
             *.lzo)       lzo -dv $1     ;;
             *.7z)        7z x $1        ;;
             *)           echo "'$1' cannot be extracted via extract()" ;;
           esac
       else
         echo "'$1' is not a valid file"
       fi
    }


echo -e "${GREEN}*******************************************************************************${RESET}"
echo '>> 服务器使用统一规范: https://ismc.yuque.com/afx7fe/icgdxz/gsfghk3h5cmchp2b <<'
echo '>> 初始用户务必更改密码，请勿使用弱密码                                      <<'
echo '>> 软件统一安装在/opt/software下，以免重复安装                               <<'
echo '>> 已自动设置Anaconda、CUDA的路径 (若需覆盖配置可修改你的~/.bashrc)          <<'


## 检查用户名与密码是否相同
username="$(whoami)"
if [ "$username" != "root" ]; then
    echo "$username" | su -s /bin/true -c "true" "$username" >/dev/null 2>&1
    # echo "$username" | su -c "exit" "$username" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "\033[1;31m[安全警告] 您的账号 \"$username\" 的密码与用户名相同！请尽快修改密码。\033[0m" >&2
    fi
fi


## 显示系统信息
HOSTNAME=$(hostname)
UPTIME=$(uptime -p | sed 's/up //')
LOADAVG=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ //')
# 内存
read MEM_TOTAL MEM_USED <<<$(free -m | awk '/Mem:/ {print $2, $3}')
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
# IP
IP_ADDR=$(hostname -I | awk '{print $1}')
# CPU 使用率
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/")
CPU_USAGE=$(awk "BEGIN {printf \"%.0f\", 100 - $CPU_IDLE}")
# 输出系统信息
echo -e "\n${CYAN}当前系统信息${RESET}"
echo -e "---------------------------------------------------"
printf "| %-10s | %-40s |\n" "资源" "使用情况"
printf "|----------|--------------------------------------|\n"
printf "| %-10s | %-36s |\n" "IP地址" "$IP_ADDR"
printf "| %-7s  | %-36s |\n" "CPU"    "$CPU_USAGE%"
printf "| %-10s | %-36s |\n" "内存"   "${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)"
printf "| %-10s | %-36s |\n" "负载情况" "$LOADAVG"
printf "| %-10s | %-36s |\n" "运行时长" "$UPTIME"
echo -e "---------------------------------------------------"
echo -e "${CYAN}磁盘挂载信息${RESET}"
echo -e "-------------------------------------------------"
printf "| %-10s | %-10s | %-10s | %-6s |\n" "Mount" "Used" "Total" "Usage"
df -h -x tmpfs -x devtmpfs | awk 'NR>1 && ($6=="/" || $6=="/mnt/disk") {
    printf "| %-10s | %-10s | %-10s | %-6s |\n", $6, $3, $2, $5
}'
echo -e "-------------------------------------------------"




echo -e "${GREEN}*******************************************************************************${RESET}\n"
