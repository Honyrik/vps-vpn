# vps-vpn

Скрипты помощь vps vpn centos (openvpn + wireguard + bgp)

# Установка

```bash
yum install -y bird2 openvpn curl kmod-wireguard wireguard-tools easy-rsa dnsmasq wget knock-server
ln -s /usr/share/easy-rsa/3/pki /etc/openvpn/server/keys
ln -s /etc/wireguard/wg-gen/wg-gen.py /usr/bin/wg-gen
ln -s /etc/openvpn/server/ovpn-generate/ovpn-gen.py /usr/bin/ovpn-gen
cd /etc/openvpn/server/ovpn-generate
pip install -r requirements.txt
cp /usr/share/easy-rsa/3/vars.example /usr/share/easy-rsa/3/vars
```

редактируем:

-   /usr/share/easy-rsa/3/vars [EasyRSA](https://community.openvpn.net/openvpn/wiki/EasyRSA3-OpenVPN-Howto)
-   /etc/openvpn/server/ovpn-generate/vars
-   /etc/wireguard/wg-gen/vars

```bash
/usr/share/easy-rsa/3/easyrsa init-pki
/usr/share/easy-rsa/3/easyrsa gen-dh
/usr/share/easy-rsa/3/easyrsa build-ca --days 3650 nopass
/usr/share/easy-rsa/3/easyrsa build-server-full server --days 1095 nopass
openvpn --genkey --secret /etc/openvpn/server/keys/ta.key
/usr/bin/wg genkey | /usr/bin/tee /etc/wireguard/server_private.key | /usr/bin/wg pubkey | /usr/bin/tee /etc/wireguard/server_public.key
sed -i.bak -e "s/^PrivateKey.*$/PrivateKey = $(cat /etc/wireguard/server_private.key)/g" /etc/wireguard/wg0.conf
```

редактируем:

-   /etc/openvpn/server/server.conf
-   /etc/wireguard/wg0.conf

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
systemctl enable openvpn-server@server
systemctl start openvpn-server@server
systemctl enable knockd
systemctl start knockd
firewall-cmd --zone=public --permanent --add-masquerade
firewall-cmd --zone=trusted --permanent --add-masquerade
firewall-cmd --permanent --zone=trusted --add-interface=wg0
firewall-cmd --permanent --zone=trusted --add-interface=tun0
firewall-cmd --permanent --add-forward-port=port=443:proto=tcp:toport=1194
firewall-cmd --permanent --zone=public --add-port=443/tcp
firewall-cmd --permanent --zone=trusted --add-service=named
firewall-cmd --permanent --zone=trusted --add-service=bird
firewall-cmd --permanent --zone=public --add-service=openvpn-tcp
firewall-cmd --permanent --zone=public --add-service=wg
firewall-cmd --reload
```

# Создание настроек клиентов

## Клиент openvpn

```bash
ovpn-gen client1
```

## Клиент wg

```bash
wg-gen client1 ip
```

ip - любой адрес в пределе (/etc/wireguard/wg-gen/vars route)
