---
title: MySQL根据离线binlog快速“闪回”
date: 2017-03-03 16:32:49
tags: [mysql]
categories:
- MySQL
updated: 2017-03-03 16:32:49
---


昨天突然有个客户说误操作，自己删除了大量数据，CTO直接将我拉到一个讨论组里，说要帮他们恢复数据。他们自己挖的坑，打算让开发那边根据业务日志去恢复，被告知只记录的删除主键这样的信息，物理删除，无能为力。

上服务器看了下记录的日志，发现好几台上面都有被误删的记录输出。阿里RDS虽然可以克隆一个恢复到删除时间点前的实例，但这散落的几万个id找起来费力，还有就是几个表之间关联的数据也要恢复，觉得麻烦。

想到 MySQL 的闪回方案。以前看过好几篇相关文章，甚至差点自己用python撸一个来解析binlog，反转得到回滚sql，实在没空，这下要急用了。赶紧找了下网上“现成的方案”。

正文开始

---

MySQL（含阿里RDS）快速闪回可以说是对数据库误操作的后悔药，flashback功能可以将数据库返回到误操作之前。但是即使oracle数据库也只支持短时间内的闪回。

网上现有开源的MySQL闪回实现，原理都是解析binlog，生成反向sql: (必须为row模式)
1. 对于 delete 操作，生成insert （DELETE_ROWS_EVENT）
2. 对于 update 操作，交换binlog里面值的顺序 （UPDATE_ROWS_EVENT）
3. 对于 insert 操作，反向生成delete （WRITE_ROWS_EVENT）
4. 对于多个event，要逆向生成sql

开源实现：
- https://github.com/58daojia-dba/mysqlbinlog_flashback
- https://github.com/danfengcao/binlog2sql/

上面两种实现方式，都是通过 python-mysql-replication 包，模拟出原库的一个从库，然后 `show binary logs` 来获取binlog，发起同步binlog的请求，再解析EVENT。但是阿里云 RDS 的binlog在同步给从库之后，** 很快就被 purge 掉了 **。如果要恢复 ** 昨天** 的 ** 部分数据 **，两种方案都是拿不到binlog的。也就是闪回的时间有限。

还有一些比较简单的实现，就是解析 binlog 物理文件，实现回滚，如 `binlog-rollback.pl` ，试过，但是速度太慢。

为了不影响速度，又想使用比较成熟的闪回方案，我们可以这样做：

1. 借助一个自建的 mysqld 实例，将已purge掉的binlog拷贝到该实例的目录下
2. 在自建实例里，提前创建好需要恢复的表（结构），因为工具需要连接上来从 `information_schema.columns` 获取元数据信息
3. 拷贝的时候，可以替换掉mysql实例自己的binlog文件名，保持连续
4. 可能要修改 `mysql-bin.index`，确保文件名还能被mysqld识别到
5. 重启mysql实例，`show binary logs` 看一下是否在列表里面
6. 接下来就可以使用上面任何一种工具，模拟从库，指定一个binlog文件，开始时间，结束时间，得到回滚SQL
7. 再根据业务逻辑，筛选出需要的sql

<!--more-->
总之就是借助另外一个mysql，把binlog event传输过来。温馨提示：

1. 两个实例间版本不要跨度太大
2. 注意文件权限
3. 如果原库开启了gtid，这个自建实例也要开启gtid

示例：

```
python mysqlbinlog_back.py --host="localhost" --username="ecuser" --password="ecuser" --port=3306 \
--schema=dbname --tables="t_xx1,t_xx2,t_xx3" -S "mysql-bin.000019" -E "2017-03-02 13:00:00" -N "2017-03-02 14:09:00" -I -U

===log will also  write to .//mysqlbinlog_flashback.log===
parameter={'start_binlog_file': 'mysql-bin.000019', 'stream': None, 'keep_data': True,
 'file': {'data_create': None, 'flashback': None, 'data': None}, 'add_schema_name': False, 'start_time': None, 'keep_current_data': False, 'start_to_timestamp': 1488430800,
 'mysql_setting': {'passwd': 'ecuser', 'host': 'localhost', 'charset': 'utf8', 'port': 3306, 'user': 'ecuser'},
 'table_name': 't_xx1,t_xx2,t_xx3', 'skip_delete': False, 'schema': 'dbname', 'stat': {'flash_sql': {}},
 'table_name_array': ['t_xx1', 't_xx2', 't_xx3'],
 'one_binlog_file': False, 'output_file_path': './log', 'start_position': 4, 'skip_update': True,
 'dump_event': False, 'end_to_timestamp': 1488434940, 'skip_insert': True, 'schema_array': ['dbname']
}
scan 10000 events ....from binlogfile=mysql-bin.000019,timestamp=2017-03-02T11:42:14
scan 20000 events ....from binlogfile=mysql-bin.000019,timestamp=2017-03-02T11:42:29
...
```

提示：
binlog为ROW格式，dml影响的每一行都会记录两个event：Table_map和Row_log。而table_map里面的table_id并不会影响它在哪个实例上应用，这个id可以认为是逻辑上，记录表结构版本的机制 —— 当它在 table_definition_cache 没有找到表定义时，id自增1，分配给要记录到binlog的表。

**mysqlbinlog_back.py 使用经验** ：

- 务必指定库名、表明，开始的binlog文件名，起始时间，结束时间。可以加快scan的速度。
- 根据恢复的需要，选择 -I, -U, -D，指定回滚哪些类型的操作。
- 如果只是恢复部分表数据（非完全闪回），做不到关联表的正确恢复。比如需要恢复delete数据，但无法恢复业务里因为delete引起其它表更新的数据，除非完全闪回。
- 不支持表字段是 enum 类型的，比如 t_xx3 的f_do_type字段。可以把自建实例上的enum定义改成int。


**参考**

1. http://dinglin.iteye.com/blog/1539167
1. http://www.penglixun.com/tech/database/mysql_flashback_feature.html/comment-page-1#comment-1207998
1. http://www.cnblogs.com/yuyue2014/p/3721172.html



---

本文链接地址：http://xgknight.com/2017/03/03/mysql-flashback_use_purged-binlog/

---
