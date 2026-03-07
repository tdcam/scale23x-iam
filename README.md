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

/etc/kea/kea-dhcp4.conf

{
    "Dhcp4": {
        "interfaces-config": {
            "interfaces": [ "enp1s0" ]
        },
        "control-sockets": {
            "dhcp4": {
                "socket-type": "unix",
                "socket-name": "/tmp/kea-dhcp4-ctrl.sock"
            }
        },
        "lease-database": {
            "type": "memfile",
            "persist": true,
            "name": "/var/lib/kea/kea-leases4.csv"
        },
        "valid-lifetime": 600,

        "dhcp-ddns": {
            "enable-updates": true,
            "server-ip": "127.0.0.1",
            "server-port": 53001,
            "ncr-protocol": "JSON",
            "ncr-format": "JSON",
            "qualifying-suffix": "redhat.lan",
            "override-client-update": true,
            "override-no-update": true
        },

        "hooks-libraries": [
            {
                "library": "/usr/lib64/kea/hooks/libdhcp_lease_cmds.so"
            },
            {
                "library": "/usr/lib64/kea/hooks/libdhcp_stat_cmds.so"
            }
        ],

        "subnet4": [
            {
                "id": 1,
                "subnet": "192.168.122.0/24",
                "next-server": "192.168.122.2",
                "pools": [
                    {
                        "pool": "192.168.122.128 - 192.168.122.254"
                    }
                ],
                "option-data": [
                    {
                        "name": "routers",
                        "data": "192.168.122.1"
                    },
                    {
                        "name": "domain-name-servers",
                        "data": "192.168.122.2"
                    },
                    {
                        "name": "domain-name",
                        "data": "redhat.lan"
                    }
                ],
                "reservations": [
                    {
                        "hostname": "filer",
                        "ip-address": "192.168.122.3",
                        "hw-address": "52:54:00:c1:cd:7c"
                    },
                    {
                        "hostname": "db",
                        "ip-address": "192.168.122.4",
                        "hw-address": "52:54:00:68:d4:ef"
                    },
                    {
                        "hostname": "web",
                        "ip-address": "192.168.122.5",
                        "hw-address": "52:54:00:b9:52:b7"
                    },
                    {
                        "hostname": "workstation1",
                        "ip-address": "192.168.122.6",
                        "hw-address": "52:54:00:82:f1:11"
                    }
                ]
            }
        ]
    }
}

/etc/kea/kea-dhcp-ddns.conf

{
"DhcpDdns": {
  "ip-address": "127.0.0.1",
  "port": 53001,
  "control-sockets": {
      "d2-socket": {
          "socket-type": "unix",
          "socket-name": "/tmp/kea-ddns-ctrl.sock"
      }
  },
  "tsig-keys": [
    {
      "name": "dhcp-key",
      "algorithm": "hmac-sha256",
      "secret": "PASTE_YOUR_GENERATED_SECRET_HERE"
    }
  ],
  "forward-ddns": {
    "ddns-domains": [
      {
        "name": "redhat.lan.",
        "key-name": "dhcp-key",
        "dns-servers": [
          { "ip-address": "192.168.122.2" }
        ]
      }
    ]
  },
  "reverse-ddns": {
    "ddns-domains": [
      {
        "name": "122.168.192.in-addr.arpa.",
        "key-name": "dhcp-key",
        "dns-servers": [
          { "ip-address": "192.168.122.2" }
        ]
      }
    ]
  },
  "loggers": [
    {
        "name": "kea-dhcp-ddns",
        "output_options": [
            {
                "output": "syslog",
                "pattern": "%-5p %m\n"
            }
        ],
        "severity": "INFO",
        "debuglevel": 0
    }
  ]
}
}

-------------------------------------------------

Edit /etc/named.conf

key "dhcp-key" {
    algorithm hmac-sha256;
    secret "PASTE_YOUR_GENERATED_SECRET_HERE";
};

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
