---
title: 生产环境使用 pt-table-checksum 检查MySQL数据一致性
date: 2015-12-29 10:21:25
aliases:
- /2015/12/29/mysql_replica_pt-table-checksum/
updated: 2015-12-29 00:46:23
tags: [mysql, 主从复制, percona]
categories: 
- MySQL
---

公司数据中心从托管机房迁移到阿里云，需要对mysql迁移（Replication）后的数据一致性进行校验，但又不能对生产环境使用造成影响，pt-table-checksum 成为了绝佳也是唯一的检查工具。

`pt-table-checksum` 是 Percona-Toolkit 的组件之一，用于检测MySQL主、从库的数据是否一致。其原理是在主库执行基于statement的sql语句来生成主库数据块的checksum，把相同的sql语句传递到从库执行，并在从库上计算相同数据块的checksum，最后，比较主从库上相同数据块的checksum值，由此判断主从数据是否一致。检测过程根据唯一索引将表按row切分为块（chunk），以为单位计算，可以避免锁表。检测时会自动判断复制延迟、 master的负载， 超过阀值后会自动将检测暂停，减小对线上服务的影响。

`pt-table-checksum` 默认情况下可以应对绝大部分场景，官方说，即使上千个库、上万亿的行，它依然可以很好的工作，这源自于设计很简单，一次检查一个表，不需要太多的内存和多余的操作；必要时，`pt-table-checksum` 会根据服务器负载动态改变 chunk 大小，减少从库的延迟。

为了减少对数据库的干预，`pt-table-checksum`还会自动侦测并连接到从库，当然如果失败，可以指定`--recursion-method`选项来告诉从库在哪里。它的易用性还体现在，复制若有延迟，在从库 checksum 会暂停直到赶上主库的计算时间点（也通过选项`--`设定一个可容忍的延迟最大值，超过这个值也认为不一致）。 

为了保证主数据库服务的安全，该工具实现了许多保护措施：
1. 自动设置 `innodb_lock_wait_timeout` 为1s，避免引起
2. 默认当数据库有25个以上的并发查询时，`pt-table-checksum`会暂停。可以设置 `--max-load` 选项来设置这个阀值
3. 当用 Ctrl+C 停止任务后，工具会正常的完成当前 chunk 检测，下次使用 `--resume` 选项启动可以恢复继续下一个 chunk

## 工作过程 ##

直接看 [nettedfish](http://www.nettedfish.com/blog/2013/06/04/check-replication-consistency-by-pt-table-checksum/) 的说明：

> 
1\. 连接到主库：pt工具连接到主库，然后自动发现主库的所有从库。默认采用show full processlist来查找从库，但是这只有在主从实例端口相同的情况下才有效。
3\. 查找主库或者从库是否有复制过滤规则：这是为了安全而默认检查的选项。你可以关闭这个检查，但是这可能导致checksum的sql语句要么不会同步到从库，要么到了从库发现从库没有要被checksum的表，这都会导致从库同步卡库。
5\. 开始获取表，一个个的计算。
6\. 如果是表的第一个chunk，那么chunk-size一般为1000；如果不是表的第一个chunk，那么采用19步中分析出的结果。
7\. 检查表结构，进行数据类型转换等，生成checksum的sql语句。
8\. 根据表上的索引和数据的分布，选择最合适的split表的方法。
9\. 开始checksum表。
10\. 默认在chunk一个表之前，先删除上次这个表相关的计算结果。除非–resume。
14\. 根据explain的结果，判断chunk的size是否超过了你定义的chunk-size的上限。如果超过了，为了不影响线上性能，这个chunk将被忽略。
15\. 把要checksum的行加上for update锁，并计算。
17-18\. 把计算结果存储到master_crc master_count列中。
19\. 调整下一个chunk的大小。
20\. 等待从库追上主库。如果没有延迟备份的从库在运行，最好检查所有的从库，如果发现延迟最大的从库延迟超过max-lag秒，pt工具在这里将暂停。
21\. 如果发现主库的max-load超过某个阈值，pt工具在这里将暂停。
22\. 继续下一个chunk，直到这个table被chunk完毕。
23-24\. 等待从库执行完checksum，便于生成汇总的统计结果。每个表汇总并统计一次。
25-26\. 循环每个表，直到结束。
校验结束后，在每个从库上，执行如下的sql语句即可看到是否有主从不一致发生： 

```
    select * from percona.checksums where master_cnt <> this_cnt OR master_crc <> this_crc OR 
    ISNULL(master_crc) <> ISNULL(this_crc) \G
```

<!-- more -->

## 你需要知道的选项 ##

- `--replicate-check`：执行完 checksum 查询在percona.checksums表中，不一定马上查看结果呀 —— yes则马上比较chunk的crc32值并输出DIFFS列，否则不输出。默认yes，如果指定为`--noreplicate-check`，一般后续使用下面的`--replicate-check-only`去输出DIFF结果。

- `--replicate-check-only`：不在主从库做 checksum 查询，只在原有 `percona.checksums` 表中查询结果，并输出数据不一致的信息。周期性的检测一致性时可能用到。

- `--nocheck-binlog-format`：不检测日志格式。这个选项对于 ROW 模式的复制很重要，因为`pt-table-checksum`会在 Master和Slave 上设置`binlog_format=STATEMENT`（确保从库也会执行 checksum SQL），MySQL限制从库是无法设置的，所以假如行复制从库，再作为主库复制出新从库时（A->B->C），B的checksums数据将无法传输。（没验证）

- `--replicate=` 指定 checksum 计算结果存到哪个库表里，如果没有指定，默认是 percona.checksums 。
但是我们检查使用的mysql用户一般是没有 create table 权限的，所以你可能需要先手动创建：

    ```
    CREATE DATABASE IF NOT EXISTS percona;
    CREATE TABLE IF NOT EXISTS percona.checksums (
        db CHAR(64) NOT NULL,
        tbl CHAR(64) NOT NULL,
        chunk INT NOT NULL,
        chunk_time FLOAT NULL,
        chunk_index VARCHAR(200) NULL,
        lower_boundary TEXT NULL,
        upper_boundary TEXT NULL,
        this_crc CHAR(40) NOT NULL,
        this_cnt INT NOT NULL,
        master_crc CHAR(40) NULL,
        master_cnt INT NULL,
        ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (db,tbl,chunk),
        INDEX ts_db_tbl(ts,db,tbl)
    ) ENGINE=InnoDB;
    ```

生产环境中数据库用户权限一般都是有严格管理的，假如连接用户是`repl_user`（即直接用复制用户来检查），它应该额外赋予对其它库的 SELECT ，LOCK TABLES 权限，如果后续要用 pt-table-sync 就就需要写权限了。对percona库有写权限：

        GRANT ALL PRIVILEGEES on percona.* to repl_user@'%' IDENTIFIED BY 'repl_pass';
        GRANT SELECT,LOCK TABLES,PROCESS,SUPER on *.* to repl_user@'%';

注：
    
1. 为了减少不必要的麻烦，确保你的 repl_user@'xxx' 用户能同时登陆主库和从库
2. `--create-replicate-table` 选项会自动创建 percona.checksums 表，但也意味着赋予额外的 `CREATE TABLE`权限给 percona_tk@'xxx' 用户。默认yes
3. PROCESS用于自动发现从库信息，SUPER权限用于set binlog_format。

- `--no-check-replication-filters` 表示不需要检查 Master 配置里是否指定了 Filter。 默认会检查，如果配置了 Filter，如 replicate_do_db,replicate-wild-ignore-table,binlog_ignore_db 等，在从库checksum就与遇到表不存在而报错退出，所以官方默认是yes（`--check-replication-filters`）但我们实际在检测中时指定`--databases=`，所以就不存在这个问题，干脆不检测

- `--empty-replicate-table`：每个表checksum开始前，清空它之前的检测数据（不影响其它表的checksum数据），默认yes。当然如果使用`--resume`启动检测数据不会清空。
当启用`--noempty-replicate-table`即不清空时，不计算计算chunk,只计算。

- `--databases=`，`-d`：要检查的数据库，逗号分隔。用脚趾头想也知道 `--databases-regex` 正则匹配要检测的数据库，`--ignore-databases[-regex]`忽略检查的库。Filter选项。
- `--tables=`，`-t`：要检查的表，逗号分隔。如果要检查的表分布在不同的db中，可以用`--tables=dbname1.table1,dbnamd2.table2`的形式。同理有`--tables-regex`，`--ignore-tables`，`--ignore-tables-regex`。`--replicate`指定的checksum表始终会被过滤。

- `--recursion-method`：发现从库的方式。pt-table-checksum 默认可以在主库的 `processlist` 中找到从库复制进程，从而识别出有哪些从库，但如果使用是非标准3306端口，会导致找不到从库信息。此时就会自动采用`host`方式，但需要提前在从库 my.cnf 里面配置`report_host`、`report_port`信息，如：
```
        report_host = MASTER_HOST
        report_port = 13306
```
最终极的办法是`dsn`，dsn指定的是某个表（如 percona.dsns ），表行记录是改主库的（多个）从库的连接信息。适用以下任一情形：

1. 主库不能自动发现从库
2. 不想在从库添加额外配置（因为要重启）
3. 主从检测连接用户信息不一样
4. 多个从库时只想验证指定从库的一致

我比较倾向使用DSN的方式。这个dsns表只需要在执行 `pt-table-checksum` 命令的服务器上能够访问到就行。这里纠正一个认识，网上很多人说 pt-table-checksum 要在主库上执行，其实不是的，我的mysql实例比较多，只需在某一台服务器上安装percona-toolkit，这台服务能够同时访问主库和从库就行了。具体用法见后面实例。


## 检测实例 ##

### 同网段间主从一致检查
场景：
1. 标准端口3306，只检查某一个库的关键表
2. 一主一从，binlog**不**是ROW模式
3. 同网段复制，percona_tk@'192.168.5.%' 具备该有的权限：
```
        GRANT ALL PRIVILEGEES on repl_user.* to repl_user@'192.168.5.%' IDENTIFIED BY 'repl_pass';
        GRANT SELECT,LOCK TABLES,PROCESS,SUPER on *.* to repl_user@'192.168.5.%';
```
这是最简单的方式，把要连接和检查的信息交代就行了：
```
# pt-table-checksum h=MASTER_HOST,u=repl_user,p='repl_pass',P=3306 \
--databases=d_ts_profile --tables=t_user,t_user_detail,t_user_group --nocheck-replication-filters
```
如果是首次运行，会在主库自动创建 percona.checksums 表。

输出结果：

```
Replica lag is 2307 seconds on mysql-5.  Waiting.
Checksumming d_ts_profile.t_user_account:   3% 54:48 remain
            TS ERRORS  DIFFS     ROWS  CHUNKS SKIPPED    TIME TABLE
12-18T16:07:48      0      0   313641       9       0 146.417 d_ts_profile.t_user
12-18T16:08:00      0      0   397734      12       0  11.747 d_ts_profile.t_user_detail
12-18T16:08:24      0      0  1668327      20       0  23.941 d_ts_profile.t_user_group
```

- TS ：完成检查的时间戳。
- ERRORS ：检查时候发生错误和警告的数量。 
- DIFFS ：不一致的chunk数量。当指定 `--no-replicate-check` 即检查完但不立即输出结果时，会一直为0；当指定 `--replicate-check-only` 即不检查只从checksums表中计算crc32，且只显示不一致的信息（毕竟输出的大部分应该是一致的，容易造成干扰）。
- ROWS ：比对的表行数。
- CHUNKS ：被划分到表中的块的数目。
- SKIPPED ：由于错误或警告或过大，则跳过块的数目。
- TIME ：执行的时间。
- TABLE ：被检查的表名

### 使用dsn跨数据中心检测
场景：
1. 非标准端口13306，只检查以 d_ts 开头的所有库
2. 一主二从，binlog**是**ROW模式，其中一从在阿里云ECS上，主库是无法直接访问该从库的
3. 检测用的账号因为不是%，所以不一样
4. 以下是我环境的情况
MASTER_HOST:13306 主库
REPLICA_HOST:3306    从库
PTCHECK_HOST pt-table-checksum所在服务器
DSN_DBHOST，记录从库（连接）dsns的数据库

最优的方式就是dsn指定从库了。在从库或从库同网段主机里装上 percona-toolkit。

在DSN_DBHOST 数据库实例上创建DSNs表：

```
create database percona;
CREATE TABLE `percona`.`dsns` (
`id` int(11) NOT NULL AUTO_INCREMENT,
`parent_id` int(11) DEFAULT NULL,
`dsn` varchar(255) NOT NULL,
PRIMARY KEY (`id`)
);

GRANT ALL PRIVILEGEES on percona.* to percona_tk@'PTCHECK_HOST' IDENTIFIED BY 'percona_pass';
```
如果有多个实例要检查，可以创建多个类似的dsns表。上面的percona_tk用户只是用来访问dsn库。插入从库信息：

```
use percona;
insert into dsns(dsn) values('h=REPLICA_HOST,P=3306,u=repl_user,p=repl_pass');
```
DSNs记录 dsn 列格式如 `h=REPLICA_HOST,u=repl_user,p=repl_pass`

在 PTCHECK_HOST 上执行检查命令：

```
# pt-table-checksum --replicate=percona.checksums --nocheck-replication-filters --no-check-binlog-format \
h=MASTER_HOST,u=repl_user,p='repl_pass',P=13306 --databases-regex=d_ts.* \
--recursion-method dsn=h=DSN_DBHOST,u=percona_tk,p='percona_pass',P=3306,D=percona,t=dsn
```
选项的意思就不多说了。

检测完如果一致，其实是求个心安，特别是在做数据迁移的时候。如果不一致，那就需要借助 `pt-table-sync` 工具了，不作介绍。

## 常见错误 ##

1. Diffs cannot be detected because no slaves were found
不能自动找到从库，确认processlist或host或dsns方式用对了。

1. Cannot connect to h=slave1.***.com,p=...,u=percona_user
可以在`pt-table-checksum`命令前加`PTDEBUG=1`来看详细的执行过程，如端口、用户名、权限错误。

1. Waiting for the --replicate table to replicate to XXX
问题出在 percona.checksums 表在从库不存在，根本原因是没有从主库同步过来，所以看一下从库是否延迟严重。

1. Pausing because Threads_running=25
反复打印出类似上面停止检查的信息。这是因为当前数据库正在运行的线程数大于默认25，pt-table-checksum 为了减少对库的压力暂停检查了。等数据库压力过了就好了，或者也可以直接 Ctrl+C 终端，下一次加上`--resume`继续执行，或者加大`--max-load=`值。

1. 字符集问题
```
Error checksumming table Error executing checksum query: DBD::mysql::st execute failed: Illegal mix of collations
12-17T14:48:04 Error checksumming table d_ec_cs.t_online_cs: Error executing checksum query: 
DBD::mysql::st execute failed: Illegal mix of collations for operation 'concat_ws' [for Statement 
"REPLACE INTO `percona`.`ali_checksum` (db, tbl, chunk, chunk_index, lower_boundary, upper_boundary, this_cnt, this_crc) SELECT ?, ?, ?, ?, ?, ?, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `f_cs_id`, `f_corp_id`, `f_valid`, `f_show_name`, `f_online_msg`, `f_offline_msg`, `f_show_mobile`, `f_group_id`, `f_qq`, `f_show_qq`, `f_msn`, `f_show_msn`, `f_sms_online`, `f_scheme`, `f_tel`, `f_telno`, `f_show_tel`, `f_contact`, `f_mobile`, `f_position`, `f_other1`, `f_other2`, `f_other_text1`, `f_other_text2`, `f_email`, `f_qq_first`, `f_qq_first_type`, `f_aids_open`, `f_aids_qq`, `f_aids_crmqq`, `f_aids_yahoo`, `f_aids_skype`, `f_aids_aliww`, `f_aids_msn`, `f_aids_alibaba`, `f_aids_alitrade`, CONCAT(ISNULL(`f_show_name`), ISNULL(`f_group_id`), ISNULL(`f_qq`), ISNULL(`f_show_qq`), ISNULL(`f_sms_online`), ISNULL(`f_other_text1`), ISNULL(`f_other_text2`), ISNULL(`f_email`)) )) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `d_ec_cs`.`t_online_cs` 
/*checksum table*/" with ParamValues: 0='d_ts_profile', 1='t_user_account', 2=1, 3=undef, 4=undef, 5=undef] at /usr/bin/pt-table-checksum line 10520.
```
是个bug，暂时无法解决，[Illegal mix of collations for operation 'concat_ws'](https://bugs.launchpad.net/percona-toolkit/+bug/1427552)。

## 参考

- [pt-table-checksum](https://www.percona.com/doc/percona-toolkit/2.2/pt-table-checksum.html)
- [用pt-table-checksum校验数据一致性](http://www.nettedfish.com/blog/2013/06/04/check-replication-consistency-by-pt-table-checksum/)
- [使用pt-table-checksum及pt-table-sync校验复制一致性详细介绍](http://blog.csdn.net/melody_mr/article/details/45224249)
- [Pausing because Threads_running=0](http://imysql.com/2015/04/19/mysql-faq-pt-table-checksum-use-case.shtml)


---

本文链接地址：http://xgknight.com/2015/12/29/mysql_replica_pt-table-checksum/

---
