---
title: 遇到腾讯云CDB连接字符集设置一个坑
date: 2016-10-17 16:32:49
aliases:
- /2016/10/17/mysql-charset-handshake-cdb/
tags: [mysql, 腾讯云, 字符集]
categories:
- MySQL
updated: 2016-10-17 16:32:49
---

最近一个与qq有关的服务迁到腾讯云上，相应的数据库也要从原阿里云RDS迁移到腾讯云CDB上，经过一番摸索，不带任何政治色彩的说，CDB跟RDS相比弱的不止一条街。比如看个错误日志还要提工单，数据库访问没有白名单，数据传输服务竞不支持源库的开启GTID，自带的后台管理是phpMyAdmin，要临时看查询日志也要提工单，当然这些都是可以容忍通过其它方法解决的，但是如果使用上带来了mysql数据库本身的影响，就用的不太爽了。

最近2个月一直在弄与字符集相关的工作，却还是在cdb踩到一个大坑。情况是这样的，我们旧的RDS上的数据库表定义都是utf8，但由于历史原因，开发一直使用 latin1 去连接的。现在要把这样的一个db迁移到CDB，腾讯云的数据传输服务出了点问题，于是想了办法用阿里云的DTS反向迁。现象是：

1. 用Navicat客户端latin1连接，旧数据显示都ok
2. 但程序端看到历史数据全是乱码，新数据正常
3. 而且**新数据通过navicat去看用 utf8 连接才正常**
4. 在mysql命令行下手动 `set names latin1` 读取旧数据ok，但新数据乱码

这明显是新写入的时候就是以 utf8 连接的，读取的时候新旧数据也以 utf8 连接。但应用端已明确设置使用 latin1 连接来读写。为了验证是否CDB的问题，在相同环境下自建了个mysql实例，一切都ok。

腾讯云工程师先是怀疑迁移有问题，后来说可能是character_set_server设置的问题，我站在2个月来处理字符集的经验看了虽然不太可能，还是配合截了几个图，在工单、电话了里撕了几个来回：

![][1]

因为跟腾讯有合作关系，上头就直接联系到了腾讯云的人，这才找到问题根源：都是`--skip-character-set-client-handshake`惹的祸。
```
--character-set-client-handshake

Do not ignore character set information sent by the client. To ignore client information and use the default server character set, use --skip-character-set-client-handshake; this makes MySQL behave like MySQL 4.0
```
<!-- more -->
一看到这个选项就恍然大悟了，官方文档FAQ里有专门介绍：[A.11.11](https://dev.mysql.com/doc/refman/5.6/en/faqs-cjk.html)（个人感觉最后一段贴的结果有问题），大意是说为了兼容 mysql 4.0 的习惯，mysqld启动时加上 `--skip-character-set-client-handshake` 来忽略客户端字符集的设置，强制使用服务端`character-set-server`的设置。

但这个选项默认是没有开启的，当你在web控制台修改了实例字符集时，CDB自作自作主张修改了这个参数并重启 character_set_client_handshake = 0 。而这个参数在 `show variables` 看不到的，隐藏的比较深。正好我建实例的时候选择了utf8，然后修改为utf8mb4，但应用端要求latin1，便中枪了。

![][2]

主要是以前没听过这个参数，后来发现老叶也有篇文章讲到它 [MySQL字符集的一个坑](http://imysql.com/2013/10/29/misunderstand-about-charset-handshake.shtm)，其实是很小的东西，结果排查验证问题前后花了2天。。。


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-qcloud-charset1.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/mysql-qcloud-charset.png


---

原文链接地址：http://xgknight.com/2016/10/17/mysql-charset-handshake-cdb/

---
