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

### Recursive lookups

To enable bind to perform recursive DNS lookups, set the environment
variable `RECURSIVE=yes`. This will result in forwarding requests to
Google DNS servers:

* `8.8.8.8`
* `8.8.4.4`

These values are currently hard coded in the `startup.sh` script.

### Domain specification

For each domain that needs to be managed by the DNS server, set an
environment variable:
```bash
DOMAIN_name=...
```

Here, `name` is the top level domain, e.g. *local*, *com*, *test* or
even just an intended host name. The value of the variable specifies
the resource records that will be in the domain.

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
found in the `bind` [manual](https://www.isc.org/downloads/bind/doc/).

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
