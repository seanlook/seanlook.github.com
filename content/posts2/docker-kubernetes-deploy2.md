---
title: 在ubuntu上部署Kubernetes管理docker集群示例
date: 2015-02-07 13:21:25
updated: 2014-02-07 15:46:23
tags: [docker, linux, kubernetes]
categories: [Virtualization, Docker]
---

本文通过实际操作来演示Kubernetes的使用，因为环境有限，集群部署在本地3个ubuntu上，主要包括如下内容：

- 部署环境介绍，以及Kubernetes集群逻辑架构
- 安装部署Open vSwitch跨机器容器通信工具
- 安装部署Etcd和Kubernetes的各大组件
- 演示Kubernetes管理容器和服务

关于 Kubernetes 系统架构及组件介绍见[这里](http://xgknight.com/2015/02/03/docker-kubernetes-arch-introduction/)。

# 1. 部署环境及架构 #

- vSphere: 5.1
- 操作系统: ubuntu 14.04 x86_64
- Open vSwith版本: 2.0.2
- Kubernetes: v0.7.2
- Etcd版本: 2.0.0-rc.1
- Docker版本: 1.4.1
- 服务器信息：

| Role      | Hostname   | IP Address    |
| --------- | ---------- | ------------- |
| APIServer | kubernetes | 172.29.88.206 |
| Minion    | minion1    | 172.29.88.207 |
| Minion    | minion2    | 172.29.88.208 |

在详细介绍部署Kubernetes集群前，先给大家展示下集群的逻辑架构。从下图可知，整个系统分为两部分，第一部分是Kubernetes APIServer，是整个系统的核心，承担集群中所有容器的管理工作；第二部分是minion，运行Container Daemon，是所有容器栖息之地，同时在minion上运行Open vSwitch程序，通过GRE Tunnel负责minions之间Pod的网络通信工作。
![kubernetes-deploy][1]

<!-- more -->

# 2. 安装Open vSwitch及配置GRE #
为了解决跨minion之间Pod的通信问题，我们在每个minion上安装Open vSwtich，并使用GRE或者VxLAN使得跨机器之间P11od能相互通信，本文使用GRE，而VxLAN通常用在需要隔离的大规模网络中。对于Open vSwitch的介绍请参考另一篇文章[Open vSwitch](http://)。
```
sudo apt-get install openvswitch-switch bridge-utils
```

安装完Open vSwitch和桥接工具后，接下来便建立minion0和minion1之间的隧道。首先在minion1和minion2上分别建立OVS Bridge：
```
# ovs-vsctl add-br obr0
```

接下来建立gre，并将新建的gre0添加到obr0，在minion1上执行如下命令：
```
# ovs-vsctl add-port obr0 gre0 -- set Interface gre0 type=gre options:remote_ip=172.29.88.208
```
上面的remoute_ip是另一台服务minion2上的对外IP。

在minion2上执行：
```
# ovs-vsctl add-port obr0 gre0 -- set Interface gre0 type=gre options:remote_ip=172.29.88.207
```

至此，minion1和minion2之间的隧道已经建立。然后我们在minion1和minion2上创建Linux网桥kbr0替代Docker默认的docker0（我们假设minion1和minion2都已安装Docker），设置minion1的kbr0的地址为172.17.1.1/24， minion2的kbr0的地址为172.17.2.1/24，并添加obr0为kbr0的接口，以下命令在minion1和minion2上执行：
```
# brctl addbr kbr0              //创建linux bridge代替docker0
# brctl addif kbr0 obr0         //添加obr0为kbr0的接口

# ip link set dev docker0 down  //设置docker0为down状态
# ip link del dev docker0       //删除docker0，可选
```

查看这些接口的状态：
```
# service openvswitch-switch status
# ovs-vsctl show
9d248403-943c-41c0-b2d0-3f9b130cdd3f
    Bridge "obr0"
        Port "gre0"
            Interface "gre0"
                type: gre
                options: {remote_ip="172.29.88.207"}
        Port "obr0"
            Interface "obr0"
                type: internal
    ovs_version: "2.0.2"

# brctl show
bridge name	bridge id		STP enabled	interfaces
docker0		8000.56847afe9799	no		
kbr0		8000.620ff7ee9c49	no		obr0
```

为了使新建的kbr0在每次系统重启后任然有效，我们在minion1的`/etc/network/interfaces`文件中追加内容如下：（在CentOS上会有些不一样）
```
# vi /etc/network/interfaces
auto kbr0
iface kbr0 inet static
        address 172.17.1.1
        netmask 255.255.255.0
        gateway 172.17.1.0
        dns-nameservers 172.31.1.1
```

同样在minion2上追加类似内容，只需修改address为172.17.2.1和gateway为172.17.2.0即可，然后执行`ip link set dev kbr0 up`，你能在minion1和minion2上发现kbr0都设置了相应的IP地址。为了验证我们创建的隧道是否能通信，我们在minion1和minion2上相互ping对方kbr0的IP地址，从下面的结果发现是不通的，经查找这是因为在minion1和minion2上缺少访问172.17.1.1和172.17.2.1的路由，因此我们需要添加路由保证彼此之间能通信：
```
minion1上执行:
# ip route add 172.17.2.0/24 via 172.29.88.208 dev eth0

minion2上执行:
# ip route add 172.17.1.0/24 via 172.29.88.207 dev eth0
```

现在可以ping通对方的虚拟网络了：
```
$ ping 172.17.2.1
PING 172.17.2.1 (172.17.2.1) 56(84) bytes of data.
64 bytes from 172.17.2.1: icmp_seq=1 ttl=64 time=0.334 ms
64 bytes from 172.17.2.1: icmp_seq=2 ttl=64 time=0.253 ms
^C
--- 172.17.2.1 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 999ms
rtt min/avg/max/mdev = 0.253/0.293/0.334/0.043 ms
```
下面安装 Kubernetes APIServer 及kubelet、proxy等服务。

# 3. 安装Kubernetes APIServer #

## 3.1 下载安装kubernetes各组件 ##
可以自己从源码编译kubernetes（需要安装golang环境），也可以从[GitHub Kubernetes repo release page.](https://github.com/GoogleCloudPlatform/kubernetes/releases)选择编译好的二进制版本（v0.7.2）下载，为了方便后面启动或关闭kubernetes组件，我们同时下载二进制包和源码包：
```
# cd /usr/local/src
# wget https://github.com/coreos/etcd/releases/download/v2.0.0-rc.1/etcd-v2.0.0-rc.1-linux-amd64.tar.gz
# wget https://github.com/GoogleCloudPlatform/kubernetes/releases/download/v0.7.2/kubernetes.tar.gz
# wget https://github.com/GoogleCloudPlatform/kubernetes/archive/v0.7.2.zip
```

然后解压下载的kubernetes和etcd包，并在kubernetes(minion1)、minion2上创建目录`/opt/bin`
```
# mkdir /opt/bin        //这一步APIserver和所有minions上都要创建

解压kubernetes
src# tar xf kubernetes.tar.gz
# ll 
drwxr-xr-x  3  501 staff     4096 Dec 19 02:32 etcd-v2.0.0-rc.1-linux-amd64/
-rw-r--r--  1 root root   6223584 Jan  6 14:39 etcd-v2.0.0-rc.1-linux-amd64.tar.gz
drwxr-xr-x  7 root root      4096 Nov 20 06:35 kubernetes/
-rw-r--r--  1 root root  82300483 Jan  6 14:37 kubernetes.tar.gz
-rw-r--r--  1 root root  9170754 Jan  9 14:47 v0.7.2.zip

# cd kubernetes/server
# tar xf kubernetes-server-linux-amd64.tar.gz
# cd kubernetes/server/bin/

APIserver本身需要的是kube-apiserver kube-scheduler kube-controller-manager kubecfg四个
# cp -a kube* /opt/bin/

把proxy和kubelet复制到其他minions，确保这些文件都是可执行的
# scp kube-proxy kubelet root@172.29.88.207:/opt/bin
# scp kube-proxy kubelet root@172.29.88.208:/opt/bin
```
`/opt/bin`并没有加入系统`PATH`，所以`kube-apiserver -version`是看不到结果，但在后面配置的服务中会自动加入（`PATH=$PATH:/opt/bin`）。

## 3.2 解压安装etcd ##
`etcd`在这里的作用是服务发现存储仓库，通俗的来讲就是记录kubernetes启动了多少pods、services、replicationController以及它们的信息等，详细介绍见[这里](http//)。此外版本2.0与v0.4.6在启动参数上的写法有一定差别。

    # tar xf etcd-v2.0.0-rc.1-linux-amd64.tar.gz && cd etcd-v2.0.0-rc.1-linux-amd64/
    # cp -a etcd etcdctl /opt/bin

## 3.3 配置kube-apiserver等为upstart脚本启动 ##
这一步主要是为了管理kube-apiserver等进程的方便，避免每次都手动启动各服务、添加冗长的启动参数选项，而且在不同的系统平台下kubernetes已经提供了相应的工具。
```
解压kubernetes*源码包*
src# unzip xf v0.7.2.zip && cd kubernetes-0.7.2

这里比较奇怪的是最新release版本源码的cluster目录下是有ubuntu子目录的，但latest之前的下载后没有ubuntu目录
# cd cluster/ubuntu
# ll
.. 2 root root 4096 Jan  8 17:39 default_scripts/   各组件默认启动参数
.. 2 root root 4096 Jan  8 17:39 init_conf/         upstart启动方式
.. 2 root root 4096 Jan  8 17:39 initd_scripts/     service启动方式，与upstart选其一
.. 1 root root 1213 Jan  8 08:53 util.sh*     

# ./util.sh
```

`util.sh`脚本就是把当前目录下的service/upstart脚本、默认参数配置文件复制到`/etc`下，可以通过`service etcd start`的形式管理kubernetes。由于kubernetes更新速度极快，项目的文件和目录结构经常变化，请找准文件。接下来我们需要修改那些只适合本机使用的默认参数。（请注意备份先，因为后面能否正常跨机器管理docker与这些选项有关，特别是IP）
```
etcd官方建议使用新的2379端口代替4001
# vi /etc/default/etcd
ETCD_OPTS="-listen-client-urls=http://0.0.0.0:4001"

# vi /etc/default/kube-apiserver
KUBE_APISERVER_OPTS="--address=0.0.0.0 \
--port=8080 \
--etcd_servers=http://127.0.0.1:4001 \
--logtostderr=true \
--portal_net=11.1.1.0/24"

# vi /etc/default/kube-scheduler
KUBE_SCHEDULER_OPTS="--logtostderr=true \
--master=127.0.0.1:8080"

# vi /etc/default/kube-controller-manager
KUBE_CONTROLLER_MANAGER_OPTS="--master=127.0.0.1:8080 \
--machines=172.29.88.207,172.29.88.208 \
--logtostderr=true"


* 复制kubelet、kube-proxy等到minion1：
# scp /etc/default/{kubelet,kube-proxy} 172.29.88.207:/etc/default/
# scp /etc/init.d/{kubelet,kube-proxy} 172.29.88.207:/etc/init.d/
# scp /etc/init/{kubelet.conf,kube-proxy.conf} 172.29.88.207:/etc/init/
```

```
* 在minion1端进行
# vi /etc/default/kubelet
KUBELET_OPTS="--address=172.29.88.207 \
--port=10250 \
--hostname_override=172.29.88.207 \
--etcd_servers=http://172.29.88.206:4001 \
--logtostderr=true"

# vi /etc/default/kube-proxy
KUBE_PROXY_OPTS="--etcd_servers=http://172.29.88.207:4001 \
--logtostderr=true"

(对minion2重复上面 * 两个步骤，把上面.207改成.208)
```
上面的各配置文件就是对应命令的选项，具体含义使用`-h`。这里只简单说明：

1. `etcd`服务APIserver和minions都要访问，也就是其他组件的`--etcd_servers`值（带http前缀）
2. `kube-apiserver`监听在8080端口，也就是其他组件的`--master`值；`--portal_net`地址段不能与docker的桥接网卡kbr0重复，指定docker容器的IP段
3. `etcd`、`kube-apiserver`、`kube-scheduler`、`kube-controller-manager`运行在apiserver（服务）端，`kubelet`、`kube-proxy`运行在minion（客户端）
4. `kube-controller-manager`使用预先定义pod模板创建pods，保证指定数量的replicas在运行，默认监听在master的127.0.0.1:10252
5. `kubelet`默认监听端口10250，也正是apiserver的`--kubelet_port`的值

## 3.4 启动 ##

**重启docker**
接下来重启minion1、minion2上的Docker daemon（注意使用的网桥）：

    # docker -d -b kbr0

由于后面的测试可能需要在线下载images，所以如果你的服务器无法访问docker hub，上面启动时记得设置`HTTP_PROXY`代理。

**启动apiserver**

    # service etcd start
    # service kube-apiserver start

`kube-apiserver`启动后会自动运行`kube-scheduler`、`kube-controller-manager`，但修改配置后依然可以单独重启各个服务如`service kube-contoller-manager restart`。这些服务的日志可以从`/var/log/upstart/kube*`找到。

**在minion1、minion2上启动kubelet、kube-proxy**：
    
    # service kubelet start
    # service kube-proxy start

# 4. 使用kubecfg部署测试应用 #
为了方便，我们使用Kubernetes提供的例子[Guestbook](https://github.com/GoogleCloudPlatform/kubernetes/tree/master/examples/guestbook)（下载的源码example目录下可以找到）来演示Kubernetes管理跨机器运行的容器，下面我们根据Guestbook的步骤创建容器及服务。在下面的过程中如果是第一次操作，可能会有一定的等待时间，状态处于pending，这是因为第一次下载images需要一段时间。

## 4.1 创建redis-master Pod和redis-master服务 ##
配置管理操作都在apiserver上执行，并且都是基于实现编写好的json格式。涉及到下载docker镜像的部分，如果没有外网，可能需要修改image的值或使用自己搭建的docker-registry：
```
# cd kubernetes-0.7.2/examples/guestbook/
# cat redis-master.json
{
  "id": "redis-master",
  "kind": "Pod",
  "apiVersion": "v1beta1",
  "desiredState": {
    "manifest": {
      "version": "v1beta1",
      "id": "redis-master",
      "containers": [{
        "name": "master",
        "image": "dockerfile/redis",
        "cpu": 100,
        "ports": [{
          "containerPort": 6379,
          "hostPort": 6379
        }]
      }]
    }
  },
  "labels": {
    "name": "redis-master"
  }
}

# kubecfg -h http://172.29.88.206:8080 -c redis-master.json create pods
# kubecfg -h http://172.29.88.206:8080 -c redis-master-service.json create services
```

完成上面的操作后，我们可以看到如下redis-master Pod被调度到172.29.88.207：
（下面直接list实际上是省略了`-h http://127.0.0.1:8080`）
```
# kubecfg list pods
Name             Image(s)            Host               Labels              Status
----------       ----------          ----------         ----------          ----------
redis-master     dockerfile/redis    172.29.88.207/     name=redis-master   Running

查看services：
# kubecfg list services
Name            Labels                                    Selector            IP            Port
----------      ----------                                ----------          ----------    ------
kubernetes      component=apiserver,provider=kubernetes                       11.1.1.233    443
kubernetes-ro   component=apiserver,provider=kubernetes                       11.1.1.204    80
redis-master    name=redis-master                         name=redis-master   11.1.1.175    6379
```
发现除了redis-master的服务之外，还有两个Kubernetes系统默认的服务kubernetes-ro和kubernetes。而且我们可以看到每个服务都有一个服务IP及相应的端口，对于服务IP，是一个虚拟地址，根据apiserver的`portal_net`选项设置的`CIDR`表示的IP地址段来选取，在我们的集群中设置为11.1.1.0/24。为此每新创建一个服务，apiserver都会在这个地址段中随机选择一个IP作为该服务的IP地址，而端口是事先确定的。对redis-master服务，其服务地址为11.1.1.175，端口为6379，与minion主机映射的端口也是6379。

## 4.2 创建redis-slave Pod和redis-slave服务 ##
```
# kubecfg -h http://172.29.88.206:8080 -c redis-slave-controller.json create replicationControllers
# kubecfg -h http://172.29.88.206:8080 -c redis-slave-service.json create services
```
注意上面的`redis-slave-controller.json`有个`"replicas": 2`、`"hostPort": 6380`，因为我们的集群中只有2个minions，如果为3的话，就会导致有2个Pod会调度到同一台minion上，产生端口冲突，有一个Pod会一直处于pending状态，不能被调度（可以通过日志看到原因）。

```
# kubecfg list pods
Name                 Image(s)                     Host             Labels                                       Status
----------           ----------                   ----------       ----------                                   --------
2c2a06...c2971614d   brendanburns/redis-slave     172.29.88.208/   name=redisslave,uses=redis-master            Running
2c2ad5...c2971614d   brendanburns/redis-slave     172.29.88.207/   name=redisslave,uses=redis-master            Running
redis-master         dockerfile/redis             172.29.88.207/   name=redis-master                            Running

# kubecfg list services
Name              Labels                                    Selector            IP                  Port
----------        ----------                                ----------          ----------          --------
kubernetes        component=apiserver,provider=kubernetes                       11.1.1.233          443
kubernetes-ro     component=apiserver,provider=kubernetes                       11.1.1.204          80
redis-master      name=redis-master                         name=redis-master   11.1.1.175          6379
redisslave        name=redisslave                           name=redisslave     11.1.1.131          6379
```

## 4.3 创建Frontend Pod和Frontend服务 ##
前面2步都是guestbook的redis数据存储，现在部署应用：(修改`frontend-controller.json`的`replicas`为2)
```
# kubecfg -h http://172.29.88.206:8080 -c frontend-controller.json create replicationControllers
# kubecfg -h http://172.29.88.206:8080 -c frontend-service.json create services
```
```
# kubecfg -h http://172.29.88.206:8080 list pods
Name                 Image(s)                                 Host              Labels                                       Status
----------           ----------                               ----------        ----------                                   ----------
2c2a06...c2971614d   brendanburns/redis-slave                 172.29.88.208/    name=redisslave,uses=redis-master            Running
2c2ad5...c2971614d   brendanburns/redis-slave                 172.29.88.207/    name=redisslave,uses=redis-master            Running
d87744...c2971614d   kubernetes/example-guestbook-php-redis   172.29.88.207/    name=frontend,uses=redisslave,redis-master   Running
redis-master         dockerfile/redis                         172.29.88.207/    name=redis-master                            Running
1370b9...c2971614d   kubernetes/example-guestbook-php-redis   172.29.88.208/    name=frontend,uses=redisslave,redis-master   Running

# kubecfg -h http://172.29.88.206:8080 list services
Name             Labels                                    Selector            IP            Port
----------       ----------                                ----------          ----------    ------
redis-master     name=redis-master                         name=redis-master   11.1.1.175    6379
redisslave       name=redisslave                           name=redisslave     11.1.1.131    6379
frontend         name=frontend                             name=frontend       11.1.1.124    80
kubernetes       component=apiserver,provider=kubernetes                       11.1.1.233    443
kubernetes-ro    component=apiserver,provider=kubernetes                       11.1.1.204    80
```
通过查看可知 Frontend Pod 也被调度到两台minion，服务IP为11.1.1.124，端口是80，映射到外面minions的端口为8000（可以通过`ps -ef|grep docker-proxy`发现）。

## 4.4 其他操作（更新、删除、查看） ##
**删除**
除此之外，你可以删除Pod、Service，如删除minion1上的redis-slave Pod：

    kubecfg -h http://172.29.88.206:8080 delete pods/2c2ad505-96fd-11e4-9c0b-000c2971614d
    Status
    ----------
    Success

格式为`services/服务Name`、`pods/pods名字`，不必关心从哪个minion上删除了。需要提醒的是，这里pods的replcas为2，所以即使删除了这个pods，kubernetes为自动为你重新启动一个。

**更新**
更新ReplicationController的Replicas数量：
```
# kubecfg list replicationControllers
Name                   Image(s)                                 Selector            Replicas
----------             ----------                               ----------          ----------
frontendController     kubernetes/example-guestbook-php-redis   name=frontend       2
redisSlaveController   brendanburns/redis-slave                 name=redisslave     2
```
把frontendController的Replicas更新为1，则这行如下命令，然后再通过上面的命令查看frontendController信息，发现Replicas已变为1：

    kubecfg -h http://172.29.88.206:8080 resize frontendController 1

**查看**
Kubernetes内置提供了一个简单的UI来查看pods、services、replicationControllers，但极其简陋，暂时可以忽略，访问`http://172.29.88.206:8080/static/#/groups//selector/`：
![kubernetes-simpleui][5]

在浏览器访问api：`http://172.29.88.206:8080/api/v1beta1/replicationControllers` 。
![kubernetes-api][2]

etcd做服务发现，可以通过api访问其内容，访问`http://172.29.88.206:4001/v2/keys/registry/services/endpoints/default` ，得到json格式数据。

## 4.5 演示guestbook ##
通过上面的结果可知当前提供前端服务的PHP和提供数据存储的后端服务Redis master的Pod分别运行在172.29.88.208和172.29.88.207上，即容器运行在不同主机上，还有Redis slave也运行在两台不同的主机上，它会从Redis master同步前端写入Redis master的数据。下面我们从两方面验证Kubernetes能提供跨机器间容器的通信：

**浏览器访问留言簿**
在浏览器打开`http://${IPAddress}:8000`，IPAddress为PHP容器运行的minion的IP地址，其暴漏的端口为8000，这里IP_Address为172.29.88.208。打开浏览器会显示如下信息：
![kubernetes-guestbook1][3]

你可以输入信息并提交，然后Submit按钮下方会显示你输入的信息：
![kubernetes-guestbook2][4]
由于前端PHP容器和后端Redis master容器分别在两台minion上，因此PHP在访问Redis master服务时一定得跨机器通信，可见Kubernetes的实现方式避免了用link只能在同一主机上实现容器间通信的缺陷。

**从redis后端验证**
我们从后端数据层验证不同机器容器间的通信。根据上面的输出结果发现Redis slave和Redis master分别调度到两台不同的minion上，在172.29.88.207主机上执行`docker exec -ti e5941db7e424 /bin/sh`，e5941db7e424 master的容器ID（`docker ps`），进入容器后通过redis-cli命令查看从浏览器输入的信息如下：
```
# docker exec -ti e5941db7e424 /bin/sh
# redis-cli
127.0.0.1:6379> keys *
1) "messages"
127.0.0.1:6379> get messages
",Hi, Sean,Kubernetes,,llll,abc,\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd\xd4\xb0\xef\xbf\xbd,sync info,"
```

类似可以在172.29.88.208的redis-slave上看到同样的内容。由此可见Redis master和Redis slave之间数据同步正常，OVS GRE隧道技术使得跨机器间容器正常通信。

## 4.6 排错提示 ##

1. 所有的kubelet必须起来，否则报错`F0319 16:56:08.058335    9960 kubecfg.go:438] Got request error: The requested resource does not exist.`
2. 必须使用-b启动docker，否则无法访问8000端口，redis-slave也没同步
3. 注意pods一直处于Pending或Failed状态时去apiserver或其他组件日志里查看错误，是否是由于端口绑定冲突导致。

**参考**

- [CentOS 7实战Kubernetes部署](http://www.infoq.com/cn/articles/centos7-practical-kubernetes-deployment)
- [kubernetes-examples-guestbook](https://github.com/GoogleCloudPlatform/kubernetes/tree/master/examples/guestbook)
- [getting_started_guides-ubuntu_single_node](https://github.com/GoogleCloudPlatform/kubernetes/blob/master/docs/getting-started-guides/ubuntu_single_node.md)
- [基于kubernetes构建Docker集群管理详解](http://blog.liuts.com/category/42/1/1/)


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/kubernetes-deploy.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/kubernetes-api.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/kubernetes-guestbook1.png
  [4]: http://github.com/seanlook/sean-notes-comment/raw/main/static/kubernetes-guestbook2.png
  [5]: http://github.com/seanlook/sean-notes-comment/raw/main/static/kubernetes-simpleui.png
