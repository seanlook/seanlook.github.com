---
title: MySQL sql_mode 说明（及处理一起 sql_mode 引发的问题）
date: 2016-04-22 16:32:49
aliases:
- /2016/04/22/mysql-sql-mode-troubleshooting/
tags: [mysql, sql_mode]
categories: 
- MySQL
updated: 2016-04-22 16:32:49
---


## 1. MySQL莫名变成了 Strict SQL Mode

最近测试组那边反应数据库部分写入失败，app层提示是插入成功，但表里面里面没有产生数据，而两个写入操作的另外一个表有数据。因为 insert 失败在数据库层面是看不出来的，于是找php的同事看下错误信息：

```
[Err] 1364 - Field `f_company_id` doesn't have a default value
```

很明显2个 insert 操作，第一条成功，第二条失败了，但因为没有控制在一个事务当中，导致app里面依然提示成功，这是客户入库操作，心想如果线上也有这个问题得是多大的代价。

不说开发的问题，好端端的mysql怎么突然就部分表写入失败呢？根据上面的问题很快能猜到是 sql_mode 问题： NOT NULL 列没有默认值但代码里也没给值，在非严格模式下，int列默认为0，string列默认为''了，所以不成问题；但在严格模式下，是直接返回失败的。

一看，果然：
```
mysql> show variables like "sql_mode";
+---------------+--------------------------------------------+
| Variable_name | Value                                      |
+---------------+--------------------------------------------+
| sql_mode      | STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION |
+---------------+--------------------------------------------+
```

但是一直是没问题的的，就突然出现了，有谁会去改 sql_mode 呢，生产环境产生这个问题的风险有多大？所以必须揪出来。

先 `set global sql_mode=''` ，让他们用着先（文后会给解决问题根本的办法），同时打开general_log看是哪一个用户有类似设置 sql_mode 命令：
```
1134456 Query   SET autocommit=1
1134456 Query   Set sql_mode='NO_ENGINE_SUBSITUTION,STRICT_TRANS_TABLES'
1134457 Connect ecuser@10.0.200.173 on
1134457 Query   /* mysql-connector-java-5.1.35 ...
```
看出是java组那边哪个框架建立连接的时候使用设置了sql_mode，但这是session级别的，不影响php那边用户的连接。

<!-- more -->

那会是什么原因在 set global 之后又变回strict模式呢，于是想到 mysqld_safe 启动实际是一个保护进程，在mysqld异常停止之后会拉起来，会不会中间有异常导致 mysqld 重启，致使 global 失效？看了mysql错误日志，才想到前些天断过电，所以决定直接改 `/etc/my.cnf`配置：
```
[mysqld]
sql_mode=NO_ENGINE_SUBSTITUTION
```
重启myqld之后，还是`STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION`，很少遇到my.cnf里面配置不生效的情况。无独有偶，在 stackoverflow上找到同样的问题 [how-to-make-sql-mode-no-engine-substitution-permanent-in-mysql-my-cnf](http://stackoverflow.com/questions/28849293/how-to-make-sql-mode-no-engine-substitution-permanent-in-mysql-my-cnf) ，原因很简单，sql_mode这个选项被其它地方的配置覆盖了。


**了解一下mysql配置文件的加载顺序：**

```
$ mysqld --help --verbose|grep -A1 -B1 cnf
Default options are read from the following files in the given order:
/etc/my.cnf /etc/mysql/my.cnf /usr/etc/my.cnf ~/.my.cnf
```
mysql按照上面的顺序加载配置文件，后面的配置项会覆盖前面的。最后终于在 `/usr/my.cnf` 找到有一条`sql_mode=NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES`，把这个文件删掉，/etc/my.cnf 里面的就生效了。

但是目前没能整明白的是，mysql运行这么长时间怎么突然在`/usr` （MYSQL_BASE）下多个my.cnf，也不像人为创建的。其它实例也没这样的问题。

类似还出现过一例：存储过程里把 '' 传给int型的，严格模式是不允许，而非严格模式只是一个warning。（命令行执行完语句后，`show warnings` 可看见）

那么解决这类问题的终极（推荐）办法其实是，考虑到数据的兼容性和准确性，MySQL就应该运行在严格模式下！无论开发环境还是生产环境，否则代码移植到线上可能产生隐藏的问题。


sql_mode 问题可以很简单，也可以很复杂。曾经在一个交流群里看到有人提到，主从sql_mode设置不一致导致复制异常，这里自己正好全面了解一下几个常用的值，方便以后排除问题多个方向。

## 2. sql_mode 常用值说明
官方手册专门有一节介绍 https://dev.mysql.com/doc/refman/5.6/en/sql-mode.html 。 SQL Mode 定义了两个方面：MySQL应支持的SQL语法，以及应该在数据上执行何种确认检查。

- SQL语法支持类
 - `ONLY_FULL_GROUP_BY`  
 对于GROUP BY聚合操作，如果在SELECT中的列、HAVING或者ORDER BY子句的列，没有在GROUP BY中出现，那么这个SQL是不合法的。是可以理解的，因为不在 group by 的列查出来展示会有矛盾。  
 在5.7中默认启用，所以在实施5.6升级到5.7的过程需要注意：
```
 Expression #1 of SELECT list is not in GROUP BY
clause and contains nonaggregated column
'1066export.ebay_order_items.TransactionID' which
is not functionally dependent on columns in GROUP BY
clause; this is incompatible with sql_mode=only_full_group_by
```
 - `ANSI_QUOTES`  
 启用 ANSI_QUOTES 后，不能用双引号来引用字符串，因为它被解释为识别符，作用与 \` 一样。  
 设置它以后，`update t set f1="" ...`，会报 Unknown column '' in 'field list 这样的语法错误。
 - `PIPES_AS_CONCAT`  
 将 `||` 视为字符串的连接操作符而非 或 运算符，这和Oracle数据库是一样的，也和字符串的拼接函数 CONCAT() 相类似
 - `NO_TABLE_OPTIONS`  
 使用 `SHOW CREATE TABLE` 时不会输出MySQL特有的语法部分，如 `ENGINE` ，这个在使用 mysqldump 跨DB种类迁移的时候需要考虑。
 - `NO_AUTO_CREATE_USER`  
 字面意思不自动创建用户。在给MySQL用户授权时，我们习惯使用 `GRANT ... ON ... TO dbuser` 顺道一起创建用户。设置该选项后就与oracle操作类似，授权之前必须先建立用户。5.7.7开始也默认了。  

- 数据检查类
 - `NO_ZERO_DATE`  
 认为日期 '0000-00-00' 非法，与是否设置后面的严格模式有关。  
 1.如果设置了严格模式，则 NO_ZERO_DATE 自然满足。但如果是 INSERT IGNORE 或 UPDATE IGNORE，'0000-00-00'依然允许且只显示warning  
 2.如果在非严格模式下，设置了`NO_ZERO_DATE`，效果与上面一样，'0000-00-00'允许但显示warning；如果没有设置`NO_ZERO_DATE`，no warning，当做完全合法的值。
 3.`NO_ZERO_IN_DATE`情况与上面类似，不同的是控制日期和天，是否可为 0 ，即 `2010-01-00` 是否合法。  
 - `NO_ENGINE_SUBSTITUTION`  
 使用 `ALTER TABLE`或`CREATE TABLE` 指定 ENGINE 时， 需要的存储引擎被禁用或未编译，该如何处理。启用`NO_ENGINE_SUBSTITUTION`时，那么直接抛出错误；不设置此值时，CREATE用默认的存储引擎替代，ATLER不进行更改，并抛出一个 warning .
 - `STRICT_TRANS_TABLES`
 设置它，表示启用严格模式。  
 注意 `STRICT_TRANS_TABLES` 不是几种策略的组合，单独指 `INSERT`、`UPDATE`出现少值或无效值该如何处理:
 1.前面提到的把 '' 传给int，严格模式下非法，若启用非严格模式则变成0，产生一个warning
 2.Out Of Range，变成插入最大边界值
 3.A value is missing when a new row to be inserted does not contain a value for a non-NULL column that has no explicit DEFAULT clause in its definition

上面并没有囊括所有的 SQL Mode，选了几个代表性的，详细还是 [看手册](https://mariadb.com/kb/en/mariadb/sql_mode/)。

sql_mode一般来说很少去关注它，没有遇到实际问题之前不会去启停上面的条目。我们常设置的 sql_mode 是 `ANSI`、`STRICT_TRANS_TABLES`、`TRADITIONAL`，ansi和traditional是上面的几种组合。
- `ANSI`：更改语法和行为，使其更符合标准SQL
相当于REAL_AS_FLOAT, PIPES_AS_CONCAT, ANSI_QUOTES, IGNORE_SPACE
- `TRADITIONAL`：更像传统SQL数据库系统，该模式的简单描述是当在列中插入不正确的值时“给出错误而不是警告”。
相当于 STRICT_TRANS_TABLES, STRICT_ALL_TABLES, NO_ZERO_IN_DATE, NO_ZERO_DATE, ERROR_FOR_DIVISION_BY_ZERO, NO_AUTO_CREATE_USER, NO_ENGINE_SUBSTITUTION
- `ORACLE`：相当于 PIPES_AS_CONCAT, ANSI_QUOTES, IGNORE_SPACE, NO_KEY_OPTIONS, NO_TABLE_OPTIONS, NO_FIELD_OPTIONS, NO_AUTO_CREATE_USER

无论何种mode，产生error之后就意味着单条sql执行失败，对于支持事务的表，则导致当前事务回滚；但如果没有放在事务中执行，或者不支持事务的存储引擎表，则可能导致数据不一致。MySQL认为，相比直接报错终止，数据不一致问题更严重。于是 `STRICT_TRANS_TABLES` 对非事务表依然尽可能的让写入继续，比如给个"最合理"的默认值或截断。而对于 `STRICT_ALL_TABLES`，如果是单条更新，则不影响，但如果更新的是多条，第一条成功，后面失败则会出现部分更新。

5.6.6 以后版本默认就是`NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES`，5.5默认为 '' 。

## 3. 设置 sql_mode

**查看**
```
查看当前连接会话的sql模式：

mysql> select @@session.sql_mode;
或者从环境变量里取
mysql> show variables like "sql_mode";


查看全局sql_mode设置：
mysql> select @@global.sql_mode;

只设置global，需要重新连接进来才会生效
```

**设置**
```
形式如
mysql> set sql_mode='';
mysql> set global sql_mode='NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES';


如果是自定义的模式组合，可以像下面这样

Adding only one mode to sql_mode without removing existing ones:
mysql> SET sql_mode=(SELECT CONCAT(@@sql_mode,',<mode_to_add>'));

Removing only a specific mode from sql_mode without removing others:
mysql> SET sql_mode=(SELECT REPLACE(@@sql_mode,'<mode_to_remove>',''));
```

配置文件里面设置`sql-mode=""` 。


## 一个有趣的试验
updated: 2017-12-10

现网做数据迁移测试时报另一个错误，原由是这样的：一个1.8亿的表里面，因为某种原因需要把字段定义null改为not null，避免下游服务（如ES）处理特殊数据时异常情况。但这是一个并发dml非常高又达到100多G的大表，online ddl针对这种修改字段类型简直束手无策，pt-osc也慢的很。

刚好有一个做数据迁移的契机，原本打算在新库上把字段改好，再通过dts或类似的数据迁移工具，同步过去。在非严格模式下，原本是null的值也会变成0或''，但还是报错了：
```
set sql_mode='';  -- 置为非严格模式
insert into t(id, a) values(1, null);
[Err] 1048 - Column 'a' cannot be null

然而
insert into t(id, a) values(1, null),(2, null),;
Affected rows: 2
```

找到官方文档上的原话，可以解释：
> If you are not using strict mode, then whenever you insert an “incorrect” value into a column, such as a NULL into a NOT NULL column or a too-large numeric value into a numeric column, MySQL sets the column to the “best possible value” instead of producing an error

> If you try to store NULL into a column that doesn't take NULL values, an error occurs for single-row INSERT statements. For multiple-row INSERT statements or for INSERT INTO ... SELECT statements, MySQL Server stores the implicit default value for the column data type

非严格模式下，*单行*插入 null 到 not null 列，会失败；多行插入则只是warning。规则是这样，也就无需解释。


## 参考
- [MySQL manual sql-mode](https://dev.mysql.com/doc/refman/5.6/en/sql-mode.html#sql-mode-strict)
- [mysql的sql_mode合理设置](http://xstarcd.github.io/wiki/MySQL/MySQL-sql-mode.html)
- [set-sql-mode-blank-after-upgrading-to-mysql-5-6](http://dba.stackexchange.com/questions/109053/set-sql-mode-blank-after-upgrading-to-mysql-5-6)
- [MySQL SQL_MODE详解](http://blog.itpub.net/29773961/viewspace-1813501/)


---

原文链接地址：http://xgknight.com/2016/04/22/mysql-sql-mode-troubleshooting/

---
