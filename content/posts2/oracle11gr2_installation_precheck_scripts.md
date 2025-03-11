---
title: Oracle单实例安装环境一键配置脚本（CentOS6 + 11gR2 ）
date: 2014-12-02 15:21:25
updated: 2014-12-03 00:46:23
tags: [oracle, centos, shell, installation]
categories: Oracle
---

这是自己曾经写的一个oracle 11gR2在CentOS6 x86_64服务器上，一键配置安装环境的脚本，能快速完成安装前环境的配置。

具体完成以下工作：

- 备份系统配置文件，以防出错
- 添加oracle用户和用户组
- 创建安装目录
- 关闭selinux
- 在.bash_profile中修改环境变量
- 修改`sysctl.conf`文件
- 修改`limits.conf`文件
- 修改PAM的login文件
- 安装必要的依赖包

使用注意事项：

- root的用户执行，`chmod +x oraclePreInstCheck.sh`
- `./oraclePreInstCheck.sh`运行后，请仔细阅读说明，再决定是否使用该脚本
- 该脚本默认参数适用于2核4G内存的环境，你可以根据需要修改`kernelset()`部分
- 执行完后，你检查一下你的安装目录及权限（默认`/db/oracle`）
- 该脚本会有提示输入的地方，请不要挑战它的健壮性，比如输入安装根目录时，不要带入空格
- 脚本只需执行一次，修改系统参数如sysctl.conf之前，都有备份成`xxx.ora_bak`
- 请**确保**可以通过yum方式安装软件包（使用挂载DVD镜像或联网）
- 建议结合`tee`将执行过程记录在日志文件中，`./oraclePreInstCheck.sh | tee oraclePreInstCheck.log`

<!-- more -->

oraclePreInstCheck.sh：

```
#!/bin/bash
# author       zhouxiao
# date         2014-03-07
# description  oracle 11g R2 for linux 6.0+ x86_64 安装辅助脚本

#定义常量
SYSCTL=/etc/sysctl.conf
LIMITS=/etc/security/limits.conf
PAM=/etc/pam.d/login
PROFILE=/etc/profile
BASH_PROFILE=/home/oracle/.bash_profile
#循环变量
i=1
#定义显示颜色
#颜色定义 信息(33黄色) 警示(31红色) 过程(36浅蓝)

usage()
{
    echo "Scripts: initialize the required env settings for Oracle 11gR2 installation on Linux 6.0+ x86_64"
    echo "Make sure you have prepared conditions list bellow:"
    echo -e "  \n\e[1;33m yum, hosts, user oracle's passwd, oralce SID, DISPLAY location \e[0m"
    echo "The Script will backup config files with .ora_bak in case failure "
    echo "The Script will set the following change:"
    echo "  - add user oracle and group oinstall/dba/oper, etc."
    echo "  - make directory ORACLE_HOME and change owner"
    echo "  - modify oracle .bash_profile"
    echo "  - modify /etc/sysctl.conf kernel parameters like shmall/shmmax"
    echo "  - modify /etc/security/limits.conf "
    echo "  - install necessary packages like libgcc/libaio/unixODBC, etc."
    echo "  - IF anything goes wrong, you need to recover ora_bak files manually."
    echo -e "\n\e[1;33m Continue? (y/n [n]): \e[0m"
    read singal
    if [ $singal != "y" ]; then
        exit 0
    else
        echo "God Bless you! Settings started."
        echo ""
        echo ""
    fi
}

#判断执行用户是否root
isroot()
{
    if [ $USER != "root" ];then
        echo -e "\n\e[1;31m the user must be root,and now you user is $USER,please su to root. \e[0m"
        exit4
    else
        echo -e "\n\e[1;36m check root ... OK! \e[0m"
    fi
}
#挂在光盘到/mnt/cdrom目录下
mount_cdrom()
{
echo -e "\n\e[1;31m please insert RHEL to CDROM,press any key ...\e[0m"
read -n 1
if [ -d /mnt/cdrom ];then
     mount -t auto -o ro /dev/cdrom /mnt/cdrom
else
    mkdir -p /mnt/cdrom
    mount -t auto -o ro /dev/cdrom /mnt/cdrom
fi
if [ $? -eq 0 ];then
    echo -e "\n\e[1;36m CDROM mount on /mnt/cdrom ... OK! \e[0m"
fi
}
#设置yum本地光盘源
yum_repo()
{
    rm -rf /etc/yum.repos.d/* && cat <<EOF >> /etc/yum.repos.d/Server.repo
[Server]
name=MyRPM
baseurl=file:///mnt/cdrom/Server
enabled=1
gpgkey=file:///mnt/cdrom/RPM-GPG-KEY-redhat-release
EOF
if [ $? -eq 0 ];then
echo -e "\n\e[1;36m  /etc/yum.repos.d/Server.repo  ... OK! \e[0m"
fi
}
#添加oracle用户，添加oracle用户所属组oinstall及附加组dba
ouseradd()
{
    if [[ `grep "oracle" /etc/passwd` != "" ]];then
        userdel -r oracle
    fi
    if [[ `grep "oinstall" /etc/group` = "" ]];then
        groupadd -g 501 oinstall
    fi
    if [[ `grep "dba" /etc/group` = "" ]];then
        groupadd -g 502 dba
        groupadd -g 503 oper
        groupadd -g 504 asmadmin
        groupadd -g 506 asmdba
        groupadd -g 505 asmoper
    fi
    useradd oracle -g oinstall -G dba,asmdba,oper && echo $1 |passwd oracle --stdin
    if [ $? -eq 0 ];then
        echo -e "\n\e[1;36m oracle's password updated successfully  --- OK! \e[0m"
    else
        echo -e "\n\e[1;31m oracle's password set faild.   --- NO!\e[0m"
    fi
}
#检查oracle所需软件包并安装
packagecheck()
{
for package in binutils compat-libcap1 compat-libstdc++-33  compat-libstdc++-33*i686 gcc gcc-c++ glibc glibc-2*i686 glibc-devel glibc-devel-2*i686  glibc-headers-2.* libgcc libgcc-4*i686 libstdc++ libstdc++-4*i686 libstdc++-devel libstdc++-devel-4*i686 libaio-0* libaio-0*i686 libaio-devel libaio-devel-0*i686 unixODBC unixODBC-2*i686 unixODBC-devel unixODBC-devel-2*i686 make sysstat ksh 
do
    rpm -q $package 2> /dev/null
    if [ $? != 0 ];then
        yum -y install $package 2> /dev/null
        echo  -e "\n\e[1;36m $package is installed ... OK! \e[0m"
    fi
done
}
#安装桌面套件 X Window System / Desktop
xdesk()
{
    LANG=C yum -y groupinstall "X Window System" "Desktop"
    if [ $? -eq 0 ];then
        echo  -e "\n\e[1;36m $package is already installed ... OK! \e[0m"
    fi
}
# 设置内核参数
# shmall 物理内存<8G =2097152     >8G MemTotal/4kb
# shmmax 物理内存<8G = 4294967296 >8G 16GMemTotal = 10G=10*1024^3
kernelset()
{
    cp $SYSCTL{,.ora_bak} && cat <<EOF >>$SYSCTL
fs.aio-max-nr = 1048576
fs.file-max = 6815744
kernel.shmall = 2097152
kernel.shmmax = 4294967296
kernel.shmmni = 4096
kernel.sem = 250 32000 100 128
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
EOF
    if [ $? -eq 0 ];then
        echo -e "\n\e[1;36m kernel parameters updated successfully --- OK! \e[0m"
    fi
sysctl -p
}
#设置oracle资源限制
oralimit()
{
    cp $LIMITS{,.ora_bak} && cat <<EOF >> $LIMITS
oracle      soft    nproc   2047
oracle      hard    nproc   16384
oracle      soft    nofile  1024
oracle      hard    nofile  65536
oracle      soft    stack   10240
EOF
    if [ $? -eq 0 ];then
        echo  -e "\n\e[1;36m $LIMITS updated successfully ... OK! \e[0m"
    fi
cat $LIMITS | grep '^o'
}
#设置login文件
setlogin()
{
    cp $PAM{,.ora_bak} && cat <<EOF >>$PAM
session     required    pam_limits.so
EOF
    if [ $? -eq 0 ];then
        echo -e "\n\e[1;36m  $PAM updated successfully ... OK! \e[0m"
    fi
}
#设置profile文件
setprofile()
{
    cp $PROFILE{,.ora_bak} && cat <<EOF >>$PROFILE
if [ $USER = "oracle" ];then
    if [ $SHELL = "/bin/ksh" ];then
        ulimit -p 16384
        ulimit -n 65536
    else
        ulimit -u 16384 -n 65536
    fi
fi
EOF
    if [ $? -eq 0 ];then
        echo -e "\n\e[1;36m  $PROFILE updated successfully ... OK! \e[0m"
    fi
}
#设置oracle的profile文件
setbash_profile()
{
    cp $BASH_PROFILE{,.ora_bak} && cat <<EOF >> $BASH_PROFILE
umask 022

#oracle settings
TMP=/tmp; export TMP

TMPDIR=\$TMP; export TMPDIR
ORACLE_BASE=$1/oracle
ORACLE_HOME=\$ORACLE_BASE/product/11.2.0/db_1
ORACLE_SID=$2
PATH=\$ORACLE_HOME/bin/:\$PATH
LANG=en_US.UTF-8
ORACLE_TERM=xterm
export ORACLE_BASE ORACLE_HOME ORACLE_SID ORACLE_TERM

LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/lib:/usr/lib; export LD_LIBRARY_PATH
CLASSPATH=\$ORACLE_HOME/jre:\$ORACLE_HOME/jlib:\$ORACLE_HOME/rdbms/jlib
export CLASSPATH

EOF
    if [ $? -eq 0 ];then
        echo -e "\n\e[1;36m $BASH_PROFILE updated successfully ... OK! \e[0m"
    fi
su - oracle -c source $BASH_PROFILE
}
#系统环境检查
oscheck()
{
#查看内存大小是否大于1G
echo -e "\n check MEM Size ..."
if [ `cat /proc/meminfo | grep MemTotal | awk '{print $2}'` -lt 1048576 ];then
    echo  -e "\n\e[1;33m Memory Small \e[0m"
    exit 1
else
    echo -e "\n\e[1;36m Memory checked PASS \e[0m"
fi
#查看tmp空间大小
echo -e "\n check tmpfs Size ..."
cp /etc/fstab{,.ora_bak}
while true;do
if [ `df | awk '/tmpfs/ {print $2}'` -lt 1048576 ];then
    echo -e "\n\e[1;33m tmpfs Smaill \e[0m"
    sed -i '/tmpfs/s/defaults/defaults,size=1G/' /etc/fstab && mount -o remount /dev/shm
    if [ $? != 0 ];then
    i=i+1
        if [ $i -eq 3 ];then
            echo -e "\n\e[1;31m set tmpfs faild. \e[0m"
            exit 3
        fi
    else
        echo -e "\n\e[1;36 tmpfs updated successfully. \e[0m"
        break
    fi
else
    echo -e "\n\e[1;36m tmpfs checked PASS \e[0m"
    break
fi
done
}

usage

#停止防火墙IPTABLES
service iptables stop
#chkconfig iptables off
#关闭SELINUX
cp /etc/selinux/config{,.ora_bak} && sed -i '/SELINUX/s/enforcing/disabled/;/SELINUX/s/permissive/disabled/'   /etc/selinux/config
setenforce 0
#执行以上函数
isroot
#oscheck
#yum_repo
#mount_cdrom
packagecheck
#xdesk
kernelset
oralimit
setlogin
setprofile
echo -e "\n\e[1;33m please input oracle's user passwd: \e[0m"
read oraclepw
ouseradd $oraclepw

echo -e "\n\e[1;33m please input oracle install PATH (default /db) \e[0m"
read oraclepath
if [ -z $oraclepath ];then
    oraclepath=/db
fi
if [ ! -x "$oraclepath" ];then
    mkdir -p "$oraclepath"
    chown oracle.oinstall $oraclepath
    echo -e "\n\e[1;36 $oraclepath created. \e[0m"
fi

echo -e "\n\e[1;33m  please input oracle_sid, just for env (default TSDB) \e[0m"
read orasid
if [ -z orasid ];then
    orasid=TSDB
fi
setbash_profile $oraclepath $orasid
mkdir -p $oraclepath/oracle/product/11.2.0/db_1 && chown -R oracle:oinstall $oraclepath && chmod -R 755 $oraclepath
unset i

echo -e "\n\e[1;33m please input where to display the X Window (default 127.0.0.1:0.0) \e[0m" 
read xdpy
if [ -z $xdpy ];then
    xdpy=127.0.0.1:0.0
fi
su - oracle -c export DISPLAY=$xdpy && host +

echo -e "\n\e[1;35m Oracle install pre-setting finish! && please run oracle installer as user oracle \e[0m"

```
