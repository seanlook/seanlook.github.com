---
title: MySQL分页优化
date: 2018-03-21 16:32:49
aliases:
- /2018/03/21/mysql-pagination-no-offset/
tags: [mysql, 分页]
categories: 
- MySQL
updated: 2018-03-21 16:32:49
---


关于数据库分页查询的话题，网上谈论的很多，但开发人员在使用上还是习惯以往的思路。

比如我们有个电话记录表：

```
CREATE TABLE `t_tel_record` (
  `f_id` bigint(20) unsigned NOT NULL DEFAULT '0' COMMENT '流水号',
  `f_qiye_id` bigint(20) NOT NULL DEFAULT '0' COMMENT '企业',
  `f_callno` varchar(20) DEFAULT NULL COMMENT '主叫号码',
  `f_calltono` varchar(30) DEFAULT NULL COMMENT '被叫号码',
  `f_Starttime` datetime NOT NULL COMMENT '开始时间',
  `f_Endtime` datetime DEFAULT NULL COMMENT '结束时间',
  `f_Calltime` mediumint(8) unsigned NOT NULL DEFAULT '0' COMMENT '通话时间',
  `f_user_id` bigint(20) NOT NULL COMMENT '员工用户',
  `f_path` varchar(200) DEFAULT NULL COMMENT '语音文件路径',
  `f_crm_id` bigint(20) NOT NULL DEFAULT '0' COMMENT '客户库id',
  `f_call_type` tinyint(4) unsigned NOT NULL DEFAULT '0' COMMENT '0:未知，1:为呼入类型，2:呼出类型',
  PRIMARY KEY (`f_id`),
  KEY `idx_endtime_userid` (`f_Endtime`,`f_user_id`,`f_qiye_id`),
  KEY `idx_crmid` (`f_crm_id`),
  KEY `idx_qiye_user_calltime` (`f_qiye_id`,`f_Starttime`),
  KEY `idx_calltono` (`f_calltono`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

```
查询第1页的数据：
 SELECT * FROM t_tel_record
 WHERE f_qiye_id=xxx
 ORDER BY f_Starttime DESC
 LIMIT 0,100
 
 
当数据量很大，需要查询第10000页的数据：
 SELECT * FROM t_tel_record
 WHERE f_qiye_id=xxx
 ORDER BY f_Starttime DESC
 LIMIT 999900,100  -- 或者 OFFSET 999900 LIMIT 100
```

MySQL的 limit m,n 工作原理就是先读取符合where条件的前面m+n条记录，然后抛弃前m条，返回后面n条，所以m越大，偏移量越大，性能就越差。这也是大部分ORM框架生成的分页sql。

还有数据不准确的问题产生。

![](http://github.com/seanlook/sean-notes-comment/raw/main/static/15223856466570.jpg)


要优化这类sql大抵有三种方法：

1. 利用索引来排序
2. 利用覆盖索引避免回表
3. 想办法去掉大offset

## 利用索引来排序
这是写sql的基础的优化手段，利用二级索引的有序性，避免filesort。考虑索引 `KEY a_b_c (a, b, c)` :

```
ORDER may get resolved using Index
    – ORDER BY a
    – ORDER BY a,b
    – ORDER BY a, b, c
    – ORDER BY a DESC, b DESC, c DESC
     
WHERE and ORDER both resolved using index:
    – WHERE a = const ORDER BY b, c
    – WHERE a = const AND b = const ORDER BY c
    – WHERE a = const ORDER BY b, c
    – WHERE a = const AND b > const ORDER BY b, c
 
ORDER will not get resolved uisng index (file sort)
    – ORDER BY a ASC, b DESC, c DESC /* mixed sort direction */
    – WHERE g = const ORDER BY b, c /* a prefix is missing */
    – WHERE a = const ORDER BY c /* b is missing */
    – WHERE a = const ORDER BY a, d /* d is not part of index */
```

当然不是说利用索引排序性能就一定好，由于MySQL优化器的局限性，也会出现选择选择糟糕的index scan执行计划，见 [MySQL order by limit 走错索引(range->indexscan)](http://xgknight.com/2017/10/26/mysql-bad-plan-order_by-limit/) ，using filesort也有可能比 index scan 要快。

<!-- more -->

## 利用覆盖索引避免回表

我们先来理解一下回表的概念：

1. MySQL是一个B+Tree结构的聚集索引组织表
2. 每一行记录都有个rowid，要么是主键，要么是非空唯一索引，要么是内部分配的ROWID
3. 二级索引是在表的一个或多个字段联合起来，创建的用于快速检索数据行的“字典”，这个有序的字典结构也是B+Tree
4. 每个二级索引元组的结构后面，都会自带存储相应行记录的rowid，以便定位数据物理位置
5. 如果一个查询采用的索引上，包含了 select 之后所需要返回的列，那么MySQL可直接从索引上返回数据；如果select 要返回的字段只要有一行没在索引中，则需要根据索引对应的rowid，进行回表获取数据。这部分数据有可能在内存，也有可能在磁盘。

当然实际情况要比上面的复杂，比如MySQL内部有ICP和MRR、BKA优化访问的手段，覆盖索引也就不需要使用了。

如果你的分页SQL where条件和select返回列刚好都在同一个索引上，那在这一部分讲的方法没什么好优化的了。由此也应该可以得到启发，** select只返回需要的行，不要返回多余的行，禁止select \* **，这些开发规范都是有依据的。


利用Covering index优化分页的方法，先用一个子查询把符合条件主键id集合查出来，然后与原表join取出其它列：

```
SELECT * FROM
 t_tel_record t1
INNER JOIN (
 SELECT f_id
 FROM t_tel_record
 WHERE f_qiye_id = xxx
 ORDER BY f_id DESC
 LIMIT 999900, 100
) t2 ON t1.f_id = t2.f_id
```

子查询部分利用覆盖索引只返回主键(rowid)，但不是每次都有好运气，原where条件放到子查询就能很快，毕竟它还是需要过滤999900条数据。

上面的sql还出现了它的一个变种：

```
min_id = SELECT f_id
FROM t_tel_record
WHERE f_qiye_id = xxx
ORDER BY f_id DESC
LIMIT 999900, 1
 
 
SELECT * FROM
  t_tel_record t1
WHERE f_qiye_id = xxx
AND f_id < {min_id} + 1
ORDER BY f_id DESC
LIMIT 100
```

第一条语句利用覆盖索引获取到该页最小id(如果是升序就是最大id)

第二条语句利用主键和其它过滤条件，获取该页数据。

上面两种方式都有一定的优化效果，具体还是要看业务本身的复杂度。

## 无offset翻页
上面的变种已经提供了一个很好的思路：

* 程序端或者客户端，保留当前页的最小id、最大id（id是主键），这并不是什么难事
* 降序情况下，每次提取下一页的数据时，f_id < min_id order by f_id desc limit 100;  上一页 f_id > max_id order by f_id desc limit 100

```
第一页：（降序）
SELECT * FROM t_tel_record t1
WHERE f_qiye_id = xxx
ORDER BY f_id DESC LIMIT 100
 
 
获取结果集最大最小id：一般是第一条和最后一条，或者 max_id=max(f_id), min_id=min(f_id)
下一页（如果有）：
SELECT * FROM t_tel_record t1
WHERE f_qiye_id = xxx
AND f_id < {min_id}  -- min_id变量
ORDER BY f_id DESC LIMIT 100
 
 
上一页（如果有）：
SELECT * FROM t_tel_record t1
WHERE f_qiye_id = xxx
AND f_id > {max_id}  -- max_id变量
ORDER BY f_id DESC LIMIT 100
```

没有第几页之说，更不存在【跳转x页】这种深度分页，只有【上一页】【下一页】，所以用户体验上有差别。这种分页方式，使用f_id过滤数据，而f_id是主键，速度是很快的，性能不会随着页数的增大而变慢。

## 反转分页
降序分页的时候，如果用户直接点击最后一页，或者上面的第10000页实际就是倒数第2页，那就没有必要取这么大的offset，转换成升序，性能就与正向前几页效率一样高了。

如下图所示，很容易理解。

![](http://github.com/seanlook/sean-notes-comment/raw/main/static/15223859031285.jpg)


在几万页的情况下翻到最后一页，用户不太关心最后一页是100条还是99条：

```
最后一页：（降序）
SELECT * FROM (
  SELECT * FROM t_tel_record t1
  WHERE f_qiye_id = xxx
  ORDER BY f_id ASC LIMIT 100) AS t
ORDER BY f_id DESC
 
 
倒数第二页：(以此类推)
SELECT * FROM (
  SELECT * FROM t_tel_record t1
  WHERE f_qiye_id = xxx
  ORDER BY f_id ASC LIMIT 100, 100) AS t
ORDER BY f_id DESC
```

分页不存在大一统的绝对优化方法，有时候需要产品层面来回避技术难题，比如前5页显示页号，便于跳页，实现上用offset；大于5页只能上下翻页，实现上用无offset方法；最后几页使用反转翻页实现：

![](http://github.com/seanlook/sean-notes-comment/raw/main/static/15223859322454.jpg)

包括前面所有优化方法，都没有提供 记录总数 这样的显示，大数据量count对MySQL来说实在不擅长。即使是Google搜索引擎也只提供 **约xx条结果** 。

抛开数据量谈实现，也就太天真的。


## 不精确分页
其实再想想 order by  xxx limit m,n 场景：

1. 展示列表或搜索结果
2. 内部统计或者导出业务

第2种场景，比如扫描一组数据或者全部数据，业务批量导出数据，并不是严格的分页，换句话讲，开发的目的是将数据分批取出，每批的数据量是不是一样并不重要，甚至顺序也不重要，而在批量取数据的实现反而引入了两个可能限制性能的条件。

比如有个扫描全表统计数据的功能，范围、等值条件比较复杂，无法很好的使用索引（比如范围搜索可能会使索引其它列失效）。下面直接按 f_Starttime 每5分钟切片，可以较好的利用(f_qiye_id,f_Starttime)索引

```
SELECT * FROM t_tel_record
WHERE f_Starttime >= '2018-03-16 08:00:01' AND f_Starttime < '2018-03-16 08:05:01'
ORDER BY f_Starttime DESC
```

# 分页优化陷阱

## order by id 与 order by f_Starttime
按照主键与按照二级索引排序，它们对优化器的影响是非常大的。

1. 在order by 主键时，MySQL优化器很“喜欢”直接用主键，而放弃where条件可能具有更好过滤效果（但有filesort）的执行计划。
2. 在order by 二级索引的某个字段时，MySQL优化器表现比较正常，虽然遇到where条件的范围索引容易失去索引排序，但好歹有可能采用覆盖索引。

正因为第1点的影响，所有再某些分页sql优化时，可考虑 order by id 改成具有接近排序效果的其它字段，比如id是自增，时间字段也是增长。

## 第一页和最后一页非常慢
考虑下面两个sql: （都采用上面的 f_id > max_id 的优化方法）

sql1:

```
- f_Starttime上没有可用索引
SELECT f_qiye_id,f_id,f_money,f_type,f_callno,f_calltono,f_Starttime,f_Endtime, f_Calltime,f_status, f_num,f_result,f_time,f_user_id,f_is400,f_crm_log,f_code, f_path,f_crm_id,f_telbox_id,f_mp3_len, f_in_out_type, f_call_type FROM d_ec_telecom7.t_tel_record_201710
WHERE f_id > 0
  and (f_Starttime>='2017-10-25 00:00:00' and f_Starttime<='2017-10-26 00:00:00') ORDER BY f_id ASC LIMIT 1000
```

sql2:

```
SELECT f_log_id,f_crm_id,f_user_id,f_qiye_id,f_creat_time,f_send_time,f_end_time,f_do_type, f_static_time,f_go_web,f_type,f_contact_num,f_share,f_record_type,f_provice,f_city,f_is_addclient, f_is_customer,f_ontime_flag,f_msg_type,f_id,f_style,f_operate_type,f_from,f_sendmsg FROM d_ec_contact.t_crm_contact_at201708
WHERE f_log_id > 3815923707
  and (f_creat_time>='2017-08-01 00:00:00' and f_creat_time<='2017-08-02 00:00:00') ORDER BY f_log_id ASC LIMIT 1000
```

都是导出性质的sql，开发反应每当扫描开始的第一页（如sql1）和最后一页（如sql2），都变的贼慢，然而中间页的数据拉取都在几十毫秒级别。

我们分析一下sql1慢的原因

* f_Starttime上没有索引，执行计划如下：
* f_id是个全局id，单调递增。应该说与f_Starttime是保持相同的趋势增长的，因为正是这样决定了中间页都较快
* 仔细观察f_Starttime条件，是从10月份表中获取 10.25 日全天数据。执行计划几乎就是根据主键全表扫描，因为f_id>0的条件需要扫描10.1，10.2，... 10.24，之后终于在10.25的第一个f_id找到，通过where条件过滤。可想而知有多慢
* 第一页取出后，拿f_id的最大值，去取第二页，因为f_id与f_Starttime是保持相同趋势增长，所以扫过的所有记录都满足where条件，很快返回（另外主键扫描是顺序IO，取1000是很快的）
* 最后一页也是同样，当最后一页不满1000条时，f_id已经超出f_Starttime范围右边了，后面虽然已经没有满足f_Starttime条件的记录，但根据主键还是要一扫到底。
  （要判断行数是否小于1000，如果不判断还会拿最后一页的最大值去查询，返回结果0，无谓的耗时）


优化第一页和优化最后一页的方法其实是类似的。第一页在f_Starttime无索引的情况下，无论如何都是很难提高效率的，除非你用专门的一段代码去猜f_id的起始值。我们这个例子还特殊点，f_id的组成是 timestamp + incr_1 ，根据f_Starttime范围直接就得到 f_id 的近似值作为下界。

同理，最后一页根据f_Starttime得到最大值，转换为 timestamp × 1000000000 + 99999 作为上界。

sql2慢的原因有点不一样：

* f_creat_time上是有一个索引 (f_creat_time,f_operate_type) 的，看一下它的执行计划：
* 像本文前面说的，一个范围条件，再 order by 主键，优化器选择了主键扫描，而非范围扫描再filesort （一天数据量约320万）

优化办法：
* 比如去7月份表查个最大值
* ...use index(idx_creattime) ... order by f_creat_time ASC

关于分页优化，具体问题具体分析。


** 参考 **

* https://mariadb.com/kb/en/library/pagination-optimization/
* http://www.cnblogs.com/wy123/p/7003157.html
* https://blog.jamespan.me/2015/01/22/trick-of-paging-query


---

本文链接地址：http://xgknight.com/2018/03/21/mysql-pagination-no-offset/

---
