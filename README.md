# bind/named in Docker for GNS3

Alpine Docker image developed for use with GNS3 that provides a DNS
server. Configuration is facilitated by setting environment variables.

The `startup.sh` script configures `named` by writing out the
`/etc/bind/named.conf` file, as well as forward zone files in the
`/var/bind/zones` directory.

The configuration of bind produced by `startup.sh` is intended
entirely for testing small networks that require an ephemeral DNS
server to be configured which maps names to IP addresses. It is not
intended for production use in any way.

In addition, bind will listen for IPv4 and IPv6 DNS requests.

## Environment Variables

Skip to [specifying domains](#domain-specification).

### Root Authority

It is recommended to configure the authoritative dns server for the
root domain. Depending on the usage, this could be the public internet
root servers (managed by [IANA][iana]), or a local server when not
using the public internet.

#### Local Roots

By default, when the image starts it will define its self as the
authoritative root server. This will create an `NS` record `ns` with
corresponding address records that reference the servers `eth0`
address. This configuration is ideal when running a standalone dns
server on a small network that does not need to perform recursive
queries onto other dns servers (including public internet).

To explicitly enable this function, set the environment variable:

```bash
AUTHORITATIVE=self
```

There are cases where it is desirable to run multiple local dns
servers with one being the authoritative (e.g. for the root or a
subdomain) and the others having responsibility for subdomains domains
delegated to them. This is similar to how the IANA root servers will
delegate to the TLD servers. To configure the delegated servers they
need both the name of the authoritative root server and a server to
forward queries to (for recursive queries) that can not be answered
locally. Consider the below scenario with 2 layers of delegation

```
------------          ------------             -------------------
| ns       |          | ns.com   |             | ns.example.com  |
| 1.2.3.4  |          | 1.2.3.5  |             | 1.2.3.6         |
------------          ------------             -------------------

Authoritative: root   Authoritative: .com      Authoritative: .example.com
Root NS: self (ns)    Root NS: ns (1.2.3.4)    Root NS: ns (1.2.3.4)
Forward: N/A          Forward: 1.2.3.4         Forward: 1.2.3.5 (could also be 1.2.3.4)
Delegate: .com        Delegate: .example.com   Delegate: N/A
```

This setup allows for both iterative and recursive queries to be
performed. That is, the use of the authoritative root means that it is
possible to perform an iterative query (e.g. using `dig` with `+trace`
option), it is also possible to request any of the 3 servers to
perform a recursive query and they should yield same results.

To configure `ns.com`, set the environment variable:

```bash
AUTHORITATIVE=ns,A,1.2.3.4,1.2.3.4
```

To configure `ns.example.com`, set the environment variable:

```bash
AUTHORITATIVE=ns,A,1.2.3.4,1.2.3.5
```

In this configuration, `AUTHORITATIVE` takes 4 parameters.

1. root nameserver FQDN
2. `A` (ipv4) or `AAAA` (ipv6) to define 3rd parameter format
3. IP address of root server (added as hint/glue on local server)
4. IP address to forward requests to that cant be answered locally (if
   this is not required, set to `#` and the server will perform an
   iterative query when needed instead of forwarding it).

#### IANA Root

In cases where resolving addresses on public internet is needed, the
server needs to know a name server to forward requests to that is
capable of resolving these queries.

To use the Google public dns server, use the following setting:

```bash
AUTHORITATIVE=iana,8.8.8.8
```

When using IANA, caution should be taken of locally defined domains
that overlap with any public domains as it can result undesired
lookups. E.g. one possibility to avoid this is to define a `.site`
domain and place all definitions in there.

If the forwarding server is set to `#`, `bind` will use an compiled-in
list of public root servers and attempt to perform an iterative query
on its own instead of forwarding it.

### Bespoke Options

To inject options into `bind`s `options` statement set the `OPTIONS`
environment variable. This variable is placed verbatim without any
checks into the options statement, so its is necessary to include all
formatting. That is, each option needs to be delimited by an `;`. For
example:

```bash
OPTIONS="check-names master; dump-file \"/path/to/a/file\";"
```

Check the `bind` [manual][bind] for available options.

### Domain specification

For each domain that needs to be managed by the DNS server, set an
environment variable:
```bash
DOMAIN_name=...
```

Here, `name` is the top level domain, e.g. *local*, *example_com*
(underscores are translated to dots), *test* or even just an intended
host name. The value of the variable specifies the resource records
that will be in the domain.

The value of the variable consists of a sequence of 3-ary tuples
(delimited by spaces). Each tuple defines the following:

* Owner - The Owner of the resource record, could be `@` to refer to
  the root domain.
* Type - The acronym which defines the type of the resource record,
  e.g. `A` for an IPv4 host record or `AAAA` for an IPv6 host record.
* Value - The RDATA of the record. The format of this changes
  depending on the type of resource record.

These three values are directly copied into the zone file for the
domain. More information on the range of values they can take can be
found in the `bind` [manual][bind].

Each tuple is written as: `owner,type,value`. These are concatenated
together to specify the variables value. That is:
```bash
DOMAIN_name="owner1,type1,value1 owner2,type2,value2 owner3,type3,value3"
```

The configuration generated already defines the `NS` resource record,
which points to its IP addresses on `eth0`.


### Example 1: Two hosts

Mapping host Alice and Bob to IP addresses 192.168.0.1 and
172.16.22.4, respectively, could be defined as follows:

```bash
DOMAIN_alice="@,A,192.168.0.1"
DOMAIN_bob="@,A,172.16.22.4"
```

Alice and Bob are both defined as TLDs, with an address record.

### Example 2: Hierarchical names

Defining two hosts within the `com` TLD could be as follows:

```bash
DOMAIN_com="example,A,10.0.25.65 www.example,A,10.0.25.67 www.example,AAAA,fd00:3443::2"
```

Here:

* `example.com` maps to IPv4 address 10.0.25.65.
* `www.example.com` maps to IPv4 address 10.0.25.67 and IPv6 address
  fd00:3443::2.

### Example 3: Delegate authority of sub-domain

To delegate authority of a subdomain such as *example.com* from the
parent domain *com*, setup the subdomain dns server as follows:

```bash
DOMAIN_example_com="www,A,10.0.0.1"
AUTHORITATIVE="ns,A,172.17.0.3,172.17.0.3"
```

Or, if its desirable for the subdomain server to also perform iterative
queries instead of forwarding them to the root server:

```bash
DOMAIN_example_com="www,A,10.0.0.1"
AUTHORITATIVE="ns,A,172.17.0.3,#"
```

Here it defines a single host (*www*) in the domain. In addition, an
implicit NS record `ns.example.com` is also defined that points to the
address on `eth0` (`172.17.0.2`). The `AUTHORITATIVE` configuration
sets the root nameserver as `ns`, hints its address as `172.17.0.3`
and also forwards recursive queries that it cant answer to
`172.17.0.3`.

On the parent dns server, configure it with the following variable:

```bash
DOMAIN_com="example,NS,ns.example ns.example,A,172.17.0.2 www,A,10.0.0.2"
```

Here, it defines the sub-domain by setting the NS record for
`example.com`. Further, it is required to add a *glue* record so the
DNS server can perform a recursive lookup.

Thus, it is possible to query the parent dns server for
`www.example.com` and it will query the subdomain dns server
automatically. Equivalently, it is possible to query the sub-domain
server for `www.com` and it will query the parent dns server
automatically.

### Example 4: Delegate authority of sub-domain (with IANA root)

Building upon example 3. It is possible to change the parent dns
server to use [IANA][iana] as authoritative name servers (i.e. public
internet).

As it is no longer possible to add entries directly to the root domain
as it would break recursive queries, a new domain `.site` is used.

The subdomain server is configured as:

```bash
DOMAIN_example_com="www,A,10.0.0.1"
AUTHORITATIVE="ns.site,A,172.17.0.3,172.17.0.3"
```

The parent server is configured as:

```bash
DOMAIN_com="example,NS,ns.example ns.example,A,172.17.0.2 www,A,10.0.0.2"
DOMAIN_site=
AUTHORITATIVE=iana,8.8.8.8
```

Here, the `site` domain is intentionally blank as only the gratuitous
`NS` record is needed.

The `.com` domain is defined by the parent server, and thus all
recursive queries for any public domain name `*.com` will fail as the
server will not know whether to check locally or remotely. Thus, it is
recommended when using `iana` root servers to avoid defining any
domains that overlap with public domains. E.g. the above could be
rewritten as:

The subdomain server would be configured as:

```bash
DOMAIN_example_site="www,A,10.0.0.1"
AUTHORITATIVE="ns.site,A,172.17.0.3,172.17.0.3"
```

The parent server would be configured as:

```bash
DOMAIN_site="example,NS,ns.example ns.example,A,172.17.0.2 www,A,10.0.0.2"
AUTHORITATIVE=iana,8.8.8.8
```

It is possible to have the parent server configurable as either root
authority or using IANA as root with no configuration changes on
subdomain servers. That is, the below configuration would be
compatible with the above subdomain server:

```bash
DOMAIN_site="example,NS,ns.example ns.example,A,172.17.0.2 www,A,10.0.0.2"
DOMAIN__="@,NS,ns.site ns.site,A,172.17.0.3"
```

## Other Bits

Licensed under GPLv3. Copyright 2019. All rights reserved, Karim Kanso.

[iana]: https://www.iana.org/domains/root/servers "Root Servers"
[bind]: https://www.isc.org/downloads/bind/doc/ "BIND manual"
