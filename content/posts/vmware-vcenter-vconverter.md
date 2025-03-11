---
title: 使用vmware vconverter从物理机迁移系统到虚拟机P2V（多图）
date: 2015-04-05 15:21:25
aliases:
- /2015/04/05/vmware-vcenter-vconverter/
updated: 2015-04-06 00:46:23
tags: [vsphere, 虚拟化,vmware]
categories: Virtualization
---

本文完整记录了如何从物理服务器，保持所有环境配置信息，纹丝不动的迁移到虚拟机上，俗称 P2V 。采用的工具是VMware公司的 `VMware vcenter vconverter standalone`，它支持将windows和linux操作系统用作源，可以执行若干转换任务：

- 将正在运行的远程物理机和虚拟机作为虚拟机导入到vCenter Server管理的独立ESX/ESXi或ESX/ESXi主机
- 将由VMware Workstation或Microsoft Hyper-V Server托管的虚拟机导入到vCenter Server管理的ESX/ESXi主机
- 将第三方备份或磁盘映像导入到vCenterServer管理的ESX/ESXi主机中
- 将旧版服务器迁移到新硬件，而不重新安装操作系统或应用程序软件等
- 完整功能见《Converter Standalone 用户指南》

Converter Standalone的组件，只能安装在Windows操作系统上：

- Converter Standalone Server —— 启用并执行虚拟机的导入和导出
- Converter Standalone agent —— Converter Standalone Server会在Windows物理机上安装代理，从而将这些物理机作为虚拟机导入，完成后可以选择自动删除
- Converter Standalone client —— 与Converter服务端配合使用，包括看到的用户界面、创建和管理转换任务等
- Vmware vCenter Converter引导CD：是单独的组件，可用于在物理机上执行冷克隆

<!-- more -->

冷克隆可以创建一致的源计算机的精确副本，而我们更多的是进行热克隆，也就是源服务器在迁移过程中会继续工作，这就可能会出现某些文件不一致，但Converter Standalone会在热克隆后将目标虚拟机与与主机同步，同步执行过程是将在初始克隆期间更改的块从源复制到目标。

本文记录的过程是，源主机是 SUSE 11.x 物理机，运行华为的智能呼叫中心应用，因此安装有Oracle数据库，对于数据文件和控制文件的一致性和安全性较高，所以建议先把oracle数据库关闭再操作；目标虚拟服务器是 ESXi 5.1，但我使用的Converter是 5.5-en，操作过程类似。下面正式开始

源主机：172.30.31.0/24
ESXi: 172.29.88.0/24，与源主机IP段无法通信
Helper VM: 172.29.41.0/24，与上面两个IP段都通

## 1. 设置源和目的主机地址
![vmware-converter-0.png][0]

- Source System

选择你要转换的源系统，物理机为 Powered-on machine，填写其他登陆信息：
![vmware-converter-1.png][1]

- Destination System
填写要在哪个主机上创建虚拟机，也就是ESXi服务器地址:
![vmware-converter-2.png][2]
这两个过程有个简短的拉去主机信息的过程。

## 2. 选择目标虚拟机和存放位置
- Destination Virtual Machine
目标虚拟机名字默认是源hostname，不用选择folder：
![vmware-converter-3.png][3]

- Destination Location

选择新虚拟机要放在ESXi的哪个Datastore上，请确保有足够的磁盘空间，不能小于源系统实际使用的大小：
![vmware-converter-4.png][4]

## 3. 为转换任务设置其它选项
这一步尤为关键，直接关乎后面转换的成败。  

- Data to copy  
设置目标虚拟机的磁盘和分区，我们可以看到自动获取的源分区信息，我这里因为硬盘资源有限，没有遵循默认的 Maintain size，但比Minmun size（在源SUSE下 `df -h` 看到的used大小）大。
![vmware-converter-5.png][5]
CPU个数和内存大小默认也是与源主机保持一致。

- Network
网络设置这一块比较纠结。按理说源主机不需要与目的主机的网卡通信，只需要与Helper VM能互通即可，但我一直卡在这走不过去。源主机有2块网卡在使用，最后在这一步只设置了一块能ping同源主机的网卡，迁移完成后再手动添加剂一块网卡。如下是vmware官方知识库的Note：

> In the Conversion wizard, ensure to select the virtual machine portgroup when configuring the network card. This virtual machine portgroup must be connected to the physical network that is routable via port 22 (SSH) in both directions from the source Linux server's configured network IP address.
> The IP address entered must be routable to the IP address of the physical Linux source machine. Helper virtual machine IP address should able to ping the physical machine.

![vmware-converter-6-1.png][61]

图中看到VM Local是事先在vSphere Server上新建的端口组（portgroup），而且这个虚拟交换机vSwitch没有关联任何物理网卡：
![vmware-converter-exsi-1.png][11]

- Helper VM network
Helper VM是做转换时的一个临时操作系统，运行在目的主机上，从源主机拷贝数据。如果转化的时windows，则没有这个vm，取而代之的时再源主机上运行一个agent，所以转换windows要求ESXi与源主机能互通，而转换Linux则只需要设定的Helper VM network能与源主机22端口互通即可。
![vmware-converter-6-2.png][62]

## 4. 开始转换
可以看到转换的信息汇总，finish则开始迁移转换过程。
![vmware-converter-7.png][7]
![vmware-converter-8-1.png][81]
![vmware-converter-8-2.png][82]


测试在ESXi上可以看到会自动创建一台虚拟机并启动。等待转换完成。

## 5. 问题 ##
转换几次失败都是因为网络设置不当，转换到1%时报错：
![vmware-converter-9.png][9]

Error：event.ObtainHelperVmIpFailedEvent.summary

解决办法就是手动设置HelperVm的IP，并确保能够与源主机通信。如果继续报错，修改目标地址网卡设置，比如去除只剩一个网卡（后续添加），也设置成HelpVm网段。参考 [Convert: converter.fault.HelperVmFailedToObtainIpFault](http://kb.vmware.com/selfservice/microsites/search.do?language=en_US&cmd=displayKC&externalId=2033203) 。

转换Windows Server 2003时还有可能会出现 
```
Unable tp locate the required Sysprep files. Please upload them under 
c:\documents and settings\all users\application data\vmware\vmware vcenter converter standalone\sysprep\svr2003 
on the converter server machine
```
 解决办法是，需要下载[WindowsServer2003-KB926028-v2-x86-CHS.exe](http://download.microsoft.com/download/9/6/a/96a40c82-26ca-4b0d-840f-b08233548900/WindowsServer2003-KB926028-v2-x86-CHS.exe)，在cmd下执行WindowsServer2003-KB926028-v2-x86-CHS –x(不可以用winrar)，解压缩出来2个目录加一堆文件,在SP2QFE目录下找到deploy.cab，再将deploy.cab解压缩(winrar即可),得到10个文件,拷贝到所提示的 svr2003 目录。参考 [Sysprep文件位置和版本 (2040984)](http://kb.vmware.com/selfservice/microsites/search.do?language=en_US&cmd=displayKC&externalId=2040984)。
## 6. on windows ##
加入迁移的是windows主机，上面的操作略有不同，主要区别在于没有HelperVm，而是在需要转换的源主机上安装agent。所以要求ESXi与源主机必须能够直接通信才可以迁移。

参考：

- [操作VMware vCenter Converter 实现物理机迁移到虚拟机](http://yaabb163.blog.51cto.com/1975905/888856)
- [VMware vCenter Converter Standalone User's Guide 5.5](https://www.vmware.com/pdf/convsa_55_guide.pdf) （[中文](https://www.vmware.com/files/cn/pdf/support/vsp_vcc_42_admin_guide-PG-CN.pdf)）
- [VMware vCenter Converter Standalone 用户指南 中文4.3](http://www.vmware.com/files/cn/pdf/convsa_43_guide-PG-CN.pdf)



  [0]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-0.png
  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-1.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-2.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-3.png
  [4]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-4.png
  [5]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-5.png
  [61]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-6-1.png
  [62]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-6-2.png
  [11]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-exsi-1.png
  [7]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-7.png
  [81]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-8-1.png
  [82]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-8-2.png
  [9]: http://github.com/seanlook/sean-notes-comment/raw/main/static/vmware-converter-9.png
