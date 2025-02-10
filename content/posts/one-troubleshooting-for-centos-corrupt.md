title: 记一次错误卸载软件包导致Linux系统崩溃的修复解决过程
date: 2014-11-03 01:21:25
updated: 2014-11-07 00:46:23
tags: [linux, 系统管理,troubleshooting]
categories: Linux
---

首先问题产生的缘由很简单，是我一同事在安装oracle一套软件时，按照要求需要binutils软件包的32位版本，然而在Oracle Linux已经装有64位，按理说是可以安装i686的，我猜应该是32位的版本低于这个已有的64位所以导致冲突而安装失败，因此同事就用`yum remove binutils`，这个命令也奇葩，由于是root权限导致依赖于它的200多个软件包也被卸载，最终导致网络断开，系统崩溃，在vSphere虚拟机上重新启动发现再也起不来。下面看问题：
## 1. Kernel panic - not syncing: Attempted to kill init! ##
![kernel_panic][1]

<!-- more -->

这个错误时在重新启动Oracle Linux一开始就出现，查阅的[相关资料](http://blog.51osos.com/linux/linux-kernel-panic/)得知`Kernel panic`问题一般是由驱动模块终端处理终端问题导致的（不懂。。。），一开始我以为是驱动程序依赖于binutils导致被卸载，因此第一反应是想办法把缺失的软件装回去。实际上，是由于安全访问控制模块selinux的问题，参考[类似问题](http://stackoverflow.com/questions/12867591/how-to-solve-kernel-panic-not-syncing-attempted-to-kill-init-without-er)。于是检查`vi /etc/selinux/config`时发现`SELINUX=disables`，拼写错误，应为`disabled`。
当再次启动没再出现该错误时，我高兴的认为原来这么简单就帮同事解决了，事实这根本还没到200多个软件包缺失而导致系统崩溃那一步。

## 2. 系统启动加载条完成后，一直hang住不动 ##
![boot_hang][2]

这无疑要使用LiveCD修复系统了，参考[Ultimate method to install package from linux rescue mode](http://www.slashroot.in/ultimate-method-install-package-linux-rescue-mode)或[Using Rescue Mode to Fix..Problems](https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Installation_Guide/rescuemode_drivers.html)。因为知道出问题前做过什么操作，下面直接上解决问题的过程。

### 2.1 将系统DVD安装镜像加载到光驱 ###
再次重启就自动进入安装界面，我们当然选择`rescue mode`：
![rescue_mode][3]

一路按照提示确定（可以不配置network，这里就不贴图了，很简单），最终会提供给用户一个shell终端，对应的是从DVD光驱加载进来的系统，执行`chroot /mnt/sysimage`才会进入到原损坏的Linux系统，还好`yum`和`rpm`命令还可以使用，悲剧的是我并不知道`yum remove`命令卸载了哪些软件包。


![chroot_sysimage][4]

![start_shell_mount][5]

### 2.2 安装缺失的软件包 ###
这里得谢天谢地`yum`命令的安装卸载日志`/var/log/yum.log`，这个日志里清楚的记录了`installed`和`erased`的所有软件包，用rpm是不可能了，因为270多个包的依赖关系难以解决，只能通过yum方式，而由于rescue模式没有配置网络，因此只能使用本地镜像源。
```
在rescue系统下挂载光驱到待修复系统中的/media目录
bash-4.1# mount /dev/cdrom /mnt/sysimage/media

chroot进入待修复系统
bash-4.1# chroot /mnt/sysimage

手动编辑一个仓库源（真实待修复的系统）
sh-4.1# cd /etc/yum.repos.d/ && vi Oracle-Media.repo
[DVD-media]
name=oracle-$releasever - Media
baseurl=file:///media
gpgcheck=0
enabled=1
```
建议只留Oracle-Media.repo文件，其他的.repo文件都`mv`成.bak，以防连接不了这些源而报错，虽然报错关系不大。
获取被依赖erased掉的软件列表
```
你可以将yum.log中多余的部分去掉，筛选出应该重新安装的packages：
sh-4.1# cp /var/log/yum.log{,.bak}
sh-4.1# less /var/log/yum.log.bak
Oct 29 20:17:34 Erased: gcc-c++
Oct 29 20:18:44 Erased: gcc
Oct 29 20:22:59 Erased: xorg-x11-drivers
...
Oct 29 20:24:46 Erased: iputils
Oct 29 20:24:46 Erased: udev
Oct 29 20:24:46 Erased: initscripts
Oct 29 20:24:46 Erased: hwdata
Oct 29 20:24:46 Erased: module-init-tools
Oct 29 20:24:48 Erased: binutils

下面一条命令应该要彻底解决问题了
sh-4.1# awk '{print "yum install -y ",$5}' /var/log/yum.log.bak |sh > /root/yum_install.log
```
保险起见，可以查看一下产生的日志文件。此时重启（记得拿出光盘）应该是修复问题了。但我遇见的问题还没完。

## 3. An error occurred during the file system check ##
![filesystem_check_error][6]
显然，文件系统损坏。根据提示输入root密码后可以进入到shell中，网上有办法说执行`fsck`命令来修复分区，又说且不能是mounted状态，但无论我怎么去`fsck.ext4 /dev/mapper/vg_fusion_lv_u1`，提示：
```
WARNING!!!  The filesystem is mounted.   if you continue you ***WILL*** 
cause ***SEVERE*** filesystem damage`

Do you really want to continue (y/n)? yes

fsck.ext4: No such file or directory while trying to open /dev/mapper/vg_fusion_lv_u1

The superblock could not be read or does not describe a correct ext2 
filesystem.  If the device is valid and it really contains an ext2 
filesystem (and not swap or ufs or something else), then the superblock 
is corrupt, and you might try running e2fsck with an alternate superblock:
    e2fsck -b 8193 <device>
```
听起来好像还挺严重的，我之前猜想的是不是反复的开关电源来重启导致lvm文件系统corrupt，但事实我发现`/dev/mapper/vg_fusion_lv_u1`不存在，但`lv_fusion_lv_root`却完好，执行`lvdisplay`发现这个命令根本不存在，这才发现原来lvm2软件没有安装（难道是第2部分安装少许出错？）。
这下容易多了，反正现在系统不借助`rescue mode`就可以起来，重新安装软件包，但是此时的整个文件系统是`read only`，有两个办法可以解决：

1. `mount -o remount,rw /`
重新挂载根分区为读写，`vi /etc/fstab`注释掉挂载`/u1`的那条记录，此时会正常启动，只是有一个文件系统没有挂载，但可以正常安装缺失的lvm2软件，不妨多执行几遍2.2的安装命令。然后手动挂载`mount /dev/mapper/vg_fusion_lv_u1 /u1`应该就没问题了。记得改回/etc/fstab。
2. 与`2.2`步骤类似，进入`rescue mode`→`chroot`，重新执行`awk '{print "yum install -y ",$5}' /var/log/yum.log.bak |sh > /root/yum_install.log`，确保没有报错且已安装lvm。

这下问题总是解决了，避免了删除系统的灾难（测试环境）。

## 4. 总结 ##
回头去看这三个问题，其他它们是各自独立的

- 第1个问题，是由于设置selinux有人拼写错误，哪怕没做后续的任何操作，重启系统就会启动不了，是早已存在到目前才发现。也有人说遇见过同样的`Kernel panic`错误但尝试各种办法都难以解决的，这就看具体问题具体分析了。
- 第2个问题，是真真切切错误卸载重要软件包，导致系统崩溃，修复系统的方法自然也就是利用原镜像在`rescue mode`下把该装的都装回去，前提是yum.log日志存在，万幸没有执行过`yum clean all`。
- 第3个问，题实际文件系统并没有损坏，还是lvm2缺失，但是此处必须小心，免得`SEVERE filesystem damage`，那么修复过程就没意义了。

以后处理其他系统故障时也可使用类似的方法修复，Redhat、CentOS、OracleLinux、Ubuntu等都适用。


  [1]: http://sean-images.qiniudn.com/kernel-panic.png
  [2]: http://sean-images.qiniudn.com/boot_up_fail.png
  [3]: http://sean-images.qiniudn.com/rescue_mode.png
  [4]: http://sean-images.qiniudn.com/chroot_sysimage.png
  [5]: http://sean-images.qiniudn.com/start_shell_mount.png
  [6]: http://sean-images.qiniudn.com/file_system_check.png