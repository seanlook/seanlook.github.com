---
title: 在Linux上使用logwatch分析监控日志文件
date: 2014-08-23 01:21:25
updated: 2014-08-23 10:46:23
tags: [logwatch, linux,日志]
categories: [Linux]
---

# 1. 介绍 #

在维护Linux服务器时，经常需要查看系统中各种服务的日志，以检查服务器的运行状态。 如登陆历史、邮件、软件安装等日志。系统管理员一个个去检查会十分不方便；且大多时候，这会是一种被动的检查，即只有在发现系统运行异常时才会想到去查看日志以获取异常的信息。那么如何主动、集中的分析这些日志，并产生报告，定时发送给管理员就会显得十分重要。

logwatch 是一款用 Perl 语言编写的开源日志解析分析器。它能对原始的日志文件进行解析并转换成结构化格式的文档，也能根据您的使用情况和需求来定制报告。logwatch 的主要目的是生成更易于使用的日志摘要，并不是用来对日志进行实时的处理和监控的。正因为如此，logwatch 通常被设定好时间和频率的自动定时任务来调度运行或者是有需要日志处理的时候从命令行里手动运行。一旦日志报告生成，logwatch 可以通过电子邮件把这报告发送给您，您可以把它保存成文件或者直接显示在屏幕上。

Logwatch 报告的详细程度和报告覆盖范围是完全可定制化的。Logwatch 的日志处理引擎也是可扩展的，从某种意义上来说，如果您想在一个新的应用程序中使用 logwatch 功能的话，只需要为这个应用程序的日志文件编写一个日志处理脚本（使用 Perl 语言），然后挂接到 logwatch 上就行。

logwatch 有一点不好的就是，在它生成的报告中没有详细的时间戳信息，而原来的日志文件中是存在的。您只能知道被记录下来的一段时间之内的特定事件，如果想要知道精确的时间点的信息，就不得不去查看原日志文件了。

# 2. 安装与配置说明 #
## 2.1 安装 ##
无论在Debian系还是Redhat系上，安装logwatch都非常简单：

    # apt-get install logwatch     //Debian、Ubuntu.etc
    # yum install logwatch -y       //Redhat、Centos.etc

<!-- more -->

以下内容基于 CentOS 6.x，其余系统相差不大。
 
## 2.2 配置 ##
### 2.2.1 配置文件说明 ###
安装后的目录文件说明：
![logwatch-dir-structure][3]

```
/usr/share/logwatch
    default.conf/     # 配置目录
        logwatch.conf   # 主配置文件，收件人，级别等
        logfiles/       # 定义待分析服务的日志文件组路径，相对于/var/log(*.conf)
        services/       # 自定义需分析日志的Service目录(*.conf)
    scripts/          # 可执行脚本
        logwatch.pl     # 启动分析的perl脚本，/usr/sbin/logwatch的源链接
        logfiles/       # 可包含多个logwatch日志文件组的子目录，对应的日志服务运行的时候，子目录下的脚本会自动被调用
        services/       # logwatch日志服务的过滤脚本，一一对应
        shared/         # 可被多个logwatch日志服务引用的脚本
    dist.conf/
        logfiles/
        services/
    lib/
```
默认情况下使用的是`/usr/share/logwatch/default.conf/logwatch.conf`作为主配置文件，但在`/etc/logwatch/conf/logwatch.conf`中的存在配置选项会覆盖前一个（`/usr/share/logwatch`下的`logwatch.conf`还是会起作用，比如在`/etc/logwatch`的`logwatch.conf`中没有的选项）。但优先级最高的是在执行命令行中指定的选项。

在`/etc/logwatch`下也存在一个与`/usr/share/logwatch`类似的目录结构，可以在这里添加自定义的监控日志信息。

从上面的目录结构划分大概可以了解到 logwatch 的原理：logwatch 首先要知道针对哪一个服务, 从这个服务中得到需要处理的 log 文件信息, 然后这个文件送给过滤脚本处理，之后把处理后格式化的信息展现出。内部细节请看第3篇参考。

### 2.2.2 编辑配置 ###
在`/usr/share/doc/logwatch-7.3.6/HOWTO-Customize-LogWatch`文件中有这里的详细的配置说明。

个人还是习惯在`/etc/logwatch/`下管理配置文件，但又不太希望同时两个配置文件生效，所以对`/usr/share/logwatch/default.conf/logwatch.conf`备份，然后软链接`/etc/logwatch/conf/logwatch.conf`：

    ln -s /usr/share/logwatch/default.conf/logwatch.conf /etc/logwatch/conf/logwatch.conf

试着执行`logwatch --service sshd --print`感受一下处理的结果。接下来修改`/etc/logwatch/conf/logwatch.conf`文件的默认配置来做些个性化设置。

**修改日志分析级别**

    Detail = <Low, Med, High, or a number>

“Detail” 配置指令控制着 logwatch 报告的详细程度。它可以是个正整数，也可以是分别代表着10、5和0数字的 High、Med、Low 几个选项。这里设置成`High`。（配置文件中是不区分大小写的）

**指定报告收件人**

    MailTo = youremailaddress@yourdomain.com

    MailFrom = youremailaddress@yourdomain.com

`MailTo`指定logwatch日志报告接收人，要把一份报告发送给多个用户，只需要把他们的邮件地址用空格或逗号隔开，但是logwatch认为你已经配置好本地邮件服务器（sendmail或postfix），并能正确传递给用户邮箱。

`MailFrom`，顾名思义，指定发件人。邮件地址可以说完整的收件人地址，也可以是服务器上的本地用户如root（有的邮件服务器不支持显示发件人别名）。

**指定发送邮件的客户端**
    
    mailer = "sendmail -t"

默认采用的是sendmail（不是sendmail服务器），而且一般没什么问题。在我的环境下有点特殊，邮件服务器必须通过smtp认证才能发送邮件，不支持匿名和其他本地MTA投递的邮件，而sendmail我一直没有找到设置smtp用户和密码认证的地方（知道的烦请告知），所以就改用了`mailer = "mailx -t"`，然后在`/etc/mail.rc`中设置`from`、`smtp`、`smtp-auth-user`、`smtp-auth-password`、`smtp-auth`参数，但使用mailx带来的问题是后面设置邮件报告格式为html时，无法设置header信息从而foxmail不能解析html正文。尝试了 [sendEmail](http://blog.csdn.net/leshami/article/details/8314570) 也没很好的解决。

大部分人情况可能没这么复杂，其实就是一个发件客户端的功能，网上得知有 mutt 结合 [msmtp](http://sourceforge.net/projects/msmtp/files/msmtp/1.4.16/msmtp-1.4.16.tar.bz2/download) 可以解决该问题：

    # yum install -y mutt       //mutt其实可以不安装
    # tar jxvf msmtp-1.4.16.tar.bz2 && cd msmtp-1.4.16
    # ./configure && make && make install

    # vi ~/.msmtprc 
      account default
      host your.smtp-server.com
      from username@smtp-server.com
      auth login
      user username
      password your_auth_pwd
      logfile ~/msmtp.log

    # 如果使用mutt发送，还需要设置~/.muttrc

将 mailer 改成`mailer = "msmtp -t"`。

**输出格式**

    Output = <mail, html or unformatted>

默认不指定输出格式（plain text）,系统管理员通过邮件客户端（如foxmail）看到的邮件内容是文本形式，比较简单、节省带宽；可以指定为`html`，此时看到的是可点击链接的友好的页面。

当同时设定了`Save = /tmp/logwatch`时，便不会发送邮件报告了，将会根据`Output`指定的格式保存到一个`Save`文件中。

![logwatch_mail_html][1]

另外在有的文章里指定`Format`选项，经过本人试验在7.3.6版本中无效。

**收集日志的范围**

    Range = <Yesterday|Today|All>

`Range`配置指令定义了生成 logwatch 报告的时间段信息。这个指令通常可选的值是 Yesterday、Today、All。当作用了`Rang = All`时，`Archive = yes` 这个指令项也必须配置上，那么所有的已存档的日志文件 (比如，/var/log/maillog、/var/log/maillog-20150111)都会被处理到。

如果我们是通过 crontab 每天收集的话，可以只报告昨天或今天的日志情况。

**收集哪些服务的日志**

    Service = <service-name-1>
    Service = <service-name-2>
    . . .

`Service`选项指定想要监控的一个或多个服务。在`/usr/share/logwatch/scripts/services`目录下列出的服务都能被监控，它们已经涵盖了重要的系统服务（例如：pam,secure,iptables,syslogd 等），也涵盖了一些像 sudo、sshd、http、fail2ban、samba等主流的应用服务。如果您想添加新的服务到列表中，得编写一个相应的日志处理 Perl 脚本，并把它放在这个目录中。
![logwatch-script-service][2]

对于一个综合日志分析工具，logwatch推荐大多数人使用`Service = "All"`，然后通过继续添加`Service = "-service_name" `等来去掉那些不监控的日志。当然在服务器上，并不是所有script下的服务都有启动，有些并没有日志。

**命令行指定logwatch选项**

如果您不想个性化 `/etc/logwatch/conf/logwatch.conf`，您可以不修改此文件让其默认，然后在命令行里运行如下所示的命令：

    # logwatch --detail 10 --mailto youremailaddress@yourdomain.com --range today \
    >  --service sshd --service postfix --service zz-disk_space --service -zz-network \
    > --output mail 

**`logwatch.conf`完整示例**
```
LogDir = /var/log
TmpDir = /var/cache/logwatch
Print = No

Range = yesterday
Detail = High

MailTo = zhouxiao@example.com.net
MailFrom = itsection@example.com.net
mailer = "msmtp -t"
Output = html

Service = All
Service = "-zz-network" 
Service = "-zz-sys"
Service = "-eximstats" 

```

# 3. 扩展 #
## 3.1 cron daily ##
我们可以看到在 crontab 定时任务设定目录下存在`/etc/cron.daily/0logwatch`：
```
#!/bin/bash

DailyReport=`grep -e "^[[:space:]]*DailyReport[[:space:]]*=[[:space:]]*" /usr/share/logwatch/default.conf/logwatch.conf | head -n1 | sed -e "s|^\s*DailyReport\s*=\s*||"`

if [ "$DailyReport" != "No" ] && [ "$DailyReport" != "no" ]
then
    logwatch
fi
```
如果在`logwatch.conf`中显式设置了选项`DailyReport = No`，则会取消logwatch每日执行任务。如果你要修改`cron.daily`的执行时间，可以删掉这个`0logwatch`然后添加到`/etc/crontab`里，或者修改[`/etc/anacrontab`](https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Deployment_Guide/ch-Automating_System_Tasks.html#s2-configuring-anacron-jobs)的`START_HOURS_RANGE`。

所以 logwatch 的工作不是监控日志异常后及时报警的工具，因为默认它是每天一封整合的邮件，并不具有及时性（安装perl的`CPAN`模块后可以更精确的控制logwatch时间，详见第一份参考）。

## 3.2 定制自己要监控的日志 ##

用一个简单的例子介绍自定义logwatch的配置方法。

**首先创建logwatch日志文件组**
`/etc/logwatch/conf/logfiles/test.conf`：

    LogFile = /path/to/your/logfile
    LogFile = /path/to/your/second/logfile

**然后创建logwatch服务配置文件**
`/etc/logwatch/conf/services/test.conf`：

    Title = test title     # 日志文件里的标题
    LogFile = test   # logwatch日志文件组的名字，通常是对应的配置文件的文件名部分

**创建logwatch服务过滤器脚本**
`/etc/logwatch/scripts/services/test`：
```
#!/bin/bash

grep -i ERROR
```

上面的脚本会从日志文件里过滤出包含ERROR的行。最后，为新建的脚本添加执行权限:

    chmod +x /etc/logwatch/scripts/services/test


**参考**

- [Linux 系统中使用 logwatch 监控日志文件](http://linux.cn/article-4490-1.html) （[英文](http://xmodulo.com/monitor-log-file-linux-logwatch.html)）
- [LogWatch Introduction](http://dylanninin.com/blog/2013/06/21/logwatch.html)
- [Managing your log files](http://tuxradar.com/content/managing-your-log-files)
- [Logwatch简单配置教程](http://blog.atime.me/note/logwatch.html)


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/logwatch-html-mail.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/logwatch-script-service.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/logwatch-dir-structure.jpg
