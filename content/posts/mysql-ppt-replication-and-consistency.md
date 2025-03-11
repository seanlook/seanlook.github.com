---
title: MySQL复制与数据一致性 分享
date: 2018-03-22 21:32:49
aliases:
- /2018/03/22/mysql-ppt-replication-and-consistency/
tags: [mysql, 分享]
categories:
- MySQL
updated: 2018-03-22 21:32:49
---

这是针对公司内部的一个分享，主题是去年10月份就想好的，中间因为一些项目，也包括自己的拖延症，ppt一直没准备好。

在临近快要辞职的时候，还是想兑现一下承诺，加班加点完成了。

分享的内容包括：

1. binlog介绍
  我们有不少项目依赖于binlog同步数据，所以对binlog的格式以及内部结构进行了简单介绍

2. innodb事务的提交过程
  主要是两阶段提交的一些概念和原理，与下面的组提交原理一起，方便后面对崩溃恢复机制的理解

3. 组提交
  着重介绍组提交的概念，以及它的实现。为下面的并行复制做铺垫

4. 介绍MySQL复制流程
  种类包括异步复制、半同步复制、增强半同步复制和并行复制，顺便结束了复制延迟常见的原因

5. 基于上面的原理，介绍主库、从库分别在异常宕机的情况下，如何保证数据一致的

6. 高可用类型
  这部分由于时间的关系，没有准备，并且本身也是一个很大课题，所以干脆就去掉了

演示稿中穿插了一些思考题，感兴趣的朋友不妨思考思考。

{% pdf http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-replication-and-consistency.pdf 1000 800 %}


---

原文连接地址：http://xgknight.com/2018/03/22/mysql-ppt-replication-and-consistency/

---


<!--
{% iframe "https://www.slideshare.net/slideshow/embed_code/key/3HLJJcJmM9KLGT" 900 512 %}
-->
