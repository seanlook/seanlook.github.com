---
title: “大”事务引起的锁等待分析案例
date: 2017-10-17 16:32:49
aliases:
- /2017/10/17/mysql-big-trx-lock-case/
tags: [mysql, lock]
categories:
- MySQL
updated: 2017-10-17 16:32:49
---

# 1. 现象
生产环境数据库在某一刻突然发现大量活跃连接，而且大部分状态是 `updating` 。问题出现在周六上午，持续了大概三四分钟，得益于我们自己的快照程序，拿到了当时现场的的processlist, 锁等待关系，innodb status 信息：(经过脱敏处理)

![mysql-bigtrx-lockinfo.png][1]
![mysql-bigtrx-processlist.png][2]
 
innodb_status.txt片段：
[var_mydb_snapshot.html](https://gist.coding.net/u/seanlook/d6ad649f81c64e23a25f3a980c44a1fe) （也可以通过 pt-stalk 收集）


首先在 Lock Waits Info 一节，看到每行的trx_id(事务)的role分为 Blocker(引起阻塞的线程) 与 Blockee（被阻塞者）；最后一列 blocking_trx_id 在role是Blockee时才有值，代表谁阻塞了当前事务。
根据上面的关系，可以得出以下结论：
1. 事务 **19705811640** 运行了231s，阻塞了19706118937、19706124453、19706124752，而这些事务都在做同一个UPDATE语句
2. 被锁定的记录是 mydb.mytable1表的主键索引值为 5317885 行
3. 事务 19706124752 既被阻塞，也阻塞了别人19706125253
4. 不难发现 **19705811640** 应该最先运行的事务，且对其它事务产生了链式阻塞，它的thread_id是 9898630，来源IP

但是当你兴冲冲的找到引起阻塞的事务 19705811640 在做什么事情时，发现它没有任何sql的信息，lock info以及processlist里面都是None。那么有哪些情况会导致在会话是活跃的，但sql的内容为空：
1. 执行show processlist的时候，刚好在事务里面两个sql的中间
2. sql已经执行完成，但长时间没有提交

# 2. 初步分析
其实这个现象已经遇到过很多次了，第1个原因常发生在 大量单条记录更新 的情况，一个sql在一个事务里循环执行10000次，即使每条都很快，但大部分时间都在网络传输上，（可以改成批量的形式）。在本案例基本上能确定的是第2个原因：事务开启之后，sql也执行了，但中间又做别的事情去了。那么怎样才能知道这个事务是什么内容呢？两个方向去找：
1. 从来源ip上的应用程序的日志里分析
2. binlog里面分析

<!-- more -->
应用程序日志里可以看 10:21:00 ~ 10:26:00 之间，mydb.mytable1 表上主键id=5317885 在做什么事情。因为我们上了听云，在听云APM里面也可以清楚的看到这个时间点的哪个方法慢：
![mysql-bigtrx-tingyun][3]

 响应时间230多秒，从“相关SQL”里面看到操作的记录内容，确定就是它了(根据innodb status快照时间 - ACTIVE 230.874 sec，倒推得到的时间与这里刚好吻合)。从接口名称也清楚的知道是在进行禁用用户的操作，猜想：
禁用用户的逻辑上有先挪到回收站，再删资料、删权限、删关系，清理缓存等等一系列操作，放在事务里保证他们的原子性，似乎是合理的。但为什么执行了将近4分钟还没有提交呢，分析相关的sql效率都很高。

有三种情况：
1. 这个事务执行到一半，它需要操作的数据被别人锁住，等待了这么久
2. 类似事务要操作5000条数据，但是一条一条的操作，然后一起提交（已出现过类似的例子）
3. 事务务执行完成很快，但调用其它接口迟迟没有返回，导致事务没提交。

不会是1和2，因为从一开始的分析看到事务 **19705811640** 都是在阻塞别人，而不是受害者。那么结合上图中有个有两个操作redis的接口执行时间占比96%，可以下定论了：  
在禁用用户时，开启了一个事务，四五个增删改很快完成，但是操作redis缓存过程比较慢，也包含在了事务代码之间，长时间没有提交。前端用户操作的时候因为迟迟没有响应，进行了多次重复点击操作，因为影响的还是同一行记录，所以只能等待前面的锁释放。

Bingo，跟最初的设想一样。但是，开发检查代码之后告诉我，没有用事务！那前面的猜想和结论都不成立了。

# 3. 论证
于是走另外一个思路，分析binlog。如果binlog里面记录那条记录修改(设置禁用标志)和删除（真正删除）的时间是 10:21:58，说明数据库操作那时候就完成；如果是10:25:xx，说明最后才提交。为了弄明白这个问题，也为了搞情况事务的内容到底是什么，解析当时的binlog。（阿里云rds的数据追踪功能本来挺好用，但这一次用着报内部错误）

还记得前面那个thread_id吗，可以用在这里过滤(也可以用记录值)：
```
$ mysqlbinlog --base64-output=decode-rows -vv --start-datetime="2017-09-16 10:21:00"  --stop-datetime="2017-09-16 10:27:00" mysql-bin.010743 > mysql-bin.010743.sql
$ grep -B5 -A200 "thread_id=9898630" mysql-bin.010743.sql > mysql-bin.010743.sql.txt

$ ./summarize_binlogs.sh > mysql-bin.010743.sql.xid  # 会比较慢
$ cat mysql-bin.010743.sql.xid|grep Transaction|awk '{if($19>0)print}'
[Transaction total : 10 Insert(s) : 1 Update(s) : 0 Delete(s) : 9 Xid : 99370218911 period : 190 ] 
[Transaction total : 10 Insert(s) : 1 Update(s) : 0 Delete(s) : 9 Xid : 99370268888 period : 236 ]
```
上面的 summarize_binlogs.sh 脚本来源于《MySQL运维内参》，可以汇总分析binlog里面事务的执行时间。

mysql-bin.010743.sql.txt:
```
# at 112037144
#170916 10:25:54 server id 1508836346  end_log_pos 112037192 CRC32 0x25216430    GTID [commit=yes]
SET @@SESSION.GTID_NEXT= '56506509-b971-11e6-8c19-6c92bf2c8aaf:10306353216'/*!*/;
# at 112037192
#170916 10:21:58 server id 1508836346  end_log_pos 112037268 CRC32 0x9cddeec2    Query    thread_id=9898630    exec_time=0    error_code=0
SET TIMESTAMP=1505528518/*!*/;
SET @@session.sql_mode=2097152/*!*/;
BEGIN
/*!*/;
# at 112037268
#170916 10:21:58 server id 1508836346  end_log_pos 112037342 CRC32 0x373641db    Table_map: `mydb`.`mytable01_del` mapped to number 950163
# at 112037342
#170916 10:21:58 server id 1508836346  end_log_pos 112037460 CRC32 0x4bba2efb    Write_rows: table id 950163 flags: STMT_END_F

BINLOG '
xoq8WRP6A+9ZSgAAAN6NrQYAAJN/DgAAAAEACWRfZWNfdXNlcgAKdF91c2VyX2RlbAAMCAgICBEB
CAgRCA8IBAAAyAAAAdtBNjc=
xoq8WRf6A+9ZdgAAAFSOrQYAAJN/DgAAAAEADP//APEL/VAAAAAAAP0kUQAAAAAACKpYGQQAAAAK
/VAAAAAAAFm8isYAAAAAAAAAAAAAAAAAAAAAADojUQAAAAAADOW+kOaxn+e6oue7hOE3BAAAAAAA
+y66Sw==
'/*!*/;
### INSERT INTO `mydb`.`mytable01_del`
# at 112037460
#170916 10:21:58 server id 1508836346  end_log_pos 112037542 CRC32 0x7b55174a    Table_map: `mydb`.`mytable1` mapped to number 950159
# at 112037542
#170916 10:21:58 server id 1508836346  end_log_pos 112037636 CRC32 0x3bdcebf7    Delete_rows: table id 950159 flags: STMT_END_F

BINLOG '
xoq8WRP6A+9ZUgAAAKaOrQYAAI9/DgAAAAEACWRfZWNfdXNlcgAOdF91c2VyX2FjY291bnQADAgC
Dw8BARISAQMBDwiAABAAAADwADgBShdVew==
xoq8WRn6A+9ZXgAAAASPrQYAAI9/DgAAAAEADP//APD9JFEAAAAAAAAACzE3NjA1MTEwMjgwEDc9
OokVkE7wcJ6AvWQXyZMEAJmc6TjAmZzs458AAAAAAAAA9+vcOw==
'/*!*/;
### DELETE FROM `mydb`.`mytable1`
......
# at 112038300
#170916 10:25:54 server id 1508836346  end_log_pos 112038331 CRC32 0x01b508cf    Xid = 99370268888
COMMIT/*!*/;
```
binlog格式当中，一个事务最先记录的是GTID事件，而这个GTID的值只有在提交的时候才会生成，binlog里面的GTID时间的时间`10:25:54`就是事务提交的时间。
Xid在最末尾，时间也是`10:25:54`。但中间该事务的其它binlog事件，像UpdateRows/DeleteRows/InsertRows，前面的时间`10:21:58`是事务开始的时间。中间有4分钟的空档，与前面redis操作4分钟不谋而合。

这下就更加明朗了：有显式的开启事务。但开发说没有用事务，又该怎么解释呢？

不同的语言，不同的框架，使用事务的方式不一样。数据库里面开启显式事务有两种方式，一是设置 `set autocommit=0`，二是运行`start transaction`。两者都要显式调用`commit`命令提交事务。
为了证实程序的确用了事务，在测试环境应用服务器模拟用户的操作，然后抓包：
```
$ sudo tcpdump -s 0 -l -w - dst your_db_ipaddr and port 3306 -i eth0 > mysql_3306.tcp
$ strings mysql_3306.tcp|grep -n commit
28:SET autocommit=0
123:commit
124:SET autocommit=1
222:SET autocommit=0
257:commit
258:SET autocommit=1
268:SET autocommit=0
333:SET autocommit=1
399:commit
400:SET autocommit=1
```
有发送 `set autocommit=0`，这下更放心了。开发再次回去检查，发现在Spring框架的时，在类上面用 `@Transactional` 的方式做了事务，而常规的做法是把注解加在类的方法上，导致忽略了这个因素。

# 4. 解决
解决办法是把需要做事务控制的地方放到Services接口级别，让redis清理缓存的操作在事务之外，或者异步清理。（但也要考虑这样做会有什么负面影响）
另外，Redis操作慢，是否是设计上的问题。（听云监控里面显示该事务里面调用了1300次）

# 5. 总结
首先根据但是的现场快照，分析锁等待关系；根据以前的经验，怀疑是“大”事务中有无关的调用；根据程序日志和听云分析出对应的接口；但开发说没有事务，于是进一步通过分析binlog，经过tcp抓包，拿出证据；最后解决。

我们经常说，尽量少用大事务，但由于现在开发都是基于各种框架，使用事务的方式被封装，要理解它们的用法。其次，我们上面的事务并不大，每个sql更新都很快，但是却把其它调用也写在事务里面，就容易阻塞而长时间不提交，也许这样做的初衷是操作db与清理redis缓存放在一个事务里，要么都成功，要么都失败，但是这种分布式设计就不合理（当然有办法是可以做到，这里不展开）。

本文即是一个大事务锁的分析案例，也展示了引用各种工具，去分析论证的过程。


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-bigtrx-lockinfo.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-bigtrx-processlist.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-bigtrx-tingyun.png


---

本文链接地址：http://xgknight.com/2017/10/17/mysql-big-trx-lock-case/

---
