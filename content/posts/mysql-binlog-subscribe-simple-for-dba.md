---
title: 一个简单的数据订阅程序(for DBA)
date: 2017-09-05 16:32:49
aliases:
- /2017/09/05/mysql-binlog-subscribe-simple-for-dba/
tags: [mysql, table_cache]
categories:
- MySQL
updated: 2017-09-05 16:32:49
---

本程序基于大众点评github项目 [binlog2sql](https://github.com/danfengcao/binlog2sql) 二次开发而来，可以实现对源库的binlog实时接收，并组装成增量sql。

原项目默认是把sql输出到控制台，二次开发后的版本把sql放入redis队列，根据需要由另一个程序消费到目标库，模拟了一个“从库”。
在测试时`--stop-never`在qa环境没有作用，添加了在 BinLogStreamReader 实例里面加入 `blocking=True` 来保证源源不断的接受binlog而不中断。

另外也加入了更改目标库名的功能，比如原库叫d_my1，生成的sql目标库名是 d_my2 。

项目地址：https://github.com/seanlook/binlog2sql

# 应用场景
目前想到以下应用场景：

- 实时同步部分表到另外一个数据库实例 
  比如在数据库迁库时，将当天表的数据同步到新库，模拟阿里云dms数据传输的功能，相当于在测试环境演练，减少失误。 
  另外还可以从新库反向同步增量数据到老库，解决测试环境多项目测试引起数据库冲突的问题。

- 正式切库时的回滚措施 
  比如数据库迁移项目，切换期间数据写向新库，但如果切换失败需要回滚到老库，就需要把这段时间新增的数据同步回老库（启动消费程序），这就不需要程序段再考虑复杂的回滚设计。

- 数据库闪回 
  关于数据库误操作的闪回方案，见 [文章MySQL根据离线binlog快速闪回](http://xgknight.com/2017/03/03/mysql-flashback_use_purged-binlog/) 。`binlog2sql`的 `-B` 选项可以将sql反向组装，生产回滚sql。如果需要完善的闪回功能，要进一步开发，提高易用性。

- binlog搜索功能 
  目前组内一版的binlog搜索功能，是离线任务处理的方式，好处是不会占用太大空间，缺点是处理时间较长。通过实时binlog解析过滤的方式，入ES可以快速搜索。需要进一步开发完善。
  
<!-- more -->


# 使用方法
安装好python2.7虚拟环境，安装必要模块：pymysql, mysql-replication, redis, rq
```
pip install -r requirements.txt
```

注意：`pymysqlreplication` 库在处理 '0000-00-00 00:00:00' 时有些不尽人意，可能会导致生产的sql在目标库执行失败，还有对`datetime(6)`类型有个bug，也对它进行了修复，地址：https://github.com/seanlook/python-mysql-replication 。

准备一个redis用于存放sql队列，在环境变量里面设置redis地址
```
export REDIS_URL='redis://localhost:6379'
```
在主库执行 `show master status` 得到binlog开始的文件名和postion，然后开始订阅：
```
binlog2sql原版使用时：
$ ~/.pyenv/versions/2.7.10/envs/py2_binlog/bin/python binlog2sql.py -h192.168.1.185 -P3306 -uecuser -pecuser \
-d d_ec_contact --tables t_crm_contact_at \
--start-file='mysql-bin.000001' --start-datetime='2017-08-30 12:30:00' --start-position=6529058 \
--stop-never > contact0.sql

加入订阅功能后：
$ ~/.pyenv/versions/2.7.10/envs/py2_binlog/bin/python binlog2sql.py -h192.168.1.185 -P3306 -uecuser -pecuser \
-d d_ec_contact:d_ec_crm --tables t_crm_contact_at t_crm_remark_today \
--start-file='mysql-bin.000001' --start-datetime='2017-08-30 12:30:00' --start-position=6529058 \
--dest-dsn h=10.0.200.195,P=3307,u=ecuser,p=ecuser
--stop-never > contact0.sql
```

`-d d_ec_contact:d_ec_crm` 表上生成目标sql映射关系，如果不改变库名，就不需要 `:` 指定，与原版兼容。  
`--dest-dsn`: 表示目标库的地址和认证信息。

这时在redis里面可以看到sql信息。如果需要在目标库重放，则启动消费程序：（在代码目录下面）
```
~/.pyenv/versions/2.7.10/envs/py2_binlog/bin/rq worker
```
待数据追上之后，可以看到几乎是实时同步的。


---

本文链接地址：http://xgknight.com/2017/09/05/mysql-binlog-subscribe-simple-for-dba/

---
