---
title: 在Mac在Mac/win7下上使用Vagrant打造本地开发环境
date: 2015-03-25 11:21:25
updated: 2015-03-27 18:46:23
tags: [vagrant, virtualbox, 虚拟化,开发环境]
categories: Virtualization
---

# 1. vagrant介绍 #
## 1.1 vagrant能做什么 ##
做Web开发（java/php/python/ruby...）少不了要在本地搭建好开发环境，虽然说目前各种脚本/语言都有对应的Windows版，甚至是一键安装包，但很多时候和Windows环境的兼容性（如配置文件、编译的模块）并不是那么好，麻烦的问题是实际部署的环境通常是Linux，常常还要面临着开发和部署环境不一致，上线前还要大量的调试。而如果让每个开发人员都自己去搭建本地环境，安装虚拟机、下载ISO镜像、选择规格安装创建vm、安装OS、配置，会耗费非常多的时间，如果是团队开发应该要尽量保持每个人的运行环境一致。此时vagrant正式你所需要的。不适用正式环境部署。

vagrant实际上一套虚拟机管理工具，基于Ruby开发，底层支持VirtualBox、VMware甚至AWS、docker等作为虚拟化系统。我们可以通过 Vagrant 封装一个 Linux 的开发环境，分发给团队成员。成员可以在自己喜欢的桌面系统（Mac/Windows/Linux）上开发程序，代码却能统一在封装好的环境里运行，“代码在我机子上运行没有问题”这种说辞将成为历史。

通过上面的介绍如果你还在困惑有virtualbox或vmware为什么还要加入vagrant，纠结于要不要使用，可以参考这个问答 [使用vagrant的意义在哪](http://segmentfault.com/q/1010000002623455)，另外docker作为后起之秀也可以做vagrant能完成的事情，stackoverflow有关于两位作者讨论各自应用场景的精彩"互掐"，[传送门→](http://stackoverflow.com/questions/16647069/should-i-use-vagrant-or-docker-io-for-creating-an-isolated-environment) （[中文](http://www.cnblogs.com/vikings-blog/p/3973265.html)）。

## 1.2 几个概念 ##

- `Provider`：供应商，在这里指Vagrant调用的虚拟化工具。Vagrant本身并没有能力创建虚拟机，它是调用一些虚拟化工具来创建，如VirtualBox、VMWare、Xen、Docker，甚至AWS，这些虚拟化工具只要安装好了，vagrant会自动封装在底层通过统一的命令调用。也就是说使用vagrant时你电脑上还需要安装对应的Provider，默认是免费开源的virtualbox。

<!-- more -->

- `Box`：可被Vagrant直接使用的虚拟机镜像文件，大小根据内容的不同从200M-2G不等。针对不同的Provider，Box文件的格式是不一样的，从 [vagrantcloud.com](https://atlas.hashicorp.com/boxes/search?utm_source=vagrantcloud.com&vagrantcloud=1) 你可以找到社区维护的box。

- `Vagrantfile`：Vagrant根据Vagrantfile中的配置来创建虚拟机，是Vagrant的核心。在Vagrantfile文件中你需要指明使用哪个Box（可以下载好的或自己制作，或指定在线的URL地址），虚拟机使用的内存大小和CPU，需要预安装哪些软件，虚拟机的网络配置，与host的共享目录等。

- `Provisioner`：是Vagrant的插件的一种。大部分现成的box并不是你正好想要的，通过使用你熟悉的provisioner，比如`Puppet`，可以在你使用`vagrant up`启动虚拟机时自动的安装软件、修改配置等初始化操作。当然你也可以在最先启动虚拟机后，使用`vagrant ssh`进去然后手动安装软件，但毕竟不是所有人都是系统管理员，写好Vagrantfile后无需人工干预马上就可以使用vm。目前支持并实现的provisioning有Puppet、Salt、Ansible、Chef这些知名的自动化运维工具，当然需要一定的使用经验；也可以使用shell provisioner，故名思议这个插件就是通过执行shell命令完成统一的作用。

- `Guest Additions`：这个是常在下载 base box 介绍里有的，一般用来实现host到vm的端口转发、目录共享，在开发环境上都建议装上以便测试。

# 2. 安装vagrant #
- VirtualBox: 4.3.12，https://www.virtualbox.org/wiki/Download_Old_Builds_4_3 。我上手使用的是4.3.20，折腾出过几个问题，据说说4.3.12版本较稳定。
建议选择VirtualBox ，即使你电脑上已经安装VMware Workstation或Fushion，它的vagrant插件还是要收费的
- Vagrant: 1.7.1，http://www.vagrantup.com/downloads-archive.html

选择适合你的平台（Windows、Mac、Linux），下载对应格式的安装包。如Mac下 vagrant_1.7.1.dmg、VirtualBox-4.3.20-96997-OSX.dmg 。

# 3. 使用vagrant打造一个本地开发环境 #
本文将会演示从 [nrel CentOS6.5](https://atlas.hashicorp.com/nrel/boxes/CentOS-6.5-x86_64) 开始，安装必要的开发包、python、插件、Puppet，然后打包成一个box分发给团队的全过程。你也可以在别人box的基础上进一步通过Vagrantfile定制自己的环境。

## 3.1 初始化 ##
### 3.1.1 vagrant box add {box-name} {box-url} ###
```
$ vagrant box add ct65_00 Downloads/centos65.box 
==> box: Adding box 'ct65_00' (v0) for provider: 
    box: Downloading: file:///Users/sean/Downloads/centos65.box
==> box: Successfully added box 'ct65_00' (v0) for 'virtualbox'!

$ ll ~/.vagrant.d/boxes/ct65_00
$ vagrant box list

# vagrant box list
ct65_00   (virtualbox, 0)
centos64-i386  (virtualbox, 0)
```
这一条命令就是根据给出的box（镜像）文件地址，解压一份到用户目录`~/.vagrant.d/boxes/{box-name}/0/virtualbox/`下，所以你尽量应该以同一用户来管理进行vagrant所有操作。

*F\**K GFW*
在GFW保护之下，这简单获取box文件反而一开始就难到我们了。官方提供的在线安装在墙外是极为方便的，`vagrant box add minimal/centos6`便自动从`vagrantcloud.com`(现更名为`https://atlas.hashicorp.com/search/boxes`)下载，直接进入第二步。

还有一种方法是，先`vagrant init minimal/centos6`，然后直接启动`vagrant up --provider virtualbox`。当然这些都与下载boxes到本地效果是一样的，下载方法就是在vagrantcloud.com上点开你所需要的box版本，然后再URL里加入`/providers/virtualbox.box`便得到文件地址，如 https://atlas.hashicorp.com/hashicorp/boxes/precise64 对应的文件为 https://atlas.hashicorp.com/hashicorp/boxes/precise64/providers/virtualbox.box 。

在墙内直接在线安装启动box，会报错：
```
The box 'ubuntu/trusty64' could not be found or
could not be accessed in the remote catalog. If this is a private
box on HashiCorp's Atlas, please verify you're logged in via
`vagrant login`. Also, please double-check the name. The expanded
URL and error message are shown below:

URL: ["https://atlas.hashicorp.com/ubuntu/trusty64"]
Error:
```
一个办法是ubuntu来 http://uec-images.ubuntu.com/vagrant/ 下载，centos来 http://nrel.github.io/vagrant-boxes/ 下载。我也从墙外下了几个典型的box放到了自己的百度云上共享了:http://pan.baidu.com/s/1sjHQBa1 。

*2015-04-01更新：无意间发现现在不用梯子也可以访问了，Happy April Fool's Day!*

### 3.1.2 vagrant init {box-name} ###
```
$ mkdir ~/vagrant && cd ~/vagrant  //这个目录的目的就是统一管理你的Vagrantfile
$ vagrant init ct65_00
A `Vagrantfile` has been placed in this directory. You are now
ready to `vagrant up` your first virtual environment! Please read
the comments in the Vagrantfile as well as documentation on
`vagrantup.com` for more information on using Vagrant.

$ vi Vagrantfile
...
Vagrant.configure(2) do |config|
  config.vm.box = "ct65_00"
  onfig.vm.network "forwarded_port", guest: 80, host: 8080
#  config.vm.synced_folder "../data", "/vagrant_data"
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "384"
    vb.cpus = 1
  end
  config.vm.hostname = "vg-ct65_00.tp-link.net"
...
```
init只是在当前目录生成一个`Vagrantfile`文件和`.vagrant/`目录，可以对它进行修改，比如定义 vm guest machine 的hostname、memory、cpu等，具体有关语法介绍见后文。

用户后面`up`虚拟机，这个 box-name 与上面add的相同，如果是 base 则可以省略。

## 3.2 启动虚拟机 ##
```
# vagrant up
Bringing machine 'default' up with 'virtualbox' provider...
==> default: Importing base box 'ct65_00'...
==> default: Matching MAC address for NAT networking...
==> default: Setting the name of the VM: v-box_default_1427284884787_97348
==> default: Clearing any previously set network interfaces...
==> default: Preparing network interfaces based on configuration...
    default: Adapter 1: nat
==> default: Forwarding ports...
    default: 22 => 2222 (adapter 1)
==> default: Booting VM...
==> default: Waiting for machine to boot. This may take a few minutes...
    default: SSH address: 127.0.0.1:2222
    default: SSH username: vagrant
    default: SSH auth method: private key
    default: Warning: Connection timeout. Retrying...
    default: Warning: Connection timeout. Retrying...
    ...
    default: Warning: Remote connection disconnect. Retrying...
    default: Warning: Remote connection disconnect. Retrying...
==> default: Machine booted and ready!
==> default: Checking for guest additions in VM...
==> default: Mounting shared folders...
    default: /vagrant => /root/vagrant/v-box/ct65_00
```
up过程是默认会根据当前目录下的Vagrantfile来启动vm，如果当前目录没有Vagrantfile，则去上层目录寻找，依次类推。第一次`vagrant up ct65_00`时会从`~/.vagrant.d/boxes`中导入相应的box文件到`~/VirtualBox VMs/`，可以通过`vboxmanage showvminfo {VM-ID}`看到该虚拟机的配置（Mac上为VBoxManage）。如果你想让虚拟机存储在指定位置，如我的Mac SSD硬盘空间贵，可以运行VirtualBox，手动设置存储/storage的路径。

默认 localhost:2222 转发到 guest:22 以供ssh连接；用户名/密码：vagrant/vagrant；默认共享目录就是host上Vagrantfile所在目录；如果电脑配置比较低导致启动时间比较长，或者VirtualBox启动出错，可能会提示上面的 [Connection timeout](http://stackoverflow.com/questions/22575261/vagrant-stuck-connection-timeout-retrying) 。

另外提示一下，某次我在Linux上测试，由于Linux host本身也是vSphere虚拟机，通过vagrant启动virtualbox另一个虚拟机（即嵌套），一直Retrying，后来根据上面 stackoverflow 打开了VBox GUI，发现是CPU架构的问题，一直堵塞，所以就不建议虚拟机上再装虚拟机了：
```
VT-x/AMD-V hardware acceleration is not available on your system. Your 64-bit guest will fail to detect a 64-bit CPU and will not be able to boot.
```

## 3.2 连接虚拟机，初始化环境 ##
### vagrant ssh ###
```
$ vagrant ssh
Last login: Tue Mar 31 02:15:38 2015 from 10.0.2.2
Welcome to your Vagrant-built virtual machine.
```
一般建立box时约定的用户名/密码：vagrant/vagrant，root密码也是 vagrant，默认的网络连接方式是Host-Only。

### 定制你的环境 ###
如安装jdk，创建用户，解压tomcat，修改server.xml，添加yum源等。这里一步到位，唯一要说明的是tomcat conf/server.xml 的
`<Context path="" docBase="/vagrant_data" reloadable="true" >...`应用目录设置为共享目录。

## 3.3 打包成box ##
### 3.3.1 安装必要软件 ###
打包是为了分发出去，做扩展用
```
# yum install -y lrzsz telnet vim puppet puppetmaster
```
如果你是从0开始建立一个box，当然还需要创建vagrant用户以及public key，具体可以参考[如何制作一个vagrant的base box](http://blog.csdn.net/samxx8/article/details/38943395)。

### 3.3.2 安装Virtualbox Guest Additions ###

每个人电脑上安装的Virtualbox版本很可能不一样，`vagrant up`可能会有提示版本不兼容（同一大版本号还好，可省略这一步），导致host到guest共享目录模块失败，最终无法启动虚拟机。

安装方法可以有 [vagrant-vbguest](https://github.com/dotless-de/vagrant-vbguest)（注意这是vagrant插件，不是virtualbox插件），使用超级详细，只需执行`vagrant plugin install vagrant-vbguest`，默认从本地找 VBoxGuestAdditions.iso （各平台路径一般都可以找到），如果没找到则去`http://download.virtualbox.org/virtualbox/%{version}/VBoxGuestAdditions_%{version}.iso` 下载，直接启动vm便可安装或更新virtualbox guest additions ，甚至可以通过`vagrant vbguest`命令给正在运行的vm安装，缺点是 plugin install 得连网。下面是手动在vm内部安装：

一般最小化的box不带有CDROM，需要通过VirtualBox图形化界面添加一个DVD/CD存储设备，然后在启动VM后 Devices -> Insert Guest Additions CD 。（相信你可以可以找到办法直接挂载 .iso 文件到vm里面，免去添加多余设备）

> for linux : /usr/share/virtualbox/VBoxGuestAdditions.iso
> for Mac : /Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso
> for Windows : %PROGRAMFILES%/Oracle/VirtualBox/VBoxGuestAdditions.iso

```
$ sudo yum install linux-headers-$(uname -r) build-essential dkms 
$ sudo mount /dev/cdrom /media/cdrom
$ sudo sh /media/cdrom/VBoxLinuxAdditions.run --nox11
```
官方参考：http://docs.vagrantup.com/v2/virtualbox/boxes.html

### 3.3.3 vagrant package ###
打包导出：
```
 vagrant package --output sean-vg-ct65_ts.box
==> default: Attempting graceful shutdown of VM...
==> default: Clearing any previously set forwarded ports...
==> default: Exporting VM...
==> default: Compressing package to: /Users/sean/vagrant/sean-vg-ct65_ts.box
```
当前目录下若存在同名package.box则会export失败。打包的来源并不是`.vagrant.d`而是VirtualBox虚拟机本身，可以通过`--base vm-name`来指定所导出的虚拟机名称，`--vagrantfile file-pathname`可以将Vagrantfile直接封进box中。以后就可以把这个 .box 文件分发给开发人员使用了。

# 4. 其他 #

## 4.1 命令 ##

`vagrant suspend`将虚拟机置于休眠状态。这时候主机会保存虚拟机的当前状态。再用vagrant up启动虚拟机时能够返回之前工作的状态。这种方式优点是休眠和启动速度都很快，只有几秒钟。缺点是需要额外的磁盘空间来存储当前状态。

`vagrant halt`则是关机。如果想再次启动还是使用vagrant up命令，不过需要多花些时间。

`vagrant destroy`则会将虚拟机从磁盘中删除。如果想重新创建还是使用vagrant up命令。

`vagrant reload`从Vagrantfile重新启动虚拟机。

`vagrant global-status`输出所有虚拟机当前运行状态，关机、已启动等。

另外1.2以上版本的Vagrant还引用了插件机制。可以通过vagrant plugin来添加各种各样的plugin，这给Vagrant的应用带来了更大的灵活性和针对性。比如可以添加vagrant-windows的插件来增加对windows系统的支持，通过添加vagrant-aws插件来实现给AWS创建虚拟机的功能。你也可以编写自己的插件。由于Vagrant是ruby写的一个gem，其插件的编写也是使用的Ruby语言。

关于 Vagrantfile说明以及网络、多机器管理的配置，见 [Varantfile说明](http://xgknight.com/2015/04/01/vagrantfile/)。

## 4.2 问题集 ##

- 选用配置略高一点的电脑做host，否则启动会相当慢而且会提示`Warning: Connection timeout. Retrying...`，如果在300s内没有boot up，你可能需要启用GUI界面可以帮我们诊断一些启动失败的问题，`vb.gui = true`。坚决不要在虚拟机里玩vagrant！

- 不要轻易在VirtualBox图形界面下强行关闭虚拟机，可能会出现意想不到的错误，如 The guest machine entered an invalid state while waiting for it
to boot. Valid states are 'starting, running'. The machine is in the
'poweroff' state ... 针对这个问题的解决办法，[issue 2175](https://github.com/mitchellh/vagrant/issues/2157) 没能搞定，直接destroy重来。

- 我在ubuntu trustry 64-bit 安装virtualbox时，提示依赖没装（libgl1-mesa-glx libqt4-network libqt4-opengl libqtcore4 libqtgui4 libxcursor1 libxinerama1 libxmu6 libxt6），
使用`apt-get install libqt4-opengl`来安装上面的依赖，如果报错`The following packages have unmet dependencies...`，执行`apt-get -f install` 解决。

- 安装 virtualbox guest additions 失败
在 3.3.2节安装Virtualbox Guest Additions时，运行`./media/cdrom/VBoxLinuxAdditions.run`后提示：

```
The headers for the current running kernel were not found. If the following module 
compilation fails then this could be the reason. The missing package can be probably
 installed with yum install kernel-devel-2.6.32-431.el6.x86_64

Building the main Guest Additions module                   [FAILED]
...
```
关机后启动虚拟机，相应的会提示：
```
Failed to mount folders in Linux guest. This is usually because the "vboxsf" file 
system is not available. Please verify that the guest additions are properly 
installed in the guest and can work properly. The command attempted was:


mount -t vboxsf -o uid=id -u vagrant,gid=getent group vagrant | cut -d: -f3 vagrant /vagrant
mount -t vboxsf -o uid=id -u vagrant,gid=id -g vagrant vagrant /vagrant

The error output from the last command was:

/sbin/mount.vboxsf: mounting failed with the error: No such device
```
原因就是旧版本卸载成功但新版本guest additions却因为`yum install kernel-devel`找不到软件包（No package available）失败。这种情况很少见，kernel-devel 一般都可以装上去解决。如果像我这样提示死活没这个软件包的，换个box吧！

- 硬盘扩容
进入到虚拟机后，通过`df -h`你可能看到磁盘空间不足，需要扩容（不允许缩小空间），就可以通过以下方法完成。

  1. 手动方式，与是否使用vagrant无关
halt关闭虚拟机虚拟机后，使用 `VBoxManage modifyhd box-disk1.vdi --resize 10240` 即完成修改。但是如果虚拟机磁盘格式创建时使用的是vmdk，则不支持直接vmdk格式修改，需要通过`VBoxManage clonehd box_disk1.vmdk box_disk2.vdi --format VDI`转换成vdi格式，然后在图形化VirtualBox中选择这个新的磁盘。另外提醒一句，这里的扩容是修改动态分配的磁盘的虚拟大小而不是实际大小，所以假如resize后的值比预分配的磁盘要小的话，会提示 Progress state: VBOX_E_NOT_SUPPORTED ..VBoxManage: error: Resize hard disk operation for this format is not implemented yet! 
相关参考：[Resizing disk space on vagrant box](http://stackoverflow.com/questions/14917353/resizing-disk-space-on-vagrant-box)、
[VirtualBox VBOX_E_NOT_SUPPORTED Drive Resize Error](http://www.streamwave.com/systems-administration/how-to-extend-your-virtualbox-virtual-hard-drive/)、[Resize a Hard Disk for a Virtual Machine](https://gist.github.com/christopher-hopper/9755310) 。

  2. 通过Vagrantfile指令修改
```
  config.vm.provider "virtualbox" do |vb|
    vb.customize 'pre-boot', ['modifyhd', 'e91678c3-b49b-489b-b280-4e138533252d', '--resize', '10240']
  end
```
上面那串数字字母，是虚拟磁盘的UUID，可以先通过`ps -ef|grep Virtual`(Mac, `virtualbox` in Linux )查到虚拟机UUID，再通过`VBoxManage showvminfo {VM UUID}|grep vdi`看到这个 disk UUID。参考 [Add some way to increase disk space from Vagrantfile](https://github.com/mitchellh/vagrant/issues/2339)。
扩容完成后把Vagrantfile中对应的部分去掉，以免每次启动都进行这步操作。

- [Hello Vagrant](http://www.cnblogs.com/huang0925/p/3349841.html)
- [使用 Vagrant 打造跨平台开发环境](http://segmentfault.com/a/1190000000264347)
- [Vagrant安装配置](https://github.com/astaxie/Go-in-Action/blob/master/ebook/zh/01.2.md)
- [Creating a Base Box](http://docs.vagrantup.com/v2/virtualbox/boxes.html)
- [如何制作一个vagrant的base box](http://blog.csdn.net/samxx8/article/details/38943395)
- http://blog.icodeu.com/?tag=vagrant
