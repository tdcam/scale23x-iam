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

-------------------------------------------------

Once the server is up and running, you can register your machines to it
using the 03-register-clients.yml playbook or:

ipa-client-install \
 --unattended \
 --principal=admin \
 --password=CHANGEME \
 --ip-address=192.168.122.6 \
 --domain=redhat.lan --server==idm.redhat.lan \
 --hostname=workstation.redhat.lan \
 --enable-dns-updates \
 --mkhomedir \
 --force 

-------------------------------------------------

I set up Hashicorp Vault for the demo as root.

dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
dnf -y install vault

vi /etc/vault.d/vault.hcl so it ends up like this:

# Copyright IBM Corp. 2016, 2025
# SPDX-License-Identifier: BUSL-1.1

# Full configuration options can be found at https://developer.hashicorp.com/vault/docs/configuration

ui = true

#mlock = true
#disable_mlock = true

storage "file" {
  path = "/opt/vault/data"
}

#storage "consul" {
#  address = "127.0.0.1:8500"
#  path    = "vault"
#}

# HTTP listener
listener "tcp" {
  # changed 127.0.0.1 to 0.0.0.0
  # address = "127.0.0.1:8200"
  address = "0.0.0.0:8200"
  tls_disable = 1
}

# HTTPS listener
#listener "tcp" {
#  address       = "0.0.0.0:8200"
#  tls_cert_file = "/opt/vault/tls/tls.crt"
#  tls_key_file  = "/opt/vault/tls/tls.key"
#}

# Enterprise license_path
# This will be required for enterprise as of v1.8
#license_path = "/etc/vault.d/vault.hclic"

# Example AWS KMS auto unseal
#seal "awskms" {
#  region = "us-east-1"
#  kms_key_id = "REPLACE-ME"
#}

# Example HSM auto unseal
#seal "pkcs11" {
#  lib            = "/usr/vault/lib/libCryptoki2_64.so"
#  slot           = "0"
#  pin            = "AAAA-BBBB-CCCC-DDDD"
#  key_label      = "vault-hsm-key"
#  hmac_key_label = "vault-hsm-hmac-key"
#}

Then start vault:
systemctl enable --now vault

Next iitialize the vault:

export VAULT_ADDR='http://192.168.122.2:8200'
vault operator init -key-shares=3 -key-threshold=2


