# tsm
Temporary sudo privilege manager. 多功能Ubuntu临时授予用户sudo权限管理工具

设计原理和初衷可以看这里：[【技巧】Ubuntu临时授予用户sudo权限，并在一定时间后自动撤销](https://blog.csdn.net/sxf1061700625/article/details/133270785)

- 简单来说，就是在`/etc/sudoers.d/temp`目录下，为每个要授权的用户，创建用户授权文件。然后通过`at`指令来定时删除该用户授权文件。
- 直接编辑`/etc/sudoers`文件是危险的，而在`/etc/sudoers.d/temp`目录下操作文件是安全的。

**用法说明**
- 先安装库：`sudo apt install dialog`
- 运行脚本：`sudo bash tsm_ui.sh`
![image](https://github.com/user-attachments/assets/48e6c2ba-8387-4b91-bb18-b77f61fcbf45)

**包含的功能**：
- 初始化日志文件和权限目录：
- 新增临时授权用户
- 新增永久授权用户
- 列举已授权用户
- 删除已授权用户
- 更新已授权用户时间(同新增用户)

---

## 打包为可执行文件

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

