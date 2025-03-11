---
title: Docker简介
date: 2014-12-18 11:21:25
aliases:
- /2014/12/18/docker-introduction/
updated: 2014-12-18 18:46:23
tags: [docker, linux]
categories: [Virtualization, Docker]
---

# 1. docker是什么 #

> Docker is an open-source engine that automates the deployment of any application as a lightweight, portable, self-sufficient container that will run virtually anywhere.

[Docker](https://www.docker.com/)是 PaaS 提供商[dotCloud](https://www.dotcloud.com/)开源的一个基于 LXC 的高级容器引擎， [源代码](https://github.com/docker/docker)托管在 Github 上, 基于go语言并遵从Apache2.0协议开源。Docker近期非常火热，无论是从 GitHub 上的代码活跃度，还是Redhat宣布在[RHEL7中正式支持Docker](http://server.cnw.com.cn/server-os/htm2014/20140616_303249.shtml)，都给业界一个信号，这是一项创新型的技术解决方案。就连 Google 公司的 Compute Engine 也支持 docker 在其之上运行，国内“BAT”先锋企业百度Baidu App Engine(BAE)平台也是[以Docker作为其PaaS云基础](http://blog.docker.com/2013/12/baidu-using-docker-for-its-paas/)。

Docker产生的目的就是为了解决以下问题：

1. 环境管理复杂：从各种OS到各种中间件再到各种App，一款产品能够成功发布，作为开发者需要关心的东西太多，且难于管理，这个问题在软件行业中普遍存在并需要直接面对。Docker可以简化部署多种应用实例工作，比如Web应用、后台应用、数据库应用、大数据应用比如Hadoop集群、消息队列等等都可以打包成一个Image部署。
2. 云计算时代的到来：AWS的成功，引导开发者将应用转移到云上, 解决了硬件管理的问题，然而软件配置和管理相关的问题依然存在 (AWS cloudformation是这个方向的业界标准, 样例模板可参考这里)。Docker的出现正好能帮助软件开发者开阔思路，尝试新的软件管理方法来解决这个问题。
3. 虚拟化手段的变化：云时代采用标配硬件来降低成本，采用虚拟化手段来满足用户按需分配的资源需求以及保证可用性和隔离性。然而无论是KVM还是Xen，在 Docker 看来都在浪费资源，因为用户需要的是高效运行环境而非OS，GuestOS既浪费资源又难于管理，更加轻量级的LXC更加灵活和快速。
![docker-traditional-virtualization][1]
![docker-virtualization][2]
4. LXC的便携性：LXC在 Linux 2.6 的 Kernel 里就已经存在了，但是其设计之初并非为云计算考虑的，缺少标准化的描述手段和容器的可便携性，决定其构建出的环境难于分发和标准化管理(相对于KVM之类image和snapshot的概念)。Docker就在这个问题上做出了实质性的创新方法。

Docker的主要特性如下：

1. 文件系统隔离：每个进程容器运行在完全独立的根文件系统里。
2. 资源隔离：可以使用cgroup为每个进程容器分配不同的系统资源，例如CPU和内存。
3. 网络隔离：每个进程容器运行在自己的网络命名空间里，拥有自己的虚拟接口和IP地址。
4. 写时复制：采用写时复制方式创建根文件系统，这让部署变得极其快捷，并且节省内存和硬盘空间。
5. 日志记录：Docker将会收集和记录每个进程容器的标准流（stdout/stderr/stdin），用于实时检索或批量检索。
6. 变更管理：容器文件系统的变更可以提交到新的映像中，并可重复使用以创建更多的容器。无需使用模板或手动配置。
7. 交互式Shell：Docker可以分配一个虚拟终端并关联到任何容器的标准输入上，例如运行一个一次性交互shell。

# 2. 比较 #
## 2.1 docker vs 传统虚拟化技术 ##
作为一种新兴的虚拟化方式，Docker 跟传统的虚拟化方式（xen、kvm、vmware）相比具有众多的优势。

<!-- more -->

首先，Docker 容器的启动可以在秒级实现，这相比传统的虚拟机方式要快得多。 其次，Docker 对系统资源的利用率很高，一台主机上可以同时运行数千个 Docker 容器。容器除了运行其中应用外，基本不消耗额外的系统资源，使得应用的性能很高，同时系统的开销尽量小。传统虚拟机方式运行 10 个不同的应用就要起 10 个虚拟机，而Docker 只需要启动 10 个隔离的应用即可。

具体说来，Docker 在如下几个方面具有较大的优势。
- 更快速的交付和部署
对开发和运维（devop）人员来说，最希望的就是一次创建或配置，可以在任意地方正常运行。
开发者可以使用一个标准的镜像来构建一套开发容器，开发完成之后，运维人员可以直接使用这个容器来部署代码。 Docker 可以快速创建容器，快速迭代应用程序，并让整个过程全程可见，使团队中的其他成员更容易理解应用程序是如何创建和工作的。 Docker 容器很轻很快！容器的启动时间是秒级的，大量地节约开发、测试、部署的时间。

- 更高效的虚拟化
Docker 容器的运行不需要额外的 hypervisor 支持，它是内核级的虚拟化，因此可以实现更高的性能和效率。
- 更轻松的迁移和扩展
Docker 容器几乎可以在任意的平台上运行，包括物理机、虚拟机、公有云、私有云、个人电脑、服务器等。 这种兼容性可以让用户把一个应用程序从一个平台直接迁移到另外一个。
更简单的管理

使用 Docker，只需要小小的修改，就可以替代以往大量的更新工作。所有的修改都以增量的方式被分发和更新，从而实现自动化并且高效的管理。

对比传统虚拟机总结：

特性  |  容器 | 虚拟机
----|----|----
启动  |  秒级  |  分钟级
硬盘使用 | 一般为 MB  |  一般为 GB
性能  |  接近原生  |  弱于
系统支持量 | 单机支持上千个容器  |  一般几十个

## 2.2 docker vs lxc ##
Docker以Linux容器LXC为基础，实现轻量级的操作系统虚拟化解决方案。在LXC的基础上Docker进行了进一步的封装，让用户不需要去关心容器的管理，使得操作更为简便，具体改进有：

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

# 3. docker应用场景 #
Docker作为一个开源的应用容器引擎，让开发者可以打包他们的应用以及依赖包到一个可移植的容器中，然后发布到任何流行的 Linux 机器上，也可以实现虚拟化。Docker可以自动化打包和部署任何应用、创建一个轻量级私有PaaS云、搭建开发测试环境、部署可扩展的Web应用等。这决定了它在企业中的应用场景是有限的，Docker将自己定位为“分发应用的开放平台”，其网站上也明确地提到了Docker的典型应用场景：

> - Automating the packaging and deployment of applications
> - Creation of lightweight, private PAAS environments
> - Automated testing and continuous integration/deployment
> - Deploying and scaling web apps, databases and backend services

对应用进行自动打包和部署，创建轻量、私有的PAAS环境，自动化测试和持续整合与部署，部署和扩展Web应用、数据库和后端服务。

平台即服务一般与大数据量系统同在，反观当前我司各IT系统，可以在以下情形下使用docker替代方案：

1. 结合vagrant或supervisor，搭建统一的开发、测试环境
多个开发人员共同进行一个项目，就必须保持开发环境完全一致，部署到测试环境、正式环境后，最好都是同一套环境，通过容器来保存状态，分发给开发人员或部署，可以让“代码在我机子上运行没有问题”这种说辞将成为历史。
2. 对memcached、mysql甚至tomcat，打包成一个个容器，避免重复配置
比如将一个稳定版本的、已配置完善的mysql，固化在一个镜像中，假如有新的环境要用到mysql数据库，便不需要重新安装、配置，而只需要启动一个容器瞬间完成。tomcat应用场景更多，可以将不同版本的jvm和tomcat打包分发，应用于多tomcat集群，或在测试服务器上隔离多个不同运行环境要求的测试应用（例如旧系统采用的是jdk6，新系统在jdk7上开发，但共用同一套测试环境）。

**docker不足**

- LXC是基于cgroup等linux kernel功能的，因此container的guest系统只能是linux base的
- 隔离性相比KVM之类的虚拟化方案还是有些欠缺，所有container公用一部分的运行库
- 网络管理相对简单，主要是基于namespace隔离
- cgroup的cpu和cpuset提供的cpu功能相比KVM的等虚拟化方案相比难以度量(所以dotcloud主要是安内存收费)
- container随着用户进程的停止而销毁，container中的log等用户数据不便收集

另外，Docker是面向应用的，其终极目标是构建PAAS平台，而现有虚拟机主要目的是提供一个灵活的计算资源池，是面向架构的，其终极目标是构建一个IAAS平台，所以它不能替代传统虚拟化解决方案。目前在容器可管理性方面，对于方便运维，提供UI来管理监控各个containers的功能还不足，还都是第三方实现如DockerUI、Dockland、Shipyard等。

# 4. docker组成部分 #
![docker_arch][3]

Docker使用客户端-服务器(client-server)架构模式。Docker客户端会与Docker守护进程进行通信。Docker守护进程会处理复杂繁重的任务，例如建立、运行、发布你的Docker容器。Docker客户端和守护进程可以运行在同一个系统上，当然你也可以使用Docker客户端去连接一个远程的Docker守护进程。Docker客户端和守护进程之间通过socket或者RESTful API进行通信。

更多内容请参考：[Docker核心技术预览](http://xgknight.com/2014/12/18/docker-core-technology-preview/) 及[docker常用管理命令](http://xgknight.com/2014/10/31/docker-command-best-use-1/)。

## 4.1 images（镜像）##
Docker 镜像就是一个只读的模板。例如，一个镜像可以包含一个完整的 ubuntu 操作系统环境，里面仅安装了 Apache 或用户需要的其它应用程序。
镜像可以用来创建 Docker 容器。
Docker 提供了一个很简单的机制来创建镜像或者更新现有的镜像，用户甚至可以直接从其他人那里下载一个已经做好的镜像来直接使用。

## 4.2 container（容器）##
Docker 利用容器来运行应用。容器是从镜像创建的运行实例。它可以被启动、开始、停止、删除。每个容器都是相互隔离的、保证安全的平台。可以把容器看做是一个简易版的 Linux 环境（包括root用户权限、进程空间、用户空间和网络空间等）和运行在其中的应用程序。
镜像是只读的，容器在启动的时候创建一层可写层作为最上层。

## 4.3 repository（仓库）##
仓库是集中存放镜像文件的场所。有时候会把仓库和仓库注册服务器（Registry）混为一谈，并不严格区分。实际上，仓库注册服务器上往往存放着多个仓库，每个仓库中又包含了多个镜像，每个镜像有不同的标签（tag）。

### 4.3.1 公开仓库###
docker团队控制的top-level的顶级repository，即[Docker Hub](https://registry.hub.docker.com/)，存放了数量庞大的镜像供用户下载，任何人都能读取，里面包含了许多常用的镜像，如ubuntu, mysql ,redis, python等。

### 4.3.2 个人公共库###
个人公共库也是被托管在Docker Hub上，网络上的其它用户也可以pull你的仓库（如`docker pull seanloook/centos6`）你可以在修改完自己的container之后，通过commit命令把它变成本地的一个image，push到自己的个人公共库。（在此之前你需要`docker login`登录，或者`vi ~/.dockercfg`。）

```
从镜像运行出一个容器
docker run -t -i 68edf809afe7 /bin/bash

记录下CONTAINER ID

docker ps -l
CONTAINER ID  IMAGE                       COMMAND  CREATED     STATUS  PORTS  NAMES
1528136ff541  172.29.88.222:5000/centos6:latest  /bin/bash  40 minutes ago Exited (0) ..  sad_mestorf


从将容器提交成一个新的image
(format is "sudo docker commit <container_id> <username>/<imagename>")
# docker commit -m " new images /docker.sean " -a "docker New" fcbd0a5348ca seanloook/centos6:test_tag_sean
fe022762070b09866eaab47bc943ccb796e53f3f416abf3f2327481b446a9503

docker images可以看到这个新的镜像

# docker images
REPOSITORY                  TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
seanloook/centos6           test_tag_sean       fe022762070b        About an hour ago   212.7 MB
sean:5000/library/centos6   latest              68edf809afe7        3 weeks ago         212.7 MB
```

在你commit为一个image后，通过push可以推送到个人公共registry中。此时需要login后才能push（当然没有设定login的Username，在第一次push时也会提示输入），接下来比较有意思。
```
# docker login https://index.docker.io/v1/
Username: seanloook
Password: 
Email: seanlook7@gmail.com
Login Succeeded
```
如果你已经有docker官网的账号，则只需要输入正确的用户名和密码就可以登录，邮箱不做验证；
如果所输入的Username不存在，则这一步便是自动从官网创建一个账号，并发送一封确认邮件，以后也可以从https://hub.docker.com/repos/ 登录。（是不是太简单了?）

login的同时，也会在~/.dockercfg中加入认证信息
```
# cat ~/.dockercfg
{"https://index.docker.io/v1/":{"auth":"c2Vhbmxvb29rOk15UGFzc3dvcmQ=","email":"seanlook7@gmail.com"}}
```
其中auth=base64(username:password)，base64编码与解码。

保存到个人公共库上，push可以是repos，格式`docker push <username>/<repo_name>`：

```
# docker push seanloook/centos6:test_tag_sean
The push refers to a repository [seanloook/centos6] (len: 1)
Sending image list
Pushing repository seanloook/centos6 (1 tags)
511136ea3c5a: Image already pushed, skipping
5b12ef8fd570: Image already pushed, skipping
68edf809afe7: Image already pushed, skipping
fe022762070b: Image successfully pushed
Pushing tag for rev [fe022762070b] on {https://cdn-registry-1.docker.io/v1/repositories/seanloook/centos6/tags/test_tag_sean}
```
上面的push操作也可以是`docker push seanloook/centos6`（但不能是`docker push fe022762070b`）。

这些镜像其他人也可以搜索得到`docker search seanloo`。


### 4.3.3 私有仓库###
首先与另外一种仓库区分——Docker Hub Private Repository，它简单理解为公网上的个人私有库，与上面的个人公共库相对应，在Docker Hub上Create Repository时选择Private便是，只有你自己才可以读写。

这里所说的私有仓库是指自己在本地服务器上搭建的专属自己的内部仓库`docker-registry`，俗称“私服”，供无法访问互联网的内部网络使用，或者镜像到本地一份以加快pull、push的速度。

它与公共仓库最明显的区分就是repository的命名，如必须使用带`.`的主机名或域名，后面必须接`:port`，如`sean.tp-link.net:5000/centos6:your_tag_name`，而公共仓库第一个斜杠前表示的是登录用户名。命名关系到推送到哪个服务器的哪个位置，更过内容可以关注[搭建docker内网私服（docker-registry with nginx&ssl on centos）](http://xgknight.com/2014/11/13/deploy-private-docker-registry-with-nginx-ssl/)。

## 4.4 运行一个容器的内部过程 ##
docker client告诉docker daemon运行一个容器，例如：`docker run -i -t ubuntu  /bin/bash`
让我们分解一下这个命令，docker client启动使用一个二进制的docker命令，最小的docker client需要你告诉docker daemon你的容器是从哪个docker镜像构建的，你希望在容器内部运行哪个命令。所以启动过程如下：

1. Pulling the ubuntu image
docker检查是否存在ubuntu镜像，如果本地不存在ubuntu镜像，则docker会到docker index下载。
2. Creates a new container
利用镜像创建容器
3. Allocates a filesystem and mounts a read-write layer
为镜像创建文件系统层和read-write层
4. Allocates a network / bridge interface
为容器创建网络接口，使容器和本地机器可以通讯
5. Sets up an IP address
在地址池中为容器分配一个可用的IP地址
6. Executes a process that you specify
运行你的应用
7. Captures and provides application output
连接log的标准输入、输出、错误，以使你直到你的应用是否正常运行

# 参考 #
- [深入浅出Docker（一）：Docker核心技术预览 ](http://www.infoq.com/cn/articles/docker-core-technology-preview)
- [Docker源码分析（一）：Docker架构](http://www.infoq.com/cn/articles/docker-source-code-analysis-part1)
- [Docker Architecture based on v1.3](http://www.slideshare.net/rajdeep/docker-architecturev2)
- [Docker简介与入门](http://www.pchou.info/open-source/2014/03/29/docker-introduction.html)


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/docker-traditional-virtualization.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/docker-virtualization.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/docker_arch.png
