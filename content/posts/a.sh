#/bin/bash

cat b.sh | while read url
do
  filename=`echo $url | awk -F/ '{print $5}'`.md
  echo $filename
  gsed -i "/date: /a\aliases:\n- $url" $filename
done
