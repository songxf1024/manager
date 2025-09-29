# Linux manager
Linux下的管理工具包，包括sudo权限管理、group管理等。

**工具清单**
- **[tsm.sh](https://github.com/songxf1024/manager?tab=readme-ov-file#tsm)**：临时授予用户sudo权限的管理工具
- **[gum.sh](https://github.com/songxf1024/manager?tab=readme-ov-file#gum)**：用户组的管理工具
- **[catcpu.sh](https://github.com/songxf1024/manager?tab=readme-ov-file#catcpu)**：监控CPU使用率
- **[scripts](https://github.com/songxf1024/manager?tab=readme-ov-file#scripts)**：一些常用的脚本
- **[thirdparty](https://github.com/songxf1024/manager?tab=readme-ov-file#thirdparty)**：第三方的好用工具


## tsm
Temporary sudo privilege manager. 
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

---

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

## gum
Group user manager. 
用户组的管理工具。

**用法说明**
- 先安装库：`sudo apt install dialog`
- 运行脚本：`sudo bash gum.sh`

<p align="center"><img src="https://github.com/user-attachments/assets/74f8d67a-5c3c-40d1-97e5-134b8f61e276" alt="image" width="600"/></p>

**包含的功能**：
- 搜索用户组：可输入关键字快速定位目标组
- 浏览所有用户组：过滤系统保留组与默认 per-user 组
- 查看组成员详情：显示用户名、UID、所属所有组（自动换行美化显示）
- 添加用户到组：从 /home 目录自动提取本地用户进行选择
- 从组中删除用户：自动更新用户所属的组列表
- 新建用户组
- 更改和恢复`/dev/nvidia*`所属的组：[可用于GPU的权限控制](https://blog.csdn.net/sxf1061700625/article/details/149027382)

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



## scripts
一些常用的脚本
- **custom_check.sh**: 放在 `/etc/profile.d/` 下或创建并放在 `/etc/bash.d/` 下。然后在 `/etc/bash.bashrc/` 的底部中添加引用，用于统一为所有用户设置一些环境：
```bash
# 加载 /etc/bash.d/ 目录下的所有脚本
if [ -d /etc/bash.d ]; then
    for file in /etc/bash.d/*; do
        [ -f "$file" ] && . "$file"
    done
fi
```

<p align="center"><img src="https://github.com/user-attachments/assets/f681a1bc-e1ec-475c-b314-d092c4c72874" alt="image" width="600"/></p>

- **multi_sysmonitor.sh**: 只需在管理机上运行，可记录多台远程服务器的CPU+GPU+网卡状态

<p align="center"><img src="https://github.com/user-attachments/assets/bf2dd7e5-786a-4a42-a39b-f807231ad070" alt="image" width="600"/></p>



## thirdparty
- **系统换源**：[LinuxMirrors](https://github.com/SuperManito/LinuxMirrors)  
> 更换系统软件源: `bash <(curl -sSL https://linuxmirrors.cn/main.sh)`  
> Docker 安装与换源: `bash <(curl -sSL https://linuxmirrors.cn/docker.sh)`  
> Docker 更换镜像加速器: `bash <(curl -sSL https://linuxmirrors.cn/docker.sh) --only-registry`  


