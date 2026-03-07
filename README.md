# scale23x-iam
Install and configure IAM for SCALE23X

Note that this requires that the machine running Ansible has the 
ansible-freeipa package installed, which contains the role for the
freeipa server. This works on Fedora, RHEL, or CentOS Stream.

Note that the TSIG keys used in this are for illustration only. They
were used for my demo, and that demo environment has already been 
nuked.

I installed the IdM server with the following settings. Obviously,
change things like the hostname, domain name, realm name, etc. to 
values which match your environment.

ipa-server-install \
  --unattended \
  --ds-password=CHANGEME \
  --admin-password=CHANGEME \
  --ip-address=192.168.122.2 \
  --domain=redhat.lan \
  --realm=REDHAT.LAN \
  --hostname=idm.redhat.lan \
  --setup-dns \
  --no-host-dns \
  --auto-reverse \
  --mkhomedir \
  --ntp-pool=pool.ntp.org \
  --forwarder=8.8.8.8 \
  --forwarder=4.2.2.1

-------------------------------------------------

Next, 
tsig-keygen -a HMAC-SHA256 dhcp-key

Copy the "secret" string from the output (e.g., kTf...==) to use in the files below.

See kea-dhcp4.conf and kea-dhcp-ddns.conf for how I configured kea DHCP

-------------------------------------------------

See ipa-ext.conf for how I added the key to the DNS server. That file survives
upgrades, so it's safe to include the TSIG key there.

Then, systemctl restart named-pkcs11

-------------------------------------------------

Authorize the Key for your zones using FreeIPA CLI:

# Authenticate as admin first
kinit admin

# Allow the key to update the Forward Zone
ipa dnszone-mod redhat.lan --dynamic-update=TRUE --update-policy="grant dhcp-key subdomain redhat.lan. ANY;"

# Allow the key to update the Reverse Zone
ipa dnszone-mod 122.168.192.in-addr.arpa --dynamic-update=TRUE --update-policy="grant dhcp-key subdomain 122.168.192.in-addr.arpa. ANY;"

Then,
systemctl enable --now kea-dhcp-ddns
systemctl restart kea-dhcp4

-------------------------------------------------

Create a small text file named test_update.txt

server 192.168.122.2
key hmac-sha256:dhcp-key PASTE_YOUR_SECRET_HERE
zone redhat.lan
update add test-manual.redhat.lan 60 A 192.168.122.100
show
send

Run the update: nsupdate test_update.txt

