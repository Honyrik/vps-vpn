ovpn-generate
=============

A python script that generates an .ovpn file after building client keys.

You can remove client access:
```bash
/usr/share/easy-rsa/3/easyrsa revoke client
```
After generating new client keys, you can read them all at once and
populate the .ovpn file:
```bash
python ovpn-gen.py name
```
A name.ovpn file will then be created. Distribute this to your user
and they can connect to the VPN server.

[Tunnelblick](https://code.google.com/p/tunnelblick/) is an OS X client that
users can use to connect.

Windows and Linux users also have client programs that they can use too.

[Apache](http://www.apache.org/licenses/LICENSE-2.0.html) 2.0 License

