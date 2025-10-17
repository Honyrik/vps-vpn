#!/usr/bin/env bash
cd /opt/router/gen
declare -g isReload
isReload=0
for site in $(cat /opt/router/gen/site.list);
do
  dig @1.1.1.1 +short A $site | grep -v -e '\.$' | grep -v "connection timed out" | sort -u >> /opt/router/gen/tmp/${site}.txt.all
  dig @8.8.8.8 +short A $site | grep -v -e '\.$' | grep -v "connection timed out" | sort -u >> /opt/router/gen/tmp/${site}.txt.all
  dig @9.9.9.10 +short A $site | grep -v -e '\.$' | grep -v "connection timed out" | sort -u >> /opt/router/gen/tmp/${site}.txt.all
  curl -H 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=$site&type=A" | jq '.Answer[].data' | sed 's!"!!g' | grep -v -e '\.$' | grep -v "connection timed out" | sort -u >> /opt/router/gen/tmp/${site}.txt.all
  curl -H 'accept: application/dns-json' "https://dns.google/resolve?name=$site&type=A" | jq '.Answer[].data' | sed 's!"!!g' | grep -v -e '\.$' | grep -v "connection timed out" | sort -u >> /opt/router/gen/tmp/${site}.txt.all
  cat /opt/router/gen/tmp/${site}.txt.all | grep -v "connection timed out" | sort -u > /opt/router/gen/tmp/${site}.txt
  cat /opt/router/gen/tmp/${site}.txt > /opt/router/gen/tmp/${site}.txt.all
  new=$(md5sum /opt/router/gen/tmp/${site}.txt)
  check=$(md5sum -c /opt/router/gen/tmp/${site}.txt.md5 --quiet 2>/dev/null | wc -l)
  if [[ $check -ne 0 ]] || [ ! -f /opt/router/gen/tmp/${site}.txt.md5 ]; then
    echo "">/etc/bird/conf.d/${site}.conf
    cat /opt/router/gen/tmp/${site}.txt | sort -u | while read line
    do
      echo "route $line/32 reject;" >> /etc/bird/conf.d/${site}.conf 
    done
    isReload=1
  fi
  echo $new > /opt/router/gen/tmp/${site}.txt.md5
done
if [[ $isReload -ne 0 ]]; then
   # echo "reload"
   /usr/sbin/birdc configure
fi
