---
title: 开源容器集群管理系统Kubernetes架构及组件介绍
date: 2015-02-03 13:21:25
aliases:
- /2015/02/03/docker-kubernetes-arch-introduction/
updated: 2014-02-03 15:46:23
tags: [docker, linux, kubernetes]
categories: [Virtualization, Docker]
---

本文来源于Infoq的一篇文章（见参考部分），并在难懂的地方自己理解的基础上做了修改。实际在ubuntu上部署 kubernetes 操作另见 [文章](http://xgknight.com/2015/02/07/docker-kubernetes-deploy2/) 。

> Together we will ensure that Kubernetes is a strong and open container management framework for any application and in any environment, whether in a private, public or hybrid cloud.  --Urs Hölzle, Google

[Kubernetes](https://github.com/GoogleCloudPlatform/kubernetes) 作为Docker生态圈中重要一员，是Google多年大规模容器管理技术的开源版本，是产线实践经验的最佳表现。如Urs Hölzle所说，无论是公有云还是私有云甚至混合云，Kubernetes将作为一个为任何应用，任何环境的容器管理框架无处不在。正因为如此，目前受到各大巨头及初创公司的青睐，如Microsoft、VMWare、Red Hat、CoreOS、Mesos等，纷纷加入给Kubernetes贡献代码。随着Kubernetes社区及各大厂商的不断改进、发展，Kuberentes将成为容器管理领域的领导者。

接下来我们一起探索Kubernetes是什么、能做什么以及怎么做。

# 1. 什么是Kubernetes #

Kubernetes是Google开源的容器集群管理系统，使用Golang开发，其提供应用部署、维护、扩展机制等功能，利用Kubernetes能方便地管理跨机器运行容器化的应用，其主要功能如下：

1. 使用Docker对应用程序包装(package)、实例化(instantiate)、运行(run)。
2. 以集群的方式运行、管理跨机器的容器。
3. 解决Docker跨机器容器之间的通讯问题。
4. Kubernetes的自我修复机制使得容器集群总是运行在用户期望的状态。

当前Kubernetes支持GCE、vShpere、CoreOS、OpenShift、Azure等平台，除此之外，也可以直接运行在物理机上。

这个官方给出的完整的架构图：（可在新标签页打开查看大图）

![kubernetes-architecture][1]

# 2. Kubernetes的主要概念 #
## 2.1 Pods ##
在Kubernetes系统中，调度的最小颗粒不是单纯的容器，而是抽象成一个Pod，Pod是一个可以被创建、销毁、调度、管理的最小的部署单元。把相关的一个或多个容器（Container）构成一个Pod，通常Pod里的容器运行相同的应用。Pod包含的容器运行在同一个Minion(Host)上，看作一个统一管理单元，共享相同的volumes和network namespace/IP和Port空间。

<!-- more -->

## 2.2 Services ##
Services也是Kubernetes的基本操作单元，是真实应用服务的抽象，每一个服务后面都有很多对应的容器来支持，通过Proxy的port和服务selector决定服务请求传递给后端提供服务的容器，对外表现为一个单一访问地址，外部不需要了解后端如何运行，这给扩展或维护后端带来很大的好处。

这一点github上的官网文档 [services.md](https://github.com/GoogleCloudPlatform/kubernetes/blob/master/docs/services.md) 讲的特别清楚。

## 2.3 Replication Controllers ##
Replication Controller，理解成更复杂形式的pods，它确保任何时候Kubernetes集群中有指定数量的pod副本(replicas)在运行，如果少于指定数量的pod副本(replicas)，Replication Controller会启动新的Container，反之会杀死多余的以保证数量不变。Replication Controller使用预先定义的pod模板创建pods，一旦创建成功，pod 模板和创建的pods没有任何关联，可以修改 pod 模板而不会对已创建pods有任何影响，也可以直接更新通过Replication Controller创建的pods。对于利用 pod 模板创建的pods，Replication Controller根据 label selector 来关联，通过修改pods的label可以删除对应的pods。Replication Controller主要有如下用法：

**Rescheduling**
如上所述，Replication Controller会确保Kubernetes集群中指定的pod副本(replicas)在运行， 即使在节点出错时。

**Scaling**
通过修改Replication Controller的副本(replicas)数量来水平扩展或者缩小运行的pods。

**Rolling updates**
Replication Controller的设计原则使得可以一个一个地替换pods来滚动更新（rolling updates）服务。

**Multiple release tracks**
如果需要在系统中运行multiple release的服务，Replication Controller使用labels来区分multiple release tracks。

以上三个概念便是用户可操作的REST对象。Kubernetes以RESTfull API形式开放的接口来处理。

## 2.4 Labels ##
service和replicationController只是建立在pod之上的抽象，最终是要作用于pod的，那么它们如何跟pod联系起来呢？这就引入了label的概念：label其实很好理解，就是为pod加上可用于搜索或关联的一组key/value标签，而service和replicationController正是通过label来与pod关联的。为了将访问Service的请求转发给后端提供服务的多个容器，正是通过标识容器的labels来选择正确的容器；Replication Controller也使用labels来管理通过 pod 模板创建的一组容器，这样Replication Controller可以更加容易，方便地管理多个容器。

如下图所示，有三个pod都有label为"app=backend"，创建service和replicationController时可以指定同样的label:"app=backend"，再通过label selector机制，就将它们与这三个pod关联起来了。例如，当有其他frontend pod访问该service时，自动会转发到其中的一个backend pod。
![kubernetes-label][2]

# 3. Kubernetes构件 #

Kubenetes整体框架如下图，主要包括kubecfg、Master API Server、Kubelet、Minion(Host)以及Proxy。
![kubernetes-simple][3]

## 3.1 Master ##

Master定义了Kubernetes 集群Master/API Server的主要声明，包括Pod Registry、Controller Registry、Service Registry、Endpoint Registry、Minion Registry、Binding Registry、RESTStorage以及Client, 是client(Kubecfg)调用Kubernetes API，管理Kubernetes主要构件Pods、Services、Minions、容器的入口。Master由API Server、Scheduler以及Registry等组成。从下图可知Master的工作流主要分以下步骤：

1. Kubecfg将特定的请求，比如创建Pod，发送给Kubernetes Client。
2. Kubernetes Client将请求发送给API server。
3. API Server根据请求的类型，比如创建Pod时storage类型是pods，然后依此选择何种REST Storage API对请求作出处理。
4. REST Storage API对的请求作相应的处理。
5. 将处理的结果存入高可用键值存储系统Etcd中。
6. 在API Server响应Kubecfg的请求后，Scheduler会根据Kubernetes Client获取集群中运行Pod及Minion信息。
7. 依据从Kubernetes Client获取的信息，Scheduler将未分发的Pod分发到可用的Minion节点上。

![kubernetes-restfull][4]
下面是Master的主要构件的详细介绍。

### 3.1.1 Minion Registry ###
Minion Registry负责跟踪Kubernetes 集群中有多少Minion(Host)。Kubernetes封装Minion Registry成实现Kubernetes API Server的RESTful API接口REST，通过这些API，我们可以对Minion Registry做Create、Get、List、Delete操作，由于Minon只能被创建或删除，所以不支持Update操作，并把Minion的相关配置信息存储到etcd。除此之外，Scheduler算法根据Minion的资源容量来确定是否将新建Pod分发到该Minion节点。

可以通过`curl http://{master-apiserver-ip}:4001/v2/keys/registry/minions/`来验证etcd中存储的内容。

### 3.1.2 Pod Registry ###
Pod Registry负责跟踪Kubernetes集群中有多少Pod在运行，以及这些Pod跟Minion是如何的映射关系。将Pod Registry和Cloud Provider信息及其他相关信息封装成实现Kubernetes API Server的RESTful API接口REST。通过这些API，我们可以对Pod进行Create、Get、List、Update、Delete操作，并将Pod的信息存储到etcd中，而且可以通过Watch接口监视Pod的变化情况，比如一个Pod被新建、删除或者更新。

### 3.1.3 Service Registry ###
Service Registry负责跟踪Kubernetes集群中运行的所有服务。根据提供的Cloud Provider及Minion Registry信息把Service Registry封装成实现Kubernetes API Server需要的RESTful API接口REST。利用这些接口，我们可以对Service进行Create、Get、List、Update、Delete操作，以及监视Service变化情况的watch操作，并把Service信息存储到etcd。

### 3.1.4 Controller Registry ###
Controller Registry负责跟踪Kubernetes集群中所有的Replication Controller，Replication Controller维护着指定数量的pod 副本(replicas)拷贝，如果其中的一个容器死掉，Replication Controller会自动启动一个新的容器，如果死掉的容器恢复，其会杀死多出的容器以保证指定的拷贝不变。通过封装Controller Registry为实现Kubernetes API Server的RESTful API接口REST， 利用这些接口，我们可以对Replication Controller进行Create、Get、List、Update、Delete操作，以及监视Replication Controller变化情况的watch操作，并把Replication Controller信息存储到etcd。

### 3.1.5 Endpoints Registry ###
Endpoints Registry负责收集Service的endpoint，比如Name："mysql"，Endpoints: ["10.10.1.1:1909"，"10.10.2.2:8834"]，同Pod Registry，Controller Registry也实现了Kubernetes API Server的RESTful API接口，可以做Create、Get、List、Update、Delete以及watch操作。

### 3.1.6 Binding Registry ###
Binding包括一个需要绑定Pod的ID和Pod被绑定的Host，Scheduler写Binding Registry后，需绑定的Pod被绑定到一个host。Binding Registry也实现了Kubernetes API Server的RESTful API接口，但Binding Registry是一个write-only对象，所有只有Create操作可以使用， 否则会引起错误。

### 3.1.7 Scheduler ###
Scheduler收集和分析当前Kubernetes集群中所有Minion节点的资源(内存、CPU)负载情况，然后依此分发新建的Pod到Kubernetes集群中可用的节点。由于一旦Minion节点的资源被分配给Pod，那这些资源就不能再分配给其他Pod， 除非这些Pod被删除或者退出， 因此，Kubernetes需要分析集群中所有Minion的资源使用情况，保证分发的工作负载不会超出当前该Minion节点的可用资源范围。具体来说，Scheduler做以下工作：

1. 实时监测Kubernetes集群中未分发的Pod。
2. 实时监测Kubernetes集群中所有运行的Pod，Scheduler需要根据这些Pod的资源状况安全地将未分发的Pod分发到指定的Minion节点上。
3. Scheduler也监测Minion节点信息，由于会频繁查找Minion节点，Scheduler会缓存一份最新的信息在本地。
4. 最后，Scheduler在分发Pod到指定的Minion节点后，会把Pod相关的信息Binding写回API Server。

## 3.2 Kubelet ##
![kubernetes-kubelet][5]
根据上图可知Kubelet是Kubernetes集群中每个Minion和Master API Server的连接点，Kubelet运行在每个Minion上，是Master API Server和Minion之间的桥梁，接收Master API Server分配给它的commands和work，与持久性键值存储etcd、file、server和http进行交互，读取配置信息。Kubelet的主要工作是管理Pod和容器的生命周期，其包括Docker Client、Root Directory、Pod Workers、Etcd Client、Cadvisor Client以及Health Checker组件，具体工作如下：

1. 通过Worker给Pod异步运行特定的Action
2. 设置容器的环境变量
3. 给容器绑定Volume
4. 给容器绑定Port
5. 根据指定的Pod运行一个单一容器
6. 杀死容器
7. 给指定的Pod创建network 容器
8. 删除Pod的所有容器
9. 同步Pod的状态
10. 从cAdvisor获取container info、 pod info、 root info、 machine info
11. 检测Pod的容器健康状态信息
12. 在容器中运行命令。

## 3.3 Proxy ##
Proxy是为了解决外部网络能够访问跨机器集群中容器提供的应用服务而设计的，运行在每个Minion上。Proxy提供TCP/UDP sockets的proxy，每创建一种Service，Proxy主要从etcd获取Services和Endpoints的配置信息（也可以从file获取），然后根据配置信息在Minion上启动一个Proxy的进程并监听相应的服务端口，当外部请求发生时，Proxy会根据Load Balancer将请求分发到后端正确的容器处理。

所以Proxy不但解决了同一主宿机相同服务端口冲突的问题，还提供了Service转发服务端口对外提供服务的能力，Proxy后端使用了随机、轮循负载均衡算法。关于更多 kube-proxy 的内容 [KUBERNETES代码走读之MINION NODE 组件 KUBE-PROXY](http://www.sel.zju.edu.cn/?p=484) 。

# 4. etcd #
[etcd](https://github.com/coreos/etcd)在上面架构图上提到过几次，但它并不是kubernetes的一部分，它是 CoreOS 团队发起的一个管理配置信息和服务发现（service discovery）项目，目标是构建一个高可用的分布式键值（key-value）数据库。与kubernetes和docker一样还是在快速迭代开发中的产品，没有ZooKeeper那样成熟。有机会再另外通过文章介绍。


**参考**

- [Kubernetes系统架构简介](http://www.infoq.com/cn/articles/Kubernetes-system-architecture-introduction)
- [An Introduction to Kubernetes](https://www.digitalocean.com/community/tutorials/an-introduction-to-kubernetes)
- [Kubernetes-DESIGN](https://github.com/GoogleCloudPlatform/kubernetes/blob/master/DESIGN.md) （[Kubernetes 设计概要](http://my.oschina.net/kakablue/blog/278038)）
- [怎样构建一个容器集群](http://dockerone.com/article/173)

  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/kubernetes-architecture.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/kubernetes-label.jpg
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/kubernetes-simple.png
  [4]: http://github.com/seanlook/sean-notes-comment/raw/main/static/kubernetes-restfull.png
  [5]: http://github.com/seanlook/sean-notes-comment/raw/main/static/kubernetes-kubelet.png
