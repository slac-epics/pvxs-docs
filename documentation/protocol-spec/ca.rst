.. _ca_protocol_spec:

==========================================
Channel Access (CA) Protocol Specification
==========================================

:Status: Draft
:Protocol Version: 4.13 (this document specifies CA major version 4, minor versions 0 through 13)
:Default Server Port: 5064 (TCP and UDP)
:Default Repeater Port: 5065 (UDP)

.. note::

   This document is the normative specification of the Channel Access
   wire protocol. Implementations conform to this specification.
   Where an implementation's behavior differs from this specification,
   the implementation is in error and the specification is authoritative.
   The reverse is not true: a behavior observed in any one
   implementation does not become normative because it is observed
   there.

   Specific implementations (EPICS Base, pvxs, others) and historical
   reference materials consulted in the preparation of this
   specification are listed under Informative References (Section
   17.2); they have no normative weight.

Abstract
========

The Channel Access (CA) protocol is the original EPICS network protocol
for accessing process variables (PVs) on Input/Output Controllers
(IOCs). CA defines a connection lifecycle, a name resolution mechanism,
and a small set of operations (read, write, monitor, error reporting)
exchanged as fixed-format binary messages over UDP (for name discovery
and beacons) and TCP (for connections). This document specifies CA
major version 4 and the minor-version extensions through 4.13. CA was
designed and is maintained by Jeffrey O. Hill.

Status of This Document
=======================

This document is a wire-protocol specification. It describes the bytes
that travel between a CA client and a CA server, the order in which they
are exchanged, and the meaning of each field. It does not describe the
EPICS Base ``libca`` C API, the IOC database engine, or any client
application; those are covered separately in the EPICS Base
documentation.

This document covers CA major protocol revision 4. Where minor
protocol revisions (4.0 through 4.13) introduce or modify
behavior, this document calls out the minor revision in which the
behavior first appeared.

Pre-existing implementations of CA (notably EPICS Base) and the
historical *Channel Access Reference Manual* by Jeffrey Hill were
consulted during the preparation of this specification (see Section
17.2); however, the specification's authority derives from this
document, not from those implementations or that manual.

Conventions Used in This Document
=================================

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in :rfc:`2119` and
:rfc:`8174`.

All multi-byte integer fields in CA messages are transmitted in
**network byte order** (big-endian). All offsets and sizes are in octets
(8-bit bytes).

Notation:

- ``u8``, ``u16``, ``u32`` denote unsigned integers of 8, 16, and 32 bits.
- ``i8``, ``i16``, ``i32`` denote signed two's-complement integers.
- ``f32``, ``f64`` denote IEEE 754 single- and double-precision floats.
- ``string[N]`` denotes a fixed-length, null-padded ASCII string of N octets.
- Brackets ``[ ... ]`` enclose a struct field list with explicit offsets.

The phrase **the protocol** refers throughout this document to CA
major revision 4.

Table of Contents
=================

1. Introduction
2. Protocol Overview
3. Transport Layer
4. Common Message Format
5. Connection Establishment
6. Name Resolution and Search
7. Channel Lifecycle
8. Operations on a Connected Channel
9. Beacons and Server Announcement
10. The CA Repeater
11. Flow Control
12. Error Handling and Status Codes
13. Version Negotiation and Extensions
14. Backward Compatibility
15. Security Considerations
16. IANA Considerations
17. References

----

1. Introduction
===============

1.1. Purpose
------------

The Channel Access protocol enables a client process to access the
value of a named *process variable* (PV) hosted by a server process,
typically an EPICS Input/Output Controller (IOC). The protocol
provides:

- **Name discovery**: locating which server hosts a given PV name,
  using UDP broadcast or unicast queries.
- **Connection management**: establishing a long-lived TCP connection
  to a server, creating channels (per-PV handles) on that connection,
  and tearing them down cleanly.
- **Data access**: reading the current value of a channel, writing a
  new value, and subscribing to receive notifications when the value
  changes (monitoring).
- **Liveness signalling**: periodic UDP beacons by which servers
  announce their presence, so that clients can detect newly-started
  servers and recover after server restarts.

CA is independent of the structure of the data being transported. A
small fixed set of native types is defined (see Section 4.4); arbitrary
structured values are not part of CA. Clients requiring structured
values use PVAccess (PVA), specified separately. See
:doc:`/protocol-spec/pva`.

1.2. Design Philosophy
----------------------

CA was designed for a control-system environment with the following
properties:

- A single facility may host tens of thousands of IOCs and millions of
  PVs.
- Clients and servers come and go independently of each other; the
  network is partially-trusted but not adversarial.
- Latency on a local-area Ethernet must be very low; throughput on a
  saturated link is secondary.
- Implementations must run on a wide range of operating systems, from
  modern Linux and Windows to embedded RTOS environments.

These properties drive several protocol-level choices that may appear
unusual compared with general-purpose RPC protocols:

- **Fixed-size 16-octet message header** for the common case, with
  an 8-octet *extended-header annex* (giving a 24-octet total
  header) for messages whose payload or count exceeds 16-bit
  limits. (See Section 4.)
- **No message framing on UDP**: each datagram contains an integral
  number of CA messages with no length prefix beyond the per-message
  header. Implementations rely on the per-message ``m_postsize`` field.
- **No persistent identifier for a PV**: the same PV name may resolve
  to different ``Channel ID`` values on different connections. ``CID``
  is a per-connection client-allocated handle.
- **In-band version negotiation**: the protocol revision is exchanged
  as the first message on every TCP connection (Section 13).

1.3. Scope
----------

This specification covers:

- The wire format of all CA messages defined for major revision 4
  (Section 4 and the operation-specific sections).
- The transport-layer behavior, including UDP search/broadcast, TCP
  connection setup, and the role of the CA Repeater (Sections 3, 6,
  and 10).
- The state machines for the client, the server, and the per-channel
  lifecycle (Sections 5 and 7).
- The version-negotiation rules and the minor-revision feature flags
  (Section 13).
- The status codes and error-reporting message format (Section 12).

It does not cover:

- The EPICS Base ``libca`` C client API (``ca_create_channel``,
  ``ca_get``, etc.). Those are covered in the EPICS Base documentation.
- The IOC record database, the access-security file (ASG/ACF), or the
  PV-name-to-record mapping. Those are server-side internals; CA only
  observes the externally-visible result (i.e. a channel either does or
  does not exist).
- Authentication or encryption. CA does not provide either. Networks
  carrying CA traffic are assumed to be trusted at the transport level.
  Sites requiring confidentiality or authentication SHOULD use SPVA
  (:doc:`/protocol-spec/spva`) instead.

1.4. Terminology
----------------

For the purposes of this document, the following terms apply:

PV (Process Variable)
   A named, externally-addressable value hosted by a server. The value
   has a fixed native type (Section 4.4). PV names are ASCII strings
   of bounded length; the bound is set by ``MAX_UDP_RECV`` minus
   header overhead and is implementation-defined.

Channel
   A per-connection client-side handle that refers to a PV on a
   specific server. Created by a successful ``CREATE_CHAN`` exchange
   (Section 7); destroyed by ``CLEAR_CHANNEL`` (Section 7) or by
   connection close.

CID (Channel ID, client-side)
   A 32-bit integer chosen by the client to identify a channel within
   a single connection. The same numeric CID MAY be reused on a
   different connection.

SID (Channel ID, server-side)
   A 32-bit integer chosen by the server to identify the server's
   binding for a channel. Returned to the client in the
   ``CREATE_CHAN_RESP`` message (Section 7.2).

IOI (Input/Output ID)
   A 32-bit integer chosen by the client to identify a single
   in-flight read, write, or monitor operation against a channel. The
   server echoes the IOI in its response so the client can correlate
   the response with the request.

Subscription (Monitor)
   A long-lived request from a client to be notified whenever a
   channel's value changes. Established by ``EVENT_ADD`` (Section 8.3),
   torn down by ``EVENT_CANCEL`` or ``CLEAR_CHANNEL``.

Beacon
   A UDP datagram emitted periodically by a CA server to announce its
   presence to potential clients. Specified in Section 9.

Repeater
   A daemon process running on each client host that collates UDP
   beacons from all servers reachable from that host and forwards them
   to all CA clients on that host. Specified in Section 10.

----

2. Protocol Overview
====================

This section gives a non-normative overview of how a CA exchange
proceeds end-to-end. It is a road map for the detailed sections that
follow. Implementers MUST consult the detailed sections for normative
behavior.

2.1. Layering
-------------

CA runs directly over UDP and TCP. There is no intermediate
framing layer.

::

    +-------------------+ +-------------------+
    |   CA Search /     | |   CA Operations   |
    |   Beacon / Echo   | |   on a Channel    |
    +-------------------+ +-------------------+
    |        UDP        | |        TCP        |
    +-------------------+ +-------------------+
    |                   IPv4                   |
    +------------------------------------------+

CA is IPv4-only. The wire format reserves a 32-bit slot for the
server's IP address in the search reply (Section 6.2) and in the
pre-V4.6 beacon (Section 9.1); these slots are sized for IPv4 and
have no IPv6 extension. See Section 3.6 for the consequence; sites
needing IPv6 transport SHALL use PVAccess
(:doc:`/protocol-spec/pva`).

UDP carries:

- Client-originated **Search** requests (Section 6) sent to the server
  port (default 5064) at the broadcast or unicast address of candidate
  servers.
- Server-originated **Search responses** (Section 6) sent back to the
  client's source UDP port.
- Server-originated **Beacons** (Section 9) sent to the broadcast
  address (or to the repeater port via the local Repeater; see
  Section 10).
- Client-originated **Echo** keepalives in some configurations
  (Section 11.3).

TCP carries:

- All operations on a channel — ``CREATE_CHAN``, ``READ``,
  ``WRITE``, ``EVENT_ADD``, ``EVENT_CANCEL``, ``CLEAR_CHANNEL``, etc.
  (Sections 7 and 8).
- The server's response messages for the above.
- Asynchronous server-side notifications, including monitor updates
  (``EVENT_ADD`` responses) and channel-state changes
  (``ACCESS_RIGHTS``).

2.2. A Typical Exchange
-----------------------

The simplest end-to-end CA exchange — connect to one PV, read its
value, disconnect — proceeds as follows:

1. **Client**: send a ``CA_PROTO_SEARCH`` UDP datagram to the broadcast
   address on port ``EPICS_CA_SERVER_PORT`` (default 5064), naming the
   PV. (Section 6.1.)

2. **Server hosting the PV**: receive the ``CA_PROTO_SEARCH``, decide
   that it hosts the PV, send a ``CA_PROTO_SEARCH`` response unicast
   to the client's source UDP port. The response carries the server's
   TCP port and protocol version. (Section 6.2.)

3. **Client**: open a TCP connection to the server's address and TCP
   port from the search response.

4. **Client**: send ``CA_PROTO_VERSION`` as the first message on the
   new TCP connection, declaring the client's minor version. (Section
   13.)

5. **Server**: respond with ``CA_PROTO_VERSION`` declaring its own
   minor version. The exchange's effective minor version is the
   minimum of the two. (Section 13.)

6. **Client**: send ``CA_PROTO_CLIENT_NAME`` and
   ``CA_PROTO_HOST_NAME`` (carrying user identity strings; see Section
   5.3) followed by ``CA_PROTO_CREATE_CHAN`` for the PV. (Sections 5.3
   and 7.1.)

7. **Server**: respond with ``CA_PROTO_CREATE_CHAN_RESP`` carrying the
   ``SID`` and the channel's native type and element count (Section
   7.2). At this point the channel is *connected*.

8. **Client**: send ``CA_PROTO_READ_NOTIFY`` referring to the SID, with
   a fresh IOI. (Section 8.1.)

9. **Server**: respond with ``CA_PROTO_READ_NOTIFY`` carrying the
   channel's value and the IOI. (Section 8.1.)

10. **Client**: send ``CA_PROTO_CLEAR_CHANNEL`` to release the
    server-side channel state. (Section 7.3.)

11. **Server**: respond with ``CA_PROTO_CLEAR_CHANNEL`` confirming.

12. **Client**: close the TCP connection.

Subscriptions are similar but the client uses ``CA_PROTO_EVENT_ADD``
in step 8 and receives an unbounded stream of update responses until
``CA_PROTO_EVENT_CANCEL`` or ``CA_PROTO_CLEAR_CHANNEL`` (Section 8.3).

2.3. The Role of the Repeater
-----------------------------

CA servers send beacons to the broadcast address on the *Repeater port*
(default 5065), not directly to clients. On each client host, exactly
one CA Repeater process listens on the Repeater port, receives beacons
from all reachable servers, and forwards each beacon to every CA client
on the host that has registered with the Repeater. This indirection
exists because:

- A host may run an arbitrary number of CA clients simultaneously.
  Without the Repeater, only one client per host could bind to the
  Repeater port to receive beacons; the rest would silently miss them.
- Beacon delivery is decoupled from client lifetime: a client that
  starts after a beacon was emitted will be sent a synthetic
  "beacon-anomaly" notification by the Repeater, prompting fresh
  searches.

The Repeater protocol is normatively specified in Section 10.

2.4. What the Protocol Does Not Do
----------------------------------

CA does not provide:

- **Authentication**. ``CA_PROTO_CLIENT_NAME`` and
  ``CA_PROTO_HOST_NAME`` carry user-supplied identity strings that the
  server MUST treat as advisory only. A CA server MUST NOT rely on
  them as a security boundary. Sites requiring authenticated access
  SHALL use SPVA (:doc:`/protocol-spec/spva`).

- **Confidentiality**. CA traffic is unencrypted. Sites requiring
  confidentiality SHALL use SPVA.

- **Integrity beyond TCP/UDP checksums**. There is no message
  authentication code or cryptographic integrity check.

- **Reliable delivery of beacons or search packets**. Both are UDP and
  MAY be lost. The protocol's recovery mechanisms are documented in
  Sections 6.4 and 9.4.

- **Structured data types**. CA's type system is the closed set of
  native types listed in Section 4.4. PVAccess (:doc:`/protocol-spec/pva`)
  carries arbitrary PVData structures.

----

3. Transport Layer
==================

3.1. Transport Protocols
------------------------

CA uses two IP transport protocols:

- **UDP** — for name discovery (``CA_PROTO_SEARCH``), beacons
  (``CA_PROTO_RSRV_IS_UP``), repeater registration (``REPEATER_REGISTER``,
  ``REPEATER_CONFIRM``), and certain version-exchange messages
  (Section 13.2).
- **TCP** — for all operations on a connected channel and for
  TCP-based search (V4.12+, Section 6.7).

A CA server MUST listen on both UDP and TCP at the same port number
(``EPICS_CA_SERVER_PORT``, default 5064). A CA client MUST send UDP
search packets to that port number on the server-address-list
destinations.

3.2. Default Port Assignments
-----------------------------

The default port numbers are derived from a fixed formula:

::

    PORT_BASE       = 5000 + 56                                = 5056
    SERVER_PORT     = PORT_BASE + (major-revision * 2)         = 5064
    REPEATER_PORT   = PORT_BASE + (major-revision * 2) + 1     = 5065

The constant 5000 above is the value of the BSD socket
``IPPORT_USERRESERVED`` constant (the start of the user-reserved
port range on POSIX systems); the spec itself does not depend on
the symbolic name of this constant and the ``5000`` value MUST be
used directly by implementations on systems that do not provide
``IPPORT_USERRESERVED``.

The factor "major-revision × 2" in the formula reflects the
historical convention that each major protocol revision occupies
two port numbers (server + repeater). For CA major revision 4
(this specification), this yields 5064 (server) and 5065
(repeater).

.. table:: Default CA port assignments
   :widths: auto

   +------------------------+-------+----------------+--------------------------------+
   | Use                    | Port  | Transport      | Override                       |
   +========================+=======+================+================================+
   | CA server (TCP)        | 5064  | TCP            | ``EPICS_CA_SERVER_PORT``       |
   +------------------------+-------+----------------+--------------------------------+
   | CA search / beacons    | 5064  | UDP            | ``EPICS_CA_SERVER_PORT``       |
   +------------------------+-------+----------------+--------------------------------+
   | CA repeater            | 5065  | UDP            | ``EPICS_CA_REPEATER_PORT``     |
   +------------------------+-------+----------------+--------------------------------+

Implementations MUST honor ``EPICS_CA_SERVER_PORT`` and
``EPICS_CA_REPEATER_PORT`` when set in the environment. A site may use
non-default port numbers for isolation (multiple independent CA networks
on one host); all clients and servers in a given CA network MUST agree
on the port numbers in use.

3.3. UDP Usage
--------------

3.3.1. Datagram Composition
~~~~~~~~~~~~~~~~~~~~~~~~~~~

A single UDP datagram MAY contain one or more CA messages
concatenated. There is no datagram-level framing beyond the per-message
``caHdr`` (Section 4). A receiver MUST iterate through the datagram,
dispatching each message in turn, until the datagram is exhausted or a
header indicates a payload that would extend beyond the datagram
boundary (in which case the receiver MUST discard the rest of the
datagram and SHOULD log a malformed-message warning).

3.3.2. Maximum Datagram Size
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The constants ``MAX_UDP_SEND`` (1024 octets) and ``MAX_UDP_RECV``
(0xffff + 16 = 65551 octets) define the maximum send and receive
buffer sizes. ``ETHERNET_MAX_UDP`` (1472 octets) is documented as the
nominal Ethernet maximum after IP and UDP header overhead but is not
enforced.

A sender MUST NOT emit a datagram exceeding ``MAX_UDP_SEND`` octets.
A receiver MUST tolerate datagrams up to ``MAX_UDP_RECV`` octets to
remain forward-compatible with future implementations that may emit
larger datagrams.

3.3.3. Broadcast and Unicast
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Search packets and beacons are typically transmitted to the IPv4
limited broadcast address (255.255.255.255) or to subnet-directed
broadcast addresses, but UNICAST destinations are also valid and
common in routed deployments. The set of destinations is determined
by the ``EPICS_CA_ADDR_LIST`` environment variable and the
``EPICS_CA_AUTO_ADDR_LIST`` boolean (Section 3.5).

A server-side UDP receiver MUST accept search packets from any source
address; the server replies unicast to the source IP and source port
of the search request, regardless of whether the original packet was
broadcast or unicast.

3.3.4. UDP Reliability
~~~~~~~~~~~~~~~~~~~~~~

UDP is unreliable. The protocol does not retransmit search packets or
beacons at the message level; loss is recovered by:

- Periodic re-emission of beacons (Section 9).
- Client-side re-emission of search packets with exponential back-off
  (Section 6.4) until a reply is received.
- The Repeater's beacon-anomaly synthesis (Section 10.4) prompts
  clients to re-search when a previously-known server stops beaconing.

3.4. TCP Usage
--------------

3.4.1. Connection Establishment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

After receiving a successful UDP search reply, the client opens a TCP
connection to the server at the ``(IP, TCP-port)`` returned in the
reply. The TCP connection is initiated using ``connect(2)`` semantics;
once ESTABLISHED at the TCP layer, the client MUST send a
``CA_PROTO_VERSION`` message as its first byte (Section 13.1).

3.4.2. Connection Sharing
~~~~~~~~~~~~~~~~~~~~~~~~~

A single TCP connection between a given client and server SHOULD
multiplex all channels the client opens against that server.
Implementations MUST NOT open more than one TCP connection per
``(client-process, server, priority)`` triple unless priority dispatch
(Section 11.4) is in use, in which case one connection per priority
level is permitted.

3.4.3. Message Boundaries on TCP
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

TCP is a byte stream. A receiver MUST reassemble the byte stream
into discrete CA messages by reading the 16-octet ``caHdr`` (or
24-octet extended header, Section 4.3), examining the ``m_postsize``
field (which may have been promoted to ``m_postsize_big``), and
reading exactly that many octets of payload (with padding to an
8-octet boundary; Section 4.4).

3.4.4. Maximum TCP Message Size
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``MAX_TCP`` is 16384 octets (16 KiB). A single CA message — header
plus payload — MUST NOT exceed ``MAX_TCP`` for clients or servers at
protocol minor version less than 9. From V4.9 onward, the extended
header (Section 4.3) supports payloads up to 2³² − 1 octets per
message.

3.4.5. Connection Loss
~~~~~~~~~~~~~~~~~~~~~~

When the TCP connection is closed (either side), all server-side
channel state MUST be released; all in-flight client-side requests
MUST fail with ``ECA_DISCONN``. Pending subscriptions MUST be
re-established by the client after reconnection. Re-connection logic
SHOULD include exponential back-off to avoid thundering-herd behavior
when many clients lose a single server simultaneously.

3.5. Address List Handling
--------------------------

Two environment variables determine the destinations of UDP search
packets and beacon listening:

- ``EPICS_CA_ADDR_LIST`` — a whitespace-separated list of IP
  addresses or hostnames, with optional ``:port`` suffix per entry.
  When set, the listed addresses are added to the search destination
  list. Addresses without a ``:port`` suffix use ``EPICS_CA_SERVER_PORT``.
- ``EPICS_CA_AUTO_ADDR_LIST`` — boolean (``YES`` or ``NO``, default
  ``YES``). When ``YES``, the OS-reported broadcast addresses of all
  locally-bound interfaces are added to the search destination list
  automatically. When ``NO``, only ``EPICS_CA_ADDR_LIST`` is used.

A client MUST send each search packet to every destination in the
final list. The client MAY parallelize transmission to all
destinations.

3.6. IPv6 Considerations
------------------------

CA major revision 4 is defined over IPv4 only. The protocol
defines no IPv6-specific message variants and provides no
mechanism for negotiating IPv6 transport. Sites requiring IPv6
transport SHALL use PVAccess (:doc:`/protocol-spec/pva`). This
restriction MAY be lifted in a future major protocol revision.

----

4. Common Message Format
========================

4.1. Standard Header (caHdr)
----------------------------

Every CA message begins with the fixed 16-octet header. As a C
structure (informative — the normative definition is the field
table that follows):

.. code-block:: c

    struct caHdr {
        uint16_t m_cmmd;       /* operation to be performed */
        uint16_t m_postsize;   /* size of payload */
        uint16_t m_dataType;   /* operation data type */
        uint16_t m_count;      /* operation data count */
        uint32_t m_cid;        /* channel identifier */
        uint32_t m_available;  /* protocol stub dependent */
    };

All fields are transmitted in network byte order (big-endian).

.. table:: caHdr field layout (16 octets)
   :widths: auto

   +--------+------+----------------+--------------------------------------+
   | Offset | Size | Field          | Meaning                              |
   +========+======+================+======================================+
   | 0      | 2    | ``m_cmmd``     | Command code (Section 4.6)           |
   +--------+------+----------------+--------------------------------------+
   | 2      | 2    | ``m_postsize`` | Payload size in octets               |
   +--------+------+----------------+--------------------------------------+
   | 4      | 2    | ``m_dataType`` | DBR type code (Section 4.7)          |
   +--------+------+----------------+--------------------------------------+
   | 6      | 2    | ``m_count``    | Element count                        |
   +--------+------+----------------+--------------------------------------+
   | 8      | 4    | ``m_cid``      | Channel identifier (CID or SID)      |
   +--------+------+----------------+--------------------------------------+
   | 12     | 4    | ``m_available``| Per-command auxiliary value          |
   +--------+------+----------------+--------------------------------------+

4.2. Field Semantics
--------------------

``m_cmmd``
   Command code identifying the operation. The complete list is in
   Section 4.6. Values 0 through 27 are defined; values 28 and above
   are reserved for future protocol extensions and MUST be rejected
   by current implementations.

``m_postsize``
   Size of the payload in octets, EXCLUDING the header itself.
   Standard-header form: ``m_postsize`` is the literal payload size
   and MUST be ≤ 0xFFFF (65535). Extended-header form (Section 4.3):
   ``m_postsize`` MUST be 0xFFFF (the sentinel) and the actual size is
   carried in the extended ``m_postsize_big`` field.

``m_dataType``
   For data-bearing operations (READ, WRITE, EVENT_ADD, etc.), the
   DBR type code (Section 4.7). For other operations, command-specific
   (see the per-command sections).

``m_count``
   For data-bearing operations: number of elements. ``m_count = 1`` is
   a scalar; ``m_count > 1`` is an array. Per the standard header, the
   maximum is 0xFFFF; extended-header form supports up to 2³² − 1.
   ``m_count = 0`` MAY be used in V4.13+ requests for "all elements"
   semantics; older versions MUST treat zero as an error
   (``ECA_BADCOUNT``, Section 12.2).

``m_cid``
   The channel identifier. In client-to-server messages, this is the
   ``SID`` (server-side identifier) returned in
   ``CA_PROTO_CREATE_CHAN_RESP``; in server-to-client messages relating
   to a channel, this is the ``CID`` (client-side identifier) chosen
   by the client when ``CA_PROTO_CREATE_CHAN`` was sent. (Sections 5.4
   and 7.2.)

``m_available``
   Per-command auxiliary value. Most commonly used as the IOI for
   read/write/monitor request-response correlation (Section 8.1.2),
   or as the access-rights bitmask in ``CA_PROTO_ACCESS_RIGHTS``
   (Section 7.4).

4.3. Extended Header (V4.9+)
----------------------------

When ``m_postsize`` or ``m_count`` exceeds the 16-bit field maximum
(0xFFFF), V4.9+ implementations use an extended 24-octet header.
The sentinel for "extended header follows" is ``m_postsize ==
0xFFFF`` AND ``m_count == 0`` in the standard 16-octet header.
Eight additional octets (two big-endian ``uint32`` fields) appended
immediately after the standard header carry the actual payload
size and the actual element count:

.. table:: Extended-header field layout (24 octets total, V4.9+)
   :widths: auto

   +--------+------+--------------------+----------------------------------+
   | Offset | Size | Field              | Meaning                          |
   +========+======+====================+==================================+
   | 0      | 2    | ``m_cmmd``         | Command code                     |
   +--------+------+--------------------+----------------------------------+
   | 2      | 2    | ``m_postsize``     | 0xFFFF (sentinel)                |
   +--------+------+--------------------+----------------------------------+
   | 4      | 2    | ``m_dataType``     | DBR type code                    |
   +--------+------+--------------------+----------------------------------+
   | 6      | 2    | ``m_count``        | 0 (sentinel)                     |
   +--------+------+--------------------+----------------------------------+
   | 8      | 4    | ``m_cid``          | Channel identifier               |
   +--------+------+--------------------+----------------------------------+
   | 12     | 4    | ``m_available``    | Per-command auxiliary            |
   +--------+------+--------------------+----------------------------------+
   | 16     | 4    | ``m_postsize_big`` | Actual payload size in octets    |
   +--------+------+--------------------+----------------------------------+
   | 20     | 4    | ``m_count_big``    | Actual element count             |
   +--------+------+--------------------+----------------------------------+

A V4.9+ client communicating with a V<4.9 server MUST NOT use the
extended header; if a transfer requires extended-header form, the
client MUST fail it locally with ``ECA_TOLARGE`` and SHOULD report
``ECA_16KARRAYCLIENT`` to the application (Section 12.2).

4.4. Payload Padding
--------------------

Every CA message — header plus payload — MUST be padded with
trailing zero octets to a multiple of 8 octets. The padding is
NOT counted in ``m_postsize``; receivers MUST consume and discard
the padding between messages.

For a payload of ``P`` octets, the on-wire size of one message is:

::

    16 + ((P + 7) & ~7)        for the standard header
    32 + ((P + 7) & ~7)        for the extended header

Senders MUST emit padding octets as zero. Receivers MUST tolerate
non-zero padding (treat as opaque) but SHOULD log a warning if any
non-zero pad octet is seen, as it indicates a malformed peer.

4.5. Message Size Limits
------------------------

.. table:: Message size limits per transport
   :widths: auto

   +-----------+------------------+----------------------------+
   | Transport | Limit            | Applies to                 |
   +===========+==================+============================+
   | UDP send  | 1024 octets      | One datagram               |
   +-----------+------------------+----------------------------+
   | UDP recv  | 65551 octets     | One datagram (incl. ext)   |
   +-----------+------------------+----------------------------+
   | TCP       | 16384 octets     | One CA message (V<4.9)     |
   +-----------+------------------+----------------------------+
   | TCP       | 2³² − 1 octets   | One CA message (V4.9+)     |
   +-----------+------------------+----------------------------+

A sender that exceeds these limits MUST fail the operation locally;
a receiver that detects an over-limit message SHOULD close the
connection and re-establish.

4.6. Command Codes
------------------

The complete set of CA command codes:

.. table:: CA command codes (all defined values)
   :widths: auto

   +----+----------------------------+--------------------------------------+----------+
   | #  | Symbol                     | Purpose                              | Min Ver  |
   +====+============================+======================================+==========+
   | 0  | ``CA_PROTO_VERSION``       | Version exchange                     | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 1  | ``CA_PROTO_EVENT_ADD``     | Add subscription                     | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 2  | ``CA_PROTO_EVENT_CANCEL``  | Cancel subscription                  | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 3  | ``CA_PROTO_READ``          | Read channel value (deprecated)      | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 4  | ``CA_PROTO_WRITE``         | Write channel value (no response)    | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 5  | ``CA_PROTO_SNAPSHOT``      | (obsolete; not used)                 | —        |
   +----+----------------------------+--------------------------------------+----------+
   | 6  | ``CA_PROTO_SEARCH``        | Channel name search (UDP, also TCP   | 4.0      |
   |    |                            | from V4.12)                          |          |
   +----+----------------------------+--------------------------------------+----------+
   | 7  | ``CA_PROTO_BUILD``         | (obsolete; not used)                 | —        |
   +----+----------------------------+--------------------------------------+----------+
   | 8  | ``CA_PROTO_EVENTS_OFF``    | Subscription flow control off        | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 9  | ``CA_PROTO_EVENTS_ON``     | Subscription flow control on         | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 10 | ``CA_PROTO_READ_SYNC``     | Purge old reads                      | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 11 | ``CA_PROTO_ERROR``         | Error response                       | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 12 | ``CA_PROTO_CLEAR_CHANNEL`` | Release channel resources            | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 13 | ``CA_PROTO_RSRV_IS_UP``    | Beacon                               | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 14 | ``CA_PROTO_NOT_FOUND``     | Negative search response (V4.1+)     | 4.1      |
   +----+----------------------------+--------------------------------------+----------+
   | 15 | ``CA_PROTO_READ_NOTIFY``   | Read with ack response               | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 16 | ``CA_PROTO_READ_BUILD``    | (obsolete; not used)                 | —        |
   +----+----------------------------+--------------------------------------+----------+
   | 17 | ``REPEATER_CONFIRM``       | Repeater registration confirmation   | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 18 | ``CA_PROTO_CREATE_CHAN``   | Open channel                         | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 19 | ``CA_PROTO_WRITE_NOTIFY``  | Write with ack response              | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 20 | ``CA_PROTO_CLIENT_NAME``   | Identify client user                 | 4.1      |
   +----+----------------------------+--------------------------------------+----------+
   | 21 | ``CA_PROTO_HOST_NAME``     | Identify client host                 | 4.1      |
   +----+----------------------------+--------------------------------------+----------+
   | 22 | ``CA_PROTO_ACCESS_RIGHTS`` | Server-pushed access rights update   | 4.2      |
   +----+----------------------------+--------------------------------------+----------+
   | 23 | ``CA_PROTO_ECHO``          | Connection liveness probe            | 4.3      |
   +----+----------------------------+--------------------------------------+----------+
   | 24 | ``REPEATER_REGISTER``      | Repeater registration request        | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 25 | ``CA_PROTO_SIGNAL``        | Internal use; wakes server select    | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 26 | ``CA_PROTO_CREATE_CH_FAIL``| Channel-create failure response      | 4.0      |
   +----+----------------------------+--------------------------------------+----------+
   | 27 | ``CA_PROTO_SERVER_DISCONN``| Server-initiated channel disconnect  | 4.0      |
   +----+----------------------------+--------------------------------------+----------+

4.7. DBR Type Codes
-------------------

The ``m_dataType`` field carries a Database Request (DBR) type
code. A DBR type combines a *base type* (DBF_*) with an optional
*meta-data prefix*. The base types are:

.. table:: DBF base types
   :widths: auto

   +---------------------+-------+------------+--------------------------------+
   | Symbol              | Code  | Element    | Description                    |
   +=====================+=======+============+================================+
   | ``DBF_STRING``      | 0     | 40 octets  | Null-padded ASCII (40 max)     |
   +---------------------+-------+------------+--------------------------------+
   | ``DBF_INT``,        | 1     | 2 octets   | Signed 16-bit integer          |
   | ``DBF_SHORT``       |       |            |                                |
   +---------------------+-------+------------+--------------------------------+
   | ``DBF_FLOAT``       | 2     | 4 octets   | IEEE 754 single-precision      |
   +---------------------+-------+------------+--------------------------------+
   | ``DBF_ENUM``        | 3     | 2 octets   | Enumerated index (0..15)       |
   +---------------------+-------+------------+--------------------------------+
   | ``DBF_CHAR``        | 4     | 1 octet    | Signed 8-bit integer           |
   +---------------------+-------+------------+--------------------------------+
   | ``DBF_LONG``        | 5     | 4 octets   | Signed 32-bit integer          |
   +---------------------+-------+------------+--------------------------------+
   | ``DBF_DOUBLE``      | 6     | 8 octets   | IEEE 754 double-precision      |
   +---------------------+-------+------------+--------------------------------+
   | ``DBF_NO_ACCESS``   | 7     | —          | Channel exists but no access   |
   +---------------------+-------+------------+--------------------------------+

The DBR namespace then layers four meta-data prefixes on top:

.. table:: DBR meta-data prefixes
   :widths: auto

   +--------------+-------+---------------------------------------------+
   | Prefix       | Range | Adds to the value                           |
   +==============+=======+=============================================+
   | (plain)      | 0–6   | Just the value                              |
   +--------------+-------+---------------------------------------------+
   | ``DBR_STS_`` | 7–13  | Status + severity                           |
   +--------------+-------+---------------------------------------------+
   | ``DBR_TIME_``| 14–20 | Status + severity + EPICS timestamp         |
   +--------------+-------+---------------------------------------------+
   | ``DBR_GR_``  | 21–27 | Status + severity + display limits          |
   +--------------+-------+---------------------------------------------+
   | ``DBR_CTRL_``| 28–34 | Status + severity + control limits          |
   +--------------+-------+---------------------------------------------+

For example, ``DBR_TIME_DOUBLE`` (code 20) is a double-precision
value preceded by a 2-byte status, 2-byte severity, and a 64-bit
EPICS timestamp. The full per-prefix layout (the on-wire field
order and width for each meta-data prefix combined with each base
type) is normative protocol detail that this revision of the
specification leaves to a future amendment; existing
implementations have implemented the layouts compatibly and the
amendment will reflect the established forms.

4.8. Element Count Semantics
----------------------------

For data-bearing requests:

- ``m_count == 0`` (V4.13+): "Send all elements that exist"
  semantics. The server returns the channel's full native element
  count.
- ``m_count == 0`` (V<4.13): MUST be treated as ``ECA_BADCOUNT`` and
  the request rejected.
- ``m_count == 1``: Scalar request. Server returns exactly one
  element.
- ``m_count > 1``: Array request. Server returns up to ``m_count``
  elements; if the channel's native count is less than ``m_count``,
  the server returns the channel's actual count and the receiver
  inspects the ``m_count`` field of the response to know how many
  were returned.

A request for ``m_count`` greater than the channel's native count
is NOT an error; the server returns the channel's actual count. A
request for ``m_count`` exceeding ``MAX_TCP`` divided by the element
size MUST return ``ECA_TOLARGE``.

----

5. Connection Establishment
===========================

5.1. Connection Lifecycle Overview
-----------------------------------

A CA TCP connection between a client and server proceeds through
the following phases:

::

    [client]                          [server]
       |                                  |
       |  TCP SYN/SYN-ACK/ACK             |
       |<-------------------------------->|
       |                                  |
       |  CA_PROTO_VERSION (client)       |
       |--------------------------------->|
       |                                  |
       |  CA_PROTO_VERSION (server)       |
       |<---------------------------------|
       |                                  |
       |  CA_PROTO_CLIENT_NAME [V4.1+]    |
       |--------------------------------->|
       |  CA_PROTO_HOST_NAME [V4.1+]      |
       |--------------------------------->|
       |                                  |
       |  CA_PROTO_CREATE_CHAN [per PV]   |
       |<-------------------------------->|
       |  ... operations ...              |
       |<-------------------------------->|
       |                                  |
       |  TCP FIN                         |
       |<-------------------------------->|

5.2. Initial Version Exchange
-----------------------------

The client MUST send ``CA_PROTO_VERSION`` as the first message on a
new TCP connection, before any other message. The server MUST send
its own ``CA_PROTO_VERSION`` in response before accepting any further
client messages.

``CA_PROTO_VERSION`` (command code 0) header layout:

.. table:: CA_PROTO_VERSION header
   :widths: auto

   +-----------------+-----------------------+------------------------------+
   | Field           | Sender (client)       | Receiver (server) reply      |
   +=================+=======================+==============================+
   | ``m_cmmd``      | 0                     | 0                            |
   +-----------------+-----------------------+------------------------------+
   | ``m_postsize``  | 0                     | 0                            |
   +-----------------+-----------------------+------------------------------+
   | ``m_dataType``  | priority (V4.9+) [1]_ | reserved (0)                 |
   +-----------------+-----------------------+------------------------------+
   | ``m_count``     | minor revision        | minor revision               |
   +-----------------+-----------------------+------------------------------+
   | ``m_cid``       | 0                     | 0                            |
   +-----------------+-----------------------+------------------------------+
   | ``m_available`` | 0                     | 0                            |
   +-----------------+-----------------------+------------------------------+

.. [1] V4.9 introduced priority dispatch (Section 11.4). The client's
   ``m_dataType`` carries the priority value (0..99) for the connection.
   Pre-V4.9 clients send 0; V4.9+ servers MUST tolerate 0 as
   "default priority".

The effective minor version for the connection is
``min(client_minor, server_minor)``. Both peers MUST behave according
to this effective version for the lifetime of the connection.

5.3. Client Identification (V4.1+)
----------------------------------

After the version exchange, a V4.1+ client SHOULD (but is not REQUIRED
to) send ``CA_PROTO_CLIENT_NAME`` and ``CA_PROTO_HOST_NAME`` to
identify itself to the server. These messages carry user-supplied
ASCII strings as payload.

``CA_PROTO_CLIENT_NAME`` (command code 20):

- ``m_postsize``: length of the ASCII user-name string, padded with
  zero bytes to a multiple of 8.
- ``m_dataType``, ``m_count``, ``m_cid``, ``m_available``: 0 (reserved).
- Payload: null-terminated ASCII string. Implementations SHOULD
  reject strings longer than 500 octets as malformed; this bound
  prevents resource-exhaustion via oversized name strings.

``CA_PROTO_HOST_NAME`` (command code 21): same structure, with the
client's host-name string as payload.

A server MUST treat the contents of these fields as advisory only
and MUST NOT use them as a security boundary. See Section 15.1.

5.4. Channel Creation
---------------------

Once the version exchange (and optional name identification) has
completed, the client opens channels by sending ``CA_PROTO_CREATE_CHAN``
(command code 18). Each channel-create request carries:

.. table:: CA_PROTO_CREATE_CHAN request
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 18                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | length of PV name string (padded to 8)       |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_count``     | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | client-chosen 32-bit CID (must be unique     |
   |                 | within this connection)                      |
   +-----------------+----------------------------------------------+
   | ``m_available`` | client-supported minor version (V4.4+)       |
   +-----------------+----------------------------------------------+
   | Payload         | PV name (null-terminated ASCII, padded to 8) |
   +-----------------+----------------------------------------------+

The CID space is per-connection. A client MAY reuse a CID for a
different channel after the original channel is destroyed
(``CA_PROTO_CLEAR_CHANNEL``). Implementations SHOULD use sequential
or hash-based CID allocation; collisions within a single connection
MUST be detected and avoided by the client.

The server's response is detailed in Section 7.2.

5.5. Connection Priority Negotiation (V4.9+)
--------------------------------------------

V4.9 introduced a priority field in ``CA_PROTO_VERSION``. The priority
is an integer in the range ``[CA_PROTO_PRIORITY_MIN, CA_PROTO_PRIORITY_MAX]``
(0 to 99). Multiple TCP connections to the same server with different
priorities MAY be opened by one client; the server MUST dispatch
operations on each connection's per-priority queue independently
(Section 11.4).

A client requesting a priority that the server does not support
(typically a server below V4.9) SHOULD fall back to a single
priority-0 connection.

----

6. Name Resolution and Search
=============================

6.1. Search Request
-------------------

A client locates servers hosting a named PV by sending
``CA_PROTO_SEARCH`` (command code 6). The search request is normally
sent over UDP to the destinations in the client's address list
(Section 3.5).

.. table:: CA_PROTO_SEARCH request
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 6                                            |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | length of PV name string (padded to 8)       |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | reply flag: ``DOREPLY`` (10) or              |
   |                 | ``DONTREPLY`` (5)                            |
   +-----------------+----------------------------------------------+
   | ``m_count``     | client minor revision                        |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | client-chosen CID (echoed in reply)          |
   +-----------------+----------------------------------------------+
   | ``m_available`` | client-chosen CID (echoed in reply, again)   |
   +-----------------+----------------------------------------------+
   | Payload         | PV name (null-terminated ASCII, padded)      |
   +-----------------+----------------------------------------------+

The CID is duplicated in ``m_cid`` and ``m_available`` for historical
reasons (some pre-V4.0 receivers used one and some the other; current
implementations SHOULD set both to the same value).

The reply flag ``m_dataType``:

- ``DOREPLY`` (10): The server, if it does NOT host the PV, SHOULD
  send ``CA_PROTO_NOT_FOUND`` (Section 6.3). Used for unicast
  searches where the client wants explicit confirmation.
- ``DONTREPLY`` (5): The server, if it does NOT host the PV, MUST
  silently ignore the request. Used for broadcast searches to avoid
  flooding the client with negative replies.

6.2. Positive Search Reply
--------------------------

If the server hosts the PV, it replies with a UDP unicast
``CA_PROTO_SEARCH`` response sent to the source IP and source port
of the search request:

.. table:: CA_PROTO_SEARCH response (positive)
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 6                                            |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 8 (V4.1+ — payload carries server minor      |
   |                 | revision; see Payload below) or 0 (pre-V4.1) |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | server TCP port number                       |
   +-----------------+----------------------------------------------+
   | ``m_count``     | reserved (set 0 by server, ignored by        |
   |                 | client)                                      |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | pre-V4.8: server's IPv4 address (in network  |
   |                 | byte order). V4.8+: ``INADDR_BROADCAST``     |
   |                 | (0xFFFFFFFF) sentinel; client MUST take      |
   |                 | server IP from the UDP source address        |
   +-----------------+----------------------------------------------+
   | ``m_available`` | client CID from the request (echoed)         |
   +-----------------+----------------------------------------------+
   | Payload         | V4.1+: 8 octets. Bytes 0..1 hold the         |
   |                 | server's minor revision in network byte      |
   |                 | order; bytes 2..7 reserved (sender SHOULD    |
   |                 | set zero, receiver MUST ignore).             |
   +-----------------+----------------------------------------------+

The client matches the response to its outstanding request via the
echoed CID in ``m_available``. The server's TCP port may differ from
``EPICS_CA_SERVER_PORT`` if the server is bound to a non-default
port; the client MUST connect to the port reported in ``m_dataType``,
not to ``EPICS_CA_SERVER_PORT`` directly.

The IP address to which the client connects is the IP source address
of the UDP reply datagram, NOT any address embedded in the payload.
This is critical for correct operation behind NAT or with multi-homed
servers.

6.3. Negative Search Reply (V4.1+)
----------------------------------

V4.1 introduced ``CA_PROTO_NOT_FOUND`` (command code 14) for
unicast-only negative replies (when ``DOREPLY`` was set):

.. table:: CA_PROTO_NOT_FOUND
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 14                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | reply flag from the request (echoed)         |
   +-----------------+----------------------------------------------+
   | ``m_count``     | client minor revision (echoed)               |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | client CID from the request                  |
   +-----------------+----------------------------------------------+
   | ``m_available`` | client CID from the request                  |
   +-----------------+----------------------------------------------+

A V<4.1 server cannot generate this message; clients MUST NOT
require it for correctness, only treat it as a hint that one
particular server is sure it does not host the PV.

6.4. Search Retransmission and Back-off
---------------------------------------

A client receiving no reply within an implementation-defined
timeout MUST retransmit the search request. Implementations SHOULD
use exponential back-off and SHOULD continue retransmitting until
the application cancels the search; the exact initial interval,
back-off factor, maximum interval, and retry count are
implementation-defined.

Each retransmission MUST use the same CID. The retransmission MAY be
sent to a different destination from the address list (round-robin)
to spread load.

6.5. UDP Search Sequence Numbers (V4.11+)
-----------------------------------------

V4.11 introduced sequence numbers in UDP messages emitted by servers,
to help clients distinguish duplicates. A V4.11+ server MAY include a
sequence number; the client uses it to deduplicate replies from
multi-homed servers reaching the client via two interfaces.

The sequence number is conveyed in the ``CA_PROTO_VERSION`` UDP
message that prefixes every UDP datagram emitted by V4.11+ servers,
with the marker ``m_dataType == sequenceNoIsValid (1)`` and the
sequence number in ``m_available``.

6.6. Search Response Source Port
--------------------------------

A server's UDP search reply MAY originate from a different UDP source
port than the server's listening port. Clients MUST match the reply
to a request via the echoed CID, not via the source port. (Older
client implementations that bound their UDP receive socket and
expected replies on a specific port have been deprecated since V4.0.)

6.7. TCP-Based Search (V4.12+)
------------------------------

V4.12 introduced TCP-based search: a client with an established TCP
connection to one server MAY send ``CA_PROTO_SEARCH`` over that TCP
connection, and the server replies on the same connection. This is
useful for routed deployments where UDP search is filtered.

A V4.12+ server MUST handle ``CA_PROTO_SEARCH`` arriving on a TCP
connection; pre-V4.12 servers MUST NOT (they will reject with
``CA_PROTO_ERROR``).

6.8. Duplicate Server Detection
-------------------------------

If multiple servers reply positively to a search for the same PV
name (a configuration error: same PV name hosted on multiple
servers), the client SHOULD log ``ECA_DBLCHNL`` and SHOULD use the
first reply received. The client MAY refuse to connect at all and
require manual disambiguation. Implementations MUST NOT silently
choose between competing servers.

----

7. Channel Lifecycle
====================

7.1. Channel States
-------------------

A channel transitions through the following states:

::

    [client]
       |
       | CREATE_CHAN sent
       v
    +-------------+
    | PENDING     |
    +-------------+
       |
       | CREATE_CHAN_RESP rcvd OR CREATE_CH_FAIL rcvd
       v
    +-------------+              +-------------+
    | CONNECTED   | --[error]--> | DISCONNECTED|
    +-------------+              +-------------+
       |                              |
       | CLEAR_CHANNEL sent           |
       | OR connection closed         |
       v                              v
    +-------------+              +-------------+
    | DESTROYED   | <----------- | DESTROYED   |
    +-------------+              +-------------+

7.2. CREATE_CHAN Response (Success)
-----------------------------------

A server that successfully creates a channel for a requested PV
responds with ``CA_PROTO_CREATE_CHAN`` (command 18) sent back over
the same TCP connection:

.. table:: CA_PROTO_CREATE_CHAN response (success)
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 18                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | DBR type of the channel's native value       |
   +-----------------+----------------------------------------------+
   | ``m_count``     | element count of the channel's native value  |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | client CID (echoed from request)             |
   +-----------------+----------------------------------------------+
   | ``m_available`` | server-chosen 32-bit SID                     |
   +-----------------+----------------------------------------------+

The client MUST cache the SID for use as ``m_cid`` in all subsequent
operations on this channel (READ, WRITE, EVENT_ADD, etc.). The server
MUST cache the CID for use in server-pushed messages
(``CA_PROTO_ACCESS_RIGHTS``, ``CA_PROTO_SERVER_DISCONN``).

The server-pushed ``CA_PROTO_ACCESS_RIGHTS`` message (Section 7.4)
typically follows ``CA_PROTO_CREATE_CHAN`` immediately, before the
client issues any operation against the channel.

7.3. CREATE_CHAN Response (Failure)
-----------------------------------

If the server cannot allocate channel resources (memory exhaustion,
PV access denied, etc.), it responds with ``CA_PROTO_CREATE_CH_FAIL``
(command 26):

.. table:: CA_PROTO_CREATE_CH_FAIL
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 26                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_count``     | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | client CID (echoed from request)             |
   +-----------------+----------------------------------------------+
   | ``m_available`` | 0                                            |
   +-----------------+----------------------------------------------+

The client MUST mark the channel as not-yet-created and MAY retry
the ``CREATE_CHAN`` request after an implementation-defined back-off.
Repeated failures SHOULD be reported to the application as
``ECA_ALLOCMEM`` or ``ECA_INTERNAL`` depending on context.

7.4. Access Rights Notification
-------------------------------

After ``CREATE_CHAN`` succeeds (and at any later time when a
channel's access rights change at the server), the server MUST send
``CA_PROTO_ACCESS_RIGHTS`` (command 22):

.. table:: CA_PROTO_ACCESS_RIGHTS
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 22                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_count``     | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | client CID                                   |
   +-----------------+----------------------------------------------+
   | ``m_available`` | bitmask of access rights                     |
   +-----------------+----------------------------------------------+

The ``m_available`` bitmask:

- Bit 0 (``CA_PROTO_ACCESS_RIGHT_READ``): channel may be read
- Bit 1 (``CA_PROTO_ACCESS_RIGHT_WRITE``): channel may be written

A client receiving access rights ``0`` (neither read nor write) MAY
keep the channel open but MUST fail any operation against it locally
with ``ECA_NORDACCESS`` or ``ECA_NOWTACCESS`` as appropriate.

The server MAY send ``CA_PROTO_ACCESS_RIGHTS`` at any time after
``CREATE_CHAN`` to notify the client of changing rights (e.g. due to
reconfiguration of the access security file). The client MUST
process such asynchronous updates and update any application state
that depends on access rights.

7.5. Channel Clearing (Client-Initiated)
----------------------------------------

A client releases a channel by sending ``CA_PROTO_CLEAR_CHANNEL``
(command 12):

.. table:: CA_PROTO_CLEAR_CHANNEL request
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 12                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_count``     | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | server SID                                   |
   +-----------------+----------------------------------------------+
   | ``m_available`` | client CID                                   |
   +-----------------+----------------------------------------------+

The server MUST respond with ``CA_PROTO_CLEAR_CHANNEL`` mirroring the
SID and CID, and MUST release all server-side resources for the
channel. After sending CLEAR_CHANNEL, the client MUST NOT use the
SID for any further operation. Any in-flight responses for that
channel that have not yet arrived MUST be discarded by the client.

7.6. Channel Disconnect (Server-Initiated)
------------------------------------------

If the server unilaterally destroys a channel (PV is removed from the
database, server is shutting down, access denied retroactively), it
sends ``CA_PROTO_SERVER_DISCONN`` (command 27):

.. table:: CA_PROTO_SERVER_DISCONN
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 27                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_count``     | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | client CID                                   |
   +-----------------+----------------------------------------------+
   | ``m_available`` | 0                                            |
   +-----------------+----------------------------------------------+

The client MUST treat this as a disconnect of just that one channel:
all in-flight operations against that channel MUST fail with
``ECA_DISCONN``; pending subscriptions for that channel MUST be
removed. The TCP connection itself remains open; other channels on
the same connection are unaffected.

7.7. Connection Loss
--------------------

If the TCP connection is closed by either side (FIN, RST, or
network-layer failure), all channels on that connection move to the
DISCONNECTED state. The client SHOULD attempt to reconnect (Section
3.4.5) and re-create all previously-connected channels. The server
SHALL release all per-channel resources for the lost connection
without delay.

7.8. CID and SID Reuse Rules
----------------------------

- A CID MAY be reused by the client only after the matching channel
  has been confirmed cleared (CLEAR_CHANNEL response received) or the
  TCP connection has been closed.
- A SID MAY be reused by the server only after the channel has been
  confirmed cleared or the connection has been closed.
- Within a single connection, both CID space and SID space are
  per-connection and ``ca_uint32_max`` (2³² − 1) is the maximum
  identifier value. Implementations SHOULD avoid using identifier
  ``0`` (reserved by some legacy code as "unset").

----

8. Operations on a Connected Channel
====================================

8.1. Read Operations
--------------------

Two read commands are defined. ``CA_PROTO_READ`` (3) is deprecated
and SHOULD NOT be issued by V4.1+ clients; ``CA_PROTO_READ_NOTIFY``
(15) is the modern equivalent and provides explicit response
acknowledgment.

8.1.1. CA_PROTO_READ_NOTIFY Request
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. table:: CA_PROTO_READ_NOTIFY request
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 15                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | requested DBR type                           |
   +-----------------+----------------------------------------------+
   | ``m_count``     | requested element count (0 = all in V4.13+)  |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | server SID                                   |
   +-----------------+----------------------------------------------+
   | ``m_available`` | client-chosen IOI                            |
   +-----------------+----------------------------------------------+

The IOI (Input/Output ID) is a client-allocated 32-bit handle used to
correlate the response to this request. IOI values MUST be unique
among all in-flight reads on this channel; reuse is permitted after
the response is received.

8.1.2. CA_PROTO_READ_NOTIFY Response
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. table:: CA_PROTO_READ_NOTIFY response
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 15                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | size of value payload (rounded to 8)         |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | DBR type returned (echoed from request)      |
   +-----------------+----------------------------------------------+
   | ``m_count``     | actual element count returned                |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | CA status code (Section 12.2):               |
   |                 | ``ECA_NORMAL`` on success, an error code     |
   |                 | otherwise. The ``m_cid`` slot is repurposed  |
   |                 | in responses of this command (and of         |
   |                 | ``CA_PROTO_WRITE_NOTIFY`` and                |
   |                 | ``CA_PROTO_EVENT_ADD`` updates) to carry the |
   |                 | operation's completion status rather than a  |
   |                 | channel identifier.                          |
   +-----------------+----------------------------------------------+
   | ``m_available`` | IOI from request (echoed)                    |
   +-----------------+----------------------------------------------+
   | Payload         | DBR-encoded value (Section 4.7) on success;  |
   |                 | zero-filled if the operation completed at    |
   |                 | the read-reply layer with a non-normal       |
   |                 | status.                                      |
   +-----------------+----------------------------------------------+

The client matches the response to its outstanding request via the
echoed IOI in ``m_available`` and dispatches on the status in
``m_cid``. ``m_cid`` is **not** the channel SID in responses of
this command.

If the operation fails earlier than the read-reply layer can
construct this response (e.g. the requested DBR type is invalid),
the server MAY instead emit ``CA_PROTO_ERROR`` (Section 12.1)
carrying the original IOI in its ``m_available``.

8.2. Write Operations
---------------------

Two write commands are defined. ``CA_PROTO_WRITE`` (4) is deprecated
("fire-and-forget"); ``CA_PROTO_WRITE_NOTIFY`` (19) returns an
acknowledgment when the write completes (including any database
processing chain that the write triggers on the server).

8.2.1. CA_PROTO_WRITE_NOTIFY Request
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. table:: CA_PROTO_WRITE_NOTIFY request
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 19                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | size of value payload (rounded to 8)         |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | DBR type of the supplied value               |
   +-----------------+----------------------------------------------+
   | ``m_count``     | element count of the supplied value          |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | server SID                                   |
   +-----------------+----------------------------------------------+
   | ``m_available`` | client-chosen IOI                            |
   +-----------------+----------------------------------------------+
   | Payload         | DBR-encoded value to write                   |
   +-----------------+----------------------------------------------+

8.2.2. CA_PROTO_WRITE_NOTIFY Response
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. table:: CA_PROTO_WRITE_NOTIFY response
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 19                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | echoed from request                          |
   +-----------------+----------------------------------------------+
   | ``m_count``     | echoed from request                          |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | CA status code (Section 12.2):               |
   |                 | ``ECA_NORMAL`` on successful write           |
   |                 | completion, an error code on failure         |
   |                 | (e.g. ``ECA_PUTFAIL``). Same repurposing as  |
   |                 | the ``CA_PROTO_READ_NOTIFY`` response        |
   |                 | (Section 8.1.2).                             |
   +-----------------+----------------------------------------------+
   | ``m_available`` | IOI (echoed)                                 |
   +-----------------+----------------------------------------------+

Receipt of this response indicates the server has finished
processing the write, including any record-processing
side-effects on the IOC. The status in ``m_cid`` reports the
overall success or failure. If the operation fails earlier than
the write-reply layer can construct this response, the server
MAY instead emit ``CA_PROTO_ERROR`` (Section 12.1) carrying the
original IOI.

8.3. Subscription Operations
----------------------------

8.3.1. EVENT_ADD Request
~~~~~~~~~~~~~~~~~~~~~~~~

A client subscribes to value-change notifications via
``CA_PROTO_EVENT_ADD`` (command 1). The payload is a 16-octet
``mon_info`` structure:

.. code-block:: c

    struct mon_info {
        ca_float32_t  m_lval;   /* low delta (deprecated) */
        ca_float32_t  m_hval;   /* high delta (deprecated) */
        ca_float32_t  m_toval;  /* period between samples (deprecated) */
        ca_uint16_t   m_mask;   /* event select mask */
        ca_uint16_t   m_pad;    /* extend to 32 bits */
    };

.. table:: CA_PROTO_EVENT_ADD request
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 1                                            |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 16 (size of ``mon_info``)                    |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | DBR type                                     |
   +-----------------+----------------------------------------------+
   | ``m_count``     | element count                                |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | server SID                                   |
   +-----------------+----------------------------------------------+
   | ``m_available`` | subscription ID (analogous to IOI)           |
   +-----------------+----------------------------------------------+
   | Payload         | ``mon_info`` (16 octets)                     |
   +-----------------+----------------------------------------------+

The ``m_lval``, ``m_hval``, ``m_toval`` fields of ``mon_info`` are
DEPRECATED and historically have not been honored. Senders SHOULD
set them to ``0.0f``; receivers MUST ignore them.

The ``m_mask`` field selects which kinds of changes trigger updates:

.. table:: EVENT_ADD mask bits
   :widths: auto

   +-------+-------------------+----------------------------------------+
   | Bit   | Symbol            | Triggers update on                     |
   +=======+===================+========================================+
   | 0     | ``DBE_VALUE``     | Value change                           |
   +-------+-------------------+----------------------------------------+
   | 1     | ``DBE_LOG``       | Archived/log monitor                   |
   +-------+-------------------+----------------------------------------+
   | 2     | ``DBE_ALARM``     | Alarm severity change                  |
   +-------+-------------------+----------------------------------------+
   | 3     | ``DBE_PROPERTY``  | Property metadata change (V4.10+)      |
   +-------+-------------------+----------------------------------------+

A typical subscription uses ``DBE_VALUE | DBE_ALARM`` (mask = 3) to
receive both value changes and alarm transitions.

8.3.2. EVENT_ADD First Update
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

After receiving an ``EVENT_ADD`` request, the server MUST send the
channel's current value as the first update, regardless of whether
any change has occurred. This ensures the client has a defined
initial state.

8.3.3. EVENT_ADD Response (Update)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Each update is a ``CA_PROTO_EVENT_ADD`` message identical in form to
the response of ``CA_PROTO_READ_NOTIFY`` (Section 8.1.2):

.. table:: CA_PROTO_EVENT_ADD response
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 1                                            |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | size of value payload                        |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | DBR type                                     |
   +-----------------+----------------------------------------------+
   | ``m_count``     | element count                                |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | CA status code (Section 12.2):               |
   |                 | ``ECA_NORMAL`` on a normal update, an error  |
   |                 | code if the channel encountered a fault. The |
   |                 | ``m_cid`` slot is repurposed in updates to   |
   |                 | carry the per-update completion status,      |
   |                 | matching the ``CA_PROTO_READ_NOTIFY``        |
   |                 | response convention (Section 8.1.2).         |
   +-----------------+----------------------------------------------+
   | ``m_available`` | subscription ID (echoed)                     |
   +-----------------+----------------------------------------------+
   | Payload         | DBR-encoded value (Section 4.7) on a normal  |
   |                 | update; zero-filled on a fault update.       |
   +-----------------+----------------------------------------------+

A subscription emits an unbounded stream of these update messages
until cancelled.

8.3.4. EVENT_CANCEL
~~~~~~~~~~~~~~~~~~~

A client cancels a subscription via ``CA_PROTO_EVENT_CANCEL``
(command 2):

.. table:: CA_PROTO_EVENT_CANCEL
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 2                                            |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | DBR type (echoed from EVENT_ADD)             |
   +-----------------+----------------------------------------------+
   | ``m_count``     | element count (echoed)                       |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | server SID                                   |
   +-----------------+----------------------------------------------+
   | ``m_available`` | subscription ID                              |
   +-----------------+----------------------------------------------+

The server's acknowledgment is a single ``CA_PROTO_EVENT_ADD``
message (command 1, NOT a same-form ``CA_PROTO_EVENT_CANCEL`` echo)
with ``m_postsize == 0`` and the original subscription ID in
``m_available``. This zero-payload ``EVENT_ADD`` is the **final
update** of the cancelled subscription and MUST be honored by the
client as the signal that no further updates will arrive for that
subscription ID. After emitting this final update the server MUST
NOT send any further updates for the cancelled subscription. Any
updates already in-flight (in the TCP send buffer) MAY arrive
between ``EVENT_CANCEL`` and the final update; the client MUST
tolerate them.

8.4. CA_PROTO_READ_SYNC (Purge Old Reads)
-----------------------------------------

``CA_PROTO_READ_SYNC`` (command 10) is used to discard the responses
of any in-flight read operations that the client no longer cares
about. After issuing READ_SYNC, the client SHOULD treat any
read-response with an IOI numerically less than the next-issued IOI
as stale and discard it.

This command is rarely used in modern code; ``CA_PROTO_READ_NOTIFY``
with explicit IOI tracking is preferred.

8.5. Zero-Length Array Handling (V4.13+)
----------------------------------------

V4.13 introduced explicit support for zero-element transfers:

- A read request with ``m_count == 0`` returns the channel's full
  native count (was: ``ECA_BADCOUNT`` pre-V4.13).
- A write request with ``m_count == 0`` writes zero elements (a
  no-op that nonetheless returns ``WRITE_NOTIFY`` ack;
  pre-V4.13 returns ``ECA_BADCOUNT``).
- An array channel may legitimately have zero elements at a given
  moment; pre-V4.13 read of such a channel returns ``ECA_BADCOUNT``,
  V4.13+ returns the value with ``m_count == 0`` and zero payload.

A V4.13+ client communicating with a V<4.13 server MUST translate
zero-count requests to count=1 (or fail locally with
``ECA_NOSUPPORT``); a V<4.13 client communicating with a V4.13+
server is unaffected (server treats requests as before).

----

9. Beacons and Server Announcement
==================================

9.1. Beacon Message Format
--------------------------

A CA server periodically emits ``CA_PROTO_RSRV_IS_UP`` (command 13)
beacon messages over UDP. Beacons are sent to the broadcast address
on ``EPICS_CA_REPEATER_PORT`` (default 5065), where the local
Repeater (Section 10) re-distributes them to all CA clients.

.. table:: CA_PROTO_RSRV_IS_UP (beacon)
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 13                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | server protocol minor revision               |
   +-----------------+----------------------------------------------+
   | ``m_count``     | server TCP port (server's listening port)    |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | beacon counter (V4.10+); 0 pre-V4.10         |
   +-----------------+----------------------------------------------+
   | ``m_available`` | server's IPv4 address (V4.6+); 0 pre-V4.6    |
   +-----------------+----------------------------------------------+

Pre-V4.6 servers MAY emit ``m_available = 0`` (or an unreliable value
on multi-homed hosts). From V4.6 onward, clients SHOULD take the
server's IP from ``m_available`` when non-zero, falling back to the
source address of the beacon datagram, which is correct for both
single-homed and multi-homed servers.

9.2. Beacon Counter (V4.10+)
----------------------------

V4.10 introduced a beacon counter in the ``m_cid`` field. The server
increments the counter for each beacon emitted; the counter is a
32-bit unsigned integer and wraps at 2³² − 1. A client tracking
beacons from a server can use the counter to:

- Detect missed beacons (gaps in the sequence).
- Detect server restart (counter resets to ``0`` or jumps backwards).

Pre-V4.10 servers always emit ``m_cid = 0`` and do not provide
miss-detection.

9.3. Beacon Cadence
-------------------

A CA server's beacon cadence is governed by:

- **Initial period** — 20 milliseconds for the first beacon after
  server startup (or after resuming from pause).
- **Steady-state period** — selected from environment variables in
  this precedence order:

  1. ``EPICS_CAS_BEACON_PERIOD`` if set (server-only variable).
  2. ``EPICS_CA_BEACON_PERIOD`` otherwise.
  3. 15 seconds if neither is set or the value is non-positive.

After each beacon the server doubles the interval, capped at the
steady-state period. The doubling sequence (starting at 20 ms,
capped at 15 s) is therefore: 0.02, 0.04, 0.08, 0.16, 0.32, 0.64,
1.28, 2.56, 5.12, 10.24, 15.0, 15.0, ... seconds.

If the server is paused administratively, the cadence resets to
the initial 20 ms period on resume.

9.4. Use of Beacons for Liveness Detection
------------------------------------------

A client tracking beacons from a server uses them to detect:

- **New server startup** — receipt of a beacon from a previously
  unknown ``(IP, port)`` indicates a new server has joined the
  network. The client SHOULD re-send any outstanding searches
  immediately to that server (in case the new server hosts PVs the
  client is looking for).
- **Server restart** — the beacon counter resets or jumps. The client
  SHOULD invalidate all channels currently connected to that server
  (close the TCP connection and re-search) because the server's
  internal SID space is fresh after restart.
- **Server failure** — N consecutive missed beacons from a known
  server indicate the server is unreachable. The client SHOULD treat
  this as a hint to verify connection liveness via ``CA_PROTO_ECHO``
  (Section 11.3) on any TCP connection to that server.

The exact thresholds (number of missed beacons, time-to-detect)
are implementation-defined; implementations SHOULD expose them to
operators as configuration. The environment variable
``EPICS_CA_CONN_TMO`` is conventionally honored where present and
sets the no-beacon-no-TCP-traffic interval after which a server is
declared unresponsive.

----

10. The CA Repeater
===================

10.1. Rationale
---------------

UDP sockets bound to a port are exclusive on most operating systems:
only one process per host can ``bind()`` to ``EPICS_CA_REPEATER_PORT``
at a time. If CA clients each tried to listen for beacons directly,
only one client per host would receive them; the rest would silently
miss server-up notifications.

The CA Repeater is a single per-host daemon that:

1. Binds to ``EPICS_CA_REPEATER_PORT`` exclusively.
2. Receives all beacons from servers reachable from this host.
3. Re-distributes each received beacon to every locally-registered
   CA client process.

Clients receive beacons via the Repeater rather than directly. Each
client opens its own UDP socket on an ephemeral port and registers
that port with the Repeater.

10.2. Repeater Registration (Client → Repeater)
-----------------------------------------------

A client that needs to receive beacons registers with the Repeater
on ``EPICS_CA_REPEATER_PORT`` (default 5065) on a local-host
address. Two registration forms are accepted:

1. A ``REPEATER_REGISTER`` (command 24) datagram:

   .. table:: REPEATER_REGISTER
      :widths: auto

      +-----------------+----------------------------------------------+
      | Field           | Value                                        |
      +=================+==============================================+
      | ``m_cmmd``      | 24                                           |
      +-----------------+----------------------------------------------+
      | ``m_postsize``  | 0                                            |
      +-----------------+----------------------------------------------+
      | ``m_dataType``  | 0                                            |
      +-----------------+----------------------------------------------+
      | ``m_count``     | 0                                            |
      +-----------------+----------------------------------------------+
      | ``m_cid``       | 0                                            |
      +-----------------+----------------------------------------------+
      | ``m_available`` | client's local IPv4 address, or ``0``        |
      +-----------------+----------------------------------------------+

2. A zero-length UDP datagram. This is treated as an implicit
   registration request equivalent to form 1 with all fields zero.

A client MAY register from the IPv4 loopback address (``127.0.0.1``)
or from any local non-loopback interface. Some legacy clients
alternate between the loopback address and a non-loopback local
interface to interoperate with pre-3.13-beta-11 Repeaters that did
not always accept loopback registrations.

The Repeater uses the UDP source ``(IP, port)`` of the registration
datagram as the destination to which forwarded beacons will be
re-emitted; it stores this tuple in its registration table.

10.3. Repeater Registration Acknowledgment (Repeater → Client)
--------------------------------------------------------------

The Repeater replies with ``REPEATER_CONFIRM`` (command 17):

.. table:: REPEATER_CONFIRM
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 17                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_count``     | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_available`` | client's source IPv4 (as observed by the     |
   |                 | Repeater)                                    |
   +-----------------+----------------------------------------------+

If the client does not receive a CONFIRM within an
implementation-defined timeout, it MAY assume no Repeater is
running and MAY attempt to launch one (the typical mechanism is to
fork or exec a Repeater process bundled with the implementation).
After launching, the client retries registration.

10.4. Beacon Forwarding (Repeater → Client)
-------------------------------------------

When the Repeater receives a ``CA_PROTO_RSRV_IS_UP`` from any
server, it forwards the beacon to each registered client by
re-emitting it to the client's registered ``(IP, port)`` tuple.

If a forwarded beacon arrives at the Repeater with
``m_available == 0`` (a pre-V4.6 server that did not include its
own IPv4 address), the Repeater MUST set ``m_available`` to the
beacon datagram's source IPv4 address before forwarding, so that
clients always receive a beacon with a populated ``m_available``
field regardless of server version.

Apart from this single substitution, beacons are forwarded
unmodified. The client cannot otherwise distinguish a
Repeater-forwarded beacon from a direct-from-server beacon; both
arrive at the client's UDP socket as ``CA_PROTO_RSRV_IS_UP``
messages.

----

11. Flow Control
================

11.1. Subscription Flow Control
-------------------------------

A client overwhelmed by subscription updates can pause server
emission via ``CA_PROTO_EVENTS_OFF`` (command 8) and resume via
``CA_PROTO_EVENTS_ON`` (command 9):

.. table:: CA_PROTO_EVENTS_OFF / CA_PROTO_EVENTS_ON
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 8 or 9                                       |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_count``     | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_available`` | 0                                            |
   +-----------------+----------------------------------------------+

These commands apply to the entire TCP connection: ALL subscriptions
on the connection are paused or resumed together. The server, on
receiving ``EVENTS_OFF``, MUST stop emitting subscription updates
within an implementation-defined window; subsequent value changes
are coalesced at the server until ``EVENTS_ON`` is received.

When subscription updates cannot be sent (either because the
connection is in ``EVENTS_OFF`` mode or because the server's
per-subscription event queue is approaching its capacity limit), a
new value for a given subscription MUST replace the most recent
queued value for that same subscription rather than displacing
older queue entries from other subscriptions. The result is
**value coalescing**: only the latest value for each subscription
is preserved, but no subscription is starved by another. The
exact queue depth, queue-pressure threshold, and coalescing trigger
are implementation-defined.

11.2. TCP-Level Flow Control
----------------------------

CA relies on TCP's native flow control (windowing) for back-pressure:
a slow receiver causes the sender's TCP send buffer to fill, which
blocks the application's ``send()`` calls. Implementations SHOULD
configure TCP send and receive buffers (e.g. via ``setsockopt`` of
``SO_SNDBUF`` / ``SO_RCVBUF``) to values appropriate for the
expected throughput. The exact buffer sizes are
implementation-defined.

A server MUST NOT drop a TCP connection due to slow client receive;
it MUST either tolerate the back-pressure or use ``CA_PROTO_EVENTS_OFF``
self-imposed (servers do this in some implementations to prevent
self-DoS when one slow client would block all subscription
processing).

11.3. Connection Liveness (CA_PROTO_ECHO, V4.3+)
------------------------------------------------

V4.3 introduced ``CA_PROTO_ECHO`` (command 23), a request-response
keepalive:

.. table:: CA_PROTO_ECHO
   :widths: auto

   +-----------------+----------------------------------------------+
   | Field           | Value                                        |
   +=================+==============================================+
   | ``m_cmmd``      | 23                                           |
   +-----------------+----------------------------------------------+
   | ``m_postsize``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_dataType``  | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_count``     | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_cid``       | 0                                            |
   +-----------------+----------------------------------------------+
   | ``m_available`` | 0                                            |
   +-----------------+----------------------------------------------+

The receiver echoes the message verbatim. A client that has not
received any traffic from a server within a configured timeout
SHOULD send ECHO and expect a reply within an implementation-defined
window; failure to receive a reply within ``EPICS_CA_CONN_TMO``
(default 30 s) MUST be treated as connection loss
(``ECA_UNRESPTMO``).

11.4. Priority Dispatch (V4.9+)
-------------------------------

V4.9 introduced per-priority TCP connections. A V4.9+ client MAY open
multiple TCP connections to the same server, each tagged with a
distinct priority value (``CA_PROTO_PRIORITY_MIN..MAX``, 0..99) in
the ``CA_PROTO_VERSION`` ``m_dataType`` field at connection
establishment.

A V4.9+ server MUST maintain separate processing queues per
priority. Numerically larger priority values denote higher priority:
99 is the highest priority and 0 is the lowest. Servers MUST
process queued requests in priority order, draining higher-priority
queues before lower-priority queues; servers MAY use additional
fairness mechanisms (e.g. weighted round-robin between priorities)
provided the strict-priority ordering is preserved at any
contention point.

A client SHOULD use priority dispatch only for genuinely
priority-sensitive traffic; opening 100 connections per server is
discouraged and resource-prohibitive at scale.

11.5. Internal-Use Command CA_PROTO_SIGNAL
------------------------------------------

``CA_PROTO_SIGNAL`` (command 25) is reserved for server-internal
use (waking the server's I/O thread) and MUST NOT appear on the
wire. A receiver of any command value not recognised by this
specification (including ``CA_PROTO_SIGNAL`` arriving from a peer)
SHOULD log the malformed message and close the TCP connection;
the application observes this as a normal disconnect
(``ECA_DISCONN``).

----

12. Error Handling and Status Codes
====================================

12.1. CA_PROTO_ERROR Message
----------------------------

When a server cannot satisfy a request (other than the structured
failures already covered: ``CA_PROTO_NOT_FOUND``,
``CA_PROTO_CREATE_CH_FAIL``, ``CA_PROTO_SERVER_DISCONN``), it
responds with ``CA_PROTO_ERROR`` (command 11):

.. table:: CA_PROTO_ERROR
   :widths: auto

   +-----------------+--------------------------------------------------+
   | Field           | Value                                            |
   +=================+==================================================+
   | ``m_cmmd``      | 11                                               |
   +-----------------+--------------------------------------------------+
   | ``m_postsize``  | length of payload (header copy + diag string +   |
   |                 | NUL terminator); maximum payload is 512 octets   |
   +-----------------+--------------------------------------------------+
   | ``m_dataType``  | 0                                                |
   +-----------------+--------------------------------------------------+
   | ``m_count``     | 0                                                |
   +-----------------+--------------------------------------------------+
   | ``m_cid``       | client CID of the failed channel, or             |
   |                 | ``0xFFFFFFFF`` if the failing request is not     |
   |                 | bound to a channel (e.g. ``CA_PROTO_EVENTS_ON``  |
   |                 | / ``EVENTS_OFF``); for ``CA_PROTO_SEARCH``,      |
   |                 | the failing request's ``m_cid`` is echoed        |
   +-----------------+--------------------------------------------------+
   | ``m_available`` | CA status code (Section 12.2)                    |
   +-----------------+--------------------------------------------------+
   | Payload         | A copy of the failing request's header (16       |
   |                 | octets standard, 24 octets extended-header       |
   |                 | form per Section 4.3 when the original used      |
   |                 | extended header), followed by a NUL-terminated   |
   |                 | ASCII diagnostic string                          |
   +-----------------+--------------------------------------------------+

The leading payload octets are a verbatim copy of the failing
request's ``caHdr`` (or ``caHdrLargeArray`` for V4.9 extended-header
requests). This allows the client to identify which request the
error pertains to: in particular, the copied ``m_available`` field
carries the IOID for the read/write/event-add commands (Sections 7,
8) and the original CID for SEARCH.

The trailing ASCII string is human-readable and SHOULD be logged but
MUST NOT be parsed for programmatic decisions; clients dispatch on
the status code in this message's ``m_available``.

12.2. Status Code Table
-----------------------

The complete set of CA status codes. Codes marked "defunct" are
reserved (current servers do not return them, but older servers
might).

.. table:: CA status codes
   :widths: auto

   +----+----------------------+-----------+----------------------------------------+
   | #  | Symbol               | Severity  | Meaning                                |
   +====+======================+===========+========================================+
   | 0  | ``ECA_NORMAL``       | SUCCESS   | Normal successful completion           |
   +----+----------------------+-----------+----------------------------------------+
   | 1  | ``ECA_MAXIOC``       | ERROR     | Max IOC connections (defunct)          |
   +----+----------------------+-----------+----------------------------------------+
   | 2  | ``ECA_UKNHOST``      | ERROR     | Unknown internet host (defunct)        |
   +----+----------------------+-----------+----------------------------------------+
   | 3  | ``ECA_UKNSERV``      | ERROR     | Unknown internet service (defunct)     |
   +----+----------------------+-----------+----------------------------------------+
   | 4  | ``ECA_SOCK``         | ERROR     | Cannot allocate socket (defunct)       |
   +----+----------------------+-----------+----------------------------------------+
   | 5  | ``ECA_CONN``         | WARNING   | Cannot connect (defunct)               |
   +----+----------------------+-----------+----------------------------------------+
   | 6  | ``ECA_ALLOCMEM``     | WARNING   | Cannot allocate memory                 |
   +----+----------------------+-----------+----------------------------------------+
   | 7  | ``ECA_UKNCHAN``      | WARNING   | Unknown channel (defunct)              |
   +----+----------------------+-----------+----------------------------------------+
   | 8  | ``ECA_UKNFIELD``     | WARNING   | Unknown record field (defunct)         |
   +----+----------------------+-----------+----------------------------------------+
   | 9  | ``ECA_TOLARGE``      | WARNING   | Transfer exceeds limit                 |
   +----+----------------------+-----------+----------------------------------------+
   | 10 | ``ECA_TIMEOUT``      | WARNING   | I/O timeout                            |
   +----+----------------------+-----------+----------------------------------------+
   | 11 | ``ECA_NOSUPPORT``    | WARNING   | Feature not supported (defunct)        |
   +----+----------------------+-----------+----------------------------------------+
   | 12 | ``ECA_STRTOBIG``     | WARNING   | String too large (defunct)             |
   +----+----------------------+-----------+----------------------------------------+
   | 13 | ``ECA_DISCONNCHID``  | ERROR     | Channel disconnected (defunct)         |
   +----+----------------------+-----------+----------------------------------------+
   | 14 | ``ECA_BADTYPE``      | ERROR     | Invalid data type                      |
   +----+----------------------+-----------+----------------------------------------+
   | 15 | ``ECA_CHIDNOTFND``   | INFO      | Channel not found (defunct)            |
   +----+----------------------+-----------+----------------------------------------+
   | 16 | ``ECA_CHIDRETRY``    | INFO      | Retry channel lookup (defunct)         |
   +----+----------------------+-----------+----------------------------------------+
   | 17 | ``ECA_INTERNAL``     | FATAL     | Internal failure                       |
   +----+----------------------+-----------+----------------------------------------+
   | 18 | ``ECA_DBLCLFAIL``    | WARNING   | Database operation failed (defunct)    |
   +----+----------------------+-----------+----------------------------------------+
   | 19 | ``ECA_GETFAIL``      | WARNING   | Channel read failed                    |
   +----+----------------------+-----------+----------------------------------------+
   | 20 | ``ECA_PUTFAIL``      | WARNING   | Channel write failed                   |
   +----+----------------------+-----------+----------------------------------------+
   | 21 | ``ECA_ADDFAIL``      | WARNING   | Subscription add failed (defunct)      |
   +----+----------------------+-----------+----------------------------------------+
   | 22 | ``ECA_BADCOUNT``     | WARNING   | Invalid element count                  |
   +----+----------------------+-----------+----------------------------------------+
   | 23 | ``ECA_BADSTR``       | ERROR     | Invalid string                         |
   +----+----------------------+-----------+----------------------------------------+
   | 24 | ``ECA_DISCONN``      | WARNING   | Virtual circuit disconnect             |
   +----+----------------------+-----------+----------------------------------------+
   | 25 | ``ECA_DBLCHNL``      | WARNING   | Identical PV on multiple servers       |
   +----+----------------------+-----------+----------------------------------------+
   | 26 | ``ECA_EVDISALLOW``   | ERROR     | Operation not allowed in callback      |
   +----+----------------------+-----------+----------------------------------------+
   | 27 | ``ECA_BUILDGET``     | WARNING   | Build-get failed (defunct)             |
   +----+----------------------+-----------+----------------------------------------+
   | 28 | ``ECA_NEEDSFP``      | WARNING   | vxWorks FP option needed (defunct)     |
   +----+----------------------+-----------+----------------------------------------+
   | 29 | ``ECA_OVEVFAIL``     | WARNING   | Event queue overflow (defunct)         |
   +----+----------------------+-----------+----------------------------------------+
   | 30 | ``ECA_BADMONID``     | ERROR     | Invalid subscription ID                |
   +----+----------------------+-----------+----------------------------------------+
   | 31 | ``ECA_NEWADDR``      | WARNING   | New network address (defunct)          |
   +----+----------------------+-----------+----------------------------------------+
   | 32 | ``ECA_NEWCONN``      | INFO      | Resumed connection (defunct)           |
   +----+----------------------+-----------+----------------------------------------+
   | 33 | ``ECA_NOCACTX``      | WARNING   | Task not in CA context (defunct)       |
   +----+----------------------+-----------+----------------------------------------+
   | 34 | ``ECA_DEFUNCT``      | FATAL     | Defunct feature (defunct)              |
   +----+----------------------+-----------+----------------------------------------+
   | 35 | ``ECA_EMPTYSTR``     | WARNING   | Empty string (defunct)                 |
   +----+----------------------+-----------+----------------------------------------+
   | 36 | ``ECA_NOREPEATER``   | WARNING   | No repeater available (defunct)        |
   +----+----------------------+-----------+----------------------------------------+
   | 37 | ``ECA_NOCHANMSG``    | WARNING   | No matching channel for reply (def.)   |
   +----+----------------------+-----------+----------------------------------------+
   | 38 | ``ECA_DLCKREST``     | WARNING   | Dead-connection reset (defunct)        |
   +----+----------------------+-----------+----------------------------------------+
   | 39 | ``ECA_SERVBEHIND``   | WARNING   | Server fallen behind (defunct)         |
   +----+----------------------+-----------+----------------------------------------+
   | 40 | ``ECA_NOCAST``       | WARNING   | No broadcast interface (defunct)       |
   +----+----------------------+-----------+----------------------------------------+
   | 41 | ``ECA_BADMASK``      | ERROR     | Invalid event-select mask              |
   +----+----------------------+-----------+----------------------------------------+
   | 42 | ``ECA_IODONE``       | INFO      | I/O completed                          |
   +----+----------------------+-----------+----------------------------------------+
   | 43 | ``ECA_IOINPROGRESS`` | INFO      | I/O in progress                        |
   +----+----------------------+-----------+----------------------------------------+
   | 44 | ``ECA_BADSYNCGRP``   | ERROR     | Invalid sync-group ID                  |
   +----+----------------------+-----------+----------------------------------------+
   | 45 | ``ECA_PUTCBINPROG``  | ERROR     | Put callback timeout                   |
   +----+----------------------+-----------+----------------------------------------+
   | 46 | ``ECA_NORDACCESS``   | WARNING   | Read access denied                     |
   +----+----------------------+-----------+----------------------------------------+
   | 47 | ``ECA_NOWTACCESS``   | WARNING   | Write access denied                    |
   +----+----------------------+-----------+----------------------------------------+
   | 48 | ``ECA_ANACHRONISM``  | ERROR     | Feature no longer supported            |
   +----+----------------------+-----------+----------------------------------------+
   | 49 | ``ECA_NOSEARCHADDR`` | WARNING   | Empty search address list              |
   +----+----------------------+-----------+----------------------------------------+
   | 50 | ``ECA_NOCONVERT``    | WARNING   | No data conversion possible            |
   +----+----------------------+-----------+----------------------------------------+
   | 51 | ``ECA_BADCHID``      | ERROR     | Invalid channel ID                     |
   +----+----------------------+-----------+----------------------------------------+
   | 52 | ``ECA_BADFUNCPTR``   | ERROR     | Invalid function pointer               |
   +----+----------------------+-----------+----------------------------------------+
   | 53 | ``ECA_ISATTACHED``   | WARNING   | Already attached to context            |
   +----+----------------------+-----------+----------------------------------------+
   | 54 | ``ECA_UNAVAILINSERV``| WARNING   | Not available in service               |
   +----+----------------------+-----------+----------------------------------------+
   | 55 | ``ECA_CHANDESTROY``  | WARNING   | User destroyed channel                 |
   +----+----------------------+-----------+----------------------------------------+
   | 56 | ``ECA_BADPRIORITY``  | ERROR     | Invalid priority value                 |
   +----+----------------------+-----------+----------------------------------------+
   | 57 | ``ECA_NOTTHREADED``  | ERROR     | Preemptive callback not enabled        |
   +----+----------------------+-----------+----------------------------------------+
   | 58 | ``ECA_16KARRAYCLIENT`` | WARNING | Client lacks 16K-array support         |
   +----+----------------------+-----------+----------------------------------------+
   | 59 | ``ECA_CONNSEQTMO``   | WARNING   | Connection sequence aborted            |
   +----+----------------------+-----------+----------------------------------------+
   | 60 | ``ECA_UNRESPTMO``    | WARNING   | Virtual circuit unresponsive           |
   +----+----------------------+-----------+----------------------------------------+

12.3. Status Code Encoding
--------------------------

CA status codes encode three subfields: a message number, a
severity, and a level. The bit layout is:

::

    bits 0..2  : severity (0..7)
    bits 3..15 : message number (0..8191)

A receiver decodes via ``CA_EXTRACT_MSG_NO(code)`` and
``CA_EXTRACT_SEVERITY(code)``. The severity values are:

- ``CA_K_WARNING (0)`` — warning, operation MAY be retried
- ``CA_K_SUCCESS (1)`` — successful operation
- ``CA_K_ERROR (2)`` — error, operation has failed
- ``CA_K_INFO (3)`` — informational
- ``CA_K_SEVERE (4)`` — fatal, do not retry
- ``CA_K_FATAL = CA_K_ERROR | CA_K_SEVERE = 6`` — fatal

A receiver MUST treat all severity values it does not recognize as
``CA_K_ERROR`` (conservative-failure).

12.4. Mapping Common Failure Conditions
---------------------------------------

.. table:: Common error mappings
   :widths: auto

   +--------------------------------+-------------------------+
   | Condition                      | Status code             |
   +================================+=========================+
   | TCP connection lost            | ``ECA_DISCONN``         |
   +--------------------------------+-------------------------+
   | TCP unresponsive (echo timeout)| ``ECA_UNRESPTMO``       |
   +--------------------------------+-------------------------+
   | Connection setup timeout       | ``ECA_CONNSEQTMO``      |
   +--------------------------------+-------------------------+
   | Out-of-memory at server        | ``ECA_ALLOCMEM``        |
   +--------------------------------+-------------------------+
   | Invalid DBR type               | ``ECA_BADTYPE``         |
   +--------------------------------+-------------------------+
   | Invalid element count          | ``ECA_BADCOUNT``        |
   +--------------------------------+-------------------------+
   | Read access denied             | ``ECA_NORDACCESS``      |
   +--------------------------------+-------------------------+
   | Write access denied            | ``ECA_NOWTACCESS``      |
   +--------------------------------+-------------------------+
   | DBR conversion impossible      | ``ECA_NOCONVERT``       |
   +--------------------------------+-------------------------+
   | Invalid event-select mask      | ``ECA_BADMASK``         |
   +--------------------------------+-------------------------+
   | Two servers claim same PV name | ``ECA_DBLCHNL``         |
   +--------------------------------+-------------------------+
   | Server-detected internal bug   | ``ECA_INTERNAL``        |
   +--------------------------------+-------------------------+

----

13. Version Negotiation and Extensions
======================================

13.1. Major Version
-------------------

The CA major protocol revision is **4**, fixed for the entire CA
specification covered by this document. The major revision is
encoded into the default port numbers (Section 3.2):

::

    CA_PORT_BASE     = IPPORT_USERRESERVED + 56 = 5000 + 56 = 5056
    CA_SERVER_PORT   = CA_PORT_BASE + major * 2     = 5056 +  8 = 5064
    CA_REPEATER_PORT = CA_PORT_BASE + major * 2 + 1 = 5056 +  9 = 5065

A future major revision (CA 5, hypothetically) would shift the
default ports by +2; clients and servers of different major
revisions cannot interoperate at all.

13.2. Minor Version Exchange
----------------------------

The minor revision is exchanged at TCP connection establishment via
``CA_PROTO_VERSION`` (Section 5.2). Both peers MUST send
``CA_PROTO_VERSION`` as the first message; the message's ``m_count``
field carries the minor version.

The effective minor version for the connection is
``min(client_minor, server_minor)``. Both peers SHOULD downgrade
their feature usage to this effective version's capabilities.

For UDP messages, the minor version is conveyed in the
``CA_PROTO_VERSION`` message that V4.11+ servers prefix to each
emitted UDP datagram (with the sequence-number marker; see
Section 6.5).

13.3. Minor Version Feature Flags
---------------------------------

.. table:: Minor-version feature flags
   :widths: auto

   +-------+----------+--------------------------------------------------+
   | Macro | First in | Feature added                                    |
   +=======+==========+==================================================+
   | V4.0  | 4.0      | Initial CA 4 release                             |
   +-------+----------+--------------------------------------------------+
   | V4.1  | 4.1      | ``CA_PROTO_CLIENT_NAME``,                        |
   |       |          | ``CA_PROTO_HOST_NAME``,                          |
   |       |          | ``CA_PROTO_NOT_FOUND`` (Section 5.3, 6.3)        |
   +-------+----------+--------------------------------------------------+
   | V4.2  | 4.2      | ``CA_PROTO_ACCESS_RIGHTS`` async push            |
   |       |          | (Section 7.4)                                    |
   +-------+----------+--------------------------------------------------+
   | V4.3  | 4.3      | ``CA_PROTO_ECHO`` connection liveness            |
   |       |          | (Section 11.3)                                   |
   +-------+----------+--------------------------------------------------+
   | V4.4  | 4.4      | Client-supported version in                      |
   |       |          | ``CA_PROTO_CREATE_CHAN`` ``m_available``         |
   |       |          | (Section 5.4)                                    |
   +-------+----------+--------------------------------------------------+
   | V4.5  | 4.5      | (reserved)                                       |
   +-------+----------+--------------------------------------------------+
   | V4.6  | 4.6      | Server populates beacon ``m_available`` with     |
   |       |          | own IPv4 (Section 9.1); pre-V4.6 senders emit    |
   |       |          | ``m_available = 0``                              |
   +-------+----------+--------------------------------------------------+
   | V4.7  | 4.7      | (reserved)                                       |
   +-------+----------+--------------------------------------------------+
   | V4.8  | 4.8      | (reserved)                                       |
   +-------+----------+--------------------------------------------------+
   | V4.9  | 4.9      | Large arrays (extended header, Section 4.3),     |
   |       |          | priority dispatch (Section 11.4)                 |
   +-------+----------+--------------------------------------------------+
   | V4.10 | 4.10     | Beacon counter (Section 9.2),                    |
   |       |          | ``DBE_PROPERTY`` event mask (Section 8.3.1)      |
   +-------+----------+--------------------------------------------------+
   | V4.11 | 4.11     | UDP sequence numbers (Section 6.5)               |
   +-------+----------+--------------------------------------------------+
   | V4.12 | 4.12     | TCP-based search (Section 6.7)                   |
   +-------+----------+--------------------------------------------------+
   | V4.13 | 4.13     | Zero-length array support (Section 8.5)          |
   +-------+----------+--------------------------------------------------+

13.4. Backward and Forward Compatibility
----------------------------------------

The protocol uses graceful degradation:

- A V4.X client communicating with a V4.Y server (X ≤ Y) MUST behave
  as a V4.X client; V4.Y server MUST tolerate this.
- A V4.X client communicating with a V4.Y server (X > Y) MUST
  downgrade its feature usage to V4.Y. Specifically: do not use
  extended headers (V4.9), do not use TCP search (V4.12), do not
  rely on sequence numbers (V4.11), do not use beacon counters
  (V4.10) for miss detection.
- A V4.X server MUST accept connections from V4.Y clients (any Y)
  and downgrade per the same rule.

13.5. Forbidden Forward Extensions
----------------------------------

A protocol implementation MUST NOT:

- Define new ``m_cmmd`` values within an existing minor version.
  New commands require a new minor-version increment.
- Repurpose existing fields' meanings.
- Change the ``caHdr`` field layout.

If a future change requires breaking any of the above, it requires
a new major-revision increment (CA 5+) and a new default port.

----

14. Backward Compatibility
==========================

14.1. Minimum Supported Version
-------------------------------

The minimum supported minor version is 4. Implementations of this
specification MUST NOT interoperate with peers reporting minor
version less than 4 in ``CA_PROTO_VERSION``. A peer reporting
minor version 0..3 MUST be treated as malformed:

- Clients MUST close the TCP connection.
- Servers MUST respond with ``CA_PROTO_ERROR (ECA_DEFUNCT)`` and
  close the connection.

14.2. Adding New Minor-Version Features
---------------------------------------

The CA protocol design allows minor versions to add features without
breaking older peers. New features MUST follow these rules:

- **Additive only**. A new feature MAY define a new ``m_cmmd``
  value, a new ``mon_info`` mask bit, or new content in an existing
  field's reserved area.
- **No reuse**. A new feature MUST NOT reinterpret an existing field's
  meaning at any older minor version.
- **Default behavior**. Receipt of any ``m_cmmd`` value not recognised
  by the receiver's implementation of this specification SHOULD be
  logged and SHOULD cause the TCP connection to be closed. Clients
  observe such closures as ``ECA_DISCONN`` (Section 12.2). A
  receiver MAY instead silently ignore the unknown command if it has
  reason to believe the sender's minor version is higher than its
  own (graceful forward-compat); this behavior is implementation-
  defined and not required.

14.3. Deprecated Commands
-------------------------

The following commands are deprecated and MUST NOT be sent by new
implementations. Receivers MAY accept them silently (treating them
as no-ops) for backward compatibility with pre-V4.0 senders, or
MAY respond with ``CA_PROTO_ERROR`` carrying ``ECA_ANACHRONISM``:

.. table:: Deprecated CA commands
   :widths: auto

   +----+--------------------------+--------------------------------+
   | #  | Symbol                   | Replacement                    |
   +====+==========================+================================+
   | 5  | ``CA_PROTO_SNAPSHOT``    | (no replacement; never used)   |
   +----+--------------------------+--------------------------------+
   | 7  | ``CA_PROTO_BUILD``       | ``CA_PROTO_CREATE_CHAN``       |
   +----+--------------------------+--------------------------------+
   | 16 | ``CA_PROTO_READ_BUILD``  | ``CA_PROTO_READ_NOTIFY``       |
   +----+--------------------------+--------------------------------+

Pre-V4.0 servers that emit these commands SHOULD be considered
defunct; client implementations SHOULD log a warning and close the
connection.

14.4. Removed Features
----------------------

The following features were specified in earlier drafts of CA but
have been removed; receivers MUST treat them as protocol errors:

- The ``m_lval``, ``m_hval``, ``m_toval`` fields of ``mon_info``
  (Section 8.3.1) are deprecated and ignored. New implementations
  MUST set them to ``0.0f`` and MUST NOT rely on receivers honoring
  any non-zero value.
- The status code ``ECA_NEEDSFP`` (vxWorks-specific FP-task option
  check) is marked defunct in the status table (Section 12.2). No
  current server returns it; receivers handle it via the generic
  unknown-status-code rule (treat unknown severities as
  ``CA_K_ERROR``; Section 12.3).

----

15. Security Considerations
============================

15.1. CA Provides No Authentication
-----------------------------------

CA carries client identity in ``CA_PROTO_CLIENT_NAME`` and
``CA_PROTO_HOST_NAME`` (Section 5.3) as plaintext ASCII strings
chosen by the client. There is no cryptographic verification of the
declared identity. Servers MUST treat these strings as advisory
metadata only — useful for logging, audit trails, and access-security
policy lookups — but MUST NOT rely on them as a security boundary.

A malicious or buggy client can spoof any user name and any host
name. Server administrators relying on the EPICS access security
file (ASG/ACF) for access control MUST understand that ASG/ACF on
top of plain CA is enforcement-by-cooperation: a determined attacker
on the network can supply any identity and obtain access permitted
to that identity.

15.2. CA Provides No Confidentiality
------------------------------------

CA traffic is plaintext over UDP and TCP. All channel names, all
read responses, all write payloads, and all subscription updates
travel unencrypted. Sites carrying sensitive process data over CA
MUST treat the network itself as a security domain (private VLANs,
dedicated subnets, physical isolation).

15.3. CA Provides Limited Integrity
-----------------------------------

CA relies on TCP and UDP checksums for integrity. There is no
cryptographic message authentication code; an active on-path attacker
can modify CA packets in flight.

15.4. Denial of Service
-----------------------

A CA server is vulnerable to DoS by:

- Flooding the UDP search port with bogus searches.
- Opening many TCP connections and exhausting server resources.
- Issuing very large array reads or large monitor subscriptions.

The protocol does not specify rate limits, connection caps, or
resource quotas; implementations SHOULD provide configurable limits
and SHOULD log unusual access patterns.

15.5. When to Use SPVA Instead
------------------------------

Sites requiring any of the following SHALL use Secure PVAccess
(:doc:`/protocol-spec/spva`) instead of CA:

- Cryptographic authentication of clients (X.509 client certificates).
- Confidentiality of channel data on the wire (TLS 1.3 transport).
- Integrity of channel data against active attackers (TLS 1.3 MAC).
- Per-channel authorization tied to verified identity (SPVA
  authorization extensions).

CA's threat model assumes a trusted local network; SPVA's threat
model assumes a hostile network and provides cryptographic protection
against on-path attackers.

----

16. IANA Considerations
=======================

16.1. Port Assignments
----------------------

The default CA port numbers are NOT IANA-registered. They are
derived from the fixed formula given in Section 3.2, which places
them in the IANA user-reserved range:

- TCP port 5064 (CA server)
- UDP port 5064 (CA search, CA beacon)
- UDP port 5065 (CA repeater)

Independent IANA registration of these ports SHOULD be coordinated
through the EPICS community to prevent conflicting registration
attempts; the formula-derived default is sufficient for internal
facility use, and the environment-variable override
(``EPICS_CA_SERVER_PORT`` / ``EPICS_CA_REPEATER_PORT``)
accommodates the case where the default ports collide with
site-specific applications.

16.2. Protocol Number
---------------------

CA does not define a custom IP protocol number; it uses standard TCP
(IP protocol 6) and UDP (IP protocol 17).

16.3. URL Scheme
----------------

CA does not define a URL scheme. Clients identify PVs by name, not
URL; the binding from PV name to ``(server, port)`` is performed by
the search mechanism (Section 6) at runtime.

----

17. References
==============

17.1. Normative References
--------------------------

- **RFC 2119** — Bradner, S., "Key words for use in RFCs to Indicate
  Requirement Levels", BCP 14, :rfc:`2119`, March 1997.
- **RFC 8174** — Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC
  2119 Key Words", BCP 14, :rfc:`8174`, May 2017.

17.2. Informative References
----------------------------

- **Channel Access Reference Manual** — Hill, J. O., Paul Scherrer
  Institute / Los Alamos National Laboratory, historical document,
  various editions. Earlier informal description of the protocol;
  consulted in preparing this specification.
- **EPICS Base implementation** — https://github.com/epics-base/epics-base.
  Consulted in preparing this specification; in particular the
  files ``modules/ca/src/client/caProto.h`` and
  ``modules/ca/src/client/caerr.h``, plus the surrounding C++
  client and ``rsrv`` server source.
- :doc:`/protocol-spec/pva` — PVAccess Protocol Specification.
- :doc:`/protocol-spec/spva` — Secure PVAccess Protocol Specification.

----

Authors' Addresses
==================

This specification is maintained by the slac-epics organization at
https://github.com/slac-epics/pvxs-docs. Issues and proposed
clarifications should be filed there.

The protocol described herein was designed by Jeffrey O. Hill
(Los Alamos National Laboratory). Attribution for the protocol
design itself is to him; this document is a description, not the
design.
