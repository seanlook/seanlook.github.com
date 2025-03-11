---
title: 配置 Oracle 11gR2 在 CentOS6 上开机自启动
date: 2015-04-11 15:21:25
updated: 2015-04-11 15:21:25
tags: [oracle, linux]
categories: Oracle
---

## 修改配置 ##
要达到oracle随开机自启动，一般使用11g自带的dbstart脚本：`$ORACLE_HOME/bin/dbstart`，但要先修改`/etc/oratab`的内容，将N改成Y，表示允许实例自启动，假如有2个实例要启动，再写一行：
```
$ vi /etc/oratab
EXCRMPROD:/db/oracle/product/11.2.0/db_1:Y
```

然后在oracle用户下执行`$ORACLE_HOME/bin/dbstart`即可启动，日志被记录在`$ORACLE_HOME/startup.log`。但是，默认情况`dbstart`和`dbshut`脚本不能自动启动或关闭监听，所以也要加以修改：
```
$ vi /db/oracle/product/11.2.0/db_1/bin/dbstart
## 找到下面的代码(约第80行)，在实际脚本代码的前面
# First argument is used to bring up Oracle Net Listener
ORACLE_HOME_LISTNER=$1
## 将此处的 ORACLE_HOME_LISTNER=$1 修改为 ORACLE_HOME_LISTNER=$ORACLE_HOME
if [ ! $ORACLE_HOME_LISTNER ] ; then
echo "ORACLE_HOME_LISTNER is not SET, unable to auto-start Oracle Net Listener"
echo "Usage: $0 ORACLE_HOME"
else
LOG=$ORACLE_HOME_LISTNER/listener.log
```

同样也修改dbshut脚本（约第50行）：
```
$ vi /db/oracle/product/11.2.0/db_1/bin/dbshut

# The this to bring down Oracle Net Listener
ORACLE_HOME_LISTNER=$ORACLE_HOME
if [ ! $ORACLE_HOME_LISTNER ] ; then
echo "ORACLE_HOME_LISTNER is not SET, unable to auto-stop Oracle Net Listener"
echo "Usage: $0 ORACLE_HOME"
else
LOG=$ORACLE_HOME_LISTNER/listener.log
```

## 开机启动 ##
这两个脚本在执行时会自动去搜索`/etc/oratab`文件的内容，将这两个命令分别加入开机启动和关闭脚本里。

<!-- more -->

**/etc/rc.local**
Linux系统开机初始化的最后过程会执行该脚本，加入以下内容：
```
su - oracle -lc "$ORACLE_HOME/bin/dbstart"
```

**/etc/rc.local.shutdown**
这个脚本时系统里没有的，完成的功能是关机自动停止服务，`/etc/rc.d/rc.local.shutdown`：
```
#!/bin/bash

# chkconfig: - 00 00
# description: Do custom commands before shutdown or reboot

### BEGIN INIT INFO
# Provides: custom-halt
# Required-Start:
# Required-Stop:
# Default-Start: 0 6
# Default-Stop:
# Short-Description: Custom halt commands
# Description: Do custom commands before shutdown or reboot
### END INIT INFO

export ORACLE_BASE=/db/oracle
export ORACLE_HOME=$ORACLE_BASE/product/11.2.0/db_1
export ORACLE_SID=EXCRMPROD
export PATH=$PATH:$ORACLE_HOME/bin

su - oracle -lc "$ORACLE_HOME/bin/dbshut /dev/null 2>&1"

exit
```

让它运行在`0`和`6`运行级别runlevel：
```
# chmod 755 /etc/rc.d/rc.local.shutdown
# ln -s /etc/rc.d/rc.local.shutdown /etc/rc.local.shutdown
# ln -s /etc/rc.d/rc.local.shutdown /etc/init.d/custom-halt

# chkconfig --add custom-halt
# chkconfig --level 06 custom-halt on 
```

另外网上也有文章不是利用 oracle 自带的 dbstart 来实现自启动，而是自己写 service 脚本，执行 sqlplus 然后运行 shutdown immediate ，个人觉得这有点重复做oracle的事情了；还有把通过类似`service oracle start/stop`这样的形式去管理，方便是方便一点，但要知道oracle数据库轻易不会频繁重启，如有需要，我们更愿意自己使用`sqlplus`连上数据库，自己执行`shutdown`命令，因为对数据库的操作还是以慎重为主，在配置了Active Data Guard等复杂环境下，对备库也不适用，所以这里就没做这个工作。
