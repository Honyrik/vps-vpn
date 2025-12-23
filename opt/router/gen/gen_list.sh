#!/usr/bin/env bash
DIR=/opt/router/gen
cd $DIR
mkdir -p $DIR/tmp
declare -g isReload
isReload=0
for site in $(cat $DIR/site.list);
do
  dig @1.1.1.1 +short A $site | grep -v -e '\.$' | grep -v "connection timed out" | sort -u >> $DIR/tmp/${site}.txt.all
  dig @8.8.8.8 +short A $site | grep -v -e '\.$' | grep -v "connection timed out" | sort -u >> $DIR/tmp/${site}.txt.all
  dig @9.9.9.10 +short A $site | grep -v -e '\.$' | grep -v "connection timed out" | sort -u >> $DIR/tmp/${site}.txt.all
  curl -H 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=$site&type=A" | jq '.Answer[].data' | sed 's!"!!g' | grep -v -e '\.$' | grep -v "connection timed out" | sort -u >> $DIR/tmp/${site}.txt.all
  curl -H 'accept: application/dns-json' "https://dns.google/resolve?name=$site&type=A" | jq '.Answer[].data' | sed 's!"!!g' | grep -v -e '\.$' | grep -v "connection timed out" | sort -u >> $DIR/tmp/${site}.txt.all
  cat $DIR/tmp/${site}.txt.all | grep -v "connection timed out" | grep -v "communications error" | grep -v ";" | sort -u > $DIR/tmp/${site}.txt
  cat $DIR/tmp/${site}.txt > $DIR/tmp/${site}.txt.all
  new=$(md5sum $DIR/tmp/${site}.txt)
  check=$(md5sum -c $DIR/tmp/${site}.txt.md5 --quiet 2>/dev/null | wc -l)
  if [[ $check -ne 0 ]] || [ ! -f $DIR/tmp/${site}.txt.md5 ]; then
    echo "">/etc/bird/conf.d/${site}.conf
    cat $DIR/tmp/${site}.txt | sort -u | while read line
    do
      echo "route $line/32 reject;" >> /etc/bird/conf.d/${site}.conf 
    done
    isReload=1
  fi
  echo $new > $DIR/tmp/${site}.txt.md5
done
if [[ $isReload -ne 0 ]]; then
   # echo "reload"
   /usr/sbin/birdc configure
fi
