title: rpm或yum安装软件提示error-rpmts_HdrFromFdno-key-ID-BAD
date: 2015-03-02 01:21:25
updated: 2015-03-02 00:46:23
tags: [linux, 软件包,troubleshooting]
categories: Linux
---

# 问题 #
在 CentOS 6.4 x86_64 上无论通过yum或rpm安装软件时，出现以下错误：
```
yum install glibc-devel
...
error: rpmts_HdrFromFdno: Header V3 RSA/SHA1 Signature, key ID c105b9de: BAD
...
Problem opening package *.el6.x86_64.rpm
```
## 分析 ##
`rpm -ivh`单独去安装软件也提示上面的错误。`rpm -qa` 无法列出系统中安装过的软件包，但许多库文件和软件命令是存在的。也尝试过`rpm --rebuilddb`来重建数据库，但情况依然没有得到改善（centos官网说千万不要在系统broken的情况下rebuilddb，不然有可能变成destroy）

由上面的推断可知问题出现在rpm这个软件包管理工具本身，但此时又无法通过rpm来重新安装自己，所以只能找到具体是什么因素导致的。好在官网的这篇较新的文章正好就是解决该BUG：[WARNING: nss-softokn-3.14.3-19.el6_6 updates may be broken](https://www.centos.org/forums/viewtopic.php?p=214791&f=13#p214791) ：

大致是说当你使用`yum update`去更新你的系统时，`nss-softokn`、`nss-softokn-freebl`和其它软件一起都得到更新，所以不会有问题。但如果单独去更新某一个软件，如`yum update nss-softokn`或`yum install <software>`引起它的依赖包也升级，使得`nss-softokn`和`nss-softokn-freebl`版本不匹配，就会导致 rpm/yum 全面停止工作，表现就是上面的`key .. BAD`。

## 解决 ##
解决起来也很方便，首先你可以通过`cat /var/log/messages|grep nss`看到`nss-softokn-freebl`的版本：
```
# cat /var/log/messages|grep nss-softokn
Mar  2 09:56:18 poprod yum[14920]: Updated: nss-softokn-3.14.3-19.el6_6.x86_64
Mar  2 14:43:29 poprod yum[33040]: Installed: nss-softokn-freebl-3.14.3-19.el6_6.x86_64
Mar  2 14:44:14 poprod yum[33047]: Installed: nss-softokn-freebl-3.14.3-19.el6_6.x86_64
...
```

下载 `nss-softokn-freebl-3.14.3-19.el6_6.x86_64.rpm`：
```
wget ftp://195.220.108.108/linux/centos/6.6/updates/x86_64/Packages/nss-softokn-freebl-3.14.3-19.el6_6.x86_64.rpm
```

解压rpm：
```
rpm2cpio nss-softokn-freebl-3.14.3-19.el6_6.x86_64.rpm | cpio -idmv
```

复制 libfreeblpriv3.* 覆盖旧的库文件：
```
cp ./lib64/libfreeblpriv3.* /lib64/
cp ./lib64/libfreebl3* /lib64/
```

试一下 `yum install gcc` 看能否正常工作，如果不行，继续下一步：
```
wget http://mirror.centos.org/centos/6/os/x86_64/Packages/yum-3.2.29-60.el6.centos.noarch.rpm
rpm -ivh --nodeps yum-3.2.29-60.el6.centos.noarch.rpm
```

应该就好了：
```
rpm -qa
yum install glibc-devel
```
**参考**

- http://unix.stackexchange.com/questions/179344/big-trouble-rpm-empty-db-install-v3-rsa-sha1-signature-key-bad-yumrepo-erro
- https://www.centos.org/forums/viewtopic.php?p=214791&f=13#p215140
- http://blog.chinaunix.net/uid-26085226-id-4545167.html
