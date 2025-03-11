---
title: ProxySQL高可用方案
date: 2017-07-15 21:32:49
tags: [mysql, 中间件, proxysql]
categories:
- MySQL
updated: 2017-07-18 21:32:49
---

MySQL的高可用方案现在如 MHA, Galera, InnoDB Cluster，一旦在上游使用中间件之后，中间件本身可能成为单点。所以本文要介绍的是对于ProxySQL自身高可用的方案对比。
首先ProxySQL自身是通过Angel进程的形式运行，即proxysql如果有崩溃，主进程会自动拉起来。但如果是无响应或者网络故障，则需要另外的机制去做到服务的高可用。本文总结了四种方法。

ProxySQL有关介绍，请参考： http://xgknight.com/2017/04/10/mysql-proxysql-install-config/

# 1. 与应用一起部署
所有部署应用的地方，都会部署proxysql节点，当这个proxysql挂掉之后，只影响本机的应用。而且不需要多经过一层网络。
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-ha-1.png)
但带来的问题是，如果应用节点很多，proxy的数量也会增加：

- 会导致proxysql的配置不容易管理
- proxysql对后端db健康检查的请求成倍增加
- 限制每个用户或后端db的 max_connections 特性用不了

# 2. 集中式部署，多ip引用
后端一个db集群，对应中间两个以上的 proxysql 节点，前端应用配置多个ip地址，随机挑选一个使用，完全无状态。仅需要多经过一次网络代理。
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-ha-2.png)
这种方式的好处是，不需要再对数据库这种基础服务，多引入一个软件来实现高可用（如下节的keepalive或consul），由应用端获取数据库连接的代码逻辑处理。

但是因为proxysql访问地址是写在配置文件里面的，如果一个节点挂掉，随机挑选还是会落地这个失败的节点。所以优化方案是，ip列表里面默认取某一个，失败之后再选取下一个重试。

示例代码：

```python
proxysql_addr_list = ['192.168.1.175', '192.168.1.176', '192.168.1.177']
proxysql_addr_list_len = 3
hostname = 'this_hostname_for_hash_loadbalance'
def get_dbconnection():
    list_index = hash(hostname) % proxysql_addr_list_len
    dbconn = None
    try:
        dbconn = DBConnect(dbhost=proxysql_addr_list[ list_index ], dbport=3306)  # timeout 1000ms
    except:
        if (list_index + 1) == proxysql_addr_list_len:
            list_index = -1  # like Circular Array
        dbconn = DBConnec(dbhost=proxysql_addr_list[ list_index + 1 ], dbport=3306)  # if failed again, through exception
    
    return dbconn
```
上述并不完美，比如可以改用环形数组轮巡，允许重试其它更多的ip。
<!-- more -->
## 能不能不进行多IP引用呢？
为了避免后端引用IP的单点，可以将上面第1种和这里的第2中结合起来，改进的部署方案：（见文后参考链接）
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-ha-1-1.png)
即在原来的基础上，App上的proxysql后端，挂的还是ProxySQL集群。

我个人没有验证这样的方案，如果要用需要充分验证proxysql互连的时候，有没有bug。

# 3. 经典 keepalived 
引入keepalived，通过VIP访问两个以上的proxysql节点，既可以减少一次网络传输，又可以实现proxysql自身的高可用，而且甚至不用关心脑裂的问题，因为proxysql配置完全一样，是无状态的，脑裂了也无妨。
你也可能意识到，这种方式一次只能一个proxysql提供服务，另一个proxysql节点始终处于备用状态。如果配合LVS或haproxy做负载均衡，部署架构又会多出一层网络请求，而且越发复杂（VIP不在proxysql节点上漂，而是在两个lvs之间）。
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-ha-3.png)
使用keepalived的前提是，局域网允许发组播包。这在阿里云ECS经典网络下是不允许的，如果有其它类似方式，如SLB也是可行的。目前测试环境采用是 haproxy + keepalived 的方式。

# 4. Consul服务发现
如果上面的方式都不适用，那么可以进一步考虑使用第三方的服务发现组件。

## 4.1 介绍
Consul用于实现分布式系统的服务发现与配置，我们将所有proxysql节点注册到consul上作为一个服务来提供，由 Consul agent Server 来判断proxysql节点的存活，每个应用节点上都安装 Consul agent Client 来供应用获取可用地址。

![](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-ha-4.png)

这样部署架构的好处是：
1. 不需要多一层负载均衡，多一层网络链路
2. 不需要部署大量的proxysql节点
3. App或者ProxySQL节点上的Consul故障，不影响其它节点。Consul Server集群的天生具备高可用
4. ProxySQL故障会被Consul检查到，踢除故障节点，并通知给所有consul agent
5. 可以利用Consul的DNS接口实现简单的负载均衡

其实consul所做的与本文第2节的类似：自动提出不可用的节点，只是一个是被动、手动，一个是主动、自动。
下面简单演示一下。

## 4.2 部署示例
Consul Server节点的安装在此略过，网上有不少文章，直接进入到在ProxySQL节点安装配置Consul。

Consul agent:
- apps-1: `10.0.201.168`
- apps-2: `10.0.201.220`
- apps-3: `10.0.201.156`

ProxySQL node:
每个节点上运行了两个proxysql进程 `7033: crm0`, `7133: crm1`
- proxysql-1 : `192.168.1.170`
- proxysql-2 : `192.168.1.171`

### 配置 proxysql 节点上的Consul

配置 proxysql-1 节点上的Consul：
```
$ sudo vim /etc/consul.d/config.json
{
    "data_dir": "/opt/consul", 
    "datacenter": "Office_test", 
    "log_level": "INFO", 
    "node_name": "proxysql-1", 
    "retry_join": [
        "10.0.201.168", 
        "10.0.201.220", 
        "10.0.201.156"
    ], 
    "telemetry": {
        "statsd_address": "10.0.201.34:8125", 
        "statsite_prefix": "proxysql-1"
    },
    "dns_config": {
        "only_passing": true
    }
    "acl_datacenter": "Office_test", 
    "acl_default_policy": "deny", 
    "encrypt": "XXXXxxxx=="
}

$ sudo vi /etc/consul.d/proxysql.json
{"services": [
    {
        "id": "proxysql_crm0", 
        "name": "proxysql", 
        "address": "192.168.1.170",
        "port": 7133, 
        "tags": ["test", "crm0"], 
        "check": {
            "interval": "5s", 
            "tcp": "192.168.1.170:7033", 
            "timeout": "1s"
        }, 
        "enableTagOverride": false, 
        "token": "xxxxxxxx-xxxx"
    },
    {
        "id": "proxysql_crm1", 
        "address": "192.168.1.170",
        "name": "proxysql", 
        "port": 7133, 
        "tags": ["test", "crm1"], 
        "check": {
            "interval": "5s", 
            "tcp": "192.168.1.170:7133", 
            "timeout": "1s"
        }, 
        "enableTagOverride": false, 
        "token": "xxxxxxxx-xxxx"
    }
]}
```

启动consul
```
sudo consul agent -config-dir /etc/consul &
```
查看日志

proxysql-2 节点上的Consul配置根据上面的内容去改。

![](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-ha-consul.png)

## 4.4 使用方式
先来看下效果：
```
[root@proxysql-1 ~]# dig @127.0.0.1 -p 8600 crm0.proxysql.service.consul SRV

; <<>> DiG 9.8.2rc1-RedHat-9.8.2-0.62.rc1.el6_9.2 <<>> @127.0.0.1 -p 8600 crm0.proxysql.service.consul SRV
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 65293
;; flags: qr aa rd; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 2
;; WARNING: recursion requested but not available

;; QUESTION SECTION:
;crm0.proxysql.service.consul.	IN	SRV

;; ANSWER SECTION:
crm0.proxysql.service.consul. 0	IN	SRV	1 1 7033 proxysql-1.node.office_test.consul.
crm0.proxysql.service.consul. 0	IN	SRV	1 1 7033 proxysql-2.node.office_test.consul.

;; ADDITIONAL SECTION:
proxysql-1.node.office_test.consul. 0 IN A	192.168.1.170
proxysql-2.node.office_test.consul. 0 IN A	192.168.1.171

;; Query time: 3 msec
;; SERVER: 127.0.0.1#8600(127.0.0.1)
;; WHEN: Fri May 26 17:01:38 2017
;; MSG SIZE  rcvd: 157
```
看到域名 `crm0.proxysql.service.consul` 解析出来有两个可用地址 192.168.1.170，192.168.1.171，SRV记录还带出了端口信息（其实这里的端口对每个proxysql是固定/已知的，所以可不用SRV记录搜索）。

在应用端想要连接proxysql使用的方式大致有3种：
### DNS接口
需要将各自开发语言的DNS解析库嵌入到项目，指定 127.0.0.1:8600 为dns地址来解析上面的 crm0.proxysql.service.consul 域名。这种方式会增加开发的复杂度。

另一种方式是将应用服务器的默认DNS Server配置成本地consul的内置dns地址，并且consul设置 `recursors` 选项，来处理解析 consul. 以外的域名。这样对运维改动比较大。
```
"recursors": [
    "10.143.22.116",
    "10.143.22.118",
    "114.114.114.114"
]
```

### HTTP接口
通过 API 的方式获取services信息：

```
$ curl -X GET 'http://10.0.201.156:8500/v1/health/service/proxysql?tag=crm1&passing=true'
```
可以获取到 crm1 库的proxysql所有健康的 Node 和 Service 信息，然后任取一个使用。

但并不需要每一次访问proxysql都需要请求api，可以定时（如每隔10s）去请求，缓冲在本地或者变量里；在处理数据库连接的时候发现连接ProxySQL错误，则再主动触发一次向Consul请求新的地址，再重连。

需要考虑的是访问API的地址如果是IP，往往也是单点。另者，java这类jvm语言修改配置后往往需要重启，也不简单。

### consul-template直接生成数据库连接的配置文件
consul-template通过事先定义好的模板，根据发现服务的健康状态，生成最新可用的配置文件，然后下发。

如果大但的想一下，各个服务或者语言的配置文件并不相同，直接生成一份 hosts 文件是最简单的，然后通过配置管理工具统一下发应用。也不需要关心是否需要重启应用。

#### consul watch
Consul watch 功能，可以检测到service变化之后，主动调用一个脚本，脚本可以去更新数据库配置信息，根据需要决定是否重启，后者生成hosts。与consul-template思想是相同的。

因为 watch 是通过阻塞式HTTP长连接请求的方式，实时获取到service的监控状态，所以有问题时反馈还比较及时。
```
"watches":[{
  "type": "service",
  "service": "proxysql",
  "tag": "crm0",
  "passingonly": true,
  "handler": "sh /tmp/consul_watch_test.sh"
}]
```
`/tmp/consul_watch_test.sh` 脚本里或者python，可以做一些更新数据库配置文件、发送邮件等工作。

**参考**
1. https://www.percona.com/blog/2016/09/16/consul-proxysql-mysql-ha/
2. https://www.percona.com/blog/2017/01/19/setup-proxysql-for-high-availability-not-single-point-failure/
3. https://www.slideshare.net/DerekDowney/proxysql-tutorial-plam-2016 (本文部分图片出自该PPT)


---

原文连接地址：http://xgknight.com/2017/07/15/mysql-proxysql-ha-consul/

---
