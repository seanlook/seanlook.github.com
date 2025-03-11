---
title: ProxySQL之性能测试对比
date: 2017-04-20 21:32:49
aliases:
- /2017/04/20/mysql-proxysql-performance-test/
tags: [mysql, 中间件, proxysql]
categories:
- MySQL
updated: 2017-04-20 21:32:49
---

本文会通过sysbench对ProxySQL进行基准测试，并与直连的性能进行对比。与此同时也对 Maxscale 和 Qihu360 Atlas 放在一起参考。
提示：压测前确保把query cache完全关掉。

# 1. proxysql vs 直连
## 1.1 select nontrx
```
./bin/sysbench --test=/root/sysbench2/sysbench/tests/db/oltp.lua --mysql-host=10.0.100.36 --mysql-port=6033 --mysql-user=myuser --mysql-password=mypass \
--mysql-db=db15 --oltp-tables-count=20 --oltp-table-size=5000000 --report-interval=20 --oltp-dist-type=uniform --rand-init=on --max-requests=0 --oltp-test-mode=nontrx --oltp-nontrx-mode=select \
--oltp-read-only=on --oltp-skip-trx=on --max-time=120 --num-threads=2 run

num-threads依次加大 2 5 10 20 50 100 200 400
```
{% iframe http://www.tubiaoxiu.com/p.html?s=106165b0eeca215a&web_mode 900 700 %}

<!--
![QPS Trends for ProxySQL](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-perf-qps.png) 
-->
![Response Time Trends for ProxySQL](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-perf-rt.png)  

sysbench线程并发数达到10以下，性能损失在30%以上；达到20，性能损失减少到10%左右。看到proxysql承载的并发数越高，性能损失越少；最好的时候在50线程数，相比直连损失5%。

## 1.2 oltp dml
混合读写测试。proxysql结果图应该与上面相差无几，因为是主要好在计算 query digest 和规则匹配，与select无异，可参考下节的图示。

sysbench 压测命令：
```
./bin/sysbench --test=/root/sysbench2/sysbench/tests/db/oltp.lua --mysql-host=10.0.100.34 --mysql-port=3306 --mysql-user=myuser --mysql-password=mypass \
--mysql-db=db15 --oltp-tables-count=20 --oltp-table-size=5000000 --report-interval=20 --oltp-dist-type=uniform --rand-init=on --max-requests=0 --oltp-read-only=off --max-time=120 \
--num-threads=2 run

num-threads依次加大 2 5 10 16 20 50 100 200 400
分别对PrxoySQL, Maxscale, Atlas, 直连，四种情况做基准测试
```

# 2. proxysql vs maxscale vs atlas
作者自己也有指出，在客户端并发数不高的情况下，maxscale表现比proxysql要好。这里我也特意对maxscale和atlas一起做了个对比。配置基本是最小化的，没有很复杂的规则，只是中间转发。
- ProxySQL  (v1.3.5): mysql-threads=4
- Atlas 360 (v2.2.1): event-threads=4
- maxscale  (v1.4.5): threads=4

** 2.1 select nontrx ** 
![QPS(select) Trends for ProxySQL/Maxscale/atlas](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-perf-qps-maxscale-atlas.png)

oltp混合读写基准测试，没有复杂配置的情况下，ProxySQL与Maxscale神奇般的几乎重合，Qihu360的atlas要弱一些。

** 2.2 oltp dml **  
![QPS(oltp) Trends for ProxySQL/Maxscale/atlas](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-perf-qps-oltp-maxscale-atlas.png)


原始数据：
![ProxySQL Performance Test Source Data](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-perf-qps-src-data.png)

# 3. rewrite vs non-rewrite
下面来测一下 query rewrite 对性能的影响，考虑到将来如果要分表，可以在ProxySQL这一层做，应用端无需改动表名。
为了达到效果，这里rewrite只是为表增加了个别名：
```
-- proxysql admin cli
update mysql_query_rules set match_pattern="(.*)(sbtest\d+)(.*)",replace_pattern="\1\2 as ttt \3" where rule_id >=61 and rule_id <=92;
load mysql query rules to run;
```
sysbench num-threads=20 的结果：

| replace? | qps | response time avg(ms) |
| :---- | ---- | ---- |
| proxysql replace | 15734.49 |17.79 |
| proxysql no-replace | 16764.66 |16.70 |
| 直连 | 18778.43 | 14.91 |

在20个并发线程下，有 rewrite 是 no-rewrite 性能的 93.9% 。测试线程数继续加大到 50，差别更小。

# 4. lots of rules
测试ProxySQL定义的 query rules 数量（并匹配但不apply），对性能的影响。

测试的规则时批量插入大量能匹配sysbench查询的规则，但 mysql_query_rules.apply=0 :
```
insert into mysql_query_rules(active,schemaname,apply,flagIN) values
  (1,'db15',0,0),(1,'db15',0,0),(1,'db15',0,0),(1,'db15',0,0),(1,'db15',0,0), ...

# 2 100 200 400 800 1200 2000 
```
这里偶然发现一个问题，flagIN=0的规则必须要在 !=0 的规则前面，否则flagOUT找不到下一个新链入口.(经作者回复是参数 `mysql-query_processor_iterations` 控制的)
下面的结果是 sysbench num-threads=20 的几轮数据：（由于结果接近，没作图）

| matched rules	 | QPS | RT avg | CPU% |
|----|----|----|----|----|
| 2	| 16741.54 | 16.69 | 151  |
| 100 | 16743.54 | 16.69 | 152 |
| 200 | 16749.94 | 16.71 | 159 |
| 400 | 16556.09 | 16.91 | 176 |
| 800 | 16522.02 | 16.94 | 203 |
| 1200 | 16477.70 | 16.99 | 220 |
| 2000 | 16333.59 | 17.14 | 263 |

看到匹配到的规则随着增多，QPS变化不大，只是略微下降；平均响应时间增加在3%以内；倒是ProxySQL对CPU的负载增加比较明显，匹配的规则从 2 个增加到 2000，cpu使用增加了 74% 。 

参考：
- https://www.percona.com/blog/2017/04/10/proxysql-rules-do-i-have-too-many/#comment-10967989

---

原文连接地址：http://xgknight.com/2017/04/20/mysql-proxysql-performance-test/

---
