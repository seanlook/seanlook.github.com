---
title: Nginx+Keepalived实现站点高可用
date: 2015-05-18 01:21:25
aliases:
- /2015/05/18/nginx-keepalived-ha/
updated: 2015-05-18 00:46:23
tags: [nignx, keepalived, 高可用]
categories: [Linux, Nginx]
---


公司内部 OA 系统要做线上高可用，避免单点故障，所以计划使用2台虚拟机通过 Keepalived 工具来实现 nginx 的高可用（High Avaiability），达到一台nginx入口服务器宕机，另一台备机自动接管服务的效果。（nginx做反向代理，实现后端应用服务器的负载均衡）快速搭建请直接跳至 第2节。

# 1. Keepalived介绍 #
Keepalived是一个基于VRRP协议来实现的服务高可用方案，可以利用其来避免IP单点故障，类似的工具还有heartbeat、corosync、pacemaker。但是它一般不会单独出现，而是与其它负载均衡技术（如lvs、haproxy、nginx）一起工作来达到集群的高可用。

## 1.1 VRRP协议 ##
VRRP全称 Virtual Router Redundancy Protocol，即 [虚拟路由冗余协议](http://en.wikipedia.org/wiki/VRRP)。可以认为它是实现路由器高可用的容错协议，即将N台提供相同功能的路由器组成一个路由器组(Router Group)，这个组里面有一个master和多个backup，但在外界看来就像一台一样，构成虚拟路由器，拥有一个虚拟IP（vip，也就是路由器所在局域网内其他机器的默认路由），占有这个IP的master实际负责ARP相应和转发IP数据包，组中的其它路由器作为备份的角色处于待命状态。master会发组播消息，当backup在超时时间内收不到vrrp包时就认为master宕掉了，这时就需要根据VRRP的优先级来选举一个backup当master，保证路由器的高可用。

在VRRP协议实现里，虚拟路由器使用 00-00-5E-00-01-XX 作为*虚拟*MAC地址，XX就是唯一的 VRID （Virtual Router IDentifier），这个地址同一时间只有一个物理路由器占用。在虚拟路由器里面的物理路由器组里面通过多播IP地址 224.0.0.18 来定时发送通告消息。每个Router都有一个 1-255 之间的优先级别，级别最高的（highest priority）将成为主控（master）路由器。通过降低master的优先权可以让处于backup状态的路由器抢占（pro-empt）主路由器的状态，两个backup优先级相同的IP地址较大者为master，接管虚拟IP。

![nginx-keepalived-vrrp.jpg][1]

### 与heartbeat/corosync等比较 ###
直接摘抄自 http://www.linuxidc.com/Linux/2013-08/89227.htm ：

<!-- more -->

> Heartbeat、Corosync、Keepalived这三个集群组件我们到底选哪个好，首先我想说明的是，Heartbeat、Corosync是属于同一类型，Keepalived与Heartbeat、Corosync，根本不是同一类型的。Keepalived使用的vrrp协议方式，虚拟路由冗余协议 (Virtual Router Redundancy Protocol，简称VRRP)；Heartbeat或Corosync是基于主机或网络服务的高可用方式；简单的说就是，Keepalived的目的是模拟路由器的高可用，Heartbeat或Corosync的目的是实现Service的高可用。
>
> 所以一般Keepalived是实现前端高可用，常用的前端高可用的组合有，就是我们常见的LVS+Keepalived、Nginx+Keepalived、HAproxy+Keepalived。而Heartbeat或Corosync是实现服务的高可用，常见的组合有Heartbeat v3(Corosync)+Pacemaker+NFS+Httpd 实现Web服务器的高可用、Heartbeat v3(Corosync)+Pacemaker+NFS+MySQL 实现MySQL服务器的高可用。总结一下，Keepalived中实现轻量级的高可用，一般用于前端高可用，且不需要共享存储，一般常用于两个节点的高可用。而Heartbeat(或Corosync)一般用于服务的高可用，且需要共享存储，一般用于多节点的高可用。这个问题我们说明白了。
>
> 又有博友会问了，那heartbaet与corosync我们又应该选择哪个好啊，我想说我们一般用corosync，因为corosync的运行机制更优于heartbeat，就连从heartbeat分离出来的pacemaker都说在以后的开发当中更倾向于corosync，所以现在corosync+pacemaker是最佳组合。

## 1.2 Keepalived + nginx ##
keepalived可以认为是VRRP协议在Linux上的实现，主要有三个模块，分别是core、check和vrrp。core模块为keepalived的核心，负责主进程的启动、维护以及全局配置文件的加载和解析。check负责健康检查，包括常见的各种检查方式。vrrp模块是来实现VRRP协议的。本文基于如下的拓扑图：

```
                   +-------------+
                   |    uplink   |
                   +-------------+
                          |
                          +
    MASTER            keep|alived         BACKUP
172.29.88.224      172.29.88.222      172.29.88.225
+-------------+    +-------------+    +-------------+
|   nginx01   |----|  virtualIP  |----|   nginx02   |
+-------------+    +-------------+    +-------------+
                          |
       +------------------+------------------+
       |                  |                  |
+-------------+    +-------------+    +-------------+
|    web01    |    |    web02    |    |    web03    |
+-------------+    +-------------+    +-------------+
```

# 2. keepalived实现nginx高可用 #
## 2.1安装 ##
我的环境是CentOS 6.2 X86_64，直接通过yum方式安装最简单：
```
# yum install -y keepalived
# keepalived -v
Keepalived v1.2.13 (03/19,2015)
```

## 2.2 nginx监控脚本 ##
该脚本检测ngnix的运行状态，并在nginx进程不存在时尝试重新启动ngnix，如果启动失败则停止keepalived，准备让其它机器接管。

`/etc/keepalived/check_nginx.sh` ：
```
#!/bin/bash
counter=$(ps -C nginx --no-heading|wc -l)
if [ "${counter}" = "0" ]; then
    /usr/local/bin/nginx
    sleep 2
    counter=$(ps -C nginx --no-heading|wc -l)
    if [ "${counter}" = "0" ]; then
        /etc/init.d/keepalived stop
    fi
fi
```
你也可以根据自己的业务需求，总结出在什么情形下关闭keepalived，如 curl 主页连续2个3s没有响应则切换：
(感谢网友对这个脚本提出的几处语法错误，已修正)
```
#!/bin/bash
# curl -IL http://localhost/member/login.htm
# curl --data "memberName=fengkan&password=22" http://localhost/member/login.htm

count=0
for (( k=0; k<2; k++ ))
do
    check_code=$( curl --connect-timeout 3 -sL -w "%{http_code}\\n" http://localhost/login.html -o /dev/null )
    if [ "$check_code" != "200" ]; then
        count=$(expr $count + 1)
        sleep 3
        continue
    else
        count=0
        break
    fi
done
if [ "$count" != "0" ]; then
#   /etc/init.d/keepalived stop
    exit 1
else
    exit 0
fi
```

## 2.3 keepalived.conf ##
```
! Configuration File for keepalived
global_defs {
    notification_email {
        zhouxiao@example.com
        itsection@example.com
    }
    notification_email_from itsection@example.com
    smtp_server mail.example.com
    smtp_connect_timeout 30
    router_id LVS_DEVEL
}

vrrp_script chk_nginx {
#    script "killall -0 nginx"
    script "/etc/keepalived/check_nginx.sh"
    interval 2
    weight -5
    fall 3  
    rise 2
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    mcast_src_ip 172.29.88.224
    virtual_router_id 51
    priority 101
    advert_int 2
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        172.29.88.222
    }
    track_script {
       chk_nginx
    }
}
```
在其它备机BACKUP上，只需要改变 `state MASTER` -> `state BACKUP`，`priority 101` -> `priority 100`，`mcast_src_ip 172.29.88.224` -> `mcast_src_ip 172.29.88.225`即可。


    service keepalived restart

## 2.4 配置选项说明 ##
**global_defs**

- `notification_email` ： keepalived在发生诸如切换操作时需要发送email通知地址，后面的 smtp_server 相比也都知道是邮件服务器地址。也可以通过其它方式报警，毕竟邮件不是实时通知的。
- `router_id` ： 机器标识，通常可设为hostname。故障发生时，邮件通知会用到

**vrrp_instance**

- `state` ： 指定instance(Initial)的初始状态，就是说在配置好后，这台服务器的初始状态就是这里指定的，但这里指定的不算，还是得要通过竞选通过优先级来确定。如果这里设置为MASTER，但如若他的优先级不及另外一台，那么这台在发送通告时，会发送自己的优先级，另外一台发现优先级不如自己的高，那么他会就回抢占为MASTER
- `interface` ： 实例绑定的网卡，因为在配置虚拟IP的时候必须是在已有的网卡上添加的
- `mcast_src_ip` ： 发送多播数据包时的源IP地址，这里注意了，这里实际上就是在那个地址上发送VRRP通告，这个非常重要，一定要选择稳定的网卡端口来发送，这里相当于heartbeat的心跳端口，如果没有设置那么就用默认的绑定的网卡的IP，也就是interface指定的IP地址
- `virtual_router_id` ： 这里设置VRID，这里非常重要，相同的VRID为一个组，他将决定多播的MAC地址
- `priority` ： 设置本节点的优先级，优先级高的为master
- `advert_int` ： 检查间隔，默认为1秒。这就是VRRP的定时器，MASTER每隔这样一个时间间隔，就会发送一个advertisement报文以通知组内其他路由器自己工作正常
- `authentication` ： 定义认证方式和密码，主从必须一样
- `virtual_ipaddress` ： 这里设置的就是VIP，也就是虚拟IP地址，他随着state的变化而增加删除，当state为master的时候就添加，当state为backup的时候删除，这里主要是有优先级来决定的，和state设置的值没有多大关系，这里可以设置多个IP地址
- `track_script` ： 引用VRRP脚本，即在 vrrp_script 部分指定的名字。定期运行它们来改变优先级，并最终引发主备切换。


**vrrp_script**
告诉 keepalived 在什么情况下切换，所以尤为重要。可以有多个 vrrp_script

- `script` ： 自己写的检测脚本。也可以是一行命令如`killall -0 nginx`
- `interval 2` ： 每2s检测一次
- `weight -5` ： 检测失败（脚本返回非0）则优先级 -5
- `fall 2` ： 检测连续 2 次失败才算确定是真失败。会用weight减少优先级（1-255之间）
- `rise 1` ： 检测 1 次成功就算成功。但不修改优先级

这里要提示一下script一般有2种写法：

1. 通过脚本执行的返回结果，改变优先级，keepalived继续发送通告消息，backup比较优先级再决定
2. 脚本里面检测到异常，直接关闭keepalived进程，backup机器接收不到advertisement会抢占IP

上文 vrrp_script 配置部分，`killall -0 nginx`属于第1种情况，`/etc/keepalived/check_nginx.sh`属于第2种情况（脚本中关闭keepalived）。个人更倾向于通过shell脚本判断，但有异常时exit 1，正常退出exit 0，然后keepalived根据动态调整的 vrrp_instance 优先级选举决定是否抢占VIP：

- 如果脚本执行结果为0，并且weight配置的值大于0，则优先级相应的增加
- 如果脚本执行结果非0，并且weight配置的值小于0，则优先级相应的减少

其他情况，原本配置的优先级不变，即配置文件中priority对应的值。

提示：

1. 优先级不会不断的提高或者降低
2. 可以编写多个检测脚本并为每个检测脚本设置不同的weight（在配置中列出就行）
3. 不管提高优先级还是降低优先级，最终优先级的范围是在[1,254]，不会出现优先级小于等于0或者优先级大于等于255的情况
4. 在MASTER节点的 vrrp_instance 中 配置 `nopreempt` ，当它异常恢复后，即使它 prio 更高也不会抢占，这样可以避免正常情况下做无谓的切换

以上可以做到利用脚本检测业务进程的状态，并动态调整优先级从而实现主备切换。

**配置结束**

在默认的keepalive.conf里面还有 virtual_server,real_server 这样的配置，我们这用不到，它是为lvs准备的。 `notify` 可以定义在切换成MASTER或BACKUP时执行的脚本，如有需求请自行google。

notify

## 2.5 nginx配置 ##
当然nginx没有什么可配置的，因为它与keepalived并没有联系。但记住，2台nginx服务器上的配置应该是完全一样的（rsync同步），这样才能做到对用户透明，nginx.conf 里面的 `server_name` 尽量使用域名来代替，然后dns解析这个域名到虚拟IP 172.29.88.222。

更多关于nginx内容配置请参考 [这里](http://xgknight.com/2015/05/17/nginx-install-and-config/) 。

# 3. 测试 #
根据上面的配置，初始化状态：172.29.88.224 (itoatest1,MASTER,101)，172.29.88.222（itoatest2,BACKUP,100），nginx和keepalived都启动，虚拟IP 172.29.88.222 在 itoatest1 上：
```
# 使用ip命令配置的地址，ifconfig查看不了
[root@itoatest1 nginx-1.6]# ip a|grep eth0
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 1000
    inet 172.29.88.224/24 brd 172.29.88.255 scope global eth0
    inet 172.29.88.222/32 scope global eth0
```
浏览器访问 172.29.88.222 或域名，OK。

直接关闭 itoatest1 上的nginx：`/usr/local/nginx-1.6/sbin/nginx -s stop`：
```
[root@localhost keepalived]# ip a|grep eth0
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 1000
    inet 172.29.88.224/24 brd 172.29.88.255 scope global eth0
```
vip消失，漂移到 itoatest2：

![nginx-keepalived-vip.png][2]

同时可以看到两台服务器上 `/var/log/messages`：
```
## itoatest1
Jun  5 16:44:01 itoatest1 Keepalived_vrrp[44875]: VRRP_Instance(VI_1) Sending gratuitous ARPs on eth0 for 172.29.88.222
Jun  5 16:44:06 itoatest1 Keepalived_vrrp[44875]: VRRP_Instance(VI_1) Sending gratuitous ARPs on eth0 for 172.29.88.222
Jun  5 16:44:46 itoatest1 Keepalived_vrrp[44875]: VRRP_Script(chk_nginx) failed
Jun  5 16:44:48 itoatest1 Keepalived_vrrp[44875]: VRRP_Instance(VI_1) Received higher prio advert
Jun  5 16:44:48 itoatest1 Keepalived_vrrp[44875]: VRRP_Instance(VI_1) Entering BACKUP STATE
Jun  5 16:44:48 itoatest1 Keepalived_vrrp[44875]: VRRP_Instance(VI_1) removing protocol VIPs.
Jun  5 16:44:48 itoatest1 Keepalived_healthcheckers[44874]: Netlink reflector reports IP 172.29.88.222 removed

## itoatest2
Jun  5 16:44:00 itoatest2 Keepalived_vrrp[35555]: VRRP_Instance(VI_1) Transition to MASTER STATE
Jun  5 16:44:00 itoatest2 Keepalived_vrrp[35555]: VRRP_Instance(VI_1) Received higher prio advert
Jun  5 16:44:00 itoatest2 Keepalived_vrrp[35555]: VRRP_Instance(VI_1) Entering BACKUP STATE
Jun  5 16:44:48 itoatest2 Keepalived_vrrp[35555]: VRRP_Instance(VI_1) forcing a new MASTER election
Jun  5 16:44:48 itoatest2 Keepalived_vrrp[35555]: VRRP_Instance(VI_1) forcing a new MASTER election
Jun  5 16:44:49 itoatest2 Keepalived_vrrp[35555]: VRRP_Instance(VI_1) Transition to MASTER STATE
Jun  5 16:44:50 itoatest2 Keepalived_vrrp[35555]: VRRP_Instance(VI_1) Entering MASTER STATE
Jun  5 16:44:50 itoatest2 Keepalived_vrrp[35555]: VRRP_Instance(VI_1) setting protocol VIPs.
Jun  5 16:44:50 itoatest2 Keepalived_vrrp[35555]: VRRP_Instance(VI_1) Sending gratuitous ARPs on eth0 for 172.29.88.222
Jun  5 16:44:50 itoatest2 Keepalived_healthcheckers[35554]: Netlink reflector reports IP 172.29.88.222 added
Jun  5 16:44:55 itoatest2 Keepalived_vrrp[35555]: VRRP_Instance(VI_1) Sending gratuitous ARPs on eth0 for 172.29.88.222
```

你也可以通过在两台服务器上抓包来查看 优先级priority 的变化：
```
## itoatest1 上
## 直接输出，或后加 -w itoatest-kl.cap存入文件用wireshark查看
# tcpdump -vvv -n -i eth0 dst 224.0.0.18 and src 172.29.88.224
```
![nginx-keepalived-prio.png][3]


**参考**

- [使用Keepalived实现Nginx高可用性](http://debugo.com/keepalived-nginx/)
- [High Availability Support Based on keepalived](http://nginx.com/resources/admin-guide/nginx-ha-keepalived/)
- [nginx+keepalived实现双机热备的高可用](https://www.centos.bz/2012/02/nginx-keepalived-high-availability/)
- [LVS原理详解及部署之五：LVS+keepalived实现负载均衡&高可用](http://atong.blog.51cto.com/2393905/1351709)
- [Keepalived双主模型中vrrp_script中权重改变故障排查](http://xxrenzhe.blog.51cto.com/4036116/1405571)
- [虚拟路由器冗余协议【原理篇】VRRP详解](http://zhaoyuqiang.blog.51cto.com/6328846/1166840)
- [Keepalived原理与实战精讲](http://bbs.ywlm.net/thread-845-1-1.html)


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/nginx-keepalived-vrrp.jpg
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/nginx-keepalived-vip.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/nginx-keepalived-prio.png
