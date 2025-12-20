# Linux manager
Linux下的管理工具包，包括sudo权限管理、group管理等。

**工具清单**
- **[tsm.sh](https://github.com/songxf1024/manager?tab=readme-ov-file#tsm)**：临时授予用户sudo权限的管理工具
- **[gum.sh](https://github.com/songxf1024/manager?tab=readme-ov-file#gum)**：GPU/用户组的管理工具
- **[asm.sh](https://github.com/songxf1024/manager?tab=readme-ov-file#asm)**：开机自启动管理工具
- **[catcpu.sh](https://github.com/songxf1024/manager?tab=readme-ov-file#catcpu)**：监控CPU使用率
- **[scripts](https://github.com/songxf1024/manager?tab=readme-ov-file#scripts)**：一些常用的脚本
- **[thirdparty](https://github.com/songxf1024/manager?tab=readme-ov-file#thirdparty)**：第三方的好用工具


## tsm
**T**emporary **S**udo **M**anager. 
临时授予用户sudo权限的管理工具。

设计原理和初衷可以看这里：[【技巧】Ubuntu临时授予用户sudo权限，并在一定时间后自动撤销](https://blog.csdn.net/sxf1061700625/article/details/133270785)

- 简单来说，就是在`/etc/sudoers.d/temp`目录下，为每个要授权的用户，创建用户授权文件。然后通过`at`指令来定时删除该用户授权文件。
- 直接编辑`/etc/sudoers`文件是危险的，而在`/etc/sudoers.d/temp`目录下操作文件是安全的。

**用法说明**
- 先安装库：`sudo apt install dialog`
- 运行脚本：`sudo bash tsm_ui.sh`

<p align="center"><img src="https://github.com/user-attachments/assets/48e6c2ba-8387-4b91-bb18-b77f61fcbf45" alt="image" width="600"/></p>


**包含的功能**：
- 初始化日志文件和权限目录：
- 新增临时授权用户
- 新增永久授权用户
- 列举已授权用户
- 删除已授权用户
- 更新已授权用户时间(同新增用户)

**打包为可执行文件**
```bash
sudo apt install shc -y
shc -f tsm_ui.sh -o tsm
```
> 如果报错 invalid first line in script: #!/bin/bash，则需要先使用dos2unix：
> ```bash
> sudo apt install dos2unix -y
> dos2unix tsm_ui.sh
> ```

```bash
sudo ./tsm
```

---

## gum
**G**PU/Group **U**ser **M**anager. 
GPU/用户组的管理工具。

<p align="center"><img src="https://github.com/user-attachments/assets/ff99a163-4563-40bc-8194-67bf13a53e12" alt="image" width="600"/></p>

**用法说明**
- 先安装库：`sudo apt install dialog`
- 运行脚本：`sudo bash gum.sh`

**包含的功能**：
- 搜索用户组：可输入关键字快速定位目标组
- 浏览所有用户组：过滤系统保留组与默认 per-user 组
- 查看组成员详情：显示用户名、UID、所属所有组（自动换行美化显示）
- 添加用户到组：从 /home 目录自动提取本地用户进行选择
- 从组中删除用户：自动更新用户所属的组列表
- 新建用户组
- 更改和恢复`/dev/nvidia*`所属的组：[可用于GPU的权限控制](https://blog.csdn.net/sxf1061700625/article/details/149027382)
- 分配GPU所述的组
- 设置GPU的性能模式

---

## asm
**A**uto **S**tart **M**anager.  
开机自启动管理工具，用于统一管理 Linux 下的开机自启命令。

<p align="center"><img src="https://github.com/user-attachments/assets/9d43a156-2957-44e1-94f4-fce7bc7eb789" alt="image" width="400"/></p>

**设计原理**

- 使用一个统一的自启命令文件：`/etc/custom_autostart_cmds.sh`
- 配套一个 `systemd` 服务：`custom-autostart.service`
- 所有要开机执行的命令都写入 `custom_autostart_cmds.sh`，由 systemd 在系统启动阶段一次性执行
- 通过交互式菜单管理命令列表与服务状态，并提供“一键卸载环境”功能，方便回滚

**用法说明**
- 直接运行：  
```bash
  sudo bash asm.sh
```

**包含的功能**：

- 列出自启动命令
  - 显示当前写入 /etc/custom_autostart_cmds.sh 中的所有有效命令
  - 自动跳过注释与空行，并带编号显示
- 新增自启动命令
  - 交互式输入一条要在开机阶段执行的命令
  - 自动追加到 /etc/custom_autostart_cmds.sh 末尾
  - 依赖初始化环境（命令文件 + systemd 服务），否则会提示无法添加
- 删除自启动命令
  - 先按编号展示当前命令列表
  - 输入编号即可删除对应命令行（对原文件做 sed 精确删除）
- 查看 systemd 服务状态
  - 调用 systemctl status custom-autostart.service
  - 用于确认服务是否加载、启用、最近一次执行状态等
- 卸载当前脚本环境
  - 禁用并删除 custom-autostart.service
  - 删除 /etc/custom_autostart_cmds.sh
  - 触发 systemctl daemon-reload
  - 不会删除 asm.sh 脚本本身，如不再需要可手动删除

---

## catcpu
曲线图方式显示CPU的使用率。

**用法说明**
- 直接运行：`bash catcpu.sh`
- 自定义绘图点：`bash catcpu.sh -p "*"`

<p align="center"><img src="https://github.com/user-attachments/assets/69888704-50d8-4b70-bce3-b269b0ac5319" alt="image" width="600"/></p>

**包含的功能**：
- 实时 CPU 使用率采集（从 /proc/stat 读取）
- 动态 ASCII 曲线图展示，带彩色（绿/黄/红）标记
- Y 轴动态缩放，刻度自动四舍五入避免重复
- 显示 CPU usage、历史最小/最大 usage、load average
- 支持通过 `-p` 参数自定义绘图点符号

## catgpu
曲线图方式显示GPU的使用率。

**用法说明**
- 直接运行：`bash catgpu.sh -g 0`

<p align="center"><img src="https://github.com/user-attachments/assets/7f2f5d27-b8fa-4689-bdac-685ec26e8a18" alt="image" width="600"/></p>

---

## scripts
一些常用的脚本
- **custom_check.sh**: 放在 `/etc/profile.d/` 下或创建并放在 `/etc/bash.d/` 下。然后在 `/etc/bash.bashrc` 的底部中添加引用，用于统一为所有用户设置一些环境：

```bash
# 1. 创建目录 
sudo mkdir /etc/bash.d/
```

```bash
# 2. 写入或者移入脚本
sudo vim /etc/bash.d/custom_check.sh
```

```bash
# 3. 添加引用
sudo vim /etc/bash.bashrc
```

> 在 `/etc/bash.bashrc` 的底部中添加：
> ```bash
> # 加载 /etc/bash.d/ 目录下的所有脚本
> if [ -d /etc/bash.d ]; then
>     for file in /etc/bash.d/*; do
>         [ -f "$file" ] && . "$file"
>     done
> fi
> ```

<p align="center"><img src="https://github.com/user-attachments/assets/f681a1bc-e1ec-475c-b314-d092c4c72874" alt="image" width="600"/></p>

- **multi_sysmonitor.sh**: 只需在管理机上运行，可记录多台远程服务器的CPU+GPU+网卡状态

<p align="center"><img src="https://github.com/user-attachments/assets/bf2dd7e5-786a-4a42-a39b-f807231ad070" alt="image" width="600"/></p>

---

## thirdparty
- **系统换源**：[LinuxMirrors](https://github.com/SuperManito/LinuxMirrors)  
> 更换系统软件源: `bash <(curl -sSL https://linuxmirrors.cn/main.sh)`  
> Docker 安装与换源: `bash <(curl -sSL https://linuxmirrors.cn/docker.sh)`  
> Docker 更换镜像加速器: `bash <(curl -sSL https://linuxmirrors.cn/docker.sh) --only-registry`  


