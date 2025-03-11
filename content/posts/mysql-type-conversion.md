---
title: 小心MySQL的隐式类型转换陷阱
date: 2016-05-05 16:32:49
tags: [mysql, schema设计]
categories: 
- MySQL
updated: 2016-05-05 16:32:49
---


## 1. 隐式类型转换实例

今天生产库上突然出现MySQL线程数告警，IOPS很高，实例会话里面出现许多类似下面的sql：(修改了相关字段和值)
  
```
SELECT f_col3_id,f_qq1_id FROM d_dbname.t_tb1 WHERE f_col1_id=1226391 and f_col2_id=1244378 and 
f_qq1_id in (12345,23456,34567,45678,56789,67890,78901,89012,90123,901231,901232,901233)
```

用 explain 看了下扫描行数和索引选择情况： 

```
mysql>explain SELECT f_col3_id,f_qq1_id FROM d_dbname.t_tb1 WHERE f_col1_id=1226391 
and f_col2_id=1244378 and f_qq1_id in (12345,23456,34567,45678,56789,67890,78901,89012,90123,901231,901232,901233);
+------+---------------+---------+--------+--------------------------------+---------------+------------+--------+--------+------------------------------------+
| id   | select_type   | table   | type   | possible_keys                  | key           | key_len    | ref    | rows   | Extra                              |
+------+---------------+---------+--------+--------------------------------+---------------+------------+--------+--------+------------------------------------+
| 1    | SIMPLE        | t_tb1   | ref    | uid_type_frid,idx_corpid_qq1id | uid_type_frid | 8          | const  | 1386   | Using index condition; Using where |
+------+---------------+---------+--------+--------------------------------+---------------+------------+--------+--------+------------------------------------+
共返回 1 行记录,花费 11.52 ms.
```

t_tb1 表上有个索引`uid_type_frid(f_col2_id,f_type)`、`idx_corp_id_qq1id(f_col1_id,f_qq1_id)`，而且如果选择后者时，f_qq1_id的过滤效果应该很佳，但却选择了前者。当使用 hint `use index(idx_corp_id_qq1id)`时：
<!-- more -->
```
mysql>explain extended SELECT f_col3_id,f_qq1_id FROM d_dbname.t_tb1  use index(idx_corpid_qq1id) WHERE f_col1_id=1226391 and f_col2_id=1244378 and f_qq1_id in (12345,23456,34567,45678,56789,67890,78901,89012,90123,901231,901232,901233);
+------+---------------+--------+--------+---------------------+------------------+------------+----------+-------------+------------------------------------+
| id   | select_type   | table  | type   | possible_keys       | key              | key_len    | ref      | rows        | Extra                              |
+------+---------------+--------+--------+---------------------+------------------+------------+----------+-------------+------------------------------------+
| 1    | SIMPLE        | t_tb1  | ref    | idx_corpid_qq1id    | idx_corpid_qq1id | 8          | const    | 2375752     | Using index condition; Using where |
+---- -+---------------+--------+--------+---------------------+------------------+------------+----------+-------------+------------------------------------+
共返回 1 行记录,花费 17.48 ms.

mysql>show warnings;
+-----------------+----------------+-----------------------------------------------------------------------------------------------------------------------+
| Level           | Code           | Message                                                                                                               |
+-----------------+----------------+-----------------------------------------------------------------------------------------------------------------------+
| Warning         |           1739 | Cannot use range access on index 'idx_corpid_qq1id' due to type or collation conversion on field 'f_qq1_id'           |
| Note            |           1003 | /* select#1 */ select `d_dbname`.`t_tb1`.`f_col3_id` AS `f_col3_id`,`d_dbname`.`t_tb1`.`f_qq1_id` AS `f_qq1_id` from `d_dbname`.`t_tb1` USE INDEX (`idx_corpid_qq1id`) where |
|                 |                |  ((`d_dbname`.`t_tb1`.`f_col2_id` = 1244378) and (`d_dbname`.`t_tb1`.`f_col1_id` = 1226391) and (`d_dbname`.`t_tb1`.`f_qq1_id` in |
|                 |                | (12345,23456,34567,45678,56789,67890,78901,89012,90123,901231,901232,901233)))                                        |
+-----------------+----------------+-----------------------------------------------------------------------------------------------------------------------+
共返回 2 行记录,花费 10.81 ms.
```

rows列达到200w行，但问题也发现了：select_type应该是 range 才对，key_len看出来只用到了`idx_corpid_qq1id`索引的第一列。上面explain使用了 `extended`，所以`show warnings;`可以很明确的看到 f_qq1_id 出现了隐式类型转换：f_qq1_id是varchar，而后面的比较值是整型。

解决该问题就是避免出现隐式类型转换(implicit type conversion)带来的不可控：把f_qq1_id in的内容写成字符串：

```
mysql>explain SELECT f_col3_id,f_qq1_id FROM d_dbname.t_tb1 WHERE f_col1_id=1226391 and f_col2_id=1244378 and 
f_qq1_id in ('12345','23456','34567','45678','56789','67890','78901','89012','90123','901231');
+-------+---------------+--------+---------+--------------------------------+------------------+-------------+---------+---------+------------------------------------+
| id    | select_type   | table  | type    | possible_keys                  | key              | key_len     | ref     | rows    | Extra                              |
+-------+---------------+--------+---------+--------------------------------+------------------+-------------+---------+---------+------------------------------------+
| 1     | SIMPLE        | t_tb1  | range   | uid_type_frid,idx_corpid_qq1id | idx_corpid_qq1id | 70          |         | 40      | Using index condition; Using where |
+-------+---------------+--------+---------+--------------------------------+------------------+-------------+---------+---------+------------------------------------+
共返回 1 行记录,花费 12.41 ms.
```

扫描行数从1386减少为40。

类似的还出现过一例：

```
SELECT count(0)  FROM d_dbname.t_tb2 where f_col1_id= '1931231'  AND f_phone in(098890);

| Warning | 1292 | Truncated incorrect DOUBLE value: '1512-98464356'
```

优化后直接从扫描rows 100w行降为1。

借这个机会，系统的来看一下mysql中的隐式类型转换。

## 2. mysql隐式转换规则

### 2.1 规则
下面来分析一下[隐式转换的规则](http://dev.mysql.com/doc/refman/5.7/en/type-conversion.html)：

> a. 两个参数至少有一个是 NULL 时，比较的结果也是 NULL，例外是使用 <=> 对两个 NULL 做比较时会返回 1，这两种情况都不需要做类型转换
b. 两个参数都是字符串，会按照字符串来比较，不做类型转换
c. 两个参数都是整数，按照整数来比较，不做类型转换
d. 十六进制的值和非数字做比较时，会被当做二进制串
e. 有一个参数是 TIMESTAMP 或 DATETIME，并且另外一个参数是常量，常量会被转换为 timestamp
f. 有一个参数是 decimal 类型，如果另外一个参数是 decimal 或者整数，会将整数转换为 decimal 后进行比较，如果另外一个参数是浮点数，则会把 decimal 转换为浮点数进行比较
g. 所有其他情况下，两个参数都会被转换为浮点数再进行比较


```
mysql> select 11 + '11', 11 + 'aa', 'a1' + 'bb', 11 + '0.01a';  
+-----------+-----------+-------------+--------------+
| 11 + '11' | 11 + 'aa' | 'a1' + 'bb' | 11 + '0.01a' |
+-----------+-----------+-------------+--------------+
|        22 |        11 |           0 |        11.01 |
+-----------+-----------+-------------+--------------+
1 row in set, 4 warnings (0.00 sec)

mysql> show warnings;
+---------+------+-------------------------------------------+
| Level   | Code | Message                                   |
+---------+------+-------------------------------------------+
| Warning | 1292 | Truncated incorrect DOUBLE value: 'aa'    |
| Warning | 1292 | Truncated incorrect DOUBLE value: 'a1'    |
| Warning | 1292 | Truncated incorrect DOUBLE value: 'bb'    |
| Warning | 1292 | Truncated incorrect DOUBLE value: '0.01a' |
+---------+------+-------------------------------------------+
4 rows in set (0.00 sec)


mysql> select '11a' = 11, '11.0' = 11, '11.0' = '11', NULL = 1;
+------------+-------------+---------------+----------+
| '11a' = 11 | '11.0' = 11 | '11.0' = '11' | NULL = 1 |
+------------+-------------+---------------+----------+
|          1 |           1 |             0 |     NULL |
+------------+-------------+---------------+----------+
1 row in set, 1 warning (0.01 sec)
```
上面可以看出`11 + 'aa'`，由于操作符两边的类型不一样且符合第g条，`aa`要被转换成浮点型小数，然而转换失败（字母被截断），可以认为转成了 0，整数`11`被转成浮点型还是它自己，所以`11 + 'aa' = 11`。

`0.01a`转成double型也是被截断成`0.01`，所以`11 + '0.01a' = 11.01`。

等式比较也说明了这一点，`'11a'`和`'11.0'`转换后都等于 `11`，这也正是文章开头实例为什么没走索引的原因： varchar型的f_qq1_id，转换成浮点型比较时，等于 12345 的情况有无数种如12345a、12345.b等待，MySQL优化器无法确定索引是否更有效，所以选择了其它方案。

但并不是只要出现隐式类型转换，就会引起上面类似的性能问题，最终是要看转换后能否有效选择索引。像`f_id = '654321'`、`f_mtime between '2016-05-01 00:00:00' and '2016-05-04 23:59:59'`就不会影响索引选择，因为前者f_id是整型，即使与后面的字符串型数字转换成double比较，依然能根据double确定f_id的值，索引依然有效。后者是因为符合第e条，只是右边的常量做了转换。

开发人员可能都只要存在这么一个隐式类型转换的坑，但却又经常不注意，所以干脆无需记住那么多规则，该什么类型就与什么类型比较。

### 2.2 隐式类型转换的安全问题
implicit type conversion 不仅可能引起性能问题，还有可能产生安全问题。
```
mysql> desc t_account;
+-----------+-------------+------+-----+---------+----------------+
| Field     | Type        | Null | Key | Default | Extra          |
+-----------+-------------+------+-----+---------+----------------+
| fid       | int(11)     | NO   | PRI | NULL    | auto_increment |
| fname     | varchar(20) | YES  |     | NULL    |                |
| fpassword | varchar(50) | YES  |     | NULL    |                |
+-----------+-------------+------+-----+---------+----------------+

mysql> select * from t_account;
+-----+-----------+-------------+
| fid | fname     | fpassword   |
+-----+-----------+-------------+
|   1 | xiaoming  | p_xiaoming  |
|   2 | xiaoming1 | p_xiaoming1 |
+-----+-----------+-------------+

假如应用前端没有WAF防护，那么下面的sql很容易注入：
mysql> select * from t_account where fname='A' ;

fname传入  A' OR 1='1  

mysql> select * from t_account where fname='A' OR 1='1';
```

攻击者更聪明一点： fname传入 `A'+'B`  ，fpassword传入 `ccc'+0` ：
```
mysql> select * from t_account where fname='A'+'B' and fpassword='ccc'+0;
+-----+-----------+-------------+
| fid | fname     | fpassword   |
+-----+-----------+-------------+
|   1 | xiaoming  | p_xiaoming  |
|   2 | xiaoming1 | p_xiaoming1 |
+-----+-----------+-------------+
2 rows in set, 7 warnings (0.00 sec)
```


## 参考

- [MySQL隐式转化整理](https://yq.aliyun.com/articles/39477)
- [WHRER条件里的数据类型必须和字段数据类型一致](http://blog.itpub.net/22418990/viewspace-1302080/)
- [Implicit type conversion in MySQL](https://vagosec.org/2013/04/mysql-implicit-type-conversion/)

---

原文链接地址：http://xgknight.com/2016/05/05/mysql-type-conversion/

---
