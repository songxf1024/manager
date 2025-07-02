# Linux manager
Linux下的管理工具包，包括sudo权限管理、group管理等。

**工具清单**
- **[tsm_ui.sh](https://github.com/songxf1024/manager?tab=readme-ov-file#tsm)**：临时授予用户sudo权限的管理工具
- **[gum.sh](https://github.com/songxf1024/manager?tab=readme-ov-file#gum)**：用户组的管理工具
- **[scripts](https://github.com/songxf1024/manager?tab=readme-ov-file#scripts)**：一些常用的脚本


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


## scripts
一些常用的脚本
- **custom_check.sh**: 放在 `/etc/profile.d/` 或 `/etc/bash_completion.d/`(推荐) 下，用于统一为所有用户设置一些环境
<p align="center"><img src="https://github.com/user-attachments/assets/f681a1bc-e1ec-475c-b314-d092c4c72874" alt="image" width="600"/></p>


