---
title: 使用pt-osc修改主键时注意
date: 2016-05-27 16:32:49
aliases:
- /2016/05/27/mysql-pt-osc-add-primarykey/
tags: [mysql, Percona-toolkit]
categories: 
- MySQL
updated: 2016-05-27 16:32:49
---


使用 pt-online-schema-change 做在线ddl最添加普通索引、列，修改列类型、添加默认值等使用比较常规，但涉及到要修改的是主键时就有点棘手。在我修改线上实例过程中，有这样的需求，不妨先思考一下怎么做才好：
```
原表上有个复合主键，现在要添加一个自增id作为主键，如何进行
```
<!-- more -->

会涉及到以下修改动作：
1. 删除复合主键定义
2. 添加新的自增主键
3. 原复合主键字段，修改成唯一索引

如果你够聪明，应该会把这三个操作放在同一个 alter table 命令执行。percona手册里有两个地方对修改主键进行了特殊注解：

> --alter
> A notable exception is when a PRIMARY KEY or UNIQUE INDEX is being created from existing columns as part of the ALTER clause; in that case it will use these column(s) for the DELETE trigger.
>
> --[no]check-alter
>  - DROP PRIMARY KEY
>    If --alter contain DROP PRIMARY KEY (case- and space-insensitive), a warning is printed and the tool exits unless --dry-run is specified. Altering the primary key can be dangerous, but the tool can handle it. The tool’s triggers, particularly the DELETE trigger, are most affected by altering the primary key because the tool prefers to use the primary key for its triggers. You should first run the tool with --dry-run and --print and verify that the triggers are correct.

由上一篇文章 [pt-online-schema-change使用说明、限制与比较](http://xgknight.com/2016/05/27/mysql-pt-online-schema-change/) 可知，pt-osc会在原表t1上创建 AFTER DELETE/UPDATE/INSERT 三个触发器，修改主键影响最大的就是 DELETE 触发器：新表t2上的主键字段在旧表t1上不存在，无法根据主键条件触发删除新表t2数据。`but the tool can handle it`，原因是pt-osc把触发器改成了下面的形式：
```
CREATE TRIGGER `pt_osc_confluence_sbtest3_del` AFTER DELETE ON `confluence`.`sbtest3` FOR EACH ROW DELETE IGNORE FROM `confluence`.`_sbtest3_new` 
WHERE `confluence`.`_sbtest3_new`.`id` <=> OLD.`id` AND `confluence`.`_sbtest3_new`.`k` <=> OLD.`k`

注：sbtest3表上以(id,k)作为复合主键
```
但是如果id或k列上没有索引，这个删除的代价非常高，所以一定要同时添加复合（唯一）索引 `(id,k)` .

而对于INSERT,UPDATE的触发器，依然是 `REPLACE INTO`语法，因为它采用的是先插入，如果违反主键或唯一约束，则根据主键或意义约束删除这条数据，再执行插入。（但是注意你不能依赖于新表的主键递增，因为如果原表有update，新表就会先插入这一条，导致id与原表记录所在顺序不一样）

所以如果使用pt-osc去修改删除主键，务必同时添加原主键为 UNIQUE KEY，否则很有可能导致性能问题：

```
$ pt-online-schema-change --user=ecuser --password=ecuser --host=10.0.201.34  \
--alter "DROP PRIMARY KEY,add column pk int auto_increment primary key,add unique key uk_id_k(id,k)" \
D=confluence,t=sbtest3 --print --dry-run

--alter contains 'DROP PRIMARY KEY'.  Dropping and altering the primary key can be dangerous, 
especially if the original table does not have other unique indexes.  ==>注意 dry-run的输出

ALTER TABLE `confluence`.`_sbtest3_new` DROP PRIMARY KEY,add column pk int auto_increment primary key,add unique key uk_id_k(id,k)
Altered `confluence`.`_sbtest3_new` OK.
Using original table index PRIMARY for the DELETE trigger instead of new table index PRIMARY because ==> 使用原表主键值判断
the new table index uses column pk which does not exist in the original table.

CREATE TRIGGER `pt_osc_confluence_sbtest3_del` AFTER DELETE ON `confluence`.`sbtest3` FOR EACH ROW DELETE IGNORE FROM `confluence`.`_sbtest3_new` 
WHERE `confluence`.`_sbtest3_new`.`id` <=> OLD.`id` AND `confluence`.`_sbtest3_new`.`k` <=> OLD.`k`
```

---

原文链接地址：http://xgknight.com/2016/05/27/mysql-pt-osc-add-primarykey/

---
