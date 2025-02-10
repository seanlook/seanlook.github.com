title: Linux下rar及zip压缩包中批量替换某文件脚本
date: 2015-01-29 18:21:25
updated: 2015-01-30 11:46:23
tags: [script, shell]
categories: Linux
---

本需求是自己负责的一个生产系统上，有大量以zip和rar结尾的压缩文件散落在文件系统的各个文件夹，先在需要把压缩包里包含某一个特定文件（如tftpd32.exe或Tftpd32.exe，版本较旧），全都替换成比较新的tftpd32.exe版本。压缩文件总数约5000个，需要替换的数量约1500个。

因为是生产环境，不敢轻易乱动，所以脚本考虑的因素就非常多，不允许中间执行过程出现异常，所以找到文件后实际执行替换操作之前做好备份，并且将操作过程记录日志。

以下几点需要考虑：

- 分别处理zip和rar文件，为减低脚本的复杂程度，分作两个shell脚本。
- rar在Linux下默认是没有安装解压缩工具，下载rarlinux-x64-5.2.0.tar.gz
- zip包中文件含有中文文件名，unzip测试解压缩或列出内容时出现文件名乱码，原因是zip在压缩时不记录当时的编码格式。这个问题非常棘手，乱码打进压缩包是绝对不允许的，网上[有几种解压办法](http://www.zhihu.com/question/20523036)有几种办法都不能很好的应对我的场景：并不需要实际解压zip文件，而只需使用 `l` ——列出文件列表、获取目录及文件名，`d` ——从压缩包中直接删除某个文件，`a` ——向压缩包添加一个文件。实际解压到文件系统上是不是乱码我们并不关心。
最后的解决办法是使用`p7zip`工具，配合`LANG`变量解决。
- 向压缩包里添加新文件时，要保持里面的目录结构，则必须在文件系统上存在同样的 相对目录/文件 。所以每次都要在脚本执行目录下创建临时目录tmp_dir，还要及时删除。但如果文件在压缩包的根目录下，这个临时目录就是当前脚本执行目录。
- 有可能会存在一个压缩包中多个文件夹中包含不止一个tftpd32.exe文件。
- 每个文件都有一个CRC值，处理文件名大小写不同但实质是同一个文件时有效。

<!-- more -->

以下脚本使用说明：

- 变量说明
  - `filelist` 变量设定你所需要检查的压缩文件列表（绝对路径），可以通过`find /your/dir/ -name *.rar | sort | uniq  > testfile`。与脚本在相同目录下，并且为unix格式
  - `existlist` 变量是从`filelist`文件中得到的包含特定文件的列表，脚本执行完后可以查看
  - `errorlist` 变量是从`filelist`文件列表中得到的不包含特定文件的列表，当然也有可能这个压缩文件本身不完整
  - `filebak` 变量指定要替换的那个压缩文件备份的目录
  - `oldfile` 指定要替换的那个文件名
  - `newfile` 指定新文件的文件名，注意这个文件一定要在脚本当前目录下
  - `binrar`,`bin7z` 指定解压缩命令目录，因为`7z`和`rar`都不是CentOS自带的
  - `fl` 是`filelist`文件列表里的每一条记录
  - `exist` 压缩文件`fl`的内容列表里包含tftpd32.exe的记录，可能有多行
  - `dirfiles` 处理`exist`的结果，形如压缩包里的目录结构 `your/dir/tftpd32.exe`，可能有多行
  - `df` 是`dirfiles`中的单行记录，它的前面目录部分便是`tmp_dir`
- 是否有必要root用户执行看个人情况，执行后部分文件的属主可能会变，可用`chown user1.user1 -R /your/dir/`恢复
- 有部分zip文件无法使用7z，但文件本身正常，从日志可以看到error信息
- tftpd32.exe区分大小写，如果要查找替换Tftpd32.exe请修改后在执行（确保grep没有`-i`选项）
- 可以处理的情况
  - 压缩文件中无tftpd32.exe
  - 要替换的tftpd32.exe文件在压缩文件根目录下
  - 要替换的tftpd32.exe在嵌套子目录中
  - 压缩文件中存在多个tftpd32.exe
  - 压缩文件本身存在问题
- 该脚本有一定的危险性（虽然已备份），在正式环境中运行之前一定要多做测试。并且运行一次之后，谨慎运行第二次，因为可能会导致备份被覆盖（可换备份目录）
- 假如出现异常，要从备份文件恢复所有修改的文件，可以根据`$existlist`和`filebak`下的目录列表拼凑`cp`语句
- 建议执行方法`./rar_new.sh | tee your.log`，事后可从`your.log`中查看日志

处理rar的脚本`rar_new.sh`:

```
#!/bin/bash

filelist="testfile"
# filelist="crm_rar.txt"
existlist="${filelist}.exist"
errorlist="${filelist}.not"
filebak="/crmbak/rarbak"
oldfile=tftpd32.exe                                                                                                                                          
newfile=tftpd32.exe
binrar="/usr/bin/rar"

IFS=$'\n'

echo "files list bellow have ${oldfile}:" > $existlist
echo "files list bellow do not have ${oldfile} or may have error:" > $errorlist

for fl in `cat $filelist`
  do 
    # ${oldfile} exist or not, file error or not
    exist=`$binrar l $fl |grep ${oldfile}`
    if [ $? -ne 0 ];then
       echo "$fl" >> $errorlist
       continue
    else
        # get extracting dir and filename, could be more than one file
       dirfiles=`echo "$exist" | awk '{for (i=5;i<=NF;i++) printf $i" " ; print ""}'`
    fi

#    echo "$exist"

    if [ "$dirfiles" != "" ];then
      echo "$fl" | tee -a $existlist
      # backup original file
      /bin/cp -af "$fl" "$filebak/"
      echo "--- $fl is backed up in $filebak"
      echo "    $dirfiles"

      for df in `echo "$dirfiles"`
        do
          # create temp directory to put new ${newfile} for compress
          tmp_dir=$( echo "$df" | awk -F '/' '{for(i=1;i<NF;i++) printf"%s/",$i} {print ""}' )
          if [ ${#tmp_dir} -ne 0 ];then
            mkdir -p "$tmp_dir" && cp -af ${newfile} "$tmp_dir"
          fi 
          # start delete old file and add new one
          $binrar d "$fl" "$tmp_dir"${oldfile} && $binrar a "$fl" "$tmp_dir"${newfile}
          if [ $? -ne 0 ];then                                                                                                                             
            echo "--- rar file $fl may have error, you SHOULD check it"
          fi

          if [ ${#tmp_dir} -ne 0 ];then
            rm -f "$tmp_dir"${newfile} && rmdir -p "$tmp_dir"
            if [ $? -ne 0 ];then
              echo "--- tmp_dir $tmp_dir delete fail"
            fi
          fi
        done

      echo "--- old deleted, new added"
    fi

  done
```

处理zip的脚本`zip_new.sh`:(两脚本相差很小，主要是为了谨慎起见减低脚本的复杂度)

```
#!/bin/bash

# filelist="test_filelist"
filelist="crm_zip.txt"
existlist="${filelist}.exist"
errorlist="${filelist}.not"
filebak="/crmbak/zipbak"
oldfile=tftpd32.exe
newfile=tftpd32.exe
bin7z="/usr/bin/7z"

export LANG="zh_CN.GB18030"
IFS=$'\n'

echo "files list bellow have ${oldfile}:" > $existlist
echo "files list bellow do not have ${oldfile} or may have error:" > $errorlist

for fl in `cat $filelist`
  do 
    # ${oldfile} exist or not, file error or not
    exist=`$bin7z l $fl |grep ${oldfile}`
    if [ $? -ne 0 ];then
       echo "$fl" >> $errorlist
       continue
    else
        # get extracting dir and filename, could be more than one file
       dirfiles=`echo "$exist" | awk '{for (i=6;i<=NF;i++) printf $i" " ; print ""}'`
    fi

# echo ===== "$dirfiles"

    if [ "$dirfiles" != "" ];then
      echo "$fl" | tee -a $existlist
      # backup original file
      /bin/cp -af "$fl" "$filebak/"
      echo "--- $fl is backed up in $filebak"
      echo "    $dirfiles"

      for df in `echo "$dirfiles"`
        do
          # create temp directory to put new ${newfile} for compress
          tmp_dir=$( echo "$df" | awk -F '/' '{for(i=1;i<NF;i++) printf"%s/",$i} {print ""}' )
          if [ ${#tmp_dir} -ne 0 ];then
            mkdir -p "$tmp_dir" && cp -af ${newfile} "$tmp_dir"
          fi 
          # start delete old file and add new one
          $bin7z d "$fl" "$tmp_dir"${oldfile} && $bin7z a "$fl" "$tmp_dir"${newfile}
          if [ $? -ne 0 ];then                                                                                                                             
            echo "--- zip file $fl may have error, you SHOULD check it"
          fi
 
          if [ ${#tmp_dir} -ne 0 ];then
            rm -f "$tmp_dir"${newfile} && rmdir -p "$tmp_dir"
            if [ $? -ne 0 ];then
              echo "--- tmp_dir $tmp_dir delete fail"
            fi
          fi
        done

      echo "--- old deleted, new added"
    fi

  done
```