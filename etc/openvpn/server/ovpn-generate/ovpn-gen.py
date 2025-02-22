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

separator = "="
envs = {}

with open('/etc/openvpn/server/vars') as f:
    for line in f:
        if separator in line:
            name, value = line.split(separator, 1)
            envs[name.strip()] = value.strip()

#'/etc/openvpn/easy-rsa'
server = envs["server"]
ca = '/etc/openvpn/server/keys/ca.crt'
ta = '/etc/openvpn/server/keys/ta.key'
usercert = '/etc/openvpn/server/keys/issued/' + username + '.crt'
userkey = '/etc/openvpn/server/keys/private/' + username + '.key'
userovpn = '/etc/openvpn/server/gen-client/' + username + '.ovpn'

if not os.path.isfile(usercert):
  subprocess.call(['./easyrsa', 'build-client-full', username, 'nopass', '--days=1095'], cwd='/usr/share/easy-rsa/3')


with open('/etc/openvpn/server/ovpn-generate/templates/ovpn.template') as ovpntemplate, \
        open(ta) as tafile, \
        open(usercert) as certfile, \
        open(userkey) as keyfile, \
        open(ca) as cafile, \
        open(userovpn, 'w') as outfile:
  model = Template(ovpntemplate.read())
  certvalue = certfile.read()
  keyvalue = keyfile.read()
  cavalue = cafile.read()
  tavalue = tafile.read()
  outfile.write(model.render(usercert=certvalue, userkey=keyvalue, cacert=cavalue, servername=server, takey=tavalue))
  print model.render(usercert=certvalue, userkey=keyvalue, cacert=cavalue, servername=server, takey=tavalue)
  print 'OVPN file generated: ' + userovpn

