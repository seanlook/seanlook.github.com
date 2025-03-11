---
title: MySQL order by limit 走错索引(range->indexscan)
date: 2017-10-26 15:32:49
tags: [mysql, 优化]
categories:
- MySQL
updated: 2017-10-26 15:32:49
---

生产库遇到过好几例本文要讨论的案例，而且比较棘手。简而言之，有类似这样的查询 `SELECT * FROM t1 where t1.f2>1 and t2.f2<100 order by t1.id`，id是主键，条件里面有个range查询，就会造成优化器是选择主键，还是选择filesort问题，有些特殊情况就会选错索引，比如为了回避内存排序，选择了主键扫描，导致原本走范围过滤再sort 500ms勉强可以结束的查询，5分钟不出结果。

下面具体来这个案例。

# 1. 背景
阿里云RDS，5.6.16-log。
表 d_ec_someextend.t_tbl_test_time_08:
```
CREATE TABLE `t_tbl_test_time_08` (
  `f_some_id` int(11) unsigned DEFAULT '0',
  `f_qiye_id` int(11) DEFAULT '0',
  `f_type` tinyint(3) DEFAULT '0' COMMENT '有效联系类型 1: QQ联系，2:拨打电话，3:发送邮件，4:发送短信，5:添加跟进记录，6:拜访客户，7:EC联系，8:更新客户阶段',
  `f_contact_time` timestamp NULL DEFAULT '1970-01-01 16:00:01',
  UNIQUE KEY `some_qiye_type` (`f_some_id`,`f_qiye_id`,`f_type`),
  KEY `f_contact_time` (`f_contact_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

表索引信息：
```
mysql> show table status like "t_tbl_test_time_08";
+-----------------------+--------+---------+------------+----------+----------------+-------------+-----------------+--------------+-----------+----------------+---------------------+-------------+------------+--------------------+----------+----------------+---------+--------------+
| Name                  | Engine | Version | Row_format | Rows     | Avg_row_length | Data_length | Max_data_length | Index_length | Data_free | Auto_increment | Create_time         | Update_time | Check_time | Collation          | Checksum | Create_options | Comment | Block_format |
+-----------------------+--------+---------+------------+----------+----------------+-------------+-----------------+--------------+-----------+----------------+---------------------+-------------+------------+--------------------+----------+----------------+---------+--------------+
| t_tbl_test_time_08 | InnoDB |      10 | Compact    | 19264318 |             45 |   882900992 |               0 |   2176843776 | 752877568 | NULL           | 2017-10-25 20:27:08 | NULL        | NULL       | utf8mb4_general_ci | NULL     |                |         | Original     |
+-----------------------+--------+---------+------------+----------+----------------+-------------+-----------------+--------------+-----------+----------------+---------------------+-------------+------------+--------------------+----------+----------------+---------+--------------+
1 row in set
 
mysql> show index from t_tbl_test_time_08;
+--------------------+------------+-----------------+--------------+----------------+-----------+-------------+----------+--------+------+------------+---------+---------------+
| Table              | Non_unique | Key_name        | Seq_in_index | Column_name    | Collation | Cardinality | Sub_part | Packed | Null | Index_type | Comment | Index_comment |
+--------------------+------------+-----------------+--------------+----------------+-----------+-------------+----------+--------+------+------------+---------+---------------+
| t_tbl_test_time_08 |          0 | some_qiye_type  |            1 | f_some_id      | A         |    19264318 | NULL     | NULL   | YES  | BTREE      |         |               |
| t_tbl_test_time_08 |          0 | some_qiye_type  |            2 | f_qiye_id      | A         |    19264318 | NULL     | NULL   | YES  | BTREE      |         |               |
| t_tbl_test_time_08 |          0 | some_qiye_type  |            3 | f_type         | A         |    19264318 | NULL     | NULL   | YES  | BTREE      |         |               |
| t_tbl_test_time_08 |          1 | f_contact_time  |            1 | f_contact_time | A         |     9632159 | NULL     | NULL   | YES  | BTREE      |         |               |
+--------------------+------------+-----------------+--------------+----------------+-----------+-------------+----------+--------+------+------------+---------+---------------+
4 rows in set
```

**问题查询：**
```
select f_some_id from d_ec_some1.t_tbl_test_time_08
where f_qiye_id=5077665 and f_type=9
and f_contact_time > '2017-10-17 14:23:49' and f_contact_time < '2017-10-17 14:23:53'
order by f_some_id limit 300
```
<!-- more -->
该表的其它查询：
```
SELECT `c`.`f_some_id`, max(f_contact_time) AS `time` FROM `d_ec_some`.`t_some_relation` AS `r`
LEFT JOIN `d_ec_someextend`.`t_tbl_test_time_10` AS `c` ON c.f_some_id=r.f_some_id AND c.f_type in(1,2,3,4,5,6,7)
WHERE (r.f_qiye_id='4047065' and r.f_user_id='4047064' and c.f_some_id is not null)
GROUP BY `f_some_id` ORDER BY `time` desc LIMIT 20
-- group-by, order-by
  
select f_some_id, f_type, f_contact_time from d_ec_some1.t_tbl_test_time_08
where f_qiye_id = 1181333
and f_type > 0 and f_type < 11
and f_some_id > 263047293 and f_some_id < 780306437
order by f_some_id
-- 分页
```

# 2. explain
问题查询执行计划：
```
mysql> explain extended select f_some_id from d_ec_some1.t_tbl_test_time_08
where f_qiye_id=5077665 and f_type=9
and f_contact_time > '2017-10-17 14:23:49' and f_contact_time < '2017-10-17 14:23:53'
order by f_some_id limit 300;
+----+-------------+-----------------------+-------+----------------+---------------+---------+------+-------+----------+-------------+
| id | select_type | table                 | type  | possible_keys  | key           | key_len | ref  | rows  | filtered | Extra       |
+----+-------------+-----------------------+-------+----------------+---------------+---------+------+-------+----------+-------------+
|  1 | SIMPLE      | t_tbl_test_time_08    | index | f_contact_time | some_qiye_type | 12     | NULL | 16032 |  2248.49 | Using where |
+----+-------------+-----------------------+-------+----------------+---------------+---------+------+-------+----------+-------------+
1 row in set
 
-- 指定一个索引
mysql> explain extended select f_some_id from d_ec_some1.t_tbl_test_time_08  use index(f_contact_time)
where f_qiye_id=5077665 and f_type=9
and f_contact_time > '2017-10-17 14:23:49' and f_contact_time < '2017-10-17 14:23:53'
order by f_some_id limit 300;
+----+-------------+-----------------------+-------+----------------+----------------+---------+------+--------+----------+---------------------------------------------------------------+
| id | select_type | table                 | type  | possible_keys  | key            | key_len | ref  | rows   | filtered | Extra                                                         |
+----+-------------+-----------------------+-------+----------------+----------------+---------+------+--------+----------+---------------------------------------------------------------+
|  1 | SIMPLE      | t_tbl_test_time_08    | range | f_contact_time | f_contact_time | 5       | NULL | 360478 |      100 | Using index condition; Using where; Using MRR; Using filesort |
+----+-------------+-----------------------+-------+----------------+----------------+---------+------+--------+----------+---------------------------------------------------------------+
1 row in set
```

解释：
第一个explain结果里面，`type=index`，表示 full index scan。注意这里看到的 index 不代表“查询用到索引了”。全索引扫描比全表扫描并不好到拿去，甚至更慢（因为随机IO）。是否用到正确的索引要看key那一列: 
`some_qiye_type` 索引定义是 `(f_some_id,f_qiye_id,f_type)`，从key_len=12看得出这三列都用上了（12=4+5+3）。但实际这个执行计划需要200多秒。

第二个explain，在sql里面指定了 `use index(f_contact_time)`，依据是where条件里面f_contact_time的范围固定4s，猜想数据量不会很大，过滤效果会比较好。
解释器结果，`type=range`，表示是个范围查找(“范围”涵盖的种类不止</>)，使用的索引是 `f_contact_time(f_contact_time)`。Extra列:
- `Using index condition`: 用到了索引下推特性。Using where是回表拿数据。关于ICP见文后参考。
- `Using MRR`: 用到了 Multi-Range Read 优化特性。mysql在通过二级索引范围查找的时候，得到的记录在物理上是无序的，为了减少去获取数据的随机IO，它会在内存缓冲区里面先根据rowid快速排序，然后顺序IO去拉取数据。（这个缓冲区大小参数由 read_rnd_buffer_size 控制）
- `Using filesort`: 需要内存排序。对应 order by f_some_id

rows扫描虽然36w行，比前面的 16032 要多，但这个执行计划实际运行只需要0.7s，要快将近300倍。

但MySQL优化器默认选择了第一个更慢的执行计划，它的理由是走 some_qiye_type 索引不需要内存排序，候选的 f_contact_time 被淘汰。mysql是基于cost的，所以在想是不是有什么参数可以改变optimizer的行为，让它filesort。
（这里提一下，这类查询该表上非常多，绝大部分都走的是 f_contact_time，偶尔会有几条走some_qiye_type。这种执行计划不稳定的查询，实际带来的风险是会很高的，可能会拖垮db）

这里我们祭出优化sql的两大法宝：profiling和optimizer_trace，来尝试找出是什么因素。
- `profiling`：可以定位出sql从接受到返回结果，时间都耗在哪里
- `optimizer_trace`: 跟踪优化器的成本评估过程，可以情况的看到它如何从多个候选索引里，做出选择

# 3. profiling
先来看两种查询计划 profiling 的结果。

profiling 默认
```
mysql> set profiling=1;
mysql> select f_some_id from d_ec_some1.t_tbl_test_time_08 where f_qiye_id=5077665 and f_type=9
and f_contact_time > '2017-10-17 14:23:49' and f_contact_time < '2017-10-17 14:23:53' order by f_some_id limit 300;

mysql> show profile block io,cpu for query 1;
+----------------------+------------+------------+------------+--------------+---------------+
| Status               | Duration   | CPU_user   | CPU_system | Block_ops_in | Block_ops_out |
+----------------------+------------+------------+------------+--------------+---------------+
| starting             | 0.000121   | 0          | 0          |            0 |             0 |
| checking permissions | 3.2E-5     | 0          | 0          |            0 |             0 |
| Opening tables       | 3.7E-5     | 0          | 0          |            0 |             0 |
| init                 | 4.2E-5     | 0          | 0          |            0 |             0 |
| System lock          | 2.9E-5     | 0          | 0          |            0 |             0 |
| optimizing           | 3.3E-5     | 0          | 0          |            0 |             0 |
| statistics           | 0.005796   | 0          | 0.000999   |          448 |             0 |
| preparing            | 4.3E-5     | 0          | 0          |            0 |             0 |
| Sorting result       | 2.8E-5     | 0          | 0          |            0 |             0 |
| executing            | 2.7E-5     | 0          | 0          |            0 |             0 |
| Sending data         | 172.824522 | 189.040262 | 2.441629   |      1504928 |          6896 |
| end                  | 8.3E-5     | 0          | 0          |            0 |             0 |
| query end            | 3E-5       | 0          | 0          |            0 |             0 |
| closing tables       | 3.3E-5     | 0          | 0          |            0 |             0 |
| freeing items        | 7E-5       | 0          | 0          |            0 |             0 |
| logging slow query   | 3.1E-5     | 0          | 0          |            0 |             0 |
| Opening tables       | 3.4E-5     | 0          | 0          |            0 |             0 |
| System lock          | 7E-5       | 0          | 0          |            0 |             8 |
| cleaning up          | 9.5E-5     | 0          | 0          |            0 |             0 |
+----------------------+------------+------------+------------+--------------+---------------+
19 rows in set
 
mysql> show status like "Handler%";
+----------------------------+---------+
| Variable_name              | Value   |
+----------------------------+---------+
| Handler_commit             | 1       |
| Handler_delete             | 0       |
| Handler_discover           | 0       |
| Handler_external_lock      | 4       |
| Handler_mrr_init           | 0       |
| Handler_prepare            | 0       |
| Handler_read_first         | 1       |
| Handler_read_key           | 1       |
| Handler_read_last          | 0       |
| Handler_read_next          | 9430930 |
| Handler_read_prev          | 0       |
| Handler_read_rnd           | 0       |
| Handler_read_rnd_next      | 0       |
| Handler_rollback           | 0       |
| Handler_savepoint          | 0       |
| Handler_savepoint_rollback | 0       |
| Handler_update             | 0       |
| Handler_write              | 1       |
+----------------------------+---------+
18 rows in set
```

profiling use index:
```
mysql> set profiling=1;
mysql> select .... use index(f_contact_time)
mysql> show profile block io,cpu for query 1;
+----------------------+----------+----------+------------+--------------+---------------+
| Status               | Duration | CPU_user | CPU_system | Block_ops_in | Block_ops_out |
+----------------------+----------+----------+------------+--------------+---------------+
| starting             | 0.00013  | 0        | 0          |            0 |             0 |
| checking permissions | 3.4E-5   | 0        | 0          |            0 |             0 |
| Opening tables       | 4.5E-5   | 0        | 0          |            0 |             0 |
| init                 | 4.6E-5   | 0        | 0          |            0 |             0 |
| System lock          | 3E-5     | 0        | 0          |            0 |             0 |
| optimizing           | 3.9E-5   | 0        | 0          |            0 |             0 |
| statistics           | 0.000109 | 0        | 0          |            0 |             0 |
| preparing            | 5.5E-5   | 0        | 0          |            0 |             0 |
| Sorting result       | 3.1E-5   | 0        | 0          |            0 |             0 |
| executing            | 3.2E-5   | 0        | 0          |            0 |             0 |
| Sending data         | 3.4E-5   | 0        | 0          |            0 |             0 |
| Creating sort index  | 1.703224 | 1.718739 | 0.012999   |            0 |             0 |
| end                  | 8.4E-5   | 0        | 0          |            0 |             0 |
| query end            | 3.2E-5   | 0        | 0          |            0 |             0 |
| closing tables       | 3.9E-5   | 0        | 0          |            0 |             0 |
| freeing items        | 7.3E-5   | 0        | 0          |            0 |             0 |
| logging slow query   | 3.2E-5   | 0        | 0          |            0 |             0 |
| Opening tables       | 5E-5     | 0        | 0          |            0 |             0 |
| System lock          | 6.9E-5   | 0        | 0          |            0 |             8 |
| cleaning up          | 4.1E-5   | 0        | 0          |            0 |             0 |
+----------------------+----------+----------+------------+--------------+---------------+
20 rows in set
set profiling=0;
 
mysql> show status like "Handler%";
+----------------------------+--------+
| Variable_name              | Value  |
+----------------------------+--------+
| Handler_commit             | 1      |
| Handler_delete             | 0      |
| Handler_discover           | 0      |
| Handler_external_lock      | 6      |
| Handler_mrr_init           | 0      |
| Handler_prepare            | 0      |
| Handler_read_first         | 0      |
| Handler_read_key           | 188156 |
| Handler_read_last          | 0      |
| Handler_read_next          | 188155 |
| Handler_read_prev          | 0      |
| Handler_read_rnd           | 188155 |
| Handler_read_rnd_next      | 0      |
| Handler_rollback           | 0      |
| Handler_savepoint          | 0      |
| Handler_savepoint_rollback | 0      |
| Handler_update             | 0      |
| Handler_write              | 1      |
+----------------------------+--------+
18 rows in set
```

**第一个profiling**
看到第一个profiling里面 `Sending data` 时间最长，第二个 `Creating sort index` 最久
```
Sending data:
The thread is reading and processing rows for a SELECT statement, and sending data to the client. Because operations occurring during this state tend to perform large amounts of disk access (reads), it is often the longest-running state over the lifetime of a given query.
  
Creating sort index
The thread is processing a SELECT that is resolved using an internal temporary table
```
Sending data 很具有误导性，它不仅表示发送数据到客户端，还包括“收集”数据，即mysql根据索引条件检索完数据后，得到一堆rowid，再根据rowid回表拿数据，有可能还要对数据过滤、排序，所以抛开网络因素，sending data时间长表明有大量的读磁盘操作，是非常笼统的一个状态。
下面的status里面
- `Handler_read_first`: 索引里面第一条记录被读取的次数，为1，说明做了一次索引全扫描。与前面 explain 结果 type=index 是一致的。
- `Handler_read_key`：根据索引定位到一行记录的次数。这个值越高，说明使用到了高效的索引。
- `Handler_read_next`：
  Number of requests to read the next row in key order, incremented if you are querying an index column 
  with a range constraint or if you are doing an index scan.

  即根据索引key的顺序，依次去获取行数据的次数。
  这个值在这里非常的大，表明Server读取从头读取索引 `(f_some_id,f_qiye_id,f_type)` key的 9430930 行数据之后，找到了300个满足条件的记录，并且已是排好顺序。在这里值会随着limit的增大而增大。

**第二个profiling**
- `Handler_read_rnd`：
  The number of requests to read a row based on a fixed position. This value is high if you are doing a lot of queries
  that require sorting of the result. You probably have a lot of queries that require MySQL to scan entire tables or you have joins
  that don't use keys properly.

  随机读取行数据的次数，可以认为是有一堆没有顺序的主键，要依次去读取数据的次数（随机IO）。一般在有内存排序的时候，后者join查询的副表关联字段上没有好的索引，这个值都会比较高。

经过计算，条件满足 `f_contact_time > '2017-10-17 14:23:49' and f_contact_time < '2017-10-17 14:23:53'` 的记录有188155 个，因此根据索引依次读取到的行数 Handler_read_key=188155。

这里有两个疑问个人没有解开：
1. 既然有MRR，Handler_read_rnd为什么还这么高呢，不应该是是顺序IO了？
这里不太肯定，两种可能：一是MRR不影响这个计数；第二种可能是，我们这个表上没有主键，唯一索引也不满足所有列都NOT NULL定义，也就是这个表的主键实际是innodb内部维持增长的rowid，使用MRR之后，rowid有序但并不连续，读取行的随机性没有得到大的改善。
2. `Using index condition` 在这里有点费解，因为似乎没有where条件可以下推，f_contact_time索引只有 f_contact_time 这一列。


上面的分析过程只能知道实际执行过程是怎样的，直接从explain也能看出结果，这里是顺便理解一下 Hander_read_xxx, MRR, ICP 的含义，大部分sql优化都不用不到profiling和status。


# 4. optimizer_trace
再看 optimizer_trace 跟踪的结果：(因为trace的信息太长，放到github gist上了)

- default： https://gist.github.com/seanlook/fe7d9065b1c05e766d88b4a5c3babb65
- use index：https://gist.github.com/seanlook/b687daf63c8babee96f567c123cb9ddd

optimizer_trace包含三个步骤，下面是本次trace简化的结构：
1. json_preparation
2. json_optimization
   - condition_processing
     - equality_propagation
     - constant_propagation
     - trivial_condition_removal
   - table_dependencies
   - ref_optimizer_key_uses
   - rows_estimation
     - range_analysis
     - table_scan
     - potential_range_indices
     - chosen_range_access_summary
   - considered_execution_plans
     - best_access_path
   - attaching_conditions_to_tables
     - attached_conditions_computation
     - rechecking_index_usage
   - clause_processing
   - refine_plan
     - pushed_index_condition
     - access_type
   - reconsidering_access_paths_for_index_ordering
     - plan_changed
     - access_type, index
3. json_execution

可以看到上面default与use index两次的trace，前大半部分都是一样的，候选索引都是 *access_type=range, index=f_contact_time*，就在 `reconsidering_access_paths_for_index_ordering` 的地方，“一票否决”，从而选择了 *access_type=index_scan, index=some_qiye_type*。

搜索 reconsidering_access_paths_for_index_ordering 可以在mysql或percona的官网上，找到四五个相关的 bug report ：

[#70245](https://bugs.mysql.com/bug.php?id=70245)，[#78997](https://bugs.mysql.com/bug.php?id=78997)，[percona#1362212](https://bugs.launchpad.net/percona-server/+bug/1362212)，[#74602 ](https://bugs.mysql.com/bug.php?id=74602)

网上提及比较多的是 #70245，调整参数 `eq_range_index_dive_limit` 可解决这个问题。我们也遇到过这个案例，见 [MySQL 5.6 查询优化器新特性的“BUG”](http://imysql.com/2014/08/05/a-fake-bug-with-eq-range-index-dive-limit.shtml) 。但是本文的例子满足range的个数达到18w(explain估算是36w)，也试着加大这个参数从2到800000，都没作用。

`#74602` 这个说的是low_limit导致的，刚好在 optimizer_trace 里面的 `rechecking_index_usage:recheck_reason:low_limit` 。
测试神奇的发发现，上面的查询limit有个分解值，会选择不同的索引：
（https://gist.github.com/seanlook/64990b956bf986eaeece5b26055f2f18  limit 8168后默认选择filesort的trace）
```
mysql> explain select f_some_id from d_ec_some1.t_tbl_test_time_08
where f_qiye_id=5077665 and f_type=9
and f_contact_time > '2017-10-17 14:23:49' and f_contact_time < '2017-10-17 14:23:53'
order by f_some_id limit 8167;
+----+-------------+-----------------------+-------+----------------+----------------+---------+------+--------+-------------+
| id | select_type | table                 | type  | possible_keys  | key            | key_len | ref  | rows   | Extra       |
+----+-------------+-----------------------+-------+----------------+----------------+---------+------+--------+-------------+
|  1 | SIMPLE      | t_tbl_test_time_08    | index | f_contact_time | some_qiye_type | 12      | NULL | 414115 | Using where |
+----+-------------+-----------------------+-------+----------------+----------------+---------+------+--------+-------------+
1 row in set
 
mysql> explain select f_some_id from d_ec_some1.t_tbl_test_time_08
where f_qiye_id=5077665 and f_type=9
and f_contact_time > '2017-10-17 14:23:49' and f_contact_time < '2017-10-17 14:23:53'
order by f_some_id limit 8168;
+----+-------------+-----------------------+-------+----------------+----------------+---------+------+--------+---------------------------------------------------------------+
| id | select_type | table                 | type  | possible_keys  | key            | key_len | ref  | rows   | Extra                                                         |
+----+-------------+-----------------------+-------+----------------+----------------+---------+------+--------+---------------------------------------------------------------+
|  1 | SIMPLE      | t_tbl_test_time_08    | range | f_contact_time | f_contact_time | 5       | NULL | 360478 | Using index condition; Using where; Using MRR; Using filesort |
+----+-------------+-----------------------+-------+----------------+----------------+---------+------+--------+---------------------------------------------------------------+
1 row in set
```

具体为啥这样，bug里面没说，只是提到5.7已修复，5.6应该不会修复。
 
# 5. 解决办法
其实做sql优化，执行计划不稳定这种，是不容易搞定的，因为并不是这个sql所有都会慢，而是不同值的特征，走不同的索引，会偶发性的慢。优化索引的时候，反而容易把原本较快的查询的索引改掉，造成更大的灾难。

本文的sql便是如此。从业务那边了解到，f_contact_time范围是固定4s，99%的情况，这个索引效率很高，但是正好有一大批数据(18万) f_contact_time='2017-10-17 14:23:51'，导致优化器做出了自己以为更优的决定。
 
那么解决这个问题，就是要去掉干扰因素，或者提供更优的选项给它。

1. 去掉干扰因素
  干扰它的索引是 some_qiye_type，是个唯一索引，因为恰好f_some_id开头，索引优化器想当然的用它来避免排序。
  去掉这个干扰因素就是调换 f_qiye_id,f_some_id的顺序。调换顺序还有个好处，有f_qiye_id等值条件，可以用在索引检索上。
  但是它的负面作用有两个：
  - 原本这个表上有 f_some_id 的等值、join ref以及分页查询，调换索引这两个字段顺序后，全都变成慢查询
  - f_qiye_id作为第一列，满足条件的值可能会有上百万，对这个查询的改观不大

2. 提供更优的索引
  添加索引 (f_qiye_id,f_contact_time) 看起来不错。这样一来，该类查询都会走这个索引

另外这个表上只有一个唯一索引，而且该唯一索引有字段允许null，所以没有主键。
加一个自增主键 f_id bigint unsigned not null
修改f_some_id字段为 f_some_id bigint unsigned NOT NULL
修改f_qiye_id字段为 f_qiye_id int unsigned NOT NULL
修改字段f_type字段为 tinyint NOT NULL
总之一句话：所有（作为索引的）字段，都定义为NOT NULL，f_some_id全部定义为bigint。最终表结构：

```
CREATE TABLE `t_tbl_test_time_16` (
  `f_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `f_some_id` bigint(20) unsigned NOT NULL,
  `f_qiye_id` int(11) unsigned NOT NULL DEFAULT '0',
  `f_type` tinyint(3) NOT NULL DEFAULT '0' COMMENT '有效联系类型 1: QQ联系，2:拨打电话，3:发送邮件，4:发送短信，5:添加跟进记录，6:拜访客户，7:EC联系，8:更新客户阶段',
  `f_contact_time` timestamp NOT NULL DEFAULT '1970-01-01 16:00:01',
  PRIMARY KEY(f_id),
  UNIQUE KEY `some_qiye_type` (`f_some_id`,`f_qiye_id`,`f_type`) USING BTREE,
  KEY `idx_qiye_time` (`f_qiye_id`,`f_contact_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

或者唯一索引变成联合主键（关于自增主键与联合主键的选择，参考 http://xgknight.com/2016/05/13/mysql-innodb-primary_key/ ）

```
CREATE TABLE `t_tbl_test_time_16` (
  `f_some_id` bigint(20) unsigned NOT NULL,
  `f_qiye_id` int(11) unsigned NOT NULL DEFAULT '0',
  `f_type` tinyint(3) NOT NULL DEFAULT '0' COMMENT '有效联系类型 1: QQ联系，2:拨打电话，3:发送邮件，4:发送短信，5:添加跟进记录，6:拜访客户，7:EC联系，8:更新客户阶段',
  `f_contact_time` timestamp NOT NULL DEFAULT '1970-01-01 16:00:01',
  PRIMARY KEY(`f_qiye_id`,`f_some_id`,`f_type`),
  KEY `idx_qiye_time` (`f_qiye_id`,`f_contact_time`),
  KEY `idx_some`(`f_some_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```


---

原文连接地址：http://xgknight.com/2017/10/26/mysql-bad-plan-order_by-limit/

---
