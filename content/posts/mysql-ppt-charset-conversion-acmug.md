---
title: 一次艰辛的字符集转换历程 ACMUG分享
date: 2017-03-27 21:32:49
tags: [mysql, 分享]
categories:
- MySQL
updated: 2017-03-28 21:32:49
---

本文的ppt是3月25日在中国MySQL用户组2017深圳活动上，我所做的一个主题分享，关于实际生产使用mysql过程中与字符集有关的一些坑。

这个总结其实自己去年一直也想去做，前后花了2个多月的时间，最后所有库无痛完成迁移转化。在2017年二月中下旬的时候微信上请教周董（去哪儿周彦韦大师）一个问题，因为以前也聊过一些，所以他突然问我要不要在3月份的活动上做个主题分享。当时有点不敢想，毕竟之前2次有关培训都是在公司内部的，而这次对外的分享，且不说台下听众有牛人存在，演讲嘉宾里面可各个都是大师级别的，所以当时没有马上答应。过了两天，偶然想到关于字符集这个经历可以讲一讲，不是为了展示自己有多牛B，只是分享下整个问题的处理经验，放低姿态。列了个提纲发给了周董，10分钟不到周董说定了。向经理请示了下没问题，这下赶着鸭子都得上了……

毕竟第一次公开在这样的场合演讲，说不紧张肯定是假的，所以早早的就在准备ppt，一边回顾，一边画图。上阵前一天晚上还在对演示稿微调，并尽量控制时间。

闲话不多说，PPT奉上：

{% pdf http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-ppt-charset-conversion-acmug-sean.pdf 1000 800 %}

IT大咖说有录视频：
- http://www.itdks.com/dakashuo/detail/700

后来自己复看了一下，没啥大毛病，内容都交代清楚了，就是感觉确实舞台经验，表述上还有待加强。

同时这里是当天的活动掠影，阅读原文可看视频：
- ACMUG 2017 Tech Tour 深圳站掠影 http://mp.weixin.qq.com/s/-QNRhnN0kBtLkiWVIUS-QQ

下方是中国MySQL用户组(ACMUG)的公众号，欢迎关注：
![ACMUG](http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-acmug-wechat.jpg)

---

原文连接地址：http://xgknight.com/2017/03/27/mysql-ppt-charset-conversion-acmug/

---


<!--
{% iframe "https://www.slideshare.net/slideshow/embed_code/key/3HLJJcJmM9KLGT" 900 512 %}
-->
