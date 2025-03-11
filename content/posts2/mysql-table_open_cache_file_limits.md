---
title: table_open_cache 与 table_definition_cache 对MySQL(内存)的影响
date: 2017-10-13 16:32:49
tags: [mysql, table_cache]
categories:
- MySQL
updated: 2017-10-13 16:32:49
---

# 1. 现象，内存使用大
首先说一下最近遇到的一个现象，因为分库的缘故，单实例里面的表的数量增加了20倍，总数将近达到10000个。在开发环境明显感觉到执行简单查询都很慢，在processlist里面看到状态 opening table 达到好几秒但数据库并没有什么负载。本能的想到应该要加大 `table_open_cache`，可是加大后发现MySQL刚启动 RES 就占用了2.5G内存，之前才500-600M的样子。

只是将 `table_open_cache` 从默认的2000，增加到10000（先不论这个值合不合理），就独占了2G的内存，这对于生产环境内存浪费是不可接受的。还好，关于这个问题的讨论有不少，感兴趣的话可以阅读 [#bug 68287](https://bugs.mysql.com/bug.php?id=68287), [#bug 68514](https://bugs.mysql.com/bug.php?id=68514), [12015-percona-5-6-14-56-very-high-memory-usage](https://www.percona.com/forums/questions-discussions/mysql-and-percona-server/percona-server-5-6/12015-percona-5-6-14-56-very-high-memory-usage)。

Oracle官方工程师并不认为这是个bug，导致初始化分配这么多内存的原因是，**开启了 Performance_Schema** 。P_S测量数据库的性能指标，需要提前一次性分配内存，而不是随着数据库运行逐渐申请内存。

下表是不同参数组合下内存占用的测试结果：
![](http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql_table_cache_1.png)


（注：可以通过这个来查看PFS里面哪些占内存比较多，`mysql -hxxxx -Pxxx -uxx -pxx -e "show engine performance_schema status"|grep memory|sort -nr -k3 |head` ）

对于 table_open_cache 设置的非常大的情况下，即使还有许多cache多余，但P_S都需要分配这个数量的内存。解决这个内存大的问题有3个方向：
1. table_open_cache, table_definition_cache, max_connections 设置合理
2. 关闭 performance_schema
3. 保持 PFS 开启，关闭测量 max_table_instances和max_table_handles  
  - performance_schema_max_table_instances: 最大测量多少个表对象  
    对应 (pfs_table_share).memory，我的环境里固定 277600000 bytes
  - performance_schema_max_table_handles: 最大打开表的总数  
    对应(pfs_table).memory，随着 table_open_cache 的增大而增大

关闭的方法是在my.cnf里面设置以上变量为 0 。默认是 -1 ，表示 autosize，即根据 table_open_cache/table_def_cache/max_connections 的值自动设置，相关代码 `pfs_autosize.cc`：
```
PFS_sizing_data *estimate_hints(PFS_global_param *param)
{
  if ((param->m_hints.m_max_connections <= MAX_CONNECTIONS_DEFAULT) &&
      (param->m_hints.m_table_definition_cache <= TABLE_DEF_CACHE_DEFAULT) &&
      (param->m_hints.m_table_open_cache <= TABLE_OPEN_CACHE_DEFAULT))
  {
    /* The my.cnf used is either unchanged, or lower than factory defaults. */
    return & small_data;
  }

  if ((param->m_hints.m_max_connections <= MAX_CONNECTIONS_DEFAULT * 2) &&
      (param->m_hints.m_table_definition_cache <= TABLE_DEF_CACHE_DEFAULT * 2) &&
      (param->m_hints.m_table_open_cache <= TABLE_OPEN_CACHE_DEFAULT * 2))
  {
    /* Some defaults have been increased, to "moderate" values. */
    return & medium_data;
  }

  /* Looks like a server in production. */
  return & large_data;
}
```
在阿里RDS中，performance_schema_max***系列变量不能单独disable，只能全局关闭PFS。这里我们尝试寻求一个合理table_cache的范围。
<!-- more -->
那么 `table_open_cache` 与 `table_definition_cache` 设置一个什么值才算合理呢？

# 2. 理解 table_open_cache 与 table_definition_cache
来理解一下 `table_open_cache` 到底是来干嘛的，文档里或者网上的文章，通通解释是“用于控制MySQL Server能同时打开表的最大个数”。如果继续问这个个数怎么算呢？

我来尝试解答一下。MySQL是多线程的，多个会话上有可能会同时访问同一个表，mysql是允许这些会话各自独立的打开这个表，而表最终都是磁盘上的数据文件。(默认假设innodb_file_per_table=1)，打开文件需要获取文件描述符(File Descriptor)，为了加快这个open table的速度，MySQL在Server层设计了这个cache：

> The idea behind this cache is that most statements don't need to go to a central table definition cache to get a TABLE object and therefore don't need to lock LOCK_open mutex. Instead they only need to go to one Table_cache instance (the specific instance is determined by thread id) and only lock the mutex protecting this cache. DDL statements that need to remove all TABLE objects from all caches need to lock mutexes for all Table_cache instances, but they are rare.

table_cache 减少了表级别 LOCK_open 这个互斥量的获取，改用获取 表对象缓存实例 列表的mutex。简化成如下过程：

  1. 假设当前并发200个连接，table_open_cache=200，其中有50连接都在访问同一张表
  2. mysql内部维护了一个 unused_table_list，在a表上的请求结束后，会把这个thread刚才用过的 table object 放入unused_table_list
  3. 每个表有个key，可以通过hash快速定位到表a的所有可用object，如果后面一下子100个连接上来访问表a，内部会先从 unused_table_list 去找这个表已经缓存过的对象(get_table)，比如前50个可以直接拿来用(unlink_unused_table)
  4. 后50个则需要调用系统内核，拿到文件描述符。
  5. 用完之后会，放回到unused_table_list，并将这个表的key放到hash表的前面。
  6. 如果缓存的对象个数超过了 table_open_cache，则会通过LRU算法，把认为不用的表对象逐出。

从上面的过程应该很容易理解 table_open_cache 与 table_definition_cache 的区别。
- `table_def_cache` 也是一个key/value形式的hash表，但每个表只有一个值，值/对象的内容就是表的元数据信息(Data Dictionay，frm文件里面的信息)，如表结构、字段、索引，它是一个全局的结构，并且不占用文件描述符。
- 而`table_open_cache`的key/value的值是一个列表，表示这个表的多个 Table_cache_element，他们共用这个表的 definition (代码层定义为TABLE_SHARE对象)。

(注：我们在row格式的binlog里面看到的 table_map_id 就是在 TABLE_SHARE 里面定义的，表结构变更、缓存被逐出，都会导致 table_map_id 递增。)

## 2.1 源码说明
源代码里面关键函数
- sql_base.cc:
  - `open_table()` 打开表的入口
  打开之前会判断mdl锁条件满不满足，再调用 get_table() 尝试从cache里面获取
  如果找到，还要判断版本信息，goto table_found
  如果没找到，注意get_table()接收了一个 table_share 参数，即使没找到table cache，也努力获取table definition，如果拿到table_share则要获取一次LOCK_open互斥量，增加表的引用计数。
  make a new table: 调用 open_table_from_share() 从磁盘上打开表
  调用 add_used_table() 将表对象放入缓存，table_open_cache_misses++
  - `get_table_share()` 从 table definition cache 获取表定义信息
    如果cache中没有，则调用 table.cc:open_table_def() 从文件系统上读取
    
- table_cache.h:Table_cache::  
  - `m_unused_tables`  
    该列表内容是table cache中没有被其它线程使用的table object。最近使用过的table object会被添加到列表的尾部，头部就成为最近没被使用的(LRU)
  - `m_table_count`  
    table objects个数，包括正在使用中，以及unused  
    所有table cache instances中这个count加起来，就是 Open_tables 的结果
  - `get_table()` 根据key(表名)从cache hash里面获取 unused table object  
    得到之后，将这个object从列表unlink掉，并且放入used table list
  - `add_used_table()` 将新创建的 table object 放入table cache  
    这是说明当前连接要打开的表在cache里面没有，所以要自己打开，并且放入used table list
  - `release_table()` 用完后将表对象放回table cache的unused列表  
    如果table_share版本比较旧，则直接remove掉
  - `remove_table()`  
  - `free_unused_tables_if_necessary()` 
    每次 add_used_table() 都会调用，判断是否需要从 table cache object list清除多余的cache，需要锁定LOCK_open。调用remove_table()  
    清除条件：m_table_count > table_cache_size / table_cache_instances  

- table.cc:
  - `open_table_from_share()`
    根据 table_share 信息来打开表。调用 outparam->file->ha_open()，*too many files opened* 错误在这里抛出
  - `open_table_def()`
    从 frm 中读取表定义

以上过程没有考虑视图、临时表、分区表。table_cache虽然会有额外的内存开销，但简化了对表状态的维护，打开表这个动作因为省去了获取 LOCK_open mutex 以及直接操作打开数据文件，而变得高效。
这部分参考taobao数据库内核月报的2篇文章，会比较清晰：
1. open file limits： http://mysql.taobao.org/monthly/2015/08/07/
2. MySQL表定义缓存：http://mysql.taobao.org/monthly/2015/08/10/

# 3 设置参考因素
## 3.1 table_open_cache
`table_open_cache` 默认值 Version<=5.6.7: 400, Version>=5.6.8: 2000，设定它的值有3个因素：

1. **最大并发连接数**
  这是最重要的考量。假设业务高峰期 **活跃并发** 连接是200，60%是单表查询，30%是两个表join，5%是三个表join，5%会创建临时表。那么table_open_cache可以是：
  200 × (60% × 1 + 30% × 2 + 5% × 3 + 5%  × 2) = 290
  当然这里不是要如何精确的计算，只是说明有哪些需要考虑的。网上有大部分文章都讲设置 max_connections * N，N是sql里面表的最大个数，我个人觉得如果max_connections值超过2000的话，就不要这样算，因为max_connection一般是不允许达到的，高峰期活跃并发连接数才是比较好的基准。

2. **存储引擎**
  - MyISAM引擎  
    因为myisam数据文件和索引是分开存放的，所以**第一次**打开表时需要2个描述符，后续如果并发2个会话访问该表，另一个会话只需要多开一个数据文件的描述符。索引文件描述符可被线程共享。因此它所需要的 table_cache 的值并不是简单上面的值的2倍，而是跟表的访问分布有关。当然现在已经几乎不用MyISAM引擎了。  
    Merge引擎也类似，因为Merge表可以有多个底层表，需要多个文件描述符。

  - InnoDB引擎  
    `table_open_cache`对InnoDB引擎其实作用不大，它是Server层的机制，而InnoDB不依赖server层去管理表空间，它使用自己的内部函数去打开ibd，创建handler来操作表。（handler只是内存对象，不牵涉文件操作。从实验结果看来，innodb每个表最多只有一个File Descriptor打开，myisam表如果并发访问一个表，会打开多个FD并cache起来） 

    注： `flush tables` 命令会关闭所有当前打开的表对象缓存/handler，所以状态变量 `open_tables` 会置0，但`opened_tables(_definition)`、`Table_open_cache_misses(_hits)`只会在实例重启后置0。对MyISAM引擎来说，它还会释放MYI/MYD文件描述符，而InnoDB引擎则不会释放ibd文件描述符。
    ```
    mysql> show variables like "table_%";
    +----------------------------+-------+
    | Variable_name              | Value |
    +----------------------------+-------+
    | table_definition_cache     | 1400  |
    | table_open_cache           | 2000  |
    | table_open_cache_instances | 1     |
    +----------------------------+-------+
    3 rows in set

    mysql> show global status like "%open%";
    +----------------------------+-----------+
    | Variable_name              | Value     |
    +----------------------------+-----------+
    | Com_ha_open                | 0         |
    | Com_show_open_tables       | 0         |
    | Innodb_num_open_files      | 364       |  -- 打开的ibd文件的数量，打开后一般不会关闭，除非超过了 innodb_open_files 的设定
    | Open_files                 | 52        |  -- 打开的常规文件数量，如slow_log,error_log等，不包含socket和具体存储引擎有关的文件，所以一般都无需关注这个，它与innodb_open_files也没关系
    | Open_streams               | 0         |
    | Open_table_definitions     | 470       |  -- 当前缓存了多少.frm文件
    | Open_tables                | 448       |  -- 当前table_cache里面缓存的table object数量
    | Opened_files               | 35617170  |
    | Opened_table_definitions   | 117134    |
    | Opened_tables              | 117409    |  -- 自总MySQL启动以来打开表的总次数，如果在缓存中找到直接使用，不会增加这个值
    | Slave_open_temp_tables     | 0         |
    | Table_open_cache_hits      | 130148442 |
    | Table_open_cache_misses    | 117404    |
    | Table_open_cache_overflows | 0         |
    +----------------------------+-----------+
    14 rows in set

    mysql> flush tables;
    Query OK, 0 rows affected

    mysql> show global status like "%open%";
    +----------------------------+-----------+
    | Variable_name              | Value     |
    +----------------------------+-----------+
    | Com_ha_open                | 0         |
    | Com_show_open_tables       | 0         |
    | Innodb_num_open_files      | 364       |
    | Open_files                 | 4         |
    | Open_streams               | 0         |
    | Open_table_definitions     | 6         |
    | Open_tables                | 6         |
    | Opened_files               | 35617220  |
    | Opened_table_definitions   | 117140    |
    | Opened_tables              | 117415    |
    | Slave_open_temp_tables     | 0         |
    | Table_open_cache_hits      | 130148523 |
    | Table_open_cache_misses    | 117410    |
    | Table_open_cache_overflows | 0         |
    +----------------------------+-----------+
    14 rows in set
    ```

3. **opened_tables**  
根据第一步的最大并发数设定的值不一定准确，在MySQL运行一段时间后，可以观察 opened_tables 增加的速度，决定是否需要扩大 table_open_cache。如果查询里面有许多要用到temporary table，这个值也会增加的很快，此时也可以比较 Table_open_cache_hits 与 Table_open_cache_misses 的值，正常的话 hits/(hits+misses ) 应该在99.9%以上。

还有一个标准，`Open_tanles`的值如果与 `table_open_cache`很接近，那么也要考虑增大 table_open_cache 。

但不要设置的太大，大部分情况不要超过10000，原因一是如第一部分看到，performance_schema会分配过多内存；二是cache的查找速度会因为越来越多而变慢；三是某些情况不缓存也许更好，比如几万张表，他们都很均匀的被使用，如果不全部缓存起来，那么缓存始终会被不断的逐出更新，效率反而更低。

# 3.2 table_definition_cache 与 innodb_open_files
至于 table_definition_cache，默认值是 *400 + (table_open_cache / 2)*，默认最大2000。如果实际表的数据量比较多，最好是能够把元数据全部cache起来，设置与表的总数量差不多大就行。

InnoDB engine层有自己参数 `innodb_open_files`，限制同时打开 ibd 文件的句柄数，作用与 table_definition_cache 相同，逐出策略也是一样采用LRU算法。innodb读取INNODB_SYS_TABLES,INNODB_SYS_COLUMNS,INNODB_SYS_FIELDS,INNODB_SYS_INDEXES等数据字典，放入 table_dict 。当需要访问这个表的时候，创建 handler 对象。
这两个变量本身没啥关系，但是设置不合理的时候mysql会改变它的值：

innodb_open_files的值如果设置大于 open_files_limit，且大于table_open_cache，那么会自动设置为table_def_cache大小。`innobase\handler\ha_innodb.cc`：
```
  if (innobase_open_files < 10) {
    innobase_open_files = 300;
    if (srv_file_per_table && table_cache_size > 300) {
      innobase_open_files = table_cache_size;
    }
  }

  if (innobase_open_files > (long) open_files_limit) {
    fprintf(stderr,
                      "innodb_open_files should not be greater"
                      " than the open_files_limit.\n");
    if (innobase_open_files > (long) table_cache_size) {
      innobase_open_files = table_cache_size;
    }
  }
```

--- 

这里顺便提一下 `open_file_limit`, 它限制的是mysqld进程总共能够打开文件描述符的个数，是个Server层的参数，它的值应该要小于服务器的最大限制，否则OS层报错会比mysql error log报错更惨。
关于它的计算公式，网上有很多，不属本文的内容，感兴趣可以参考 http://www.cnblogs.com/zhoujinyi/archive/2013/01/31/2883433.html 


参考
- http://hidba.org/?p=170
- https://dev.mysql.com/doc/refman/5.6/en/table-cache.html
- http://mysql.taobao.org/monthly/2015/08/07/
- https://dev.mysql.com/doc/dev/mysql-server/8.0.0/classTable__cache.html
- http://www.orczhou.com/index.php/2010/10/mysql-open-file-limit/


---

本文链接地址：http://xgknight.com/2017/10/13/mysql-table_open_cache_file_limits/

---
