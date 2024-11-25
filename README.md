# tsm
Temporary sudo privilege manager. 多功能Ubuntu临时授予用户sudo权限管理工具

设计原理和初衷可以看这里：[【技巧】Ubuntu临时授予用户sudo权限，并在一定时间后自动撤销](https://blog.csdn.net/sxf1061700625/article/details/133270785)

- 简单来说，就是在`/etc/sudoers.d/temp`目录下，为每个要授权的用户，创建用户授权文件。然后通过`at`指令来定时删除该用户授权文件。
- 直接编辑`/etc/sudoers`文件是危险的，而在`/etc/sudoers.d/temp`目录下操作文件是安全的。

**用法说明：**

> 如果要使用ui版，需要先安装库：
> `sudo apt install dialog`


```bash
sudo bash tsm.sh
# 或 sudo bash tsm_ui.sh
```

![image](https://github.com/songxf1024/tsm/assets/111047002/95847695-4e67-4017-b4de-7e434cea3696)


**初始化日志文件和权限目录：**

```bash
sudo bash tsm.sh init
```

![image](https://github.com/songxf1024/tsm/assets/111047002/593e9f89-7700-448a-8d28-f46e7e7894c0)


**新增临时用户：**

```bash
sudo bash tsm.sh add <username> <time>
```

![image](https://github.com/songxf1024/tsm/assets/111047002/3f2471cd-8cc2-4895-a8cb-32d090736c02)


**新增临时用户(检查用户有效性)：**

```bash
sudo bash tsm.sh add <username> <time> -c
```

![image](https://github.com/songxf1024/tsm/assets/111047002/3f79f1d6-4428-409f-a75e-a4c5dd9d0250)


**新增永久用户(伪永久，876000小时约100+年)：**

```bash
sudo bash tsm.sh add <username> -p
```

![image](https://github.com/songxf1024/tsm/assets/111047002/90198291-bef5-4904-b239-db9296a63b0c)


**列举已授权用户：**

```bash
sudo bash tsm.sh list
```

![image](https://github.com/songxf1024/tsm/assets/111047002/5a47bd03-48a2-43cf-b5b7-bff5abb1774e)


**删除已授权用户：**

```bash
sudo bash tsm.sh del test
```

![image](https://github.com/songxf1024/tsm/assets/111047002/3c86ad43-47b1-4b6f-bf37-5ac5878cd486)

![image](https://github.com/songxf1024/tsm/assets/111047002/0461a3aa-6e5c-4c97-be63-fe462d841bb3)


**更新已授权用户时间(同新增用户)：**

```bash
sudo bash tsm.sh add <username> <time>
```

![image](https://github.com/songxf1024/tsm/assets/111047002/fa957c95-d0a6-4cc2-a179-ef6d8091b336)

![image](https://github.com/songxf1024/tsm/assets/111047002/576d47cc-ca65-47f8-a126-0044953add9a)

---

打包为可执行文件：

```bash
shc -f tsm.sh -o tsm
```

```bash
sudo ./tsm
```

