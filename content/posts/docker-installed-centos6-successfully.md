---
title: 在 CentOS 6.x上安装 docker.io成功
date: 2014-10-26 19:45:25
updated: 2014-10-27 10:46:23
tags: [docker, centos,linux]
categories: [Virtualization, Docker]
---
docker是什么就不多说了，见[docker基础原理介绍](http://xgknight.com/2014/12/18/docker-introduction/)。
docker容器最早受到RHEL完善的支持是从最近的CentOS 7.0开始的，官方说明是只能运行于64位架构平台，内核版本为2.6.32-431及以上（即>=CentOS 6.5，运行docker时实际提示3.8.0及以上），升级内核请参考[CentOS 6.x 内核升级（2.6.32 -> 3.10.58）过程记录](http://xgknight.com/2014/10/24/upgrade-centos6_kernel-to-3.10.x/)
需要注意的是CentOS 6.5与7.0的安装是有一点点不同的，CentOS-6上docker的安装包叫docker-io，并且来源于Fedora epel库，这个仓库维护了大量的没有包含在发行版中的软件，所以先要安装EPEL，而CentOS-7的docker直接包含在官方镜像源的Extras仓库（CentOS-Base.repo下的[extras]节enable=1启用）。前提是都需要联网，具体安装过程如下。
###1. 禁用selinux###
```bash
# getenforce
enforcing
# setenforce 0
permissive
# vi /etc/selinux/config
SELINUX=disabled
...
```

<!-- more -->

###2. 安装 Fedora EPEL###
epel-release-6-8.noarch.rpm包在发行版的介质里面已经自带了，可以从rpm安装。
```bash
# yum install epel-release-6-8.noarch.rpm
//或
yum -y install http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
```
如果出现`GPG key retrieval failed: [Errno 14] Could not open/read file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-6`问题，请在线安装epel，下载RPM-GPG-KEY-EPEL-6文件。
这一步执行之后，会在/etc/yum.repos.d/下生成epel.repo、epel-testing.repo两个文件，用于从Fedora官网下载rpm包。
###3. 检查内核版本###
```bash
# uname -r
2.6.32-431.el6.x86_64
# cat /etc/redhat-release 
CentOS release 6.5 (Final)
```
看到这个最低的内核版本，事实运行起来是没太大问题的，你也可以升级到3.10.x版本。
另外你也可以运行脚本[check-config.sh](https://raw.githubusercontent.com/dotcloud/docker/master/contrib/check-config.sh)，来检查内核模块符不符合（下面有些missing的，我的docker还是可以正常启动）：
```
[root@sean ~]# ./check-config 
warning: /proc/config.gz does not exist, searching other paths for kernel config...
info: reading kernel config from /boot/config-2.6.32-431.el6.x86_64 ...

Generally Necessary:
- cgroup hierarchy: properly mounted [/cgroup]
- CONFIG_NAMESPACES: enabled
- CONFIG_NET_NS: enabled
- CONFIG_PID_NS: enabled
- CONFIG_IPC_NS: enabled
- CONFIG_UTS_NS: enabled
- CONFIG_DEVPTS_MULTIPLE_INSTANCES: enabled
- CONFIG_CGROUPS: enabled
- CONFIG_CGROUP_CPUACCT: enabled
- CONFIG_CGROUP_DEVICE: enabled
- CONFIG_CGROUP_FREEZER: enabled
- CONFIG_CGROUP_SCHED: enabled
- CONFIG_MACVLAN: enabled
- CONFIG_VETH: enabled
- CONFIG_BRIDGE: enabled
- CONFIG_NF_NAT_IPV4: missing
- CONFIG_IP_NF_TARGET_MASQUERADE: enabled
- CONFIG_NETFILTER_XT_MATCH_ADDRTYPE: missing
- CONFIG_NETFILTER_XT_MATCH_CONNTRACK: enabled
- CONFIG_NF_NAT: enabled
- CONFIG_NF_NAT_NEEDED: enabled

Optional Features:
- CONFIG_MEMCG_SWAP: missing
- CONFIG_RESOURCE_COUNTERS: enabled
- CONFIG_CGROUP_PERF: enabled
- Storage Drivers:
  - "aufs":
    - CONFIG_AUFS_FS: missing
    - CONFIG_EXT4_FS_POSIX_ACL: enabled
    - CONFIG_EXT4_FS_SECURITY: enabled
  - "btrfs":
    - CONFIG_BTRFS_FS: enabled
  - "devicemapper":
    - CONFIG_BLK_DEV_DM: enabled
    - CONFIG_DM_THIN_PROVISIONING: enabled
    - CONFIG_EXT4_FS: enabled
    - CONFIG_EXT4_FS_POSIX_ACL: enabled
    - CONFIG_EXT4_FS_SECURITY: enabled
```
假如你是自己编译内核，请特别留意几个绝对不能缺少的：DM_THIN_PROVISIONING、IP_NF_TARGET_MASQUERADE、NF_NAT。（AUFS_FS没有对应选项，还不清楚怎么回事，但不是必须）
###4. 安装 docker-io###
```
# yum install docker-io
Dependencies Resolved

===========================================================================================
 Package                        Arch               Version          Repository     Size
===========================================================================================
Installing:
 docker-io                      x86_64         1.1.2-1.el6          epel          4.5 M
Installing for dependencies:
 lua-alt-getopt                 noarch         0.7.0-1.el6          epel          6.9 k
 lua-filesystem                 x86_64         1.4.2-1.el6          epel           24 k
 lua-lxc                        x86_64         1.0.6-1.el6          epel           15 k
 lxc                            x86_64         1.0.6-1.el6          epel          120 k
 lxc-libs                       x86_64         1.0.6-1.el6          epel          248 k

Transaction Summary
===========================================================================================
Install       6 Package(s)
```
许多文档介绍到这里，下一步为挂载/cgroup文件系统，我的docker版本为1.1.2，没有修改/etc/fstab的步骤。

###5. 启动试运行###
```bash
# service docker start
//或
# docker -d 
```
##6. 异常##
在我的一次安装过程中，很不幸遇到下面的问题：
`docker -d`启动，或`tail -f /var/log/docker`查看日志
```
[f32e7d9f] +job initserver()
[f32e7d9f.initserver()] Creating server
[f32e7d9f] +job serveapi(unix:///var/run/docker.sock)
2014/10/22 13:02:45 Listening for HTTP on unix (/var/run/docker.sock)
Error running DeviceCreate (createPool) dm_task_run failed
[f32e7d9f] -job initserver() = ERR (1)
2014/10/22 13:02:45 Error running DeviceCreate (createPool) dm_task_run failed
\nWed Oct 22 14:35:54 CST 2014\n
```
再或者是`service docker restart`
```
Stopping docker:                                             [  OK  ]
Starting cgconfig service: Error: cannot mount cpuset to /cgroup/cpuset: Device or resource busy
/sbin/cgconfigparser; error loading /etc/cgconfig.conf: Cgroup mounting failed
Failed to parse /etc/cgconfig.conf                           [FAILED]

Starting docker:                                              [  OK  ]
```
```
Unable to enable network bridge NAT: iptables failed: iptables -I POSTROUTING -t nat -s 172.17.42.1/16 ! -d 172.17.42.1/16 -j MASQUERADE: iptables v1.4.7: can't initialize iptables table `nat': Table does not exist (do you need to insmod?)
Perhaps iptables or your kernel needs to be upgraded.
```
上面的三个异常都是由于内核模块的缺失导致的，这也是自己编译内核来升级带来的风险，于是就有了[sciurus](https://github.com/sciurus/docker-rhel-rpm/tree/master/kernel-ml-aufs)的kernel-ml-aufs的rpm包（见参考的第一个链接）。

##7. 参考##
- [Installing docker.io on centos 6.4 (64-bit)](http://nareshv.blogspot.hk/2013/08/installing-dockerio-on-centos-64-64-bit.html)，[在 CentOS 6.4(64位) 安装 docker.io](http://www.oschina.net/translate/nstalling-dockerio-on-centos-64-64-bit) [中文]
- [在 CentOS 6.4 上安装 docker](http://cn.soulmachine.me/blog/20131025/)
- [Official Installing Docker Docs CentOS-6](https://docs.docker.com/installation/centos/)
- Troubleshooting:
[Error: cannot mount cpuset to /cgroup/cpuset: Device or resource busy](http://stackoverflow.com/questions/25183063/docker-on-rhel-6-cgroup-mounting-failing)
[Error running DeviceCreate (createPool) dm_task_run failed](https://github.com/docker/docker/issues/6325)
