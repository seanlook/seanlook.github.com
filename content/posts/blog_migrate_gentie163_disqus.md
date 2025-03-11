---
title: 网易云跟帖迁移评论到disqus
date: 2017-08-29 16:32:49
tags: [mysql, blog]
categories:
- MySQL
updated: 2017-08-29 16:32:49
---


早前折腾博客的时候，在众多评论系统中选择了多说，用了2年结果多说倒闭了，也算是影响了网络上众多的站点。

于是在16年的时候把评论换成了网易云跟帖，以为有网易这个靠山，体验虽然差点但是不会轻易关闭。云跟帖还提供了从多说直接导入的工具，随意旧的评论直接弄过来了。

可谁想不到一年，网易云跟帖也关闭了。

现在不怎么去折腾博客这玩意了，往里面写写东西才是王道，所以就决定直接把评论系统换成国外的 disqus，总不至于国内种种原因关闭了，代价就是要懂得科学上网，考虑博客的受众都是IT同仁，也就只好这样了。

然而被坑了，网上有许多文章和工具可以[从多说迁移到disqus](https://github.com/JamesPan/duoshuo-migrator/blob/master/duoshuo-migrator.py)，但是几乎没看到从网易云跟帖迁移到disqus，三者导出的评论格式不一样。云跟帖导出的是 json，disqus导入是扩展的Wordpress格式。

在拖了3个月后，找到了从网易云跟帖备份出来的旧评论文件，简单用python转换了一下，现在可以用了。

WXR格式：https://help.disqus.com/customer/portal/articles/472150-custom-xml-import-format

**转换代码gist地址**：https://gist.coding.net/u/seanlook/c395cda7c5f4421b85efcd898a8fdf21  (comments_convert.py)

云跟帖导出文件命名为 gentie163.py，懒得用python处理，直接修改这个文件的内容为 python 字典定义：
```
sed -i 's/"url":"xgknight.com/"url":"http:\/\/xgknight.com/g' gentie163.py
sed -i 's/false/False/g' gentie163.py
sed -i 's/:null/:""/g' gentie163.py
sed -i 's/^/comments = /' gentie163.py
```

字典直接转xml比较容易：http://python3-cookbook.readthedocs.io/zh_CN/latest/c06/p05_turning_dictionary_into_xml.html#


转换后的文件为 `data_output.xml`:
```
# python3 comments_convert.py
```

在这个页面导入：https://seanlook.disqus.com/admin/discussions/import/platform/generic/

可在页面 https://import.disqus.com/ 看到import进度，包括失败信息。（不要重复导入）

说明：
- disqus每篇文章有个thread_idendifier，这里处理直接根据文章的时间戳转换来用，不影响
- dsq:remote是设置单点登录，没去深究，直接丢弃这个属性了
- 头像信息丢失(因为sso)


---

本文链接地址：http://xgknight.com/2017/08/29/blog_migrate_gentie163_disqus/

---
