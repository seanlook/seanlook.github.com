---
title: Binlog可视化搜索：实现类似阿里RDS数据追踪功能
date: 2018-01-25 15:32:49
aliases:
- /2018/01/25/maxwell-graylog/
tags: [mysql, binlog]
categories:
- MySQL
updated: 2018-01-25 15:32:49
---

MySQL Binlog 里面记录了每行数据的变更，开发有时候需要根据这些变更的时间、中间值去查问题，是bug导致的，还是用户操作引发的。然而原始binlog内容不利于检索，有段时间使用阿里RDS企业版DMS数据追踪的功能，也能完成这个工作，甚至生成回滚sql，后由于收费以及容量不够的缘故，放弃不用。

本文所介绍的就是基于外面开源的各类组件，整合起来，达到类似数据追踪的功能 —— binlog 可视化。
功能类似：[10分钟搭建MySQL Binlog分析+可视化方案](https://yq.aliyun.com/articles/338423)

## 1. 主要技术

项目地址： https://github.com/seanlook/maxwell-graylog

- docker  
  使用容器来实现资源的申请和释放，毕竟这类检索binlog内容的需求不多。 
  本文基于阿里云的容器服务。  

- maxwell  
  从mysql server获取binlog和字段信息，组装成json流。建议先阅读 http://xgknight.com/2018/01/13/maxwell-binlog/  
  官网：http://maxwells-daemon.io/  

- graylog  
  代替ELK技术栈的日志收集、处理、展示平台。社区版够用，需要自行安装，也可以把 graylog 换成 ELK stack。  
  官网：https://www.graylog.org/  

- nxlog  
  nxlog 是用 C 语言写的一个开源日志收集处理软件，它是一个模块化、多线程、高性能的日志管理解决方案，支持多平台。  
  参考：http://blog.csdn.net/weixin_29477879/article/details/52183746  

- rabbitmq  
  一款开源消息队列中间件，采用Erlang语言开发，RabbitMQ是AMQP(Advanced Message Queueing Protocol)的标准实现。建议先阅读 http://xgknight.com/2018/01/06/rabbitmq-introduce/ 。  
  你也可以把消息队列换成kafka。

![maxwell-graylog.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/maxwell-graylog.png)

## 2. 使用说明
### 2.1 举例
> 查看 some3 库 2018-01-22 13:00:00 ~ 2018-01-22 13:00:00 之间，表 t_ecsome_detail 的binlog变化，graylog根据AMQP协议从rabbitmq取binlog json流

提前创建一个 Swarm容器集群，名字叫 maxwell。  
![compose-template.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/compose-template.png)

在【编排模板】里选择 *maxwell-graylog-rabbitmq*，【创建应用】下一步修改编排模板：
（只修改 environment 里面的变量值）
```
mysql-binlogsvr:
  image: registry-vpc.cn-hangzhou.aliyuncs.com/workec/mysql_binlogsvr:1.1.3
  volumes:
    - maxwellgraylog_db_data:/var/lib/mysql
  environment:
    DBINSTANCE_ID: rm-bp19t9it7c2998633
    START_TIME: '2018-01-22 13:00:00'
    END_TIME: '2018-01-22 14:00:00'
    ACCESS_ID: LTAIXKHm0v6ob5P4
    ACCESS_SECRET: F7g***************Nll19no
    MYSQL_ROOT_PASSWORD: strongpassword

maxwell-svr:
  image: registry-vpc.cn-hangzhou.aliyuncs.com/workec/maxwell_graylog:1.1.3
  depends_on:
    - mysql-binlogsvr
  environment:
    producer: rabbitmq
    MYSQL_HOST:
    MYSQL_USER:
    MYSQL_PASSWORD:
    MYSQL_HOST_GIT: db_some_shard3
    include_dbs:
    include_tables: t_ecsome_detail
    include_column_values:
    init_position:
    rabbitmq_host: 10.81.xx.xxx
    rabbitmq_virtual_host: /maxwell
    rabbitmq_user: admin
    rabbitmq_pass: admin
    kafka_server:
    kafka_producer_partition_by: database
    MAXWELL_OPTS:
  volumes:
    - maxwellgraylog_db_data:/var/lib/mysql
  links:
    - mysql-binlogsvr:mysql_binlogsvr
```

### 2.2 变量/参数说明：
- `DBINSTANCE_ID`  
  需要分析哪个实例的binlog。必须提供  
- `ACCESS_ID`, `ACCESS_SECRET`  
  从OSS下载该实例binlog的key，这个key的用户需要RDS的读权限。必须提供  
- `START_TIME`, `END_TIME`  
  需要分析 binlog 大致位于哪个时间段。请尽可能的精确，如果时间范围过大，可能耗时非常久。3个binlog入完graylog大约6分钟。不能保持示例默认的值  
  如果你想从 `MYSQL_HOST` 直接在线拉取binlog，则不要设置设置 START_TIME 和 END_TIME，程序会一致从当前位置持续读取。  
- `MYSQL_ROOT_PASSWORD`  
  mysql binlogsvr 的root的密码。默认为 strongpassword  
<!-- more -->
- `producer`  
  指定maxwell产生的binlog json流输出到哪里，完整的支持`file`, `rabbitmq`, `kafka`  
- `MYSQL_HOST`, `MYSQL_USER`, `MYSQL_PASSWORD`  
  它在两种情况下使用：  
  1. 前面的`START_TIME`、`END_TIME`留空，这里的 MYSQL_HOST 代表的是maxwell直接连接的地址，持续获取binlog。maxwell的 schema_database 也在这个库上(monitor，用户需要有读写这个db的权限)  
  2. 前面的`START_TIME`、`END_TIME`有值，并且没有设置 `MYSQL_HOST_GIT`，那么 MYSQL_HOST 代表的是从这个地址拉取表结构，相当于maxwell的 schema_host 地址（当然获取binlog还是从 mysql_binlogsvr ）  
- `MYSQL_HOST_GIT`, `MYSQL_HOST_GIT_COMMIT`  
  从git仓库拉取表结构信息，`MYSQL_HOST_GIT`指定仓库里面实例目录名，`MYSQL_HOST_GIT_COMMIT`可以满足指定某个 提交 时候的表机构版本。在 START_TIME, END_TIME 有设置的情况下才有效。  
  仓库见：http://xgknight.com/2016/11/28/mysql-schema-gather-structure/
- `rabbitmq_host`, `rabbitmq_virtual_host`, `rabbitmq_user`, `rabbitmq_pass`, `rabbitmq_exchange_type`  
  在 producer=rabbitmq 才有效。这些rabbitmq_xxx选项，与maxwell配置文件里面的完全相同  
- 过滤选项  
  `include_dbs`, `include_tables`, `include_column_values`  
  与maxwell配置文件里面的完全相同。这里没有列出 exclude_xxx 相关过滤项，如果要指定，请使用 `MAXWELL_OPTS`  
  `exclude_columns`，去除哪些列是值不予展示，可用于脱敏。  
  支持的值参考maxwell的配置文件里面正则说明。  
- `kafka_server`  
  在 rabbitmq=kafka 时有效。对应 maxwell 的 `kafka.bootstrap.servers` 选项  
  其它选项如果要指定，可以使用`MAXWELL_OPTS`  
- `MAXWELL_OPTS`  
  因为现有 environment 变量没有覆盖所有的maxwell选项，所有其它选项可以直接像 maxwell 命令行参数一样，指定在 `MAXWELL_OPTS` 里面。

创建完后，可以看到两个容器：  
![maxwell-binlog-container.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/maxwell-binlog-container.png)

其中 `maxwell-svr` 在等待 mysql_binlogsvr 就绪:
```
maxwell-graylog-rabbitmq-some3_maxwell-svr_1 | 2018-01-26T11:58:08.424411112Z waiting for mysql_binlogsvr prepared
maxwell-graylog-rabbitmq-some3_maxwell-svr_1 | 2018-01-26T11:58:28.427993770Z waiting for mysql_binlogsvr prepared
maxwell-graylog-rabbitmq-some3_maxwell-svr_1 | 2018-01-26T11:58:48.431136523Z binlog download is done, wait more seconds for mysql_binlogsvr ready
```

`mysql-binlogsvr` 在初始化 mysql server 的数据，下载binlog。完成的标志是在 `/var/lib/mysql/initialized.lock`里面写入 1 或 2，来通知 maxwell-svr。（1和2的意义见下面的Dockerfile说明）
在 `maxwell-svr` 日志里面看到 `INFO  BinlogConnectorLifecycleListener - Binlog connected.` 字样，表示已经在binlog往外推。

此时在 graylog 里面就可以看到输出内容了: http://graylog.workec.com:3003/search?q=gl2_source_input%3A5a655c3ba002a0526615062a&relative=0

处理速度大概在 10000msg/s，在graylog里面没有看到新数据进来，就代表分析完成。
现在比较麻烦的地方在于，处理完结束后，销毁容器容易，但前面创建的持久存储卷，阿里云的容器服务并不会删除本地的卷，它所提供的存储推荐是 OSS,NAS,云盘 这些存储服务，然后要为它单独创建子账号，单独对某个盘、bucket授权，十分麻烦。

本地卷并不能自动的删除，如果下次启动这个binlog分析服务，因为挂在的是同样的 db_data，里面已经有脏数据，所以需要**手动删除** 主机上的 `rm -rf /var/lib/docker/volumes/maxwellgraylog_db_data/_data/*`

### 2.3 其它编排模板
上面的示例，是基于 `maxwell-graylog-rabbitmq` 的编排模板，已经自定义了一下compose模板：
- `maxwell-graylog-rabbitmq`  
  依赖于外部 rabbitmq server，需要明确指定 `rabbitmq_host` 等信息。  
  第一次使用，通过`rabbitmq-init-for-maxwell.sh`去初始化 maxwell-graylog 所需要的exchange,queue等。

- `maxwell-graylog-rabbitmq-nodeps`  
  会比上面的多起一个容器： rabbitmq-server，但是它的数据要通过容器集群的LB，才能被外面的graylog服务消费。 
  它的 `rabbitmq_host`被指定为`maxwell-rabbitmq-server` (container link)

- `maxwell-graylog-file`  
  不适用消息队列，直接写入文件，通过 nxlog 将数据推到 graylog，所以会多出一个 nxlog 容器
  多出三个 environment variabeles:  
  - `graylogserver`  
    nxlog将“日志”上报的 graylog server 地址  
  - `graylog_maxwell_gelf_port`  
    graylog 节点为接收这个消息监听的端口 (NXlog Outputs)  
  - `graylog_maxwell_source_collector`  
    graylog 为这个消息定义好的collecter名字 （collecter是graylog的入口，在它之上定义流转、拆解、存储等流程）

  graylog的配置方法和搜索使用，见后文。

- `maxwell-graylog-kafka`  
  使用 kafka 作为消息队列。需要指定现有的 kafka_server 。  
  这个编排模板，没有提供很详细的实现，请结合 `MAXWELL_OPTS` 使用。

**提示：**
1. 在使用时，如果容器启动失败，观察日志后，一般可以放心的直接重启容器，已做良好的修复处理。  
2. 选择哪个模板和设置什么变量值，主要考虑两个因素：从哪里获取binlog，maxwell将binlog生产到哪里
3. 输出到file，nxlog读取的交给graylog处理的压力会非常大，可能会导致graylog响应慢。输出到rabbitmq，可以控制流入graylog的速度(Allow throttling this input?)

### 2.4 docker-compose.yml
阿里云的编排模板，与标准的 docker compose 并不完全一样。在 docker-compose 目录中，提供了6种编排方案，可使用自建的docker平台来做。
4个容器和变量的组合，应对不同的场景：
- **docker-compose.file.yml**  
  启动 mysql-binlogsvr, maxwell-svr, nxlog-svr 三个容器，binlog数据写入file。

- **docker-compose.file-schema.yml**  
  启动 mysql-binlogsvr, maxwell-svr, nxlog-svr 三个容器，binlog数据写入file。  
  表结构从 schema_host 获取，而不是git仓库。monitor用户需要 REPLICATION SLAVE, REPLICATION CLIENT 权限。

- **docker-compose.rabbitmq.yml**  
  启动 mysql-binlogsvr, maxwell-svr 两个容器，binlog数据写入现有rabbitmq。

- **docker-compose.rabbitmq-nodeps.yml**  
  启动 mysql-binlogsvr, maxwell-svr, rabbitmq-server 三个容器，binlog数据写入rabbitmq容器。  
  不依赖外部rabbitmq。

- **docker-compose.rabbitmq-nobinlog-svr.yml**  
  启动 mysql-binlogsvr, maxwell-svr, rabbitmq-server 三个容器，binlog数据写入rabbitmq容器。  
  mysql-binlogsvr启动后会停止，这里直接从 MYSQL_HOST 在线持续拉取binlog，用户需要能够读取表结构的权限。

-  **docker-compose.kafka.yml**  
  启动 mysql-binlogsvr, maxwell-svr 两个容器，binlog数据写入现有kafka。

也可以逐个启动容器，不适用 docker-compose.yml。各个容器详情见后文。


## 3. graylog配置和使用
生成的binlog json流要在graylog里面可视化展示，还需要对graylog设置。下面分别以 file 和 rabbitmq 的输出为例。

### 3.1 Input: file
上面已经通过 maxwell容器 将数据写入了 `output_file`=`/var/lib/mysql/maxwell_binlog_stream.json.log`，又通过 nxlog容器 tail监控这个日志文件。

1. **创建一个 GELF TCP Input**
[System / Inputs] -> [Inputs]  
![graylog-fileinput.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/graylog-fileinput.png)

![graylog-fileinput-create.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/graylog-fileinput-create.png)

勾选 Global 表示所有的 graylog 集群节点，都可以接收这个日志，Port： `12201` 便是监听的端口。前文编排模板里面要求提供的参数 `graylogserver` 和 `graylog_maxwell_gelf_port`，就是从这来的。

那么 Collecter `graylog_maxwell_source_collector` 呢，可以任意设置一个字符串。在标准的 graylog 配置流程里面，collecter 就是一个 nxlog 进程，一般一台机器就一个 nxlog，所以collecter对应的其实是收集日志的机器。

nxlog 是一个单独的组件，与graylog没多大关系，而为了将两者整合在一起，需要 graylog-sidecar 来下发 nxlog 的配置，告诉它日志目录在哪、怎么读取日志。

所以我们的docker容器只需要nxlog进程，不需要graylog-sidecar来交代配置，也就不需要在graylog Web界面配置NXLog Outputs/Inputs，而是直接通过变量传递来完成 nxlog.conf 模板的配置。

下面的过程实际是不需要的，只是为了理解如何生成 nxlog.conf。

2. Create configuration
给这个 configuration 设置 `tags` 例如`maxwell_binlog`。  
![graylog-nxlog-config.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/graylog-nxlog-config.png)

graylog-sidecar 会把 tag 打给某个机器(collecter)，告诉nxlog或其他收集组件，当前机器有哪几种日志需要收集

3. 编写 NXLog Outputs
相当于 nxlog.conf 中 `<Output>`部分，Host、Port 即第1步里面的graylog接收binlog json流而监听的地址和端口。
Type选择 `[NXLog]GELF TCP output`。  
![graylog-nxlog-output.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/graylog-nxlog-output.png)

4. 编写 NXLog Inputs
相当于 nxlog.conf 中 `<Input>`部分，这里指定日志输入来源于**文件**,`Type`选择`[NXLog]file input`  
![graylog-nxlog-input.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/graylog-nxlog-input.png)

`Forward to` 设置刚才创建的 Output
`File`，要收集的日志路径为`/var/lib/mysql/maxwell_binlog_stream.json.log`
`Pool Interval`，即检查日志文件的间隔时间。剩下的保持默认

5. **使用 JSON extractor 解析message**
经过上面几步，启动maxwell和nxlog服务/容器之后，在graylog的 WebUI 上找到第1步建的Input，就可以看到有日志进来了。  
![maxwell-graylog-message.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/maxwell-graylog-message.png)

选择任意一个message，[Create extractor for field message] -> [JSON]，将json数据解压出来，存储，便可以快速根据字段名来搜索binlog内容。

### 3.2 Input: rabbitmq
使用rabbitmq更简单，不需要nxlog，直接在第1步里，把新建`GELF TCP`改成`Raw/Plaintext AMQP`。  
![maxwell-graylog-rabbitmq.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/maxwell-graylog-rabbitmq.png)

需要填写的就是AMQP协议里broker, port, user, exchange, queue, routing_key。
就可以在binlog里面，可视化看到binlog内容了。

### 3.3 在graylog里面搜索binlog日志
搜索语法：http://docs.graylog.org/en/2.4/pages/queries.html

例如，查看 t_ecsome_detail 表中 f_some_id=1242036566 在给定时间内的变化过程：
```
gl2_source_input:5a38cc9bd56c001305aaefc0 AND data_f_some_id: 1242036566 OR old_f_some_id: 1242036566
```

例如使用Quick values功能，快速得到全国各地区对t_ecsome_detail表的操作量：
```
gl2_source_input:5a38cc9bd56c001305aaefc0 AND NOT data_f_company_region: 0
```

我们有做db分库，查看各个分库下的请求量数据是不是平均的，database: quick value：  
![maxwell-graylog-quickvalue.png](http://github.com/seanlook/sean-notes-comment/raw/main/static/maxwell-graylog-quickvalue.png)

## 4. 容器镜像说明：Dockerfile
本节是关于细节实现的部分，与上面的介绍会略有重复。

### 4.1 Dockerfile.binlogsvr
承载 binlog 的mysql server服务。  
它首先根据提供的数据库实例信息、日期时间信息，去OSS拉取已经上传的binlog到本地，修改 `mysql-bin.index`文件，提供binlog来源。  
因为容器停止或者销毁后，内部的数据也随之丢失，所以需要一个主机上的目录来挂在到容器中，做数据的持久化，我们把这个数据卷命名为 db_data 。

 - `binlogsvr-entrypoint.sh`  
   容器入口。因为 mysql server 启动第一次都要进行初始化，假如容器启动失败，再次启动时不需要再次初始化。  
   脚本内通过 `lockfile=/var/lib/mysql/initialized.lock` 区分三种工作模式：  
   - lockfile 存在：mysql server 已经初始化  
   - lockfile 内容为0：mysql server 作为binlogsvr  
   - lockfile 内容为2: binlog已经下载完成。避免重启容器导致重复下载binlog  
   - lockfile 内容为1：该容器无用，因为判断 START_TIME 和 END_TIME 为空。实际上表示后续maxwell  拉取，是直接从原 MYSQL_HOST 读取，不需要该binlogsvr  
   lockfile 里面的值会被 maxwell 容器读取，以便决定工作模式

- `download_binlog.py`  
  从阿里OSS下载binlog，需要提供 DBINSTANCE_ID 和 时间界限。  
  requirements.txt：python环境依赖

- `mysql_3306.cnf`  
  binlogsvr的启动配置文件

### 4.2 Dockerfile.maxwell
  maxwell服务容器，主版本1.12.0，加上修改了点内容：https://github.com/seanlook/maxwell  
  - `maxwell-entrypoint.sh`  
    容器入口。会等待 mysql_binlogsvr 初始化完成，maxwell的结构、postion等信息存放在binlogsvr的 monitor 库。  
    - `work_mode=1`: 直接从 `MYSQL_HOST` 拉取binlog，不需要binlogsvr，可以实现持续读取现网的binlog  
    - `work_mode=0`: 从 mysql_binlogsvr 拉取binlog  
      该模式下因为 binlogsvr 里并没有maxwell需要的表结构，支持两种方法： 
      - 如果设置了 `MYSQL_HOST_GIT`，表示从我们的git仓库里面拉取表结构  
      - 否则从 `MYSQL_HOST` 拉取表结构，对应maxwell变量 `schema_host` 。即这个时候的 MYSQL_HOST 不是指定binlog来源，而是表结构来源。  
      - 如果都没设置，异常退出  

    maxwell启动时需要指定 init_position，即从binlog_svr哪个binlog位置开始拉取：  
    - 如果从直接从原数据库实例拉取，则指定为最新的binlog起始点；  
    - 如果为 binlogsvr 拉取，则指定为下载的binlog最小的那个binlog起始点；  
    - 在容器启动的时候，也可以直接指定 init_postion ，优先生效。  
    `lockfile=/var/lib/mysql/initialized_maxwell.lock` 表示已经通过 init_postion 启动，如果重启maxwell容器，应该从上次停止的地方继续。

    容器启动时，可以指定 producer 为 file, rabbitmq, kafka，根据对应的生产者，应该设置子选项。见后文。  

- `maxwell-retrive-tablemeta.sh`  
  从git拉取所需要的表结构，并用 myloader 工具导入到 binlogsvr 。  
  因为考虑到需求通常要过滤表，所以这里也这会在 binlogsvr 创建需要的表结构。  
  如果指定了 `MYSQL_HOST_GIT_COMMIT`，可以拉取git上历史表结构。  
  `id_rsa`：文件是拉起表结构用的 ssh key。 

- `maxwell-src-1.12.0.tar.gz`:  
  已下载的maxwell包，会通过maven编译。  

### 4.3 Dockerfile.nxlog
  在 `producer=file` 时，maxwell产生的binlog stream 是文件，要把文件放到 graylog 用到 nxlog 。  
  它也会挂在 db_data，读取 `output_file=/var/lib/mysql/maxwell_binlog_stream.json.log` 内容，发送到 graylog server 。  
  - `graylogserver`: graylog server 地址  
  - `graylog_maxwell_gelf_port`: 在graylog提前配置好的接收maxwell数据的端口  
  - `graylog_maxwell_source_collector`: 对应graylog的 collector id.  
  配置graylog 方法见后文。  

  - `nxlog-entrypoint.sh`  
    容器入口。主要是对 /etc/nxlog/nxlog.conf 进行变量替换。  
    提示：也会读取 `/var/lib/mysql/maxwell_instance_id` 里面由 mysql_binlogsvr 传递过来的 instance_id 作为 message 的一部分
      
  - `nxlog.conf`  
    nxlog的配置文件模板，用于替换成上面的变量。  

### 4.4 Dockerfile.rabbitmq
  在 `producer=rabbitmq` 时，maxwell需要 rabbitmq server 作为队列。  
  这里提供两种使用方法：  
  - 如果已经有现成的 rabbitmq ，则自己创建 vhost, exchange, user，需要提供的内容见 `rabbitmq-init-formaxwell.sh`  
  - 如果没有rabbitmq，则通过这个 Dockerfile 创建 rabbitmq server container  

  - `rabbitmq-entrypoint.sh`  
    容器入口。只是为了调用 `rabbitmq-init-formaxwell.sh`，在rabbitmq起来后，创建 `--vhost=/maxwell --username=admin --password=admin`,`exchange=maxwell.binlog queue=maxwell_binlog binding_key=#` 给maxwell和graylog使用。  
    在后台通过 [`wait-for-it.sh`](https://github.com/vishnubob/wait-for-it) 来同步等待 rabbitmq ok.  

### 4.5 build image

```
docker build -f Dockerfile.binlogsvr . -t registry-vpc.cn-hangzhou.aliyuncs.com/workec/mysql_binlogsvr:1.1.3
docker build -f Dockerfile.maxwell . -t registry-vpc.cn-hangzhou.aliyuncs.com/workec/maxwell_graylog:1.1.3
docker build -f Dockerfile.nxlog . -t registry-vpc.cn-hangzhou.aliyuncs.com/workec/maxwell_nxlog:0.4.3
docker build -f Dockerfile.rabbitmq . -t registry-vpc.cn-hangzhou.aliyuncs.com/workec/maxwell_rabbitmq:0.4.3

docker push registry-vpc.cn-hangzhou.aliyuncs.com/workec/mysql_binlogsvr:1.1.3
docker push registry-vpc.cn-hangzhou.aliyuncs.com/workec/maxwell_graylog:1.1.3
docker push registry-vpc.cn-hangzhou.aliyuncs.com/workec/maxwell_nxlog:0.4.3
docker push registry-vpc.cn-hangzhou.aliyuncs.com/workec/maxwell_rabbitmq:0.4.3
```

**参考**


---

原文连接地址：http://xgknight.com/2018/01/25/maxwell-graylog/

---
