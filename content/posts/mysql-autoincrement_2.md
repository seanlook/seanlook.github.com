---
title: 关于MySQL自增主键的几点问题（下）
date: 2017-02-17 16:32:49
aliases:
- /2017/02/17/mysql-autoincrement_2/
tags: [mysql, schema设计]
categories:
- MySQL
updated: 2017-02-17 16:32:49
---

### AUTO-INC waiting 锁等待
这是生产环境出现的现象，某日下午5点业务高峰期，我们的 [慢查询快照抓取程序](http://xgknight.com/2016/09/27/python-mysql-querykill/) 报出大量线程阻塞，但是1分钟以后就好了。于是分析了当时的 processlist 和 innodb status 现场记录，发现有大量的 `AUTO-INC waiting`：

![auto-inc-lock-wait][1]

当时想这是得多大的并发量，才会导致 AUTO_INCREMENT 列的自增id分配出现性能问题，不太愿意相信这个事实（后面就再也没出现过）。了解一番之后（见 [关于MySQLz自增主键问题（上篇）](http://xgknight.com/2017/02/16/mysql-autoincrement/)），发现这个表级别的 AUTO-INC lock 就不应该在业务中存在，因为 `innodb_autoinc_lock_mode`为1，普通业务都是 simple inserts，获取自增id是靠内存里维护的一个互斥量（mutex counter）。

问题拿到知数堂优化班上课群里讨论过，也只是猜测是不是慢查询多了导致负载高，或者当时磁盘遇到什么物理故障阿里云那边自动恢复了。再后来怀疑是不是因为插入时带了 auto_increment 列的值（我们有个redis incr实现的自增id服务，虽然这一列有 AAUTO_INCREMENT 定义，但实际已经从发号器取id了），会导致锁的性质会变？

为了弄清这个疑问，特意去看了下mysql源码，发现如果插入的自增值比表当前AUTOINC值要大，是直接update mutex counter：

![](http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-autoinc-mutex-update.png)

看源码的时候也打消了另一个疑虑：`show engine innodb status` 看到的 `AUTO-INC` 有没有可能不区分 表级自增锁和互斥量计数器 两种自增方案，只是告诉你自增id获取忙不过来？ 实际不是的，代码里面有明确的定义是 `autoinc_lock`还是`autoinc_mutex`：
```
// dict0dict.cc :
#ifndef UNIV_HOTBACKUP
/********************************************************************//**
Acquire the autoinc lock. */
UNIV_INTERN
void
dict_table_autoinc_lock(
/*====================*/
	dict_table_t*	table)	/*!< in/out: table */
{
	mutex_enter(&table->autoinc_mutex);
}

/********************************************************************//**
Unconditionally set the autoinc counter. */
UNIV_INTERN
void
dict_table_autoinc_initialize(
/*==========================*/
	dict_table_t*	table,	/*!< in/out: table */
	ib_uint64_t	value)	/*!< in: next value to assign to a row */
{
	ut_ad(mutex_own(&table->autoinc_mutex));

	table->autoinc = value;
}
```
<!-- more -->
最后在微信上找周彦伟大神问问，在快要放弃的时候，从 innodb_lock_waits 中锁等待之间关系，一层一层挖，终于找到了一条这样的sql:
```
"INSERT INTO mydb1.t_mytable_inc ( f_log_id, f_fff_id, ..., f_from, f_sendmsg )
    SELECT 2021712366, 507019984, ..., 10, 0 from dual"
```
瞬间就明(ma)白(niang)了。典型的 `INSERT ... SELECT ...`， 但是 select 子句带的全是常量，但是对 innodb 来说它还是认为“这是 bulk inserts，我无法预估插入行数”，所以使用表级锁的自增方式。当时同时有 22 个这样的插入，可能负载也确实比较高导致活跃事务里主键最小的那一条一直处于 *query end* 状态，后面简单insert也需要等这个 语句 结束，直到释放 AUTO-INC table lock，以致引起雪崩效应。

之所以一直没发现这条语句，是因为 processlist 太长了，而且格式不友好。快照抓取程序这块还可以优化。

最后解决其实非常容易：
1. 既然已经有自增id服务，直接把把主键上的 AUTO_INCREMENT 定义去掉
2. 整改这种 insert ... select ... 的sql。维护时可以，但开发账号要杜绝
3. 周大神说他们用的是 mode 2 模式。也不失为一种方法

### load data 为什么没阻塞其它事务
这是一个同行网友请教我的：
![][2]

上篇讲到，load data infile 由于innodb无法提前知道插入的行数，所以归为 bulk inserts —— 表自增方式升级为表级锁，这样一来其它会话里的 insert岂不应该是会被阻塞，为什么实验结果却没有阻塞。

当然一开始我也觉得奇怪，但是仔细想一下就知道，这个表级锁是一个特殊的表锁，为了提高并发性，它是在 **语句** 结束就释放了（而不是事务结束），那么只要验证 LOAD DATA 是把文件里面的行记录，拼装成单个insert就行了，这样其它会话的插入就可以在交错获得表级自增锁，实现不阻塞插入：
![][3]

~~~上图我是为了看效果，临时设置 `log_bin='statement'`，看到 `LOAD DATA INFILE` 会把文件转换成 *一个* 事务包含的 *多行* insert，于是就说得通了。~~~ @jin 多谢指正。

上图 row 模式下 的binlog，看到 BEGIN ... COMMIT 之间包含了 多行 insert。（注：在 statement 模式下，binlog里面记录的是 LOAD DATA 语句，从库会把文件从主库传输过来，再执行）


温馨提示：  
1. 如果load data 的文件自带主键值，那么另一个会话获取的自增值很容易产生重复。
2. stackexchange上有个关于 [load data infile 对复制安全性的讨论](http://dba.stackexchange.com/questions/40400/loading-data-in-mysql-using-load-data-infile-replication-safe) ，同意二楼的观点，官方文档里说的 unsafe，并不是说执行这样的语句会导致安全问题，而是 considered unsafe，在 row-based 可用的情况下，优化器会自动把binlog记录为 row ，依然是安全的。



  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-autoinc-1.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-autoinc-loaddata.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-autoinc-loaddata-binlog.png



---

本文链接地址：http://xgknight.com/2017/02/17/mysql-autoincrement_2/

---
