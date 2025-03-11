#/bin/bash

cat b.sh | while read url
do
  #filename=`echo $url | awk -F/ '{print $5}'`.md
  filename=`echo $url | awk -F/ '{print $4 ":::"$0}'`.md
  echo $filename
done
