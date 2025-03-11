---
title: ProxySQL之读写分离与分库路由演示
date: 2017-04-17 15:32:49
aliases:
- /2017/04/17/mysql-proxysql-route-rw_split/
tags: [mysql, 中间件, proxysql]
categories:
- MySQL
updated: 2017-04-17 15:32:49
---

本文演示使用ProxySQL来完成读写分离和后端分库的一个实际配置过程，安装及配置项介绍见前文 [ProxySQL之安装及配置详解](http://xgknight.com/2017/04/10/mysql-proxysql-install-config/)。

环境
```
instance0: 10.0.100.100 (db0,db2,db4,db6)
instance1: 10.0.100.101 (db1,db3,db5,db7)
instance2: 10.0.100.102 (db2,db6,db10,db14)
instance3: 10.0.100.103 (db3,db7,db11,db15)

instance0 slave: 192.168.10.4:3316
instance1 slave: 192.168.10.4:3326
instance2 slave: 192.168.10.4:3336
instance3 slave: 192.168.10.4:3346

proxysql node0: 10.0.100.36
```

现在想达到这样一个目的：客户端应用连接上 proxysql 的ip:port，连接时指定分库db名，执行sql时自动路由到对应的实例、对应的库。考虑下面的部署结构：
![ProxySQL Deploy](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-rw-lb-deploy.png)

任何一个proxysql节点都是对等的，路由请求到后端instance的各个database上。

# 1. 配置后端DB
```
-- proxysql admin cli

insert into mysql_servers(hostgroup_id,hostname,port,weight,weight,comment) values
  (100, '10.0.100.100', 3307, 1, 'db0,ReadWrite'),
  (1000, '10.0.100.100', 3307, 1, 'db0,ReadWrite'),(1000, '192.168.10.4', 3316, 9, 'db0,ReadOnly');

insert into mysql_servers(hostgroup_id,hostname,port,weight,weight,comment) values
  (101, '10.0.100.101', 3307, 1, 'db1,ReadWrite'),
  (1001, '10.0.100.101', 3307, 1, 'db1,ReadWrite'),(1001, '192.168.10.4', 3326, 9, 'db1,ReadOnly');

insert into mysql_servers(hostgroup_id,hostname,port,weight,weight,comment) values
  (102, '10.0.100.102', 3307, 1, 'db2,ReadWrite'),
  (1002, '10.0.100.102', 3307, 1, 'db2,ReadWrite'),(1002, '192.168.10.4', 3336, 9, 'db2,ReadOnly');

insert into mysql_servers(hostgroup_id,hostname,port,weight,weight,comment) values
  (103, '10.0.100.103', 3307, 1, 'db3,ReadWrite'),
  (1003, '10.0.100.103', 3307, 1, 'db3,ReadWrite'),(1003, '192.168.10.4', 3346, 9, 'db3,ReadOnly');
```
比如 100 是主库，则 1000 是从库，同时主库也可以处理 1/10 的读请求。

# 2. 配置用户
```
-- proxysql admin cli

insert into mysql_users(username, password,active,transaction_persistent)
  values('user0', 'password0', 1, 1),('read1', 'password1', 1, 1);
```
这里将 transaction_persistent 设置为1，如果不知道它的含义，请参考前文。

要确保用户有能够登陆到后端的所有db的权限。


# 3. 修改全局变量
```
-- proxysql admin cli

set mysql-default_charset='utf8mb4';
set mysql-query_retries_on_failure=0;
set mysql-max_stmts_per_connection=1000;
set mysql-eventslog_filename='queries.log';
set monitor_slave_lag_when_null=7200;

set mysql-ping_timeout_server=1500;
set mysql-monitor_connect_timeout=1000;
set mysql-default_max_latency_ms=2000;

set mysql-monitor_username='monitor';
set mysql-monitor_password='monitor';
set mysql-server_version='5.6.16';
```
需要提前给 monitor 账号开通权限，一般共用监控数据库的权限就足够了。


**让上面所有的修改生效**:
```
-- proxysql admin cli
-- 应用
load mysql users to runtime;
load mysql servers to runtime;
load mysql variables to runtime;

-- 保存到磁盘
save mysql users to disk;
save mysql servers to disk;
save mysql variables to disk;

save mysql users to mem;  -- 可以屏蔽看到的明文密码
```


# 4. 添加路由规则
一般配置ProxySQL规则步骤是 [issues #653](https://github.com/sysown/proxysql/issues/653#issuecomment-242122732) :
1. 配置proxysql，将所有sql都发到主库
2. 分析表 `stats_mysql_query_digest` 里面哪几种查询占比高
3. 筛选哪些些占比高的SELECT，可以路由到从库
4. 修改 `mysql_query_rules` 里面的规则，使其生效。不要一味的把所有查询都路由到主库

```
-- [1] read&write split
insert into mysql_query_rules(rule_id, active,match_digest,apply,flagOUT) values(49, 1,'^select\s.*\sfor update',0,21);
insert into mysql_query_rules(rule_id, active,match_digest,apply,flagOUT) values(50, 1,'^\(?select',0,20);
insert into mysql_query_rules(rule_id, active,match_digest,negate_match_pattern,apply,flagOUT) values(60, 1,'^select',1,0,21);

-- 下面最好从rule_id 70开始，中间留空

-- [2] flag 20 read
insert into mysql_query_rules(active,schemaname,destination_hostgroup,apply,flagIN,flagOUT) values
  (1,'db0',1000,1,20,20), (1,'db1',1001,1,20,20), (1,'db2',1002,1,20,20), (1,'db3',1003,1,20,20), (1,'db4',1000,1,20,20), (1,'db5',1001,1,20,20), (1,'db6',1002,1,20,20), (1,'db7',1003,1,20,20),
  (1,'db8',1000,1,20,20), (1,'db9',1001,1,20,20), (1,'db10',1002,1,20,20), (1,'db11',1003,1,20,20), (1,'db12',1000,1,20,20), (1,'db13',1001,1,20,20), (1,'db14',1002,1,20,20), (1,'db15',1003,1,20,20);

-- [3] flag 21 write
insert into mysql_query_rules(active,schemaname,destination_hostgroup,apply,flagIN,flagOUT) values
  (1,'db0',100,1,21,21), (1,'db1',101,1,21,21), (1,'db2',102,1,21,21), (1,'db3',103,1,21,21), (1,'db4',100,1,21,21), (1,'db5',101,1,21,21), (1,'db6',102,1,21,21), (1,'db7',103,1,21,21), 
  (1,'db8',100,1,21,21), (1,'db9',101,1,21,21), (1,'db10',102,1,21,21), (1,'db11',103,1,21,21), (1,'db12',100,1,21,21), (1,'db13',101,1,21,21), (1,'db14',102,1,21,21), (1,'db15',103,1,21,21);

-- [4] no schema given when connect
insert into mysql_query_rules(rule_id,active,schemaname,apply,flagOUT) values(20,1,'information_schema',0,302);

-- [5] route according to dbX.
insert into mysql_query_rules(rule_id,active,match_digest,destination_hostgroup,apply,flagIN,flagOUT) values(1000,1,'([\s\`])db(0|4|8|12)([\.\`])',100,1,302,302);
insert into mysql_query_rules(rule_id,active,match_digest,destination_hostgroup,apply,flagIN,flagOUT) values(1001,1,'([\s\`])db(1|5|9|13)([\.\`])',101,1,302,302);
insert into mysql_query_rules(rule_id,active,match_digest,destination_hostgroup,apply,flagIN,flagOUT) values(1002,1,'([\s\`])db(2|6|10|14)([\.\`])',102,1,302,302);
insert into mysql_query_rules(rule_id,active,match_digest,destination_hostgroup,apply,flagIN,flagOUT) values(1003,1,'([\s\`])db(3|7|11|15)([\.\`])',103,1,302,302);

-- [6] wrong usage
insert into mysql_query_rules(rule_id,active,match_digest,apply,flagIN,flagOUT,error_msg,comment) 
  values(1404,1,'^SELECT DATABASE\(\)$',1,302,302,'You should specify schema name first', 'use db0 Take long when no schema given for connection');

-- [7] default route
insert into mysql_query_rules(rule_id,active,apply, flagIN,flagOUT,error_msg,comment) values(9999,1,1, 302,302,'No query rules matched (by ProxySQL)', "Don't define the default hostgroup 0 for ME");

-- [8]
LOAD MYSQL QUERY RULES TO RUN;
SAVE MYSQL QUERY RULES TO DISK;
```

逐个解释：
1. 以 select 开头并且不是 for update 类型的SQL，进入到新的规则链flagOUT=20;  
   其它诸如 insert, delete, update, replace, set, show 等语句，都进入到规则链flagOUT=21。
   注：'^\(?select' 规则匹配以`select`或 `(select` 开头的查询，但目前proxysql(1.3.6, 1.4.1)版本对以 `(` 开头的查询不记录 stats_mysql_query_digest 表。[#issue 1100](https://github.com/sysown/proxysql/issues/1100)

   有个小技巧，mysql_query_rules 表的rule_id有自增，但最好从中间某个数开始，因为一旦后续可能需要紧急在前面插入规则，从1开始就没空位了。

   这里大家可能有个顾虑，从库上可以执行 `set NAMES xxx`, `set session sql_mode=xxx`, `SET autocommit=?`, `commit`, `rollback`, `START TRANSACTION`, `use dbx` 这样的语句，不能全路由到主库吧？对此，另起了一篇文章 http://xgknight.com/2017/04/17/mysql-proxysql-multiplexing 。

2. flagIN=20 是 *只读链* 的入口  
  根据连接时指定的dbname，路由到对应的分库上。db0, db4, db8, db12 路由到 hostgroup_id=1000 ，db1, db5, db9, db16 路由到 hostgroup_id=1002 ，依次类推。
  flagIN=flagOUT 则结束匹配。

3. flagOUT=21 是 *读写链*的入口  
  与上面的 [2] 类似，但是根据dbname路由到主库。

4. 当建立连接的时候没有指定dbname时，分两种情况
 - 使用连接的时候 `use db0`，因为mysql协议在每次 use dbname 时都会发送一个 `SELECT DATABASE()` 命令，第一次由于没有连接上后端任何DB，命令会执行超时失败，再次 use db0 是才成功。具体参考我所提的 [issue #988](https://github.com/sysown/proxysql/issues/988) 。
   因此这里我为它添加了一个规则 **[6]**，遇到这种情况马上处理，而不用等待失败。
 - 使用连接时从未有默认schema，添加规则 **[5]**，使用 `schemaname.tablename` 的形式匹配 schemaname，然后路由到对应的 hostgroup 。

7. 因为没有定义 hostgroup 0，在意外情况什么规则都没匹配上时也依旧会等待失败，所以默认规则（默认路由）返回一个错误。

# 5. 效果演示
```
db0 与 db15 分别在两个实例上：

(ecdba@10.0.100.36:6033) [(none)]> select * from db0.tbl_0;
+-----+----------------+--------+
| fid | username       | corpid |
+-----+----------------+--------+
|   1 | db0 aa         |      0 |
|   2 | db0 aa         |     16 |
|   3 | db0 autocommit |     32 |
+-----+----------------+--------+
3 rows in set (0.00 sec)

(ecdba@10.0.100.36:6033) [(none)]> select * from db15.tbl_0;
+-----+-----------------------------+--------+
| fid | username                    | corpid |
+-----+-----------------------------+--------+
|   1 | db15 c2dfdf地方大幅度d      |     15 |
|   2 | db15 c2dfdf地方大幅度d      |     47 |
|   3 | db15 c2dfdf地方大幅度d      |    111 |
+-----+-----------------------------+--------+
3 rows in set (0.00 sec)

无法路由时，报错：
(ecdba@10.0.100.36:6033) [(none)]> show databases;
ERROR 1148 (42000): No query rules matched (by ProxySQL)


看到 rule 的命中数符合预期：
-- proxysql admin cli
(admin@127.0.0.1:6032) [(none)]> select active,hits, mysql_query_rules.rule_id, schemaname, match_digest, match_pattern, replace_pattern,destination_hostgroup hostgroup,s.comment,flagIn,flagOUT   
FROM mysql_query_rules NATURAL JOIN stats.stats_mysql_query_rules 
JOIN mysql_servers s on destination_hostgroup=hostgroup_id ORDER BY mysql_query_rules.rule_id;
+--------+------+---------+--------------------+--------------+-------------------------------+-----------------+-----------+--------+---------+
| active | hits | rule_id | schemaname         | match_digest | match_pattern                 | replace_pattern | hostgroup | flagIN | flagOUT |
+--------+------+---------+--------------------+--------------+-------------------------------+-----------------+-----------+--------+---------+
| 1      | 3    | 20      | information_schema | NULL         | NULL                          | NULL            | NULL      | 0      | 302     |
| 1      | 0    | 50      | NULL               | ^\(*select   | NULL                          | NULL            | NULL      | 0      | 20      |
| 1      | 0    | 60      | NULL               | ^select      | NULL                          | NULL            | NULL      | 0      | 21      |
| 1      | 0    | 61      | db0                | NULL         | NULL                          | NULL            | 1000      | 20     | 20      |
| 1      | 0    | 62      | db1                | NULL         | NULL                          | NULL            | 1001      | 20     | 20      |
| 1      | 0    | 63      | db2                | NULL         | NULL                          | NULL            | 1002      | 20     | 20      |
| 1      | 0    | 64      | db3                | NULL         | NULL                          | NULL            | 1003      | 20     | 20      |
....
| 1      | 0    | 77      | db0                | NULL         | NULL                          | NULL            | 100       | 21     | 21      |
| 1      | 0    | 78      | db1                | NULL         | NULL                          | NULL            | 101       | 21     | 21      |
| 1      | 0    | 79      | db2                | NULL         | NULL                          | NULL            | 102       | 21     | 21      |
| 1      | 0    | 80      | db3                | NULL         | NULL                          | NULL            | 103       | 21     | 21      |
...
| 1      | 0    | 92      | db15               | NULL         | NULL                          | NULL            | 103       | 21     | 21      |
| 1      | 1    | 1000    | NULL               | NULL         | ([\s\`])db(0|4|8|12)([\.\`])  | NULL            | 100       | 302    | 302     |
| 1      | 0    | 1001    | NULL               | NULL         | ([\s\`])db(1|5|9|13)([\.\`])  | NULL            | 101       | 302    | 302     |
| 1      | 0    | 1002    | NULL               | NULL         | ([\s\`])db(2|6|10|14)([\.\`]) | NULL            | 102       | 302    | 302     |
| 1      | 1    | 1003    | NULL               | NULL         | ([\s\`])db(3|7|11|15)([\.\`]) | NULL            | 103       | 302    | 302     |
| 1      | 0    | 1404    | NULL               | NULL         | ^SELECT DATABASE\(\)$         | NULL            | NULL      | 302    | 302     |
| 1      | 1    | 9999    | NULL               | NULL         | NULL                          | NULL            | NULL      | 302    | 302     |
+--------+------+---------+--------------------+--------------+-------------------------------+-----------------+-----------+--------+---------+
41 rows in set (0.01 sec)

mysql> select rule_id,schemaname,match_digest,match_pattern,destination_hostgroup,negate_match_pattern,apply,flagIN,flagOUT,error_msg from mysql_query_rules;
```

切换数据库继续：
```
(ecdba@10.0.100.36:6033) [(none)]> use db1;
Database changed

(ecdba@10.0.100.36:6033) [db1]> select * from tbl_0;
+-----+----------+--------+
| fid | username | corpid |
+-----+----------+--------+
|   1 | db1 bb   |      1 |
|   2 | db1 bb   |     17 |
|   3 | db1 bb   |     33 |
+-----+----------+--------+
3 rows in set (0.01 sec)

(ecdba@10.0.100.36:6033) [db1]> select * from `db5`.tbl_0;
+-----+--------------------+--------+
| fid | username           | corpid |
+-----+--------------------+--------+
|   1 | db5 ces测试 kfjd   |      5 |
+-----+--------------------+--------+

db6并不在当前实例里：
(ecdba@10.0.100.36:6033) [db1]> select * from db6.tbl_0;
ERROR 1146 (42S02): Table 'db6.tbl_0' doesn't exist

现在show databases不会再报错：
(ecdba@10.0.100.36:6033) [db1]> show databases;
+--------------------+
| Database           |
+--------------------+
| information_schema |
| db1                |
| db13               |
| db5                |
| db9                |
| mysql              |
| performance_schema |
+--------------------+


看到 stats 模块的统计信息：
-- proxysql admin cli
(admin@127.0.0.1:6032) [(none)]> select hostgroup,schemaname,username,digest,substr(digest_text,120,-120),count_star from stats_mysql_query_digest;
+-----------+--------------------+----------+--------------------+--------------------------------------------+------------+
| hostgroup | schemaname         | username | digest             | substr(digest_text,120,-120)               | count_star |
+-----------+--------------------+----------+--------------------+--------------------------------------------+------------+
| 1002      | db2                | ecdba    | 0x45033ED34D21EDF5 | select * from tbl_0                        | 1          |
| 102       | db2                | ecdba    | 0x02033E45904D3DF0 | show databases                             | 1          |
| 102       | db2                | ecdba    | 0x99531AEFF718C501 | show tables                                | 1          |
| 1001      | db1                | ecdba    | 0x620B328FE9D6D71A | SELECT DATABASE()                          | 1          |
| 1001      | db1                | ecdba    | 0x903E7B5A87B51352 | select * from db6.tbl_0                    | 1          |
| 1001      | db1                | ecdba    | 0x0CE250A1C0E2C539 | select * from `db5`.tbl_0                  | 1          |
| 1001      | db1                | ecdba    | 0x45033ED34D21EDF5 | select * from tbl_0                        | 1          |
| 101       | db1                | ecdba    | 0x02033E45904D3DF0 | show databases                             | 2          |
| 102       | db2                | ecdba    | 0x6F8289B2913564A0 | update tbl_0 set username=? where corpid=? | 1          |
| 0         | information_schema | ecdba    | 0x620B328FE9D6D71A | SELECT DATABASE()                          | 1          |
| 101       | db1                | ecdba    | 0x99531AEFF718C501 | show tables                                | 1          |
| 0         | information_schema | ecdba    | 0x02033E45904D3DF0 | show databases                             | 1          |
| 1001      | db1                | ecdba    | 0x7A3428659E1BFDC2 | select * from db5.tbl_0                    | 1          |
| 103       | information_schema | ecdba    | 0xA951EB38FA9ED6A4 | select * from db15.tbl_0                   | 1          |
| 100       | information_schema | ecdba    | 0xA132AEDEC5932600 | select * from db0.tbl_0                    | 1          |
| 0         | information_schema | ecdba    | 0x594F2C744B698066 | select USER()                              | 1          |
| 0         | information_schema | ecdba    | 0x226CD90D52A2BA0B | select @@version_comment limit ?           | 1          |
+-----------+--------------------+----------+--------------------+--------------------------------------------+------------+
17 rows in set (0.01 sec)
```
达到了读写分离和分实例分库的目的。


# 6. 另一种规则写法
从上面可以看到，客户端应用在使用的时候，最好都要指定 database name ，上面是因为加了第 5 类规则才避免由于不指定db时所带来的问题，但始终要求对每个 分db 建立自己连接，或者查询之前 use dbname ，当然也可以在获取连接的时候，传递dbname过去，拿到带正确db的连接过来。

那么其实还有一种办法，不需要指定连接db，而是采用注释 hint 的形式，传递给proxysql，然后来自动路由。将第 4 节的规则 [2],[3] 改成下面的形式：
```
-- [1] read&write split
-- instance0，read & write
INSERT INTO mysql_query_rules (rule_id,active,match_pattern,apply,flagIN,flagOUT) VALUES (40,1,"\/\*\s*shard_corp_mod=(0|4|8|12)\s*\*.",0,0,20);
INSERT INTO mysql_query_rules (rule_id,active,match_digest,destination_hostgroup,apply,flagIN,flagOUT) VALUES (50,1,'^select',1000,1,20,20);
INSERT INTO mysql_query_rules (active,match_digest,negate_match_pattern,destination_hostgroup,apply,flagIN,flagOUT) VALUES (1,"^select",1,100,1,20,20);

INSERT INTO mysql_query_rules (rule_id,active,match_pattern,apply,flagIN,flagOUT) VALUES (60,1,"\/\*\s*shard_corp_mod=(1|5|9|13)\s*\*.",0,0,21);
INSERT INTO mysql_query_rules (active,match_digest,destination_hostgroup,apply,flagIN,flagOUT) VALUES (1,'^select',1001,1,21,21);
INSERT INTO mysql_query_rules (active,match_digest,negate_match_pattern,destination_hostgroup,apply,flagIN,flagOUT) VALUES (1,"^select",1,101,1,21,21);

INSERT INTO mysql_query_rules (rule_id,active,match_pattern,apply,flagIN,flagOUT) VALUES (70,1,"\/\*\s*shard_corp_mod=(2|6|10|14)\s*\*.",0,0,22);
INSERT INTO mysql_query_rules (active,match_digest,destination_hostgroup,apply,flagIN,flagOUT) VALUES (1,'^select',1002,1,22,22);
INSERT INTO mysql_query_rules (active,match_digest,negate_match_pattern,destination_hostgroup,apply,flagIN,flagOUT) VALUES (1,"^select",1,102,1,22,22);

INSERT INTO mysql_query_rules (rule_id,active,match_pattern,apply,flagIN,flagOUT) VALUES (80,1,"\/\*\s*shard_corp_mod=(3|7|11|15)\s*\*.",0,0,23);
INSERT INTO mysql_query_rules (active,match_digest,destination_hostgroup,apply,flagIN,flagOUT) VALUES (1,'^select',1003,1,23,23);
INSERT INTO mysql_query_rules (active,match_digest,negate_match_pattern,destination_hostgroup,apply,flagIN,flagOUT) VALUES (1,"^select",1,103,1,23,23);

-- [2] no /* shard_corp_mod=? */ given
insert into mysql_query_rules(rule_id,active,match_digest,destination_hostgroup,apply,flagIN) values(1000,1,'([\s\`])db(0|4|8|12)([\.\`])',100,1,0);
insert into mysql_query_rules(rule_id,active,match_digest,destination_hostgroup,apply,flagIN) values(1001,1,'([\s\`])db(1|5|9|13)([\.\`])',101,1,0);
insert into mysql_query_rules(rule_id,active,match_digest,destination_hostgroup,apply,flagIN) values(1002,1,'([\s\`])db(2|6|10|14)([\.\`])',102,1,0);
insert into mysql_query_rules(rule_id,active,match_digest,destination_hostgroup,apply,flagIN) values(1003,1,'([\s\`])db(3|7|11|15)([\.\`])',103,1,0);

-- [3] wrong usage
insert into mysql_query_rules(rule_id,active,schemaname,match_digest,apply,flagIN,error_msg,comment) 
  values(1404,1,'information_schema','^SELECT DATABASE\(\)$',1,0,'You should specify schema name first', 'use db0 Take long when no schema given for connection');

-- [7] default route
insert into mysql_query_rules(rule_id,active,apply, flagIN,error_msg,comment) values(9999,1,1, 0,'No query rules matched (by ProxySQL)', "Don't define the default hostgroup 0 for ME");

-- [8]
LOAD MYSQL QUERY RULES TO RUN;
SAVE MYSQL QUERY RULES TO DISK;
```
注意这里[2][3]用的是 `match_pattern`，而上节用的是`match_digest`，因为proxysql在处理fingerprint的时候，会去掉注释。如果在命令行测试，要加 `-c` 避免 HINT 被过滤掉。

使用时Hint放sql最后面，每个sql都要带mod或者指定实例：`select * from db5.tbl_0 /* shard_corp_mod=5 */`，真正实施起来，应用端的复杂度以及proxysql的性能，还是有待考虑的。

关于这些路由规则的写法对ProxySQL性能的影响，欢迎继续阅读这边文章 [ProxySQL之性能测试对比](http://xgknight.com/2017/04/20/mysql-proxysql-performance-test/)

参考：
- https://severalnines.com/blog/how-proxysql-adds-failover-and-query-control-your-mysql-replication-setup
- https://www.percona.com/blog/2016/08/30/mysql-sharding-with-proxysql/


---

原文连接地址：http://xgknight.com/2017/04/17/mysql-proxysql-route-rw_split/

---
