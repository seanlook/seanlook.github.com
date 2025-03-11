---
title: docker如何创建一个运行后台进程的容器并同时提供shell终端
date: 2014-11-03 20:21:25
aliases:
- /2014/11/03/docker-run-container-with-shell-daemon_process/
updated: 2014-11-07 15:46:23
tags: [docker, shell, linux]
categories: [Virtualization, Docker]
---

只看标题还不是很明显，本文实现docker的这样一种比较常用的功能：通过`docker run`启动一个容器后，容器中已经运行了一个后台进程（这里以监听80端口的nginx为例），同时进入一个shell终端可供操作，而不受限于只能在前台运行nginx与运行shell终端之间的一种。这个例子实现了，那么其他类似的运行多任务docker就可以以此类推。另外本文还提供了一种在docker容器内部安装软件（`vim`）的方法，对于定制自己需要的镜像大有帮助。
你可能需要先阅读[docker专题(2)：docker常用管理命令（上）](hhttp://xgknight.com/2014/10/31/docker-command-best-use-1/)、[docker专题(2)：docker常用管理命令（下）](http://xgknight.com/2014/11/05/docker-command-best-use-2/)来理解更多。
## 1. 已经pull了官方的[nginx 1.7.6](https://registry.hub.docker.com/_/nginx/)的镜像（也可以从私服获取）##
```
# docker images|grep nginx
nginx              1.7.6          561ed4952ef0     10 days ago         100 MB
```
## 2. 根据官方指示启动这个容器 ##
```
先做好自己要显示的页面
# echo "<h2 >This is nginx official container running </h2> <br /> static files:/tmp/doccker/index.html" > /tmp/docker/index.html
```

使用官方image启动一个容器，名字nginx_dist，把host的目录（包含刚才的html）映射到容器中nginx server的root，绑定80端口：

<!-- more -->

```
# docker run --name nginx_dist -v /tmp/docker:/usr/share/nginx/html:ro \
> -p 80:80 -d nginx:1.7.6
1b10b08d7905517a26c72ce8b17b719aaea5e5eac0889263db8b017427e3c8f7
# docker ps
CONTAINER ID  IMAGE    COMMAND               CREATED          STATUS         PORTS                        NAMES
1b10b08d7905  nginx:1  nginx -g 'daemon off  51 seconds ago   Up 48 seconds  443/tcp, 0.0.0.0:80->80/tcp  nginx_dist
```
此时通过浏览器访问主机`http://host_ip:port/`就可以看到结果了：
![docker_nginx_dist][1]

## 3. 查看这个容器的信息 ##
熟悉一下docker的命令。
```
查看容器中运行着哪些进程
# docker top nginx_dist
UID     PID      PPID     C     STIME     TTY    TIME         CMD
root    24378    18471    0     15:25     ?      00:00:00     nginx: master process nginx -g daemon off;
101     24433    24378    0     15:25     ?      00:00:00     nginx: worker process

查看容器IP和主机等信息
# docker inspect nginx_dist |grep 172.17
        "Gateway": "172.17.42.1",
        "IPAddress": "172.17.42.6",

连接到容器上，--sig-proxy可以保证 Ctrl+D、Ctrl+C 不会退出
# docker attach --sig-proxy=false nginx_dist 
xxx.xx.xx.xx - - [03/Nov/2014:07:39:52 +0000] "GET / HTTP/1.1" 304 0 "-" "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.104 Safari/537.36" "-"
Ctrl+C
```

## 4. 容器改造—在容器内部安装vim ##
这里有个未解决的问题，能否有办法在上面已经启动的container的基础上执行命令？官方没有这样的支持。
目前只能重新启动一个容器(停止上面的`nginx_dist`容器)
```
可以比较一下与2中命令的变化
# docker run --name nginx_bash_vim -v /tmp/docker:/usr/share/nginx/html:ro \
> -p 80:80 -i -t nginx:1.7.6 
> /bin/bash
root@3911d1104c3f:/# 
```
但此时nginx服务是停止的，并没有在后台运行，访问`http://host_ip:port/`无效。为了后面编辑配置文件方便，我们先把`vim`安装好。
容器内部的网络与容器外部是相同的，并与host具有相同的DNS，所以可以使用公网软件（`cat /etc/apt/sources.list`）镜像源来安装。
```
如果需要代理：export http_proxy=http://proxy_server:port
# apt-get clean
# apt-get update
# apt-get install vim
Reading package lists... Done
...
After this operation, 25.2 MB of additional disk space will be used.
Do you want to continue [Y/n]? y
...
Setting up vim (2:7.3.547-7) ...
...
```
## 5. 让nginx在后台运行，前台提供shell终端 ##
实现这一步的方法有许多种，比如
### 5.1 手动运行`/usr/sbin/nginx -c /etc/nginx/nginx.conf` ###
也就是用第4步的方法先启动到`/bin/bash`，再手动运行`/usr/sbin/nginx -c /etc/nginx/nginx.conf`或`service nginx start`，很容易想到，但太麻烦。

### 5.2 通过`Dockerfile`来`build` ###
将装好vim的容器提交成新的image，然后通过`Dockerfile`来自定义要启动哪些服务。关于`Dockerfile`后面我也会写文章来单独介绍其语法。
```
在主机下运行
# docker commit -m "nginx 14.10 with bash,vim" nginx_bash_vim seanlook/nginx:bash_vim
a06ab41a6565f0dbd5d35d44cb441d1a166beaae3bc49bffcb09d334a1e77a5c

使用Dockerfile来建立一个新的镜像，加入启动到容器是运行的命令
# vi Dockerfile
FROM seanlook/nginx:bash_vim
ENTRYPOINT /usr/sbin/nginx -c /etc/nginx/nginx.conf && /bin/bash

build新image，tag为bash_vim_Df
# docker build -t seanlook/nginx:bash_vim_Df .
Sending build context to Docker daemon 73.45 MB
Sending build context to Docker daemon 
Step 0 : FROM seanlook/nginx:bash_vim
 ---> aa8516fa0bb7
Step 1 : EXPOSE 80
 ---> Using cache
 ---> fece07e2b515
Step 2 : ENTRYPOINT /usr/sbin/nginx -c /etc/nginx/nginx.conf && /bin/bash
 ---> Running in e08963fd5afb
 ---> d9bbd13f5066
Removing intermediate container e08963fd5afb
Successfully built d9bbd13f5066    --> 新image id

# docker images |grep 'bash_vim'
seanlook/nginx      bash_vim_Df       d9bbd13f5066       About an hour ago   125.9 MB
seanlook/nginx      bash_vim          aa8516fa0bb7       About an hour ago   125.9 MB

运行由Dockerfile创建的image
# docker run --name nginx_bash_vim_Df -v /tmp/docker:/usr/share/nginx/html:ro \
> -i -t -p 8080:80 \
> d9bbd13f5066   --> 或seanlook/nginx:bash_vim_Df
```
最后一条`docker run`之后就会自动进入`bash`终端，同时发现`nginx`服务也启动了，可以通过`vim`来编辑配置文件。

### 5.3 修改容器的/etc/bash.bashrc ###
这是投机取巧但不失为最简单的一种办法，见[Run a service automatically in a docker container](http://stackoverflow.com/questions/17252356/run-a-service-automatically-in-a-docker-container/19872810#19872810)。

```
启动刚安装完vim的那个容器（不必用run）
# docker start nginx_bash_vim

连接到终端上
# docker attach nginx_bash_vim
root@3911d1104c3f:/# vi /etc/bash.bashrc 
# added by mis_zx for auto-service nginx  --> 在最后加入
/usr/sbin/nginx -c /etc/nginx/nginx.conf
```
保存后直接Ctrl+D退出，在`start`就可以访问了，如果要进入终端就`attach`，如果需要可以`commit`成一个镜像。
### 5.4 听说有一种通过`supervisor`来管理docker容器的多个任务，有时间会研究一下 ###

从上面的操作中可以看出，`start`是可以保留`run`启动时的参数如`-v`、`-p`，而`commit`之后如果没在`Dockerfile`中指定，下次启动依然需要带上目录、端口的映射参数。
另外提一点， `docker run -i -t seanlook/nginx:bash_vim`启动便会同时进入一个shell界面（但没有启动nginx），因为它的“前身”容器是在shell交互界面下`run`来的，但也没有保留`-v`、`-p`指定的映射关系。

  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/docker_registry_nginx_dist.png
