---
title: MySQL数据库表结构同步之mysqldiff
date: 2017-08-05 15:32:49
tags: [mysql, 表结构]
categories:
- MySQL
updated: 2017-08-05 15:32:49
---

# mysqldiff
mysql官方有个 [mysql-utilities 工具集](https://dev.mysql.com/doc/mysql-utilities/1.6/en/mysql-utils-install-rpm.html)，其中 mysqldiff 可用于比较两个db之间的表结构。
mysqldiff的语法格式是：
```
$ mysqldiff --server1=user:pass@host:port:socket --server2=user:pass@host:port:socket db1.object1:db2.object1 db3:db4
```

这个语法有两个用法：
- `db1:db2`：如果只指定数据库，那么就将两个数据库中互相缺少的对象显示出来，不比较对象里面的差异。这里的对象包括表、存储过程、函数、触发器等。
  如果db1与db2名字相同，可以只指定 `db1`
- `db1.object1:db2.object1`：如果指定了具体表对象，那么就会详细对比两个表的差异，包括表名、字段名、备注、索引、大小写等所有的表相关的对象。  
  如果两边db和对象名都相同，可以只指定 `db1.object1`

接下来看一些主要的参数：
- `--server1`：配置server1的连接。
- `--server2`：配置server2的连接。
- `--character-set`：配置连接时用的字符集，如果不显示配置默认使用character_set_client。
- `--width`：配置显示的宽度。
- `--skip-table-options`：保持表的选项不变，即对比的差异里面不包括表名、AUTO_INCREMENT、ENGINE、CHARSET等差异。
- `-d DIFFTYPE,--difftype=DIFFTYPE`：差异的信息显示的方式，有 [unified|context|differ|sql]，默认是unified。如果使用`sql`，那么就直接生成差异的SQL，这样非常方便。
- `--changes-for=`：修改对象。例如 --changes-for=server2，那么对比以sever1为主，生成的差异的修改也是针对server2的对象的修改。
- `--show-reverse`：在生成的差异修改里面，同时会包含server2和server1的修改。
- `--force`：完成所有的比较，不会在遇到一个差异之后退出
- `-vv`：便于调试，输出许多信息
- `-q`：quiet模式，关闭多余的信息输出

# 问题修复与增强
但是试用下来，发现有以下几大问题
1. 对象在一方不存在时，比对结果是 object does not exist，而我们通常需要的是，生产 `CREATE/DROP XXX` 语句
2. 要比对一个db下面所有的对象（table, view, event, proc, func, trigger），要手动挨个 db1.t1, db2.v2...，而 db1:db2只是检查对象是否存在，不会自动比较db1与db2下的所有对象
3. 比较时，`auto_increment`应该忽略，但是 mysqldiff 只提供 `--skip-table-options` ，忽略全部表选项，包括 auto_increment, engine, charset等等。
3. 严重bug
   - T1: idx1(f1,f2),  T2: idx1(f1)，这种索引会生成 ADD INDEX idx(f2)
   - T1: idx2(f1,f2), idx3(f3,f4),  T2: idx4(f5)，这种组合索引，有可能生成的会乱序

这两个bug与mysqldiff的设计有关系，个人觉得它把比较和生产差异sql完全分开，复杂化了。它得到差异结果之后，生成sql又从db捞各种元数据来组装，其实从差异diff里面就可以获得组装需要的数据，也不容易出现隐藏的bug。参考实现 https://github.com/hidu/mysql-schema-sync

针对上面几大问题，花了两天的时间阅读并修改了 mysqldiff 以及相关依赖的代码，都一一解决。
修复后的地址：https://github.com/seanlook/mysql-utilities/commits/master
(mysql-utilities不像percona-toolkit那样每个工具都是All In One，需要改动mysqldiff.py意外的依赖模块)

默认情况与官方的 mysqldiff 完全兼容，新增3个选项
1. `--include-create`：是否生成创建对象(表等)的语句，而不是仅告知对象不存在。只有在 `--difftype=sql` 时有效。默认False
2. `--include-drop`：是否生成DROP对象的语句，针对对象在原db不存在，而仅目标db存在的情况。只有在指定了`--include-create` 时起作用。drop操作因为比较危险，默认False，所以多加了这个选项
3. `--skip-opt-autoinc`：比较时跳过AUTO_INCREMNT。默认False
4. 比较对象是，指定 `db1.*`  或 `db1.*:db2.*` 时，会比较他们所有的对象差异，而不仅显示缺少的对象


## 使用注意
1. 比较时，尽量选择mysql版本相近的实例，比如mysql与mariadb比较，相同的表结构 show create table xxx 时可能得到不同的结果：
   - mariadb会把int字段 default '0' 自动改成 default 0
   - `CURRENT_TIMESTAMP`会显示成 `current_timestamp()`
   - 字段 `default NULL` 时，mysql connector/python 查 `information_schema.COLUMNS.COLUMN_DEFAULT` 字段为 `‘NULL’` （带引号的字符），而不是None（即查出来是NULL），导致与mysql版本用不一样
2. 字段注释 `COMMENT '是否批准加入群 默认1批准 0拒绝\0e=''t_user_g\0'` ，是成立的，正常\0后面的都是没用的，但有个 `'` 号，会导致生产sql时有多余的 `'` 好，直接执行会失败。
   所以，字段注释要规范，不要带入这些乱起乱七八糟的字符，特别是用IDE建表时，完成后在命令行 show create table xxx 看一下。

<!-- more -->
# 演示对比
```
mysqldiff --server1=ecdba:xx@yyyy:3305 --server2=ecdba:xx@yyyy:3305 mydb1.t_user:mydb2.t_user  --changes-for=server2  --difftype=sql
# WARNING: Using a password on the command line interface can be insecure.
# server1 on 10.xx.xx.127: ... connected.
# server2 on 10.xx.xx.127: ... connected.
# Comparing mydb1.t_user to mydb2.t_user                           [FAIL]
# Transformation for --changes-for=server2:
#
 
ALTER TABLE `mydb2`.`t_user`
  DROP INDEX idx_corpid,
  ADD INDEX idx_corpid_deptid (f_corp_id,f_dept_id),
  ADD INDEX idx_dept (f_dept_id);
 
# Compare failed. One or more differences found.
  
这个地方原版里面会将idx_corpid_deptid生成 ADD INDEX idx_corpid_deptid(f_corp_id), ADD INDEX idx_corpid_deptid(f_dept_id)。这里已修复
```

```
原版：
mydb1.t_test1:mydb2.t_test1  --changes-for=server2  --difftype=sql
# WARNING: Using a password on the command line interface can be insecure.
# server1 on 10.xx.xx.127: ... connected.
# server2 on 10.xx.xx.127: ... connected.
ERROR: The object mydb2.t_test1 does not exist.
 
 
新选项 --include-create --include-drop
mydb1.t_test1:mydb2.t_test1  --changes-for=server2  --difftype=sql --include-create --include-drop
# WARNING: Using a password on the command line interface can be insecure.
# server1 on 10.xx.xx.127: ... connected.
# server2 on 10.xx.xx.127: ... connected.
 
USE mydb2;
CREATE TABLE `t_test1` (
  `id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
'
# Compare failed. One or more differences found.
 
 
新选项，修改changes-for后，生成drop
mydb1.t_test1:mydb2.t_test1  --changes-for=server1  --difftype=sql --include-create --include-drop
# WARNING: Using a password on the command line interface can be insecure.
# server1 on 10.xx.xx.127: ... connected.
# server2 on 10.xx.xx.127: ... connected.
DROP TABLE IF EXISTS mydb1.t_test1;
 
# Compare failed. One or more differences found.
```


```
mydb1.t_user_face:mydb2.t_user_face  --changes-for=server2  --difftype=sql --include-create --include-drop
# WARNING: Using a password on the command line interface can be insecure.
# server1 on 10.xx.xx.127: ... connected.
# server2 on 10.xx.xx.127: ... connected.
# Comparing mydb1.t_user_face to mydb2.t_user_face                 [FAIL]
# Transformation for --changes-for=server2:
#
 
ALTER TABLE `mydb2`.`t_user_face`
  DROP INDEX idx_tt2,
  DROP INDEX idx_corp_time,
  DROP COLUMN f_test,
  ADD INDEX idx_corp_time (f_corp_id,f_modify_time),
  CHANGE COLUMN f_corp_id f_corp_id int(11) unsigned NOT NULL COMMENT '企业id',
  CHANGE COLUMN f_user_id f_user_id int(11) unsigned NOT NULL COMMENT '用户id',
AUTO_INCREMENT=123434, COLLATE=utf8mb4_general_ci;
 
# Compare failed. One or more differences found.
这个地方原版处理 idx_corp_time 时，因为第一列索引字段相同，会生成 ADD INDEX idx_corp_time(f_modify_time)。这里已修复
 
新选项 --skip-option-autoinc
mydb1.t_user_face:mydb2.t_user_face  --changes-for=server1  --difftype=sql --include-create --include-drop --skip-option-autoinc
# WARNING: Using a password on the command line interface can be insecure.
# server1 on 10.xx.xx.127: ... connected.
# server2 on 10.xx.xx.127: ... connected.
# Comparing mydb1.t_user_face to mydb2.t_user_face                 [FAIL]
# Transformation for --changes-for=server1:
#
 
ALTER TABLE `mydb1`.`t_user_face`
  DROP INDEX idx_corp_time,
  ADD UNIQUE INDEX idx_tt2 (f_user_id,f_modify_time),
  ADD INDEX idx_corp_time (f_corp_id),
  CHANGE COLUMN f_corp_id f_corp_id int(10) unsigned NOT NULL COMMENT '企业id',
  CHANGE COLUMN f_user_id f_user_id int(10) unsigned NOT NULL COMMENT '用户id',
  ADD COLUMN f_test varchar(20) NOT NULL DEFAULT '' AFTER f_url,
COLLATE=utf8_general_ci;
 
# Compare failed. One or more differences found.
```

```
直接指定db，原版预修改版处理相同
mydb1:mydb2  --changes-for=server2  --difftype=sql
# WARNING: Using a password on the command line interface can be insecure.
# server1 on 10.xx.xx.127: ... connected.
# server2 on 10.xx.xx.127: ... connected.
# WARNING: Objects in server1.mydb1 but not in server1.mydb2:
#        TABLE: t_test1
# WARNING: Objects in server1.mydb2 but not in server1.mydb1:
#         VIEW: view_test
#        TABLE: t_test2
# Compare failed. One or more differences found.
 
 
指定 db.* ，处理相同
mydb1.*:mydb2.*  --changes-for=server2  --difftype=sql
# WARNING: Using a password on the command line interface can be insecure.
# server1 on 10.xx.xx.127: ... connected.
# server2 on 10.xx.xx.127: ... connected.
ERROR: The object mydb1.* does not exist.
 
 
指定 db.* 和 --include-create ，依次处理全部对象，包括过程，视图等
mydb1.*:mydb2.*  --changes-for=server2  --difftype=sql --difftype=sql --include-create --include-drop --skip-option-autoinc
# WARNING: Using a password on the command line interface can be insecure.
# server1 on 10.xx.xx.127: ... connected.
# server2 on 10.xx.xx.127: ... connected.
# WARNING: Objects in server1.mydb1 but not in server1.mydb2:
#        TABLE: t_test1
# WARNING: Objects in server1.mydb2 but not in server1.mydb1:
#         VIEW: view_test
#        TABLE: t_test2
# Comparing mydb1.t_user_face to mydb2.t_user_face                 [FAIL]
# Transformation for --changes-for=server2:
#
 
ALTER TABLE `mydb2`.`t_user_face`
  DROP INDEX idx_tt2,
  DROP INDEX idx_corp_time,
  DROP COLUMN f_test,
  ADD INDEX idx_corp_time (f_corp_id,f_modify_time),
  CHANGE COLUMN f_corp_id f_corp_id int(11) unsigned NOT NULL COMMENT '企业id',
  CHANGE COLUMN f_user_id f_user_id int(11) unsigned NOT NULL COMMENT '用户id',
COLLATE=utf8mb4_general_ci;
 
DROP VIEW IF EXISTS mydb2.view_test;
 
 
USE mydb2;
CREATE TABLE `t_test1` (
  `id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
'
# Comparing mydb1.t_user to mydb2.t_user                           [FAIL]
# Transformation for --changes-for=server2:
#
 
ALTER TABLE `mydb2`.`t_user`
  DROP INDEX idx_corpid,
  ADD INDEX idx_corpid_deptid (f_corp_id,f_dept_id),
  ADD INDEX idx_dept (f_dept_id);
 
# Comparing mydb1.proc_test to mydb2.proc_test                     [FAIL]
# Transformation for --changes-for=server2:
#
 
DROP PROCEDURE IF EXISTS `mydb2`.`proc_test`;
DELIMITER //
CREATE DEFINER=`ecdba`@`%` PROCEDURE `mydb2`.`proc_test` () CONTAINS SQL SQL SECURITY DEFINER BEGIN
    select 1;
 
END//
DELIMITER ;
 
 
DROP TABLE IF EXISTS mydb2.t_test2;
 
# Compare failed. One or more differences found.
```

---

原文连接地址：http://xgknight.com/2017/08/05/mysql_mysqldiff/

---
