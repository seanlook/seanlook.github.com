title: 【转+改】Docker核心技术预览
date: 2014-12-18 13:21:25
updated: 2014-12-18 15:46:23
tags: [docker, linux, lxc, cgroup, aufs]
categories: [Virtualization, Docker]
---

本文简单介绍docker使用到的部分核心技术，但不做深入探究，因为每一个技术都是一个独立的项目，有机会再分别详细介绍。
来源地址：http://www.infoq.com/cn/articles/docker-core-technology-preview

![docker-core-tech](http://sean-images.qiniudn.com/docker-core-tech.png)

## Linux Namespace （实例隔离）##
> The purpose of each namespace is to wrap a particular global system resource in an abstraction that makes it appear to the processes within the namespace that they have their own isolated instance of the global resource.

每个用户实例之间相互隔离，互不影响。一般的硬件虚拟化方法给出的方法是VM，而LXC给出的方法是container，更细一点讲就是kernel namespace。其中pid、net、ipc、mnt、uts、user等namespace将container的进程、网络、消息、文件系统、UTS("UNIX Time-sharing System")和用户空间隔离开。

- **pid namespace**

不同用户的进程就是通过pid namespace隔离开的，且不同 namespace 中可以有相同pid。所有的LXC进程在docker中的父进程为docker进程，每个lxc进程具有不同的namespace。同时由于允许嵌套，因此可以很方便的实现 Docker in Docker。

![docker-kernel-pid-namespace.png][1]

<!-- more -->

- ** net namespace **

有了 pid namespace, 每个namespace中的pid能够相互隔离，但是网络端口还是共享host的端口。网络隔离是通过net namespace实现的， 每个net namespace有独立的 network devices, IP addresses, IP routing tables, `/proc/net` 目录。这样每个container的网络就能隔离开来。LXC在此基础上有5种网络类型，docker默认采用veth的方式将container中的虚拟网卡同host上的一个docker bridge—docker0连接在一起。

- ** ipc namespace **

container中进程交互还是采用linux常见的进程间交互方法(interprocess communication - IPC), 包括常见的信号量、消息队列和共享内存。然而与VM不同，container 的进程间交互实际上还是host上具有相同pid namespace中的进程间交互，因此需要在IPC资源申请时加入namespace信息 - 每个IPC资源有一个唯一的 32bit ID。

- ** mnt namespace **

类似`chroot`，将一个进程放到一个特定的目录执行。mnt namespace允许不同namespace的进程看到的文件结构不同，这样每个 namespace 中的进程所看到的文件目录就被隔离开了。同`chroot不同，每个namespace中的container在`/proc/mounts`的信息只包含所在namespace的mount point。

- ** uts namespace **

UTS("UNIX Time-sharing System") namespace允许每个container拥有独立的hostname和domain name, 使其在网络上可以被视作一个独立的节点而非Host上的一个进程。

- ** user namespace **

每个container可以有不同的 user 和 group id, 也就是说可以以container内部的用户在container内部执行程序而非Host上的用户。

有了以上6种namespace从进程、网络、IPC、文件系统、UTS和用户角度的隔离，一个container就可以对外展现出一个独立计算机的能力，并且不同container从OS层面实现了隔离。 然而不同namespace之间资源还是相互竞争的，仍然需要类似ulimit来管理每个container所能使用的资源——LXC 采用的是cgroup。

**参考**

- [PaaS under the hood, episode 1: kernel namespaces](http://blog.dotcloud.com/under-the-hood-linux-kernels-on-dotcloud-part)， [[中文]](https://github.com/dockercn/docs/blob/master/paas-under-the-hood-episode-1-kernel-namespaces.md)
- http://blog.blackwhite.tw/2013/12/docker.html

## cgroup （资源配额） ##
cgroups 实现了对资源的配额和度量。cgroups 的使用非常简单，提供类似文件的接口，在 `/cgroup`目录下新建一个文件夹即可新建一个group，在此文件夹中新建`task`文件，并将pid写入该文件，即可实现对该进程的资源控制。具体的资源配置选项可以在该文件夹中新建子`subsystem`，`{子系统前缀}.{资源项}` 是典型的配置方法， 如`memory.usage_in_bytes`就定义了该group 在subsystem memory中的一个内存限制选项。

我们主要关心cgroups可以限制哪些资源，即有哪些subsystem是我们关心。

- **cpu**
在cgroup中，并不能像硬件虚拟化方案一样能够定义CPU能力，但是能够定义CPU轮转的优先级，因此具有较高CPU优先级的进程会更可能得到CPU运算。 通过将参数写入cpu.shares,即可定义改cgroup的CPU优先级 - 这里是一个相对权重，而非绝对值。当然在cpu这个subsystem中还有其他可配置项，手册中有详细说明。

- **cpuacct**
产生cgroup任务的cpu资源报告

- **cpuset**
cpusets 定义了有几个CPU可以被这个group使用，或者哪几个CPU可以供这个group使用。在某些场景下，单CPU绑定可以防止多核间缓存切换，从而提高效率

- **memory**
设置每个cgroup的内存限制以及产生内存资源报告

- **blkio**
block IO相关的统计和限制，byte/operation统计和限制(IOPS等)，读写速度限制等，但是这里主要统计的都是同步IO

- **net_cls**
标记每个网络包以供cgroup方便使用

- **devices**
允许或拒绝cgroup任务对设备的访问

- **freezer**
暂停和恢复cgroup任务

**参考**

- [PaaS Under the Hood, Episode 2: cgroups](http://blog.dotcloud.com/kernel-secrets-from-the-paas-garage-part-24-c)
- https://www.kernel.org/doc/Documentation/cgroups/
- http://en.wikipedia.org/wiki/Cgroups

## LXC（LinuX Container） ##
> LXC (LinuX Container) is an operating system-level virtualization method for running multiple isolated Linux systems (containers) on a single control host. This is accomplished through kernel level isolation.

借助于namespace的隔离机制和cgroup限额功能，LXC提供了一套统一的API和工具来建立和管理container，LXC利用了如下 kernel 的特性：

- Kernel namespaces (ipc, uts, mount, pid, network and user)
- Apparmor and SELinux profiles (security)
- Seccomp policies
- Chroots (using pivot_root)
- Kernel capabilities
- Control groups (cgroups)

LXC 旨在提供一个共享kernel的 OS 级虚拟化方法，在执行时不用重复加载Kernel，且container的kernel与host共享，因此可以大大加快container的 启动过程，并显著减少内存消耗。

这篇[stackoverflow](http://stackoverflow.com/questions/17989306/what-does-docker-add-to-just-plain-lxc)上的问题和答案很好地诠释了Docker和LXC的区别，能够让你更好的了解什么是Docker， 简单翻译下就是以下几点：

1. Portable deployment across machines
Docker提供了一种可移植的配置标准化机制，允许你一致性地在不同的机器上运行同一个Container；而LXC本身可能因为不同机器的不同配置而无法方便地移植运行；
2. Application-centric 
Docker以App为中心，为应用的部署做了很多优化，而LXC的帮助脚本主要是聚焦于如何机器启动地更快和耗更少的内存；
3. Automatic build 
Docker为App提供了一种自动化构建机制（Dockerfile），包括打包，基础设施依赖管理和安装等等；
4. Versioning
Docker提供了一种类似git的Container版本化的机制，允许你对你创建过的容器进行版本管理，依靠这种机制，你还可以下载别人创建的Container，甚至像git那样进行合并；
5. Component reuse
Docker Container是可重用的，依赖于版本化机制，你很容易重用别人的Container（叫Image），作为基础版本进行扩展；
6. Sharing 
Docker Container是可共享的，有点类似github一样，Docker有自己的INDEX，你可以创建自己的Docker用户并上传和下载Docker Image；
7. Tool ecosystem
Docker提供了很多的工具链，形成了一个生态系统；这些工具的目标是自动化、个性化和集成化，包括对PAAS平台的支持等。

**参考**

- http://linuxcontainers.org/
- http://en.wikipedia.org/wiki/LXC
- http://marceloneves.org/papers/pdp2013-containers.pdf (性能测试)
- http://article.sciencepublishinggroup.com/pdf/10.11648.j.ajnc.20130204.11.pdf



## AUFS ##

Docker对container的使用基本是建立在LXC基础之上的，然而LXC存在的问题是难以移动——难以通过标准化的模板制作、重建、复制和移动 container。在以VM为基础的虚拟化手段中，有image和snapshot可以用于VM的复制、重建以及移动的功能。想要通过container来实现快速的大规模部署和更新, 这些功能不可或缺。Docker正是利用AUFS来实现对container的快速更新——在docker0.7中引入了storage driver, 支持AUFS, VFS, device mapper, 也为BTRFS以及ZFS引入提供了可能。

AUFS (Another Union FS) 是一种 Union FS，简单来说就是支持将不同目录挂载到同一个虚拟文件系统下(unite several directories into a single virtual filesystem)的文件系统, 更进一步的理解, AUFS支持为每一个成员目录（类似Git Branch）设定readonly、readwrite 和 whiteout-able 权限, 同时 AUFS 里有一个类似分层的概念, 对 readonly 权限的 branch 可以逻辑上进行修改(增量地, 不影响 readonly 部分的)。通常 Union FS 有两个用途, 一方面可以实现不借助 LVM、RAID 将多个disk挂到同一个目录下, 另一个更常用的就是将一个 readonly 的 branch 和一个 writeable 的 branch 联合在一起，Live CD正是基于此方法可以允许在 OS image 不变的基础上允许用户在其上进行一些写操作。Docker 在 AUFS 上构建的 container image 也正是如此，接下来我们从启动 container 中的 linux 为例来介绍 docker 对AUFS特性的运用。

典型的启动Linux运行需要两个FS: bootfs + rootfs：

![docker-filesystems-generic][2]

bootfs（boot file system）主要包含 bootloader 和 kernel, bootloader主要是引导加载kernel, 当boot成功后 kernel 被加载到内存中后 bootfs就被umount了。rootfs (root file system) 包含的就是典型 Linux 系统中的 `/dev`, `/proc`, `/bin`, `/etc`等标准目录和文件。

由此可见对于不同的linux发行版, bootfs基本是一致的, rootfs会有差别, 因此不同的发行版可以公用bootfs 如下图：

![docker-filesystems-multiroot][3]

典型的Linux在启动后，首先将 rootfs 置为 readonly，进行一系列检查，然后将其切换为 "readwrite" 供用户使用。在docker中，起初也是将 rootfs 以readonly方式加载并检查，然而接下来利用 union mount 的将一个 readwrite 文件系统挂载在 readonly 的rootfs之上，并且允许再次将下层的 file system设定为readonly 并且向上叠加，这样一组readonly和一个writeable的结构构成一个container的运行目录，每一个被称作一个Layer。如下图：

![docker-filesystems-multilayer][4]


得益于AUFS的特性，每一个对readonly层文件/目录的修改都只会存在于上层的writeable层中。这样由于不存在竞争，多个container可以共享readonly的layer。所以docker将readonly的层称作 "image"——对于container而言整个rootfs都是read-write的，但事实上所有的修改都写入最上层的writeable层中，image不保存用户状态，可以用于模板、重建和复制。

![docker-filesystems-debian.png][5]
![docker-filesystems-debianrw.png][6]

上层的image依赖下层的image，因此docker中把下层的image称作父image，没有父image的image称作base image。

因此想要从一个image启动一个container，docker会先加载其父image直到base image，用户的进程运行在writeable的layer中。所有parent image中的数据信息以及 ID、网络和lxc管理的资源限制等具体container的配置，构成一个docker概念上的container。如下图：

![docker-filesystems-busyboxrw.png][7]

由此可见，采用AUFS作为docker的container的文件系统，能够提供如下好处:

1. 节省存储空间：多个container可以共享base image存储
2. 快速部署：如果要部署多个container，base image可以避免多次拷贝
3. 内存更省：因为多个container共享base image, 以及OS的disk缓存机制，多个container中的进程命中缓存内容的几率大大增加
4. 升级更方便：相比于 copy-on-write 类型的FS，base-image也是可以挂载为可writeable的，可以通过更新base image而一次性更新其之上的container
5. 允许在不更改base-image的同时修改其目录中的文件：所有写操作都发生在最上层的writeable层中，这样可以大大增加base image能共享的文件内容。

以上5条 1-3 条可以通过 copy-on-write 的FS实现，4可以利用其他的union mount方式实现, 5只有AUFS实现的很好，这也是为什么Docker一开始就建立在AUFS之上。

由于AUFS并不会进入linux主干 (According to Christoph Hellwig, linux rejects all union-type filesystems but UnionMount.), 同时要求kernel版本3.0以上(docker推荐3.8及以上)，因此在RedHat工程师的帮助下在docker0.7版本中实现了driver机制, AUFS只是其中的一个driver, 在RHEL中采用的则是Device Mapper的方式实现的container文件系统。

**参考**

- [PAAS Under the Hood, Episode 3: AUFS](http://blog.dotcloud.com/kernel-secrets-from-the-paas-garage-part-34-a)
- http://docs.docker.com/terms/layer/
- http://docs.docker.com/terms/filesystem/

## 全文参考 ##

- http://tiewei.github.io/cloud/Docker-Getting-Start/
- https://docker.cn/a/1
- http://blog.dotcloud.com/category/under-the-hood
- http://www.slideshare.net/BodenRussell/realizing-linux-containerslxc


  [1]: http://sean-images.qiniudn.com/docker-kernel-pid-namespace.png
  [2]: http://sean-images.qiniudn.com/docker-filesystems-generic.png
  [3]: http://sean-images.qiniudn.com/docker-filesystems-multiroot.png
  [4]: http://sean-images.qiniudn.com/docker-filesystems-multilayer.png
  [5]: http://sean-images.qiniudn.com/docker-filesystems-debian.png
  [6]: http://sean-images.qiniudn.com/docker-filesystems-debianrw.png
  [7]: http://sean-images.qiniudn.com/docker-filesystems-busyboxrw.png


