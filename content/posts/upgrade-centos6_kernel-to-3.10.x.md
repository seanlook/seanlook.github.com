---
title: CentOS 6.x 内核升级（2.6.32 -> 3.10.58）过程记录
date: 2014-10-24 01:21:25
aliases:
- /2014/10/24/upgrade-centos6_kernel-to-3.10.x/
updated: 2014-10-27 10:46:23
tags: [docker, Linux内核, upgrade]
categories: [Linux, CentOS]
---

本人升级的目的是想在CentOS6.2上运行docker，官方建议内核版本在3.8.0及以上，于是就自己从Linux内核官方网站上下载源码，自己编译。
##1. 准备工作##
###1.1 确认内核及版本信息###
```python
[root@hostname ~]# uname -r
2.6.32-220.el6.x86_64
[root@hostname ~]# cat /etc/centos-release 
CentOS release 6.2 (Final)
```

<!-- more -->

###1.2 安装软件###

编译安装新内核，依赖于开发环境和开发库
```python
# yum grouplist  //查看已经安装的和未安装的软件包组，来判断我们是否安装了相应的开发环境和开发库；
# yum groupinstall "Development Tools"  //一般是安装这两个软件包组，这样做会确定你拥有编译时所需的一切工具
# yum install ncurses-devel //你必须这样才能让 make *config 这个指令正确地执行
# yum install qt-devel //如果你没有 X 环境，这一条可以不用
# yum install hmaccalc zlib-devel binutils-devel elfutils-libelf-devel //创建 CentOS-6 内核时需要它们
```
如果当初安装系统是选择了Software workstation，上面的安装包几乎都已包含。
##2. 编译内核##
###2.1 获取并解压内核源码，配置编译项###
去 http://www.kernel.org 首页，可以看到有stable, longterm等版本，longterm是比stable更稳定的版本，会长时间更新，因此我选择 3.10.58。
```python
[root@sean ~]# tar -xf linux-3.10.58.tar.xz -C /usr/src/
[root@sean ~]# cd /usr/src/linux-3.10.58/
[root@sean linux-3.10.58]# cp /boot/config-2.6.32-220.el6.x86_64 .config
```
我们在系统原有的内核配置文件的基础上建立新的编译选项，所以复制一份到当前目录下，命名为.config。接下来继续配置：
```python
[root@sean linux-3.10.58]# sh -c 'yes "" | make oldconfig'
  HOSTCC  scripts/basic/fixdep
  HOSTCC  scripts/kconfig/conf.o
  SHIPPED scripts/kconfig/zconf.tab.c
  SHIPPED scripts/kconfig/zconf.lex.c
  SHIPPED scripts/kconfig/zconf.hash.c
  HOSTCC  scripts/kconfig/zconf.tab.o
  HOSTLD  scripts/kconfig/conf
scripts/kconfig/conf --oldconfig Kconfig
.config:555:warning: symbol value 'm' invalid for PCCARD_NONSTATIC
.config:2567:warning: symbol value 'm' invalid for MFD_WM8400
.config:2568:warning: symbol value 'm' invalid for MFD_WM831X
.config:2569:warning: symbol value 'm' invalid for MFD_WM8350
.config:2582:warning: symbol value 'm' invalid for MFD_WM8350_I2C
.config:2584:warning: symbol value 'm' invalid for AB3100_CORE
.config:3502:warning: symbol value 'm' invalid for MMC_RICOH_MMC
*
* Restart config...
*
*
* General setup
*

... ...
XZ decompressor tester (XZ_DEC_TEST) [N/m/y/?] (NEW) 
Averaging functions (AVERAGE) [Y/?] (NEW) y
CORDIC algorithm (CORDIC) [N/m/y/?] (NEW) 
JEDEC DDR data (DDR) [N/y/?] (NEW) 
#
# configuration written to .config
#
```
make oldconfig会读取当前目录下的.config文件，在.config文件里没有找到的选项则提示用户填写。有的文档里介绍使用make memuconfig，它便是根据需要定制模块，类似界面如下：（我们不需要）
![make menuconfig][1]
make oldconfig会在生成新的.config之前备份为.config.old，并生成新的.config文件

###2.2 开始编译###
```python
[root@sean linux-3.10.58]# make -j4 bzImage  //生成内核文件
[root@sean linux-3.10.58]# make -j4 modules  //编译模块
[root@sean linux-3.10.58]# make -j4 modules_install  //编译安装模块
```
-j后面的数字是线程数，用于加快编译速度，一般的经验是，逻辑CPU，就填写那个数字，例如有8核，则为-j8。（modules部分耗时30多分钟）
###2.3 安装###
[root@sean linux-3.10.58]# make install
实际运行到这一步时，出现```ERROR: modinfo: could not find module vmware_balloon```，但是不影响内核安装，是由于vsphere需要的模块没有编译，要避免这个问题，需要在make之前时修改.config文件，加入
HYPERVISOR_GUEST=y
CONFIG_VMWARE_BALLOON=m 
（这一部分比较容易出问题，参考下文异常部分）
###2.4 修改grub引导，重启###
安装完成后，需要修改Grub引导顺序，让新安装的内核作为默认内核。
编辑 grub.conf文件，
```python
vi /etc/grub.conf
#boot=/dev/sda
default=0
timeout=5
splashimage=(hd0,0)/grub/splash.xpm.gz
hiddenmenu
title CentOS (3.10.58)
    root (hd0,0)
...
```
数一下刚刚新安装的内核在哪个位置，从0开始，然后设置default为那个数字，一般新安装的内核在第一个位置，所以设置default=0。
重启`reboot`：
![boot-with-new-kernel][2]
###2.5 确认当内核版本###
```python
[root@sean ~]# uname -r
3.10.58
```
升级内核成功!
##3. 异常##
###3.1 编译失败（如缺少依赖包）###
可以先清除，再重新编译：
```python
# make mrproper         #完成或者安装过程出错，可以清理上次编译的现场
# make clean
```
###3.2 在vmware虚拟机上编译，出现类似下面的错误###
```python
[root@sean linux-3.10.58]# make install 
sh /usr/src/linux-3.10.58/arch/x86/boot/install.sh 3.10.58 arch/x86/boot/bzImage \
		System.map "/boot"
ERROR: modinfo: could not find module vmware_balloon
```
可以忽略，如果你有强迫症的话，尝试以下办法：
要在vmware上需要安装VMWARE_BALLOON，可直接修改.config文件，但如果vi直接加入`CONFIG_VMWARE_BALLOON=m`依然是没有效果的，因为它依赖于`HYPERVISOR_GUEST=y`。如果你不知道这层依赖关系，通过`make menuconfig`后，Device Drivers -> MISC devices 下是找不到VMware Balloon Driver的。（手动vi .config修改HYPERVISOR_GUEST后，便可以找到这一项），另外，无论是通过make menuconfig或直接vi .config，最后都要运行`sh -c 'yes "" | make oldconfig'`一次得到最终的编译配置选项。
然后，考虑到vmware_balloon可能在这个版本里已更名为vmw_balloon，通过下面的方法保险起见：
```
# cd /lib/modules/3.10.58/kernel/drivers/misc/
# ln -s vmw_balloon.ko vmware_balloon.ko #建立软连接
```
其实，针对安装docker的内核编译环境，最明智的选择是使用[sciurus](https://raw.githubusercontent.com/sciurus/docker-rhel-rpm/master/kernel-ml-aufs/config-3.10.11-x86_64)帮我们配置好的.config文件。
也建议在`make bzImage`之前，运行脚本[check-config.sh](https://raw.githubusercontent.com/dotcloud/docker/master/contrib/check-config.sh)检查当前内核运行docker所缺失的模块。
当提示缺少其他module时如NF_NAT_IPV4时，也可以通过上面的方法解决，然后重新编译。
##4. TO-DO##
- 如何清除原内核
- 现有软件是否需要yum update升级

##5. 参考资料##
- [CentOS 6.5 升级内核到 3.10.28](http://cn.soulmachine.me/blog/20140123/)
- [Linux Kernel内核配置方式详解](http://smilejay.com/2011/05/linux-kernel-configuration/)


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/config-kernel-module.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/boot-with-new-kernel.png
