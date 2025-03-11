---
title: ProxySQL监控方案
date: 2017-07-16 21:32:49
tags: [mysql, middleware, proxysql]
categories:
- MySQL
updated: 2017-07-18 21:32:49
---

ProxySQL能监控的信息不多，而且大部分是统计信息，不是性能数据。

```
mysql> show tables from stats;
+--------------------------------+
| tables                         |
+--------------------------------+
| global_variables               |
| stats_mysql_commands_counters  |
| stats_mysql_connection_pool    |
| stats_mysql_global             |
| stats_mysql_processlist        |
| stats_mysql_query_digest       |
| stats_mysql_query_digest_reset |
| stats_mysql_query_rules        |
+--------------------------------+
```

主要关心的指标都在表 `stats_mysql_global` 里面，源代码 diamond 目录下有个 *proxysqlstat.py* 脚本，是通过`SHOW MYSQL STATUS`命令，由diamond收集进程将指标上报到Graphite。有以下几个Metrics：
- 并发数
    - Active_Transactions
    - Questions
- 连接相关
    - Client_Connections_connected
    - Server_Connections_connected
    - Server_Connections_aborted
- 内存相关
    - Query_Cache_Entries
    - Query_Cache_Memory_bytes
    - SQLite3_memory_bytes
    - ConnPool_memory_bytes
- 流量相关
    - mysql_backend_buffers_bytes
    - mysql_frontend_buffers_bytes
    - mysql_session_internal_bytes
- 其它
    - MySQL_Monitor_Workers
    - MySQL_Thread_Workers

但是这些远远不够，还有以下更值得关心的指标：
表 `stats_mysql_connection_pool`:
- 对后端DB请求的网络延时 Latency
- 对后端各个DB的请求数 Queries
- 后端各个DB的当前活跃连接数 ConnUsed
- 后端DB的状态 status

表 `stats_mysql_processlist`:
- 每个用户的当前的连接数

表 `stats_mysql_query_digest`:
- 各个类型的sql请求量比例、趋势



在我们的环境下使用的是 InfluxDB + Grafana，通过telegraf收集上报。上述所有的监控脚本见仓库 https://github.com/seanlook/proxysql_tools ：

- `proxysql_stats.py`:
    - 收集 stats_mysql_global 和 stats_mysql_connection_pool 中的信息，打印出 influxdb 数据上报格式

- `proxysql_stats_digest.py`:
    -  收集 sql digest，收集的信息用于展示每类sql的执行趋势。
    因为数据是累计值，所以这里做了增量计算，然后一方面上报给influxdb，一方面存入mysql，可以做更多用途。mysql的表结构 proxysql_stats_digest.sql 。
    建议收集频率不要过高，比如10分钟一次。
 
- `grafana_proxysql_stats.json`:
    - Grafana Dashboard，直接导入可用 。

除此外，还需要对proxysql进程的监控，如内存占用、CPU使用，这部分通过telegraf的 procstat 插件去做：
```
[[inputs.procstat]]
    exe = "proxysql"

[[inputs.exec]]

  # the command to run
  command = "/etc/telegraf/telegraf.d/proxysql_stats.py"

  ## Timeout for each command to complete.
  timeout = "10s"

  data_format = "influx"
```

对后端DB status和proxysql端口存活，设置告警。这样就有一个相对完整的ProxySQL监控方案了。
<!-- more -->
面板示例：

![Geneal](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-monitor-1.png)
![Queries](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-monitor-2.png)
![Process](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-monitor-3.png)


---

原文连接地址：http://xgknight.com/2017/07/16/mysql-proxysql-monitor/

---
