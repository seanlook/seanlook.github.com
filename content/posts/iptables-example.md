title: iptables常用实例备查（更新中）
date: 2014-02-26 01:21:25
updated: 2014-02-26-12 00:46:23
tags: [iptables,安全]
categories: Linux
---

## 1. 普通规则 ##

### 1.1 操作规则 ###
- `iptables -nL`
查看本机关于iptables的设置情况，默认查看的是`-t filter`，可以指定`-t nat`
- `iptables-save > iptables.rule`
会保存当前的防火墙规则设置，命令行下通过iptables配置的规则在下次重启后会失效，当然这也是为了防止错误的配置防火墙。默认读取和保存的配置文件地址为`/etc/sysconfig/iptables`。

- 设置chain默认策略
```
    iptables -P INPUT DROP
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
```
将 INPUT 链默认处理策略设置为DROP，前提是已经存在一条可以访问22端口的规则。这里要说明的是，在添加这类拒绝访问的规则之前，一定要想好执行完，会不会把自己关在防火墙外面，不然就傻眼了。像下面这句。

### 1.2 限制访问规则 ###
- `iptables -I INPUT 1 -m state --state RELATED,ESTABLISHED -j ACCEPT`
把这条语句插在input链的最前面（第一条），对状态为ESTABLISHED,RELATED的连接放行。
这条规则在某种情况下甚至比下面开放ssh服务都重要：① 如果INPUT连默认为DROP，② INPUT链默认为INPUT，但存在这条规则`-A INPUT -j REJECT --reject-with icmp-host-prohibited`，上面两种情况下都必须添加`--state RELATED,ESTABLISHED`为第一条，否则22端口无法通行，把自己锁在防火墙外面了。
有了这条规则，可保证只要当前ssh没有关闭，哪怕防火墙忘记开启22端口，也可以继续连接。

- `iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 22 -j ACCEPT`
允许所有，不安全，默认。

- `iptables -A INPUT -s 172.29.73.0/24 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT`
限制指定IP范围能SSH，可取

- `iptables -A INPUT -s 10.30.0.0/16 -p tcp -m tcp -m multiport --dports 80,443 -j ACCEPT`
允许一个IP段访问多个端口

- `iptables -A INPUT -s 10.30.26.0/24 -p tcp -m tcp --dport 80 -j DROP`
禁止某IP段访问80端口，将`-j DROP`改成 `-j REJECT --reject-with icmp-host-prohibited`作用相同。

`iptables -A INPUT -s 172.29.73.23 -j ACCEPT`
完全信任某一主机，尽量不使用

`iptables -I INPUT 2 -i lo -j ACCEPT`
允许loopback。回环接口是一个主机内部发送和接收数据的虚拟设备接口，应该放行所有数据包。指定插入位置为 2 则之前该编号为 2 规则依次后移。

- `-A INPUT -p icmp -j ACCEPT`
接受icmp数据包，可以ping。也可以设置只允许某个特定的IP，见后文。

`iptables -A INPUT -j REJECT --reject-with icmp-host-prohibited`
这条规则用在INPUT链默没有DROP的情况，作用与`-P DROP`相同，当前面所有的规则都没匹配时，自然落到这个 REJECT 上。
类似的FORWARD链也可以这么用：`iptables -A FORWARD -j REJECT --reject-with icmp-host-prohibited`。

当然，更强的规则是将`OUPUT`链也设置成DROP，这样一来情况就会复杂很多，如就是发送名解析请求，也要添加规则`iptables -A OUTPUT -p udp --dport 53 -j ACCEPT`。
正是因为这样的太过麻烦，所以一般OUTPUT策略默认为ACCEPT。（安全性比较高的系统除外）

### 1.3 删除规则 ###

- `iptables -nL --line-number`
显示每条规则链的编号

- `iptables -D FORWARD 2`
删除FORWARD链的第2条规则，编号由上一条得知。如果删除的是nat表中的链，记得带上`-t nat`

- `iptables -D INPUT -j REJECT --reject-with icmp-host-prohibited`
删除规则的第二种方法，所有选项要与要删除的规则都相同才能删除，否则提示`iptables: No chain/target/match by that name.`

- 丢弃非法连接

    iptables -A INPUT   -m state --state INVALID -j DROP
    iptables -A OUTPUT -m state --state INVALID -j DROP
    iptables-A FORWARD -m state --state INVALID -j DROP


## 2. 几种情形 ##

### 2.1 端口转发 ###
首先要开启端口转发器必须先修改内核运行参数ip_forward,打开转发:
```
# echo 1 > /proc/sys/net/ipv4/ip_forward   //此方法临时生效
或
# vi /ect/sysctl.conf                      //此方法永久生效
# sysctl -p 
```

**本机端口转发**

    # iptables -t nat -A PREROUTING -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 8080

根据 [iptables防火墙原理详解](http://seanlook.com/2014/02/23/iptables-understand/) 可知，实际上在数据包进入INPUT链之前，修改了目标地址（端口），于是不难理解在开放端口时需要设置的是放行8080端口，无需考虑80：

    # iptables -A INPUT -s 172.29.88.0/24 -p tcp -m state --state NEW -m tcp --dport 8080 -j ACCEPT

此时外部访问http的80端口便可自动转到8080（浏览器地址栏不会变），而且又具有很高的性能，但如果你通过服务器**本地**主机的curl或firfox浏览器访问`http://localhost:80`或`http://doman.com:80`都是不行（假如你有这样的奇葩需求），这是因为本地数据包产生的目标地址不对，你需要额外添加这条 OUTPUT 规则：

    iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-ports 8080

下面的规则可以达到同样的效果：

	iptables -t nat -A PREROUTING -p tcp -i eth0 -d $YOUR_HOST_IP --dport 80 -j DNAT --to $YOUR_HOST_IP:8080
	iptables -t nat -A OUTPUT -p tcp -d $YOUR_HOST_IP --dport 80 -j DNAT --to 127.0.0.1:8080
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1      --dport 80 -j DNAT --to 127.0.0.1:8080

**异机端口转发**
有些情况下企业内部网络隔离比较严格，但有一个跨网段访问的情况，此时只要转发用的中转服务器能够与另外的两个IP(服务器或PC)通讯就可以使用iptables实现转发。（端口转发的还有其他方法，[请参考 linux服务器下各种端口转发技巧](http://) ）

要实现的是所有访问 192.168.10.100:8000 的请求，转发到 172.29.88.56:80 上，在 192.168.10.100 是哪个添加规则:

	iptables -t nat -A PREROUTING -i eth0 -p tcp -d 192.168.10.100 --dport 8000 -j DNAT --to-destination 172.29.88.56:80
    iptables -t nat -A POSTROUTING -o eth0 -j SNAT --to-source 192.168.10.100
    或者
    iptables -t nat -A PREROUTING -d 192.168.10.100 -p tcp --dport 8000 -j DNAT --to 172.29.88.56:80
    iptables -t nat -A POSTROUTING -d 172.29.88.56 -p tcp --dport 80 -j SNAT --to-source 192.168.10.100

需要注意的是，如果你的FORWARD链默认为DROP，上面所有端口转发都必须建立在FORWARD链允许通行的情况下：

    iptables -A FORWARD -d 172.29.88.56 -p tcp --dport 80 -j ACCEPT
    iptables -A FORWARD -s 172.29.88.56 -p tcp -j ACCEPT

### 2.2 记录日志 ###

为22端口的INPUT包增加日志功能，插在input的第1个规则前面，为避免日志信息塞满`/var/log/message`，用`--limit`限制：

    iptables -R INPUT 1 -p tcp --dport 22 -m limit --limit 3/minute --limit-burst 8 -j LOG

`vi /etc/rsyslog.conf` 编辑日志配置文件，添加`kern.=notice   /var/log/iptables.log`，可以将日志记录到自定义的文件中。

`service rsyslog restart` #重启日志服务

### 2.3 防止DoS攻击 ###
SYN洪水是攻击者发送海量的SYN请求到目标服务器上的一种DoS攻击方法，下面的脚本用于预防轻量级的DoS攻击：
`ipt-tcp.sh`：
```  
iptables -N syn-flood   (如果您的防火墙默认配置有“ :syn-flood - [0:0] ”则不许要该项，因为重复了)
iptables -A INPUT -p tcp --syn -j syn-flood   
iptables -I syn-flood -p tcp -m limit --limit 2/s --limit-burst 5 -j RETURN   
iptables -A syn-flood -j REJECT   
# 防止DOS太多连接进来,可以允许外网网卡每个IP最多15个初始连接,超过的丢弃
# 需要iptables v1.4.19以上版本：iptables -V 
iptables -A INPUT -p tcp --syn -i eth0 --dport 80 -m connlimit --connlimit-above 20 --connlimit-mask 24 -j DROP   

#用Iptables抵御DDOS (参数与上相同)   
iptables -A INPUT -p tcp --syn -m limit --limit 5/s --limit-burst 10 -j ACCEPT  
iptables -A FORWARD -p tcp --syn -m limit --limit 1/s -j ACCEPT 

iptables -A FORWARD -p icmp -m limit --limit 2/s --limit-burst 10 -j ACCEPT
iptables -A INPUT -p icmp --icmp-type 0 -s ! 172.29.73.0/24 -j DROP
```
请参考：[Linux: 20 Iptables Examples For New SysAdmins](http://www.cyberciti.biz/tips/linux-iptables-examples.html)、[Iptables Limits Connections Per IP](http://www.cyberciti.biz/faq/iptables-connection-limits-howto/)、[iptables预防DDOS和CC攻击配置](http://blog.csdn.net/zqtsx/article/details/9405515)

**参考**

- [IPTables wiki](http://wiki.centos.org/zh/HowTos/Network/IPTables)
- [iptables/netfilter详解中文手册](http://www.ha97.com/4095.html)
- [Linux的iptables常用配置范例](http://www.ha97.com/3928.html)