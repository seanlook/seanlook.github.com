---
title: 关于MySQL自增主键的几点问题（上）
date: 2017-02-16 16:32:49
aliases:
- /2017/02/16/mysql-autoincrement/
tags: [mysql, schema设计]
categories:
- MySQL
updated: 2017-02-16 16:32:49
---

前段时间遇到一个InnoDB表自增锁导致的问题，最近刚好有一个同行网友也问到自增锁的疑问，所以抽空系统的总结一下，这两个问题下篇会有阐述。

## 1. 划分三种插入类型
这里区分一下几种插入数据行的类型，便于后面描述：（纯逻辑上的划分）

1. "Simple inserts"  
简单插入，就是在处理sql语句的时候，能够提前预估到插入的行数，包括 `INSERT` / `REPLACE` 的单行、多行插入，但不含嵌套子查询以及 `INSERT ... ON DUPLICATE KEY UPDATE`。

2. "Bulk inserts"  
本文暂且叫做 大块插入，不能提前预知语句要插入的行数，也就无法知道分配多少个自增值，包括 `INSERT ... SELECT`, `REPLACE ... SELECT`, 以及 `LOAD DATA` 导入语句。InnoDB会每处理一行记录就为 AUTO_INCREMENT 列分配一个值。

3. "Mixed-mode inserts"  
混合插入，比如在 “简单插入” 多行记录的时候，有的新行有指定自增值，有的没有，所以获得最坏情况下需要插入的数量，然后一次性分配足够的auto_increment id。比如:
```
# c1 是 t1 的 AUTO_INCREMENT 列
INSERT INTO t1 (c1,c2) VALUES (1,'a'), (NULL,'b'), (5,'c'), (NULL,'d');
```

又比如 `INSERT ... ON DUPLICATE KEY UPDATE`，它在 update 阶段有可能分配新的自增id，也可能不会。


## 2. 三种自增模式：`innodb_autoinc_lock_mode`
在以 5.6 版本，自增id累加模式分为：
- ** 传统模式**  
  traditional，`innodb_autoinc_lock_mode = 0`  
  在具有 AUTO_INCREMENT 的表上，所有插入语句会获取一个特殊的表级锁 *AUTO-INC* ，这个表锁是在语句结束之后立即释放（无需等到事务结束），它可以保证在一个insert里面的多行记录连续递增，也能保证多个insert并发情况下自增值是连续的（不会有空洞）。

- ** 连续模式 **  
  consecutive，`innodb_autoinc_lock_mode = 1`  
  MySQL 5.1.22开始，InnoDB提供了一种轻量级互斥的自增实现机制，在内存中会有一个互斥量（mutex），每次分配自增长ID时，就通过估算插入的数量（前提是必须能够估算到插入的数量，否则还是使用传统模式），然后更新mutex，下一个线程过来时从新 mutex 开始继续计算，这样就能避免传统模式非要等待每个都插入之后才能获取下一个，把“锁”降级到 只在分配id的时候 锁定互斥量。  
  在 `innodb_autoinc_lock_mode = 1`（默认） 模式下，“简单插入”采用上面的 mutex 方式，“大块插入”（insert/replace ... select ... 、load data...）依旧采用 AUTO-INC 表级锁方式。当然如果一个事务里已经持有表 AUTO-INC 锁，那么后续的简单插入也需要等待这个 AUTO-INC 锁释放。这能够保证任意insert并发情况下自增值是连续的。
<!-- more -->
- ** 交叉模式 **  
  interleaved，`innodb_autoinc_lock_mode = 2`  
  该模式下所有 INSERT SQL 都不会有表级 AUTO-INC 锁，多个 **语句** 可以同时执行，所以在高并发插入场景下性能会好一些。但是当 binlog 采用 SBR 格式时，对于从库重放日志或者主库实例恢复时，并不可靠。  
  另者，它只能保证自增值在 insert语句级别 （单调）递增，所以多个insert可能会交叉着分配id，最终可能导致多个语句之间的id值不连续，这种情况出现在 混合插入：
  ```
  INSERT INTO t1 (c1,c2) VALUES (1,'a'), (NULL,'b'), (5,'c'), (NULL,'d');
  ```
  mutex 会按行分配4个id，但实际只用到2个，因此出现空洞。

## 3. 自增空洞（auto-increment sequence gap）

关于 AUTO_INCREMENT 自增出现空洞的问题，有必要再说明一下。
1. 在 0, 1, 2 三种任何模式下，如果事务回滚，那么里面获得自增值的sql回滚，但产生的自增值会一起丢失，不可能重新分配给其它insert语句。这也会产生空洞。

2. 在大块插入情景下
  - `innodb_autoinc_lock_mode`为 0 或 1 时，因为 AUTO-INC 锁会持续到语句结束，同一时间只有一个 语句 在表上执行，所以自增值是连续的（其它事务需要等待），不会有空洞；
  - `innodb_autoinc_lock_mode`为 2 时，两个 “大块插入” 之间可能会有空洞，因为每条语句事先无法预知精确的数量而导致分配过多的id，可能有空洞。

## 4. 混合插入对 AUTO_INCREMENT 的影响
混合插入在 innodb_autoinc_lock_mode 不同模式下会有对 表自增值有不同的表现。
```
CREATE TABLE t1 (
  c1 INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  c2 CHAR(1)
  ) ENGINE=INNODB;

ALTER TABLE t1 AUTO_INCREMENT 101;


mysql> SHOW CREATE TABLE t1\G
*************************** 1. row ***************************
       Table: t1
Create Table: CREATE TABLE `t1` (
  `c1` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `c2` char(1) DEFAULT NULL,
  PRIMARY KEY (`c1`)
) ENGINE=InnoDB AUTO_INCREMENT=101 DEFAULT CHARSET=utf8
```

### 1. mode 0

```
mysql> select @@innodb_autoinc_lock_mode;
+----------------------------+
| @@innodb_autoinc_lock_mode |
+----------------------------+
|                          0 |
+----------------------------+

mysql> INSERT INTO t1 (c1,c2) VALUES (1,'a'), (NULL,'b'), (5,'c'), (NULL,'d');
mysql> select * from t1;
+-----+------+
| c1  | c2   |
+-----+------+
|   1 | a    |
|   5 | c    |
| 101 | b    |
| 102 | d    |
+-----+------+

mysql> show create table t1\G
...
) ENGINE=InnoDB AUTO_INCREMENT=103 DEFAULT CHARSET=utf8
...
```

可以看到下一个自增值是 103 ，因为即使这是 ** 一条 ** insert语句（多行记录），自增值还是每次分配一个，不会在语句开始前一次分配全。

### 2. mode 1

```
mysql> truncate table t1; ALTER TABLE t1 AUTO_INCREMENT 101;  -- 复原
mysql> select @@innodb_autoinc_lock_mode;
+----------------------------+
| @@innodb_autoinc_lock_mode |
+----------------------------+
|                          1 |
+----------------------------+
1 row in set (0.00 sec)

mysql> INSERT INTO t1 (c1,c2) VALUES (1,'a'), (NULL,'b'), (5,'c'), (NULL,'d');
Query OK, 4 rows affected (0.00 sec)
Records: 4  Duplicates: 0  Warnings: 0

mysql> select * from t1;
+-----+------+
| c1  | c2   |
+-----+------+
|   1 | a    |
|   5 | c    |
| 101 | b    |
| 102 | d    |
+-----+------+

mysql> show create table t1\G
...
) ENGINE=InnoDB AUTO_INCREMENT=105 DEFAULT CHARSET=utf8
```

可以看到最终插入的值是一样的，但下一个自增值变成了 105，因为该模式下insert语句处理的时候，提前分配了 4 个自增值，但实际只有了两个。

注：如果你的insert自增列全都有带值，那么处理的时候是不会分配自增值的，经过下面这个实验，可以知道 ** 分配自增值，是在遇到第一个没有带自增列的行时，一次性分配的 ** ：
```
-- Tx1，先运行。 -- 插入第2行的时候 sleep 5s
INSERT INTO t1 (c1,c2) VALUES (2,'e'),(sleep(5)+6,'g'),(NULL,'f'), (NULL,'h');

-- Tx2，后运行。 -- 第一行没有给自增列值，马上分配 4 个
INSERT INTO t1 (c1,c2) VALUES  (NULL,'b'), (1,'a'), (sleep(5)+5,'c'), (NULL,'d');

-- 得到的结果是
+-----+------+
| c1  | c2   |
+-----+------+
|   1 | a    |
|   2 | e    |
|   5 | c    |
|   6 | g    |
| 101 | b    |
| 102 | d    |
| 105 | f    |
| 106 | h    |
+-----+------+
```

### 3. mode 2

```
mysql> truncate table t1; ALTER TABLE t1 AUTO_INCREMENT 101;  -- 复原
mysql> select @@innodb_autoinc_lock_mode;
+----------------------------+
| @@innodb_autoinc_lock_mode |
+----------------------------+
|                          2 |
+----------------------------+

mysql> INSERT INTO t1 (c1,c2) VALUES (1,'a'), (NULL,'b'), (5,'c'), (NULL,'d');
mysql> select * from t1;
+-----+------+
| c1  | c2   |
+-----+------+
|   1 | a    |
|   5 | c    |
| 101 | b    |
| 102 | d    |
+-----+------+

mysql> show create table t1\G
...
) ENGINE=InnoDB AUTO_INCREMENT=105 DEFAULT CHARSET=utf8
```
结果看起来与 连续模式 一样，其实不然！该模式下，如果另外一个 大块插入 并发执行时，可能会出现以下现象：
  1. 大块插入的的自增值有间断
  2. 其它并发执行的事务插入出现 duplicate-key error

```
第1点 (create t2 select * from t1)
Tx1: insert into t1(c2) select c2 from t2；  -- 先执行
Tx2: INSERT INTO t1 (c1,c2) VALUES (1,'a'), (NULL,'b'), (5,'c'), (NULL,'d');  -- 后 并发执行

在交叉模式下，Tx1事务插入的数据行会与 Tx1 交叉出现。
注：如果 Tx1 改成 insert into t1 select * from t2 ，那么 Tx2 执行极有可能会报 duplicate-key error，与下面第2点所说的重复键是不一样的

第2点
mysql> truncate table t1; ALTER TABLE t1 AUTO_INCREMENT 5;  -- 复原
mysql> INSERT INTO t1 (c1,c2) VALUES (1,'a'), (NULL,'b'), (5,'c'), (NULL,'d');
ERROR 1062 (23000): Duplicate entry '5' for key 'PRIMARY'
```

## 总结
上面说了这么多，那么自增模式到底该怎么选择呢？其实很简单，目前数据库默认的 consecutive 即 `innodb_autoinc_lock_mode=1` 就是最好的模式，一般业务生产库不会有 `insert into ... select ...`或者 load data infile 这样的维护动作。（提示：即使晚上有数据迁移任务，也不要通过这样的形式进行）

`innodb_autoinc_lock_mode=2` 可以提高获取表自增id的并发能力（性能），但是除非出现上面演示的 duplicate-key 特殊用法情形，不会像网上所说的获取到相同key导致重复的问题。但是如果binlog在 RBR 格式下不建议使用，可能出现主从数据不一致。还有就是能够容忍gap的存在，以及多个语句insert的自增值交叉。


参考： https://dev.mysql.com/doc/refman/5.6/en/innodb-auto-increment-handling.html

下篇分析遇到过的 MySQL 自增主键相关的具体问题。

---

本文链接地址：http://xgknight.com/2017/02/16/mysql-autoincrement/

---
