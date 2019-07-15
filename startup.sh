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
EOF

case "${AUTHORITATIVE:-self}" in
    iana,*)
        FORWARDER=${AUTHORITATIVE#iana,}
        echo "Using IANA as authoritative root with upstream as ${FORWARDER}"
        cat - >> ${CONF_FILE} <<EOF
        forwarders {
              ${FORWARDER};
        };
};
zone "." IN {
        type hint;
        file "named.ca";
};
EOF
    ;;
    self)
        echo "Assuming authoritative role for root"
        echo '};' >> ${CONF_FILE}
        # Define root domain (.), so that server is authoritative
        if test -z "${DOMAIN__}" ; then
            DOMAIN__=
        fi
    ;;
    *,A,*,* | *,AAAA,*,*)
        ROOT_NAME=${AUTHORITATIVE%%,*}
        FORWARDER=${AUTHORITATIVE##*,}
        AUTHORITATIVE=${AUTHORITATIVE%,*}
        echo "Setting authoritative root to \"${ROOT_NAME}\" with upstream as ${FORWARDER}"
        cat - >> ${CONF_FILE} <<EOF
        forwarders {
              ${FORWARDER};
        };
};
zone "." IN {
        type hint;
        file "custom.ca";
};
EOF
        cat - >> /var/bind/custom.ca <<EOF
$(echo -en '.\tNS\t')${ROOT_NAME}.
$(echo ${AUTHORITATIVE} | awk 'BEGIN {RS=" "; FS=","; OFS="\t"} {print $1 ".",$2,$3}')
EOF
    ;;
    *)
        1>&2 echo "AUTHORITATIVE should be one of:"
        1>&2 echo " * iana,forwarder"
        1>&2 echo " * self"
        1>&2 echo " * fqdn,A,ipv4addr,forwarder"
        1>&2 echo " * fqdn,AAAA,ipv6addr,forwarder"
        1>&2 echo
        1>&2 echo "Where:"
        1>&2 echo " * fqdn is the name of the authoritative server for root."
        1>&2 echo " * forwarder is the address of a dns server to pass"
        1>&2 echo "   unresolved recursive queries to."
        1>&2 echo
        1>&2 echo "Example:"
        1>&2 echo "  Set to iana,8.8.8.8 to forward queries not answerable"
        1>&2 echo "  locally to Google's dns."
        1>&2 echo
        1>&2 echo "Dropping into a shell"
        exec /bin/sh
    ;;
esac

## Setup self referencing resource records

# Find ip addresses to advertise as the ns authority in all domains
# that it masters.
if test -z "${INTERFACE}" ; then
    INTERFACE=eth0
fi
IPv4=$(ip -4 addr show dev ${INTERFACE} up | awk '/ inet /{split($2,a,"/"); print a[1];}')
IPv6=$(ip -6 addr show dev ${INTERFACE} up | awk '/ inet6 ([^fF]|[fF][^eE]|[fF][eE][^8]|[fF][eE]8[^0])/{split($2,a,"/"); print a[1];}')
echo "Detected the following ip addresses on ${INTERFACE}:"
for a in ${IPv4} ${IPv6} ; do
    echo "  ${a}"
done
echo "They will be used for NS records in master zones."

SELF_ADDRESS_RR=$(
    for a in ${IPv4} ; do
        echo -e "ns\tA\t${a}"
    done
    for a in ${IPv6} ; do
        echo -e "ns\tAAAA\t${a}"
    done
               )
## Setup a zone for each domain

DOMAINS=$(set | grep -o ^DOMAIN_[^=]\\\+ | sed s/DOMAIN_//)

if test -z "${DOMAINS}" ; then
    1>&2 echo "No domains found to add to DNS server."
    1>&2 echo
    1>&2 echo "Configure each domain by setting env variable:"
    1>&2 echo "    DOMAIN_name=(owner,rr,rdata )+"
    1>&2 echo
    1>&2 echo "Here, name is the domain name (underscore is mapped to dot)."
    1>&2 echo "  owner is the owner of the resource record."
    1>&2 echo "  rr is the type of the resource record."
    1>&2 echo "  rdata is the data of the resource record."
    1>&2 echo
    1>&2 echo "These three values can be repeated many times, each separated"
    1>&2 echo "by a space to fully define the records stored in the zone."
    1>&2 echo "For more info about owner, rr and rdata see the bind manual."
    1>&2 echo
    1>&2 echo "Example:"
    1>&2 echo "  DOMAIN_test=\"@,A,192.168.1.1 @,AAAA,fd11::1 www,A,192.168.1.2 www,AAAA,fd00::5\""
    1>&2 echo "  \"test\" will resolve to 192.168.1.1 (and fd11::1)"
    1>&2 echo "  \"www.test\" will resolve to 192.168.1.2 (and fd00::5)"
    1>&2 echo
    1>&2 echo "Dropping into a shell"
    exec /bin/sh
fi

ZONEDIR=/var/bind/zones
if ! mkdir ${ZONEDIR} ; then
    1>&2 echo "Failed to make dir ${ZONEDIR}"
    exit 1
fi

for D in ${DOMAINS} ; do
    eval records=\$DOMAIN_$D
    D=$(echo -n $D | tr _ \.)
    echo "Processing domain \"${D}\" with value ${records}"
    D_ZONE=${ZONEDIR}/$D.zone

    # Check if custom ns record is provided
    if echo ${records} | grep -E '( +|^)@ *, *NS *, *ns( +|$)' ; then
        NS=$(echo ${records} | sed -E 's/^.*@ *, *NS *, *([^ ]+).*$/\1/')
        cat - > ${D_ZONE} <<EOF
\$TTL 1W
@       SOA     ${NS} root (
                                      1          ; Serial
                                      28800      ; Refresh
                                      14400      ; Retry
                                      604800     ; Expire - 1 week
                                      86400 )    ; Minimum
EOF
    else
        cat - > ${D_ZONE} <<EOF
\$TTL 1W
@       SOA     ns root (
                                      1          ; Serial
                                      28800      ; Refresh
                                      14400      ; Retry
                                      604800     ; Expire - 1 week
                                      86400 )    ; Minimum
@       NS      ns
${SELF_ADDRESS_RR}
EOF
    fi
    echo ${records} | awk 'BEGIN {RS=" "; FS=","; OFS="\t"} {print $1,$2,$3}' >> ${D_ZONE}
    cat - >> ${CONF_FILE} <<EOF
zone "${D}" IN {
        type master;
        file "zones/${D}.zone";
        forwarders { };
};
EOF
done

echo "Starting named"

exec named -g
