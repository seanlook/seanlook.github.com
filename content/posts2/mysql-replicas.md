---
title: 使用 Xtrabackup 在线对MySQL做主从复制
date: 2015-12-14 10:21:25
updated: 2015-12-14 00:46:23
tags: [mysql, 主从复制, 备份]
categories: 
- MySQL
---

## 1. 说明
### 1.1 xtrabackup
mysqldump对于导出10G以下的数据库或几个表，还是适用的，而且更快捷。一旦数据量达到100-500G，无论是对原库的压力还是导出的性能，mysqldump就力不从心了。Percona-Xtrabackup备份工具，是实现MySQL在线热备工作的不二选择，可进行全量、增量、单表备份和还原。（但当数据量更大时，可能需要考虑分库分表，或使用 LVM 快照来加快备份速度了）

2.2版本 xtrabackup 能对InnoDB和XtraDB存储引擎的数据库非阻塞地备份，innobackupex通过perl封装了一层xtrabackup，对MyISAM的备份通过加表读锁的方式实现。2.3版本 xtrabackup 命令直接支持MyISAM引擎。

XtraBackup优势 ：

1. 无需停止数据库进行InnoDB热备
2. 增量备份MySQL
3. 流压缩到传输到其它服务器
4. 能比较容易地创建主从同步
5. 备份MySQL时不会增大服务器负载

### 1.2 replication

1. **为什么要做主从复制？**
我想这是要在实施以前要想清楚的问题。是为了实现读写分离，减轻主库负载或数据分析？ 为了数据安全，做备份恢复？主从切换做高可用？
大部分场景下，以上三个问号一主一从都能够解决，而且任何生产环境都建议你至少要有一个从库，假如你的读操作压力特别大，甚至要做一主多从，还可以不同的slave扮演不同的角色，例如使用不同的索引，或者不同的存储引擎，或使用一个小内存server做slave只用于备份。（当然slave太多也会对master的负载和网络带宽造成压力，此时可以考虑级联复制，即 A->B->C ）

    还有需要考虑的是，一主一从，一旦做了主从切换，不通过其它HA手段干预的话，业务访问的还是原IP，而且原主库很容易就作废了。于是 主-主 复制就产生了，凭借各自不同的 server-id ，可以避免 “A的变化同步到B，B应用变化又同步到A” 这样循环复制的问题。但建议是，主主复制，其中一个主库强制设置为只读，主从切换后架构依然是可用的。

    复制过程是slave主动向master拉取，而不是master去推的，所以理想情况下做搭建主从时不需要master做出任何改变甚至停服，slave失败也不影响主库。

<!-- more -->

2. **复制类型**

    - 基于语句的复制：`STATEMENT`，在主服务器上执行的SQL语句，在从服务器上执行同样的语句，有可能会由于SQL执行上下文环境不同而是数据不一致，例如调用NOW()函数。MySQL在5.7.7以前默认采用基于语句的复制，在 5.7.7 及以后版本默认改用 row-based。   
    - 基于行的复制：`ROW`，把改变的内容复制过去，而不是把命令在从服务器上执行一遍。从mysql5.0开始支持，能够严格保证数据完全一致，但此时用`mysqlbinlog`去分析日志就没啥意义。因为任何一条update语句，都会把涉及到的行数据全部set值，所以binlog文件会比较大。
    （遇到的一个坑是，迁移时，从库改正了字段默认值定义，但数据在主库更改后，即使产生的新数据默认值是正确的，但基于行的复制依然用不正确的值字段全部更新了）
    - 混合类型的复制: `MIXED`，默认采用基于语句的复制，一旦发现基于语句的无法精确的复制时，就会采用基于行的复制。
  
  mysql系统库`mysql`库里面表的日志记录格式需要说明：在通过如INSERT、UPDATE、DELETE、TRUNCATE等方式直接修改数据的语句，使用` binlog_format`指定的方式记录，但使用GRANT、ALTER、CREATE、RENAME等改动的mysql库里数据的，会强制使用`statement-based`方式记录binlog。

  可以在线修改二进制日志类型，如`SET SESSION binlog_format=MIXED;`，需要`SUPER`权限。

    复制类型还可以分为 异步复制和半同步复制。
    通常没说明指的都是异步，即主库执行完Commit后，在主库写入Binlog日志后即可成功返回客户端，无需等等Binlog日志传送给从库，一旦主库宕机，有可能会丢失日志。而半同步复制，是等待其中一个从库也接收到Binlog事务并成功写入Relay Log之后，才返回Commit操作成功给客户端；如此半同步就保证了事务成功提交后至少有两份日志记录，一份在主库Binlog上，另一份在从库的Relay Log上，从而进一步保证数据完整性；半同步复制很大程度取决于主从网络RTT（往返时延），以插件 semisync_master/semisync_slave 形式存在。


3. **原理**
(1) master将改变记录到二进制日志(binary log)中（这些记录叫做二进制日志事件，binary log events）；
(2) slave将master的binary log events拷贝到它的中继日志(relay log)；
(3) slave重做中继日志中的事件，将改变反映它自己的数据。


![mysql-replication][1]


  - 该过程的第一部分就是master记录二进制日志。在每个事务更新数据完成之前，master在二进制日志记录这些改变。MySQL将事务串行的写入二进制日志，即使事务中的语句都是交叉执行的。在事件写入二进制日志完成后，master通知存储引擎提交事务。
  - 下一步将master的binary log拷贝到它自己的中继日志。首先，slave开始一个工作线程——I/O线程。I/O线程在master上打开一个普通的连接，请求从指定日志文件的指定位置之后的日志内容，然后开始binlog dump process。Binlog dump process从master的二进制日志中读取事件，如果已经跟上master，它会睡眠并等待master产生新的事件。I/O线程将这些事件写入中继日志。
  - SQL slave thread（SQL从线程）处理该过程的最后一步。SQL线程从中继日志读取事件，并重放其中的事件而更新slave的数据，使其与master中的数据一致。只要该线程与I/O线程保持一致，中继日志通常会位于OS的缓存中，所以中继日志的开销很小。

  此外，在master中也有一个工作线程：和其它MySQL的连接一样，slave在master中打开一个连接也会使得master开始一个线程。复制过程有一个很重要的限制——复制在slave上是串行化的，也就是说master上的并行更新操作不能在slave上并行操作。

补充:
 
- mysql 5.7开始加入了多源复制，这个特性对同时有很多个mysql实例是很有用的，阿里云RDS（迁移）实现了类似的方式。
- 从MySQL 5.6.2开始，mysql binlog支持checksum校验，并且5.6.6默认启用（CRC32），这对自己模拟实现mysql复制的场景有影响。


**下面开始配置主从**：

　　主从版本一致—>主库授权复制帐号—>确保开启binlog及主从server_id唯一—>xtrabackup恢复到从库—>记录xtrabackup_binlog_info中binlog名称及偏移量—>从库change master to —>slave start—>检查两个yes

## 2. 创建复制账号

在主库上

    mysql> GRANT REPLICATION SLAVE ON *.* TO 'slave_ali'@'192.168.5.%' IDENTIFIED BY 'slave_ali_pass';  
    mysql> FLUSH PRIVILEGES;

## 3. 使用Percona-Xtrabackup恢复数据
这里假设比较简单的情况：全量备份，全量恢复，不涉及增量。

安装和具体使用，见[文章]()。

赋予备份用户权限：
```
mysql> CREATE USER 'bkpuser'@'localhost' IDENTIFIED BY 'bkppass';
mysql> GRANT RELOAD, LOCK TABLES, REPLICATION CLIENT,PROCESS,SUPER ON *.* TO 'bkpuser'@'localhost';
mysql> FLUSH PRIVILEGES;
```
完整的选项使用请执行innobackupex –-help，这里只介绍使用常用的选项进行完整备份及增量备份和还原。


这一节是把数据恢复到从库，借此记录一下xtrabackup的使用（用了云之后，备份技能都丢了~）。生产环境你应该是早就有了xtrabackup的备份，做从库时只需要把备份拷过来，解压恢复。


假设 MySQL 安装目录在`/opt/mysql`，my.cnf配置文件`/opt/mysql/my.cnf`，端口3306，数据目录`/opt/mysql_data`，sock位于`/opt/mysql_data/mysql.sock`。备份数据放在`/data/backup/mysql/`。

### 3.1 全量备份
```
$ export BKP_PASS="bkppass"
$ innobackupex --defaults-file=/opt/mysql/my.cnf --host=localhost --port=3306 --user=bkpuser --password=${BKP_PASS} /data/backup/mysql
```
默认会以当天 日期+时间 戳命名备份目录，如 2015-09-16_00-00-02。一般会对它进行tar压缩，由于tar只能单进程，所以往往这个压缩过程会比备份过程耗时2倍还多。拷贝到需要恢复（做从库）的目录。

    如果手头有一份未压缩的全备数据，要在另一台恢复，其实还不如直接 rsync 过来，将近400G的数据压缩与解压缩过程特别漫长。

### 3.2 全量恢复 
在恢复的数据库服务器（从库）上：

    ```
    恢复准备
    $ innobackupex --use-memory=16G --apply-log 2015-09-16_00-00-02
    
    确认数据库是关闭的，并且datadir，目录下为空
    $ innobackupex --defaults-file=/opt/mysql/my.cnf --use-memory=16G --copy-back 2015-09-16_00-00-02 
    ```

    第一步是恢复准备，apply-log应用全备时 log sequence number 之后的数据，完了后会输出类似 InnoDB: Last MySQL binlog file position 0 262484673, file name ./mysql-bin.000135 的信息，告诉我们了后面的从库应该从哪个地方开始复制。时间不会很长，但最好用screen之类的软件放到后台执行，以免终端断开，功亏一篑。
    
    第二步使用新的my.cnf文件，将完整的mysql数据文件拷贝到datadir下。


## 4. 做从库
上面恢复过程最后一步`apply-log`完成之后，会得到一个lsn position 和binlog文件名：262484673、mysql-bin.000135。下面开始从库制作。

一般在`copy-back`之后需要修改数据文件目录的属性：
```
# chown -R mysql.mysql /opt/mysql_data
```

### 4.1 my.cnf
从库的配置文件简单一点可以从主库拷贝过来，但根据需要，要注意以下几处

- server-id一定不能与主库相同
否则，会出现如下错误：
Slave: received end packet FROM server, apparent master shutdown

- 从库一般作为只读库使用，所以为安全起见，设置只读 `set global read_only=1`;
可以在从服务器的 my.cnf 里加入`read-only`参数来实现这一点，唯一需要注意的一点事read-only仅对没有super权限的用户有效。所以最好核对一下连接从服务器的用户，确保其没有super权限。

- 关于从库的事件
MYSQL Replication 可以很好的达到你的预期：从库的事件不会自己去执行，主库会把event执行的结果直接同步。在statement模式下，复制的是 event BODY 里的SQL，在row模式下是主库事件执行完成后影响的行精确复制。

    从库 event_scheduler 参数是被忽略的，并且每个event 状态会是 SLAVESIDE_DISABLED ，但CREATE/ALTER EVENT等操作语句是会复制。主从切换后，从库事件状态会变成ENABLE。

- 参数调整
从库是不允许写入的，否则数据就不一致了。从库实例的配置可以不要主库那么高，比如原16G的buffer pool，根据用途，从库可以设到4-8G（当时前提是将来你也不打算把它切换为主库用）。
相应的，read_buffer_size，sort_buffer_size, query_cache_size 这些读相关参数可以略微增大。当然我一般都懒得去改。

- skip-slave-start
主从创建完成后，默认情况下次启动从库，会自动启动复制进程，一般这也正是我们需要的，但在维护阶段时你可能不想从库启动后立即开始复制，`--skip-slave-start`选项可以帮到你。

- log-slave-updates
正常情况从库是不需要写回放日志产生的binlog，无形中增加服务器压力。但如果你想要实现级联复制即 `A -> B -> C` ，B同时是A的从库，也是C的主库，就需要开启 log-bin 和 log-slave-updates 。

    另外，建议显示设置 `log-bin=mysql-bin` 确保主从正常切换。 `show variables like 'log%'` 查看当前值。

- 关于过滤表见[mysql-replica-filter]()

- sync_binlog
For the greatest possible durability and consistency in a replication setup using InnoDB with transactions, you should use innodb_flush_log_at_trx_commit=1 and sync_binlog=1 in the master my.cnf file.

    上面的话同时也意味着性能最低。可以在这埋点，假如出现慢的情况，把两参数调成2。

### 4.2 启动从库
启动数据库，注意看日志
```
# /opt/mysql/bin/mysqld_safe --defaults-file=/opt/mysql/my.cnf &
```
提示：如果你不确定这个库是谁的从库，保守起见加上`--skip-slave-start`启动，兴许能防止数据不一致。

### 4.3 change master

在从库上
    
    $ mysql -uslave_ali -p'slave_ali_pass' -S /opt/mysql_data/mysql.sock
    mysql> change master to master_host=MASTER_HOST, master_port=3306, 
           master_user='slave_ali',master_password='slave_ali_pass',
           master_log_file='mysql-bin.000135', master_log_pos=262484673;

上面的 master_log_file 和 master_log_pos 即是输出的值，也可以在新的数据目录下`xtrabackup_binlog_info`找到信息。
    
    mysql> show slave status\G
    mysql> start slave;
    mysql> show slave status\G

### 4.4 验证同步延迟
从库执行 show slave status\G
节选：
```
            Slave_IO_State: Waiting for master to send event
            Master_Log_File: mysql-bin.000004
        Read_Master_Log_Pos: 931
             Relay_Log_File: slave1-relay-bin.000056
              Relay_Log_Pos: 950
      Relay_Master_Log_File: mysql-bin.000004
           Slave_IO_Running: Yes
          Slave_SQL_Running: Yes
         Exec_Master_Log_Pos: 931
            Relay_Log_Space: 408
      Seconds_Behind_Master: 0
```

- `Master_Log_File`： I/O线程当前正在读取的主服务器二进制日志文件的名称
- `Read_Master_Log_Pos`：本机I/O线程读取主服务器二进制日志位置
上面2各值，与在主库执行`show master status;`看到的值如果基本接近，说明从库*IO线程*已经赶上了主库的binlog。
- `Relay_Master_Log_File`: 由SQL线程执行的包含多数近期事件的主服务器二进制日志文件的名称
- `Exec_Master_Log_Pos`: SQL线程执行来自master的二进制日志最后一个事件位置
与上面的`Relay_Master_Log_File`一起，同`Master_Log_File`、`Read_Master_Log_Pos`比较，能看到*SQL线程*是否已经赶上从库本地的IO线程。

- `Slave_IO_Running`：I/O线程是否启动并成功连接到主服务器上
一般和下面的`Slave_IO_Running`和`Seconds_Behind_Master`一起监控主从健康状态
- `Slave_SQL_Running`：SQL线程是否启动
- `Seconds_Behind_Master`: 从属服务器“落后”多少秒
官网的解释是：The number of seconds that the slave SQL thread is behind processing the master binary log。但是当 SBM 为 0 时也不代表一定没有延迟，因为可能因为网络慢的缘故，从库的IO线程传输binlog太慢，它的SQL线程应用日志很容易就赶上relay log，但实际主库产生的binlog比传输的快，就会造成为0的假象。
有时你反复status会发现 Seconds_Behind_Master 的值在0与一个很大的数之间波动，有可能是主库上执行了一个非常大的event，没执行完毕的时候从库SBM显示为0，event执行完成并传输完binlog后，就会显示SBM非常巨大。（我在从机房迁移mysql到阿里云上部分库老出现这种情况，应该跟网络和大event都有关系）。
另外，relay log 中event记录的时间戳是主库上的时间戳，而SQL thread的时间戳是从库上的，如果主库和从库的时间偏差较大，那么这个SBM的意义就基本不存在了。


## 5. 参考

- [高性能Mysql主从架构的复制原理及配置详解](http://blog.csdn.net/hguisu/article/details/7325124)
- [How does MySQL Replication really work?](https://www.percona.com/blog/2013/01/09/how-does-mysql-replication-really-work/)
- [XtraBackup不停机不锁表搭建MySQL主从同步实践](https://segmentfault.com/a/1190000003063874)
- [MySQL复制原理与配置](http://www.simlinux.com/archives/236.html)
- [许多模糊的内容还是看官网的](http://dev.mysql.com/doc/refman/5.6/en/replication-administration-status.html)


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-replica-concept.jpg



---

本文链接地址：http://xgknight.com/2015/12/14/mysql-replicas/

---
