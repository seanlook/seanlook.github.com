---
title: READ-COMMITED 与 REPEATABLE-READ 事务隔离级别之间的异同
date: 2016-09-03 16:32:49
tags: [mysql, 事务]
categories:
- MySQL
updated: 2016-09-03 16:32:49
---



经常会被问到 InnoDB隔离级别中 READ-COMMITED和REPEATABLE-READ 的区别，今天就整理了一下，不再从“脏读”、“幻读”这样的名词解释一样去回答了。

## 1. 行锁
InnoDB行锁实际锁的是索引记录，为了防止死锁的产生以及维护所需要的隔离级别，在执行sql语句的全过程中，innodb必须对所需要修改的行每条索引记录上锁。如此一来，如果你执行的 UPDATE 没有很好的索引，那么会导致锁定许多行：
```
update employees set store_id = 0 where store_id = 1;
---TRANSACTION 1EAB04, ACTIVE 7 sec
633 lock struct(s), <strong>heap size 96696</strong>, 218786 row lock(s), undo log entries 1
MySQL thread id 4, OS thread handle 0x7f8dfc35d700, query id 47 localhost root
show engine innodb status
```
上面的 `employees` 表 `store_id` 列没有索引。注意 UPDATE 已经执行完成（没有提交），但依然有 218786 个行锁没有释放，还有一个undo记录。这意味着只有一行被更改，但却持有了额外的锁。堆大小（heap size）代表了分配给锁使用的内存数量。

在 REPEATABLE-READ 级别，事务持有的 **每个锁** 在整个事务期间一直被持有。

在 READ-COMMITED 级别，事务里面特定语句结束之后，不匹配该sql语句扫描条件的锁，会被释放。

下面是上述相同的 UPDATE 在 READ-COMMITED 级别下的结果：
```
---TRANSACTION 1EAB06, ACTIVE 11 sec
631 lock struct(s), <strong>heap size 96696</strong>, 1 row lock(s), undo log entries 1
MySQL thread id 4, OS thread handle 0x7f8dfc35d700, query id 62 localhost root
show engine innodb status
```

可以看到 heap size 没有变化，但是现在我们只持有一个行锁。无论什么隔离级别下，InnoDB 会为扫描过的每条索引记录创建锁，不同的是在 RC 模式，一旦语句执行完毕（事务未必完成），不符合扫描条件的记录上的锁会被随即释放。释放这些锁后，堆内存并不会马上释放，所以heap size看到与 RR 模式是一样的，但是持有的锁数量明显小了很多。

这也就意味着在 RC 级别下的事务A，只要A的UPDATE **语句** 完成了，其它事务可以修改A中也扫描过的行，但在 RR 级别下不允许。

## 2. Read View
### REPEATABLE-READ
在 REPEATABLE-READ 级别，*read view* 对象在事务一开启就被创建，这个一致性快照在整个事务期间一直保持打开。在同一个事务里，前后间隔几个小时执行一遍相同的 SELECT，你会得到完全一样的结果，这就是所谓的 MVCC (multiple version concurrency control)，它是通过行版本号和UNDO段来实现的。

在 REPEATABLE-READ 级别， InnoDB会为范围扫描创建间隙锁（gap locks）：
```
select * from some_table where id > 100 FOR UPDATE;
```

<!-- more -->

上面的update将会创建一个 gap lock，用来防止在 id>100 范围内有新行被插入，锁会持续到事务回滚或提交。比如在同一个事务里，上午5点执行 SELECT ... FOR UPDATE，下午5点执行 UPDATE some_table where id>100，那么这个update只会修改上午5点 SELECT FOR UPDATE所锁定的行，因为大于100的记录的整个 **间隙** 被加了锁。

### READ-COMMITED
在 READ-COMMITED 级别，*read view* 结构在每个语句开始的时候被创建，这意味着即使在同一个事务中，上午5点执行的 SELECT与下午5点执行的SELECT可能会得到不同的结果。因为 read view 在 READ-COMMITED 级别下仅在 **语句执行** 期间存在。

这就是所谓的 “幻读”（phantom read）。

READ-COMMITED 隔离级别下是没有gap locks，所以执行上面的 SELECT FOR UPDATE where id>100 并不会阻止其它事务插入新行，如果同一个事务里后面执行 UPDATE ... where id>100，就有可能导致实际更新的行数比前面锁定的行数要多。

补充：
如果了解过 mysqldump 的实现原理，可知它就是充分利用InnoDB的MVCC特性，使用 REPEATABLE-READ 模式获取备份事务的一致性快照，避免锁表和幻读。

本文主要参考自 percona博客上的一篇文章 https://www.percona.com/blog/2012/08/28/differences-between-read-committed-and-repeatable-read-transaction-isolation-levels/ 。


---

本文链接地址：http://xgknight.com/2016/09/03/diffs-between-rr-and-rc-trx_isolation_level/

---
