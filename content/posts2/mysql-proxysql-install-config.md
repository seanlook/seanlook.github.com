---
title: ProxySQL之安装及配置详解
date: 2017-04-10 21:32:49
tags: [mysql, 中间件, proxysql]
categories:
- MySQL
updated: 2017-04-10 21:32:49
---

ProxySQL是一个高性能的MySQL中间件，拥有强大的规则引擎。具有以下特性：

- 连接池，而且是 [multiplexing](http://xgknight.com/2017/04/17/mysql-proxysql-multiplexing/)
- 主机和用户的最大连接数限制
- 自动下线后端DB
  - 延迟超过阀值
  - ping 延迟超过阀值
  - 网络不通或宕机
- 强大的规则路由引擎
 - 实现读写分离
 - 查询重写
 - sql流量镜像
- 支持prepared statement
- 支持Query Cache
- 支持负载均衡，与gelera结合自动failover

集这么多优秀特性于一身，那么缺点呢就是项目不够成熟，好在作者一直在及时更新，并且受到 Percona 官方的支持。

# 1. 安装
从 https://github.com/sysown/proxysql/releases 下载相应的版本。这里我选择 `proxysql-1.3.5-1-centos67.x86_64.rpm`，也是当前最新稳定版。 

```
yum localinstall proxysql-1.3.5-1-centos67.x86_64.rpm -y
```

可以马上启动了：
```
/etc/init.d/proxysql start
Starting ProxySQL: DONE!
```

proxysql有个配置文件 `/etc/proxysql.cnf`，只在第一次启动的时候有用，后续所有的配置修改都是对SQLite数据库操作，并且不会更新到proxysql.cnf文件中。ProxySQL绝大部分配置都可以在线修改，配置存储在  `/var/lib/proxysql/proxysql.db` 中，后面会介绍它的在线配置的设计方式。

proxysql 启动后会像 mysqld 一样，马上fork一个子进程，真正处理请求，而父进程负责监控子进程运行状况，如果crash了就拉起来。

## 编译安装
```
安装高版本 gcc-4.8
# cd /etc/yum.repos.d
# wget https://copr.fedoraproject.org/coprs/rhscl/devtoolset-3/repo/epel-6/rhscl-devtoolset-3-epel-6.repo  \
  -O /etc/yum.repos.d/rhscl-devtoolset-3-epel-6.repo
# yum install -y  scl-utils policycoreutils-python
# yum --disablerepo='*' --enablerepo='rhscl-devtoolset-3' install devtoolset-3-gcc devtoolset-3-gcc-c++ devtoolset-3-binutils
# yum --enablerepo=testing-devtools-2-centos-6 install devtoolset-3-gcc devtoolset-3-gcc-c++ devtoolset-3-binutils

上一步会把 GCC 安装到以下目录 /opt/rh/devtoolset-3/root/usr/bin

接下来需要修改系统的配置，使默认的 gcc 和 g++ 命令使用的是新安装的版本。启用SCL环境中新版本GCC：
# scl enable devtoolset-3 bash
 
现在查看 g++ 的版本号：
# gcc --version

编译安装proxysql
# cd proxysql-master
# make
# make install
```

# 2. 内置库表介绍
### 2.1 内置“库”
首先登陆到 proxysql 之后才能进一步配置：
```
$ export MYSQL_PS1="(\u@\h:\p) [\d]> "
$ mysql -uadmin -padmin -h127.0.0.1 -P6032
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 2
Server version: 5.6.30 (ProxySQL Admin Module)

(admin@127.0.0.1:6032) [(none)]> show databases;
+-----+---------+-------------------------------+
| seq | name    | file                          |
+-----+---------+-------------------------------+
| 0   | main    |                               |
| 2   | disk    | /var/lib/proxysql/proxysql.db |
| 3   | stats   |                               |
| 4   | monitor |                               |
+-----+---------+-------------------------------+
```

默认管理端口是6032，客户端服务端口是6033。默认的用户名密码都是 `admin`。 
- `main` 是默认的"数据库"名，表里存放后端db实例、用户验证、路由规则等信息。表名以 `runtime_`开头的表示proxysql当前运行的配置内容，不能通过dml语句修改，只能修改对应的不以 runtime_ 开头的（在内存）里的表，然后 `LOAD` 使其生效， `SAVE` 使其存到硬盘以供下次重启加载。
- `disk` 是持久化到硬盘的配置，sqlite数据文件。
- `stats` 是proxysql运行抓取的统计信息，包括到后端各命令的执行次数、流量、processlist、查询种类汇总/执行时间，等等。
- `monitor` 库存储 monitor 模块收集的信息，主要是对后端db的健康/延迟检查。

`global_variables` 有80多个变量可以设置，其中就包括监听的端口、管理账号、禁用monitor等，详细可参考 https://github.com/sysown/proxysql/wiki/Global-variables 。

```
(admin@127.0.0.1:6032) [(none)]> show tables;
+--------------------------------------+
| tables                               |
+--------------------------------------+
| global_variables                     |
| mysql_collations                     |
| mysql_query_rules                    |
| mysql_replication_hostgroups         |
| mysql_servers                        |
| mysql_users                          |
| runtime_global_variables             |
| runtime_mysql_query_rules            |
| runtime_mysql_replication_hostgroups |
| runtime_mysql_servers                |
| runtime_mysql_users                  |
| runtime_scheduler                    |
| scheduler                            |
+--------------------------------------+
13 rows in set (0.00 sec)

(admin@127.0.0.1:6032) [(none)]> show tables from stats;
+--------------------------------+
| tables                         |
+--------------------------------+
| global_variables               |
| stats_mysql_commands_counters  |
| stats_mysql_connection_pool    |
| stats_mysql_global             |
| stats_mysql_processlist        |
| stats_mysql_query_digest       |
| stats_mysql_query_digest_reset |
| stats_mysql_query_rules        |
+--------------------------------+
8 rows in set (0.00 sec)
```

### 2.2 表 `mysql_servers`
```
(admin@127.0.0.1:6032) [(none)]> show create table mysql_servers\G
*************************** 1. row ***************************
       table: mysql_servers
Create Table: CREATE TABLE mysql_servers (
    hostgroup_id INT NOT NULL DEFAULT 0,
    hostname VARCHAR NOT NULL,
    port INT NOT NULL DEFAULT 3306,
    status VARCHAR CHECK (UPPER(status) IN ('ONLINE','SHUNNED','OFFLINE_SOFT', 'OFFLINE_HARD')) NOT NULL DEFAULT 'ONLINE',
    weight INT CHECK (weight >= 0) NOT NULL DEFAULT 1,
    compression INT CHECK (compression >=0 AND compression <= 102400) NOT NULL DEFAULT 0,
    max_connections INT CHECK (max_connections >=0) NOT NULL DEFAULT 1000,
    max_replication_lag INT CHECK (max_replication_lag >= 0 AND max_replication_lag <= 126144000) NOT NULL DEFAULT 0,
    use_ssl INT CHECK (use_ssl IN(0,1)) NOT NULL DEFAULT 0,
    max_latency_ms INT UNSIGNED CHECK (max_latency_ms>=0) NOT NULL DEFAULT 0,
    comment VARCHAR NOT NULL DEFAULT '',
    PRIMARY KEY (hostgroup_id, hostname, port) )
1 row in set (0.00 sec)

(admin@127.0.0.1:6032) [(none)]> select * from mysql_servers;
+--------------+--------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------------+
| hostgroup_id | hostname     | port | status | weight | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment       |
+--------------+--------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------------+
| 100          | 10.0.100.100 | 3307 | ONLINE | 1      | 0           | 1000            | 0                   | 0       | 0              | db0,ReadWrite |
| 1000         | 10.0.100.100 | 3307 | ONLINE | 1      | 0           | 1000            | 0                   | 0       | 0              | db0,ReadWrite |
| 1000         | 192.168.10.4 | 3316 | ONLINE | 4      | 0           | 1000            | 0                   | 0       | 0              | db0,ReadOnly  |
| 101          | 10.0.100.101 | 3307 | ONLINE | 1      | 0           | 1000            | 0                   | 0       | 0              | db1,ReadWrite |
| 1001         | 192.168.10.4 | 3326 | ONLINE | 1      | 0           | 1000            | 0                   | 0       | 0              | db1,ReadOnly  |
+--------------+--------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------------+
```

- `hostgroup_id`: ProxySQL通过 hostgroup (下称HG) 的形式组织后端db实例。一个 HG 代表同属于一个角色
  - 该表的主键是 `(hostgroup_id, hostname, port)`，可以看到一个 hostname:port 可以在多个hostgroup里面，如上面的 10.0.100.100:3307，这样可以避免 HG 1000 的从库全都不可用时，依然可以把读请求发到主库上。
  - 一个 HG 可以有多个实例，即多个从库，可以通过 `weight` 分配权重
  - hostgroup_id 0 是一个特殊的HG，路由查询的时候，没有匹配到规则则默认选择 HG 0
- `status`: 
  - `ONLINE`: 当前后端实例状态正常
  - `SHUNNED`: 临时被剔除，可能因为后端 too many connections error，或者超过了可容忍延迟阀值 `max_replication_lag`
  - `OFFLINE_SOFT`: "软离线"状态，不再接受新的连接，但已建立的连接会等待活跃事务完成。
  - `OFFLINE_HARD`: "硬离线"状态，不再接受新的连接，已建立的连接或被强制中断。当后端实例宕机或网络不可达，会出现。
- `max_connections`: 允许连接到该后端实例的最大连接数。不要大于MySQL设置的 max_connections
  如果后端实例 hostname:port 在多个 hostgroup 里，以较大者为准，而不是各自独立允许的最大连接数。
- `max_replication_lag`: 允许的最大延迟，主库不受这个影响，默认0。如果 > 0， monitor 模块监控主从延迟大于阀值时，会临时把它变为 SHUNNED 。
- `max_latency_ms`: mysql_ping 响应时间，大于这个阀值会把它从连接池剔除（即使是ONLINE）
- `comment`: 备注，不建议留空。这有什么好讲呢，但是你可以通过它的内容如json格式的数据，配合自己写的check脚本，完成一些自动化的工作。

`compression` 和 `use_ssl` 顾名思义。

### 2.3 表 `mysql_users`
```
(admin@127.0.0.1:6032) [(none)]> show create table mysql_users\G
*************************** 1. row ***************************
       table: mysql_users
Create Table: CREATE TABLE mysql_users (
    username VARCHAR NOT NULL,
    password VARCHAR,
    active INT CHECK (active IN (0,1)) NOT NULL DEFAULT 1,
    use_ssl INT CHECK (use_ssl IN (0,1)) NOT NULL DEFAULT 0,
    default_hostgroup INT NOT NULL DEFAULT 0,
    default_schema VARCHAR,
    schema_locked INT CHECK (schema_locked IN (0,1)) NOT NULL DEFAULT 0,
    transaction_persistent INT CHECK (transaction_persistent IN (0,1)) NOT NULL DEFAULT 0,
    fast_forward INT CHECK (fast_forward IN (0,1)) NOT NULL DEFAULT 0,
    backend INT CHECK (backend IN (0,1)) NOT NULL DEFAULT 1,
    frontend INT CHECK (frontend IN (0,1)) NOT NULL DEFAULT 1,
    max_connections INT CHECK (max_connections >=0) NOT NULL DEFAULT 10000,
    PRIMARY KEY (username, backend),
    UNIQUE (username, frontend))
1 row in set (0.00 sec)

(admin@127.0.0.1:6032) [(none)]> select * from mysql_users;
+----------+-----------+--------+---------+-------------------+----------------+---------------+------------------------+--------------+---------+----------+-----------------+
| username | password  | active | use_ssl | default_hostgroup | default_schema | schema_locked | transaction_persistent | fast_forward | backend | frontend | max_connections |
+----------+-----------+--------+---------+-------------------+----------------+---------------+------------------------+--------------+---------+----------+-----------------+
| user0    | password0 | 1      | 0       | 0                 | NULL           | 0             | 1                      | 0            | 1       | 1        | 10000           |
| read1    | password1 | 1      | 0       | 0                 | NULL           | 0             | 1                      | 0            | 1       | 1        | 10000           |
+----------+-----------+--------+---------+-------------------+----------------+---------------+------------------------+--------------+---------+----------+-----------------+
2 rows in set (0.00 sec)

(admin@127.0.0.1:6032) [(none)]> select username,password,transaction_persistent,active,backend,frontend,max_connections from runtime_mysql_users;
+----------+------------------------------+------------------------+--------+---------+----------+-----------------+
| username | password                     | transaction_persistent | active | backend | frontend | max_connections |
+----------+------------------------------+------------------------+--------+---------+----------+-----------------+
| user0    | *FAB0955B2CE7AE2DAFEE46C3... | 1                      | 1      | 0       | 1        | 10000           |
| read1    | *88A287979B45658C6CE41FB9... | 1                      | 1      | 0       | 1        | 10000           |
| user0    | *FAB0955B2CE7AE2DAFEE46C3... | 1                      | 1      | 1       | 0        | 10000           |
| read1    | *88A287979B45658C6CE41FB9... | 1                      | 1      | 1       | 0        | 10000           |
+----------+------------------------------+------------------------+--------+---------+----------+-----------------+
4 rows in set (0.00 sec)
```

- `username`, `password`: 连接后端db的用户密码。
  这个密码你可以插入明文，也可以插入hash加密后的密文，proxysql会检查你插入的时候密码是否以  `*` 开头来判断，而且密文要在其它地方使用 `PASSWORD()`生成。
  但到 *runtime_mysql_users* 里，都统一变成了密文，所以可以明文插入，再 `SAVE MYSQL USERS TO MEM`，此时看到的也是HASH密文。
- `active`: 是否生效该用户。
- `default_hostgroup`: 这个用户的请求没有匹配到规则时，默认发到这个 hostgroup，默认0
- `default_schema`: 这个用户连接时没有指定 database name 时，默认使用的schema
  注意表面上看默认为NULL，但实际上受到变量 `mysql-default_schema` 的影响，默认为 information_schema。关于这个参考我所提的 issue [#988](https://github.com/sysown/proxysql/issues/988#issuecomment-293876759)
- `transaction_persistent`: 如果设置为1，连接上ProxySQL的会话后，如果在一个hostgroup上开启了事务，那么后续的sql都继续维持在这个hostgroup上，不伦是否会匹配上其它路由规则，直到事务结束。
  虽然默认是0，但我建议还是设成1，虽然一般来说由于前段应用的空值，为0出问题的情况几乎很小。作者也在考虑默认设成 1，[refer this issue #793](https://github.com/sysown/proxysql/issues/793)
- `frontend`, `backend`: 目前版本这两个都需要使用默认的1，将来有可能会把 * Client -> ProxySQL * (frontend) 与 * ProxySQL -> BackendDB * (backend)的认证分开。
  从 *runtime_mysql_users* 表内容看到，记录数比 *mysql_users* 多了一倍，就是把前端认证与后端认证独立出来的结果。
- `fast_forward`: 忽略查询重写/缓存层，直接把这个用户的请求透传到后端DB。相当于只用它的连接池功能，一般不用，路由规则 `.*` 就行了。

### 2.4 表 `mysql_replication_hostgroups`
```
CREATE TABLE mysql_replication_hostgroups (
    writer_hostgroup INT CHECK (writer_hostgroup>=0) NOT NULL PRIMARY KEY,
    reader_hostgroup INT NOT NULL CHECK (reader_hostgroup<>writer_hostgroup AND reader_hostgroup>0),
    comment VARCHAR,
    UNIQUE (reader_hostgroup))
```
定义 hostgroup 的主从关系。ProxySQL monitor 模块会监控 HG 后端所有servers 的 `read_only` 变量，如果发现从库的 read_only 变为0、主库变为1，则认为角色互换了，自动改写 mysql_servers 表里面 hostgroup 关系，达到自动 Failover 效果。

目前这个表我是留空的，它与Gelera或PXC结合起来用比较合适。

### 2.5 表 `mysql_query_rules`
ProxySQL非常核心一个表，定义查询路由规则，参考 https://github.com/sysown/proxysql/wiki/MySQL-Query-Rules ：
```
(admin@127.0.0.1:6032) [(none)]> show create table mysql_query_rules\G
*************************** 1. row ***************************
       table: mysql_query_rules
Create Table: CREATE TABLE mysql_query_rules (
    rule_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    active INT CHECK (active IN (0,1)) NOT NULL DEFAULT 0,
    username VARCHAR,
    schemaname VARCHAR,
    flagIN INT NOT NULL DEFAULT 0,
    client_addr VARCHAR,
    proxy_addr VARCHAR,
    proxy_port INT,
    digest VARCHAR,
    match_digest VARCHAR,
    match_pattern VARCHAR,
    negate_match_pattern INT CHECK (negate_match_pattern IN (0,1)) NOT NULL DEFAULT 0,
    flagOUT INT,
    replace_pattern VARCHAR,
    destination_hostgroup INT DEFAULT NULL,
    cache_ttl INT CHECK(cache_ttl > 0),
    reconnect INT CHECK (reconnect IN (0,1)) DEFAULT NULL,
    timeout INT UNSIGNED,
    retries INT CHECK (retries>=0 AND retries <=1000),
    delay INT UNSIGNED,
    mirror_flagOUT INT UNSIGNED,
    mirror_hostgroup INT UNSIGNED,
    error_msg VARCHAR,
    log INT CHECK (log IN (0,1)),
    apply INT CHECK(apply IN (0,1)) NOT NULL DEFAULT 0,
    comment VARCHAR)
1 row in set (0.00 sec)
```

- `rule_id`: 表主键，自增。规则处理是以 rule_id 的顺序进行。
- `active`: 只有 active=1 的规则才会参与匹配。
- `username`: 如果非 NULL，只有连接用户是 username 的值才会匹配
- `schemaname`: 如果非 NULL，只有查询连接使用的db是 schemaname 的值才会匹配。
  注意如果是 NULL，不代表连接没有使用schema，而是不伦任何schema都进一步匹配。
- `flagIN`, `flagOUT`, `apply`: 用来定义路由链 chains of rules
  - 首先会检查 flagIN=0 的规则，以rule_id的顺序；如果都没匹配上，则走这个用户的 default_hostgroup 
  - 当匹配一条规则后，会检查 `flagOUT`
    - 如果不为NULL，并且 flagIN != flagOUT ，则进入以flagIN为上一个flagOUT值的新规则链
    - 如果不为NULL，并且 flagIN = flagOUT，则应用这条规则
    - 如果为NULL，或者 apply=1，则结束，应用这条规则
    - 如果最终没有匹配到，则找到这个用户的 default_hostgroup
    ![proxysql route chain](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-route-rule-flag.png)
- `client_addr`: 匹配客户端来源IP
- `proxy_addr`, `proxy_port`: 匹配本地proxysql的IP、端口。我目前没有想到它的应用场景，可能是把proxysql监听在多个接口上，分发到不同的业务？
- `digest`: 精确的匹配一类查询。
- `match_digest`: 正则匹配一类查询。query digest 是指对查询去掉具体值后进行“模糊化”后的查询，类似 *pt-fingerprint* / *pt-query-digest* 的效果。
- `match_pattern`: 正则匹配查询。
  以上都是匹配查询的规则，目前1.3.5使用的正则引擎只有 RE2 ，1.4版本可以通过变量 [`mysql-query_processor_regex`](https://github.com/sysown/proxysql/wiki/Global-variables#mysql-query_processor_regex) 设置 RE2 或者 PCRE，且1.4开始默认是PCRE。
  ProxySQL的作者 renecannao 自己推荐用 match_digest 。关于每条查询都会计算digest对性能的影响，我提出疑问后，作者在这篇文章[ProxySQL Rules: Do I Have Too Many?](https://www.percona.com/blog/2017/04/10/proxysql-rules-do-i-have-too-many/#comment-10967989)的评论里做出了解释。大意是说计算query digest确实会有性能损失，但是确实proxysql里面非常重要特性，主要是两点：
  1. proxysql无法知道连接复用(multipexing)是否必须被自动禁用，比如连接里面有variables/tmp tables/lock table等特殊命令，是不能复用的。
  2. 完整的查询去匹配正则的效率，一般没有参数化后的查询匹配效率高，因为有很长的字符串内容需要处理。再者，`SELECT * FROM randomtable WHERE comment LIKE ‘%INTO sbtest1 % FROM sbtest2 %’`字符串里有类似这样的语句，很难排除误匹配。
- `negate_match_pattern`: 反向匹配，相当于对 match_digest/match_pattern 的匹配取反。
- `re_modifiers`: 修改正则匹配的参数，比如默认的：忽略大小写`CASELESS`、禁用`GLOBAL`

上面都是匹配规则，下面是匹配后的行为：
- `replace_pattern`: 查询重写，默认为空，不rewrite。
  rewrite规则要遵守  [RE2::Replace](https://github.com/google/re2/wiki/Syntax) 。
- `destination_hostgroup`: 路由查询到这个 hostgroup。当然如果用户显式 start transaction 且 transaction_persistent=1，那么即使匹配到了，也依然按照事务里第一条sql的路由规则去走。
- `cache_ttl`: 查询结果缓存的毫秒数。
  proxysql这个 Query Cache 与 MySQL 自带的query cache不是同一个。proxysql query cache也不会关心后端数据是否被修改，它所做的就是针对某些特定种类的查询结果进行缓存，比如一些历史数据的count结果。一般不设。
- `timeout`: 这一类查询执行的最大时间（毫秒），超时则自动kill。
  这是对后端DB的保护机制，相当于阿里云RDS `loose_max_statement_time` 变量的功能，但是注意不同的是，阿里云这个变量的时间时不包括DML操作出现InnoDB行锁等待的时间，而ProxySQL的这个 timeout 是计算从发送sql到等待响应的时间。默认`mysql-default_query_timeout`给的是 10h .
- `retries`: 语句在执行时失败时，重试次数。默认由 `mysql-query_retries_on_failure`变量指定，为1 。
  我个人建议把它设成0，即不重试。因为执行失败，对select而言很少见，主要是dml，但自己重试对数据不放心。
- `delay`: 查询延迟执行，这是ProxySQL提供的限流机制，会让其它的查询优先执行。
  默认值 `mysql-default_query_delay`，为0。我们一般不用，其实还是要配合应用端使用，比如这边延迟执行，但上层等待你返回，那前端不就堵住了，没准出现雪崩效应。
- `mirror_flagOUT`,`mirror_hostgroup`
  这两个高级了，目前这部分文档不全，功能是SQL镜像。顾名思义，就是把匹配到的SQL除了发送到 destination_hostgroup，同时镜像一份到这里的hostgroup，比如我们的测试库。比如这种场景，数据库要从5.6升级到5.7，要验证现有查询语句对5.7的适用情况，就可以把生产流量镜像到5.7新库上验证。
- `error_msg`: 默认为NULL，如果指定了则这个查询直接被 block 掉，马上返回这个错误信息。
  这个功能也很实用，比如线上突然冒出一个 “坏查询”，应用端不方便马上发版解决，我们就可以在这配置一个规则，把查询屏蔽掉，想正常的mysql报错那样抛异常。下一篇文章有演示。
- `multiplex`: 连接是否复用。
  关于这个，单独起一篇文章来写，传送门：http://xgknight.com/2017/04/17/mysql-proxysql-multiplexing/
- `log`: 是否记录查询日志。可以看到log是否记录的对象是根据规则。
  要开启日志记录，需要设置变量 `mysql-eventslog_filename` 来指定文件名，然后这个 log 标记为1。但是目前proxysql记录的日志是二进制格式，需要特定的工具才能读取： eventslog_reader_sample 。这个工具在源码目录 tools下面，我下载的1.3.5版本rpm表竟然还没有编译它。
  参考 issue [#561 Logging all queries](https://github.com/sysown/proxysql/issues/561)

照 [wiki Multi-layer-configuration-system](https://github.com/sysown/proxysql/wiki/Multi-layer-configuration-system#modifying-config-at-runtime) 所说，在debug版本里应该有个 debug_levels 表来定义日志级别，但我没找到。据作者回复，上面的方式已过时，推荐 `mysql-eventslog_filename`。

# 3. proxysql的多层配置设计

ProxySQL采用多层配置的设计来达到以下目的：
- 允许在线应用配置项，而不需要重启proxysql
- 使用MySQL接口风格，来操作配置项，自定更新
- 如果配置有误，可以轻易回滚

![ProxySQL Multi layer configuration system](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-config-multi-layer.png)

**RUNTIME** 代表的是ProxySQL当前生效的配置，包括 global_variables, mysql_servers, mysql_users, mysql_query_rules。无法直接修改这里的配置，必须要从下一层load进来。
**MEMORY** 是平时在mysql命令行修改的 main 里头配置，可以认为是SQLite数据库在内存的镜像
**DISK / CONFIG FILE** 持久存储的那份配置，一般在`$(DATADIR)/proxysql.db`，在重启的时候会从硬盘里加载。 `/etc/proxysql.cnf`文件只在第一次初始化的时候用到，完了后，如果要修改监听端口，还是需要在管理命令行里修改，再 save 到硬盘。

需要修改配置时，直接操作的是 MEMORAY，以下命令可用于加载或保存 `users`： （序号对应上图） 
```
[1]: LOAD MYSQL USERS TO RUNTIME / LOAD MYSQL USERS FROM MEMORY  -- 常用
[2]: SAVE MYSQL USERS TO MEMORY / SAVE MYSQL USERS FROM RUNTIME
[3]: LOAD MYSQL USERS TO MEMORY / LOAD MYSQL USERS FROM DISK
[4]: SAVE MYSQL USERS TO DISK /  SAVE MYSQL USERS FROM MEMORY    -- 常用
[5]: LOAD MYSQL USERS FROM CONFIG
```
我比较习惯用 `TO`，记住往上层是 LOAD，往下层是 SAVE。

以下命令加载或保存`servers`:
```
[1]: LOAD MYSQL SERVERS TO RUNTIME  -- 常用，让修改的配置生效
[2]: SAVE MYSQL SERVERS TO MEMORY
[3]: LOAD MYSQL SERVERS TO MEMORY
[4]: SAVE MYSQL SERVERS TO DISK     -- 常用，将修改的配置持久化
[5]: LOAD MYSQL SERVERS FROM CONFIG
```

后面的使用方法也基本相同，一并列出。
以下命令加载或保存`query rules`:
```
[1]: load mysql query rules to run    -- 常用
[2]: save mysql query rules to mem
[3]: load mysql query rules to mem
[4]: save mysql query rules to disk   -- 常用
[5]: load mysql query rules from config
```

以下命令加载或保存 `mysql variables`:
```
[1]: load mysql variables to runtime
[2]: save mysql variables to memory
[3]: load mysql variables to memory
[4]: save mysql variables to disk
[5]: load mysql variables from config
```

以下命令加载或保存`admin variables`:
```
[1]: load admin variables to runtime
[2]: save admin variables to memory
[3]: load admin variables to memory
[4]: save admin variables to disk
[5]: load admin variables from config
```

下一篇文章将演示ProxySQL读写分离与分库的路由规则编写：http://xgknight.com/2017/04/17/mysql-proxysql-route-rw_split/ 

# 参考：
- https://severalnines.com/blog/mysql-load-balancing-proxysql-overview
- https://github.com/sysown/proxysql/wiki
- http://www.techietown.info/2017/01/mysql-readwrite-splitting-proxysql/

---

原文连接地址：http://xgknight.com/2017/04/10/mysql-proxysql-install-config/

---
