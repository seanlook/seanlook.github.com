title: CentOS 6 服务器安全配置指南（通用）
date: 2014-09-07 01:21:25
updated: 2014-09-07-12 00:46:23
tags: [安全,ssh]
categories: Linux
---

Linux是一个开放式系统，可以在网络上找到许多现成的程序和工具，这既方便了用户，也方便了黑客，因为他们也能很容易地找到程序和工具来潜入Linux系统，或者盗取Linux系统上的重要信息。不过，只要我们仔细地设定Linux的各种系统功能，并且加上必要的安全措施，就能让黑客们无机可乘。一般来说，对Linux系统的安全设定包括取消不必要的服务、限制远程存取、隐藏重要资料、修补安全漏洞、采用安全工具以及经常性的安全检查等。

本文是可参考的实际操作，不涉及如IP欺骗这样的原理，而且安全问题也不算几行命令就能预防的，这里只是linux系统上基本的安全加固方法，后续有新的内容再添加进来。

注：所有文件在修改之前都要进行备份如 `cp /etc/passwd{,.dist}`

## 1. 禁用不使用的用户 ##

注意：不建议直接删除，当你需要某个用户时，自己重新添加会很麻烦。也可以`usermod -L`或`passwd -l user`锁定。

`cp /etc/passwd{,.bak}`  修改之前先备份
`vi /etc/passwd` 编辑用户，在前面加上#注释掉此行

<!-- more -->

注释的用户名：

    # cat /etc/passwd|grep ^#
    #adm:x:3:4:adm:/var/adm:/sbin/nologin
    #lp:x:4:7:lp:/var/spool/lpd:/sbin/nologin
    #shutdown:x:6:0:shutdown:/sbin:/sbin/shutdown
    #halt:x:7:0:halt:/sbin:/sbin/halt
    #uucp:x:10:14:uucp:/var/spool/uucp:/sbin/nologin
    #operator:x:11:0:operator:/root:/sbin/nologin
    #games:x:12:100:games:/usr/games:/sbin/nologin
    #gopher:x:13:30:gopher:/var/gopher:/sbin/nologin
    #ftp:x:14:50:FTP User:/var/ftp:/sbin/nologin
    #nfsnobody:x:65534:65534:Anonymous NFS User:/var/lib/nfs:/sbin/nologin
    #postfix:x:89:89::/var/spool/postfix:/sbin/nologin

注释的组：

    # cat /etc/group|grep ^#
    #adm:x:4:adm,daemon
    #lp:x:7:daemon
    #uucp:x:14:
    #games:x:20:
    #gopher:x:30:
    #video:x:39:
    #dip:x:40:
    #ftp:x:50:
    #audio:x:63:
    #floppy:x:19:
    #postfix:x:89:

## 2. 关闭不使用的服务 ##

    # chkconfig --list |grep '3:on'

邮件服务，使用公司邮件服务器：

    service postfix stop
    chkconfig postfix --level 2345 off

通用unix打印服务，对服务器无用：

    service cups stop
    chkconfig cups --level 2345 off

调节cpu速度用来省电，常用在Laptop上：

    service cpuspeed stop
    chkconfig cpuspeed --level 2345 off

蓝牙无线通讯，对服务器无用：

    service bluetooth stop
    chkconfig bluetooth --level 2345 off

系统安装后初始设定，第一次启动系统后就没用了：

    service firstboot stop
    chkconfig firstboot --level 2345 off

关闭nfs服务及客户端：

    service netfs stop
    chkconfig netfs --level 2345 off
    service nfslock stop
    chkconfig nfslock --level 2345 off

如果要恢复某一个服务，可以执行下面操作：
`service acpid start && chkconfig acpid on`
也可以使用`setup`工具来设置

## 3. 禁用IPV6 ##
IPv6是为了解决IPv4地址耗尽的问题，但我们的服务器一般用不到它，反而禁用IPv6不仅仅会加快网络，还会有助于减少管理开销和提高安全级别。以下几步在CentOS上完全禁用ipv6。

禁止加载IPv6模块：
让系统不加载ipv6相关模块，这需要修改modprobe相关设定文件，为了管理方便，我们新建设定文件`/etc/modprobe.d/ipv6off.conf`，内容如下

    alias net-pf-10 off
    options ipv6 disable=1

禁用基于IPv6网络，使之不会被触发启动：

    # vi /etc/sysconfig/network
    NETWORKING_IPV6=no

禁用网卡IPv6设置，使之仅在IPv4模式下运行：

    # vi /etc/sysconfig/network-scripts/ifcfg-eth0
    IPV6INIT=no
    IPV6_AUTOCONF=no

关闭ip6tables：

    # chkconfig ip6tables off

重启系统，验证是否生效：

    # lsmod | grep ipv6
    # ifconfig | grep -i inet6

如果没有任何输出就说明IPv6模块已被禁用，否则被启用。

## 4. iptables规则 ##
启用linux防火墙来禁止非法程序访问。使用iptable的规则来过滤入站、出站和转发的包。我们可以针对来源和目的地址进行特定udp/tcp端口的准许和拒绝访问。

关于防火墙的设置规则请参考博客文章 [iptables设置实例](http://seanlook.com/2014/02/26/iptables-example/)。

## 5. SSH安全 ##
如果有可能，第一件事就是修改ssh的默认端口22，改成如20002这样的较大端口会大幅提高安全系数，降低ssh破解登录的可能性。

创建具备辨识度的应用用户如crm以及系统管理用户sysmgr

    # useradd crm -d /apps/crm
    # passwd crm

    # useradd sysmgr
    # passwd sysmgr

### 5.1 只允许wheel用户组的用户su切换 ###

    # usermod -G wheel sysmgr

    # vi /etc/pam.d/su
    # Uncomment the following line to require a user to be in the "wheel" group.
    auth            required        pam_wheel.so use_uid

其他用户切换root，即使输对密码也会提示 su: incorrect password

### 5.2 登录超时 ###
用户在线5分钟无操作则超时断开连接，在`/etc/profile`中添加：

    export TMOUT=300
    readonly TMOUT

### 5.3 禁止root直接远程登录 ###

    # vi /etc/ssh/sshd_config
    PermitRootLogin no

### 5.4 限制登录失败次数并锁定 ###

在`/etc/pam.d/login`后添加

    auth required pam_tally2.so deny=6 unlock_time=180 even_deny_root root_unlock_time=180

登录失败5次锁定180秒，根据需要设置是否包括root。

### 5.5 登录IP限制 ###

（由于要与某一固定IP或IP段绑定，暂未设置）
更严格的限制是在sshd_config中定死允许ssh的用户和来源ip：

    ## allowed ssh users sysmgr
    AllowUsers sysmgr@172.29.73.*

或者使用tcpwrapper:

    vi /etc/hosts.deny
    sshd:all
    vi /etc/hosts.allow
    sshd:172.29.73.23
    sshd:172.29.73.

## 6. 配置只能使用密钥文件登录 ##

使用密钥文件代替普通的简单密码认证也会极大的提高安全性：

    [dir@username ~]$ ssh-keygen -t rsa -b 2048
    Generating public/private rsa key pair.
    Enter file in which to save the key (/root/.ssh/id_rsa):   //默认路径，回车
    Enter passphrase (empty for no passphrase): 	//输入你的密钥短语，登录时使用
    Enter same passphrase again: 
    Your identification has been saved in /root/.ssh/id_rsa.
    Your public key has been saved in /root/.ssh/id_rsa.pub.
    The key fingerprint is:
    3e:fd:fc:e5:d3:22:86:8e:2c:4b:a7:3d:92:18:9f:64 root@ibpak.tp-link.net
    The key's randomart image is:
    +--[ RSA 2048]----+
    |                 |
    …
    |      o++o..oo..o|
    +-----------------+

将公钥重命名为`authorized_key`：

    $ mv ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys
    $ chmod 600 ~/.ssh/authorized_keys

下载私钥文件 id_rsa 到本地（为了更加容易识别，可重命名为`hostname_username_id_rsa`），保存到安全的地方。以后 username 用户登录这台主机就必须使用这个私钥，配合密码短语来登录（不再使用 username 用户自身的密码）

另外还要修改`/etc/ssh/sshd_config`文件
打开注释

    RSAAuthentication yes
    PubkeyAuthentication yes
    AuthorizedKeysFile      .ssh/authorized_keys

我们要求 username 用户（可以切换到其他用户，特别是root）必须使用ssh密钥文件登录，而其他普通用户可以直接密码登录。因此还需在sshd_config文件最后加入：
    
    Match User itsection
            PasswordAuthentication no

重启sshd服务

    # service sshd restart

另外提醒一句，这对公钥和私钥一定要单独保存在另外的机器上，服务器上丢失公钥或连接端丢失私钥（或密钥短语），可能导致再也无法登陆服务器获得root权限！

## 7. 减少history命令记录 ##

执行过的历史命令记录越多，从一定程度上讲会给维护带来简便，但同样会伴随安全问题

    vi /etc/profile

找到 `HISTSIZE=1000` 改为 `HISTSIZE=50`。

或每次退出时清理history，`history -c`  


## 8. 增强特殊文件权限 ##
给下面的文件加上不可更改属性，从而防止非授权用户获得权限

    chattr +i /etc/passwd
    chattr +i /etc/shadow
    chattr +i /etc/group
    chattr +i /etc/gshadow
    chattr +i /etc/services #给系统服务端口列表文件加锁，防止未经许可的删除或添加服务
    chattr +i /etc/pam.d/su
    chattr +i /etc/ssh/sshd_config

显示文件的属性

    lsattr /etc/passwd /etc/shadow /etc/services /etc/ssh/sshd_config

注意：执行以上 chattr 权限修改之后，就无法添加删除用户了。

如果再要添加删除用户，需要先取消上面的设置，等用户添加删除完成之后，再执行上面的操作，例如取消只读权限`chattr -i /etc/passwd`。（记得重新设置只读）


## 9. 防止一般网络攻击 ##
网络攻击不是几行设置就能避免的，以下都只是些简单的将可能性降到最低，增大攻击的难度但并不能完全阻止。

### 9.1 禁ping ###
阻止ping如果没人能ping通您的系统，安全性自然增加了，可以有效的防止ping洪水。为此，可以在`/etc/rc.d/rc.local`文件中增加如下一行：

    # echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all

或使用iptable禁ping：
    
    iptables -A INPUT -p icmp --icmp-type 0 -s 0/0 -j DROP
    
    不允许ping其他主机：
    iptables -A OUTPUT -p icmp --icmp-type 8 -j DROP

### 9.2. 防止IP欺骗 ###
编辑/etc/host.conf文件并增加如下几行来防止IP欺骗攻击。

    order hosts,bind    #名称解释顺序
    multi on           #允许主机拥有多个IP地址
    nospoof on         #禁止IP地址欺骗

### 9.3 防止DoS攻击 ###
对系统所有的用户设置资源限制可以防止DoS类型攻击，如最大进程数和内存使用数量等。
可以在`/etc/security/limits.conf`中添加如下几行：

    *    soft    core    0
    *    soft    nproc   2048
    *    hard    nproc   16384
    *    soft    nofile 1024
    *    hard    nofile  65536

core 0 表示禁止创建core文件；nproc 128 把最多的进程数限制到20；nofile 64 表示把一个用户同时打开的最大文件数限制为64；* 表示登录到系统的所有用户，不包括root

然后必须编辑`/etc/pam.d/login`文件检查下面一行是否存在。

    session    required     pam_limits.so

`limits.conf`参数的值需要根据具体情况调整。

## 10. 修复已知安全漏洞 ##
在linux上偶尔会爆出毁灭级的漏洞，如[udev](http://www.ha97.com/1002.html)、[heartbleed](https://access.redhat.com/solutions/781793)、[shellshock](http://linux.cn/article-3902-1.html)、[ghost](http://www.36kr.com/p/219344.html)等，如果服务器暴露在外网，一定及时修复。

## 11. 定期做日志安全检查 ##
将日志移动到专用的日志服务器里，这可避免入侵者轻易的改动本地日志。下面是常见linux的默认日志文件及其用处：

- `/var/log/message` – 记录系统日志或当前活动日志。
- `/var/log/auth.log` – 身份认证日志。
- `/var/log/cron`   – Crond 日志 (cron 任务).
- `/var/log/maillog` – 邮件服务器日志。
- `/var/log/secure` – 认证日志。
- `/var/log/wtmp`	历史登录、注销、启动、停机日志和，lastb命令可以查看登录失败的用户
- `/var/run/utmp`	当前登录的用户信息日志，w、who命令的信息便来源与此
- `/var/log/yum.log` Yum 日志。

参考 [深度解析CentOS通过日志反查入侵](http://linux.it.net.cn/CentOS/safe/2014/0429/985.html)。

### 11.1 安装logwatch ###

Logwatch是使用 Perl 开发的一个日志分析工具。能够对Linux 的日志文件进行分析，并自动发送mail给相关处理人员，可定制需求。

Logwatch的mail功能是借助宿主系统自带的 mail server 发邮件的，所以系统需安装mail server , 如sendmail,postfix,Qmail等

安装和配置方法见博文 [linux日志监控logwatch](http://seanlook.com/2014/08/23/linux-logwatch-usage/)。

## 12. web服务器安全 ##

像apache或tomcat这样的服务端程序在配置时，如果有安全问题存在可以查阅文档进行安全加固。日后有时间再补充到新的文章。

**参考**

- [Top 20 OpenSSH Server Best Security Practices](http://www.cyberciti.biz/tips/linux-unix-bsd-openssh-server-best-practices.html)
