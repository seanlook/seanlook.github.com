---
title: Linux进阶培训-tplink
date: 2014-10-06 16:32:49
tags: [linux,磁盘,内存,网络,进程管理]
categories: 
- Linux
updated: 2014-10-06 16:32:49
---

本文没啥实际内容，是给新人做linux培训的第二课进阶篇，主要着眼于体系，把一些工具混个眼熟。

![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-01.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-02.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-03.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-04.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-05.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-06.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-07.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-08.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-09.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-10.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-11.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-12.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-13.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-14.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-15.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-16.PNG)
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/linux-level2-17.PNG)



## 目录
- Linux磁盘管理(进阶)
- Linux内存管理
- Linux进程管理(进阶)
- Linux网络管理(进阶)
- Linux系统状态监控与调优
- 常见服务
- Linux安全策略
- 其他

## Linux磁盘管理（进阶）
- ext4文件系统格式
 - Inode、block、superblock、MBR
 - VFS
- LVM
 - pv、lv、vg
 - lvdisplay、lvextend、vgdisplay、pvcreate…
- RAID
 - raid0、raid1、raid5、raid10
 - r/w速度、磁盘利用率、安全性的权衡
- 磁盘IO性能
  - dd、iostat、iotop
  - I/O等待

## Linux内存管里（基础）
- 物理内存与虚拟内存
 - Swap space，分页存取
- buffer与cache区分
- 内存监控命令
 - free、vmstat
- /proc文件系统

<!-- more -->

## Linux进程管理（进阶）
- 进程与线程
 - 进程优先级
- 进程监控命令
 - pidstat、lsof
 - strace（系统调用跟踪）
- 后台进程
 - Ctrl+z、jobs、bg、fg、&、nohup
 - screen

## Linux的网络管理
- 一些概念
 - 防火墙
 - 路由/网关
 - 子网掩码
 - 网络接口（参数）
 - MAC

- TCP/IP协议
- 应用层协议

Linux网络管理
iptables


## Linux网络管理
- 主机网络流量监控
 - iftop、iptraf、sar
- tcpdump抓包
 - wireshark数据包分析工具

##Linux网络管理
- iproute2
 - ip、ss

## Linux系统状态监控与调优
- 一些工具
 - sar、sysstat
 - perf、logwatch
- 一些配置文件
 - sysctl.conf
 - limits.conf

## Linux安全策略
- 禁止root直接登录
- 锁定不使用的账号
- 关闭ipv6
- 启用防火墙
- 定期检查日志
- …

## Linux常见服务
- tcp_wrappers
- SSH
- postfix
- FTP
- NFS/Samba
- DNS
- Apache/nginx
- …

## Linux其他
- Linux开机过程分析
- pam模块解读lsmod
- 编译make、ldd、ldconfig、gcc、gdb
- ACL
- Linux集群
- 内核模块
- linux编程
- …


---

本文链接地址：http://xgknight.com/2014/10/06/linux-level2/

---
