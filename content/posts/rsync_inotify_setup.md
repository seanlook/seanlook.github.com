title: Linux下同步工具inotify+rsync使用详解
date: 2014-12-12 01:21:25
updated: 2014-12-12 00:46:23
tags: [rsync,inotify,backup，文件同步]
categories: Linux
---

# 1. rsync #
## 1.1 什么是rsync ##

rsync是一个远程数据同步工具，可通过LAN/WAN快速同步多台主机间的文件。它使用所谓的“Rsync演算法”来使本地和远程两个主机之间的文件达到同步，这个算法只传送两个文件的不同部分，而不是每次都整份传送，因此速度相当快。所以通常可以作为备份工具来使用。

运行Rsync server的机器也叫backup server，一个Rsync server可同时备份多个client的数据；也可以多个Rsync server备份一个client的数据。Rsync可以搭配ssh甚至使用daemon模式。Rsync server会打开一个873的服务通道(port)，等待对方rsync连接。连接时，Rsync server会检查口令是否相符，若通过口令查核，则可以开始进行文件传输。第一次连通完成时，会把整份文件传输一次，下一次就只传送二个文件之间不同的部份。

**基本特点：**

1. 可以镜像保存整个目录树和文件系统；
2. 可以很容易做到保持原来文件的权限、时间、软硬链接等；
3. 无须特殊权限即可安装；
4. 优化的流程，文件传输效率高；
5. 可以使用rcp、ssh等方式来传输文件，当然也可以通过直接的socket连接；
6. 支持匿名传输。


**命令语法：**
rsync的命令格式可以为以下六种：
　rsync [OPTION]… SRC DEST
　rsync [OPTION]… SRC [USER@]HOST:DEST
　rsync [OPTION]… [USER@]HOST:SRC DEST
　rsync [OPTION]… [USER@]HOST::SRC DEST
　rsync [OPTION]… SRC [USER@]HOST::DEST
　rsync [OPTION]… rsync://[USER@]HOST[:PORT]/SRC [DEST]

对应于以上六种命令格式，我们可以总结rsync有2种不同的工作模式：

- shell模式：使用远程shell程序（如ssh或rsh）进行连接。当源路径或目的路径的主机名后面包含一个冒号分隔符时使用这种模式，rsync安装完成后就可以直接使用了，无所谓启动。（目前没有尝试过这个方法）
- daemon模式：使用TCP直接连接rsync daemon。当源路径或目的路径的主机名后面包含两个冒号，或使用rsync://URL时使用这种模式，无需远程shell，但必须在一台机器上启动rsync daemon，默认端口873，这里可以通过`rsync --daemon`使用独立进程的方式，或者通过xinetd超级进程来管理rsync后台进程。

当rsync作为daemon运行时，它需要一个用户身份。如果你希望启用chroot，则必须以root的身份来运行daemon，监听端口，或设定文件属主；如果不启用chroot，也可以不使用root用户来运行daemon，但该用户必须对相应的模块拥有读写数据、日志和lock file的权限。当rsync以daemon模式运行时，它还需要一个配置文件——rsyncd.conf。修改这个配置后不必重启rsync daemon，因为每一次的client连接都会去重新读取该文件。

<!-- more -->

我们一般把DEST远程服务器端成为rsync Server，运行rsync命令的一端SRC称为Client。

**安装：**
rsync在CentOS6上默认已经安装，如果没有则可以使用`yum install rsync -y`，服务端和客户端是同一个安装包。
```
# rsync -h
```

## 1.2 同步测试 ##
关于`rsync`命令的诸多选项说明，见另外一篇文章[rsync与inotifywait命令和配置选项说明](http://seanlook.com/2014/12/13/rsync_inotify_configuration)。

### 1.2.1 本机文件夹同步 ###
```
# rsync -auvrtzopgP --progress  /root/ /tmp/rsync_bak/
```
会看到从`/root/`传输文件到`/tmp/rsync_bak/`的列表和速率，再运行一次会看到sending incremental file list下没有复制的内容，可以在/root/下`touch`某一个文件再运行看到只同步了修改过的文件。

上面需要考虑以下问题：

- 删除/root/下的文件不会同步删除/tmp/rsync_bak，除非加入`--delete`选项 
- 文件访问时间等属性、读写等权限、文件内容等有任何变动，都会被认为修改
- 目标目录下如果文件比源目录还新，则不会同步
- 源路径的最后是否有斜杠有不同的含义：有斜杠，只是复制目录中的文件；没有斜杠的话，不但要复制目录中的文件，还要复制目录本身

## 1.3 同步到远程服务器 ##
在服务器间rsync传输文件，需要有一个是开着rsync的服务，而这一服务需要两个配置文件，说明当前运行的用户名和用户组，这个用户名和用户组在改变文件权限和相关内容的时候有用，否则有时候会出现提示权限问题。配置文件也说明了模块、模块化管理服务的安全性，每个模块的名称都是自己定义的，可以添加用户名密码验证，也可以验证IP，设置目录是否可写等，不同模块用于同步不同需求的目录。

### 1.3.1 服务端配置文件 ###

** /etc/rsyncd.conf： **
```
#2014-12-11 by Sean
uid=root
gid=root
use chroot=no
max connections=10
timeout=600
strict modes=yes
port=873
pid file=/var/run/rsyncd.pid
lock file=/var/run/rsyncd.lock
log file=/var/log/rsyncd.log

[module_test]
path=/tmp/rsync_bak2
comment=rsync test logs
auth users=sean
uid=sean
gid=sean
secrets file=/etc/rsyncd.secrets
read only=no
list=no
hosts allow=172.29.88.204
hosts deny=0.0.0.0/32
```
这里配置socket方式传输文件，端口873，[module_test]开始定义一个模块，指定要同步的目录（接收）path，授权用户，密码文件，允许哪台服务器IP同步（发送）等。关于配置文件中选项的详细说明依然参考[rsync与inotifywait命令和配置选项说明](http://seanlook.com/2014/12/13/rsync_inotify_configuration)。

经测试，上述配置文件每行后面不能使用`#`来来注释

** /etc/rsyncd.secrets： **
```
sean:passw0rd
```
一行一个用户，用户名:密码。请注意这里的用户名和密码与操作系统的用户名密码无关，可以随意指定，与`/etc/rsyncd.conf`中的`auth users`对应。

修改权限：`chmod 600 /etc/rsyncd.d/rsync_server.pwd`。

### 1.3.2 服务器启动rsync后台服务 ###
修改`/etc/xinetd.d/rsync`文件，disable 改为 no
```
# default: off
# description: The rsync server is a good addition to an ftp server, as it \
#	allows crc checksumming etc.
service rsync
{
	disable	= no
	flags		= IPv6
	socket_type     = stream
	wait            = no
	user            = root
	server          = /usr/bin/rsync
	server_args     = --daemon
	log_on_failure  += USERID
}
```
执行`service xinetd restart`会一起重启rsync后台进程，默认使用配置文件`/etc/rsyncd.conf`。也可以使用`/usr/bin/rsync --daemon --config=/etc/rsyncd.conf`。

为了以防rsync写入过多的无用日志到`/var/log/message`（容易塞满从而错过重要的信息），建议注释掉`/etc/xinetd.conf`的success：   
```
# log_on_success  = PID HOST DURATION EXIT
```

如果使用了防火墙，要添加允许IP到873端口的规则。
```
# iptables -A INPUT -p tcp -m state --state NEW  -m tcp --dport 873 -j ACCEPT
# iptables -L  查看一下防火墙是不是打开了 873端口
# netstat -anp|grep 873
```
建议关闭`selinux`，可能会由于强访问控制导致同步报错。

### 1.3.3 客户端测试同步 ###
单向同步时，客户端只需要一个包含密码的文件。
**/etc/rsync_client.pwd：**
```
passw0rd
```
chmod 600 /etc/rsync_client.pwd

**命令：**
将本地`/root/`目录同步到远程172.29.88.223的/tmp/rsync_bak2目录（module_test指定）：
```
/usr/bin/rsync -auvrtzopgP --progress --password-file=/etc/rsync_client.pwd /root/ sean@172.29.88.223::module_test 
```

当然你也可以将远程的/tmp/rsync_bak2目录同步到本地目录/root/tmp：
```
/usr/bin/rsync -auvrtzopgP --progress --password-file=/etc/rsync_client.pwd sean@172.29.88.223::module_test /root/ 
```
从上面两个命令可以看到，其实这里的服务器与客户端的概念是很模糊的，rsync daemon都运行在远程172.29.88.223上，第一条命令是本地主动推送目录到远程，远程服务器是用来备份的；第二条命令是本地主动向远程索取文件，本地服务器用来备份，也可以认为是本地服务器恢复的一个过程。

## 1.4 rsync不足 ##
与传统的cp、tar备份方式相比，rsync具有安全性高、备份迅速、支持增量备份等优点，通过rsync可以解决对实时性要求不高的数据备份需求，例如定期的备份文件服务器数据到远端服务器，对本地磁盘定期做数据镜像等。

随着应用系统规模的不断扩大，对数据的安全性和可靠性也提出的更好的要求，rsync在高端业务系统中也逐渐暴露出了很多不足，首先，rsync同步数据时，需要扫描所有文件后进行比对，进行差量传输。如果文件数量达到了百万甚至千万量级，扫描所有文件将是非常耗时的。而且正在发生变化的往往是其中很少的一部分，这是非常低效的方式。其次，rsync不能实时的去监测、同步数据，虽然它可以通过crontab方式进行触发同步，但是两次触发动作一定会有时间差，这样就导致了服务端和客户端数据可能出现不一致，无法在应用故障时完全的恢复数据。基于以上原因，rsync+inotify组合出现了！

# 2. inotify-tools #
## 2.1 什么是inotify ##
inotify是一种强大的、细粒度的、异步的文件系统事件监控机制，Linux内核从2.6.13开始引入，允许监控程序打开一个独立文件描述符，并针对事件集监控一个或者多个文件，例如打开、关闭、移动/重命名、删除、创建或者改变属性。

CentOS6自然已经支持：
使用`ll /proc/sys/fs/inotify`命令，是否有以下三条信息输出，如果没有表示不支持。
```
total 0
-rw-r--r-- 1 root root 0 Dec 11 15:23 max_queued_events
-rw-r--r-- 1 root root 0 Dec 11 15:23 max_user_instances
-rw-r--r-- 1 root root 0 Dec 11 15:23 max_user_watches
```

- `/proc/sys/fs/inotify/max_queued_evnets`表示调用inotify_init时分配给inotify instance中可排队的event的数目的最大值，超出这个值的事件被丢弃，但会触发IN_Q_OVERFLOW事件。
- `/proc/sys/fs/inotify/max_user_instances`表示每一个real user ID可创建的inotify instatnces的数量上限。
- `/proc/sys/fs/inotify/max_user_watches`表示每个inotify instatnces可监控的最大目录数量。如果监控的文件数目巨大，需要根据情况，适当增加此值的大小。

**inotify-tools：**

inotify-tools是为linux下inotify文件监控工具提供的一套C的开发接口库函数，同时还提供了一系列的命令行工具，这些工具可以用来监控文件系统的事件。 inotify-tools是用c编写的，除了要求内核支持inotify外，不依赖于其他。inotify-tools提供两种工具，一是`inotifywait`，它是用来监控文件或目录的变化，二是`inotifywatch`，它是用来统计文件系统访问的次数。

下载inotify-tools-3.14-1.el6.x86_64.rpm，通过rpm包安装：
```
# rpm -ivh /apps/crm/soft_src/inotify-tools-3.14-1.el6.x86_64.rpm 
warning: /apps/crm/soft_src/inotify-tools-3.14-1.el6.x86_64.rpm: Header V3 DSA/SHA1 Signature, key ID 4026433f: NOKEY
Preparing...                ########################################### [100%]
   1:inotify-tools          ########################################### [100%]
# rpm -qa|grep inotify
inotify-tools-3.14-1.el5.x86_64
```

## 2.2 inotifywait使用示例 ##
监控/root/tmp目录文件的变化：
```
/usr/bin/inotifywait -mrq --timefmt '%Y/%m/%d-%H:%M:%S' --format '%T %w %f' \
 -e modify,delete,create,move,attrib /root/tmp/
```
上面的命令表示，持续监听`/root/tmp`目录及其子目录的文件变化，监听事件包括文件被修改、删除、创建、移动、属性更改，显示到屏幕。执行完上面的命令后，在`/root/tmp`下创建或修改文件都会有信息输出：
```
2014/12/11-15:40:04 /root/tmp/ new.txt
2014/12/11-15:40:22 /root/tmp/ .new.txt.swp
2014/12/11-15:40:22 /root/tmp/ .new.txt.swx
2014/12/11-15:40:22 /root/tmp/ .new.txt.swx
2014/12/11-15:40:22 /root/tmp/ .new.txt.swp
2014/12/11-15:40:22 /root/tmp/ .new.txt.swp
2014/12/11-15:40:23 /root/tmp/ .new.txt.swp
2014/12/11-15:40:31 /root/tmp/ .new.txt.swp
2014/12/11-15:40:32 /root/tmp/ 4913
2014/12/11-15:40:32 /root/tmp/ 4913
2014/12/11-15:40:32 /root/tmp/ 4913
2014/12/11-15:40:32 /root/tmp/ new.txt
2014/12/11-15:40:32 /root/tmp/ new.txt~
2014/12/11-15:40:32 /root/tmp/ new.txt
...
```

# 3. rsync组合inotify-tools完成实时同步 #
这一步的核心其实就是在客户端创建一个脚本`rsync.sh`，适用`inotifywait`监控本地目录的变化，触发`rsync`将变化的文件传输到远程备份服务器上。为了更接近实战，我们要求一部分子目录不同步，如`/root/tmp/log`和临时文件。

## 3.1 创建排除在外不同步的文件列表 ##
排除不需要同步的文件或目录有两种做法，第一种是inotify监控整个目录，在rsync中加入排除选项；第二种是inotify排除部分不监控的目录，rsync自然也不会触发。我们选择第二种。

这个操作在客户端进行，`/root/tmp/log`以及`/root/tmp/src`目录下的js、css和一些临时文件不同步，所以不需要`inotifywait`，`/root/tmp`下的其他文件和目录都同步。（其实对于打开的临时文件，可以不监听`modify`时间而改成监听`close_write`）
```
# vi /etc/inotify_rsync_exclude.lst：
@/root/tmp/cache??*
@/root/tmp/src/js
@/root/tmp/src/css
@/root/tmp/src
@/root/tmp/src/20*/20*/20*/.??*
@/root/tmp/log/
```
目前测试看到只能用绝对路径。

## 3.2 客户端同步到远程的脚本`rsync.sh` ##
rsync.sh：
```
#rsync auto sync script with inotify
#2014-12-11 Sean
#variables
current_date=$(date +%Y%m%d_%H%M%S)
source_path=/root/tmp/
log_file=/var/log/rsync_client.log

#rsync
rsync_server=172.29.88.223
rsync_user=sean
rsync_pwd=/etc/rsync_client.pwd
rsync_module=module_test

#rsync client pwd check
if [ ! -e ${rsync_pwd} ];then
    echo -e "rsync client passwod file ${rsync_pwd} does not exist!"
    exit 0
fi

#inotify_function
inotify_fun(){
    /usr/bin/inotifywait -mrq --timefmt '%Y/%m/%d-%H:%M:%S' --format '%T %w %f' \
          --fromfile /etc/inotify_rsync_exclude.lst -e modify,delete,create,move,attrib ${source_path} \
          | while read file
      do
          /usr/bin/rsync -auvrtzopgP --progress --bwlimit=200 --password-file=${rsync_pwd} ${source_path} ${rsync_user}@${rsync_server}::${rsync_module} 
      done
}

#inotify log
inotify_fun >> ${log_file} 2>&1 &
```
`--bwlimit=200`用于限制传输速率最大200kb，因为在实际应用中发现如果不做速率限制，会导致巨大的CPU消耗。

在客户端运行脚本`# ./rsync.sh`即可实时同步目录。

其他功能：[双向同步](http://seanlook/2014/12/13/rsync_two-way_eg)、[sersync2实时同步多远程服务器](http://seanlook2014/12/16/rsync_sersyc2_muti_remote_dest)

## 参考 ##
- [How Rsync Works](http://rsync.samba.org/how-rsync-works.html)
- [用 inotify 监控 Linux 文件系统事件](https://www.ibm.com/developerworks/cn/linux/l-inotify/)
- [Inotify: 高效、实时的Linux文件系统事件监控框架](http://www.infoq.com/cn/articles/inotify-linux-file-system-event-monitoring)
- [rsync 的核心算法](http://coolshell.cn/articles/7425.html)