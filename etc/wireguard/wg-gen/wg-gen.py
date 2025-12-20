#!/usr/bin/env python2
# -*- coding: utf-8 -*-

from jinja2 import Template
import sys
import os.path
import subprocess
'''Generate an .ovpn file from a set of user keys
to be used with an ovpn client.
'''

print(sys.argv)

try:
  username = sys.argv[1]
except:
  print 'Error: Supply a username!'
  sys.exit()

try:
  ip = sys.argv[2]
except:
  print 'Error: Supply a ip!'
  sys.exit()

force = next((True for item in sys.argv if item == '--force'), False)
separator = "="
envs = {}

with open('/etc/wireguard/wg-gen/vars') as f:
    for line in f:
        if separator in line:
            name, value = line.split(separator, 1)
            envs[name.strip()] = value.strip()

server = envs["server"]
dns = envs["dns"]
route = envs["route"]
serverPublicPath = '/etc/wireguard/server_public.key'
userkey = '/etc/wireguard/client/' + username + '_private.key'
userpublickey = '/etc/wireguard/client/' + username + '_public.key'
userwg = '/etc/wireguard/client-gen/' + username + '.wg'
oldpublickey = ''

if os.path.isfile(userkey) and force:
  with open(userpublickey) as publickeyfile:
    oldpublickey = publickeyfile.read().strip()

if not os.path.isfile(userkey) or force:
  subprocess.call(['/usr/bin/wg genkey | /usr/bin/tee /etc/wireguard/client/' + username +'_private.key | /usr/bin/wg pubkey | /usr/bin/tee /etc/wireguard/client/' + username + '_public.key'], shell=True)

'''
[Interface]
Address = {{ip}}/24
DNS = {{dns}}
PrivateKey = {{privatekey}}

[Peer]
PublicKey = {{public-key-server}}
AllowedIPs = {{route}} # to allow untunneled traffic, use `0.0.0.0/1, 128.0.0.0/1` instead
Endpoint = {{server}}
PersistentKeepalive = 25
'''

with open('/etc/wireguard/wg-gen/templates/wg.template') as wgtemplate, \
        open(serverPublicPath) as serverPublicFile, \
        open(userkey) as keyfile, \
        open(userpublickey) as publickeyfile, \
        open(userwg, 'w') as outfile:
  model = Template(wgtemplate.read())
  keyvalue = keyfile.read().strip()
  publickeyvalue = publickeyfile.read().strip()
  serverPublicvalue = serverPublicFile.read().strip()
  outfile.write(model.render(ip=ip,dns=dns,route=route,publickeyserver=serverPublicvalue,privatekey=keyvalue,server=server))
  if oldpublickey != '':
    subprocess.call(['wg set wg0 peer "'+ oldpublickey +'" remove'], shell=True)
  subprocess.call(['wg set wg0 peer "'+ publickeyvalue +'" allowed-ips ' + ip + '/32'], shell=True)
  print 'wg file generated: ' + userwg

