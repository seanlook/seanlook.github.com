title: 管理多tomcat服务shell脚本（CentOS）
date: 2014-10-29 18:21:25
updated: 2014-10-29 11:46:23
tags: [tomcat, script, shell]
categories: Tomcat
---

该脚本改自csdn上的一个shell，忘记出处了，只记得它能够简单的通过`service tomcat [stop|start|restart]`来方便的管理Linux服务器上的tomcat，这可以满足大部分人的需求，然而并不适合我所管理的CentOS上的tomcat应用：通过端口区分的3台tomcat集群。如果每一次管理tomcat或查看日志，都`cd /apps/test/tomcat0/log/`然后切换到另外一个`cd ../../`或`cd /apps/test/tomcat1/log/`，麻烦至极。因此“懒人”创造了这个脚本`tomcat`：

<!-- more -->

```bash
#!/bin/bash  
# author: Sean Chow (seanlook7@gmail.com)
# 
#  
# chkconfig: 345 80 15  
# description: Multiple tomcats service management script.  
  
# Source function library.  
. /etc/rc.d/init.d/functions  

# 第几个tomcat
tcNo=$1
tcName=tomcat$1
basedir=/apps/test/$tcName
tclog=${basedir}/logs/catalina.$(date +%Y-%m-%d).out

RETVAL=0  
  
start(){
        checkrun  
        if [ $RETVAL -eq 0 ]; then  
                echo "-- Starting tomcat..."  
                $basedir/bin/startup.sh  
                touch /var/lock/subsys/${tcNo}
                checklog 
                status
        else  
                echo "-- tomcat already running"  
        fi  
}  

# 停止某一台tomcat，如果是重启则带re参数，表示不查看日志，等待启动时再提示查看  
stop(){
        checkrun  
        if [ $RETVAL -eq 1 ]; then  
                echo "-- Shutting down tomcat..."  
                $basedir/bin/shutdown.sh  
                if [ "$1" != "re" ]; then
                  checklog
                else
                  sleep 5
                fi
                rm -f /var/lock/subsys/${tcNo} 
                status
        else  
                echo "-- tomcat not running"  
        fi  
}  
  
status(){
        checkrun
        if [ $RETVAL -eq 1 ]; then
                echo -n "-- Tomcat ( pid "  
                ps ax --width=1000 |grep ${tcName}|grep "org.apache.catalina.startup.Bootstrap start" | awk '{printf $1 " "}'
                echo -n ") is running..."  
                echo  
        else
                echo "-- Tomcat is stopped"  
        fi
        #echo "---------------------------------------------"  
}

# 查看tomcat日志，带vl参数
log(){
        status
        checklog yes
}

# 如果tomcat正在运行，强行杀死tomcat进程，关闭tomcat
kill(){
        checkrun
        if [ $RETVAL -eq 1 ]; then
            read -p "-- Do you really want to kill ${tcName} progress?[no])" answer
            case $answer in
                Y|y|YES|yes|Yes)
                    ps ax --width=1000 |grep ${tcName}|grep "org.apache.catalina.startup.Bootstrap start" | awk '{printf $1 " "}'|xargs kill -9  
                    status
                ;;
                *);;
            esac
        else
            echo "-- exit with $tcName still running..."
        fi
}


checkrun(){  
        ps ax --width=1000 |grep ${tcName}| grep "[o]rg.apache.catalina.startup.Bootstrap start" | awk '{printf $1 " "}' | wc | awk '{print $2}' >/tmp/tomcat_process_count.txt  
        read line < /tmp/tomcat_process_count.txt  
        if [ $line -gt 0 ]; then  
                RETVAL=1  
                return $RETVAL  
        else  
                RETVAL=0  
                return $RETVAL  
        fi  
}  
# 如果是直接查看日志viewlog，则不提示输入[yes]，否则就是被stop和start调用，需提示是否查看日志
checklog(){
        answer=$1
        if [ "$answer" != "yes" ]; then
            read -p "-- See Catalina.out log to check $2 status?[yes])" answer
        fi
        case $answer in
            Y|y|YES|yes|Yes|"")
                tail -f ${tclog}
            ;;
            *)
            #    status
            #    exit 0
            ;;
        esac
}
checkexist(){
        if [ ! -d $basedir ]; then
            echo "-- tomcat $basedir does not exist."
            exit 0
        fi
}
  
  
case "$2" in  
start)  
        checkexist
        start  
        exit 0
        ;;  
stop)  
        checkexist
        stop  
        exit 0
        ;;  
restart)  
        checkexist
        stop re 
        start 
        exit 0
        ;;  
status)  
        checkexist
        status  
        #$basedir/bin/catalina.sh version  
        exit 0
        ;;  
log)
        checkexist
        log
        exit 0
        ;;
kill)
        checkexist
        status
        kill
        exit 0
        ;;
*)  
        echo "Usage: $0 {start|stop|restart|status|log|kill}"  
        echo "       service tomcat {0|1|..} {start|stop|restart|status|log|kill}"  
        esac  
  
exit 0

```
使用说明：
1. 使用前设定好`baseDir`（多tomcat所在路径），各tomcat命名如`tomcat0`、`tomcat1`...
2. 脚本名字为`tomcat`，放到`/etc/init.d/`下，并基于可执行权限`chmod +x /etc/init.d/tomcat`
3. 执行用户不允许用`root`，特别是在线上环境
4. 已处理其他错误参数输入，可用于正式环境
5. 你也可以修改`tcName`来适应管理一个tomcat服务的情形
6. 使用，以下针对`tomcat0`（`/apps/test/tomcat0`）
```bash
service tomcat 0 start   启动，默认回车会查看启动日志；已启动则仅输出进程号
service tomcat 0 stop    停止，默认回车会查看日志；已停止则无动作；无法停止，则提示是否`kill`（默认No）
service tomcat 0 restart 重启tomcat，有日志输出
service tomcat 0 status  查看tomcat是否启动
service tomcat 0 log     使用`tail -f`命令实时查看日志
service tomcat 0 kill    直接`kill`tomcat进程；尽量少用
```

TO-DO
加入`service tomcat 0 clean`命令来清除`work`和`tmp`目录，正在运行的不允许清除。

这个脚本最近（2014/11/13）在使用过程中发现一个新的问题，因为服务器上tomcat一直开启着监控端口7091，所以在`service tomcat 1 start`失败以后，7091端口就被占用了，但使用`service tomcat 1 status`状态时`stopped`，其实还是有这个失败的tomcat进程，但用`service tomcat 1 kill`会失败。脚本里在考虑这个功能的话就有点臃肿了，还是老实结合手动管理吧。