---
title: InnoDB行格式对text/blob大变长字段的影响
date: 2016-05-18 16:32:49
aliases:
- /2016/05/18/mysql-blob-row_format/
tags: [mysql, schema设计]
categories: 
- MySQL
updated: 2016-05-18 16:32:49
---

最近在排查现网Text与Blob类型，发现有不少，在《高性能MySQL(第3版)》看到对这两种变长数据类型的处理会涉及到在磁盘上创建临时表，性能开销比较大。于是把影响blob型数据存储方式了解了一下：row_format。<!-- 关于临时表的内容，请参考 -->

## 1. InnoDB的Antelop与Barracuda文件格式
Innodb存储引擎保存记录，是以行的形式存放的（与之对应的是像Google BigTable这种列数据库）。在InnoDB 1.0.x版本之前，InnoDB 存储引擎提供了 `Compact` 和 `Redundant` 两种格式来存放行记录数据，这也是目前使用最多的一种格式。Redundant 格式是为兼容之前版本而保留的。

MySQL 5.1 中的 innodb_plugin 引入了新的*文件格式*：`Barracuda`（将以前的*行格式* compact 和 redundant 合称为`Antelope`），该文件格式拥有新的两种行格式：`compressed`和`dynamic`。

在 MySQL 5.6 版本中，默认还是 Compact 行格式，也是目前使用最多的一种 ROW FORMAT。用户可以通过命令 `SHOW TABLE STATUS LIKE'table_name'` 来查看当前表使用的行格式，其中 *row_format* 列表示当前所使用的行记录结构类型。

```
mysql> show variables like "innodb_file_format";
+--------------------+-----------+
| Variable_name      | Value     |
+--------------------+-----------+
| innodb_file_format | Barracuda |
+--------------------+-----------+
1 row in set

mysql> show table status like "tablename%"\G
*************************** 1. row ***************************
           Name: t_rf_compact
         Engine: InnoDB
        Version: 10
     Row_format: Compact
           Rows: 4
 Avg_row_length: 36864
    Data_length: 147456
Max_data_length: 0
   Index_length: 0
      Data_free: 0
 Auto_increment: 7
    Create_time: 2016-05-14 20:52:58
    Update_time: NULL
     Check_time: NULL
      Collation: utf8_general_ci
       Checksum: NULL
 Create_options: 
        Comment: 
1 row in set (0.00 sec)
```

在 msyql 5.7.9 及以后版本，默认行格式由`innodb_default_row_format`变量决定，它的默认值是`DYNAMIC`，也可以在 create table 的时候指定`ROW_FORMAT=DYNAMIC`。

<!-- more -->
注意，如果要修改现有表的行模式为`compressed`或`dynamic`，必须先将文件格式设置成Barracuda：`set global innodb_file_format=Barracuda;`，再用`ALTER TABLE tablename ROW_FORMAT=COMPRESSED;`去修改才能生效，否则修改无效却无提示：

```
mysql> ALTER TABLE tablename ROW_FORMAT=COMPRESSED;
Query OK, 0 rows affected
Records: 0  Duplicates: 0  Warnings: 2

修改失败
mysql> show warnings;
+---------+------+-----------------------------------------------------------------------+
| Level   | Code | Message                                                               |
+---------+------+-----------------------------------------------------------------------+
| Warning | 1478 | InnoDB: ROW_FORMAT=COMPRESSED requires innodb_file_format > Antelope. |
| Warning | 1478 | InnoDB: assuming ROW_FORMAT=COMPACT.                                  |
+---------+------+-----------------------------------------------------------------------+
2 rows in set
```

## 2. 对TEXT/BLOB这类大字段类型的影响

### 2.1 compact
在 Antelope 两种行格式下，如果blob列值长度 <= 768 bytes，就不会发生行溢出(page overflow)，内容都在数据页(B-tree Node)；如果列值长度 > 768字节，那么前768字节依然在数据页，而剩余的则放在溢出页(off-page)，如下图：

![][1]

上面所讲的讲的blob或变长大字段类型包括blob,text,varchar，其中varchar列值长度大于某数N时也会存溢出页，在latin1字符集下N值可以这样计算：innodb的块大小默认为16kb，由于innodb存储引擎表为索引组织表，树底层的叶子节点为一双向链表，因此每个页中至少应该有两行记录，这就决定了innodb在存储一行数据的时候不能够超过8k，减去其它列值所占字节数，约等于N。

我们知道对于InnoDB来说，内存是极为珍贵的，如果把768字节长度的blob都放在数据页，虽然可以节省部分IO，但相对来说能缓存行数就变少，也就是能缓存的索引值变少了，降低了索引效率。

### 2.2 dynamic
Barracuda 的两种行格式对blob采用完全行溢出，即聚集索引记录（数据页）只保留20字节的指针，指向真实存放它的溢出段地址：
![][2]

dynamic行格式，列存储是否放到off-page页，主要取决于行大小，它会把行中最长的那一列放到off-page，直到数据页能存放下两行。TEXT/BLOB列 <=40 bytes 时总是存放于数据页。这种方式可以避免compact那样把太多的大列值放到 B-tree Node，因为dynamic格式认为，只要大列值有部分数据放在off-page，那把整个值放入都放入off-page更有效。

**compressed** 物理结构上与dynamic类似，但是对表的数据行使用zlib算法进行了压缩存储。在long blob列类型比较多的情况下用，可以降低off-page的使用，减少存储空间（一般40%左右），但要求更高的CPU，buffer pool里面可能会同时存储数据的压缩版和非压缩版，所以也多占用部分内存。这里 [MySQL 5.6 Manual innodb-compression-internals](http://dev.mysql.com/doc/refman/5.6/en/innodb-compression-internals.html) 讲的十分清楚。 

另外，由于`ROW_FORMAT=DYNAMIC` 和 `ROW_FORMAT=COMPRESSED` 是从 `ROW_FORMAT=COMPACT` 变化来的，所以他们处理 `CHAR`类型存储的方式和 COMPACT 一样。

## 3. 对blob型字段存取优化

如果一个查询涉及BLOB值，又需要使用临时表——不管它多小——它都会立即在磁盘上创建临时表。这样效率很低，尤其是对小而快的查询，临时表可能是查询中最大的开销。

比如：创建一个带Text字段的compact表：
```
mysql> CREATE TABLE `t_rf_compact` (
  `f_id` int(11) NOT NULL AUTO_INCREMENT,
  `f_char` char(30) DEFAULT NULL,
  `f_varchar` varchar(30) NOT NULL DEFAULT '',
  `f_text` text NOT NULL,
  PRIMARY KEY (`f_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=COMPACT;

mysql> insert into t_rf_compact(f_char,f_varchar,f_text) values('aa','中中',repeat('b',700));
mysql> insert into t_rf_compact(f_char,f_varchar,f_text) values('aa','文',repeat('c',60000));
第二条数据会行溢出，前768字节放在Clustered Index数据页，剩余的放扩展存储空间

mysql> explain select t1.f_id from t_rf_compact t1,t_rf_compact t2 where t1.f_id=t2.f_id order by t1.f_id limit 1; 
+----+-------------+-------+--------+---------------+---------+---------+-------------------+------+-------------+
| id | select_type | table | type   | possible_keys | key     | key_len | ref               | rows | Extra       |
+----+-------------+-------+--------+---------------+---------+---------+-------------------+------+-------------+
|  1 | SIMPLE      | t1    | index  | PRIMARY       | PRIMARY | 4       | NULL              |    6 | Using index |
|  1 | SIMPLE      | t2    | eq_ref | PRIMARY       | PRIMARY | 4       | d_ec_crm2.t1.f_id |    1 | Using index |
+----+-------------+-------+--------+---------------+---------+---------+-------------------+------+-------------+
2 rows in set (0.00 sec)


mysql> show status like "%tmp%tables";
+-------------------------+-------+
| Variable_name           | Value |
+-------------------------+-------+
| Created_tmp_disk_tables | 7     |
| Created_tmp_tables      | 36    |
+-------------------------+-------+
2 rows in set (0.00 sec)

mysql> select t1.f_id from t_rf_compact t1,t_rf_compact t2 where t1.f_id=t2.f_id order by t1.f_id limit 1;
+------+
| f_id |
+------+
|    1 |
+------+
1 row in set (0.00 sec)

mysql> show status like "%tmp%tables";
+-------------------------+-------+
| Variable_name           | Value |
+-------------------------+-------+
| Created_tmp_disk_tables | 7     |
| Created_tmp_tables      | 36    |
+-------------------------+-------+
2 rows in set (0.00 sec)
```

没有临时表产生，所以磁盘临时表无变化。让它产生临时表：（但不涉及text列）

```
mysql> explain select t1.f_id from t_rf_compact t1,t_rf_compact t2 where t1.f_id=t2.f_id order by t2.f_id;
+----+-------------+-------+--------+---------------+---------+---------+-------------------+------+----------------------------------------------+
| id | select_type | table | type   | possible_keys | key     | key_len | ref               | rows | Extra                                        |
+----+-------------+-------+--------+---------------+---------+---------+-------------------+------+----------------------------------------------+
|  1 | SIMPLE      | t1    | index  | PRIMARY       | PRIMARY | 4       | NULL              |    6 | Using index; Using temporary; Using filesort |
|  1 | SIMPLE      | t2    | eq_ref | PRIMARY       | PRIMARY | 4       | d_ec_crm2.t1.f_id |    1 | Using index                                  |
+----+-------------+-------+--------+---------------+---------+---------+-------------------+------+----------------------------------------------+
2 rows in set (0.00 sec)

mysql> select t1.f_id from t_rf_compact t1,t_rf_compact t2 where t1.f_id=t2.f_id order by t2.f_id;

mysql> show status like "%tmp%tables";
+-------------------------+-------+
| Variable_name           | Value |
+-------------------------+-------+
| Created_tmp_disk_tables | 7     |
| Created_tmp_tables      | 37    |
+-------------------------+-------+
2 rows in set (0.00 sec)
```

虽然有`Using temporary`，但内存临时表还是够用，磁盘临时表还是无变化。返回TEXT列（也会使用临时表排序）：

```
mysql> select t1.f_text from t_rf_compact t1,t_rf_compact t2 where t1.f_id=t2.f_id order by t2.f_id;
mysql> show status like "%tmp%tables";
+-------------------------+-------+
| Variable_name           | Value |
+-------------------------+-------+
| Created_tmp_disk_tables | 8     |
| Created_tmp_tables      | 38    |
+-------------------------+-------+
2 rows in set (0.00 sec)
```
`Created_tmp_disk_tables`磁盘临时表有增加，与上面结论相符：只有有TEXT/BLOB列参与，如果用到临时表，不管它多小，都会创建在磁盘上，从而带来性能消耗。

注：磁盘临时表存储引擎一定是 MyISAM，与`select @@default_tmp_storage_engine;`（5.6.3开始）看到的*InnoDB*无关，它是控制*CREATE TEMPORARY TABLE*时的默认引擎。在 5.7.5 开始`internal_tmp_disk_storage_engine`选项可以定义磁盘临时表的引擎类型。关于临时表与内存表可以参考 [[MySQL FAQ]系列 — 什么情况下会用到临时表 -老叶](http://imysql.com/2015/07/11/mysql-faq-how-using-temp-table.shtml) 。

有两种办法来减轻这种不利的情况：通过 `SUBSTRING()` 函数把值转换为 VARCHAR，或者让磁盘临时表更快一些。

让磁盘临时表运行更快的方式是，把它们放在基于内存的文件系统tmpfs，tmpfs文件系统为了降低开销不会刷新内存数据到磁盘，读写速度也很快，而临时表也不需要持久存放。mysql的 tmpdir 参数控制临时文件存放位置，建议如果使用的话要监控空间使用率。另外如果BLOB列非常大或多，可以考虑调大InnoDB日志缓存大小`innodb_log_buffer_size`。

如果使用BLOB这类变长大字段类型，需要以下后果考虑：

> - 大字段在InnoDB里可能浪费大量空间。例如，若存储字段值只是比行的要求多了一个字节，也会使用整个页面来存储剩下的字节，浪费了页面的大部分空间。同样的，如果有一个值只是稍微超过了32个页的大小，实际上就需要使用96个页面。
- 扩展存储禁用了自适应哈希，因为需要完整的比较列的整个长度，才能发现是不是正确的数据（哈希帮助InnoDB非常快速的找到“猜测的位置”，但是必须检查“猜测的位置”是不是正确）。因为自适应哈希是完全的内存结构，并且直接指向Buffer Pool中访问“最”频繁的页面，但对于扩展存储空间却无法使用Adaptive Hash。
- 太长的值可能使得在查询中作为WHERE条件不能使用索引，因而执行很慢。在应用WHERE条件之前，MySQL需要把所有的列读出来，所以可能导致MySQL要求InnoDB读取很多扩展存储，然后检查WHERE条件，丢弃所有不需要的数据。查询不需要的列绝对不是好主意，在这种特殊的场景下尤其需要避免这样做。如果发现查询正遇到这个限制带来的问题，可以尝试通过覆盖索引来解决部分问题。
- 如果一张表里有很多大字段，最好是把它们组合起来单独存到一个列里面，比如说用XML文档格式存储。这让所有的大字段共享一个扩展存储空间，这比每个字段用自己的页要好。
- 有时候可以把大字段用COMPRESS()压缩后再存为BLOB，或者在发送到MySQL前在应用程序中进行压缩，这可以获得显著的空间优势和性能收益。
 —— 《高性能MySQL(第3版)》 P368

对上面的解读就是：
- 如果预期长度范围varchar就满足，就避免使用TEXT
- 对于字段非常大的列可以在应用程序里压缩后再存到mysql，如果列值很长请考虑用单独的表存放
- 一张表有多个类blob字段，把它们组合起来如`<TEXT><f_big_col1>long..</f_big_col1> <f_content>long..</f_content></TEXT>`，再压缩存储。但要考虑是否使用全文索引，是否需要前缀索引。

## 参考
- [MySQL 大字段溢出导致数据回写失败](http://blog.opskumu.com/mysql-blob.html)
- [innodb使用大字段text，blob的一些优化建议 -玄惭](http://hidba.org/?p=551)
- [[MySQL优化案例]系列 — 优化InnoDB表BLOB列的存储效率 -老叶](http://imysql.com/2014/09/28/mysql-optimization-case-blob-stored-in-innodb-optimization.shtml)
- [InnoDB 数据表压缩原理与限制 ](http://blog.chinaunix.net/uid-24485075-id-3523032.html)
- [MySQL Manual DYNAMIC and COMPRESSED Row Formats ](http://dev.mysql.com/doc/refman/5.6/en/innodb-row-format-dynamic.html)
- 《MySQL技术内幕·InnoDB存储引擎》 P

  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-compact-768.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-barracuda-20-off-page.png


---

原文链接地址：http://xgknight.com/2016/05/18/mysql-blob-row_format/

---
