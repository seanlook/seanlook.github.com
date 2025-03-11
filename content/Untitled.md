
```
#创建一个5G大的test.txt文件 
dd if=/dev/zero of=test.txt count=10 bs=512M 

#创建一个5G大的test.txt文件，但显示容量为10G 
dd if=/dev/zero of=test.txt count=10 bs=512M seek=10
```