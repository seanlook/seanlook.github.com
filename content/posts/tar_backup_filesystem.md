---
title: tar命令高级用法——备份数据
date: 2014-12-08 01:21:25
updated: 2014-12-09 00:46:23
tags: [linux命令,tar,backup]
categories: Linux
---

Linux上有功能强大的tar命令，tar最初是为了制作磁带备份（tape archive）而设计的，它的作用是把文件和目录备份到磁带中，然后从磁带中提取或恢复文件。现在我们可以使用tar来备份数据到任何存储介质上。它是文件级备份，不必考虑底层文件系统类别，并且支持增量备份。

## 1. 部分常用选项 ##
- `-z, --gzip`：使用gzip工具（解）压缩，后缀一般为`.gz`
- `-c, --create`：tar打包，后缀一般为`.tar`
- `-f, --file=`：后面立刻接打包或压缩后得到的文件名
- `-x, --extract`：解包命令，与`-c`对应
- `-p`：保留备份数据的原本权限和属性
- `-g`：后接增量备份的快照文件
- `-C`：指定解压缩的目录
- `--exclude`：排除不打包的目录或文件，支持正则匹配

其他

- `-X, --exclude-from`：在一个文件中列出要排除的目录或文件（在`--exclude=`较多时使用）
- `-t, --list`：列出备份档案中的文件列表，不与`-c`、`-x`同时出现
- `-j, --bzip2`：使用bzip2工具（解）压缩，后缀一般为`.bz2`
- `-P`：保留绝对路径，解压时同样会自动解压到绝对路径下
- `-v`：（解）压缩过程显示文件处理过程，常用但不建议对大型文件使用

## 2. 增量备份（网站）数据 ##
许多系统（应用或网站）每天都有静态文件产生，对于一些比较重要的静态文件如果有进行定期备份的需求，就可以通过tar打包压缩备份到指定的地方，特别是对一些总文件比较大比较多的情况，还可以利用-g选项来做增量备份。

备份的目录最好使用相对路径，也就是进入到需要备份的根目录下

具体示例方法如下。
```
备份当前目录下的所有文件
# tar -g /tmp/snapshot_data.snap -zcpf /tmp/data01.tar.gz .

在需要恢复的目录下解压恢复
# tar -zxpf /tmp/data01.tar.gz -C .
```
`-g`选项可以理解备份时给目录文件做一个快照，记录权限和属性等信息，第一次备份时`/tmp/snapshot_data.snap`不存在，会新建一个并做完全备份。当目录下的文件有修改后，再次执行第一条备份命令（记得修改后面的档案文件名），会自动根据`-g`指定的快照文件，增量备份修改过的文件，包括权限和属性，没有动过的文件不会重复备份。

<!-- more -->

另外需要注意上面的恢复，是“保留恢复”，即存在相同文件名的文件会被覆盖，而原目录下已存在（但备份档案里没有）的，会依然保留。所以如果你想完全恢复到与备份文件一模一样，需要清空原目录。如果有增量备份档案，则还需要使用同样的方式分别解压这些档案，而且要注意顺序。

下面演示一个比较综合的例子，要求：

- 备份`/tmp/data`目录，但`cache`目录以及临时文件排除在外
- 由于目录比较大（>4G），所以全备时分割备份的档案（如每个备份档案文件最大1G）
- 保留所有文件的权限和属性，如用户组和读写权限

```
# cd /tmp/data

做一次完全备份
# rm -f /tmp/snapshot_data.snap
# tar -g /tmp/snapshot_data.snap -zcpf - --exclude=./cache ./ | split -b 1024M - /tmp/bak_data$(date -I).tar.gz_
分割后文件名后会依次加上aa,ab,ac,...，上面最终的备份归档会保存成
bak_data2014-12-07.tar.gz_aa
bak_data2014-12-07.tar.gz_ab
bak_data2014-12-07.tar.gz_ac
...

增量备份
可以是与完全备份一模一样的命令，但需要注意的是假如你一天备份多次，可能导致档案文件名重复，那么就会导致
备份实现，因为split依然会从aa,ab开始命名，如果一天的文件产生（修改）量不是特别大，那么建议增量部分不
分割处理了：（ 一定要分割的话，文件名加入更细致的时间如$(date +%Y-%m-%d_%H) ）
# tar -g /tmp/snapshot_data.snap -zcpf /tmp/bak_data2014-12-07.tar.gz --exclude=./cache ./

第二天增备
# tar -g /tmp/snapshot_data.snap -zcpf /tmp/bak_data2014-12-08.tar.gz --exclude=./cache ./
```

恢复过程
```
恢复完全备份的档案文件
可以选择是否先清空/tmp/data/目录
# cat /tmp/bak_data2014-12-07.tar.gz_* | tar -zxpf - -C /tmp/data/

恢复增量备份的档案文件
$ tar –zxpf /tmp/bak_data2014-12-07.tar.gz -C /tmp/data/
$ tar –zxpf /tmp/bak_data2014-12-08.tar.gz -C /tmp/data/
...
一定要保证是按时间顺序恢复的，像下面文件名规则也可以使用上面通配符的形式
```

如果需要定期备份，如每周一次全备，每天一次增量备份，则可以结合crontab实现。

## 3. 备份文件系统 ##
备份文件系统方法有很多，例如cpio, rsync, dump, tar，这里演示一个通过`tar`备份整个Linux系统的例子，整个备份与恢复过程与上面类似。
首先Linux（这里是CentOS）有一部分目录是没必要备份的，如`/proc`、`/lost+found`、`/sys`、`/mnt`、`/media`、`/dev`、`/proc`、`/tmp`，如果是备份到磁带`/dev/st0`则不必关心那么多，因为我这里是备份到本地`/backup`目录，所以也需要排除，还有其它一些NFS或者网络存储挂载的目录。

```
创建排除列表文件
# vi /backup/backup_tar_exclude.list
/backup
/proc
/lost+found
/sys
/mnt
/media
/dev
/tmp

$ tar -zcpf /backup/backup_full.tar.gz -g /backup/tar_snapshot.snap --exclude-from=/backup/tar_exclude.list /

```

## 4. 注意 ##
使用tar无论是备份数据还是文件系统，需要考虑是在原系统上恢复还是另一个新的系统上恢复。

- tar备份极度依赖于文件的atime属性，
- 文件所属用户是根据用户ID来确定的，异机恢复需要考虑相同用户拥有相同USERID
- 备份和恢复的过程尽量不要运行其他进程，可能会导致数据不一致
- 软硬连接文件可以正常恢复

## 参考 ##
- [tar高级教程：增量备份、定时备份、网络备份](https://lesca.me/archives/how-to-incrementally-backup-linux-with-gnu-tar.html)
- [Linux服务器数据备份恢复的详细讲解](http://tech.watchstor.com/backup-and-archiving-115687.htm)


