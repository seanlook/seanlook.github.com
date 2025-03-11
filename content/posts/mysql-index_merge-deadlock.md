---
title: index merge 引起的死锁分析
date: 2017-03-11 16:32:49
tags: [mysql, mysql优化]
categories:
- MySQL
updated: 2017-03-11 16:32:49
---


在看线上一个 MySQL innodb status 时，发现有死锁信息，而且出现的频率还不低。于是分析了一下，把过程记录下来。

## 1. 概要

表结构脱敏处理：
```
CREATE TABLE t_mytb1 (
  f_id int(11) unsigned NOT NULL AUTO_INCREMENT,
  f_fid int(11) unsigned NOT NULL DEFAULT '0',
  f_sid int(11) unsigned NOT NULL DEFAULT '0',
  f_mode varchar(32) NOT NULL DEFAULT '',
  f_read int(11) unsigned NOT NULL DEFAULT '0',
  f_xxx1 int(11) unsigned NOT NULL DEFAULT '0',
  f_xxx2 int(11) unsigned NOT NULL DEFAULT '0',
  f_wx_zone int(11) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (f_id),
  KEY idx_sid (f_sid),
  KEY idx_fid (f_fid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

死锁信息：
```
LATEST DETECTED DEADLOCK
------------------------
2017-02-28 13:58:29 7f25a3efd700
*** (1) TRANSACTION:
TRANSACTION 4907718431, ACTIVE 0.010 sec fetching rows
mysql tables in use 3, locked 3
LOCK WAIT 154 lock struct(s), heap size 30248, 10 row lock(s)
LOCK BLOCKING MySQL thread id: 13589250 block 13589247
MySQL thread id 13589247, OS thread handle 0x7f25a17e3700, query id 27061926722 11.xx.52.xx ecweb Searching rows for update
UPDATE `d_db1`.`t_mytb1` SET `f_read` = f_read+1 WHERE (f_fid=91243) AND (f_sid=100) AND (f_mode='浏览器')
*** (1) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 13288 page no 375 n bits 352 index `PRIMARY` of table `d_db1`.`t_mytb1` trx id 4907718431 lock_mode X locks rec but not gap waiting
Record lock, heap no 245 PHYSICAL RECORD: n_fields 10; compact format; info bits 0
 0: len 4; hex 0000a63b; asc    ;;;
 1: len 6; hex 0001246304a7; asc   $c  ;;
 2: len 7; hex 7f000ac0162428; asc      $(;;
 3: len 4; hex 00016470; asc   dp;;
 4: len 4; hex 00000064; asc    d;;
 5: len 9; hex e6b58fe8a788e599a8; asc          ;;
 6: len 4; hex 0000244f; asc   $O;;
 7: len 4; hex 0000007c; asc    |;;
 8: len 4; hex 00000000; asc     ;;
 9: len 4; hex 00000000; asc     ;;

*** (2) TRANSACTION:
TRANSACTION 4907718435, ACTIVE 0.007 sec fetching rows
mysql tables in use 3, locked 3
154 lock struct(s), heap size 30248, 3 row lock(s)
MySQL thread id 13589250, OS thread handle 0x7f25a3efd700, query id 27061926757 11.xx.104.xxx ecweb Searching rows for update
UPDATE `d_db1`.`t_mytb1` SET `f_read` = f_read+1 WHERE (f_fid=91248) AND (f_sid=100) AND (f_mode='浏览器')
*** (2) HOLDS THE LOCK(S):
RECORD LOCKS space id 13288 page no 375 n bits 352 index `PRIMARY` of table `d_db1`.`t_mytb1` trx id 4907718435 lock_mode X locks rec but not gap
Record lock, heap no 245 PHYSICAL RECORD: n_fields 10; compact format; info bits 0
 0: len 4; hex 0000a63b; asc    ;;;  -- 42555
 1: len 6; hex 0001246304a7; asc   $c  ;;  -- 4905436327
 2: len 7; hex 7f000ac0162428; asc      $(;;
 3: len 4; hex 00016470; asc   dp;;  -- 91248
 4: len 4; hex 00000064; asc    d;;  -- 100
 5: len 9; hex e6b58fe8a788e599a8; asc          ;;
 6: len 4; hex 0000244f; asc   $O;;  -- 9295
 7: len 4; hex 0000007c; asc    |;;  -- 124
 8: len 4; hex 00000000; asc     ;;
 9: len 4; hex 00000000; asc     ;;

*** (2) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 13288 page no 202 n bits 1272 index `idx_sid` of table `d_db1`.`t_mytb1` trx id 4907718435 lock_mode X locks rec but not gap waiting
Record lock, heap no 705 PHYSICAL RECORD: n_fields 2; compact format; info bits 0
 0: len 4; hex 00000064; asc    d;;  -- 100
 1: len 4; hex 0000a633; asc    3;;  -- 42547

*** WE ROLL BACK TRANSACTION (2)
```

乍一看很奇怪，tx1和tx2 两个 UPDATE 各自以 f_fid 为条件更新的记录互不影响才对，即使 91243，91248 两个值有可能出现在同一条数据上（因为f_fid上是二级索引），那顶多也就是个更新锁等待，谁后来谁等待，怎么会出现互相争用对方已持有的锁，被死锁检测机制捕获？

当然,把 update 语句拿到数据库中 EXPLAIN 一下就可以看出端倪。这里不妨先分析一下输出的锁情况：


**先看 Tx2 (对应trx id 4907718435)** :  
1. `RECORD LOCKS space id 13288 page no 375 n bits 352` 告诉我们是表空间id 13288 (可从 `information_schema.INNODB_SYS_DATAFILES` 查到对应ibd文件) 即 t_mytb1 表，第 375 号页面的 245 位置的记录被锁，并且是 idx PRIMARY 上的记录锁（注：本实例隔离级别为RC）。 Tx2正持有这把记录锁。
因为是聚集索引，显示了完整记录
```
0: 主键f_id=42555
1: DB_TRX_ID = 4905436327
2: DB_ROLL_PTR指向undo记录的地址
3: f_fid=91248
4: f_sid=100
   ...
```
2. 然而Tx2还在等待一个记录锁（lock_mode X locks rec but not gap waiting），但这把锁来自二级索引 `idx_sid` 索引上的记录锁。在 RC 级别下没有GAP lock，行锁除了加在符合条件的二级索引 f_sid=100 上外，还会对主键加record lock。
二级索引值：
<!--more-->
```
0: f_sid=100
1: 主键f_id=42547
```
明显它们是两条不同的记录。

**再看 Tx1（对应trx id 4907718431）**  
Tx1 事务等待的锁，就是上面 Tx2 已持有的记录锁 f_id=42555 。但是由于输出的关系，没有看到它持有的锁。既然这里出现死锁，可以推断，Tx1执行update时，已获得 f_id=42547 的记录锁，这样才导致死锁，否则的话只会出现一方等待。示意图如下：

![][1]

InnoDB最终选择回滚 Tx2 是可以理解的 —— 它只获得了一个记录锁，资源占用最少。目前还无法解释的是关于锁数量这一部分：
```
mysql tables in use 3, locked 3
154 lock struct(s), heap size 30248, 3 row lock(s)
```

## 2. 死锁产生的原因 —— index merge
上面任何一个 update 的explain结果：
![][2]

可以看到 EXTRA 列 `Using intersect(idx_sid, idx_fid)`。

索引合并是 5.0 就引入的一种优化手段，意指在查询语句里，可以在一个表上使用多个索引，同时扫描，最后进行结果合并。上面的例子里，条件 `f_fid=xxx and f_sid=xxx`，因为表上有 *f_fid* 和 *f_sid* 两个单列索引，优化器在成本模型里进行估算，认为一边使用 f_fid=91243 索引扫描，一边使用 f_sid=100 索引扫描，然后对两个结果集取交集，会更快。结果在高并发更新情况下：

- Tx2通过 f_fid 索引锁住了记录 42555，欲通过 f_sid 锁定另一条记录 42547
- Tx1 已通过 f_sid 锁定 42547，欲通过 f_fid 锁住记录42555
- 死锁发生

### 关于索引合并
intersection 只是 索引合并中的一种，还有 union, sort_union 。可以用到  index_merge 是有比较苛刻的条件。
1. 首先是 Range 优先(>5.6.7)。比如 key1=1 or (key1=2 and key2=3)，其中key1是可以转化成 range scan 的，不会使用 index merge union
2. 其次，Intersect和Union要符合 ROR，即 Rowid-Ordered-Retrival：
> Intersect和Union都需要使用的索引是ROR的，也就时ROWID ORDERED，即针对不同的索引扫描出来的数据必须是同时按照ROWID排序的，这里的 ROWID其实也就是InnoDB的主键(如果不定义主键，InnoDB会隐式添加ROWID列作为主键)。只有每个索引是ROR的，才能进行归并排序，你懂的。 当然你可能会有疑惑，查不记录后内部进行一次sort不一样么，何必必须要ROR呢，不错，所以有了SORT-UNION。SORT-UNION就是每个非ROR的索引 排序后再进行Merge
>  -- 来自 http://www.cnblogs.com/nocode/archive/2013/01/28/2880654.html

像 *key1=v1 or key2=v2* ， key1与key2是单列索引，并且无其它索引可用，就有可能看到 Using Union(xx,xxx) 。更多内容可见参考链接。


## 3. 解决 —— 加联合索引
解决这个死锁可能你也想到了，添加联合索引 `idx_fid_sid(f_fid, f_sid)`，这样一来查询会选择这一个索引，至于 idx_sid 这个单列索引还需不需要，看业务场景。

另外，如果懂点业务的话，会发现这个更新之所以这么频繁，实际上是一个阅读量计数的功能，放到redis里可极大的提高并发能力，定时持久化到mysql表。

最后提一句 index_merge 是有选项可以关闭的：
```
mysql> select @@optimizer_switch;
index_merge=on,index_merge_union=on,index_merge_sort_union=on,index_merge_intersection=on ...
```

如果优化器选择了index_merge，一般是索引没建好，我看不让它使用比较更好。

** 参考文章 **  
1. [MySQL优化器：index merge介绍](http://www.orczhou.com/index.php/2013/01/mysql-source-code-query-optimization-index-merge/)
2. [MySQL update use index merge(Using intersect) increase chances for deadlock](http://hidba.org/?p=1065)
3. https://dev.mysql.com/doc/refman/5.6/en/index-merge-optimization.html


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-secondary-index-merge.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-index_merge-deadlock.png


  ---

  原文链接地址：http://xgknight.com/2017/03/11/mysql-index_merge-deadlock/

  ---
