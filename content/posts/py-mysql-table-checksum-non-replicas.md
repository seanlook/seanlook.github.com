---
title: MySQL非主从环境下数据一致性校验及修复程序
date: 2016-11-20 16:32:49
aliases:
- /2016/11/20/py-mysql-table-checksum-non-replicas/
tags: [mysql, python, pt-table-checksum]
categories:
- Python
updated: 2016-11-20 16:32:49
---

## 1. 简介

项目地址：https://github.com/seanlook/px-table-checksum

主从环境下数据一致性校验经常会用 pt-table-checksum 工具，它的原理及实施过程之前写过一篇文章：[生产环境使用 pt-table-checksum 检查MySQL数据一致性](http://xgknight.com/2015/12/29/mysql_replica_pt-table-checksum/)。但是DBA工作中还会有些针对两个表检查是否一致，而这两个表之间并没有主从关系，pt工具是基于binlog把在主库进行的检查动作，在从库重放一遍，此时就不适用了。

总会有这样特殊的需求，比如从阿里云RDS实例迁移到自建mysql实例，它的数据传输服务实现方式是基于表的批量数据提取，加上binlog订阅，但强制row模式会导致pt-table-checksum没有权限把会话临时改成statement。另一种需求是，整库进行字符集转换：库表定义都是utf8，但应用连接使用了默认的 latin1，要将连接字符集和表字符集统一起来，只能以latin1导出数据，再以utf8导入，这种情况数据一致性校验，且不说binlog解析程序不支持statement（如canal），新旧库本身内容不同，pt-table-checksum 算出的校验值也会不一样，失效。

所以才萌生了参考 pt-table-checksum 自己写了一个：px-table-checksum 。

## 2. 实现方法
整体思路是借鉴pt-table-checksum，从源库批量（即chunk）取出一块数据如1000行，计算CRC32值，同样的语句在目标库运行一遍，结果都存入另一个库，最后检查对应编号的chunk crc值是否一致。知道不一致还不行，得能否快速方便的修复差异，所以继续根据那些不一致的chunk，去目标库和源库找到不一致的行，是缺失，还是多余，还是被修改了，然后生成修复sql，根据指示是否自动修复。

那么问题就在于：

1. 如何确定批次，也就是下一个chunk该怎么取？
我还没想做到pt-table-checksum那样，可以根据负载动态调整chunk大小，甚至活跃线程数超过阀值就暂停检查，上来工作量就太大了。目前每次计算的chunk的行数是固定的，可以配置1000或2000等。
所以就要用到分页查询，根据（自增或联合）主键、唯一索引，每次limit 1000后升序取最后一条，作为下一批的起始。所以要分析表上的键情况，组合查询条件。目前仅能检查有主键或唯一所以的表。

2. 如何保证源库和目标库，运行的sql一样？
之前一版是目标库和源库，以多线程各自计算chunk，入库，后来才意识到严重的bug：比如同样是取1000行，如果目标库少数据，那么下一个chunk起始就不一样，比较的结果简直一塌糊涂。
所以必须保证相同编号的chunk，起点必须相同，所以想到用队列，存放在源库跑过的所有校验sql，模拟pt工具在目标库重放。考虑到要多线程同时比较多个表，队列可能吃内存过大，于是使用了redis队列。

3. 直接在数据库中计算crc32，还是取出数据在内存里计算？
翻了pt-table-checksum的源码，它是在数据库里计算的。但是第一节里说过，如果目标库和源库要使用不同的字符集才能读出正确的数据，只能查询出来之后再比较。所以 px-table-checksum 两种都支持，只需指定一个配置项。

4. 同时检查多个表，源库sql挤在队列，目标库拿出来执行时过了1s，此时源库那条数据又被修改了一次同步到了目标库，会导致计算结果不一致，实则一致，怎么处理
无法处理，是px-table-checksum相比pt-table-checksum最大的缺陷。
但为了尽可能减少此类问题（比如主从延迟也可能会），特意设计了多个redis队列，目标库多个检查线程，即比如同时指定检查8个表，源库检查会有8个线程对应，但可以根据表的写入情况，配置4个redis队列（目前是随机入列），10个目标库检查线程，来减少不准确因素。
但站在我的角度往往来说，不一致的数据会被记录下来，如果不多，人工核对一下；如果较多，就再跑一遍检查，如果两次都有同一条数据不一致，那就有情况了。

## 3. 限制
1. 如果检查期间源表数据，变化频繁，有可能检查的结果不准确
也就是上面第4点的问题。很明显，这个程序每个检查的事务是分开的，不像pt工具能严格保证每条检查sql的事务顺序。但有不一致的数据再排查一下就ok了。实际在我线上使用过程中，99.9%是准确的。
<!-- more -->
2. 表上必须有主键或唯一索引
程序会检查，如果没有会退出。

3. varbinay,blob等二进制字段不支持修复
其实也不是完全不支持，要看怎么用的。开发如果有把字符先转成字节，再存入mysql，这种就不支持修复。是有办法可以处理，那就是从源库查时用 `hex()`函数，修复sql里面`unhex()`写回去。

## 4. 使用说明
该python程序基于2.7开发，2.6、3.x上没有测试。使用前需要安装 `MySQLdb`和`hotqueue`：
```
$ sudo pip install MySQL-python hotqueue
```
要比较的表和选项，使用全配置化，即不通过命令行的方式指定（原谅命令行参数使用方式会额外增加代码量）。
### 4.1 `px-table-checksum.py`
主程序，运行`python px-table-checksum.py` 执行一致性检查，但一定了解下面的配置文件选项。

### 4.2 `settings_checksum.py`
配置选项
  - `CHUNK_SIZE`: 每次提取的chunk行数
  - `REDIS_INFO`: 指定使用redis队列地址
  - `REDIS_QUEUE_CNT`: redis队列数量，消费者（目标库）有一一对应的线程守着队列
  - `REDIS_POOL_CNT`: 生产者（源库）redis客户端连接池。这个设计是为了缓解GIL带来的问题，把入列端与出列端分开，因为如果表多可能短时间有大量sql入队列，避免hotqueue争用
  - `CALC_CRC32_DB`: True 表示在db里面计算checksum值，False表示取出chunk数据在python里面计算。默认给的值是根据连接字符集定的。

  - `DO_COMPARE`: 运行模式
   - 0: 只提取数据计算，不比较是否一致。可以在之后在模式2下只比较
   - 1: 计算，并比较。常用，每次计算之前会删除上一次这个待检查表的结果，比较的结果只告诉哪些chunk号不一致。
   - 2: 不计算，只从t_checkum结果比较。常用，计算是消耗数据库资源的，可以只对已有的checksum计算结果比较不一致的地方。类似pt工具的`--replicate-check-only`选项。
  - `GEN_DATAFIX`:
  与`DO_COMPARE`结合使用，为 True 表示对不一致的chunk找到具体不一致行，并生成修复sql；为 False 则什么都不做。
  - `RUN_DATAFIX`:
  与`GEN_DATAFIX`结合使用，为 True 表示对生成的修复sql，在目标库执行。需要谨慎，如果哪一次设置了修复，记得完成后改回False，不然下次检查另一个表就出意外了，所以特意对这个选项再加了一个确认提示。

  - `DB_CHECKSUM`: 一个字典，指定checksum的结果存到哪里
  配置文件有示例，必须指定 `db_name`，表会自动创建。

### 4.3 `settings_cs_tables.py`
上面的配置文件可以认为是用于控制程序的，这个配置文件是指定要校验的源库和目标库信息，以及要检验哪些表。
- `TABLES_CHECK`: 字典，指定要检查哪些表的一致性，db名为key，多个table名组成列表为value。暂不支持对整个db做检查，同时比较的表数量不建议超过8个
- `DB_SOURCE`: 字典，指定源库的连接信息
- `DB_SOURCE`: 字典，指定目标库的连接信息

## 5. 示例：
```
Starting checksum thread for table: db1.t_test_201308 (192.168.1.122:3306)
Before checksum: create table if not exists t_checksum
Before checksum: delele old data from t_checksum if exists for table:  db1.t_test_201308
Caculate crc32 in program instead of db.(this program need more memory and more db net traffic, but convert charset)
Caculating checksums:  192.168.1.122:3306 db1.t_test_201308
TARGET: ('192.168.1.121:3306', 't_test_201308', 1, 'db1', '0', u'1495969', 451060506)
TARGET: ('192.168.1.121:3306', 't_test_201308', 2, 'db1', u'1495969', u'1502593', -678155635)
...
Starting checksum thread for table: db1.t_test_201408 (192.168.1.122:3306)
Before checksum: delele old data from t_checksum if exists for table:  db1.t_test_201408
Caculate crc32 in program instead of db.(this program need more memory and more db net traffic, but convert charset)
Caculating checksums:  192.168.1.122:3306 db1.t_test_201408
TARGET: ('192.168.1.121:3306', 't_test_201408'TARGET: ('192.168.1.121:3306', 't_test_201408', 9, 8, 'db1', u'3836877', u'3845812', , 'db1', u'3845812'373759054)
...
源实例 192.168.1.122:3306 db1.t_test_201308  计算checksum结束！
db conection closed.
Checksum thread ended for table: db1.t_test_201308 (192.168.1.122:3306)
...
源实例 192.168.1.122:3306 db1.t_test_201408  计算checksum结束！
消费sql 0 退出！！
消费sql -1 退出！！

################################################################################
Start compare chunk's crc32 for table: [ db1.t_test_201308 ]
表 db1.t_test_201308 数据一致

################################################################################
################################################################################
Start compare chunk's crc32 for table: [ db1.t_test_201408 ]
表 db1.t_test_201408 数据不一致chunk数：10
--------------------------------------------------------------------------------

该chunk [1] 存在行内容不一致, CRC32: src(828649697) rgt(-1396224393)
去源库和目标库获取chunk[1]不一致行：
  TO insert or update:  [u'3761994']
aliases:
- /2016/11/20/py-mysql-table-checksum-non-replicas/
  TO delete:  []

该chunk [5] 存在行内容不一致, CRC32: src(1513453680) rgt(-1614463460)
去源库和目标库获取chunk[5]不一致行：
  TO insert or update:  [u'3806841']
aliases:
- /2016/11/20/py-mysql-table-checksum-non-replicas/
  TO delete:  []
```

---

原文链接地址：http://xgknight.com/2016/11/20/py-mysql-table-checksum-non-replicas/

---
