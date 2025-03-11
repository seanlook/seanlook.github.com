---
title: RabbitMQ 入门
date: 2018-01-06 15:32:49
aliases:
- /2018/01/06/rabbitmq-introduce/
tags: [消息队列, rabbitmq]
categories:
- MQ
updated: 2018-01-06 15:32:49
---

rabbitmq可以用一本书取讲，这里只是介绍一些使用过程中，常用到的基本的知识点。
官方文档覆盖的内容，非常全面：http://www.rabbitmq.com/documentation.html 。

## 1. 介绍
RabbitMQ，即消息队列系统，它是一款开源消息队列中间件，采用Erlang语言开发，RabbitMQ是AMQP(Advanced Message Queueing Protocol)的标准实现。

AMQP是一个公开发布的异步消息的规范，是提供统一消息服务的应用层标准高级消息队列协议，为面向消息的中间件设计.消息中间件主要用于组件之间的解耦，消息的发送者无需知道消息使用者的存在，反之亦然。

https://www.rabbitmq.com/tutorials/amqp-concepts.html

相对于JMS(Java Message Service)规范来说，JMS使用的是特定语言的APIs，而消息格式可自由定义，而AMQP对消息的格式和传输是有要求的，但实现不会受操作系统、开发语言以及平台等的限制。

JMS和AMQP还有一个较大的区别：JMS有队列(Queues)和主题(Topics)两种消息传递模型，发送到 JMS队列 的消息最多只能被一个Client消费，发送到 JMS主题 的消息可能会被多个Clients消费；AMQP只有队列(Queues)，队列的消息只能被单个接受者消费，发送者并不直接把消息发送到队列中，而是发送到Exchange中，该Exchage会与一个或多个队列绑定，能够实现与JMS队列和主题同样的功能。

另外还有一种 MQTT协议，意为消息队列遥测传输，是IBM开发的一个即时通讯协议。由于其维护一个长连接以轻量级低消耗著称，所以常用于移动端消息推送服务开发。MQTT是基于TCP的应用层协议封装，实现了异步Pub/Sub，在物联网（IoT）应用广泛。

RabbitMQ可通过库、插件的形式，支持JMS和MQTT协议。参考：http://geek.csdn.net/news/detail/71894

### 1.1 主要概念
![](https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_MRG/2/html-single/Messaging_Programming_Reference/images/1083.png)

1. Broker  
接收和分发消息的应用，RabbitMQ Server就是Message Broker

2. Exchange  
message到达broker的第一站，根据分发规则，匹配查询表中的routing key，分发消息到queue中去。常用的类型有：direct, topic, fanout。  
如果没有队列绑定到exchange上，那么该exchange上的消息都会被丢弃，因为它不存储消息又不知道该怎么处理消息。
<!-- more -->
3. Queue  
消息队列载体，每个消息都会被投入到一个或多个队列

4. Binding  
在exchange和queue之间建立关系就叫Binding，消费者声明队列的时候一般会指定routing_key，也可以叫binding_key。Binding信息被保存到exchange中的查询表中，用于message的分发依据。

5. Routing Key  
这里区分一下binding和routing: binding是一个将exchange和queue关联起来的**动作**，routing_key可以理解成队列的一个属性，表示这个队列接受符合该routing_key的消息，routing_key需要在发送消息的时候指定。

6. Vhost  
于多租户和安全因素设计的，把AMQP的基本组件划分到一个虚拟的分组中，类似于网络中的namespace概念。当多个不同的用户使用同一个RabbitMQ server提供的服务时，可以划分出多个vhost，每个用户在自己的vhost创建exchange／queue等

7. Producer  
消息生产者，就是投递消息的程序。只负责把消息发送exchange，附带一些消息属性。

8. Consumer  
消息消费者，就是接受消息的程序。

9. Channel  
如果每一次访问RabbitMQ都建立一个Connection，在消息量大的时候建立TCP Connection的开销将是巨大的，效率也较低。  
Channel是在connection内部建立的逻辑连接，如果应用程序支持多线程，通常每个thread创建单独的channel进行通讯，AMQP method包含了channel id帮助客户端和message broker识别channel，所以channel之间是完全隔离的。Channel作为轻量级的Connection极大减少了操作系统建立TCP connection的开销。

### 1.2 对比
rabbitmq
activemq
rocketmq
kafka
zeromq
redis

celery
待续

## 2. 安装配置
CentOS 6.7，安装3.6.14最新稳定版本：
```
wget https://packages.erlang-solutions.com/erlang-solutions-1.0-1.noarch.rpm
rpm -Uvh erlang-solutions-1.0-1.noarch.rpm
rpm --import https://dl.bintray.com/rabbitmq/Keys/rabbitmq-release-signing-key.asc
yum install -y socat
```

如果机器上有epel源，先把它禁用掉：enabled=0，否则会默认从这个源按照低版本rabbitmq 。
如果已安装老版本，可能需要卸载 `rpm -qa|grep erlang|awk '{print "yum remove -y "$1}'|sh` 。
继续
```
wget http://packages.erlang-solutions.com/rpm/centos/6/x86_64/erlang-20.1-1.el6.x86_64.rpm
wget https://www.rabbitmq.com/releases/rabbitmq-server/v3.6.14/rabbitmq-server-3.6.14-1.el6.noarch.rpm

yum localinstall -y erlang-20.1-1.el6.x86_64.rpm rabbitmq-server-3.6.14-1.el6.noarch.rpm
```

确保本地主机名能够正常解析出自己的ip，或 127.0.0.1. （ping rabbitmq-01）

```
ulimit -S -n 4096
ulimit -n 65534

# limits.conf
cat /etc/security/limits.conf
* soft nofile 65535
* hard nofile 65535

# 从配置文件模板创建配置文件
sudo cp -a /usr/share/doc/rabbitmq-server-3.6.14/rabbitmq.config.example /etc/rabbitmq/rabbitmq.config

# 启动
/etc/init.d/rabbitmq-server restart
```

默认用户名密码 `guest`/`guest`， 具有vhost `/` 的所有权限，只能在本地访问。
队列元数据及内容信息，默认在目录 `/var/lib/rabbitmq/mnesia` 下。

### 2.1 配置
```
# 启用管理插件
rabbitmq-plugins enable rabbitmq_management

# /etc/rabbitmq/rabbitmq.config 配置
[
 {rabbit,
  [%%
   {tcp_listeners, [5672]},
   {vm_memory_high_watermark, 0.6},
   %% {vm_memory_high_watermark_paging_ratio, 0.5},
   {hipe_compile, true}
  ]},
 {rabbitmq_management,
  [%% Preload schema definitions from a previously exported definitions file. See
  ]}
].
```
`%%`是Erlang的注释符号。
- vm_memory_high_watermark
  RabbitMQ在使用当前机器的40%以上内存时候，会发出内存警告，并阻止RabbitMQ所有连接（producer连接）。这个阈值便由 `vm_memory_high_watermark` 控制
- vm_memory_high_watermark_paging_ratio
  当内存中的数据达到一定数量后，他需要被page out出来。比如默认这个ratio=0.5，机器内存8G，于是 memory watermark=0.4 * 8G几即 3.2G。3.2G * paging_raio = 1.6G，当消息挤压的量达到1.6G后，开始paging到磁盘上。
  一搬不去改它。
- hipe_compile
  开启Erlang HiPE编译选项（相当于Erlang的jit技术），能够提高性能20%-50%。在Erlang R17后HiPE已经相当稳定，RabbitMQ官方也建议开启此选项。
  开启之后，每次启动 rabbitmq-server，需要多花1分钟左右。

看下 `rabbitmqctl status` 信息，混个眼熟：
```

Status of node 'rabbit@rabbitmq-01'
[{pid,6232},
 {running_applications,
     [{rabbitmq_management,"RabbitMQ Management Console","3.6.14"},
      {rabbitmq_management_agent,"RabbitMQ Management Agent","3.6.14"},
      {rabbitmq_web_dispatch,"RabbitMQ Web Dispatcher","3.6.14"},
      {cowboy,"Small, fast, modular HTTP server.","1.0.4"},
      {rabbitmq_consistent_hash_exchange,"Consistent Hash Exchange Type",
          "3.6.14"},
      {rabbitmq_sharding,"RabbitMQ Sharding Plugin","3.6.14"},
      {rabbit,"RabbitMQ","3.6.14"},
      {amqp_client,"RabbitMQ AMQP Client","3.6.14"},
      {rabbit_common,
          "Modules shared by rabbitmq-server and rabbitmq-erlang-client",
          "3.6.14"},
      {os_mon,"CPO  CXC 138 46","2.4.3"},
      {mnesia,"MNESIA  CXC 138 12","4.15.1"},
      {cowlib,"Support library for manipulating Web protocols.","1.0.2"},
      {compiler,"ERTS  CXC 138 10","7.1.2"},
      {recon,"Diagnostic tools for production use","2.3.2"},
      {syntax_tools,"Syntax tools","2.1.3"},
      {crypto,"CRYPTO","4.1"},
      {stdlib,"ERTS  CXC 138 10","3.4.2"},
      {kernel,"ERTS  CXC 138 10","5.4"}]},
 {os,{unix,linux}},
 {erlang_version,
     "Erlang/OTP 20 [erts-9.1] [source] [64-bit] [smp:4:4] [ds:4:4:10] [async-threads:64] [hipe] [kernel-poll:true]\n"},
 {memory,
     [{connection_readers,0},
      {connection_writers,0},
      {connection_channels,0},
      {connection_other,8864},
      {queue_procs,48686248},
      {queue_slave_procs,0},
      {plugins,14194848},
      {other_proc,12618480},
      {metrics,323944},
      {mgmt_db,12627800},
      {mnesia,701856},
      {binary,22261264},
      {msg_index,634656},
      {allocated_unused,364165712},
      {reserved_unallocated,0},
      {total,596238336}]},
 {alarms,[]},
 {listeners,
     [{clustering,25672,"::"},{amqp,5672,"0.0.0.0"},{http,15672,"0.0.0.0"}]},
 {vm_memory_calculation_strategy,rss},
 {vm_memory_high_watermark,0.6},
 {vm_memory_limit,4952820940},
 {disk_free_limit,50000000},
 {disk_free,1626125135872},
 {file_descriptors,
     [{total_limit,65435},
      {total_used,58},
      {sockets_limit,58889},
      {sockets_used,0}]},
 {processes,[{limit,1048576},{used,446}]},
 {run_queue,0},
 {uptime,1232025},
 {kernel,{net_ticktime,60}}]
```

### 2.2 命令行
```
# 添加新的 vhost
rabbitmqctl add_vhost /some0
rabbitmqctl list_vhost

# 添加登录用户 admin  
rabbitmqctl add_user admin admin
rabbitmqctl list_users

# 设置为管理员角色
rabbitmqctl set_user_tags admin administrator

# 设置权限
rabbitmqctl set_permissions -p /some0 admin '.*' '.*' '.*'
rabbitmqctl list_permissions -p /some0
rabbitmqctl list_user_permissions admin
```

在开始介绍概念之前，先可以从Web UI上来认识一下rabbitmq:
rabbitmq overview 首页监控面板:  
![rabbitmq-overview.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/rabbitmq-overview.png)

rabbitmq 客户端的连接信息:  
![rabbitmq-connections.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/rabbitmq-connections.png)

某个channel的详情:  
![rabbitmq-channel-info.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/rabbitmq-channel-info.png)

exchanges信息:  
![rabbitmq-exchanges.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/rabbitmq-exchanges.png)

queues信息:  
![rabbitmq-queues-consuming.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/rabbitmq-queues-consuming.png)

策略定义:  
![rabbitmq-policy.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/rabbitmq-policy.png)

<!-- more -->

## 3. Exchange类型
AMQP 0-9-1 定义了四种内置类型的exchange type: direct, fanout, topic, header。exchange除了类型以外，还可以指定一些属性：
- Name: 交换器名字。一般以 `.` 号分隔以作区分  
- Durability: 持久化的exchange在broker重启之后依然存在。相对应是 transient exchange  
- Auto-delete: 如果设置了该属性，在最后一个队列unbound之后，exchange会自动删除  
- Arguments: 可以用在满足插件扩展上  
  - alternate-exchange  
    RabbitMQ自己扩展的功能，不是AMQP协议定义的。  
    Alternate Exchange属性的作用，创建Exchange指定该 `x-arguments` 的`alternate-exchange `属性，发送消息的时候根据route key没有找到可以投递的队列，这就会将此消息路由到 Alternate Exchange 属性指定的 Exchange (就是一个普通的exchange)上了。

    比如把MySQL的binlog订阅出来，因为里面有许多表，每个表的dml行数有多有少。我们可以将变更量多的表单独放到一个队列，其它表一起放到一个队列，就可以为原始的exchange添加 alternate-exchange 属性，将其它表的数据重新投递到另一个exchange。

### 3.1 fanout
fanout类型的exchange是最容易理解的，它会把来自生产者的消息广播到所有绑定的queues上。这种情况一般会把消息的routing_key设置为空`''`，甚至不关心队列的名字。如下图：  
![](https://www.rabbitmq.com/img/tutorials/python-three-overall.png)

`amq.gen-RQ6...`和`amq.gen-As8...`是消费者随机生成了两个队列，绑定到fanout exchange上，C1,C2会各自收到一模一样的消息。

### 3.2 direct
direct类型的exchange转发消息到队列里，是直接基于消息的routing key。  
![](https://www.rabbitmq.com/img/tutorials/python-four.png)

C1在声明队列的时候，指定routing_key=error。C2的队列上绑定了info,error,warning三个key。
于是error类型的消息会被同时发送到C1,C2（准确的说是两个队列上），而info,warning类型的消息只发送到队列a`mqp.gen-Agl...`。

如果要达到Round-Robin轮询效果，即两个Consumer依次从同一个队列里取消息，那么可以在声明队列的时候指定相同的 queue name，rabbitmq会自动均衡的发送消息给多个Consumer，可水平扩展消费者的处理能力（如果要保证处理顺序，得设置prefetch_count=1）。

### 3.3 topic
topic类型的exchange大大提升了消息路由的灵活性。不像fanout那样无脑的全部转发，也不像direct那样指定所有的routing_key，否则不匹配的key的消息就会被丢弃。
比如有一个收集日志的系统，模块包括auth/cron/kernel/app1/app2，日志级别包括error,info,warning。现在要把所有模块的error日志规整在一起，可以设计routing_key: \<module\>.\<severity\> (auth.error, auth.info, ..., app1.error, app1.info...)，然后设置queue的binding_key='*.error'

topic exchange 会根据 `.` 划分word，有以下两种正则符号用于匹配routing_key：
- `*`: 代表一个word
- `#`: 代表0个或多个word

拿官网的例图来说：<敏捷度>.<颜色>.<物种>  
![](https://www.rabbitmq.com/img/tutorials/python-five.png)  
上图创建了3个bindings: 
- 队列Q1的binding_key=`*.orange.*`，即对所有橙色的动物感兴趣
- 队列Q2绑定了`*.*.rabbit`和`lazy.#`，即订阅了所有和兔子相关的消息，以及反应迟钝的动物

于是：
- routing_key为`quick.orange.rabbit`的消息，会被发送到两个队列
- routing_key为`lazy.orange.elephant`的消息，也会被发送到两个队列
- routing_key为`quick.orange.fox`的消息，只会发送到Q1
- routing_key为`lazy.brown.fox`的消息，只会发送到Q2
- routing_key为`lazy.pink.rabbit`的消息，只会发送到Q2。虽然匹配到了`lazy.#`和`*.*.rabbit`，但只会发送一次
- routing_key为`quick.brown.fox`的消息，会被丢弃，因为没有任何绑定的队列得到匹配
- routing_key为`lazy.orange.male.rabbit`的消息，还是会发送到Q2，因为 `lazy.#`
  然而`orange`、`quick.orange.male.rabbit`，也破坏了约定，但没得到匹配，消息丢弃。
- routing_key为`#`，接受所有消息，相当于fanout exchange
- routing_key没有`*`和`#`时，相当于direct exchange

### 3.4 headers
header类型的exchange用的不多，是在routing_key不能满足使用场景的情况下(如routing_key必须是字符串)，在消息的头部加入一个或多个key/value，然后在声明队列的时候也指定要绑定的header。

binding的时候有个参数`x-match`，指定headers所有的k/v都要匹配成功（`all`）还是任意一个匹配则接受（`any`）。

### 3.5 x-consistent-hash
这是个第三方插件形式存在的exchange，目前已内置于rabbitmq：https://github.com/rabbitmq/rabbitmq-consistent-hash-exchange

`x-consistent-hash`类型的exchange可以根据routing_key，用一致性哈希算法，将消息路由到不同的队列上。它可以尽可能的保证每个队列上的消息数量相同，也可以随时添加更多的队列来“分流”，并且能保证同一个routing_key会进入相同的queue。

要达到这样的效果，queue routing key必须是一个字符串类型的数字。比如Q1:routing_key='10', Q2:routing_key='20'，那么消息就会按照1:2的比例，发送到Q1,Q2。

### 3.6 x-modulus-hash
第三方插件形成存在的exchange，从3.6.0版本开始，也内置到了rabbitmq发行版：https://github.com/rabbitmq/rabbitmq-sharding

`x-modulus-hash`类型的exchange与 `x-consistent-hash` 很像，也叫 sharding exchange，即将message在多个队列之间进行分区发送。它的实现方法是根据 routing_key 先获得hash，再用 `Hash mod N` 得到队列，N就是绑定到exchange上的队列个数。

## 4. Queue属性
Queue 要先于 Exchange 创建，否则生产者发布的消息，在没有绑定队列之前，会丢失。
已存在的Queue可以重复declare，但前提是属性要相同。

- Name: 队列名称。可以在应用里面指定，或者交给broker生成  
- Durable：持久化的Queue在broker重启之后，依然存在。
  注意，这里的持久化与消息持久无关。是个 property  
- Exclusive: 为True时，表示当Consumer的Connection端口之后，队列自动删除。一般由broker生成的随机队列名，指定这个选项 。
  排他队列是基于连接可见的，同一连接的不同信道是可以同时访问同一个连接创建的排他队列的
- Auto-delete: 当最后一个consumer取消订阅之后，队列自动删除

- Arguments: 设置可选的一些参数，如  
  - x-message-ttl  
    消息在队里里最大存活时间，超过这个ttl就会被丢弃。单位毫秒

  - x-max_length  
    队列里最多容纳的消息个数，超过这个值，则会从队列头部drop掉消息

  - x-max-priority  
    设置了这个参数，就表示这是一个具有优先级的队列。它的值是可定义的优先级最大值，一般10以内就够了。
    在生产商Publish消息的时候，消息Property上可设置Priority

  - x-queue-mode  
    这个参数是控制是否为"延迟队列"，Lazy Queue是在3.6.0引入的，它会尽量把消息存在磁盘上，节省内存
    RabbitMQ一开始的设计初衷，是做异步、解耦，所以会把消息放在内存里面，以便快速的发送给消费者（持久化类型的消息会同时存在于磁盘和内存缓存中）。

    如果用它来暂时存放大量消息，而不消费或者消费太慢，会导致性能明显下降，因为为了释放内存，消息得swap到磁盘上 —— 会阻塞队列接收新消息。如果内存使用达到broker设置的 water-mark，也会拒绝接收新消息。  
    Lazy Queue(`x-queue-mode=lazy`)的作用就是一接收到新消息，马上存到文件系统，完全避免了前面提到的内存占用。这会增加磁盘I/O（顺序的），与处理持久化类型的消息很相似。

  - x-dead-letter-exchange  
    死信。当消息在一个队列中变成死信后，它能被重新publish到另一个Exchange，这个Exchange就是DLX。消息变成死信一向有以下几种情况：
      - 消息被拒绝（basic.reject or basic.nack）并且requeue=false
      - 消息TTL过期
      - 队列达到最大长度

    DLX也是一下正常的Exchange同一般的Exchange没有区别，它能在任何的队列上被指定，实际上就是设置某个队列的属性，当这个队列中有死信时，RabbitMQ就会自动的将这个消息重新发布到设置的Exchange中去，进而被路由到另一个队列。  
    死信被重新 requeue 时，可以改变它的routing_key，以便新的队列处理，routing_key用`x-dead-letter-routing-key`指定，如果不指定则继续使用消息原来的routing_key。


## 5. Message属性
- routing_key  
  路由关键字，exchange根据这个关键字进行消息投递
- delivery_mode
  - 1: Non-persistent，消息不持久化到磁盘，尽快被消费掉。重启broker之后消息丢失
  - 2: Persistent，消息持久化。当然被取走的消息，也就不存在了
- headers  
  消息头信息，key/value形式，可以认为给消息打上了各种各样的标签。可用于代替 routing_key 去路由（结合headers来下的exchange），或者第三方插件使用。
- properties  
  实际上 headers 和 delivery_mode 也是properties的一部分，因为使用较多，所以单独拿出去。这里也只提几个：
  - priority  
    消息优先级。数字，优先级高的消息会排在队列头部  
  - correlation_id 和 reply_to  
    这两个一般用于实现服务间RPC调用， 即生产者发起请求到rabbitmq队列，等待处理结果返回，消费者处理完消息后返回结果给调用方。  
    reply_to 在消息里面告诉消费者，处理完的结果放到哪个队列，调用方根据 correlation_id 找到结果。详情参考 https://www.rabbitmq.com/tutorials/tutorial-six-python.html
  - expiration  
    消息自身的Time-To-Live，用的较少，也叫 Per-Message TTL In Publisher.  
    前面提到，队列的arguemnts可以设置 x-message-ttl ，也叫 Per-Queue Message TTL In Queues.消息是否过期以两者的最小值为准，并且消息自身过期时间到了之后，不会自动从队列删除，而是在发送给消费者的时候丢弃。  
    队列自身也有个 `x-expires`，它指的是队列在多久没有消费者连上来，超过这个时间后队列自动删除。
- payload: 消息正文

## 6. 插件
RabbitMQ支持插件式的来扩展功能。
```
列举server上安装的所有插件
# rabbitmq-plugins list
 Configured: E = explicitly enabled; e = implicitly enabled
 | Status:   * = running on rabbit@rabbitmq-01
 |/
[e*] amqp_client                       3.6.14
[e*] cowboy                            1.0.4
[e*] cowlib                            1.0.2
[  ] rabbitmq_amqp1_0                  3.6.14
[  ] rabbitmq_auth_backend_ldap        3.6.14
[  ] rabbitmq_auth_mechanism_ssl       3.6.14
[E*] rabbitmq_consistent_hash_exchange 3.6.14
[  ] rabbitmq_event_exchange           3.6.14
[  ] rabbitmq_federation               3.6.14
[  ] rabbitmq_federation_management    3.6.14
[  ] rabbitmq_jms_topic_exchange       3.6.14
[E*] rabbitmq_management               3.6.14
[e*] rabbitmq_management_agent         3.6.14
[  ] rabbitmq_management_visualiser    3.6.14
[  ] rabbitmq_mqtt                     3.6.14
[  ] rabbitmq_random_exchange          3.6.14
[  ] rabbitmq_recent_history_exchange  3.6.14
[E*] rabbitmq_sharding                 3.6.14
[  ] rabbitmq_shovel                   3.6.14
[  ] rabbitmq_shovel_management        3.6.14
[  ] rabbitmq_stomp                    3.6.14
[  ] rabbitmq_top                      3.6.14
[  ] rabbitmq_tracing                  3.6.14
[  ] rabbitmq_trust_store              3.6.14
[e*] rabbitmq_web_dispatch             3.6.14
[  ] rabbitmq_web_mqtt                 3.6.14
[  ] rabbitmq_web_mqtt_examples        3.6.14
[  ] rabbitmq_web_stomp                3.6.14
[  ] rabbitmq_web_stomp_examples       3.6.14
[  ] sockjs                            0.3.4

启用插件
# rabbitmq-plugins enable plugin-name
```
下面是几个常用插件：
1. rabbitmq_management  
管理 rabbitmq server 的插件，提供给予HTTP的API和 WebUI，提供管理exchanges、管理queues、管理users、管理policies，监控，发布/接收消息。功能强大，基本是必定开启的插件。
开启管理插件后，也可以选择不使用Web界面，从 `http://localhost:15672/cli/rabbitmqadmin` 下载 `rabbitmqadmin` 命令行工具，它用在一些脚本里面会很方便。（提示： rabbitmqctl 是不能创建exchange和queue，但rabbitmqadmin可以）

1. rabbitmq_federation
与MySQL Federated 存储引擎很相似，可以认为 federated exchange 是其它exchange(也叫upstream exchange)的“软连接”、“流量复制”。消息是被publish到上游exchange，然后消费者是从其它broker上的federated exchange订阅消息。
Federated exchanges/queues 是通过 AMQP 协议的Erlang客户端从真实broker里面取数据(不会消费源数据)，可以实现跨网络的消息提取，或者将不同地方的消息汇总到一处。应用场景有 broker / cluster 数据迁移，模仿真实数据的线下测试。

1. rabbitmq_shovel
shovel插件就是一个 消费者 + 生产者：从一个queue消费内容，发送到另一个exchange上，甚至可以对消息做些转换。你可以自己实现将消息从源broker消费，重新publish到另一个exchange，但shovel帮我们做好了。

1. rabbitmq_mqtt
实现了 MQTT 3.1 协议的adapter，如文章开头所述。

1. rabbitmq_consistent_hash_exchange
一致性hash exchange，如前文所述。

## 6. 策略 Policy
首先为什么rabbitmq会有策略这个东西。

前面我们讲到，queue和exchange有一些固定属性，如`durable`、`exclusive`、`auto-delete`等，还有一些可选参数，也叫`x-arguments`，如`x-max-length`、`x-queue-mode`。这些都是客户端在定义队列和交换器时指定的。

如果事后想修改 TTL 或者 queue length limit ，那么得修改应用、重新部署，甚至涉及到删除队列，重新declare。Policy就是解决这个痛点的，在服务端对匹配的 exchanges 或者 queues 设置参数，无需动应用。更多请参考 https://www.rabbitmq.com/parameters.html 

一个 policy 包含以下内容：
- name: 策略名字
- pattern: 对哪些queues(exchanges)的应用策略，正则表达式
- definition: 策略内容定义，key/value形式（也可以认为是JSON格式）
- apply-to: 策略应用在什么身上，`queues`、`exchanges`、`all`。默认是all
- priority: 策略优先级，默认0

每个exchange/queue只能“注入”一个policy，所以如果要设置多个策略，把key/value组合成json，定义在一起。设置完成会马上生效，包括后面新创建的exchange、queues。

```
将exchange设置为 alternate exchange:(策略名：AE)
rabbitmqctl set_policy -p /some0 AE "^maxwell.some3$" '{"alternate-exchange":"maxwell.AE"}' --apply-to exchanges

将vhost /some0 的所有队列都设置成 Lazy Queue
rabbitmqctl set_policy -p /some0 Lazy "^" '{"queue-mode":"lazy"}' --apply-to queues

队列名匹配 'two-messages' 的队列，设置最大队列消息数为2，超过之后的行为是 禁止接收新消息（与之对应的是 drop-head: 删除头部老的消息）
rabbitmqctl set_policy my-pol "^two-messages$" '{"max-length":2,"overflow":"reject-publish"}' --apply-to queues
```

## 7. 消息可靠性
有的系统要保证消息不允许丢失，甚至不允许重复，有的系统追求的是高性能，所以要在性能和可靠性之间权衡。rabbitmq在多个层面提供消息可靠性保证。
### 7.1 持久化
声明持久化的exchange: channel.exchange_delcare(exchange_name, durable)
声明持久化的队列：channel.queueDeclare(queue_name, durable, exclusive, auto_delete, arguments)
发布的持久化消息，投递模式为2： delivery_mode=2

http://www.rabbitmq.com/reliability.html
persistent

### 7.1 ack & confirm
持久化保证了在broker或者机器出现异常的时候，消息不会丢失，要保证发送者在pub消息、接收sub消息时出现网络异常，客户端也应该有相应的处理。

#### Consumer Delivery Acknowledgements
rabbitmq对Consumer处理消息提供 acknowledgements 确认机制，客户端通过`basic.consume`注册到broker(push)，或者通过`basic.get` pull 消息，都可以在指定是否开启`ack`。

*delivery tags*是实现 ack 的关键，RabbitMQ会用 `basic.deliver` 方法向消费者推送消息，这个方法携带了一个 delivery tag，它是单调递增的正整数，在一个channel中唯一代表了一次投递。

确认模式包括自动确认和手动确认。
自动确认就是rabbitmq一旦把消息发送出去后，就认为成功，完成确认。此模式性能最高，只要消费者能处理的过来，但自然降低了消息到达处理的可靠性，比如一个消息还在路上，消费者的TCP连接或者channel就关闭了，那么消息也就丢失。如果消费者处理不过来，可能会导致消息在客户端挤压，内存过载，引发异常。所以自动确认一般用在消息比较平稳、客户端能处理的来的系统。

手动确认，就是客户端需要自己发送确认命令，包括：
- basic.ack —— 确认成功，客户端成功处理
- basic.nack —— 确认失败，客户端处理失败，但依然删掉消息
- basic.reject —— 确认失败，客户端处理失败，消息不删除，可重新发送。

手动确认模式，可以控制消息处理的速度（流控QoS），通过 prefetch 设置该channel上最大没有确认的消息数，server会等待有空闲的配额时才继续发送给消费者。
手动确认模式如果不设置 prefetch_count，那么消费者可能会接收许多的消息但未ack，从而导致内存耗尽，所以这点需要小心。正常来说，100-300是个比较可控的范围。（当然如果是 pull 模式，就不存在QoS一说）

`basic.ack`和`basic.nack`可以设置 `multiple` 字段，批量确认来减少网络传输。比如说在信道 `ch` 上有 delivery tags 5, 6, 7, 8 没有确认，当客户端发回的确认帧是8并且 multiple=true，那么5-8的tags都被ack。

在启用手动确认时，发生网络连接断开或者消费者崩溃，而无法返回 ack/nack 命令时，（检测方法是 [heartbead](https://www.rabbitmq.com/heartbeats.html)）rabbitmq会自动将没有确认的消息 **requeue**，所以客户端处理消息时，最好能满足幂等性，即能够重复处理这些消息。

#### Publisher Confirms
rabbitmq对Producer发布消息提供 confirm 机制：客户端可以发送一个 `confirm.select` 命令将channel设置成`confirm`工作模式。
所有在该信道上面发布的消息都将会被指派一个唯一的ID(从1开始)，一旦消息被投递到所有匹配的队列之后，broker就会发送一个确认给生产者(basic.ack)，这就使得生产者知道消息已经正确到达目的队列了。如果消息和队列是可持久化的，那么确认消息会在将消息写入磁盘之后发出，broker回传给生产者的确认消息中delivery-tag域包含了确认消息的序列号。

如果RabbitMQ因为自身内部错误导致消息丢失，就会发送一条nack消息，生产者应用程序同样可以在回调方法中处理该nack消息，确保消息不会再发送之前就丢失。

然后对于需要持久化的消息的确认，不能完全保证数据被刷到磁盘上，因为每个消息调用 fsync 的带来的IO代价太高，rabbitmq会每隔几百毫秒，批量将消息从文件系统缓存 fsync 刷到磁盘。（了解MySQL的话对这个应该不陌生）

### 7.2 事务
RabbitMQ 实现了AMQP 0-9-1协议里的事务，这样说唯一能确保消息不丢失的方式，信道可以设置成 transaction 模式：发布消息，commit/rollback消息。

但是事务在这里太重了，而且会极大的降低性能。不用。

### 7.3 rabbitmq分布式
待聊

## 5. python使用示例
https://pika.readthedocs.io/en/0.10.0/intro.html

下面的示例是使用Maxwell或者MySQL binlog增量流，json数据进入rabbitmq，然后通过 pika —— python版本的rabbitmq client，重新组装成sql，达到数据增量同步的效果。
```
   def binlog_sync(self):
        logger.info("connect to rabbitmq server [%s], vhost=%s", rabbitmq_conn_info.get('host'), rabbitmq_conn_info.get('vhost', '/'))
        ## rabbitmq 用户认证信息
        credentials = pika.PlainCredentials(rabbitmq_conn_info.get('user', 'guest'),
                                            rabbitmq_conn_info.get('password', 'guest')
        )
        ## rabbitmq tcp连接
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(
                host=rabbitmq_conn_info.get('host'),
                port=rabbitmq_conn_info.get('port', 5672),
                virtual_host=rabbitmq_conn_info.get('vhost', '/'),
                credentials=credentials
            )
        )
        ## rabbitmq 信道，避免频繁tcp断连
        channel = connection.channel()

        # exchange_name = 'maxwell.some' + str(self.corpmod)
        # exchange_other = 'maxwell.AE'
        logger.info("declare mq exchange [%s], type=[%s]", self.exchange_name, self.exchange_type)
        ## 创建 exchange，如果已经存在相同名字，就不会重复创建，但要求属性要相同
        ## 指定exchange_type，durable, arguments 。这里的alternate-exchange放到策略里从创建，因为目前maxwell作为消费者，没有支持arguemnts参数
        channel.exchange_declare(exchange=self.exchange_name,
                                 exchange_type=self.exchange_type,
                                 durable=True,
                                 # arguments={'alternate-exchange': exchange_other}
        )

        """
        channel.exchange_declare(exchange=exchange_other, exchange_type='topic', durable=True)  # alternative exchange
        channel.queue_declare(queue='ae_other', durable=True)
        channel.queue_bind(exchange=exchange_other,
                           queue='ae_other',
                           routing_key='d_ec_some.*')
        """
        logger.info("declare queue name=[%s]", self.queue_name)
        ## 创建 queue，如果以经存在相同名字的队列，则不会创建，但要求属性相同，否则报错
        ## 指定了 lazy queue
        channel.queue_declare(queue=self.queue_name, durable=True, arguments={'x-queue-mode': 'lazy'})

        ## 将routing_key 绑定到队列上
        for key in self.queue_bind_key:
            logger.info("bind routing_key [%s] to queue [%s]", key, self.queue_name)
            channel.queue_bind(exchange=self.exchange_name,
                               queue=self.queue_name,
                               routing_key=key)

        # consume callback, internal
        ## 客户端处理消息
        def callback(ch, method, properties, body):
            # print(" [x] Received %s" % body)
            logger.debug("Received message: %s", body)
            try:
                data_row = json.loads(body.decode('utf-8'))
                self.process_data(data_row)

                if ret == -2:  # requeue
                ## 处理异常，如Ctrl+C断开，重新排队
                    logger.warning("message data: %s (requeue)", data_row)
                    ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
                    # return
            except ValueError as e:
                logger.error("proces Error: %s(skip)", e)
                logger.error("  received data: %s", body)
                ## 处理异常，但跳过
                ch.basic_ack(delivery_tag=method.delivery_tag)
            except Exception as e:
                logger.error("proces Error: %s(skip)", e)
                logger.error("  message data: %s", data_row)
                ch.basic_ack(delivery_tag=method.delivery_tag)
            else:
            ## 发送确认成功
                ch.basic_ack(delivery_tag=method.delivery_tag)
        
        ## 设置最多 50 个未确认
        channel.basic_qos(prefetch_count=50)

        # 开始消费，拿到的消息调用callback处理
        channel.basic_consume(callback, queue=self.queue_name, no_ack=False)

        # print(' [*] Waiting for messages. To exit press CTRL+C')
        logger.info("start comsuming")
```

**参考**
- https://www.rabbitmq.com/tutorials/amqp-concepts.html
- http://www.rabbitmq.com/admin-guide.html
- https://geewu.gitbooks.io/rabbitmq-quick/content/index.html
- http://blog.csdn.net/anzhsoft/article/details/19607841
- http://dbaplus.cn/news-141-1464-1.html


---

原文连接地址：http://xgknight.com/2018/01/06/rabbitmq-introduce/

---
