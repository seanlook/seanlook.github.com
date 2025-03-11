---
title: ProxySQL之改进patch：记录查询sql完整样例与合并digest多个?
date: 2017-04-27 15:32:49
tags: [mysql, 中间件, proxysql]
categories:
- MySQL
updated: 2017-04-28 15:32:49
---

近期一直在思考sql上线审核该怎么做，刚好接触到 ProxySQL 这个中间件，内置了一个计算sql指纹的功能，但是没有记录原始的sql语句。当前正有个紧急的拆库项目也希望知道库上所有的查询。于是把ProxySQL的代码下了回来研究了几天，改了把，加入了两个功能：

1. 在 `stats_mysql_query_digest` 表上增加 `query_text` 字段，当第一次出现这个digest_text时，把原始sql记录下来。
2. 修改计算指纹的模块，对 IN或者 VALUES 后面的多个 `?` 合并。这个是目前 `c_tokenizer.c` 文件里没有做的，用到底1点上可以避免重复记录。

效果：
![proxysql-querytext-sample-digest](http://github.com/seanlook/sean-notes-comment/raw/main/static/proxysql-querytext-sample-digest.png)

多个 `?` 被折叠成 `?,`，有些意外情况时 `??`，因为后面一些多余空格的缘故，没有像 *pt-fingerprint* 那样完全模糊化，像这里digest就保留了大小写、去除重复空格、保留 \` 分隔符。但仅有的几种意外情况是可以接受的。

后面的 query_text 列也有些未知情况，就是末尾会加上一些奇怪的字符，还在排除，但大体不影响需求。

代码是基于最新 v1.3.6 稳定版修改的，查看变更 https://github.com/sysown/proxysql/compare/v1.3.6...seanlook:v1.3.7-querysample_digest 

多个 `?` 合并只涉及到 *c_tokenizer.c* 文件，分别在flag=4（处理 `'abc','def'` 的情况）和flag=5（处理 `1,2, 3` 的情况）加入判断：
```
// wrap two more ? to one ?,
if (*(p_r_t-2) == '?' && (*(p_r_t-1) ==' ' || *(p_r_t-1) == ',' || *(p_r_t-1) == '?')){
    *(p_r-1) = ',';
}
else
    *p_r++ = '?';
```

然后在 line:450 左右 COPY CHAR 的时候进行一次过滤：
```
// COPY CHAR
// =================================================
// wrap two more ? to ?,
if ((*s == ' ' || *s == ',') && (*(p_r_t-1) == '?' || *(p_r_t-1) == ',' || *(p_r_t-1) == ' ')) {
    if (*(p_r_t-1) == ' ' && *(p_r_t-2) == '?')
        *(p_r-1) = ',';  // p_r may be changed in line:435:is_digit_string
}
else {
```

这部分代码调试花了不少功夫，一是理清逻辑，而是意外情况处理。变量的用途注释不清晰，几年没写C，不得不动用 gdb 来跟踪调试，怀念大学时用IDE的日子。

<!-- more -->

加 query_text 字段，在用 gdb 理清c++函数间调用关系的之后，改起来还是比较容易：

1. *MySQL_Session.cpp:Query_Info::init* 里面会将连接会话的sql信息临时存起来
2. *MySQL_Session.cpp:Query_Info::query_parser_init* 调用 *Qurey_Processor.cpp:Query_Processor::query_parser_init*，里面会调用上面 *c_tokenizer.c* 来处理digest_text并计算得到digest
3. 继而是 Query_Processor 类骨规则路由函数 *process_mysql_query*，但这与我们的改动无关
4. 路由完成后，调用 *query_parser_update_counters* 函数来更新统计信息，改动从这里开始。从 sess 里拿到原始的sql，把地址传递给 *update_query_digest()*
5. *Query_Processor::update_query_digest* 方法会判断当前digest是否已存在 *digest_umap.find(qp->digest_total)*
  - 如果不是第一次出现，则更新 `last_seen` 时间
  - 如果是第一次出现，则 *new QP_query_digest_stats* 对象，就在这个地方把sql传过去。（Query_Processor.cpp:1026,1028）
6. 在 `QP_query_digest_stats` 加入 `query_text` 字段并在析构函数里初始化，同时记得free掉
  这个地方一度出现 qt 的值在赋给 query_text 的时候，被莫名的吃掉，猜想应该是内存分配的时候被擦掉了，请了公司C++大神涛哥一起调试看了下，是传过来长度截取不对。
  现在是没有这个问题，但是会随机性出现本文开头所说，sql末尾出现意外字符。还需要进一步排查。
7. 修改操作sqlite的命令
  - *Query_Processor.cpp*：*SQLite3_result * Query_Processor::get_query_digests()*
  - *ProxySQL_Admin.cpp*：修改 `stats_mysql_query_digest` 表定义，以及插入sql的模板。
    这个地方参数漏了一个导致proxysql crash，编译的时候建议把 Makefile中的 `-O2` 改成 `-O0`，这样gdb调试的时候不会优化输出，容易跟踪。


这些改动对于c++程序员来说，小菜一碟，但对于我一个DBA来说，总算啃下来了。主要是考虑功能急用，提交 issue 等作者renecannao发版也是太慢。
现在可以愉快的收集所有sql了，接下来就是新产生的sql进行自动化审核。

以上两点特性对于升级来讲是无障碍的，因为 `stats_mysql_query_stats` 在内存里，重启之前字段就加上了，无需改动proxysql.db里面的内容。代码在我fork仓库的 [**v1.3.7-querysample_digest**](https://github.com/seanlook/proxysql/tree/v1.3.7-querysample_digest) 分支，我也已提交 [pull request](https://github.com/sysown/proxysql/pull/1010) 给作者合并。等消息中……


---

原文连接地址：http://xgknight.com/2017/04/27/mysql-proxysql-patch-querytext-sample/

---
