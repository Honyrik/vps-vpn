#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from jinja2 import Template
import sys
import os.path
import subprocess
import configparser
'''Generate an .ovpn file from a set of user keys
to be used with an ovpn client.
'''

print(sys.argv)

try:
  username = sys.argv[1]
except:
  print('Error: Supply a username!')
  sys.exit()

try:
  ip = sys.argv[2]
except:
  print('Error: Supply a ip!')
  sys.exit()

force = next((True for item in sys.argv if item == '--force'), False)
separator = "="
left_separator = "["
right_separator = "]"
envs = {}

def simple_parse_awg_config(c):
    config = {}
    section = {}
    for line in c.split('\n'):
        if separator in line:
            name, value = line.split(separator, 1)
            section[name.strip()] = value.strip()
        elif left_separator in line and right_separator in line:
            section_name = line.strip(left_separator + right_separator)
            section = {}
            if section_name not in config:
                config[section_name] = [section]
            else:
                config[section_name].append(section)
    return config

with open('/etc/amnezia/amneziawg/awg-gen/vars') as f:
    for line in f:
        if separator in line:
            name, value = line.split(separator, 1)
            envs[name.strip()] = value.strip()

server = envs["server"]
dns = envs["dns"]
route = envs["route"]
serverPublicPath = '/etc/amnezia/amneziawg/server_public.key'
userkey = '/etc/amnezia/amneziawg/client/' + username + '_private.key'
userpublickey = '/etc/amnezia/amneziawg/client/' + username + '_public.key'
userwg = '/etc/amnezia/amneziawg/client-gen/' + username + '.conf'
oldpublickey = ''
awgconfigpath = '/etc/amnezia/amneziawg/awg0.conf'

if envs.get('awgconfigpath', '').strip() != '':
  awgconfigpath = envs['awgconfigpath']

if os.path.isfile(userkey) and force:
  with open(userpublickey) as publickeyfile:
    oldpublickey = publickeyfile.read().strip()

if not os.path.isfile(userkey) or force:
  subprocess.call(['/usr/bin/awg genkey | /usr/bin/tee /etc/amnezia/amneziawg/client/' + username +'_private.key | /usr/bin/awg pubkey | /usr/bin/tee /etc/amnezia/amneziawg/client/' + username + '_public.key'], shell=True)

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

with open('/etc/amnezia/amneziawg/awg-gen/templates/wg.template') as wgtemplate, \
        open(serverPublicPath) as serverPublicFile, \
        open(userkey) as keyfile, \
        open(userpublickey) as publickeyfile, \
        open(userwg, 'w') as outfile,\
        open(awgconfigpath) as awgconfigfile:
  awgconfig = simple_parse_awg_config(awgconfigfile.read())
  Jc = awgconfig['Interface'][0]['Jc']
  Jmin = awgconfig['Interface'][0]['Jmin']
  Jmax = awgconfig['Interface'][0]['Jmax']
  S1 = awgconfig['Interface'][0]['S1']
  S2 = awgconfig['Interface'][0]['S2']
  H1 = awgconfig['Interface'][0]['H1']
  H2 = awgconfig['Interface'][0]['H2']
  H3 = awgconfig['Interface'][0]['H3']
  H4 = awgconfig['Interface'][0]['H4']
  model = Template(wgtemplate.read())
  keyvalue = keyfile.read().strip()
  publickeyvalue = publickeyfile.read().strip()
  serverPublicvalue = serverPublicFile.read().strip()
  outfile.write(model.render(
    ip=ip,
    dns=dns,
    route=route,
    publickeyserver=serverPublicvalue,
    privatekey=keyvalue,
    server=server,
    Jc=Jc,
    Jmin=Jmin,
    Jmax=Jmax,
    S1=S1,
    S2=S2,
    H1=H1,
    H2=H2,
    H3=H3,
    H4=H4
  ))
  if oldpublickey != '':
    subprocess.call(['/usr/bin/awg set awg0 peer "'+ oldpublickey +'" remove'], shell=True)
  subprocess.call(['/usr/bin/awg set awg0 peer "'+ publickeyvalue +'" allowed-ips ' + ip + '/32'], shell=True)
  print('awg file generated: ' + userwg)

