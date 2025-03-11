---
title: 高效Linux bash快捷键及alias总结
date: 2014-03-09 01:21:25
aliases:
- /2014/03/09/linux-bash/
updated: 2015-05-10 00:46:23
tags: [bash,linux]
categories: Linux
---

## bash快捷键 ##
习惯使用编辑的快捷键可以大大提高效率，记忆学习过程要有意识的忽略功能键、方向键和数字小键盘。以下快捷键适用在bash处于默认的Emacs模式下，是由一个名为Readline的库实现的，用户可以通过命令bind添加新快捷键，或者修改系统中已经存在的快捷键。（如果你有`set -o vi`，就处于 vi 模式就不适用了）

另外下面的内容并不包含所有快捷键，只是我个人适用频率最高的几种，但相信已经可以大大提高工作效率了。以下所有 Alt 键可以以 Esc 键代替。

- `Ctrl + l` ：清除屏幕，同clear
- `Ctrl + a` ：将光标定位到命令的开头
- `Ctrl + e` ：与上一个快捷键相反，将光标定位到命令的结尾
- `Ctrl + u` ：剪切光标之前的内容，在输错命令或密码
- `Ctrl + k` ：与上一个快捷键相反，剪切光标之后的内容
- `Ctrl + y` ：粘贴以上两个快捷键所剪切的内容。Alt+y粘贴更早的内容
- `Ctrl + w` ：删除光标左边的参数（选项）或内容（实际是以空格为单位向前剪切一个word）
- `Ctrl + /` ：撤销，同`Ctrl+x` + `Ctrl+u`

- `Ctrl + f` ：按字符前移（右向），同→
- `Ctrl + b` ：按字符后移（左向），同←
- `Alt + f` ：按单词前移，标点等特殊字符与空格一样分隔单词（右向），同Ctrl+→
- `Alt + b` ：按单词后移（左向），同Ctrl+←
- `Alt + d` ：从光标处删除至字尾。可以Ctrl+y粘贴回来
- `Alt + \` ：删除当前光标前面所有的空白字符
- `Ctrl + d` ：删除光标处的字符，同Del键。没有命令是表示注销用户
- `Ctrl + h` ：删除光标前的字符

- `Ctrl + r` ：逆向搜索命令历史，比history好用
- `Ctrl + g` ：从历史搜索模式退出，同ESC
- `Ctrl + p` ：历史中的上一条命令，同↑
- `Ctrl + n` ：历史中的下一条命令，同↓
- `Alt + . `：同!$，输出上一个命令的最后一个参数（选项or单词）。
还有如Alt+0 Alt+. Alt+.，表示输出上上一条命令的的第一个单词（即命令）。
另外有一种写法 `!:n`，表示上一命令的第n个参数，如你刚备份一个配置文件，马上编辑它：`cp nginx.conf nginx.conf`，`vi !:1`，同`vi !^`。`!^`表示命令的第一个参数，`!$`最后一个参数（一般是使用`Alt + .`代替）。

<!-- more -->

这里提一下按字符或字符串，向左向后搜索字符串的命令：

- `Ctrl + ]`　c ：从当前光标处向*右*定位到`字符` c 处
- `Esc`　`Ctrl + ]`　c ：从当前光标向*左*定位到`字符` c 处。（ bind -P 可以看到绑定信息）
- `Ctrl + r`　str ：可以搜索历史，也可以当前光标处向*左*定位到`字符串` str，`Esc`后可定位继续编辑
- `Ctrl -s`　str ：从当前光标处向*右*定位到`字符串` str 处，Esc 退出。注意，`Ctrl + S`默认被用户控制 [XON/XOFF](http://superuser.com/questions/124845/can-you-disable-the-ctrl-s-xoff-keystroke-in-putty) ，需要在终端里执行`stty -ixon`或加入profile。

注意上述所有涉及Alt键的实际是Meta键，在xshell中默认是没有勾选“Use Alt key as Meta key”，要充分体验这些键带来的快捷，请在对应的terminal设置。

**参考**：[高效操作Bash](http://ahei.info/bash.htm) ，[Bash (Unix shell) Keyboard shortcuts](http://en.wikipedia.org/wiki/Bash_%28Unix_shell%29#Keyboard_shortcuts) ，[bash中的命令基本操作](http://www.cnblogs.com/nufangrensheng/archive/2013/11/20/3434474.html)。

## 常用alias ##
以下bash中别名设置我还并没有完全使用，也是个人觉得非常有用的（多了记起来也麻烦），所以收集在一起，习惯就好。
`/etc/profile.d/alias.sh`：
```
alias wl='ll | wc -l'
alias l='ls -l'
alias lh='ls -lh'
alias grep='grep -i --color' #用颜色标识，更醒目；忽略大小写
alias vi=vim
alias c='clear'  # 快速清屏
alias p='pwd'

# 进入目录并列出文件，如 cdl ../conf.d/
cdl() { cd "$@" && pwd ; ls -alF; }

alias ..="cdl .."
alias ...="cd ../.."   # 快速进入上上层目录
alias .3="cd ../../.." 
alias cd..='cdl ..'

# alias cp="cp -iv"      # interactive, verbose
alias rm="rm -i"      # interactive
# alias mv="mv -iv"       # interactive, verbose

alias psg='\ps aux | grep -v grep | grep --color' # 查看进程信息

alias hg='history|grep'

alias netp='netstat -tulanp'  # 查看服务器端口连接信息

alias lvim="vim -c \"normal '0\""  # 编辑vim最近打开的文件

alias tf='tail -f '  # 快速查看文件末尾输出

# 自动在文件末尾加上 .bak-日期 来备份文件，如 bu nginx.conf
bak() { cp "$@" "$@.bak"-`date +%y%m%d`; echo "`date +%Y-%m-%d` backed up $PWD/$@"; }

# 级联创建目录并进入，如 mcd a/b/c
mcd() { mkdir -p $1 && cd $1 && pwd ; }

# 查看去掉#注释和空行的配置文件，如 nocomm /etc/squid/squid.conf
alias nocomm='grep -Ev '\''^(#|$)'\'''

# 快速根据进程号pid杀死进程，如 psid tomcat， 然后 kill9 两个tab键提示要kill的进程号
alias kill9='kill -9';
psid() {
  [[ ! -n ${1} ]] && return;   # bail if no argument
  pro="[${1:0:1}]${1:1}";      # process-name –> [p]rocess-name (makes grep better)
  ps axo pid,user,command | grep -v grep |grep -i --color ${pro};   # show matching processes
  pids="$(ps axo pid,user,command | grep -v grep | grep -i ${pro} | awk '{print $1}')";   # get pids
  complete -W "${pids}" kill9     # make a completion list for kk
}

# 解压所有归档文件工具
function extract {
 if [ -z "$1" ]; then
    # display usage if no parameters given
    echo "Usage: extract <path/file_name>.<zip|rar|bz2|gz|tar|tbz2|tgz|Z|7z|xz|ex|tar.bz2|tar.gz|tar.xz>"
 else
    if [ -f $1 ] ; then
        # NAME=${1%.*}
        # mkdir $NAME && cd $NAME
        case $1 in
          *.tar.bz2)   tar xvjf $1    ;;
          *.tar.gz)    tar xvzf $1    ;;
          *.tar.xz)    tar xvJf $1    ;;
          *.lzma)      unlzma $1      ;;
          *.bz2)       bunzip2 $1     ;;
          *.rar)       unrar x -ad $1 ;;
          *.gz)        gunzip $1      ;;
          *.tar)       tar xvf $1     ;;
          *.tbz2)      tar xvjf $1    ;;
          *.tgz)       tar xvzf $1    ;;
          *.zip)       unzip $1       ;;
          *.Z)         uncompress $1  ;;
          *.7z)        7z x $1        ;;
          *.xz)        unxz $1        ;;
          *.exe)       cabextract $1  ;;
          *)           echo "extract: '$1' - unknown archive method" ;;
        esac
    else
        echo "$1 - file does not exist"
    fi
fi
}

# 其它你自己的命令
alias nginxreload='sudo /usr/local/nginx/sbin/nginx -s reload'
```
要去掉别名，请用`unalias aliasname`，或者*临时*执行不用别名，执行原始命令`\alias` 。

欢迎补充评论补充~

**参考**： [30 Handy Bash Shell Aliases For Linux](http://www.cyberciti.biz/tips/bash-aliases-mac-centos-linux-unix.html)
