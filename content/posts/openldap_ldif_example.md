---
title: LDIF修改ldap记录或配置示例
date: 2015-01-22 01:21:25
aliases:
- /2015/01/22/openldap_ldif_example/
updated: 2015-01-22 10:46:23
tags: [LDAP, ldif]
categories: [Linux, OpenLDAP]
---

可以说LDIF文件是OpenLDAP操作数据或修改配置的一切来源，下面是实际通过客户端工具操作的具体示例。（openldap安装及配置过程见[这里](http://xgknight.com/2015/01/21/openldap-install-guide-ssl/)）。

### 1. 添加组织或条目 ###

创建一个Marketing部门，添加一个dn记录：
```
# cat add_entry.ldif
dn: ou=Marketing, dc=example,dc=com
changetype: add
objectclass: top
objectclass: organizationalUnit
ou: Marketing

dn: cn=Pete Minsky,ou=Marketing,dc=example,dc=com
changetype: add
objectclass: person
objectclass: organizationalPerson
objectclass: inetOrgPerson
cn: Pete Minsky
sn: Pete
ou: Marketing
description: sb, sx
description: sx
uid: pminsky
```

```
# ldapmodify -xWD 'cn=admin,dc=example,dc=com' -f add_entry.ldif

或去掉changetype后
# ldapmodify -a -xWD 'cn=admin,dc=example,dc=com' -f add_entry.ldif
# ldapadd -xWD 'cn=admin,dc=example,dc=com' -f add.ldif
```

<!-- more -->

### 2. 修改组织或条目 ###

添加mail属性，修改sn的值，删除一个description属性：
```
# cat modify_entry.ldif
dn: cn=Pete Minsky,ou=Marketing,dc=example,dc=com
changetype: modify
add: mail
mail: pminsky@example.com
-
replace: sn
sn: Minsky
-
delete: description
description: sx
```

```
# ldapmodify -xWD 'cn=admin,dc=example,dc=com' -f modify_entry.ldif
# ldapsearch -xD 'cn=admin,dc=mydomain,dc=net' -b 'ou=People,dc=mydomain,dc=net' -s sub 'objectclass=*' -w tplink -LLL
```

### 3. 重命名条目 ###
```
dn: cn=Pete Minsky,ou=Marketing,dc=example,dc=com
changetype: modrdn
newrdn: cn=Susan Jacobs
deleteoldrdn: 1
```

`modrdn`只允许修改dn最左边的部分，且不能重命名带叶子或分支的子树，如果要将一个用户移动到另一个部门下，只能在新部门创建dn，然后删除旧的dn。

### 4. 删除组织或条目 ###
LDAP协议只能删除无分支的叶子dn：
```
# cat delete_entry.ldif
dn: cn=Susan Jacobs,ou=Marketing,dc=example,dc=com
changetype: delete

或
# ldapdelete -xWD "cn=admin,dc=example,dc=com" -h localhost -p 389 "cn=Susan Jacobs,ou=Marketing,dc=example,dc=com"
```

### 5. LDIF配置backend ###
OpenLDAP的配置采用以cn=config为根的目录树的形式组织起来，采用config作为database，默认情况下包括admin或root用户都没有访问权限，需要赋予读写权限，然而赋予修改权限要求首先要提供认证信息，初始化安装后的cn=config是[没有credentials](http://serverfault.com/questions/661151/how-to-modify-rootpw-without-edit-ldif-manually-but-with-ldap-command-tools-in)
```
# ldapmodify -Y EXTERNAL -H ldapi:/// -f modify_config.ldif 
SASL/EXTERNAL authentication started
SASL username: gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth
SASL SSF: 0
modifying entry "olcDatabase={0}config,cn=config"
ldap_modify: Insufficient access (50)
```

所以这里不得不手动编辑`olcDatabase={0}config.ldif`文件，获得最初认证权限（虽然官方不推荐手动修改配置）：
```
# vi /etc/ldap/slapd.d/cn\=config/olcDatabase\=\{0\}config.ldif
olcRootPW: {SSHA}your_slappasswd_secret
```
重启slapd后(不是说不用重启吗)便可以修改config：
```
# ldapwhoami -x -D cn=config -W 

修改示例：
# ldapmodify -xWD 'cn=config' 
Enter LDAP Password: 
dn: olcDatabase={0}config,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=config 
-
replace: olcRootPW
olcRootPW: {SSHA}your_slappasswd_secret

modifying entry "olcDatabase={0}config,cn=config" 
```
在`/etc/ldap/slapd.d/cn=config/olcDatabase={0}config.ldif`中`olcRootDN`变成base64加密后的值（两个":"）。

最后，如果要在slapd服务未启动的情况下修改配置可以通过以下命令转换成ldif中间文件：
```
# slapcat -n0 -F /etc/ldap/slapd.d/ > /tmp/config-in-portable-format.ldif
编辑ldif文件后，重新shengc slapd.d目录
# slapadd -n0 -F /tmp/slapd.d -l /tmp/config-in-portable-format.ldif
```

使用这类命令行工具有助于对 LDAP concept 理解，如果要达到快速配置的效果，可以使用 ldapbrowser 或 [Apache Directory Studio](http://directory.apache.org/studio/users-guide.html) 图形化工具，特别是 Apache Directory Studio 不仅提供了 LDAP Browser/Editor 的功能，还能编辑LDIF文件和自定义schema，智能提示非常友好。
![ldap_apache_directory_studio][1]

**参考**

- [Chapter 6.1.1: OpenLDAP using OLC (cn=config)](http://www.zytrax.com/books/ldap/ch6/slapd-config.html#entries)
- [LDIF Tutorial: slapd.conf](http://www.yolinux.com/TUTORIALS/LinuxTutorialLDAP-SLAPD-LDIF-V2-config.html)


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/ldap_apache_directory_studio.png
