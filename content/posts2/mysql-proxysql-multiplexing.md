---
title: ProxySQL之连接复用（multiplexing）以及相关问题说明
date: 2017-04-17 21:32:49
tags: [mysql, 中间件, proxysql]
categories:
- MySQL
updated: 2017-04-17 21:32:49
---

ProxySQL在连接池(*persistent connection poll*)的基础上，还有一个连接复用的概念 *multiplexing connection*，官方的wiki里没有很明确的说明，但在作者的一些 blog post 和 issue 里能找到解答： https://github.com/sysown/proxysql/issues/939#issuecomment-287489317 

由于SQL可以路由，一个客户端连接上来，可能会到多个 hostgroup 发起连接。复用的意思是，一个后端DB的连接，可以“同时”被多个客户端使用。

传统的连接池，会在客户端**断开连接**（会话）后，把连接放回到池里。在ProxySQL中，由于连接复用，连接会在**sql语句**执行结束后，便将连接放回到池里（客户端会话可能并没有断开），这样便可大大提高后端连接的使用效率，而避免前段请求过大导致后端连接数疯长。

但这样做有时候并不安全，比如应用端连接时指定了 `set NAMES xxx`，然后执行查询，那么由于multiplexing可能导致两个语句发到不同的DB上执行，继而没有按照预期的字符集执行。proxysql考虑到了这种情况：
1. 连接会话里创建了临时表，`CREATE TEMPORARY table xxxx...`
2. select @开头的变量，如`select @@hostname`
3. 手动开启了事务，`start transaction`, `commit`, `rollback`等等
4. 连接设置了自己的用户变量，比如`set names xxx`, `set autocommit x`, `set sql_mode=xxx`, `set v_uservar=xx`等等

第1,2,3点会根据路由规则，会自动禁用multiplex，发到对应hostgroup后，连接未断开之前不会复用到其它客户端。具体是发到主库还是从库，与匹配的规则有关。
issue [#941](https://github.com/sysown/proxysql/issues/941) 和 [#917](https://github.com/sysown/proxysql/issues/917) 都有提到临时表丢失的问题，可以用不同的rule来避免

下面对上面几点一一说明。

## 1. 临时表与用户变量（验证 1, 2）
以下注意连接的会话窗口及执行顺序，admin打头的是在proxysql管理接口上执行。

```
-- [session 1] mysql client proxysql
(ecdba@10.0.100.36:6033) [(none)]> select 1;
+---+
| 1 |
+---+
| 1 |
+---+

-- [session 2] proxysql admin cli
select * from stats_mysql_processlist;
Empty set (0.00 sec)

普通查询，session 1 没断开，但后端连接已放回连接池，所以看不到processlist。下面试验临时表：

-- [session 1] mysql client proxysql
(ecdba@10.0.100.36:6033) [(none)]> CREATE TEMPORARY TABLE db0.tbl_tmp(id int);
Query OK, 0 rows affected (0.18 sec)

-- [session 2] proxysql admin cli
(admin@127.0.0.1:6032) [(none)]> select * from stats_mysql_processlist;
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+--------------+----------+---------+---------+------+
| ThreadID | SessionID | user  | db                 | cli_host    | cli_port | hostgroup | l_srv_host  | l_srv_port | srv_host     | srv_port | command | time_ms | info |
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+--------------+----------+---------+---------+------+
| 0        | 60        | ecdba | information_schema | 10.0.100.34 | 27058    | 100       | 10.0.100.36 | 41245      | 10.0.100.100 | 3307     | Sleep   | 4506    |      |
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+--------------+----------+---------+---------+------+
1 row in set (0.00 sec)

看到后端的连接没有释放回连接池，但是在 session 1 里select却看不到刚才创建的临时表：

-- [session 1] 
(ecdba@10.0.100.36:6033) [(none)]> select * from db0.tbl_tmp;
ERROR 1146 (42S02): Table 'db0.tbl_tmp' doesn't exist

-- [session 2] 
(admin@127.0.0.1:6032) [(none)]> select * from stats_mysql_processlist;
+----------+-----------+-------+--------------------+-------------+----------+-----------+------------+------------+----------+----------+---------+---------+------+
| ThreadID | SessionID | user  | db                 | cli_host    | cli_port | hostgroup | l_srv_host | l_srv_port | srv_host | srv_port | command | time_ms | info |
+----------+-----------+-------+--------------------+-------------+----------+-----------+------------+------------+----------+----------+---------+---------+------+
| 0        | 60        | ecdba | information_schema | 10.0.100.34 | 27058    | 1000      |            |            |          |          | Sleep   | 2002    |      |
+----------+-----------+-------+--------------------+-------------+----------+-----------+------------+------------+----------+----------+---------+---------+------+
1 row in set (0.00 sec)

select之后，发现上面的srv_host为空。下面往临时表里插数据，正常，且连接被 session 1 客户端持有：

-- [session 1] 
(ecdba@10.0.100.36:6033) [(none)]> insert into db0.tbl_tmp values(1);
Query OK, 1 row affected (0.01 sec)

-- [session 2] 
(admin@127.0.0.1:6032) [(none)]> select * from stats_mysql_processlist;
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+--------------+----------+---------+---------+------+
| ThreadID | SessionID | user  | db                 | cli_host    | cli_port | hostgroup | l_srv_host  | l_srv_port | srv_host     | srv_port | command | time_ms | info |
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+--------------+----------+---------+---------+------+
| 0        | 60        | ecdba | information_schema | 10.0.100.34 | 27058    | 100       | 10.0.100.36 | 41245      | 10.0.100.100 | 3307     | Sleep   | 2996    |      |
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+--------------+----------+---------+---------+------+
1 row in set (0.00 sec)

-- [session 1] 
(ecdba@10.0.100.36:6033) [(none)]> select 1;
+---+
| 1 |
+---+
| 1 |
+---+

-- [session 2] 
(admin@127.0.0.1:6032) [(none)]> select * from stats_mysql_processlist;
+----------+-----------+-------+--------------------+-------------+----------+-----------+------------+------------+----------+----------+---------+---------+------+
| ThreadID | SessionID | user  | db                 | cli_host    | cli_port | hostgroup | l_srv_host | l_srv_port | srv_host | srv_port | command | time_ms | info |
+----------+-----------+-------+--------------------+-------------+----------+-----------+------------+------------+----------+----------+---------+---------+------+
| 0        | 60        | ecdba | information_schema | 10.0.100.34 | 27058    | 1000      |            |            |          |          | Sleep   | 2303    |      |
+----------+-----------+-------+--------------------+-------------+----------+-----------+------------+------------+----------+----------+---------+---------+------+
```
通过上面的过程可以看见，proxysql在遇到与会话本身相关的变量或操作时，自动禁用了multiplexing，并且针对整个会话有效，直到断开连接。另外，禁用了multiplexing，但**路由规则依然生效**，这就导致了select临时表时路由到了其它实例， Table xxx doesn't exist。

## 2. 显式start transaction (验证3)
第1,2点根据开发的习惯，都可以避免使用，但显式事务有时却不得不用，也做一个测试。

```
为了效果明显，我将一个不相干的实例，分配同一个hostgroup_id，权重1:1

-- [session 1] 
(ecdba@10.0.100.36:6033) [(none)]> select * from db0.tbl_0;
+-----+----------+--------+
| fid | username | corpid |
+-----+----------+--------+
|   1 | db0 aa   |      0 |
|   2 | db0 aa   |     16 |
|   3 | db0 aa   |     32 |
+-----+----------+--------+

(ecdba@10.0.100.36:6033) [(none)]> select * from db0.tbl_0;
ERROR 1146 (42S02): Table 'db0.tbl_0' doesn't exist

(ecdba@10.0.100.36:6033) [(none)]> begin;  -- 开启一个事务
(ecdba@10.0.100.36:6033) [(none)]> select * from db0.tbl_0;
+-----+----------+--------+
| fid | username | corpid |
+-----+----------+--------+
|   1 | db0 aa   |      0 |
|   2 | db0 aa   |     16 |
|   3 | db0 aa   |     32 |
+-----+----------+--------+

(ecdba@10.0.100.36:6033) [(none)]> select * from db0.tbl_0;
ERROR 1146 (42S02): Table 'db0.tbl_0' doesn't exist

这就尴尬了，明显是在同一个事务里面，后端依然请求了多个backend。设置 transaction_persistent ：

-- [session 2] 
(admin@127.0.0.1:6032) [(none)]> update mysql_users set transaction_persistent=1 where username='ecdba';
(admin@127.0.0.1:6032) [(none)]> load mysql users to run;

-- [session 1] 
(ecdba@10.0.100.36:6033) [(none)]> begin;
Query OK, 0 rows affected (0.00 sec)

(ecdba@10.0.100.36:6033) [(none)]> select * from db0.tbl_0;
+-----+----------+--------+
| fid | username | corpid |
+-----+----------+--------+
|   1 | db0 aa   |      0 |
|   2 | db0 aa   |     16 |
|   3 | db0 aa   |     32 |
+-----+----------+--------+

反复执行多次还是上面的结果。 看到到后端连接的情况：
-- [session 2] 
(admin@127.0.0.1:6032) [(none)]> select * from stats_mysql_processlist;
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+--------------+----------+---------+---------+------+
| ThreadID | SessionID | user  | db                 | cli_host    | cli_port | hostgroup | l_srv_host  | l_srv_port | srv_host     | srv_port | command | time_ms | info |
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+--------------+----------+---------+---------+------+
| 3        | 73        | ecdba | information_schema | 10.0.100.34 | 45030    | 100       | 10.0.100.36 | 6057       | 10.0.100.100 | 3307     | Sleep   | 43046   |      |
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+--------------+----------+---------+---------+------+
1 row in set (0.00 sec)
```

看到用户的 `transaction_persistent` 属性可以保证在同一个事务内的所有sql，都发向后端同一个db实例。如果它为0，同时一个hostgroup有多个可用slave，可能由于不同从库的延迟不一样，而查到不一致的数据。

`transaction_persistent=1` 时还注意一下隐藏的一点点细节，begin 开启事务后，事务内所有语句包括select，都路由到了主库，这是因为 begin 匹配规则选择的是主库，后续的查询都跟着走;而 `transaction_persistent=0` 时 bgein 由于路由规则作用，也发到了主库，但后续的select,update等是不受它约束，继续根据路由规则走。在 非 *master-master* 模式下，事务还是安全的。


## 3.1 autocommit 会话变量 (验证4)
第 4 点略微有些复杂，开始之前先引用一段作者针对 issue [#653](https://github.com/sysown/proxysql/issues/653#issuecomment-241828093) 的回复：（不完全翻译）
> **ProxySQL doesn't track user variable**  
ProxySQL不会记录 用户变量，当proxysql识别到 `set @variable1 = 67` 语句时，会自动禁用连接复用(disable multiplexing)，并根据路由规则选择后端节点（通常是写节点），执行完成后，连接不会放回连接池，直到disconnect。
>
> **ProxySQL tracks some session variables**  
ProxySQL会记录 会话变量，“记录” 的意思是，proxysql接收到这些会话变量后，不会马上从后端连接池去拿连接然后 set xxx （因为还没有足够的信息知道拿哪个用户哪个db的连接），而是在当前连接保存起来，等待下一个查询命令，然后一起发送到到后端。`use dbname`就是这样处理的。
当前，记录的只有 `autocommit` 和字符集变量、`timezone`。比如执行sql前发送一个 `set autocommit=1`，proxysql会马上返回一个 `OK`，代表它知道应用端设置了自动提交，等真正的dml请求过来时，它将与后端拿到的连接比较autocommit是否匹配，不匹配则先set再执行dml。
>
> 当然现实还受到proxysql全局变量 `mysql-enforce_autocommit_on_reads` 的影响，即是否开启对读操作强制 autocommit。这个变量所解决的问题是，在同一个事务里既有 write 又有 read 且配置了读写分离的情况下，会导致在 读库 和 写库 各自开一个事务 (从库会set autocommit=0)，这就不合理了，所以把它设为 true 可以保证事务始终是一个。默认 false。
但是如上节所说，如果开启了 `transaction_persistent=1`，这个问题就不存在了。


```
-- [session 1] 
(ecdba@10.0.100.36:6033) [(none)]> set @variable1 = 67;

-- [session 2] 
(admin@127.0.0.1:6032) [(none)]> show processlist;
+-----------+-------+--------------------+-----------+---------+---------+------+
| SessionID | user  | db                 | hostgroup | command | time_ms | info |
+-----------+-------+--------------------+-----------+---------+---------+------+
| 79        | ecdba | information_schema | 100       | Sleep   | 8008    |      |
+-----------+-------+--------------------+-----------+---------+---------+------+
1 row in set (0.00 sec)

与后端的连接已建立。但如果没有路由规则匹配到，proxysql会选择该用户 default_hostgroup，一般是0，由于没有 HG 0 记录，这个set variables会失败：
-- [session 1] 
(ecdba@10.0.100.36:6033) [(none)]> set @variable1 = 67;
ERROR 9001 (HY000): Max connect timeout reached while reaching hostgroup 0 after 11462ms


同样情况下，set autocommit 和 set names 就很快返回，并且看不到后端有连接：
(ecdba@10.0.100.36:6033) [(none)]> set session transaction isolation level read committed;
Query OK, 0 rows affected (0.00 sec)
(ecdba@10.0.100.36:6033) [(none)]> set autocommit=0;
Query OK, 0 rows affected (0.00 sec)

-- [session 2] 
(admin@127.0.0.1:6032) [(none)]> show processlist;
Empty set (0.00 sec)

-- [session 1] 
begin开启一个事务，验证 transaction_persistent：
(ecdba@10.0.100.36:6033) [(none)]> UPDATE db0.tbl_0 set username='db0 autocommit' where fid=3;
Query OK, 1 row affected (0.00 sec)
Rows matched: 1  Changed: 1  Warnings: 0

(ecdba@10.0.100.36:6033) [(none)]> select * from db0.tbl_0;
+-----+----------------+--------+
| fid | username       | corpid |
+-----+----------------+--------+
|   1 | db0 aa         |      0 |
|   2 | db0 aa         |     16 |
|   3 | db0 autocommit |     32 |
+-----+----------------+--------+
3 rows in set (0.00 sec)

(ecdba@10.0.100.36:6033) [(none)]> commit;
Query OK, 0 rows affected (0.00 sec)

查看后端DB（主库）的 general_log：（都发到了主库）

		9651978 Connect	ecdba@10.0.100.36 on information_schema
		9651978 Query	SET autocommit=0
		9651978 Query	UPDATE db0.tbl_0 set username='db0 autocommit' where fid=3
		9651978 Query	select * from db0.tbl_0
		9651978 Query	commit
```

这也告诉我们，尽量不要在 proxy admin cli 里面执行 show slave status， set global xxx 这样的管理命令，你较难预知到后端在哪里执行的。


## 3.2 字符集prepared会话变量 (验证4)
对字符集 `set NAMES xxx`, `set character_set_client=xxx`，处理方法与上面 set autocommit 是一样的，但是遇到使用 prepared statement 时需要特别提一下。

首先ProxySQL所支持的字符集，在表 *mysql_collations* 可以看到，它是直接从本地安装的mysql client lib获取的，proxysql默认使用的是utf8，指的是在连接的时候默认认为客户端的字符集是utf8。

根据 issue #780：https://github.com/sysown/proxysql/issues/780 的讨论，某些框架比如 Laravel 在通过PDO连接MySQL时，执行 prepared statement时会连同 `set NAMES xx` 一起发送，导致没有生效。经测试，该问题在 v1.3.5 中已不存在：
```
-- [session 1] 
mysql -uecweb -pweber -h10.0.100.34 -P6033 --default-character-set=latin1

(ecweb@10.0.100.34:6033) [(none)]> select * from d_ec_crm.tttt;
+-----+-------+
| fid | fname |
+-----+-------+
|   1 | xx??? |
+-----+-------+

 latin1连接看utf8的数据，所以乱码。下面模拟 prepared statement 设置字符集：
(ecweb@10.0.100.34:6033) [(none)]> PREPARE stmt FROM 'SET NAMES utf8';
Query OK, 0 rows affected (0.00 sec)
Statement prepared

-- [session 2] 
(admin@127.0.0.1:6032) [(none)]> select * from stats_mysql_processlist;
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+---------------+----------+---------+---------+------+
| ThreadID | SessionID | user  | db                 | cli_host    | cli_port | hostgroup | l_srv_host  | l_srv_port | srv_host      | srv_port | command | time_ms | info |
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+---------------+----------+---------+---------+------+
| 1        | 50        | ecweb | information_schema | 10.0.100.34 | 46389    | 110       | 10.0.100.34 | 31946      | 192.168.1.229 | 3307     | Sleep   | 35649   |      |
+----------+-----------+-------+--------------------+-------------+----------+-----------+-------------+------------+---------------+----------+---------+---------+------+

直接执行还是乱码，也要在prepared ：
(ecweb@10.0.100.34:6033) [(none)]> select * from d_ec_crm.tttt;
+-----+-------+
| fid | fname |
+-----+-------+
|   1 | xx??? |
+-----+-------+

(ecweb@10.0.100.34:6033) [(none)]> PREPARE stmt FROM 'select * from d_ec_crm.tttt';
Query OK, 0 rows affected (0.00 sec)
Statement prepared

(ecweb@10.0.100.34:6033) [(none)]> EXECUTE stmt;
+-----+-------------+
| fid | fname       |
+-----+-------------+
|   1 | xx嘻嘻嘻 |
+-----+-------------+
```
注意到 `PREPARE stmt FROM 'SET NAMES utf8'` 发送之后，马上与后端建立了连接，而不像上节`set names xx`止步于proxysql。所以是自动禁用了 multiplexing。

## 3.3 set sql_mode
作者明确表示 `sql_mode` 在 1.3.x 版本里不会track，也就是它完全按照路由规则走，不会像临时表或用户变量那样 disable multiplexing automaticly，也不像上面的会话变量那样 “记录” 然后一并发送。

如果sql_mode确实对应用使用造成困扰，1.4版本里会修复，在此前估计只好将连接复用的特性全局禁用：
```
SET mysql-multiplexing='false';
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;
```
参考 [issue #916](https://github.com/sysown/proxysql/issues/916)。禁用 multiplexing 后，就像一般的中间件连接池一样，维持或者释放连接。


最后，关于 multiplexing 向作者提了一个特性 [594#issuecomment-294703577](https://github.com/sysown/proxysql/issues/594#issuecomment-294703577) ：前端连接执行完一个查询，后端不马上把它返回连接池（复用），而是等待几秒，如果这个连接后续又有sql进来，就不需要重新从池里获取连接，还有检查一堆变量。renecannao 的回复非常及时，也确认 v1.4 会加上这个功能。


updated at 2017-07-27:
关于连接复用与连接池的差别，在后一次与作者的沟通中，更加明确了，见 [#issue 1107](https://github.com/sysown/proxysql/issues/1107):
问题始于发现环境中的connection pool没有起作用（禁用了multiplexing），因为一开始只是认为禁用了multiplexing，connection pool不会受影响。但实际不是的，在1.3.x版本里，禁用multiplexing，就相当于连接复用和连接池都没有了，前端应用在释放连接后，proxysql也把后端的连接释放了；在1.4.x版本里表现不同，禁用multiplexing后，前端连接释放，proxysql对后端的连接继续保持，并对连接重置以便重复利用。

所以如果测试上没啥问题，建议开启连接复用，或者升级到 1.4.x 版本。

---

原文连接地址：http://xgknight.com/2017/04/17/mysql-proxysql-multiplexing/

---
