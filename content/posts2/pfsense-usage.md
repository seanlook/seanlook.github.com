---
title: 图解pfSense软路由系统的使用（NAT功能）
date: 2015-04-23 15:21:25
updated: 2015-04-24 00:46:23
tags: [pfsense,vmware]
categories: Linux
---

pfsense是一款开源的路由和防火墙产品，它基于freebsd系统定制和开发。pfsene拥有友好的web的配置界面，且具有伸缩性强又不失强大性能，在众多开源网络防火墙中属于佼佼者。

2004年，pfsense作为m0n0wall项目（基于freebsd内核的嵌入式软防火墙）的分支项目启动，增加了许多m0n0wall没有的功能(pfSense的官方网站称它为the better m0n0wall).pfSense除了包含宽带路由器的基本功能外,还有以下的特点:

- 基于稳定可靠的FreeBSD操作系统,能适应全天候运行的要求
- 具有用户认证功能,使用Web网页的认证方式,配合RADIUS可以实现记费功能
- 完善的防火墙、流量控制和数据包功能,保证了网络的安全,稳定和高速运行
- 支持多条WAN线路和负载均衡功能,可大幅度提高网络出口带宽,在带宽拥塞时自动分配负载
- 内置了IPsec 和PPTP VPN功能,实现不同分支机构的远程互联或远程用户安全地访问内部网
- 支持802.1Q VLAN标准,可以通过软件模拟的方式使得普通网卡能识别802.1Q的标记,同时为多个VLAN的用户提供服务
- 支持使用额外的软件包来扩展pfSense功能,为用户提供更多的功能(如FTP和透明代理).
- 详细的日志功能,方便用户对网络出现的事件分析,统计和处理
- 使用Web管理界面进行配置(支持SSL),支持远程管理和软件版本自动在线升级

本文简单介绍pfSense的安装及配置过程，完成一个基本的路由器该有的功能，如访问局外网、设置防火墙规则、配置端口映射。这里演示在ESXi虚拟服务器上，解决IP不足的问题。

## 创建虚拟机 ##
首先去 https://www.pfsense.org/download/ 下载稳定版本的pfSense，如pfSense-LiveCD-2.2.2-RELEASE-amd64.iso.gz（网上看到有人提到这个版本不稳定，我在使用中偶尔也发现突然很慢，建议2.1.5）。在vSphere上创建虚拟机的过程省略，取名01_pfSense，创建虚拟机操作系统时选择“其他 -> FreeBSD 64位”，单CPU,512Mb内存，4G硬盘。将下载的系统解压成iso后挂载到CD/DVD，并“打开电源时连接”。
下图是网卡情况：
为pfSense分配两个网卡，分别是可以连接公司内网的172.29.88.1/24网段的vSphere_Admin端口组，和IP范围是172.30.31.1/24的内部局域网端口组VM Local。
![pfsense-vsphere0.png][0]

记录下Mac地址
外网接口：00:0c:29:36:b6:c2
内网接口：00:0c:29:36:b6:cc

## 安装pfsense ##
启动电源后出现欢迎界面，选择`1.Boot pfSense [default]`，或等待几秒钟自动选择，进入如下界面：
![pfsense-vsphere1.png][1]

输入I，回车，然后是一个蓝屏，开始安装。

<!-- more -->

也可以什么都不用管，系统会一直启动从CD启动得到一个完整的pfSense系统，因为没有安装所以在屏幕下方会有一个选项`99） Install pfSense to a hard drive, etc.`，输入99同样会进入下面的安装操作系统的过程。
![pfsense-vsphere2.png][2]

一路保存默认：`< Accept these Settings >` → `< Quick/Easy InStall >` → `erase all content < OK >` → `< Standard Kernel >` → `< Reboot >`。

重启后安装完成，断开CD介质。
![pfsense-vsphere3.png][3]
详见见官网文档 https://doc.pfsense.org/index.php/Installing_pfSense 。

下面开始配置内外网接口。
## 分配接口 ##
从上图可以看到系统默认将em0接口当做WAN（外网），em1当做LAN（内部局域网），但我们不确定em0就是在创建虚拟机时分配的外网接口，需要根据MAC地址判断。

选择`1) Assgin Interfaces`，回车
首先询问你是否设置VLAN（用于划分多个子局域网网），Do you want to set up VLANs now [y|n]?，否n：
![pfsense-vsphere4.png][4]
![pfsense-vsphere4-1.png][41]

## 分配IP ##
选择`2) Set interfce(s) IP address`：
![pfsense-vsphere5.png][5]
先配置WAN的IP，禁用DHCP,配置地址172.29.88.230/24，网关172.29.88.1，禁用IPV6：
![pfsense-vsphere5-1.png][51]
再配置LAN，172.30.31.1/24，不配置网关：
![pfsense-vsphere5-2.png][52]
完成后会提示可以在浏览器打开`http://172.30.31.1/`，通过webConfigurator来操作pfSense。

已打通两端网络：
```
sean@seanubt:~$ ssh admin@172.30.31.1 22
Password for admin@pfSense.domain:
*** Welcome to pfSense 2.2.2-RELEASE-pfSense (amd64) on pfSense ***

 WAN (wan)       -> em0        -> v4: 172.29.88.230/24
 LAN (lan)       -> em1        -> v4: 172.30.31.1/24
 0) Logout (SSH only)                  9) pfTop
 1) Assign Interfaces                 10) Filter Logs
 2) Set interface(s) IP address       11) Restart webConfigurator
 3) Reset webConfigurator password    12) pfSense Developer Shell
 4) Reset to factory defaults         13) Upgrade from console
 5) Reboot system                     14) Disable Secure Shell (sshd)
 6) Halt system                       15) Restore recent configuration
 7) Ping host                         16) Restart PHP-FPM
 8) Shell
  

7


Enter a host name or IP address: 172.29.88.56

PING 172.29.88.56 (172.29.88.56): 56 data bytes
64 bytes from 172.29.88.56: icmp_seq=0 ttl=64 time=1.406 ms
64 bytes from 172.29.88.56: icmp_seq=1 ttl=64 time=1.215 ms
64 bytes from 172.29.88.56: icmp_seq=2 ttl=64 time=0.480 ms

--- 172.29.88.56 ping statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 0.480/1.034/1.406/0.399 ms

Press ENTER to continue.

*** Welcome to pfSense 2.2.2-RELEASE-pfSense (amd64) on pfSense ***

 WAN (wan)       -> em0        -> v4: 172.29.88.230/24
 LAN (lan)       -> em1        -> v4: 172.30.31.1/24
 0) Logout (SSH only)                  9) pfTop
 1) Assign Interfaces                 10) Filter Logs
 2) Set interface(s) IP address       11) Restart webConfigurator
 3) Reset webConfigurator password    12) pfSense Developer Shell
 4) Reset to factory defaults         13) Upgrade from console
 5) Reboot system                     14) Disable Secure Shell (sshd)
 6) Halt system                       15) Restore recent configuration
 7) Ping host                         16) Restart PHP-FPM
 8) Shell
  

8

ping 172.30.31.20
PING 172.30.31.20 (172.30.31.20): 56 data bytes
64 bytes from 172.30.31.20: icmp_seq=0 ttl=64 time=0.239 ms
64 bytes from 172.30.31.20: icmp_seq=1 ttl=64 time=0.211 ms
```

## 登录 ##
172.30.31.1是内部局域网的IP，所以只能通过另一台lan上的服务器的浏览器访问：
![pfsense-vsphere6.png][6]
当然这样操作起来很不方便，，而且假如lan上的其它服务器都是linux而且没有图像界面，没办法使用webConfigurator了。端口转发似乎是一个比较好的方案：在某一台lan服务器上添加一个可以通过你的pc端访问的网卡（我这里的172.29.88.206，它的lan接口IP为172.30.31.20），然后使用rinetd工具转发到172.30.31.1。
这个方法似乎可选，但需要额外的设置：
![pfsense-vsphere7.png][7]

> An HTTP_REFERER was detected other than what is defined in System -> Advanced (http://172.29.88.206:8008/index.php?logout).  You can disable this check if needed in System -> Advanced -> Admin.

pfSense为了安全起见，不允许任何形式的转发来访问webConfigurator，根据你的需要决定是否关闭这个功能：System -> Advanced -> Admin，勾选Browser HTTP_REFERER enforcement -> Save -> Apply。
![pfsense-vsphere8.png][8]

登陆的用户名默认为admin/pfsense
![pfsense-vsphere9.png][9]

## 使用配置向导 ##
前面是通过命令行的方法对接口和IP进行配置，也可以直接通过webGUI向导对WAN和LAN、网关等设置：System -> Setup Wizard，因为太过简单，就不贴图了。
在设置WAN接口时（Configure WAN Interface）注意两点：

- Static IP Configuration 部分设置正确的IP和网关，否则会无法进出网络
- RFC1918 Networks 默认是勾选的，这是为了避免WAN上也存在与LAN一样的网段。如果要允许wan的其他主机ping通该pfSense，则去掉勾

其它保持为空或默认值。

## pfSense的NAT功能 ##
即Port Forward，目的是为了WAN上的其他机器可以访问LAN内部的服务。
Friewall -> NAT 
![pfsense-vsphere10.png][10]

端口映射分为单端口和范围端口。但端口容易理解，访问WAN 172.29.88.230:8000 的 数据包都转发到内部LAN 172.30.31.20:8000；范围端口是在 from *m* to `n` 的端口范围内的数据包都发送到内部IP的对应端口上，减少规则的数量。
![pfsense-vsphere11.png][11]
Save -> Apply Changes，与此同时pfSense会自动在防火墙里添加规则，Firewal -> Rules
![pfsense-vsphere12.png][12]

## pfSense做负载均衡 ##

## 其它功能 ##
pfSense还有几大重要的功能，如快速搭建VPN服务器，作为前端负载均衡服务器，流量限制。由于工作中暂未用到，所以就不加说明了。

关于负载均衡见 http://xgknight.com/2015/04/24/pfsense-loadbalancer/

**参考**

- [用pfSense搭建ESXi上的软路由](http://bbs.pceva.com.cn/thread-100070-1-1.html)
- [pfsense 企业应用实例](http://www.pppei.net/blog/post/331)
- [pfsense 研究- m0n0wall中国论坛](http://bbs.m0n0china.org/forumdisplay.php?fid=16)
- [PFsense学习 - 端口映射](http://44001217.blog.51cto.com/462930/180718)
- [pfSense 2.0 多 WAN 负载均衡设置指南](https://doc.pfsense.org/index.php/Multi-WAN_2.0) （[中文](http://www.netadmin.com.tw/article_content.aspx?sn=1205110003)）

  [0]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere0.png
  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere1.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere2.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere3.png
  [4]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere4.png
  [41]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere4-1.png
  [5]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere5.png
  [51]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere5-1.png
  [52]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere5-2.png
  [6]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere6.png
  [7]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere7.png
  [8]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere8.png
  [9]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere9.png
  [10]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere10.png
  [11]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere11.png
  [12]: http://github.com/seanlook/sean-notes-comment/raw/main/static/pfsense-vsphere12.png
