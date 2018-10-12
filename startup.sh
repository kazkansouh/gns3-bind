#! /bin/sh

# Copyright (C) 2018 Karim Kanso. All Rights Reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

## Create main config file
CONF_FILE=/etc/bind/named.conf
if test "${RECURSIVE}" = "yes" ; then
    echo "Enabling recursion onto Google DNS"
    cat - > ${CONF_FILE} <<EOF
options {
        directory "/var/bind";
        listen-on { any; };
        listen-on-v6 { any; };
        allow-transfer {
                none;
        };

        pid-file "/var/run/named/named.pid";

        allow-recursion { 0.0.0.0/0; };
        forwarders {
              8.8.8.8;
              8.8.4.4;
        };
};

zone "private" IN {
        type master;
        file "zones/private.zone";
};
EOF
else
    echo "DNS recursion not enabled, enable by setting env. var RECURSIVE=yes"
    cat - > ${CONF_FILE} <<EOF
options {
        directory "/var/bind";
        listen-on { any; };
        listen-on-v6 { any; };
        allow-transfer {
                none;
        };

        pid-file "/var/run/named/named.pid";

        allow-recursion { none; };
        recursion no;
};

zone "private" IN {
        type master;
        file "zones/private.zone";
};
EOF
fi

## Setup private zone

# Find ip addresses to advertise as the ns authority in all domains
# that it masters.
if test -z "${INTERFACE}" ; then
    INTERFACE=eth0
fi
IPv4=$(ip -4 addr show dev ${INTERFACE} up | awk '/ inet /{split($2,a,"/"); print a[1];}')
IPv6=$(ip -6 addr show dev ${INTERFACE} up | awk '/ inet6 ([^fF]|[fF][^eE]|[fF][eE][^8]|[fF][eE]8[^0])/{split($2,a,"/"); print a[1];}')
echo "Using ip addresses as nameserver root:"
for a in ${IPv4} ${IPv6} ; do
    echo ${a}
done

ZONEDIR=/var/bind/zones
if ! mkdir ${ZONEDIR} ; then
    1>&2 echo "Failed to make dir ${ZONEDIR}"
    exit 1
fi

PRIVATE_ZONE=${ZONEDIR}/private.zone
cat - > ${PRIVATE_ZONE} <<EOF
\$TTL 1W
@       SOA     nameserver root (
                                      1          ; Serial
                                      28800      ; Refresh
                                      14400      ; Retry
                                      604800     ; Expire - 1 week
                                      86400 )    ; Minimum
@       NS      nameserver
EOF
for a in ${IPv4} ; do
    echo -e "nameserver\tA\t${a}" >> ${PRIVATE_ZONE}
done
for a in ${IPv6} ; do
    echo -e "nameserver\tAAAA\t${a}" >> ${PRIVATE_ZONE}
done

## Setup a zone for each domain

DOMAINS=$(set | grep -o ^DOMAIN_[^=]\\\+ | sed s/DOMAIN_//)

if test -z "${DOMAINS}" ; then
    2>&1 echo "No domains found to add to DNS server."
    2>&1 echo 
    2>&1 echo "Configure each domain by setting env variable:"
    2>&1 echo "    DOMAIN_name=(owner,rr,rdata )+"
    2>&1 echo
    2>&1 echo "Here, name is the domain name."
    2>&1 echo "  owner is the owner of the resource record."
    2>&1 echo "  rr is the type of the resource record."
    2>&1 echo "  rdata is the data of the resource record."
    2>&1 echo
    2>&1 echo "These three values can be repeated many times, each separated"
    2>&1 echo "by a space to fully define the records stored in the zone."
    2>&1 echo "For more info about owner, rr and rdata see the bind manual."
    2>&1 echo
    2>&1 echo "Example:"
    2>&1 echo "  DOMAIN_test=\"@,A,192.168.1.1 @,AAAA,fd11::1 www,A,192.168.1.2 www,AAAA,fd00::5\""
    2>&1 echo "  \"test\" will resolve to 192.168.1.1 (and fd11::1)"
    2>&1 echo "  \"www.test\" will resolve to 192.168.1.2 (and fd00::5)"
    2>&1 echo
    2>&1 echo "Dropping into a shell"
    exec /bin/sh
fi

for D in ${DOMAINS} ; do
    eval records=\$DOMAIN_$D
    echo "Processing domain $D with value ${records}"
    D_ZONE=${ZONEDIR}/$D.zone
    cat - > ${D_ZONE} <<EOF
\$TTL 1W
@       SOA     nameserver.private. root (
                                      1          ; Serial
                                      28800      ; Refresh
                                      14400      ; Retry
                                      604800     ; Expire - 1 week
                                      86400 )    ; Minimum
@       NS      nameserver.private.
EOF
    echo ${records} | awk 'BEGIN {RS=" "; FS=","; OFS="\t"} {print $1,$2,$3}' >> ${D_ZONE}
    cat - >> ${CONF_FILE} <<EOF
zone "${D}" IN {
        type master;
        file "zones/${D}.zone";
};
EOF
done

echo "Starting named"

exec named -g
