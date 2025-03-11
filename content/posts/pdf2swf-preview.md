---
title: 仿豆丁网文件在线浏览解决方案搭建
date: 2015-05-13 01:21:25
aliases:
- /2015/05/13/pdf2swf-preview/
updated: 2015-05-13 00:46:23
tags: [linux]
categories: [Linux]
---

在公司OA和CRM系统遇到要实现在线查看word/jpg等文件的功能，按照开发小组的要求搭建了一套解决方案：OpenOffice + JodConvertor  + SWFTool+ FlexPaper，其中OpenOffice + JodConvertor用于将文档转化为PDF格式文档，SwfTool用于将PDF转化为SWF文档，FlexPaper用于展示。使用这个解决方案的最大好处就是跨平台且较为简单。

## 1.1 安装openoffice ##
openoffice需要jdk的支持，而且默认已经安装，如果没有，手动下载`Apache_OpenOffice_4.0.1_Linux_x86-64_install-rpm_zh-CN.tar.gz`到`/usr/local/src`（CentOS 6.4 x86_64）：
```
# tar -zxf Apache_OpenOffice_4.0.1_Linux_x86-64_install-rpm_zh-CN.tar.gz
# cd zh-CN/RPMS
# rpm –ivh *.rpm
```

**拷贝字体**
安装完成后把windows（`c:\windows\fonts`）下的一些常用字体拷贝到 `/opt/openoffice4/share/fonts/truetype` 目录下，如Arial, Calibri, Courier New, Consolas等，如果你想正确的保留原doc的中文字体，还需要把 黑体、微软雅黑、宋体 常规、新宋体 常规、幼圆、隶书、楷体 等中文字体拷贝进去（重启进程后生效）。

**启动后台进程**
切换至普通用户，如wxcrm启动转换进程：
```
$ /opt/openoffice4/program/soffice -headless -accept="socket,host=127.0.0.1,port=8100;urp;" -nofirststartwizard &

# ps –ef | grep soffice
```
## 1.2 解压jodconverter ##
JODConverter是一个java的OpenDucument文件转换器，可以进行许多文件格式的转换工具，它利用OpenOffice来进行转换工作，它能完成以下转换：

1. Microsoft Office格式转换为OpenDucument，以及OpenDucument转换为Microsoft Office
2. OpenDucument转换为PDF，Word、Excel、PowerPoint转换为PDF，RTF转换为PDF等。

从 http://sourceforge.net/projects/jodconverter/files/JODConverter/2.2.2/ 下载`jodconverter-2.2.2.zip`解压到 /opt 目录下`/opt/jodconverter-2.2.2/`。手动转换测试，使用到的文件是安装包内的lib/jodconverter-cli-2.2.2.jar：
```
java -jar /opt/jodconverter-2.2.2/lib/jodconverter-cli-2.2.2.jar /home/oa/docker.docx /home/oa/docker.pdf
```
至此doc等文件格式可以成功转换成pdf。

## 2.1 swftool ##

swftool可以将pdf/jpg等转换成swf格式。搜索下载`swftools-0.9.1.tar.gz`（0.9.2在安装时可能需要错误处理）：

<!-- more -->

```
# yum install gcc* automake zlib-devel libjpeg-devel giflib-devel freetype-devel
# tar vxzf swftools-0.9.1.tar.gz
# cd swftools-0.9.1

# ./configure --prefix=/usr/local/swftools
# make && make install
```

至此已安装完预览功能，可以通过：
```
/usr/local/bin/pdf2swf -t docker4.pdf -o docker4.swf -T 9 -f -z
```
测试转换。`-t` 后接待转换的pdf文件路径，`-o`接输出文件路径和名称，`-T 9` 设置使用flash版本9，这个设置主要是为了跟FlexPaper的版本对应； `-f` 保留字体，`-z`使用zlib进行压缩，这是最常用的几个命令，其他命令可以从SWF官网了解。

## 2.2 安装xpdf语言包 ##
在转换包含中文的PDF文档成swf时，常常会因为缺少所需的字体而出现乱码，或者干脆就没有文字，就需要使用到xpdf的字体库。
到 http://www.foolabs.com/xpdf/download.html 下载`xpdf-chinese-simplified.tar.gz`，解压到`/usr/local`下，编辑add-to-xpdfrc文件，如下：
```
# vi /usr/local/xpdf-chinese-simplified/add-to-xpdfrc
#----- begin Chinese Simplified support package (2011-sep-02)
cidToUnicode    Adobe-GB1       /usr/local/xpdf-chinese-simplified/Adobe-GB1.cidToUnicode
unicodeMap      ISO-2022-CN     /usr/local/xpdf-chinese-simplified/ISO-2022-CN.unicodeMap
unicodeMap      EUC-CN          /usr/local/xpdf-chinese-simplified/EUC-CN.unicodeMap
unicodeMap      GBK             /usr/local/xpdf-chinese-simplified/GBK.unicodeMap
cMapDir         Adobe-GB1       /usr/local/xpdf-chinese-simplified/CMap
toUnicodeDir                    /usr/local/xpdf-chinese-simplified/CMap

fontDir /usr/share/fonts/win
displayCIDFontTT    Adobe-GB1    /usr/share/fonts/win/SIMHEI.ttf
displayCIDFontTT    Adobe-GB1    /usr/local/xpdf-chinese-simplified/CMap/gbsn00lp.ttf
displayCIDFontTT    Adobe-GB1    /usr/local/xpdf-chinese-simplified/CMap/gkai00mp.ttf
```

可以使用xftp将常用的中文字体上传到/usr/share/fonts/win，如宋体、微软雅黑、黑体、楷体等。另外去 [网上下载](http://www.nginxs.com/download/font.zip) gkai00mp.ttf、gbsn00lp.ttf简体中文放到上面正确的路径下，参考http://shitouququ.blog.51cto.com/24569/1252930。

转换时加上`-s languagedir=/usr/local/xpdf-chinese-simplified/`来加载语言包路径。

另外据同事说在 windows 平台安装和转换效果会好一点，没有验证。

**参考**

- [linux安装openoffice与SWFtools工具](http://shitouququ.blog.51cto.com/24569/1252930)
- [仿豆丁网在线浏览文件方案openoffice.org 3+swftools+flexpaper](http://blog.csdn.net/xingkong22star/article/details/38269613)
- [swftools Installation](http://wiki.swftools.org/wiki/Installation)
