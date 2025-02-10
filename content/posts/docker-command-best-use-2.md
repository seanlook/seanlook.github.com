title: docker常用管理命令（下）
date: 2014-11-05 16:21:25
updated: 2014-11-05 19:46:23
tags: [docker, command,linux]
categories: [Virtualization, Docker]
---

本文承接[docker专题(2)：docker常用管理命令（上）](http://seanlook.com/2014/10/31/docker-command-best-use-1/)。
### 1. 开启/停止/重启container（start/stop/restart） ###
容器可以通过`run`新建一个来运行，也可以重新`start`已经停止的container，但`start`不能够再指定容器启动时运行的指令，因为docker只能有一个前台进程。
容器stop（或`Ctrl+D`）时，会在保存当前容器的状态之后退出，下次start时保有上次关闭时更改。而且每次进入`attach`进去的界面是一样的，与第一次run启动或commit提交的时刻相同。
```
CONTAINER_ID=$(docker start <containner_id>)
docker stop $CONTAINER_ID
docker restart $CONTAINER_ID
```
关于这几个命令可以通过一个完整的实例使用：[docker如何创建一个运行后台进程的容器并同时提供shell终端](http://seanlook.com/2014/11/03/docker-run-container-with-shell-daemon_process/)。

### 2. 连接到正在运行中的container（attach） ###
要`attach`上去的容器必须正在运行，可以同时连接上同一个container来共享屏幕（与`screen`命令的attach类似）。
官方文档中说`attach`后可以通过`CTRL-C`来detach，但实际上经过我的测试，如果container当前在运行bash，`CTRL-C`自然是当前行的输入，没有退出；如果container当前正在前台运行进程，如输出nginx的access.log日志，`CTRL-C`不仅会导致退出容器，而且还stop了。这不是我们想要的，detach的意思按理应该是脱离容器终端，但容器依然运行。好在`attach`是可以带上` --sig-proxy=false`来确保`CTRL-D`或`CTRL-C`不会关闭容器。

<!-- more -->

```
# docker attach --sig-proxy=false $CONTAINER_ID
```

### 3. 查看image或container的底层信息（inspect） ###
`inspect`的对象可以是image、运行中的container和停止的container。

```
查看容器的内部IP
# docker inspect --format='{\{.NetworkSettings.IPAddress}}' $CONTAINER_ID
172.17.42.35
（注：由于代码块解析的问题，上面NetworkSettings前面的 \ 去掉）
```

### 4. 删除一个或多个container、image（rm、rmi） ###
你可能在使用过程中会`build`或`commit`许多镜像，无用的镜像需要删除。但删除这些镜像是有一些条件的：
- 同一个`IMAGE ID`可能会有多个`TAG`（可能还在不同的仓库），首先你要根据这些 image names 来删除标签，当删除最后一个tag的时候就会自动删除镜像；
- 承上，如果要删除的多个`IMAGE NAME`在同一个`REPOSITORY`，可以通过`docker rmi <image_id>`来同时删除剩下的`TAG`；若在不同Repo则还是需要手动逐个删除`TAG`；
- 还存在由这个镜像启动的container时（即便已经停止），也无法删除镜像；

TO-DO
  如何查看镜像与容器的依存关系

** 删除容器 **
`docker rm <container_id/contaner_name>`
```
删除所有停止的容器
docker rm $(docker ps -a -q)
```

** 删除镜像 **
`docker rmi <image_id/image_name ...>` 
下面是一个完整的示例：
```
# docker images            <==
ubuntu            13.10        195eb90b5349       4 months ago       184.6 MB
ubuntu            saucy        195eb90b5349       4 months ago       184.6 MB
seanlook/ubuntu   rm_test      195eb90b5349       4 months ago       184.6 MB

使用195eb90b5349启动、停止一个容器后，删除这个镜像
# docker rmi 195eb90b5349
Error response from daemon: Conflict, cannot delete image 195eb90b5349 because it is 
tagged in multiple repositories, use -f to force
2014/11/04 14:19:00 Error: failed to remove one or more images

删除seanlook仓库中的tag     <==
# docker rmi seanlook/ubuntu:rm_test
Untagged: seanlook/ubuntu:rm_test

现在删除镜像，还会由于container的存在不能rmi
# docker rmi 195eb90b5349
Error response from daemon: Conflict, cannot delete 195eb90b5349 because the 
 container eef3648a6e77 is using it, use -f to force
2014/11/04 14:24:15 Error: failed to remove one or more images

先删除由这个镜像启动的容器    <==
# docker rm eef3648a6e77

删除镜像                    <==
# docker rmi 195eb90b5349
Deleted: 195eb90b534950d334188c3627f860fbdf898e224d8a0a11ec54ff453175e081
Deleted: 209ea56fda6dc2fb013e4d1e40cb678b2af91d1b54a71529f7df0bd867adc961
Deleted: 0f4aac48388f5d65a725ccf8e7caada42f136026c566528a5ee9b02467dac90a
Deleted: fae16849ebe23b48f2bedcc08aaabd45408c62b531ffd8d3088592043d5e7364
Deleted: f127542f0b6191e99bb015b672f5cf48fa79d974784ac8090b11aeac184eaaff
```
注意，上面的删除过程我所举的例子比较特殊——镜像被tag在多个仓库，也有启动过的容器。按照`<==`指示的顺序进行即可。

### 5. docker build <path> 使用此配置生成新的image ###

`build`命令可以从`Dockerfile`和上下文来创建镜像：
`  docker build [OPTIONS] PATH | URL | -`
上面的`PATH`或`URL`中的文件被称作上下文，build image的过程会先把这些文件传送到docker的服务端来进行的。
如果`PATH`直接就是一个单独的`Dockerfile`文件则可以不需要上下文；如果`URL`是一个Git仓库地址，那么创建image的过程中会自动`git clone`一份到本机的临时目录，它就成为了本次build的上下文。无论指定的`PATH`是什么，`Dockerfile`是至关重要的，请参考[Dockerfile Reference](http://docs.docker.com/reference/builder/)。
请看下面的例子：
```
# cat Dockerfile 
FROM seanlook/nginx:bash_vim
EXPOSE 80
ENTRYPOINT /usr/sbin/nginx -c /etc/nginx/nginx.conf && /bin/bash

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
Successfully built d9bbd13f5066
```
上面的`PATH`为`.`，所以在当前目录下的所有文件（不包括`.dockerignore`中的）将会被`tar`打包并传送到`docker daemon`（一般在本机），从输出我们可以到`Sending build context...`，最后有个`Removing intermediate container`的过程，可以通过`--rm=false`来保留容器。
TO-DO
  `docker build github.com/creack/docker-firefox`失败。

### 6. 给镜像打上标签（tag） ###
tag的作用主要有两点：一是为镜像起一个容易理解的名字，二是可以通过`docker tag`来重新指定镜像的仓库，这样在`push`时自动提交到仓库。
```
将同一IMAGE_ID的所有tag，合并为一个新的
# docker tag 195eb90b5349 seanlook/ubuntu:rm_test

新建一个tag，保留旧的那条记录
# docker tag Registry/Repos:Tag New_Registry/New_Repos:New_Tag
```

### 7. 查看容器的信息container（ps） ###
`docker ps`命令可以查看容器的`CONTAINER ID`、`NAME`、`IMAGE NAME`、端口开启及绑定、容器启动后执行的`COMMNAD`。经常通过`ps`来找到`CONTAINER_ID`。
`docker ps` 默认显示当前正在运行中的container
`docker ps -a` 查看包括已经停止的所有容器
`docker ps -l` 显示最新启动的一个容器（包括已停止的）

### 8. 查看容器中正在运行的进程（top） ###
容器运行时不一定有`/bin/bash`终端来交互执行top命令，查看container中正在运行的进程，况且还不一定有`top`命令，这是`docker top <container_id/container_name>`就很有用了。实际上在host上使用`ps -ef|grep docker`也可以看到一组类似的进程信息，把container里的进程看成是host上启动docker的子进程就对了。

### 9. 其他命令 ###
docker还有一些如`login`、`cp`、`logs`、`export`、`import`、`load`、`kill`等不是很常用的命令，比较简单，请参考官网。

### 参考 ###
- [Official Command Line Reference](http://docs.docker.com/v1.1/reference/commandline/cli/)
- [docker中文指南cli-widuu翻译](http://www.widuu.com/docker/)
- [Docker —— 从入门到实践](http://www.dockerpool.com/static/books/docker_practice/)
- [Docker基础与高级](http://17173ops.com/2014/10/13/docker%E5%9F%BA%E7%A1%80%E4%B8%8E%E9%AB%98%E7%BA%A7.shtml)