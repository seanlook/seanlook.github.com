---
title: iscsi网络存储介绍及客户端配置操作
date: 2015-04-28 01:21:25
aliases:
- /2015/04/28/iscsi-san-initiator/
updated: 2015-04-29 10:46:23
tags: [iscsi]
categories: [Linux]
---

本文不介绍iSCSI服务端的搭建过程，不然就会很累赘。主题就是怎么去完成iscsi网络存储的挂载过程，并顺带介绍一些必要的概念。
# 1. iscsi介绍与initiator安装 #
## 1.1 iSCSI介绍 ##
iSCSI简单来说，就是把SCSI指令通过TCP/IP协议封装起来，在以太网中传输。iSCSI 可以实现在IP网络上传递和运行SCSI协议，使其能够在诸如高速千兆以太网上进行数据存取，实现了数据的网际传递和管理。基于iSCSI建立的存储区域网（SAN）与基于光纤的FC-SAN相比，具有很好的性价比。

iSCSI属于端到端的会话层协议，它定义的是SCSI到TCP/IP的映射（如下图），即Initiator将SCSI指令和数据封装成iSCSI协议数据单元，向下提交给TCP层，最后封装成IP数据包在IP网络上传输，到达Target后通过解封装还原成SCSI指令和数据，再由存储控制器发送到指定的驱动器，从而实现SCSI命令和数据在IP网络上的透明传输。它整合了现有的存储协议SCSI和网络协议TCP/IP，实现了存储与TCP/IP网络的无缝融合。在本文中，将把发起器Initiator称为客户端，将目标器Target称为服务端以方便理解。

![iscsi-protocal-arch.gif][1]

iSCSI 服务端和客户端的通讯就是一个在网络上封包和解包的过程，在网络的一端，数据包被封装成包括TCP/IP头、iSCSI 识别包和SCSI 数据三部分内容，传输到网络另一端时，这三部分内容分别被顺序地解开。为了保证安全，iSCSI 有约定操作顺序。在首次运行时，客户端（initiator）设备需要登录到服务端（target）中。任何一个接收到没有执行登录过程的客户端的iSCSI PDU （iSCSI rotocol Data Units，iSCSI 协议数据单元）服务端都将生成一个协议错误，并且关闭连接。在关闭会话之前，服务端可能发送回一个被驳回的iSCSI PDU。

在工作时，iSCSI使SCSI数据块由原来的SCSI总线连接扩展到internet上，这一过程有些产品通过硬件来实现，这种硬件产品被简称为TOE（TCP Offload Engine），随着近年来服务器芯片技术的不断发展，服务器处理能力日益强劲，目前更为普遍的是通过软件来实现SCSI数据块的封装过程。这种软件通常被称为iSCSI Initiator软件/驱动。Initiator软件可以将以太网卡虚拟为iSCSI卡，接受和发送iSCSI数据报文，通过普通以太网卡来进行网络连接，但是需要占用CPU资源。另外的TOE和HBA连接转换方式都需要专门的硬件设备来完成，虽然相对昂贵但执行效率高，也可以减轻主机CPU的负载。本文客户端采用Initiator驱动的连接方式。

## 1.2 Initiator安装 ##
在Linux 2.6内核中提供了iscsi驱动，iSCSI 驱动（driver）使主机拥有了通过IP网络访问存储的能力，但还需要一个具体的客户端工具（Linux用户空间组件）初始化iSCSI驱动，即`iscsi-initiator-utils`，也是大家常说的open-iscsi。

<!-- more -->

```
# rpm -qa|grep iscsi
iscsi-initiator-utils-6.2.0.873-10.el6.x86_64
iscsi-initiator-utils-devel-6.2.0.873-10.el6.x86_64
# rpm -qi iscsi-initiator-utils
（yum install iscsi-initiator-utils iscsi-initiator-utils-devel）
```
这个安装将`iscsid`、`iscsiadm`安装到 /sbin 目录下，它还将把默认的配置文件安装到`/etc/iscsi/`目录下：

- `/etc/iscsi/iscsid.conf`：所有刚发起的iSCSI session默认都将使用这个文件中的参数设定。
- `/etc/iscsi/initiatorname.iscsi`：软件iSCSI initiator的intiator名称配置文件。

确保iscsid和iscsi两个服务器开机自启动，`chkconfig --list |grep iscsi`，在iscsi启动的时候，iscsid和iscsiadm会读取这两个配置文件。

service iscsid [status|start]
service iscsi status        查看iscisi的信息，只有在连接成功后才输出
这里可能遇到start始终没有启动成功的信息输出，请继续往下执行discovery，一般会启动iscsid。

## 1.3 open-iscsi initiator说明 ##
open-iscsi包括两个守护进程iscsid和iscsi，其中iscsid是主进程，iscsi进程则主要负责根据配置在系统启动时进行发起端（Initiator）到服务端（target）的登录，建立发起端与服务端的会话，使主机在启动后即可使用通过iSCSI提供服务的存储设备。 
       
iscsid进程实现iSCSI协议的控制路径以及相关管理功能。例如守护进程（指iscsid）可配置为在系统启动时基于持久化的iSCSI数据库内容，自动重新开始发现（discovery）目标设备。

Open-iSCSI是通过以下iSCSI数据库文件来实现永久配置的：

- Discovery (`/var/lib/iscsi/send_targets`)
在 /var/lib/iscsi/send_targets 目录下包含iSCSI portals的配置信息，每个portal对应一个文件，文件名为“iSCSI portal IP，端口号”（例如`172.29.88.61,3260`）。
- Node (`/var/lib/iscsi/nodes`)
在 /var/lib/iscsi/nodes 目录下，生成一个或多个以iSCSI存储服务器上的Target名命名的文件夹如`iqn.2000-01.com.synology:themain-3rd.ittest`，在该文件夹下有一个文件名为“iSCSI portal IP，编号” （例如`172.29.88.62,3260,0`）的配置参数文件default，该文件中是initiator登录target时要使用的参数，这些参数的设置是从`/etc/iscsi/iscsi.conf`中的参数设置继承而来的，可以通过iscsiadm对某一个参数文件进行更改（需要先注销到target的登录）。

`iscsiadm`是用来管理（更新、删除、插入、查询）iSCSI配置数据库文件的命令行工具，用户能够用它对iSCSI nodes、sessions、connections和discovery records进行一系列的操作。

iSCSI node是一个在网络上可用的SCSI设备标识符，在open-iscsi中利用术语node表示目标（target）上的门户（portal）。一个target可以有多个portal，portal 由IP地址和端口构成。

# 2. 初次挂载网络存储 #
## 2.1 设置InitiatorName ##
initiator名称用来唯一标识一个iSCSI Initiator端。保存此名称的配置文件为`/etc/iscsi/initiatorname.iscsi`：
```
# vi /etc/iscsi/initiatorname.iscsi
InitiatorName=iqn.2000-01.com.synology:themain-3rd.ittest
```
注意大小写，同时，必须顶格写，xxxx代表要设置的initiator名称，请遵循iqn命名规范，格式为iqn.domaindate.reverse.domain.name:optional_name。

## 2.2 iSCSI Initiator配置 ##
iSCSI Initiator的配置文件为`/etc/iscsi/iscsid.conf`,在iSCSI initiator的iscsid进程启动和执行iscsiadm命令时，将读取这个配置文件的内容，获取与SCSI目标进行交互的相关信息。

### 2.2.1 添加CHAP认证 ###
本组下的各个设置项主要用来指定Initiator与target验证方式。
```
vi /etc/iscsi/iscsid.conf
# To enable CHAP authentication set node.session.auth.authmethod
node.session.auth.authmethod = CHAP        去掉注释
# To set a CHAP username and password for initiator
node.session.auth.username = ittest              修改为网管提供的认证username/password
node.session.auth.password = Storageittest
```
上面是在我的环境中最为简单的一种CHAP（Challenge Handshake Authentication Protocol）认证方式，而且只验证的节点会话initiator端。其实iSCSI验证可以是双向的，根据服务端的设置，可以验证节点会话的target端（username_in），验证发现会话的CHAP initiator，验证发现会话的CHAP target。（节点会话node.session即登录认证，发现会话discovery.sendtargets即查看）

### 2.2.2 其他配置项 ###
处理CHAP认证需要关注外，其它的都保持默认即可，但是你需要知道可以修改如:

1. 设置initiator与target端交互的超时时间
2. 设置iscsid重试登录节点的次数
3. 是否开机启动iscsid等待

## 2.3 扫描并登录到iqn连接 ##
open-iscsi initiator-utils提供的管理命令为`iscsiadm`，此命令包括discovery、node、session几种模式，分别处理不同的情况。在客户端使用Target提供的存储空间前，必须在服务器上通过Initiator软件执行以下步骤：发现目标设备 --> 登录目标设备 --> 与目标设备建立会话，下面分别说明通过各个命令进行说明。

### 2.3.1 discovery sendtargets ###
可以通过sendtargets方式（根据iscsi服务器端使用的方式不同还有slp、isns）发现属于你的iqn（iSCSI Qualified Name）：
```
iscsiadm -m discovery -t sendtargets -p 172.29.88.62
iscsiadm -m discovery -t sendtargets -p 172.29.88.62:3260 |grep ittest
```
默认端口3260。discovery之前会自动启动iscsid服务，有时候`service iscsid start`启动没反应，可以通过这种方式启动服务。
此命令查询目标门户（Portal）为172.29.88.62:3260上的目标，查找成功后，返回相应的target ID，同时在`/var/lib/iscsi/send_targets`和 `/var/lib/iscsi/nodes`目录下记录相应的门户和节点信息。使用`iscsiadm -m node`命令，可以查看到发现的节点记录。

### 2.3.2 node session login ###
在完成目标发现后，即可以登录到相应的节点，使用目标设备提供的存储空间：
```
# iscsiadm -m node -T iqn.2000-01.com.synology:themain-3rd.ittest -p 172.29.88.62 --login
```
`-T`后面跟target名称，`--login`等同于`-l`，

登录目标节点成功后，即建立了initiator与target之间的会话（session），同时target提供的存储设备也挂载到主机中，在/dev目录下生成一个新的设备文件类似于sdb、sdc等。使用`iscsiadm -m session -P 3`（与`service iscsi status`相同）来查看连接会话信息。

## 2.4 使用磁盘 — lvm ##
LVM是非常流行的可修改磁盘分区大小的管理方式，可以根据你的需要使用使用lvm管理磁盘。
假设新存储的设备路径为`/dev/sdb`
```
pvcreate /dev/sdb                    ## 在新存储上建立物理卷
pvdisplay                                   ## 查看物理卷状态
vgcreate vg_ittest /dev/sdb      ## 在该物理卷上建立名为vg_test的卷组
vgdisplay                                   ## 查看已建立的卷组状态
lvcreate -l 100%FREE -n lv_static vg_ittest
```
在vg_ittest卷组上建立名为lv_static的逻辑卷，-L可指定分区大小，此处-l表示使用全部空间
```
vgscan或lvdisplay                     ## 查看逻辑卷的状态
vgchange -ay                            ## 使卷组处于激活状态
mkfs.ext4 /dev/mapper/vg_ittest-lv_static            ## 格式化已创建的逻辑卷，文件系统格式为ext4
```
格式化完毕后，使用mount命令挂载即可：
```
mount -o acl,rw /dev/mapper/vg_ittest-lv_static  /iscsi    ## /iscsi为事先建立的挂载点
```
也可以根据需求划分成多个分区挂载。

**开机自动挂载**
```
vi /etc/rc.d/rc.local
iscsiadm -m node -T iqn.2000-01.com.synology:themain-3rd.ittest -p 172.29.88.62 --login
vgchange -ay && mount -o acl,rw /dev/mapper/vg_ittest-lv_static /iscsi
```

# 3. 维护操作 #
## 3.1 正常断开重连网络存储 ##
因为磁盘上就是数据（一般网络存储用于备份），因此尽量减少异常断开存储的可能性，所以保险起见先卸载，再断开连接(`-u`)。
```
# umount /iscsi
# vgchange -an && vgscan
# iscsiadm -m session
# iscsiadm -m node -T iqn.2000-01.com.synology:themain-3rd.ittest -p 172.29.88.62 --logout
```
## 3.2 异常断开恢复 ##
如果使用LVM管理磁盘，由于网络中断，或主机突然关机，会导致网络存储异常断开，下次启动后重新连接可能会报如下错误：
```
# vgscan
 Reading all physical volumes.  This may take a while...
 /dev/backupdrive1/backup: read failed after 0 of 4096 at 319836585984: Input/output error
 /dev/backupdrive1/backup: read failed after 0 of 4096 at 319836643328: Input/output error
 /dev/backupdrive1/backup: read failed after 0 of 4096 at 0: Input/output error
 /dev/backupdrive1/backup: read failed after 0 of 4096 at 4096: Input/output error
 Found volume group "backupdrive1" using metadata type lvm2
 Found volume group "networkdrive" using metadata type lvm2
```
产生原因就是，在卷组（VG）失活（deactivate）之前就移除了外部的LVM设备。在你断开连接之前，需要保证以下命令被执行：
```
# vgchange -an volume_group_name
```

解决方案就是，（假设你已经用`vgchange -ay vg`命令来激活卷组，但仍有 Input/output error 的错误信息。）执行命令`vgchange -an volume group name`，移除外部设备，稍候几分钟后再执行以下命令：
```
# vgscan
# vgchange -ay volume_group_name
```

## 3.3 进程数超标 ##
iscsi存储使用正常，但`ps -ef|grep iscsi`则包含200+以上的类似于`[iscsi_q_112]`进程，并且无法kill，使用`service iscsi status`不断输出类似：
```
iscsiadm: could not read session targetname: 5
iscsiadm: could not find session info for session30
iscsiadm: could not read session targetname: 5
iscsiadm: could not find session info for session31
...
```
这个问题很纠结，但重启服务器是可以解决的。网上资料很少，我猜想是iscsid服务端设置认证方面的问题。

# 4. iscsi的其它常用操作 #

- 列出所有target
`iscsiadm -m node`

- 连接所有target
`iscsiadm -m node -L all`

- 连接指定target
`iscsiadm -m node -T iqn.... -p 172.29.88.62 --login`

- 使用如下命令可以查看配置信息
`iscsiadm -m node -o show -T iqn.2000-01.com.synology:rackstation.exservice-bak`

- 查看目前 iSCSI target 连接状态 
`iscsiadm -m session`
iscsiadm: No active sessions. 
(目前没有已连接的 iSCSI target)

- 断开所有target
`iscsiadm -m node -U all`

- 断开指定target
`iscsiadm -m node -T iqn...  -p 172.29.88.62 --logout`

- 删除所有node信息
`iscsiadm -m node --op delete`

- 删除指定节点（/var/lib/iscsi/nodes目录下，先断开session）
`iscsiadm -m node -o delete -name iqn.2012-01.cn.nayun:test-01`

- 删除一个目标（/var/lib/iscsi/send_targets目录下）
`iscsiadm --mode discovery -o delete -p 172.29.88.62:3260`

**参考**
- [CentOS客户端加载ISCSI磁盘](http://blog.csdn.net/sflsgfs/article/details/9180521)
- [linux iscsi initiator 安装配置](http://tagche.blog.51cto.com/649757/267390/)
- http://linux.vbird.org/linux_server/0460iscsi.php


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/iscsi-protocal-arch.gif
