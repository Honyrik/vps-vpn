# vps-vpn

Скрипты помощь vps vpn centos (openvpn + wireguard + bgp)

# Установка

```bash
#CENTOS 7
curl https://copr.fedorainfracloud.org/coprs/amneziavpn/amneziawg/repo/epel-7/amneziavpn-amneziawg-epel-7.repo -o /etc/yum.repos.d/amneziavpn-amneziawg-epel-7.repo
yum install -y bird2 openvpn curl kmod-wireguard wireguard-tools easy-rsa dnsmasq wget knock-server amneziawg-dkms amneziawg-tools fail2ban
pip3 install --upgrade setuptools wheel --break-system-packages
pip3 install Jinja2 --break-system-packages
#DEBIAN
sudo apt upgrade
reboot
sudo apt install -y curl wget python3-launchpadlib python3-pip gnupg2 linux-headers-$(uname -r)
pip3 install --upgrade setuptools wheel --break-system-packages
pip3 install Jinja2 --break-system-packages
curl 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x75c9dd72c799870e310542e24166f2c257290828' -o /etc/apt/trusted.gpg.d/amnezia.asc
echo "deb https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu noble main" | sudo tee -a /etc/apt/sources.list.d/amnezia.list
echo "deb-src https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu noble main" | sudo tee -a /etc/apt/sources.list.d/amnezia.list
sudo apt update
sudo apt install -y bird2 openvpn wireguard wireguard-tools easy-rsa dnsmasq knockd amneziawg amneziawg-tools fail2ban ufw jq cron dnsutils
sudo bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

```bash
ln -s /etc/wireguard/wg-gen/wg-gen.py /usr/bin/wg-gen
ln -s /etc/amnezia/amneziawg/awg-gen/awg-gen.py /usr/bin/awg-gen
ln -s /etc/openvpn/server/ovpn-generate/ovpn-gen.py /usr/bin/ovpn-gen
#CENTOS7
mkdir -p /usr/share/easy-rsa/3/pki
mkdir -p /etc/openvpn/server/keys
ln -s /usr/share/easy-rsa/3/pki /etc/openvpn/server/keys
cp /usr/share/easy-rsa/3/vars.example /usr/share/easy-rsa/3/vars
#DEBIAN
mkdir -p /usr/share/easy-rsa/pki
mkdir -p /etc/openvpn/server/keys
ln -s /usr/share/easy-rsa/pki /etc/openvpn/server/keys
cp /usr/share/easy-rsa/vars.example /usr/share/easy-rsa/vars
```

редактируем:

-   /usr/share/easy-rsa/3/vars [EasyRSA](https://community.openvpn.net/openvpn/wiki/EasyRSA3-OpenVPN-Howto)
-   /etc/openvpn/server/ovpn-generate/vars
-   /etc/wireguard/wg-gen/vars

```bash
#CENTOS7
cd /usr/share/easy-rsa/3
#DEBIAN
cd /usr/share/easy-rsa

./easyrsa init-pki
./easyrsa gen-dh
./easyrsa build-ca --days 3650 nopass
./easyrsa build-server-full server --days 1095 nopass
openvpn --genkey --secret /etc/openvpn/server/keys/ta.key
/usr/bin/wg genkey | /usr/bin/tee /etc/wireguard/server_private.key | /usr/bin/wg pubkey | /usr/bin/tee /etc/wireguard/server_public.key
sed -i.bak -e "s/^PrivateKey.*$/PrivateKey = $(cat /etc/wireguard/server_private.key)/g" /etc/wireguard/wg0.conf

/usr/bin/awg genkey | /usr/bin/tee /etc/amnezia/amneziawg/server_private.key | /usr/bin/awg pubkey | /usr/bin/tee /etc/amnezia/amneziawg/server_public.key
sed -i.bak -e "s/^PrivateKey.*$/PrivateKey = $(cat /etc/amnezia/amneziawg/server_private.key)/g" /etc/amnezia/amneziawg/awg0.conf
```

редактируем:

-   /etc/openvpn/server/server.conf
-   /etc/wireguard/wg0.conf
-   /etc/amnezia/amneziawg/awg0.conf

# Добавляем cron

```bash
crontab -e
```

```
*/30 * * * * /opt/router/downloadbgp
*/30 * * * * /opt/router/gen/gen_list.sh
0 1 * * * /usr/bin/systemctl restart openvpn-server@server.service 2>&1 1>>/dev/null
```

# Стартуем

```bash
systemctl enable bird
systemctl start bird
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
systemctl enable awg-quick@awg0
systemctl start awg-quick@awg0
systemctl enable openvpn-server@server
systemctl start openvpn-server@server
systemctl enable knockd
systemctl start knockd
systemctl enable dnsmasq
systemctl start dnsmasq
#CENTOS
firewall-cmd --zone=public --permanent --add-masquerade
firewall-cmd --zone=trusted --permanent --add-masquerade
firewall-cmd --permanent --zone=trusted --add-interface=wg0
firewall-cmd --permanent --zone=trusted --add-interface=tun0
firewall-cmd --permanent --zone=public --add-port=443/tcp
firewall-cmd --permanent --zone=trusted --add-service=named
firewall-cmd --permanent --zone=trusted --add-service=bird
firewall-cmd --permanent --zone=public --add-service=openvpn-tcp
firewall-cmd --permanent --zone=public --add-service=wg
firewall-cmd --permanent --zone=public --add-service=awg
firewall-cmd --reload
#DEBIAN
ufw allow OpenSSH               # Или ufw allow 2222/tcp для кастомного порта после настройки knockd можно удалить
ufw allow 443/tcp               # HTTPS, если нужно
ufw allow 443/udp
ufw allow openvpn-tcp
ufw allow wg
ufw allow v2ray
ufw allow awg
ufw allow from 192.168.57.0/24 to 192.168.57.1/32 app BIRD
ufw allow from 192.168.58.0/24 to 192.168.58.1/32 app BIRD
ufw allow from 192.168.59.0/24 to 192.168.59.1/32 app BIRD
ufw allow from 192.168.57.0/24 to 192.168.57.1/32 app Named
ufw allow from 192.168.58.0/24 to 192.168.58.1/32 app Named
ufw allow from 192.168.59.0/24 to 192.168.59.1/32 app Named
ufw allow from 192.168.57.0/24 to 192.168.57.1/32 app OpenSSH
ufw allow from 192.168.58.0/24 to 192.168.58.1/32 app OpenSSH
ufw allow from 192.168.59.0/24 to 192.168.59.1/32 app OpenSSH
ufw route allow in on wg0 out on ens3
ufw route allow in on wg1 out on ens3
ufw route allow in on awg0 out on ens3
ufw route allow in on tun0 out on ens3
ufw default deny incoming
ufw default allow outgoing
ufw default allow FORWARD
ufw enable
systemctl enable ufw
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/forward.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.d/forward.conf
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv4.ip_forward=1


```

# Создание настроек клиентов

## Клиент openvpn

```bash
ovpn-gen client1
```

## Клиент wg or awg

```bash
wg-gen client1 ip
```

ip - любой адрес в пределе (/etc/wireguard/wg-gen/vars route)

```bash
awg-gen client1 ip
```

ip - любой адрес в пределе (/etc/amnezia/amneziawg/awg-gen/vars route)
