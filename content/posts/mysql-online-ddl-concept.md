---
title: mysql 5.6 原生Online DDL解析
date: 2016-05-24 16:32:49
tags: [mysql, Percona-toolkit]
categories:
- MySQL
updated: 2016-05-24 16:32:49
---

做MySQL的都知道，数据库操作里面，DDL操作（比如CREATE,DROP,ALTER等）代价是非常高的，特别是在单表上千万的情况下，加个索引或改个列类型，就有可能堵塞整个表的读写。

然后 mysql 5.6 开始，大家期待的Online DDL出现了，可以实现修改表结构的同时，依然允许DML操作(select,insert,update,delete)。在这个特性出现以前，用的比较多的工具是`pt-online-schema-change`，比较请参考[pt-online-schema-change使用说明、限制与比较](http://xgknight.com/2016/05/27/mysql-pt-online-schema-change)或 [ONLINE DDL VS PT-ONLINE-SCHEMA-CHANGE](http://www.fromdual.ch/online-ddl_vs_pt-online-schema-change) 。

## 1. Online DDL
在 MySQL 5.1 （带InnoDB Plugin）和5.5中，有个新特性叫 Fast Index Creation（下称 FIC），就是在添加或者删除二级**索引**的时候，可以不用复制原表。对于之前的版本对于索引的添加删除这类DDL操作，MySQL数据库的操作过程为如下：
1. 首先新建Temp table，表结构是 ALTAR TABLE 新定义的结构
2. 然后把原表中数据导入到这个Temp table
3. 删除原表
4. 最后把临时表rename为原来的表名

为了保持数据的一致性，中间复制数据（Copy Table）全程锁表只读，如果有写请求进来将无法提供服务，连接数爆张。

引入FIC之后，创建二级索引时会对原表加上一个S锁，创建过程不需要重建表（no-rebuild）；删除InnoDB二级索引只需要更新内部视图，并标记这个索引的空间可用，去掉数据库元数据上该索引的定义即可。这个过程也只允许读操作，不能写入，但大大加快了修改索引的速度（不含主键索引，InnoDB IOT的特性决定了修改主键依然需要 Copy Table ）。

FIC只对索引的创建删除有效，MySQL 5.6 Online DDL把这种特性扩展到了添加列、删除列、修改列类型、列重命名、设置默认值等等，实际效果要看所使用的选项和操作类别来定。

### 1.1 Online DDL选项

MySQL 在线DDL分为 `INPLACE` 和 `COPY` 两种方式，通过在ALTER语句的ALGORITHM参数指定。
- `ALGORITHM=INPLACE`，可以避免重建表带来的IO和CPU消耗，保证ddl期间依然有良好的性能和并发。
- `ALGORITHM=COPY`，需要拷贝原始表，所以不允许并发DML写操作，可读。这种copy方式的效率还是不如 inplace ，因为前者需要记录undo和redo log，而且因为临时占用buffer pool引起短时间内性能受影响。

上面只是 Online DDL 内部的实现方式，此外还有 LOCK 选项控制是否锁表，根据不同的DDL操作类型有不同的表现：默认mysql尽可能不去锁表，但是像修改主键这样的昂贵操作不得不选择锁表。

- `LOCK=NONE`，即DDL期间允许并发读写涉及的表，比如为了保证 ALTER TABLE 时不影响用户注册或支付，可以明确指定，好处是如果不幸该 alter语句不支持对该表的继续写入，则会提示失败，而不会直接发到库上执行。`ALGORITHM=COPY`默认LOCK级别
- `LOCK=SHARED`，即DDL期间表上的写操作会被阻塞，但不影响读取。
- `LOCK=DEFAULT`，让mysql自己去判断lock的模式，原则是mysql尽可能不去锁表
- `LOCK=EXCLUSIVE`，即DDL期间该表不可用，堵塞任何读写请求。如果你想alter操作在最短的时间内完成，或者表短时间内不可用能接受，可以手动指定。

但是有一点需要说明，无论任何模式下，online ddl开始之前都需要一个短时间排它锁(exclusive)来准备环境，所以alter命令发出后，会首先等待该表上的其它操作完成，在alter命令之后的请求会出现等待`waiting meta data lock`。同样在ddl结束之前，也要等待alter期间所有的事务完成，也会堵塞一小段时间。所以尽量在ALTER TABLE之前确保没有大事务在执行，否则一样出现连环锁表。

### 1.2 考虑不同的DDL操作类别

从上面的介绍可以看出，不是5.6支持在线ddl就可以随心所欲的alter table，锁不锁表要看情况：

<!-- more -->

提示：下表根据官方 [Summary of Online Status for DDL Operations](https://dev.mysql.com/doc/refman/5.6/en/innodb-create-index-overview.html) 整理挑选的常用操作。
- *In-Place* 为Yes是优选项，说明该操作支持INPLACE
- *Copies Table* 为No是优选项，因为为Yes需要重建表。大部分情况与In-Place是相反的
- *Allows Concurrent DML?* 为Yes是优选项，说明ddl期间表依然可读写，可以指定 LOCK=NONE（如果操作允许的话mysql自动就是NONE）
- *Allows Concurrent Query?* 默认所有DDL操作期间都允许查询请求，放在这只是便于参考
- *Notes* 会对前面几列Yes/No带 * 号的限制说明


|Operation | In-Place? | Copies Table? | Allows Concurrent DML? | Allows Concurrent Query? | Notes |
|--|--|--|--|--|--|
|添加索引| Yes* | No* | Yes | Yes | 对全文索引的一些限制|
|删除索引| Yes | No | Yes | Yes | 仅修改表的元数据|
|OPTIMIZE TABLE | Yes | Yes | Yes | Yes | 从 5.6.17开始使用ALGORITHM=INPLACE，当然如果指定了`old_alter_table=1`或mysqld启动带`--skip-new`则将还是COPY模式。如果表上有全文索引只支持COPY |
|对一列设置默认值 | Yes | No | Yes | Yes | 仅修改表的元数据 |
|对一列修改auto-increment 的值 | Yes | No | Yes | Yes | 仅修改表的元数据 |
|添加 foreign key constraint | Yes* | No* | Yes | Yes | 为了避免拷贝表，在约束创建时会禁用foreign_key_checks|
|删除 foreign key constraint | Yes | No | Yes | Yes | foreign_key_checks 不影响|
|改变列名 | Yes* | No* | Yes* | Yes | 为了允许DML并发, 如果保持相同数据类型，仅改变列名|
|添加列 | Yes* | Yes* | Yes* | Yes | 尽管允许 ALGORITHM=INPLACE ，但数据大幅重组，所以它仍然是一项昂贵的操作。当添加列是auto-increment，不允许DML并发 |
|删除列 | Yes | Yes* | Yes | Yes | 尽管允许 ALGORITHM=INPLACE ，但数据大幅重组，所以它仍然是一项昂贵的操作 |
|修改列数据类型 | No | Yes* | No | Yes |修改类型或添加长度，都会拷贝表，而且不允许更新操作|
|更改列顺序 | Yes | Yes | Yes | Yes | 尽管允许 ALGORITHM=INPLACE ，但数据大幅重组，所以它仍然是一项昂贵的操作 |
|修改ROW_FORMAT <br/> 和KEY_BLOCK_SIZE | Yes | Yes | Yes | Yes | 尽管允许 ALGORITHM=INPLACE ，但数据大幅重组，所以它仍然是一项昂贵的操作 |
|设置列属性NULL<br/>或NOT NULL | Yes | Yes | Yes | Yes |尽管允许 ALGORITHM=INPLACE ，但数据大幅重组，所以它仍然是一项昂贵的操作 |
|添加主键 | Yes* | Yes | Yes | Yes | 尽管允许 ALGORITHM=INPLACE ，但数据大幅重组，所以它仍然是一项昂贵的操作。<br/> 如果列定义必须转化NOT NULL，则不允许INPLACE |
|删除并添加主键 | Yes | Yes | Yes | Yes | 在同一个 ALTER TABLE 语句删除就主键、添加新主键时，才允许inplace；数据大幅重组,所以它仍然是一项昂贵的操作。 |
|删除主键 | No | Yes | No | Yes | 不允许并发DML，要拷贝表，而且如果没有在同一 ATLER TABLE 语句里同时添加主键则会收到限制 |
|变更表字符集 | No | Yes | No | Yes | 如果新的字符集编码不同，重建表 |


从表看出，In-Place为No，DML一定是No，说明 `ALGORITHM=COPY` 一定会发生拷贝表，只读。但 `ALGORITHM=INPLACEE` 也要可能发生拷贝表，但可以并发DML:
- 添加、删除列，改变列顺序
- 添加或删除主键
- 改变行格式ROW_FORMAT和压缩块大小KEY_BLOCK_SIZE
- 改变列NULL或NOT NULL
- 优化表OPTIMIZE TABLE
- 强制 rebuild 该表

不允许并发DML的情况有：修改列数据类型、删除主键、变更表字符集，即这些类型操作ddl是不能online的。

另外，更改主键索引与普通索引处理方式是不一样的，主键即聚集索引，体现了表数据在物理磁盘上的排列，包含了数据行本身，需要拷贝表；而普通索引通过包含主键列来定位数据，所以普通索引的创建只需要一次扫描主键即可，而且是在已有数据的表上建立二级索引，更紧凑，将来查询效率更高。

修改主键也就意味着要重建所有的普通索引。删除二级索引更简单，修改InnoDB系统表信息和数据字典，标记该所以不存在，标记所占用的表空间可以被新索引或数据行重新利用。

### 1.3 在线DDL的限制

- 在alter table时，如果涉及到table copy操作，要确保 `datadir` 目录有足够的磁盘空间，能够放的下整张表，因为拷贝表的的操作是直接在数据目录下进行的。
- 添加索引无需table copy，但要确保 `tmpdir` 目录足够存下索引一列的数据（如果是组合索引，当前临时排序文件一合并到原表上就会删除）
- 在主从环境下，主库执行alter命令在完成之前是不会进入binlog记录事件，如果允许dml操作则不影响记录时间，所以期间不会导致延迟。然而，由于从库是单个SQL Thread按顺序应用relay log，轮到ALTER语句时直到执行完才能下一条，所以从库会在master ddl完成后开始产生延迟。（pt-osc可以控制延迟时间，所以这种场景下它更合适）
- During each online DDL ALTER TABLE statement, regardless of the LOCK clause, there are brief periods at the beginning and end requiring an exclusive lock on the table (the same kind of lock specified by the LOCK=EXCLUSIVE clause). Thus, an online DDL operation might wait before starting if there is a long-running transaction performing inserts, updates, deletes, or SELECT ... FOR UPDATE on that table; and an online DDL operation might wait before finishing if a similar long-running transaction was started while the ALTER TABLE was in progress.
- 在执行一个允许并发DML在线 ALTER TABLE时，结束之前这个线程会应用 *online log* 记录的增量修改，而这些修改是其它thread里产生的，所以有可能会遇到重复键值错误 *(ERROR 1062 (23000): Duplicate entry)*。
- 涉及到table copy时，目前还没有机制限制暂停ddl，或者限制IO阀值  
在MySQL 5.7.6开始能够通过 performance_schema 观察alter table的进度
- 一般来说，建议把多个alter语句合并在一起进行，避免多次table rebuild带来的消耗。但是也要注意分组，比如需要copy table和只需inplace就能完成的，应该分两个alter语句。
- 如果DDL执行时间很长，期间又产生了大量的dml操作，以至于超过了 `innodb_online_alter_log_max_size` 变量所指定的大小，会引起 *DB_ONLINE_LOG_TOO_BIG* 错误。默认为 128M，特别对于需要拷贝大表的alter操作，考虑临时加大该值，以此获得更大的日志缓存空间
- 执行完 `ALTER TABLE` 之后，最好 `ANALYZE TABLE tb1` 去更新索引统计信息

## 2. 实现过程
online ddl主要包括3个阶段，prepare阶段，ddl执行阶段，commit阶段，rebuild方式比no-rebuild方式实质多了一个ddl执行阶段，prepare阶段和commit阶段类似。下面将主要介绍ddl执行过程中三个阶段的流程。

- ** Prepare阶段 ** :  
 1. 创建新的临时frm文件(与InnoDB无关)
 2. 持有EXCLUSIVE-MDL锁，禁止读写
 3. 根据alter类型，确定执行方式(copy,online-rebuild,online-norebuild)
 假如是Add Index，则选择online-norebuild即INPLACE方式
 4. 更新数据字典的内存对象
 5. 分配row_log对象记录增量(仅rebuild类型需要)
 6. 生成新的临时ibd文件(仅rebuild类型需要)

- ** ddl执行阶段 ** :  
 1. 降级EXCLUSIVE-MDL锁，允许读写
 2. 扫描old_table的聚集索引每一条记录rec
 3. 遍历新表的聚集索引和二级索引，逐一处理
 4. 根据rec构造对应的索引项
 5. 将构造索引项插入sort_buffer块排序
 6. 将sort_buffer块更新到新的索引上
 7. 记录ddl执行过程中产生的增量(仅rebuild类型需要)
 8. 重放row_log中的操作到新索引上(no-rebuild数据是在原表上更新的)
 9. 重放row_log间产生dml操作append到row_log最后一个Block


- ** commit阶段 ** :  

 1. 当前Block为row_log最后一个时，禁止读写，升级到EXCLUSIVE-MDL锁
 2. 重做row_log中最后一部分增量
 3. 更新innodb的数据字典表
 4. 提交事务(刷事务的redo日志)
 5. 修改统计信息
 6. rename临时idb文件，frm文件
 7. 变更完成

这有一直导图挺直观的：http://blog.itpub.net/22664653/viewspace-2056953 。
**添加列** 时由于需要copy table，row_log会重放到新表上（临时ibd文件），直到最后一个block，锁住原表禁止更新。

row_log记录了ddl变更过程中新产生的dml操作，并在ddl执行的最后将其应用到新的表中，保证数据完整性


## 3. 对比实验

### 3.1 添加二级索引 ###
我这里使用sysbench产生的表测试（500w数据）：
```
mysql> select version();
+------------+
| version()  |
+------------+
| 5.6.30-log |
+------------+
1 row in set (0.00 sec)

mysql> show create table sbtest1;
CREATE TABLE `sbtest1` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `k` int(10) unsigned NOT NULL DEFAULT '0',
  `c` char(120) COLLATE utf8_bin NOT NULL DEFAULT '',
  `pad` char(60) COLLATE utf8_bin NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `k_1` (`k`)
) ENGINE=InnoDB AUTO_INCREMENT=5000001 DEFAULT CHARSET=utf8 COLLATE=utf8_bin MAX_ROWS=1000000


mysql> show variables like "old_alter_table";
+-----------------+-------+
| Variable_name   | Value |
+-----------------+-------+
| old_alter_table | OFF   |
+-----------------+-------+
1 row in set (0.00 sec)

```

** 旧模式 ** 下，创建删除普通索引：
```
**SESSION1:**
mysql> set old_alter_table=1;
Query OK, 0 rows affected (0.00 sec)

mysql> alter table sbtest1 drop index idx_k_1;
Query OK, 5000000 rows affected (44.79 sec)
Records: 5000000  Duplicates: 0  Warnings: 0

mysql> alter table sbtest1 add index idx_k_1(k);
Query OK, 5000000 rows affected (1 min 11.29 sec)
Records: 5000000  Duplicates: 0  Warnings: 0


**SESSION2:**
mysql> select * from sbtest1 limit 1;
+----+---------+-------------------------------------------------------------------------------------------------------------------------+-------------------------------------------------------------+
| id | k       | c                                                                                                                       | pad                                                         |
+----+---------+-------------------------------------------------------------------------------------------------------------------------+-------------------------------------------------------------+
|  1 | 2481886 | 08566691963-88624...106334-50535565977 | 63188288836-9235114...351-49282961843 |
+----+---------+-------------------------------------------------------------------------------------------------------------------------+-------------------------------------------------------------+
1 row in set (0.00 sec)

mysql> update sbtest1 set k=2481885 where id=1;
Query OK, 1 row affected (45.16 sec)
Rows matched: 1  Changed: 1  Warnings: 0


**SESSION3:**
mysql> show processlist;
+--------+-----------------+-----------+------------+---------+--------+---------------------------------+-----------------------------------------+
| Id     | User            | Host      | db         | Command | Time   | State                           | Info                                    |
+--------+-----------------+-----------+------------+---------+--------+---------------------------------+-----------------------------------------+
| 118652 | root            | localhost | confluence | Query   |     19 | copy to tmp table               | alter table sbtest1 add index k_1(k)    |
| 118666 | root            | localhost | confluence | Query   |      3 | Waiting for table metadata lock | update sbtest1 set k=2481885 where id=1 |
| 118847 | root            | localhost | NULL       | Query   |      0 | init                            | show processlist                        |
+--------+-----------------+-----------+------------+---------+--------+---------------------------------+-----------------------------------------+
4 rows in set (0.00 sec)

同时在datadir目录下可以看到
-rw-rw---- 1 mysql mysql 8.5K May 23 21:24 sbtest1.frm
-rw-rw---- 1 mysql mysql 1.2G May 23 21:24 sbtest1.ibd
-rw-rw---- 1 mysql mysql 8.5K May 23 20:48 #sql-1c6a_1cf7c.frm
-rw-rw---- 1 mysql mysql 638M May 23 20:48 #sql-1c6a_1cf7c.ibd
```

传统ddl方式有 *copy to tmp table* 过程，dml更新操作期间被堵住45s：`Waiting for table metadata lock`。

下面改成 **Online DDL方式**
```
**SESSION1**
mysql> set old_alter_table=0;

mysql> alter table sbtest1 drop index k_1;
Query OK, 0 rows affected (0.01 sec)
Records: 0  Duplicates: 0  Warnings: 0
索引秒删

mysql> alter table sbtest1 add index k_1(k);
Query OK, 0 rows affected (13.99 sec)
Records: 0  Duplicates: 0  Warnings: 0

**SESSION2**
mysql> update sbtest1 set k=2481887 where id=1;
Query OK, 1 row affected (0.00 sec)
Rows matched: 1  Changed: 1  Warnings: 0


**SESSION3**
mysql> show processlist;
+--------+-----------------+-----------+------------+---------+--------+------------------------+--------------------------------------+
| Id     | User            | Host      | db         | Command | Time   | State                  | Info                                 |
+--------+-----------------+-----------+------------+---------+--------+------------------------+--------------------------------------+
| 118652 | root            | localhost | confluence | Query   |     10 | altering table         | alter table sbtest1 add index k_1(k) |
| 118666 | root            | localhost | confluence | Sleep   |      9 |                        | NULL                                 |
| 118847 | root            | localhost | NULL       | Query   |      0 | init                   | show processlist                     |
+--------+-----------------+-----------+------------+---------+--------+------------------------+--------------------------------------+
4 rows in set (0.00 sec)
```

添加普通索引，并未出现阻塞update操作，而且速度更快。从 rows affected 可以看出有没有copy table。

但如果在alter之前有大事务在执行，** 会阻塞 ** ddl以及后续的所有请求：

```
**SESSION1**
mysql> select * from sbtest1 where c='long select before alter';
Empty set (4.36 sec)

**SESSION2**
mysql> alter table sbtest1 add index k_1(k);
Query OK, 0 rows affected (16.28 sec)
Records: 0  Duplicates: 0  Warnings: 0

**SESSION3**
mysql> select * from sbtest1 where c='long select after alter execution but not complete';
Empty set (5.89 sec)

**SESSION4**
mysql> show processlist;
+----+-----------------+-----------+------------+---------+------+---------------------------------+------------------------------------------------------------------------------------+
| Id | User            | Host      | db         | Command | Time | State                           | Info                                                                               |
+----+-----------------+-----------+------------+---------+------+---------------------------------+------------------------------------------------------------------------------------+
|  5 | root            | localhost | confluence | Query   |    3 | Sending data                    | select * from sbtest1 where c='long select before alter'                           |
|  7 | root            | localhost | NULL       | Query   |    0 | init                            | show processlist                                                                   |
| 13 | root            | localhost | confluence | Query   |    2 | Waiting for table metadata lock | alter table sbtest1 add index k_1(k)                                               |
| 14 | root            | localhost | confluence | Query   |    1 | Waiting for table metadata lock | select * from sbtest1 where c='long select after alter execution but not complete' |
+----+-----------------+-----------+------------+---------+------+---------------------------------+------------------------------------------------------------------------------------+
5 rows in set (0.00 sec)
```

### 3.2 添加列示例 ###
添加新列是ddl操作里面相对较多的一类操作。从上文表中可以看到
```
**SESSION1**
mysql> ALTER TABLE `sbtest2` \
       ADD COLUMN `f_new_col1` int(11) NULL DEFAULT 0, \
       ADD COLUMN `f_new_col2` varchar(32) NULL DEFAULT '' AFTER `f_new_col1`;
Query OK, 0 rows affected (1 min 57.86 sec)
Records: 0  Duplicates: 0  Warnings: 0

**SESSION2**
mysql> update sbtest2 set c="update when add colomun ddl start" where c='33333';
Query OK, 0 rows affected (4.41 sec)
Rows matched: 0  Changed: 0  Warnings: 0

**SESSION3**
mysql> select * from sbtest2 where c='select when add colomun ddl start';
Empty set (3.44 sec)

**SESSION4**
mysql> show processlist;
+-----+-----------------+-----------+------------+---------+------+---------------------------+------------------------------------------------------------------------------------------------------+
| Id  | User            | Host      | db         | Command | Time | State                     | Info                                                                                                 |
+-----+-----------------+-----------+------------+---------+------+---------------------------+------------------------------------------------------------------------------------------------------+
|   5 | root            | localhost | confluence | Query   |    4 | altering table            | ALTER TABLE `sbtest2`  ADD COLUMN `f_new_col1` int(11) NULL DEFAULT 0, ADD COLUMN `f_new_col2` varch |
|   7 | root            | localhost | NULL       | Query   |    0 | init                      | show processlist                                                                                     |
| 161 | root            | localhost | confluence | Query   |    2 | Searching rows for update | update sbtest2 set c="update when add colomun ddl start" where c='33333'                             |
| 187 | root            | localhost | confluence | Query   |    1 | Sending data              | select * from sbtest2 where c='select when add colomun ddl start'                                    |
+-----+-----------------+-----------+------------+---------+------+---------------------------+------------------------------------------------------------------------------------------------------+
5 rows in set (0.00 sec)
```

看到，默认不加 ALGORITHM=INPLACE 就已经允许ddl期间并发DML操作。但是会有一个小临时文件产生：
```
-rw-rw---- 1 mysql mysql 8.6K May 23 21:42 #sql-7055_5.frm
-rw-rw---- 1 mysql mysql 112K May 23 21:42 #sql-ib21-16847116.ibd
```

当指定copy时，就会锁表了（一般你不想这样做）：
```
ALTER TABLE `sbtest2`
	DROIP COLUMN `f_new_col1`, algorithm=copy;
```

### 3.3 修改字段类型 ###
修改列类型与添加新列不一样，修改类型需要rebuild整个表：
(select ok, update waiting)
```
**SESSION1**
mysql> ALTER TABLE sbtest2
	   CHANGE f_new_col2 f_new_col2 varchar(50) NULL DEFAULT '', algorithm=inplace ;
ERROR 1846 (0A000): ALGORITHM=INPLACE is not supported. Reason: Cannot change column type INPLACE. Try ALGORITHM=COPY.
不支持INPLACE

mysql> ALTER TABLE sbtest2
	   CHANGE f_new_col2 f_new_col2 varchar(50) NULL DEFAULT '';

**SESSION2**
mysql> update sbtest2 set c="update when add colomun ddl start" where c='33333';

mysql> select * from sbtest2 where c='select when add colomun ddl start';
Empty set (3.79 sec)

mysql> show processlist;
+-----+-----------------+-----------+------------+---------+------+---------------------------------+----------------------------------------------------------------------------------+
| Id  | User            | Host      | db         | Command | Time | State                           | Info                                                                             |
+-----+-----------------+-----------+------------+---------+------+---------------------------------+----------------------------------------------------------------------------------+
|   5 | root            | localhost | confluence | Query   |    5 | copy to tmp table               | ALTER TABLE sbtest2
   CHANGE f_new_col2 f_new_col2 varchar(50) NULL DEFAULT '' |
|   7 | root            | localhost | NULL       | Query   |    0 | init                            | show processlist                                                                 |
| 161 | root            | localhost | confluence | Query   |    4 | Waiting for table metadata lock | update sbtest2 set c="update when add colomun ddl start" where c='33333'         |
| 187 | root            | localhost | confluence | Query   |    3 | Sending data                    | select * from sbtest2 where c='select when add colomun ddl start'                |
+-----+-----------------+-----------+------------+---------+------+---------------------------------+----------------------------------------------------------------------------------+
5 rows in set (0.00 sec)
```

### 3.4 Waiting for table metadata lock
Online DDL看起来很美好，实验测试也正如预期，但几次在生产环境修改索引时（5000w的表），还是无法避免出现大量 *Waiting for table metadata lock* 锁等待，线程数持续增加并告警，导致长达十多分钟不可写。后来发现原来是 5.6.16 版本开始mysql对日期、时间类型的存储格式进行了改动，会导致日期类型的表在升级前后，第一次alter必须rebuild：（[地址](https://dev.mysql.com/doc/refman/5.6/en/upgrading-from-previous-series.html)）
```
As of MySQL 5.6.16, ALTER TABLE upgrades old temporal columns to 5.6 format for ADD COLUMN, CHANGE COLUMN, MODIFY COLUMN, ADD INDEX, and FORCE operations.
Hence, the following statement upgrades a table containing columns in the old format:

  ALTER TABLE tbl_name FORCE;

This conversion cannot be done using the INPLACE algorithm because the table must be rebuilt,
so specifying ALGORITHM=INPLACE in these cases results in an error. Specify ALGORITHM=COPY if necessary.
```

关于 metadata lock 介绍参考云栖 [这系列文章](https://yq.aliyun.com/articles/27667?spm=5176.100240.searchblog.8.StFEGY)。


## 4. 参考
- [MySQL online ddl原理](http://www.cnblogs.com/cchust/p/4639397.html)
- [MySQL 5.6 Online DDL](http://www.cnblogs.com/gomysql/p/3776192.html)
- [[MySQL 5.6] MySQL 5.6 online ddl 使用、测试及关键函数栈](http://mysqllover.com/?p=547)
- [MySQL Manual Overview of Online DDL](https://dev.mysql.com/doc/refman/5.6/en/innodb-create-index-overview.html)
- [MySQL InnoDB Add Index实现调研(一：Inplace Add Index)](http://hedengcheng.com/?p=405)
- [tencentDBA 实现的在线加字段](http://tencentdba.com/blog/mysql%E5%9C%A8%E7%BA%BF%E5%8A%A0%E5%AD%97%E6%AE%B5%E5%AE%9E%E7%8E%B0%E5%8E%9F%E7%90%86/)


---

原文链接地址：http://xgknight.com/2016/05/24/mysql-online-ddl-concept/

---
