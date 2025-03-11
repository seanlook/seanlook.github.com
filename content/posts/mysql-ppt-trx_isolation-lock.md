---
title: 浅析MySQL事务隔离级别与锁 分享
date: 2016-08-30 21:32:49
tags: [mysql, 事务]
categories:
- MySQL
updated: 2016-08-30 21:32:49
---

这段时间在公司内部准备了一个分享，主题是关于 MySQL事务与锁，准备过程内容很多，也深入弄清楚了一些以前比较迷糊的地方，加上后面的讨论也就一个半小时。

主要涉及的是乐观锁与悲观锁，InnoDB多版本并发控制的实现，以及隔离级别与各种情况加锁分析，因为涉及的主要还是开发人员，所以不是很深奥。也算花了不少心血，分享一下。

slideshare: http://www.slideshare.net/ssuser5a0bc0/my-sql-seanlook

{% pdf http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-ppt-trx_isolation-lock-seanlook.pdf 900 512 %}


---

原文连接地址：http://xgknight.com/2016/08/30/mysql-ppt-trx_isolation-lock/

---


<!--
{% iframe "https://www.slideshare.net/slideshow/embed_code/key/3HLJJcJmM9KLGT" 900 512 %}
-->
