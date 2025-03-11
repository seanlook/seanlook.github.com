---
title: MySQL数字类型int与tinyint、float与decimal如何选择
date: 2016-04-29 16:32:49
aliases:
- /2016/04/29/mysql-numeric-int-float/
tags: [mysql, schema设计]
categories:
- MySQL
updated: 2016-04-29 16:32:49
---

最近在准备给开发做一个mysql数据库开发规范方面培训，一步一步来，结合在生产环境发现的数据库方面的问题，从几个常用的数据类型说起。

## int、tinyint与bigint ##
它们都是（精确）整型数据类型，但是占用字节数和表达的范围不同。首先没有这个表就说不过去了：

|Type   |Storage    |Minimum Value  |Maximum Value|
|----|----|----|----|
|    |(Bytes)   |(Signed/Unsigned)  |(Signed/Unsigned)|
|TINYINT    |1  |-128   |127|
|    |      |0  |255|
|SMALLINT   |2  |-32768 |32767|
|    |      |0  |65535|
|MEDIUMINT  |3  |-8388608   |8388607|
|    |      |0  |16777215|
|INT |4     |-2147483648    |2147483647|
|    |      |0  |4294967295|
|BIGINT |8  |-9223372036854775808   |9223372036854775807|
|    |      |0  |18446744073709551615|

只需要知道对应类型占多少字节就能推算出范围了，比如int占 4 bytes,即4*8=32bits，大约10位数字，也能理解为什么int默认显示位数是11。

遇到比较多的是tinyint和bigint，tinyint一般用于存放status,type这种数值小的数据，不够用时可能会用smallint。bigint一般用于自增主键。

为了避免数据库被过度设计，布尔、枚举类型也采用tinyint。

还有一点也是经常被提到的关于 int(M) 中M的理解，int型数据无论是int(4)还是int(11)，都已经占用了 4 bytes 存储空间，M表示的只是显示宽度(display width, max value 255)，并不是定义int的长度。

例如：

```
mysql> CREATE TABLE `tc_integer` (
  `f_id` bigint(20) PRIMARY KEY AUTO_INCREMENT,
  `f_type` tinyint,
  `f_flag` tinyint(1),
  `f_num` smallint(5) unsigned ZEROFILL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

mysql> desc tc_integer;
+----------------+-------------------------------+------+-----+---------+----------------+
| Field          | Type                          | Null | Key | Default | Extra          |
+----------------+-------------------------------+------+-----+---------+----------------+
| f_id           | bigint(20)                    | NO   | PRI | NULL    | auto_increment |
| f_type         | tinyint(4)                    | YES  |     | NULL    |                |
| f_flag         | tinyint(1)                    | YES  |     | NULL    |                |
| f_num          | smallint(5) unsigned zerofill | YES  |     | NULL    |                |
+----------------+-------------------------------+------+-----+---------+----------------+
4 rows in set (0.01 sec)
```

插入几条数据看一下：
<!-- more -->

```
mysql> insert into tc_integer values(1, 1, 1, 1);
Query OK, 1 row affected (0.02 sec)

mysql> insert into tc_integer values(9223372036854775808, 127, 127, 65535);
Query OK, 1 row affected, 1 warning (0.01 sec)

mysql> show warnings;
+---------+------+-----------------------------------------------+
| Level   | Code | Message                                       |
+---------+------+-----------------------------------------------+
| Warning | 1264 | Out of range value for column 'f_id' at row 1 |
+---------+------+-----------------------------------------------+
1 row in set (0.00 sec)

mysql> select i.*, length(i.f_flag) as len_flag from tc_integer i;
+---------------------+--------------+---------------+----------------+----------+
| f_id                | f_type       | f_flag        | f_num          | len_flag |
+---------------------+--------------+---------------+----------------+----------+
|                   1 |            1 |             1 |          00001 |        1 |
| 9223372036854775807 |          127 |           127 |          65535 |        3 |
+---------------------+--------------+---------------+----------------+----------+
2 rows in set (0.00 sec)

mysql> select * from tc_integer where f_num=' 01' and f_num=1 and f_num=f_flag;
+------+--------------+---------------+----------------+
| f_id | f_type       | f_flag        | f_num          |
+------+--------------+---------------+----------------+
|    1 |            1 |             1 |          00001 |
+------+--------------+---------------+----------------+
1 row in set (0.00 sec)
```
上面的实验说明了几个问题：

- f_id列插入比最大值还大的数，出现warnings，并且最终的值自动变成 9223372036854775807 。这个坑曾经在迁移到阿里RDS时遇到过，他们的迁移工具是java写的，结果我们的主键值大于java INTEGER里面的最大限制，导致 duplicate key问题。
- f_flag的显示宽度为1，但并不影响更多位数的显示。也证实了tinyint(1)并不像char(1)那样限制存储长度
- f_num定义成无符号的zerofill类型，能存储的最大数值是65535，而signed才是32767。（当列上使用zerofill时，unsigned会自动加上）
- zerofill的作用是在显示检索结果的时候，左边用0补齐到display width，实际存储时不补0的，仅作为返回结果meta data的一部分。查询的条件值忽略0和空格
- length()在numeric类型中作用于char_length()一样，因为字节数已经固定了。

zerofill的使用可能会在复杂join时因为了解不够深入而带来问题，所以最终的结论也很简单：除非极端的特殊需要，尽量不用zerofill，建表时这类int无需指定 (11) 这样的显示宽度。

## float与decimal
MySQL使用`DECIMAL`类型去存储对精度要求比较高的数值，比如金额，也叫定点数，decimal在mysql内存是以~~字符串~~二进制存储的。声明语法是`DECIMAL(M,D)`，~~占用字节 M+2 bytes~~。M是数字最大位数（精度precision），范围1-65；D是小数点右侧数字个数（标度scale），范围0-30，但不得超过M。

占用字节数计算方法 —— 小数和整数分别计算，每9位数占4字节，剩余部分如下表换算：

|Leftover Digits  |Number of Bytes|
|----|----|
|0  |0  |
|1–2  |1  |
|3–4	|2  |
|5–6  |3  |
|7–9  |4  |

比如`DECIMAL(18,9)`，整数部分和小数部分各9位，所以各占4字节，共8bytes
再比如`DECIMAL(20,6)`，整数14位，需要4字节存9位，还需3字节存5位；小数6位，需3字节。共10bytes
（感谢 consatan 在评论区提出文中错误）

比如定义`DECIMAL(7,3)`：
- 能存的数值范围是 -9999.999 ~ 9999.999，占用4个字节
- 123.12 -> 123.120，因为小数点后未满3位，补0
- 123.1245 -> 123.125，小数点只留3位，多余的自动四舍五入截断
- 12345.12 -> 保存失败，因为小数点未满3位，补0变成12345.120，超过了7位。严格模式下报错，非严格模式存成9999.999


MySQL使用`FLOAT`和`DOUBLE`来表示近似数值类型，这是因为十进制0.1在电脑里用二进制是无法精确表示的，[只能尽可能的接近](https://segmentfault.com/a/1190000004112565)。

单精度浮点数float占4字节，float标准语法允许通过`FLOAT(M)`的形式指定精度，但是这个精度值M只是决定存储大小： 0-23与默认不指定效果相同，24-53就变成双精度的`DOUBLE`了。

float还有非MySQL自己实现的*非标准*语法`FLOAT(M,D)`，代表最多存储M个数字长度，其中小数点后数字个数为D。效果与 DECIMAL(M,D)很相似。

double 和 float 的区别是double精度高，有效数字16位（float精度7位）。但double消耗内存是float的两倍，占8字节，double的运算速度比float慢得多。

```
msyql> create table tc_float(fid int primary key auto_increment,f_float float, f_float10 float(10), f_float25 float(25), f_float7_3 float(7,3), f_float9_2 float(9,2), f_float30_3 float(30,3), f_decimal9_2 decimal(9,2));

mysql> insert into tc_float(f_float,f_float10,f_float25) values(123456,123456,123456);
mysql> insert into tc_float(f_float,f_float10,f_float25) values(1234567.89,12345.67,1234567.89);
mysql> select * from tc_float;
+-----+----------+-----------+------------+------------+------------+-------------+--------------+
| fid | f_float  | f_float10 | f_float25  | f_float7_3 | f_float9_2 | f_float30_3 | f_decimal9_2 |
+-----+----------+-----------+------------+------------+------------+-------------+--------------+
|   1 |   123456 |    123456 |     123456 | NULL       | NULL       | NULL        | NULL         |
|   2 |  1234570 |   12345.7 | 1234567.89 | NULL       | NULL       | NULL        | NULL         |
+-----+----------+-----------+------------+------------+------------+-------------+--------------+

```

- 可以看到float与float(10)是没区别的，float默认能精确到6位有效数字

```
mysql> insert into tc_float(f_float9_2,f_decimal9_2) values(123456.78,123456.78);
mysql> insert into tc_float(f_float9_2,f_decimal9_2) values(1234567.1,1234567.125);
Query OK, 1 row affected, 1 warning (0.00 sec)

mysql> show warnings;
+-------+------+---------------------------------------------------+
| Level | Code | Message                                           |
+-------+------+---------------------------------------------------+
| Note  | 1265 | Data truncated for column 'f_decimal9_2' at row 1 |
+-------+------+---------------------------------------------------+
1 row in set (0.00 sec)

mysql> select * from tc_float;
+-----+----------+-----------+------------+------------+------------+-------------+--------------+
| fid | f_float  | f_float10 | f_float25  | f_float7_3 | f_float9_2 | f_float30_3 | f_decimal9_2 |
+-----+----------+-----------+------------+------------+------------+-------------+--------------+
|   6 | NULL     | NULL      | NULL       | NULL       |  123456.78 | NULL        |    123456.78 |
|   9 | NULL     | NULL      | NULL       | NULL       | 1234567.12 | NULL        |   1234567.13 |
+-----+----------+-----------+------------+------------+------------+-------------+--------------+

mysql> insert into tc_float(f_float7_3) values(12345.1);
ERROR 1264 (22003): Out of range value for column 'f_float7_3' at row 1
```

- float(9,2)与decimal(9,2)是很像的，并没有前面提到24位一下6位有效数字的限制
- 他们俩之间的差别就在精度上，f_float9_2本应该是 1234567.10，结果小数点变成 .12 。f_decimal9_2因为标度为2，所以 .125 四舍五入成 .13
- 将 12345.1 插入f_float7_3列，因为转成标度3时 12345.100，整个位数大于7，所以 out of range 了

另外在编程中应尽量避免做浮点数的比较，否则可能会导致一些潜在的问题。

坚决不允许使用float去存money，使用decimal更加稳妥，但使用decimal做除法依旧会产生浮点型，所以特殊情况请考虑使用整型，货币单位使用 分 ，或者除法在最后进行。

## 参考

- [MySQL各数据类型的区别](http://www.path8.net/tn/archives/951)
- [MySQL manual Out-of-Range and Overflow Handling](http://dev.mysql.com/doc/refman/5.6/en/out-of-range-and-overflow.html)
- [MySQL FLOAT vs DEC: working with fraction and decimal](http://www.intechgrity.com/mysql-datatypes-working-with-fraction-and-decimal-dec/)
- [Never use floats for money](http://www.noelherrick.com/blog/always-use-decimal-for-money)


---

本文链接地址：http://xgknight.com/2016/04/29/mysql-numeric-int-float/

---
