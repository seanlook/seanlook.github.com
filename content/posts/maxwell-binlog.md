---
title: 自建Binlog订阅服务 —— Maxwell
date: 2018-01-13 15:32:49
aliases:
- /2018/01/13/maxwell-binlog/
tags: [mysql, binlog]
categories:
- MySQL
updated: 2018-01-13 15:32:49
---

## 1. 介绍

Maxwell 是java语言编写的能够读取、解析MySQL binlog，将行更新以json格式发送到 Kafka、RabbitMQ、AWS Kinesis、Google Cloud Pub/Sub、文件，有了增量的数据流，可以想象的应用场景实在太多了，如ETL、维护缓存、收集表级别的dml指标、增量到搜索引擎、数据分区迁移、切库binlog回滚方案，等等。

它还提供其它功能：
- 支持`SELECT * FROM table` 的方式做全量数据初始化
- 支持主库发生failover后，自动恢复binlog位置（GTID）
- 灵活的对数据进行分区，解决数据倾斜的问题。kafka支持 database, table, column等级别的数据分区
- 它的实现方式是伪装成MySQL Server的从库，接收binlog events，然后根据schemas信息拼装，支持ddl,xid,rows等各种event.

maxwell由 zendesk 开源：https://github.com/zendesk/maxwell ，而且维护者相当活跃。

网上已有人对 Alibaba Cannal, Zendesk Maxwell, Yelp mysql_streamer进行对比，见文后参考 实时抓取MySQL的更新数据到Hadoop。

类似功能的还有：http://debezium.io/docs/connectors/mysql/

### 安装
使用 maxwell 非常简单，只需要jdk环境
```
yum install -y java-1.8.0-openjdk-1.8.0.121-1.b13.el6.x86_64

curl -sLo - https://github.com/zendesk/maxwell/releases/download/v1.12.0/maxwell-1.12.0.tar.gz \
       | tar zxvf -
cd maxwell-1.12.0

# 默认寻找当前目录下的 config.properties 配置文件
```

要求 mysql server binlog格式是 `ROW`， row_image 是 `FULL`。感受一下输出结果
```
mysql> update test.e set m = 5.444, c = now(3) where id = 1;
{
   "database":"test",
   "table":"e",
   "type":"update",
   "ts":1477053234,
   "commit": true,
   ...
   "data":{
      "id":1,
      "m":5.444,
      "c":"2016-10-21 05:33:54.631000",
      "comment":"I am a creature of light."
   },
   "old":{
      "m":4.2341,
      "c":"2016-10-21 05:33:37.523000"
   }
}

mysql> create table test.e ( ... )
{
   "type":"table-create",
   "database":"test",
   "table":"e",
   "def":{
      "database":"test",
      "charset":"utf8mb4",
      "table":"e",
      "columns":[
         {"type":"int", "name":"id", "signed":true},
         {"type":"double", "name":"m"},
         {"type":"timestamp", "name":"c", "column-length":6},
         {"type":"varchar", "name":"comment", "charset":"latin1"}
      ],
      "primary-key":[
         "id"
      ]
   },
   "ts":1477053126000,
   "sql":"create table test.e ( id int(10) not null primary key auto_increment, m double, c timestamp(6), comment varchar(255) charset 'latin1' )",
   "position":"master.000006:800050"
}
```
`data`是 After image, `old` 是 Before image。 insert 只有后镜像，delete只有前镜像（`data`）
`type`是语句类型：`insert`, `update`, `delete`, `database-create`, `database-alter`, `database-drop`, `table-create`, `table-alter`, `table-drop` 。

<!-- more -->
## 基本配置
config.properties 配置文件里面的所有选项，都可以在启动 maxweill `./bin/maxwell` 是指定，覆盖配置文件的内容。这里只讲一些常用的。

### mysql options
- host
  指定从哪个地址的mysql获取binlog
- replication_host
  如果指定了 `replication_host`，那么它是真正的binlog来源的mysql server地址，而那么上面的`host`用于存放maxwell表结构和binlog位置的地址。
  将两者分开，可以避免 replication_user 往生产库里写数据。
- schema_host
  从哪个host获取表结构。binlog里面没有字段信息，所以maxwell需要从数据库查出schema，存起来。
  schema_host一般用不到，但在binlog-proxy场景下就很实用。比如要将已经离线的binlog通过maxwell生成json流，于是自建一个mysql server里面没有结构，只用于发送binlog，此时表机构就可以制动从 `schema_host` 获取。

- gtid_mode
  如果 mysql server 启用了GTID，maxwell也可以基于gtid取event。如果mysql server发生failover，maxwell不需要手动指定newfile:postion

正常情况下，replication_host 和 schema_host都不需要指定，只有一个 `--host`。

- schema_database
  使用这个db来存放 maxwell 需要的表，比如要复制的databases, tables, columns, postions, heartbeats.

### filtering
- include_dbs
  只发送binlog里面这些databases的变更，以`,`号分隔，中间不要包含空格。
  也支持java风格的正则，如 `include_tables=db1,/db\\d+/`，表示 db1, db2, db3...这样的。（下面的filter都支持这种regex）
  提示：这里的dbs指定的是真实db。比如binlog里面可能 `use db1` 但 `update db2.ttt`，那么maxwell生成的json `database` 内容是db2。
- exclude_dbs
  排除指定的这些 databbases
- include_tables
  只发送这些表的数据变更。不只需要指定 database.
- exclude_tables
  排除指定的这些表
- exclude_columns
  不输出这些字段。如果字段名在row中不存在，则忽略这个filter。
- include_column_values
  1.12.0新引入的过滤项。只输出满足 column=values 的行，比如 `include_column_values=bar=x,foo=y`，如果有`bar`字段，那么只输出值为`x`的行，如果有`foo`字段，那么只输出值为`y`的行。  
  如果没有对应字段，如只有`bar=x`没有`foo`字段，那么也成立。（即不是 或，也不是 与）

- blacklist_dbs
  一般不用。`blacklist_dbs`字面上难以与`exclude_dbs` 分开，官网的说明也是模棱两可。  
  从代码里面看出的意思是，屏蔽指定的这些dbs,tables的**结构变更**，与行变更过滤，没有关系。它应对的场景是，某个表上频繁的有ddl，比如truncate。

因为往往我们只需要观察部分表的变更，所以要注意这些 include 与 exclude 的关系，记住三点：
1. 只要 include 有值，那么不在include里面的都排除
2. 只要在 exclude 里面的，都排除
3. 其它都正常输出

举个比较极端的例子：
```
# database: db1,db2,db3,mydb
① include_dbs=db1,/db\\d+/
② exclude_dbs=db2
③ inlcude_tables=t1,t2,t3
④ exclude_tables=t3
```
配置了 include_dbs，那么mydb不在里面，所以排除；
配置了 exclude_dbs，那么db2排除。剩下db1,db3
同样对 tables，剩下t1,t2
所以db1.t1, db1.t2, db3.t1, db3.t2是筛选后剩下可输出的。如果没有指定include_dbs，那么mydb.t1也可以输出。

### formatting
- output_ddl
  是否在输出的json流中，包含ddl语句。**默认 false**  
- output_binlog_position
  是否在输出的json流中，包含binlog filename:postion。默认 false
- output_commit_info
  是否在输出的json流里面，包含 commit 和 xid 信息。默认 true  
  比如一个事物里，包含多个表的变更，或一个表上多条数据的变更，那么他们都具有相同的 xid，最后一个row event输出 commit:true 字段。这有利于消费者实现 事务回放，而不仅仅是行级别的回放。
- output_thread_id
  同样，binlog里面也包含了 thread_id ，可以包含在输出中。默认 false  
  消费者可以用它来实现更粗粒度的事务回放。还有一个场景是用户审计，用户每次登陆之后将登陆ip、登陆时间、用户名、thread_id记录到一个表中，可轻松根据thread_id关联到binlog里面这条记录是哪个用户修改的。

### monitoring
如果是长时间运行的maxwell，添加monitor配置，maxwell提供了http api返回监控数据。

### 其它
- init_position
  手动指定maxwell要从哪个binlog，哪个位置开始。指定的格式`FILE:POSITION:HEARTBEAT`。只支持在启动maxwell的命令指定，比如 `--init_postion=mysql-bin.0000456:4:0`。
  maxwell 默认从连接上mysql server的当前位置开始解析，如果指定 init_postion，要确保文件确实存在，如果binlog已经被purge掉了，可能需要想其它办法。见 [Binlog可视化搜索：实现类似阿里RDS数据追踪功能](xx)

## 2. 选择合适的生产者
Maxwell是将binlog解析成json这种比较通用的格式，那么要去用它可以选择输出到哪里，比如Kafka, rabbitmq, file等，总之送到消息队列里去。每种 Producer 有自己对应的选项。

### 2.1 file
```
producer=file
output_file=/tmp/mysql_binlog_data.log
```
比较简单，直接指定输出到哪个文件`output_file`。有什么日志收集系统，可以直接从这里拿。

### 2.2 rabbitmq
rabbitmq 是非常流行的一个AMQP协议的消息队列服务，相关介绍请参考 [rabbitmq入门](xx)
```
producer=rabbitmq

rabbitmq_host=10.81.xx.xxx
rabbitmq_user=admin
rabbitmq_pass=admin
rabbitmq_virtual_host=/some0
rabbitmq_exchange=maxwell.some
rabbitmq_exchange_type=topic
rabbitmq_exchange_durable=true
rabbitmq_exchange_autodelete=false
rabbitmq_routing_key_template=%db%.%table%
```
上面的参数都很容易理解，1.12.0版本新加入`rabbitmq_message_persistent`控制发布消息持久化的参数。
`rabbitmq_routing_key_template`是按照 db.tbl 的格式指定 routing_key，在创建队列时，可以根据不同的表进入不同的队列，提高并行消费而不乱序的能力。

因为rabbitmq搭建起来非常简单，所以我习惯用这个。

### 2.3 kafka
kafka是maxwell支持最完善的一个producer，并且内置了 多个版本的 kafka client(0.8.2.2, 0.9.0.1, 0.10.0.1, 0.10.2.1 or 0.11.0.1)，默认 `kafka_version=0.11.0.1`
```
producer=kafka

# 指定kafka brokers 地址
kafka.bootstrap.servers=hosta:9092,hostb:9092

# kafka主题可以是固定的，可以是 `maxwell_%{database}_%{table}` 这种按表去自动创建的动态topic
kafka_topic=maxwell

# ddl单独使用的topic
ddl_kafka_topic=maxwell_ddl

# kafka和kenesis都支持分区，可以选择根据 database, table, primary_key, 或者column的值去做partition
# maxwell默认使用database，在启动的时候会去检查是否topic是否有足够多数量的partitions，所以要提前创建好
#  bin/kafka-topics.sh --zookeeper ZK_HOST:2181 --create \
#                      --topic maxwell --partitions 20 --replication-factor 2
producer_partition_by=database

# 如果指定了 producer_partition_by=column, 就需要指定下面两个参数
# 根据user_id,create_date两列的值去分区，partition_key形如 1178532016-10-10 18:29:04
producer_partition_columns=user_id,create_date
# 如果不存在user_id或create_date，则按照database分区:
producer_partition_by_fallback=database  
```
maxwell会读取`kafka.`开头的参数，设置到连接参数里，比如`kafka.acks=1`,`kafka.retries=3`等

### 2.4 redis
redis也有简单的发布订阅(`pub/sub`)功能
```
producer=redis

redis_host=10.47.xx.xxx
redis_port=6379
# redis_auth=redis_auth
redis_database=0
redis_pub_channel=maxwell
```
但是试用一番之后，发现如果订阅没有连上去的话，所有pub的消息是会丢失的。所以最好使用`push/pop`去实现。

## 3. 注意事项
下面的是在使用过程中遇到的一些小问题，做下总结。
### timestamp column
maxwell对时间类型（datetime, timestamp, date）都是当做字符串处理的，这也是为了保证数据一致(比如`0000-00-00 00:00:00`这样的时间在timestamp里是非法的，但mysql却认，解析成java或者python类型就是null/None)。

如果MySQL表上的字段是 timestamp 类型，是有时区的概念，binlog解析出来的是标准UTC时间，但用户看到的是本地时间。比如 `f_create_time timestamp` 创建时间是北京时间`2018-01-05 21:01:01`，那么mysql实际存储的是`2018-01-05 13:01:01`，binlog里面也是这个时间字符串。如果不做消费者不做时区转换，会少8个小时。被这个狠狠坑了一把。

与其每个客户端都要考虑这个问题，我觉得更合理的做法是提供时区参数，然后maxwell自动处理时区问题，否则要么客户端先需要知道哪些列是timestamp类型，或者连接上原库缓存上这些类型。

### binary column
maxwell可以处理binary类型的列，如`blob`、`varbinary`，它的做法就是对二进制列使用 base64_encode，当做字符串输出到json。消费者拿到这个列数据后，不能直接拼装，需要 base64_decode。

### 表结构不同步
如果是拿比较老的binlog，放到新的mysql server上去用maxwell拉去，有可能表结构已经发生了变化，比如binlog里面字段比 schema_host 里面的字段多一个。目前这种情况没有发现异常，比如阿里RDS默认会为 无主键无唯一索引的表，增加一个`__##alibaba_rds_rowid##__`，在 show create table 和 schema里面都看不到这个隐藏主键，但binlog里面会有，同步到从库。

另外我们有通过git去管理结构版本，如果真有这种场景，也可以应对。

### 大事务binlog
当一个事物产生的binlog量非常大的时候，比如迁移日表数据，maxwell为了控制内存使用，会自动将处理不过来的binlog放到文件系统
```
Using kafka version: 0.11.0.1
21:16:07,109 WARN  MaxwellMetrics - Metrics will not be exposed: metricsReportingType not configured.
21:16:07,380 INFO  SchemaStoreSchema - Creating maxwell database
21:16:07,540 INFO  Maxwell - Maxwell v?? is booting (RabbitmqProducer), starting at Position[BinlogPosition[mysql-bin.006235:24980714],
lastHeartbeat=0]
21:16:07,649 INFO  AbstractSchemaStore - Maxwell is capturing initial schema
21:16:08,267 INFO  BinlogConnectorReplicator - Setting initial binlog pos to: mysql-bin.006235:24980714
21:16:08,324 INFO  BinaryLogClient - Connected to rm-xxxxxxxxxxx.mysql.rds.aliyuncs.com:3306 at mysql-bin.006235/24980714 (sid:637
9, cid:9182598)
21:16:08,325 INFO  BinlogConnectorLifecycleListener - Binlog connected.
03:15:36,104 INFO  ListWithDiskBuffer - Overflowed in-memory buffer, spilling over into /tmp/maxwell7935334910787514257events
03:17:14,880 INFO  ListWithDiskBuffer - Overflowed in-memory buffer, spilling over into /tmp/maxwell3143086481692829045events
```

但是遇到另外一个问题，overflow随后就出现异常`EventDataDeserializationException: Failed to deserialize data of EventHeaderV4`，当我另起一个maxwell指点之前的binlog postion开始解析，却有没有抛异常。事后的数据也表明并没有数据丢失。

问题产生的原因还不明，Caused by: java.net.SocketException: Connection reset，感觉像读取 binlog 流的时候还没读取到完整的event，异常关闭了连接。这个问题比较顽固，github上面类似问题都没有达到明确的解决。（这也从侧面告诉我们，大表数据迁移，也要批量进行，不要一个insert into .. select 搞定）

```
03:18:20,586 INFO  ListWithDiskBuffer - Overflowed in-memory buffer, spilling over into /tmp/maxwell5229190074667071141events
03:19:31,289 WARN  BinlogConnectorLifecycleListener - Communication failure.
com.github.shyiko.mysql.binlog.event.deserialization.EventDataDeserializationException: Failed to deserialize data of EventHeaderV4{time
stamp=1514920657000, eventType=WRITE_ROWS, serverId=2115082720, headerLength=19, dataLength=8155, nextPosition=520539918, flags=0}
        at com.github.shyiko.mysql.binlog.event.deserialization.EventDeserializer.deserializeEventData(EventDeserializer.java:216) ~[mys
ql-binlog-connector-java-0.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.event.deserialization.EventDeserializer.nextEvent(EventDeserializer.java:184) ~[mysql-binlog-c
onnector-java-0.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.BinaryLogClient.listenForEventPackets(BinaryLogClient.java:890) [mysql-binlog-connector-java-0
.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.BinaryLogClient.connect(BinaryLogClient.java:559) [mysql-binlog-connector-java-0.13.0.jar:0.13
.0]
        at com.github.shyiko.mysql.binlog.BinaryLogClient$7.run(BinaryLogClient.java:793) [mysql-binlog-connector-java-0.13.0.jar:0.13.0
]
        at java.lang.Thread.run(Thread.java:745) [?:1.8.0_121]
Caused by: java.net.SocketException: Connection reset
        at java.net.SocketInputStream.read(SocketInputStream.java:210) ~[?:1.8.0_121]
        at java.net.SocketInputStream.read(SocketInputStream.java:141) ~[?:1.8.0_121]
        at com.github.shyiko.mysql.binlog.io.BufferedSocketInputStream.read(BufferedSocketInputStream.java:51) ~[mysql-binlog-connector-
java-0.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.io.ByteArrayInputStream.readWithinBlockBoundaries(ByteArrayInputStream.java:202) ~[mysql-binlo
g-connector-java-0.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.io.ByteArrayInputStream.read(ByteArrayInputStream.java:184) ~[mysql-binlog-connector-java-0.13
.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.io.ByteArrayInputStream.readInteger(ByteArrayInputStream.java:46) ~[mysql-binlog-connector-jav
a-0.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.event.deserialization.AbstractRowsEventDataDeserializer.deserializeLong(AbstractRowsEventDataD
eserializer.java:212) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.event.deserialization.AbstractRowsEventDataDeserializer.deserializeCell(AbstractRowsEventDataD
eserializer.java:150) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.event.deserialization.AbstractRowsEventDataDeserializer.deserializeRow(AbstractRowsEventDataDeserializer.java:132) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.event.deserialization.WriteRowsEventDataDeserializer.deserializeRows(WriteRowsEventDataDeserializer.java:64) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.event.deserialization.WriteRowsEventDataDeserializer.deserialize(WriteRowsEventDataDeserializer.java:56) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.event.deserialization.WriteRowsEventDataDeserializer.deserialize(WriteRowsEventDataDeserializer.java:32) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
        at com.github.shyiko.mysql.binlog.event.deserialization.EventDeserializer.deserializeEventData(EventDeserializer.java:210) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
        ... 5 more
03:19:31,514 INFO  BinlogConnectorLifecycleListener - Binlog disconnected.
03:19:31,590 WARN  BinlogConnectorReplicator - replicator stopped at position: mysql-bin.006236:520531744 -- restarting
03:19:31,595 INFO  BinaryLogClient - Connected to rm-xxxxxx.mysql.rds.aliyuncs.com:3306 at mysql-bin.006236/520531744 (sid:6379, cid:9220521)
```

### tableMapCache
前面讲过，如果我只想获取某几个表的binlog变更，需要用 `include_tables` 来过滤，但如果mysql server上现在删了一个表t1，但我的binlog是从昨天开始读取，被删的那个表t1在maxwell启动的时候是拉取不到表结构的。然后昨天的binlog里面有 t1 的变更，因为找不到表结构给来组装成json，会抛异常。

手动在 maxwell.tables/columns 里面插入记录是可行的。但这个问题的根本是，maxwell在binlog过滤的时候，只在处理row_event的时候，而对 tableMapCache 要求binlog里面的所有表都要有。

自己提交了一个commit，可以在做 tableMapCache 的时候也仅要求缓存 include_dbs/tables 这些表： https://github.com/seanlook/maxwell/commit/2618b70303078bf910a1981b69943cca75ee04fb

### 提高消费性能
再用rabbitmq时，routing_key 是 `%db%.%table%`，但某些表产生的binlog增量非常大，就会导致各队列消息量很不平均，目前因为还没做到事务xid或者thread_id级别的并发回放，所以最小队列粒度也是表，尽量单独放一个队列，其它数据量小的合在一起。


**参考**
- http://maxwells-daemon.io/config/
- [实时抓取MySQL的更新数据到Hadoop](http://bigdatadecode.club/%E5%AE%9E%E6%97%B6%E6%8A%93%E5%8F%96MySQL%E7%9A%84%E6%9B%B4%E6%96%B0%E6%95%B0%E6%8D%AE%E5%88%B0Hadoop.html)
- [MySQL CDC, Streaming Binary Logs and Asynchronous Triggers](https://www.percona.com/blog/2016/09/13/mysql-cdc-streaming-binary-logs-and-asynchronous-triggers/)

---

原文连接地址：http://xgknight.com/2018/01/13/maxwell-binlog/

---
