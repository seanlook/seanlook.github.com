---
title: MySQL数据库表结构同步之SchemaSync
date: 2017-11-02 15:32:49
tags: [mysql, 表结构]
categories:
- MySQL
updated: 2017-11-02 15:32:49
---

SchemaSync是个能够在mysql数据库之间，比较并生成表结构差异的工具，项目地址 https://github.com/mmatuson/SchemaSync  。

# SchemaSync介绍与使用
因为工作中经常需要在各个环境之间同步表结构，特别是生产与测试环境之间，长时间的运行后，总会有不一致的。测试环境的表结构一般是测试验证功能之后没有问题，然后通过工单的形式由DBA在生产环境修改。但生产库的结构，如修改索引，紧急修改字段长度，久而久之就会与测试环境有差异，需要同步到测试环境。

又或者有多套测试环境之间要保持结构同步，又比如同一类db（分库）的情况下，比较schema之间的对象差异。

SchemaSync不仅限于表结构，它可以处理的对象还有：视图、事件、存储过程、函数、触发器、外键，与 mysql-utilities 相当。但 SchemaSync 更适合于实践：
1. 默认不会同步 `AUTO_INCREMENT` 和  COMMENT`，有选项可以控制
2. 对不存在的对象会生成对应的CREATE，对多余的对象会生成DROP
3. 对生成 alter...column 的sql，是有列顺序的
4. 安装简单，相比mysqldiff，要安装mysql-connector-python和一整套mysql-utilities工具

当然前两点在我自己的 `mysqldiff` 版本里，已经加入了支持，见 [MySQL数据库表结构同步之mysqldiff](http://xgknight.com/2017/08/05/mysql_mysqldiff/)

**SchemaSync安装：**
```
（使用virtualenv）
$ pip install mysql-python pymysql schemaobject schemasync
```
SchemaObject也是同一个作者的，专门用于操作数据库对象的库，于是schemasync只需要获取对象，比较差异，然后调用schemaobect生成sql。（SchemaObject依赖pymysql，SchemaSync依赖MySQLdb，其实可以用同一个）
<!-- more -->

**SchemaSync用法：**
```
$ schemasync --help
Usage: 
                schemasync [options] <source> <target>
                source/target format: mysql://user:pass@host:port/database

                        A MySQL Schema Synchronization Utility

Options:
  -h, --help            show this help message and exit
  -V, --version         show version and exit.
  -r, --revision        increment the migration script version number if a
                        file with the same name already exists.
  -a, --sync-auto-inc   sync the AUTO_INCREMENT value for each table.
  -c, --sync-comments   sync the COMMENT field for all tables AND columns
  -D, --no-date         removes the date from the file format
  --charset=CHARSET     set the connection charset, default: utf8
  --tag=TAG             tag the migration scripts as <database>_<tag>. Valid
                        characters include [A-Za-z0-9-_]
  --output-directory=OUTPUT_DIRECTORY
                        directory to write the migration scrips. The default
                        is current working directory. Must use absolute path
                        if provided.
  --log-directory=LOG_DIRECTORY
                        set the directory to write the log to. Must use
                        absolute path if provided. Default is output
                        directory. Log filename is schemasync.log
```

示例：
```
$ schemasync mysql://ecuser:dbpass@10.x.xxx.141:3307/d_dbtest mysql://ecuser:dbpass@192.168.x.xxx:3306/d_dbtest --tag=BASE
Migration scripts created for mysql://192.168.x.xxx/d_dbtest
Patch Script: /home/zx/SchemaSync/d_dbtest_BASE.20171111.patch.sql
Revert Script: /home/zx/SchemaSync/d_dbtest_BASE.20171111.revert.sql
```

第一个是source db，第二个是target db，是标准的 connection string url 格式。
`--tag`, `--no-date`：都是控制生成的ddl文件名格式。

# 问题修复与增强
有两个小问题都是在SchemaObject里面，而且都有人 [提交patch](https://github.com/mmatuson/SchemaObject/pulls) 但还没合并到主干：
1. ADD INDEX 语法错误，`alter table t ADD INDEX ON t`，不需要这个ON。在不用alter table而直接 ADD INDEX 才要。
2. schemaobject 生成 `DEFAULT 'xx'` 时不支持python3。当然文件里也只说了支持2.6,2.7

目前我们的做法是对 schemaobject/index.py 大概170行的地方，手动修改，也懒的fork自己的分支：
```
-            return "DROP INDEX `%s` ON `%s`" % (self.name, self.parent.name)
+            return "DROP INDEX `%s`" % (self.name)
```

另一个增强是如果我想比较一个实例下面的所有database，SchemaSync是要手动一个一个去运行，于是拉了个自己的分支，支持 
`mysql://user:pass@host:port/*` 的格式，自动遍历实例下面所有的schema（忽略mysql,information_schema,performance_schema,sys），然后递归调用自身。使用起来就方便多了。

代码地址：https://github.com/seanlook/SchemaSync

```
$ schemasync mysql://ecuser:dbpass@10.x.xxx.141:3307/* mysql://ecuser:dbpass@192.168.x.xxx:3306/* --tag=BASE
 
Migration scripts created for mysql://192.168.x.xxx/d_ec_admin
Patch Script: /home/zx/SchemaSync/d_ec_admin_BASE.20171110.patch.sql
Revert Script: /home/zx/SchemaSync/d_ec_admin_BASE.2017110.revert.sql
...
MySQL Error 1049: Unknown database 'd_ec_package_bak_1027' (Ignore)  # 对db在目标库不存在的情况，忽略，不会CREAETE DATABASE
...
Migration scripts created for mysql://192.168.x.xxx/d_ec_package
Patch Script: /home/zx/SchemaSync/d_ec_package_BASE.20171110.patch.sql
Revert Script: /home/zx/SchemaSync/d_ec_package_BASE.20171110.revert.sql

$ cat *_BASE.20171110.patch.sql > target_schema_BASE.20171110.patch.sql
```

生成结构后不要盲目去执行同步，还要审查一遍，否则把不改删的字段删了就惨了。
还有，如果你在目标表上只是改变了列名，那么schema比较的时候，也是先drop在add，这个风险要自己把握。

如果要安装这个增强后的版本，请使用这种方式安装：
```
pip install git+https://github.com/seanlook/SchemaSync.git
```


---

原文连接地址：http://xgknight.com/2017/11/02/mysql_schemasync/

---
