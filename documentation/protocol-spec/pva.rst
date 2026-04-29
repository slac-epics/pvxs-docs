.. _pva_protocol_spec:

======================================
PVAccess (PVA) Protocol Specification
======================================

:Status: Draft
:Protocol Version: 2 (this document specifies PVA wire-protocol version 2)
:Default Server Port: 5075 (TCP)
:Default Broadcast Port: 5076 (UDP)

.. note::

   This document is the normative specification of the PVAccess
   wire protocol. Implementations conform to this specification.
   Where an implementation's behavior differs from this
   specification, the implementation is in error and the
   specification is authoritative.

   Three independent implementations of the protocol exist and
   were consulted in the preparation of this specification:

   - **pvxs** — modern C++ client/server library
     (https://github.com/mdavidsaver/pvxs upstream;
     https://github.com/slac-epics/pvxs in the slac-epics fork).
   - **pvAccessCPP** — original C++ reference implementation,
     integrated into EPICS Base 7 as ``modules/pvAccess``.
   - **core-pva** — independent Java client/server implementation,
     part of phoebus (``phoebus/core/pva``).

   These three implementations are listed under Informative
   References (Section 19.2); they have no normative weight. None
   of them is the protocol's "canonical implementation" — the spec
   is.

Abstract
========

The PVAccess (PVA) protocol is the EPICS 7 successor to Channel
Access (CA, :doc:`/protocol-spec/ca`). Where CA carries a fixed set of
typed scalars and arrays, PVA carries arbitrary structured values
(PVData) — the structure of each value is itself part of the
exchange. PVA defines a connection-validation handshake, a name-
resolution mechanism that allows multiple servers to share a UDP
broadcast group, a richer set of operations (get / put / put-get /
monitor / RPC / introspect) and a 23-command wire format with
explicit segmentation and per-message byte-order declaration. This
document specifies PVA wire-protocol version 2 as implemented in
pvxs.

Status of This Document
=======================

This document is a wire-protocol specification. It describes the
bytes that travel between a PVA client and a PVA server, the order
in which they are exchanged, and the meaning of each field. It does
not describe the pvxs C++ API, the pvxs IOC integration, the P4P
Python bindings, or any client application; those are covered
separately in :doc:`/programmers-ref/index`.

This document covers PVA wire-protocol version 2. Pre-existing
implementations of PVA — notably pvxs and the
``epics-base/modules/pvAccess`` C++ reference implementation —
were consulted in preparing this specification (see Section 19.2);
the specification's authority derives from this document, not from
those implementations.

Conventions Used in This Document
=================================

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in :rfc:`2119` and
:rfc:`8174`.

Unlike CA, PVA messages declare their byte order **per-message** in
the header flags byte (Section 4.2). Senders MAY choose either
byte order on a per-message basis; receivers MUST honor the byte
order declared in the message header.

Notation:

- ``u8``, ``u16``, ``u32``, ``u64`` denote unsigned integers of 8,
  16, 32, and 64 bits.
- ``i8``, ``i16``, ``i32``, ``i64`` denote signed two's-complement
  integers.
- ``f32``, ``f64`` denote IEEE 754 single- and double-precision
  floats.
- ``Size`` denotes a variable-length size encoding (Section 5.1.1).
- ``String`` denotes a UTF-8 string with ``Size`` length prefix
  (Section 5.1.2).
- Brackets ``[ ... ]`` enclose a struct field list with explicit
  offsets.
- The phrase **the protocol** refers throughout this document to
  PVA wire-protocol version 2.

Table of Contents
=================

1. Introduction
2. Protocol Overview
3. Transport Layer
4. Common Message Format
5. PVData Type System and Wire Encoding
6. Connection Validation
7. Name Resolution and Search
8. Channel Lifecycle
9. Operations on a Connected Channel
10. Beacons and Server Announcement
11. Segmentation and Large Messages
12. Flow Control and Liveness
13. ACL Change Notification
14. Origin Tagging
15. Error Handling and Status
16. Version Negotiation
17. Security Considerations
18. IANA Considerations
19. References

----

1. Introduction
===============

1.1. Purpose
------------

The PVAccess protocol enables a client process to access named
process variables hosted by a server process, with three additions
beyond CA's capabilities:

- **Structured values** — a PV's value is an arbitrarily-nested
  structure of named, typed fields (the PVData type system), not
  just a typed scalar or array.
- **Introspection** — a client can fetch a PV's type description
  (its "type ID") without fetching the value, enabling generic
  tooling that adapts to whatever structure a server publishes.
- **Multiple operation styles** — get, put, put-get (atomic
  read-modify-write), monitor (subscription with structured
  delta-encoding), RPC (request-response with arbitrary
  structured payloads), introspect, process, cancel.

PVA was designed in the late 2000s by Marty Kraimer and others as
the wire protocol underlying EPICS V4, then adopted as the EPICS 7
"PVA module". A clean re-implementation, pvxs, was developed at
Brookhaven and is now maintained at SLAC (slac-epics).

1.2. Design Philosophy
----------------------

PVA inherits CA's deployment assumptions (large facility, many IOCs,
many clients, partial-trust LAN) but adds:

- **Variable-byte-order**. A sender MAY emit either little-endian or
  big-endian on every message, declared in a flag bit. This allows
  IOC software to skip byte-swapping when client and server are on
  the same architecture, the dominant case in a single facility.
- **Explicit framing**. Every message starts with a magic byte
  (0xCA) and a 4-byte explicit length field, allowing receivers to
  resync on a damaged stream and to skip messages of unknown
  command code.
- **Segmentation**. A single logical message MAY span multiple
  on-wire frames, with start/middle/end markers in the flags byte.
  This decouples the application's logical message size from the
  TCP send buffer size.
- **Type system embedded in the protocol**. A "type id" + an
  introspection block at the start of any structured exchange
  identifies the value's shape. Subsequent same-type exchanges in
  the same connection use the cached type id.
- **Search request batching**. UDP search packets carry a list of
  channel names rather than a single name, reducing UDP
  amplification when a client looks up many PVs at startup.

1.3. Scope
----------

This specification covers:

- The wire format of all PVA messages defined for protocol version
  2 (Sections 4 and the operation-specific sections).
- The PVData type system, wire encoding, and introspection
  (Section 5).
- Transport-layer behavior: TCP for operations, UDP for search and
  beacons (Section 3).
- The connection-validation handshake (Section 6).
- The state machines for the client, the server, and the per-channel
  and per-operation lifecycles (Sections 8 and 9).
- Segmentation, flow control, error handling (Sections 11–13, 15).

It does not cover:

- The pvxs C++ API, the P4P Python bindings, the pvxs IOC
  integration. Those are in :doc:`/programmers-ref/index`.
- The IOC record database, ASG/ACF, or PVAccess Group ("QSRV2")
  features.
- Any security mechanisms (authentication, encryption). PVA itself
  has no transport security; sites requiring it use Secure
  PVAccess (:doc:`/protocol-spec/spva`).

1.4. Terminology
----------------

PV (Process Variable)
   A named, externally-addressable value hosted by a server. The
   value's type is described by a **type id** + a PVData structure
   (Section 5).

Channel
   A per-connection client-side handle that refers to a PV on a
   specific server. Created by a successful ``CMD_CREATE_CHANNEL``
   exchange (Section 8); destroyed by ``CMD_DESTROY_CHANNEL`` or
   connection close.

CID (Client Channel ID)
   A 32-bit integer chosen by the client to identify a channel
   within a single connection. Echoed by the server in responses
   that pertain to a channel.

SID (Server Channel ID)
   A 32-bit integer chosen by the server in
   ``CMD_CREATE_CHANNEL`` response to identify the server's
   binding for a channel.

IOID (I/O Identifier)
   A 32-bit integer chosen by the client to identify a single
   in-flight get / put / monitor / RPC operation on a channel.
   Server echoes the IOID in its responses.

GUID (Globally-Unique Identifier)
   A 12-octet random identifier chosen by a server at startup,
   transmitted in beacons and in ``CMD_CONNECTION_VALIDATION``.
   Clients use the GUID to detect server restarts (different GUID
   value across restarts implies the same address-port now hosts
   a different server instance, even if the IP and port are
   unchanged).

Type ID
   A 16-bit integer that identifies a previously-introduced PVData
   type description on the current connection. The mapping from
   type ID to type description is per-connection and built up
   during the connection's lifetime.

Subscription (Monitor)
   A long-lived request from a client to be notified whenever a
   channel's value changes. Established by ``CMD_MONITOR`` with
   sub-command ``Init`` (Section 9.5).

Beacon
   A UDP datagram emitted periodically by a PVA server to announce
   its presence to potential clients. Specified in Section 10.

pvxs
   The reference implementation of PVA used by this specification,
   hosted at https://github.com/slac-epics/pvxs.

epics-base PVA
   The independent reference C++ implementation maintained at
   ``epics-base/modules/pvAccess``. Informative only for this
   specification.

----

2. Protocol Overview
====================

This section gives a non-normative overview of how a PVA exchange
proceeds end-to-end. Implementers MUST consult the detailed sections
for normative behavior.

2.1. Layering
-------------

Like CA, PVA runs directly over UDP and TCP with no intermediate
framing layer.

::

    +-------------------+ +-------------------+
    |   PVA Search /    | |   PVA Operations  |
    |   Beacon          | |   on a Channel    |
    +-------------------+ +-------------------+
    |        UDP        | |        TCP        |
    +-------------------+ +-------------------+
    |               IPv4 / IPv6                |
    +------------------------------------------+

UDP carries:

- Client-originated **Search** requests (Section 7) sent to the
  broadcast or unicast addresses in the client's address list.
- Server-originated **Search responses** (Section 7).
- Server-originated **Beacons** (Section 10) sent to the broadcast
  port (default 5076 UDP).

TCP carries:

- Connection-validation handshake (Section 6).
- All operations on channels — ``CMD_CREATE_CHANNEL``,
  ``CMD_GET``, ``CMD_PUT``, ``CMD_MONITOR``, ``CMD_RPC``, etc.
  (Sections 8 and 9).
- Server-pushed asynchronous notifications (e.g.
  ``CMD_ACL_CHANGE``, monitor updates).

2.2. A Typical Exchange
-----------------------

A simple end-to-end PVA exchange — connect to one PV, get its
value, disconnect — proceeds as follows:

1. **Client**: send ``CMD_SEARCH`` UDP datagram to the broadcast
   address on UDP port ``EPICS_PVA_BROADCAST_PORT`` (default 5076),
   carrying the PV name in the search list. (Section 7.1.)

2. **Server hosting the PV**: receive the ``CMD_SEARCH``, send a
   ``CMD_SEARCH_RESPONSE`` UDP unicast back to the client's source
   address and source port. The response carries the server's GUID,
   the server's TCP port, and the search ID echoed from the
   request. (Section 7.2.)

3. **Client**: open a TCP connection to the server's IP and TCP
   port from the search response.

4. **Server**: send ``CMD_CONNECTION_VALIDATION`` as the first
   message after the TCP connection is established, declaring
   the server's GUID, supported authentication mechanisms, and
   buffer sizes. (Section 6.1.)

5. **Client**: respond with ``CMD_CONNECTION_VALIDATION``
   declaring chosen authentication, requested buffer sizes, and
   client GUID. (Section 6.2.)

6. **Server**: send ``CMD_CONNECTION_VALIDATED`` with the result
   status (Section 6.3). Connection is now ready.

7. **Client**: send ``CMD_CREATE_CHANNEL`` for the PV with a
   client-chosen CID. (Section 8.1.)

8. **Server**: respond with ``CMD_CREATE_CHANNEL`` carrying the
   server-chosen SID and the channel's access permissions
   (Section 8.2). Channel is now connected.

9. **Client**: send ``CMD_GET`` with sub-command ``Init`` and a
   client-chosen IOID. (Section 9.2.1.) The Init response from
   the server returns the channel's PVData type description.

10. **Client**: send ``CMD_GET`` with sub-command ``Get``, IOID
    same as Init. (Section 9.2.2.)

11. **Server**: respond with ``CMD_GET`` carrying the value
    (encoded per the type description from step 9). (Section
    9.2.2.)

12. **Client**: send ``CMD_DESTROY_REQUEST`` to clean up the
    operation, then ``CMD_DESTROY_CHANNEL`` to release the
    channel. (Sections 9.10 and 8.3.)

13. **Client**: close the TCP connection.

Subscriptions (``CMD_MONITOR``) are similar but the server emits an
unbounded stream of update messages between Init and Destroy
sub-commands.

2.3. The Type System
--------------------

PVA's defining feature is its embedded type system. A PV's value is
not just an integer or string — it is a structured composition of
fields, each with its own type. To exchange a value, sender and
receiver must agree on its structure.

PVA achieves this by transmitting a **type description** (an FieldDesc
tree, Section 5.4) once per connection, the first time a given type
appears, and assigning that type a 16-bit **type ID**. Subsequent
exchanges of the same type cite only the type ID. Both peers maintain
a per-connection cache mapping type IDs to type descriptions.

The type description itself is a recursive encoding of typed-field
trees, supporting scalars (boolean, integers of various widths,
floats, strings), arrays of any of those, structures (named fields
each with their own type), unions (one-of), and named-type references
("normalized types" from epics-pvData; e.g. ``epics:nt/NTScalar:1.0``).

2.4. What the Protocol Does Not Do
----------------------------------

PVA does not provide:

- **Authentication or confidentiality**. Sites requiring either
  SHALL use SPVA (:doc:`/protocol-spec/spva`).
- **Repeater-style beacon redistribution** as in CA. PVA beacons
  reach clients directly via the broadcast port, not via a per-host
  forwarding daemon.
- **Reliable delivery of beacons or search packets**. Both are UDP.
  Recovery is by re-emission cadence (Section 10.3) and client-side
  search retry (Section 7.5).
- **Transactional groups**. There is no PVA-level transaction
  manager; atomic multi-channel update is an application concern.

----

3. Transport Layer
==================

3.1. Transport Protocols
------------------------

PVA uses two IP transport protocols:

- **UDP** — for ``CMD_SEARCH`` and ``CMD_SEARCH_RESPONSE`` (Section 7)
  and for ``CMD_BEACON`` (Section 10).
- **TCP** — for ``CMD_CONNECTION_VALIDATION`` and all operations on
  a connected channel.

A PVA server MUST listen on both:

- UDP at ``EPICS_PVA_BROADCAST_PORT`` (default 5076) for search
  and beacon traffic.
- TCP at ``EPICS_PVA_SERVER_PORT`` (default 5075) for client
  connections.

The two ports are independent; they are not derived from each other
by any formula (in contrast to CA where they were tied to the major
revision).

3.2. Default Port Assignments
-----------------------------

.. table:: Default PVA port assignments
   :widths: auto

   +------------------------+-------+----------------+----------------------------------+
   | Use                    | Port  | Transport      | Override                         |
   +========================+=======+================+==================================+
   | PVA server (TCP)       | 5075  | TCP            | ``EPICS_PVA_SERVER_PORT``        |
   +------------------------+-------+----------------+----------------------------------+
   | PVA search / beacons   | 5076  | UDP            | ``EPICS_PVA_BROADCAST_PORT``     |
   +------------------------+-------+----------------+----------------------------------+
   | PVA TLS server [SPVA]  | 5076  | TCP (TLS)      | ``EPICS_PVAS_TLS_PORT``          |
   +------------------------+-------+----------------+----------------------------------+

The variant ``EPICS_PVAS_*`` (with trailing 'S') is the
server-side configuration; ``EPICS_PVA_*`` (without 'S') is the
client-side configuration. Servers SHOULD honour both forms (with
``EPICS_PVAS_*`` taking precedence when both are set); clients
SHOULD honour ``EPICS_PVA_*`` and SHOULD NOT honour
``EPICS_PVAS_*`` for variables whose meaning differs between
client and server (notably the broadcast port: a client connecting
to a server on a non-default broadcast port reads
``EPICS_PVA_BROADCAST_PORT`` and ignores any
``EPICS_PVAS_BROADCAST_PORT`` value, since the latter configures
which port the local server *binds*, not which port a remote
server is listening on).

For ``EPICS_PVA_SERVER_PORT`` and ``EPICS_PVAS_SERVER_PORT`` the
two forms are usually equivalent on both sides because the variable
expresses the same TCP port number from both perspectives (a server
binding it; a client connecting to it); implementations therefore
typically honour both, with the client preferring the unsuffixed
form and the server preferring the ``-S``-suffixed form.

The TLS port (5076 TCP) collides with the UDP broadcast port; this
is intentional and works because TCP and UDP are different transport
layers with separate port spaces. SPVA uses this default; see
:doc:`/protocol-spec/spva`.

3.3. UDP Usage
--------------

3.3.1. Datagram Composition
~~~~~~~~~~~~~~~~~~~~~~~~~~~

A single UDP datagram MAY contain one or more PVA messages
concatenated. Each message is self-framing via its 8-octet header
(Section 4.1). A receiver MUST iterate through the datagram,
dispatching each message in turn.

3.3.2. UDP Buffer Sizes
~~~~~~~~~~~~~~~~~~~~~~~

Implementations SHOULD configure ``SO_RCVBUF`` to at least 65536
octets (the IPv4 maximum datagram size). pvxs uses 65536 by
default; this accommodates large search-request batches.

3.3.3. Broadcast and Multicast
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Search requests are sent to every destination in the client's
``EPICS_PVA_ADDR_LIST`` (analog to ``EPICS_CA_ADDR_LIST``) plus,
if ``EPICS_PVA_AUTO_ADDR_LIST=YES`` (default), the broadcast
addresses of all locally-bound network interfaces.

PVA additionally supports IPv4 **multicast** for search and beacons
(unlike CA, which only supports broadcast). The client MAY join a
multicast group and emit search packets to it; servers wishing to
participate in that group join it on the same port. The default
multicast configuration is implementation-defined; pvxs does not
auto-join a multicast group by default and requires explicit
configuration via ``EPICS_PVA_NAME_SERVERS``.

3.4. TCP Usage
--------------

3.4.1. Connection Establishment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

After receiving a ``CMD_SEARCH_RESPONSE``, the client opens a TCP
connection to ``(server_IP, server_TCP_port)`` from the response.
The TCP connection is established before any PVA-level handshake.

Once the TCP three-way handshake completes, the **server** initiates
the PVA handshake by sending ``CMD_CONNECTION_VALIDATION`` (Section
6). This is the OPPOSITE of CA where the client sends the version
exchange first. PVA's server-first handshake allows the server to
assert its identity (GUID + version + supported authentication
methods) before the client commits to the connection.

3.4.2. Connection Sharing
~~~~~~~~~~~~~~~~~~~~~~~~~

A single TCP connection between a given client and server SHOULD
multiplex all channels and all operations the client opens against
that server. Implementations MUST NOT open more than one TCP
connection per ``(client-process, server)`` pair under normal
conditions.

3.4.3. Message Boundaries on TCP
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A receiver MUST reassemble the byte stream into discrete PVA
messages by reading the 8-octet header (Section 4.1) and then
``Header.len`` octets of payload. Segmented messages (Section 11)
are reassembled across multiple frames before being passed to the
operation-specific handler.

3.4.4. Maximum TCP Message Size
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

There is no hard upper bound on a single PVA message size; the
4-octet length field accommodates up to 2³² − 1 octets. Practical
upper bounds are set by:

- The receiver's buffer size, declared in
  ``CMD_CONNECTION_VALIDATION`` (Section 6.1). pvxs's default is
  16384 octets per logical message, with longer messages
  segmented (Section 11).
- The configured limit ``EPICS_PVA_MAX_ARRAY_BYTES`` for the size
  of a single value payload.

A sender that exceeds the receiver's declared buffer size for a
single (non-segmented) message MUST segment the message; if
segmentation is not possible (e.g. the value cannot be split), the
sender MUST fail the operation with status ``ERROR``.

3.4.5. Connection Loss
~~~~~~~~~~~~~~~~~~~~~~

When the TCP connection is closed (either side), the client MUST
treat all channels and all in-flight operations on that connection
as failed. The server MUST release all per-connection resources.
Reconnection logic SHOULD include exponential back-off.

3.5. Address List Handling
--------------------------

Two environment variables determine search destinations:

- **``EPICS_PVA_ADDR_LIST``** — whitespace-separated list of IP
  addresses or hostnames, optional ``:port`` suffix per entry.
  Without ``:port``, ``EPICS_PVA_BROADCAST_PORT`` is used.
- **``EPICS_PVA_AUTO_ADDR_LIST``** — boolean (``YES``/``NO``,
  default ``YES``). When ``YES``, broadcast addresses of all
  locally-bound interfaces are added to the list.

A third variable is unique to PVA:

- **``EPICS_PVA_NAME_SERVERS``** — explicit list of unicast
  ``(host, TCP-port)`` PVA servers to connect to directly without
  UDP search. Useful for routed deployments where UDP is filtered.

3.6. IPv6 Considerations
------------------------

pvxs supports IPv6 transport for both UDP and TCP. Servers binding
to ``::`` (IPv6 wildcard) accept both v4 and v6 connections. The
search and beacon mechanisms work over IPv6 multicast (e.g.
``ff02::1`` link-local all-nodes); IPv6 broadcast equivalents are
multicast-based by IPv6 design. Sites deploying IPv6 SHOULD
configure ``EPICS_PVA_ADDR_LIST`` with explicit IPv6 multicast
addresses; auto-detection of IPv6 multicast groups is
implementation-defined.

----

4. Common Message Format
========================

4.1. Header
-----------

Every PVA message begins with the fixed 8-octet header:

::

    Offset  Size  Field            Value
    ------  ----  -------------    --------------------------------
       0    1     magic            0xCA  (always; receiver MUST verify)
       1    1     version          2 (this specification's version)
       2    1     flags            Bitmask (Section 4.2)
       3    1     command          Command code (Section 4.3)
       4    4     length           Payload length in octets (excludes
                                   this 8-byte header). Byte-order
                                   per the MSB flag in flags.

The version byte (offset 1) travels in every message header and
carries the protocol version of the sender. For this specification
the version byte is ``2`` for both directions of traffic; see
Section 16 for forward and backward compatibility rules.

A receiver MUST verify byte 0 == 0xCA and byte 1 != 0 and treat
any other value as a malformed message: close the TCP connection
or discard the UDP datagram. The 0xCA magic is named after the
"CA" lineage (Channel Access → Channel Access version 4 →
PVAccess, which kept the magic byte for identification of the
EPICS protocol family).

4.2. Flags Byte
---------------

The ``flags`` byte at offset 2 is a bitmask:

.. table:: PVA header flags
   :widths: auto

   +-------+--------+----------------------------------------------+
   | Bit   | Symbol | Meaning                                      |
   +=======+========+==============================================+
   | 0     | 0x01   | ``Control``: 1 = control message,            |
   |       |        | 0 = application message                      |
   +-------+--------+----------------------------------------------+
   | 1–3   |        | (unused; senders MUST set 0; receivers MUST  |
   |       |        | ignore)                                      |
   +-------+--------+----------------------------------------------+
   | 4–5   |        | Segmentation (Section 11):                   |
   |       |        | 00 = not segmented, 01 = first segment,      |
   |       |        | 11 = middle segment, 10 = last segment       |
   +-------+--------+----------------------------------------------+
   | 6     | 0x40   | ``Server``: 1 = server origin,               |
   |       |        | 0 = client origin                            |
   +-------+--------+----------------------------------------------+
   | 7     | 0x80   | ``MSB``: 1 = big-endian payload,             |
   |       |        | 0 = little-endian payload                    |
   +-------+--------+----------------------------------------------+

Receivers use bit 7 (``MSB``) to determine the byte order of the
4-octet length field at header offset 4 AND of all multi-octet
fields in the payload. A receiver's payload-decoding logic MUST
key off the per-message MSB bit; it MUST NOT assume any persistent
byte-order policy across messages.

The ``Server`` bit allows a peer to verify that the message arrived
in the expected direction. A client receiving a message with
``Server == 0`` MUST treat as malformed; a server receiving
``Server == 1`` likewise.

4.3. Command Codes
------------------

The complete set of PVA application command codes:

.. table:: PVA application command codes
   :widths: auto

   +----+--------------------------------+--------------------------------------+
   | #  | Symbol                         | Purpose                              |
   +====+================================+======================================+
   | 0  | ``CMD_BEACON``                 | Server liveness announcement         |
   +----+--------------------------------+--------------------------------------+
   | 1  | ``CMD_CONNECTION_VALIDATION``  | Authentication / capability exchange |
   +----+--------------------------------+--------------------------------------+
   | 2  | ``CMD_ECHO``                   | Connection liveness probe            |
   +----+--------------------------------+--------------------------------------+
   | 3  | ``CMD_SEARCH``                 | Channel name search request          |
   +----+--------------------------------+--------------------------------------+
   | 4  | ``CMD_SEARCH_RESPONSE``        | Search reply                         |
   +----+--------------------------------+--------------------------------------+
   | 5  | ``CMD_AUTHNZ``                 | Authentication continuation          |
   +----+--------------------------------+--------------------------------------+
   | 6  | ``CMD_ACL_CHANGE``             | Server-pushed ACL update             |
   +----+--------------------------------+--------------------------------------+
   | 7  | ``CMD_CREATE_CHANNEL``         | Open channel                         |
   +----+--------------------------------+--------------------------------------+
   | 8  | ``CMD_DESTROY_CHANNEL``        | Close channel                        |
   +----+--------------------------------+--------------------------------------+
   | 9  | ``CMD_CONNECTION_VALIDATED``   | Validation complete (status)         |
   +----+--------------------------------+--------------------------------------+
   | 10 | ``CMD_GET``                    | Get channel value                    |
   +----+--------------------------------+--------------------------------------+
   | 11 | ``CMD_PUT``                    | Put channel value                    |
   +----+--------------------------------+--------------------------------------+
   | 12 | ``CMD_PUT_GET``                | Atomic put-get                       |
   +----+--------------------------------+--------------------------------------+
   | 13 | ``CMD_MONITOR``                | Subscribe to value changes           |
   +----+--------------------------------+--------------------------------------+
   | 14 | ``CMD_ARRAY``                  | (legacy; not used in v2)             |
   +----+--------------------------------+--------------------------------------+
   | 15 | ``CMD_DESTROY_REQUEST``        | Cancel/destroy in-flight operation   |
   +----+--------------------------------+--------------------------------------+
   | 16 | ``CMD_PROCESS``                | Trigger record processing            |
   +----+--------------------------------+--------------------------------------+
   | 17 | ``CMD_GET_FIELD``              | Introspect channel type              |
   +----+--------------------------------+--------------------------------------+
   | 18 | ``CMD_MESSAGE``                | Server-side log message              |
   +----+--------------------------------+--------------------------------------+
   | 19 | ``CMD_MULTIPLE_DATA``          | (legacy; not used in v2)             |
   +----+--------------------------------+--------------------------------------+
   | 20 | ``CMD_RPC``                    | Remote procedure call                |
   +----+--------------------------------+--------------------------------------+
   | 21 | ``CMD_CANCEL_REQUEST``         | Soft-cancel operation                |
   +----+--------------------------------+--------------------------------------+
   | 22 | ``CMD_ORIGIN_TAG``             | Multicast origin tagging             |
   +----+--------------------------------+--------------------------------------+

Values 0..22 are defined; values 23..255 are reserved for future
protocol extensions and MUST be rejected by current
implementations.

4.4. Control Messages
---------------------

When the ``Control`` flag bit (0x01) is set, the message is a
control message rather than an application message. Control
messages have a separate command-code namespace:

.. table:: PVA control message codes
   :widths: auto

   +----+------------------+---------------------------------------+
   | #  | Symbol           | Purpose                               |
   +====+==================+=======================================+
   | 0  | ``SetMarker``    | Mark a flow-control point in stream   |
   +----+------------------+---------------------------------------+
   | 1  | ``AckMarker``    | Acknowledge a SetMarker               |
   +----+------------------+---------------------------------------+
   | 2  | ``SetEndian``    | Server requests client to switch      |
   |    |                  | byte-order policy for outgoing        |
   |    |                  | messages                              |
   +----+------------------+---------------------------------------+

Control messages have no payload; the 4-octet length field MUST be
0 (or carry control-specific data; ``SetEndian`` carries a single
byte indicating requested order, encoded as the MSB flag of a
following message).

4.5. Sub-Commands
-----------------

Several application commands (``CMD_GET``, ``CMD_PUT``,
``CMD_MONITOR``, ``CMD_RPC``, ``CMD_PUT_GET``) carry a
**sub-command** byte at the start of their payload:

.. table:: Operation sub-commands
   :widths: auto

   +---------+-------+------------------------------------+
   | Value   | Name  | Purpose                            |
   +=========+=======+====================================+
   | 0x08    | Init  | First request — fetch type info    |
   +---------+-------+------------------------------------+
   | 0x10    | Destroy| Tear down the operation           |
   +---------+-------+------------------------------------+
   | 0x40    | Get   | Get-style invocation               |
   +---------+-------+------------------------------------+

Other values are reserved per-command (e.g. monitor uses
sub-command bits for ``Start`` / ``Stop`` / ``Pipeline`` flow
control; see Section 9.5).

----

5. PVData Type System and Wire Encoding
========================================

5.1. Primitive Encodings
------------------------

5.1.1. Size Encoding
~~~~~~~~~~~~~~~~~~~~

The PVA "Size" type is a variable-length unsigned integer. The
encoding rules:

.. table:: Size encoding
   :widths: auto

   +---------------------+-----------------------------------------+
   | First octet         | Encoding                                |
   +=====================+=========================================+
   | 0..253              | The single octet IS the value           |
   |                     | (range 0..253).                         |
   +---------------------+-----------------------------------------+
   | 254 (0xFE)          | Followed by a 4-octet unsigned integer  |
   |                     | (per-message byte order; Section 4.2)   |
   |                     | giving the value (range 0..2³²−1).      |
   +---------------------+-----------------------------------------+
   | 255 (0xFF)          | "Null" sentinel; valid ONLY in nullable |
   |                     | contexts (see below). Outside nullable  |
   |                     | contexts, 0xFF is a protocol error.     |
   +---------------------+-----------------------------------------+

The maximum representable Size is 2³² − 1; PVA does not define a
64-bit Size form. Sites or applications requiring values larger
than 2³² − 1 octets in a single field SHALL fail the operation
locally; the protocol provides no encoding for such values.

**Null sentinel (0xFF).** A Size appearing in a *nullable* context
— principally in the PVData scalar-string encoding (Section 5.1.2),
where a string field whose schema permits a null value is encoded
either as a present empty string (Size 0 followed by zero octets)
or as null (a single 0xFF octet with no following payload) — uses
0xFF to denote null. The set of Size occurrences that are nullable
is determined by the surrounding type description (FieldDesc):
nullable contexts are limited to those explicitly defined in
Sections 5.1.2 and 5.4.

Outside a nullable context, a receiver encountering 0xFF where a
Size is expected MUST treat the message as malformed.

5.1.2. String Encoding
~~~~~~~~~~~~~~~~~~~~~~

A PVA String is a UTF-8 byte sequence prefixed by a Size. The
length is the number of UTF-8 octets, NOT the number of Unicode
code points. Strings are NOT null-terminated; the Size prefix
fully delimits them.

Empty strings are encoded as a single zero byte (Size = 0 in the
0..253 range, no payload follows).

5.2. Numeric Primitives
-----------------------

PVA numeric types are encoded directly in the per-message byte
order with no length prefix:

.. table:: PVA numeric primitives
   :widths: auto

   +-------------+-------+--------------------------------------+
   | Type        | Size  | Encoding                             |
   +=============+=======+======================================+
   | bool        | 1     | 0 = false, 1 = true; other reserved  |
   +-------------+-------+--------------------------------------+
   | i8 / u8     | 1     | Two's complement / unsigned          |
   +-------------+-------+--------------------------------------+
   | i16 / u16   | 2     | Two's complement / unsigned, BE/LE   |
   +-------------+-------+--------------------------------------+
   | i32 / u32   | 4     | Two's complement / unsigned, BE/LE   |
   +-------------+-------+--------------------------------------+
   | i64 / u64   | 8     | Two's complement / unsigned, BE/LE   |
   +-------------+-------+--------------------------------------+
   | f32         | 4     | IEEE 754 single, BE/LE               |
   +-------------+-------+--------------------------------------+
   | f64         | 8     | IEEE 754 double, BE/LE               |
   +-------------+-------+--------------------------------------+

5.3. Array Encoding
-------------------

An array of any element type is encoded as:

::

    Size      element_count
    [type]    element_0
    [type]    element_1
    ...
    [type]    element_{count-1}

The element count is a Size (Section 5.1.1) — typically a single
byte for short arrays. The elements follow contiguously with no
intervening padding.

5.4. FieldDesc (Type Description)
---------------------------------

A FieldDesc is the wire encoding of a PVData type. Every connection
maintains a per-direction cache of FieldDesc trees, keyed by 16-bit
type ID. The first time a value of a given type is exchanged on the
connection, the FieldDesc is transmitted in full and assigned a
type ID; subsequent exchanges of the same type reference only the
type ID.

A FieldDesc starts with a single byte indicating the field kind:

.. table:: FieldDesc kind byte
   :widths: auto

   +---------+--------------------+-------------------------------------+
   | Value   | Kind               | Followed by                         |
   +=========+====================+=====================================+
   | 0x00    | NULL_TYPE_CODE     | (no further data; rarely used)      |
   +---------+--------------------+-------------------------------------+
   | 0x80..  | scalar (bool,      | sub-byte distinguishes width and    |
   | 0xBF    | numeric, string)   | signedness                          |
   +---------+--------------------+-------------------------------------+
   | 0x88..  | scalar array of    | sub-byte distinguishes element type |
   | 0x8F    | a primitive        |                                     |
   +---------+--------------------+-------------------------------------+
   | 0xFE    | FieldDesc by ID    | Type-ID lookup against connection   |
   |         | reference          | cache                               |
   +---------+--------------------+-------------------------------------+
   | 0xFD    | FieldDesc by ID +  | New type to add to cache: ID (u16)  |
   |         | inline body        | + FieldDesc body                    |
   +---------+--------------------+-------------------------------------+
   | 0xFF    | NULL FieldDesc     | (no further data — null/empty)      |
   +---------+--------------------+-------------------------------------+

The complete sub-byte mapping (the bit-level meaning of bits 0..2
of a scalar kind byte that distinguish the specific scalar width
and signedness) is normative protocol detail that this revision of
the specification leaves to a future amendment; existing
implementations have implemented the mapping compatibly and the
amendment will reflect the established encoding.

For Structure (kind 0xFD with structure bit) and Union, the body is:

::

    String    type_id      (e.g. "epics:nt/NTScalar:1.0", possibly empty)
    Size      field_count
    For each field:
        String    field_name
        FieldDesc field_type   (may itself reference cache or be inline)

The type ID assignment is **bidirectional**: each peer maintains its
own outgoing-side cache (IDs it has assigned) and incoming-side cache
(IDs the peer has assigned). The two caches are independent and MAY
use overlapping ID values.

5.5. BitSet Encoding
--------------------

Many PVA messages carry a *BitSet*: a length-prefixed sequence of
octets used as a bitmap whose bit indices correspond to fields of
a previously-introduced PVData type description (FieldDesc, Section
5.4). BitSets appear in operation messages to indicate which fields
of a structured value are present (CMD_GET response, Section 9.2.2),
which fields are being written (CMD_PUT request, Section 9.3),
which fields changed in a monitor update (CMD_MONITOR update,
Section 9.5.3), and which fields experienced server-side queue
overrun (the ``overrun_mask`` of a monitor update). All BitSets in
this protocol use the encoding and indexing rules specified here.

5.5.1. Wire Format
~~~~~~~~~~~~~~~~~~

A BitSet is encoded as:

::

    Size      n               (octet count of the bit data;
                               0 is permitted and means "no bits")
    octet[n]  data             (bit data; little-endian within each
                               octet — see 5.5.2)

The leading Size (Section 5.1.1) is the **octet count** of the
bit data, NOT the bit count. A BitSet that addresses K bits
occupies ceil(K/8) octets, padded with trailing zero bits in the
final octet.

5.5.2. Bit-to-Octet Mapping
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Within the bit data, **bit index i is octet (i / 8), bit (i mod 8)**,
with bit 0 of an octet being the least-significant bit (value 1)
and bit 7 the most significant (value 128). Equivalently:

::

    is_set(i) = (data[i / 8] >> (i mod 8)) & 1

The bit-to-octet mapping does NOT depend on the per-message byte
order flag (Section 4.2). BitSet octets are read in receive order;
the LSB-first-within-octet convention is fixed. (This is consistent
with the standard ``java.util.BitSet``-style encoding from which
the PVA encoding was derived.)

5.5.3. Bit Indexing within a FieldDesc Tree
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Bit indices in a BitSet correspond to nodes of the FieldDesc tree
(Section 5.4) of the receiving operation. The mapping is
**depth-first pre-order** with the root structure assigned bit 0:

- **Bit 0** is assigned to the **root node** of the FieldDesc
  (the structure that the BitSet is reporting on, in its entirety).
- For any node assigned bit ``i``, its **first child** is assigned
  bit ``i + 1``.
- A child's **subsequent siblings** are assigned bits at offsets
  computed from each preceding sibling's *subtree size*: if the
  first child of a node N is assigned bit ``i+1`` and has
  subtree-size ``s``, then N's second child is assigned bit
  ``i + 1 + s``; the third is offset by another full subtree-size
  of the second child; and so on.

The **subtree size** of a node is defined recursively:

- A leaf node (a primitive scalar, a scalar array, or a string)
  has subtree size 1.
- A complex node (struct, union, any, structure-array) has
  subtree size = 1 + sum(subtree-sizes of its direct children).

Thus a BitSet for a structure with ``M`` total nodes (counting the
root, every nested structure, and every leaf field) addresses bit
indices in the range ``[0, M-1]``; the BitSet's octet count is
ceil(M / 8). Bits beyond ``M-1`` are reserved and MUST be sent as
zero by senders; receivers MUST ignore them.

**Example.** Consider this FieldDesc:

::

    structure {                  bit 0  (root)
        double  value;           bit 1
        structure timestamp {    bit 2
            uint  secondsPastEpoch;  bit 3
            uint  nanoseconds;       bit 4
        }
        structure alarm {        bit 5
            int  severity;       bit 6
            int  status;         bit 7
            string message;      bit 8
        }
    }

The whole tree has 9 nodes; a complete BitSet addressing every
field requires at least 2 octets (ceil(9/8) = 2). Bit indices are
assigned in depth-first pre-order. To indicate that the entire
``timestamp`` substructure is present, a sender sets bit 2; bits
3 and 4 (the children of ``timestamp``) MAY be left zero — see the
parent-cascade rule in Section 5.5.5.

5.5.4. Special Node Kinds
~~~~~~~~~~~~~~~~~~~~~~~~~

The bit-indexing rules above are uniform across structure-bearing
node kinds, but two kinds have additional semantics:

- **Union** (and **any** / variant-union). The union node itself
  has a bit; its possible discriminated-union members do NOT each
  have separate bits at the same level. The union's child structure
  in the FieldDesc is the *currently-selected* member; sub-bits
  inside the union descend into that selected member. Union bits
  do NOT participate in the parent-cascade rule (Section 5.5.5).

- **Structure-array** (an array whose elements are themselves
  structures). The structure-array node has a single bit; the
  per-element structures do NOT each receive their own bits. When
  the structure-array bit is set, the entire array (every element)
  is considered present in the message; partial-array deltas at
  per-element granularity are not expressible via BitSet.

5.5.5. Parent Cascade
~~~~~~~~~~~~~~~~~~~~~

When a parent node's bit is set AND none of that parent's direct
children's bits are set, AND the parent is a complex type that is
NOT a union (or any / variant-union), then the parent bit
**implicitly cascades** to all direct children: the receiver
treats every direct child's bit as set. The cascade applies
recursively — once a child receives the implicit set via cascade,
the same rule fires again at the next level if that child is itself
complex with no explicit child bits set.

This rule is the standard way to denote "the whole subtree is
present" without listing every leaf bit individually:

- A sender that includes the entire structure sets only bit 0
  (the root) and leaves all other bits zero. The receiver, on
  applying the cascade, treats the whole tree as present.
- A sender that updates only one leaf inside a substructure sets
  only that leaf's bit; the parent and root bits are zero, and
  no cascade fires.
- A sender that updates an entire substructure sets that
  substructure's bit and leaves the substructure's children
  zero; the cascade fills in the children at the receiver.

The cascade does NOT apply to unions, anys, or structure-arrays
(the union case is documented in Section 5.5.4).

5.5.6. Empty BitSets
~~~~~~~~~~~~~~~~~~~~

A BitSet with ``n = 0`` (zero octets of bit data) is permitted and
has well-defined meaning: no bits are set. In the contexts where
BitSets appear in this protocol, an empty BitSet means:

- **CMD_GET / CMD_PUT request and response**: no fields are being
  reported or written. The body of the operation MUST contain no
  per-field data.
- **CMD_MONITOR update**: no fields changed since the last update;
  the update is a heartbeat / keepalive only. (Servers SHOULD use
  pipelined-monitor flow control rather than emitting empty
  updates; see Section 9.5.4.)
- **overrun_mask**: no per-field overrun.

5.5.7. Receiver Algorithm
~~~~~~~~~~~~~~~~~~~~~~~~~

Pseudocode for decoding a BitSet against a known FieldDesc tree
``T``:

::

    1. Read Size n.
    2. Read n octets of bit data into D.
    3. For each node N in T, in depth-first pre-order, with index i:
         is_set(i) := (i/8 < n) AND ((D[i/8] >> (i mod 8)) & 1)
         If T's node N is a leaf (or union/any/struct-array),
             N.included := is_set(i).
         If T's node N is a structure (and not union/any/
                 struct-array):
             N.included := is_set(i).
             If N.included AND no direct child of N has its
                     is_set(j) true:
                 mark every direct child of N as included
                 (cascade — apply recursively as each marked
                 child is itself processed).

A complete decoder additionally walks ``T`` to consume the
per-field encoded values for every node whose ``included`` flag
came out true.

5.6. Type ID Lifetime
---------------------

Type IDs are valid for the lifetime of the TCP connection only.
A new connection MUST start with empty type-ID caches in both
directions. There is no protocol-level way to "forget" an ID
mid-connection; once assigned, an ID maps to its type description
until connection close.

5.7. Normalised Types (NT)
--------------------------

The PVA type system supports user-defined named types via the
``type_id`` field of the Structure FieldDesc. Common conventions
defined by the EPICS pvData "Normative Types" specification use IDs
of the form ``epics:nt/NTScalar:1.0``, ``epics:nt/NTTable:1.0``,
etc.

This specification does NOT define the structure of any specific
NT type; it only specifies how a type ID is transmitted on the
wire. The set of NT types and their field structures is defined in
the epics-pvData NT specification (informative reference).

----

6. Connection Validation
========================

6.1. Server-Initiated Validation Request
----------------------------------------

After TCP three-way handshake completes, the **server** MUST send
``CMD_CONNECTION_VALIDATION`` (command 1) as the first PVA message:

.. table:: CMD_CONNECTION_VALIDATION (server → client) payload
   :widths: auto

   +--------------+---------------------------------------------+
   | Field        | Type / value                                |
   +==============+=============================================+
   | server GUID  | 12 octets (random, server-chosen)           |
   +--------------+---------------------------------------------+
   | server_buf   | u32 server's receive buffer size            |
   +--------------+---------------------------------------------+
   | server_intro | u16 server's introspection-registry size    |
   +--------------+---------------------------------------------+
   | reg_addr     | u8 + Size-list of authentication            |
   |              | mechanisms (each: String) the server        |
   |              | accepts                                     |
   +--------------+---------------------------------------------+

The server's GUID is a 12-octet random identifier chosen at server
startup. It MUST be globally unique with high probability (server
implementations typically generate it from ``/dev/urandom`` or
equivalent). The GUID is the same for all connections and beacons
emitted by the server; clients use it to detect server restarts.

The receive buffer size advertises the maximum non-segmented
message size the server will accept. The introspection-registry
size advertises the maximum number of cached type IDs the server
will track per connection.

The authentication-mechanisms list enumerates the auth methods the
server will accept. For plain PVA (this specification), the only
mechanism is "ca" (advisory client-name only, no cryptographic
verification). For SPVA, additional mechanisms appear:
``x509``, ``krb``, ``ldap``, etc. (See :doc:`/protocol-spec/spva`.)

6.2. Client Validation Response
-------------------------------

The client responds with its own ``CMD_CONNECTION_VALIDATION``:

.. table:: CMD_CONNECTION_VALIDATION (client → server) payload
   :widths: auto

   +--------------+---------------------------------------------+
   | Field        | Type / value                                |
   +==============+=============================================+
   | client_buf   | u32 client's receive buffer size            |
   +--------------+---------------------------------------------+
   | client_intro | u16 client's introspection-registry size    |
   +--------------+---------------------------------------------+
   | qos          | u16 quality-of-service hints (priority)     |
   +--------------+---------------------------------------------+
   | auth_method  | String: chosen auth method (from server's   |
   |              | offered list)                               |
   +--------------+---------------------------------------------+
   | auth_data    | Variant: auth-method-specific payload       |
   |              | (e.g. for "ca": user-name + host-name       |
   |              | strings)                                    |
   +--------------+---------------------------------------------+

The client MUST choose an auth method that the server offered. If
no acceptable method is available, the client MUST close the
connection.

6.3. Connection Validated (Success or Failure)
----------------------------------------------

The server acknowledges with ``CMD_CONNECTION_VALIDATED`` (command
9):

.. table:: CMD_CONNECTION_VALIDATED payload
   :widths: auto

   +-------------+----------------------------------------------+
   | Field       | Type / value                                 |
   +=============+==============================================+
   | status      | Status (Section 15.1): OK or ERROR + msg     |
   +-------------+----------------------------------------------+

If the status is OK (or OK_WITH_WARNING), the connection is ready
for channel operations. If the status is ERROR or FATAL, the server
MUST close the TCP connection after sending the message.

6.4. Authentication Continuation
--------------------------------

If the chosen auth method requires additional round-trips (e.g.
SPVA's Kerberos or X.509 challenge-response), the client and server
exchange further ``CMD_AUTHNZ`` messages between
``CMD_CONNECTION_VALIDATION`` and ``CMD_CONNECTION_VALIDATED``.
The format of ``CMD_AUTHNZ`` payloads is auth-method-specific and
out of scope for this specification (see :doc:`/protocol-spec/spva`).

----

7. Name Resolution and Search
=============================

7.1. Search Request
-------------------

A client sends ``CMD_SEARCH`` (command 3) over UDP to discover
servers hosting one or more named PVs:

.. table:: CMD_SEARCH payload
   :widths: auto

   +-----------------+--------------------------------------------+
   | Field           | Type / value                               |
   +=================+============================================+
   | search_seq      | u32 client-chosen sequence number          |
   +-----------------+--------------------------------------------+
   | flags           | u8 (``MustReply`` 0x01, ``Unicast`` 0x80)  |
   +-----------------+--------------------------------------------+
   | reserved        | 3 octets, MUST be zero                     |
   +-----------------+--------------------------------------------+
   | response_addr   | 16 octets (IPv6 or IPv4-mapped-IPv6)       |
   +-----------------+--------------------------------------------+
   | response_port   | u16 client's UDP source port               |
   +-----------------+--------------------------------------------+
   | proto_count     | u8 number of accepted protocols            |
   +-----------------+--------------------------------------------+
   | protocols       | proto_count × String (e.g. "tcp",          |
   |                 | "tls" for SPVA)                            |
   +-----------------+--------------------------------------------+
   | channel_count   | u16 number of channel names searched       |
   +-----------------+--------------------------------------------+
   | channels        | channel_count × {u32 search_id,            |
   |                 | String name}                               |
   +-----------------+--------------------------------------------+

The ``response_addr`` and ``response_port`` are the address the
server should reply TO. This is normally the client's UDP source
address, but the explicit field is necessary because broadcast
search packets may be relayed and the server needs an authoritative
return address.

The flags:

- ``MustReply`` (0x01): Server MUST reply with whatever it knows,
  including negative replies (server has no matching channel).
- ``Unicast`` (0x80): Hint that this is a unicast search; affects
  rate-limiting on the server side.

The ``protocols`` list enumerates which TCP transports the client
accepts:

- ``"tcp"`` — plain PVA over TCP
- ``"tls"`` — SPVA over TCP with TLS 1.3

A server replying MUST select a transport from this list and
include it in the response.

The per-channel ``search_id`` is a client-allocated handle the
client uses to match the response to the request.

7.2. Search Response
--------------------

A server replies with ``CMD_SEARCH_RESPONSE`` (command 4) UDP
unicast to the client:

.. table:: CMD_SEARCH_RESPONSE payload
   :widths: auto

   +-----------------+-----------------------------------------+
   | Field           | Type / value                            |
   +=================+=========================================+
   | server GUID     | 12 octets                               |
   +-----------------+-----------------------------------------+
   | search_seq      | u32 (echoed from request)               |
   +-----------------+-----------------------------------------+
   | server_addr     | 16 octets (IPv6 or v4-mapped)           |
   +-----------------+-----------------------------------------+
   | server_port     | u16 server's TCP listening port         |
   +-----------------+-----------------------------------------+
   | protocol        | String (chosen from request's list)     |
   +-----------------+-----------------------------------------+
   | found           | bool: 1 = at least one match,           |
   |                 | 0 = no match (negative reply)           |
   +-----------------+-----------------------------------------+
   | channel_count   | u16                                     |
   +-----------------+-----------------------------------------+
   | search_ids      | channel_count × u32 (echoed from        |
   |                 | request, only for matched channels)     |
   +-----------------+-----------------------------------------+

Negative replies (``found = 0``) are sent only when the request had
``MustReply = 1``. Otherwise, a server with no matching channel
silently ignores the search.

7.3. The GUID and Server Identity
---------------------------------

The 12-octet GUID in the search response identifies the server
process. A client tracks ``(GUID, server_addr, server_port)`` as
the unique server identity. If a search response arrives with the
same address+port but a different GUID than previously seen, the
client MUST treat it as a server restart: tear down all channels
on the old (GUID, addr, port) tuple and re-search.

The GUID also appears in beacons (Section 10.1) and in
``CMD_CONNECTION_VALIDATION`` (Section 6.1); all three sources MUST
agree for the same server.

7.4. Multicast and Origin Tagging
---------------------------------

When a client sends a search to a multicast address, multiple
server hosts may receive it. To allow the receiving infrastructure
to identify which host first injected the packet (for diagnostics
and routing), the client MAY include a ``CMD_ORIGIN_TAG`` message
prefix in the same UDP datagram (Section 14).

7.5. Search Retransmission and Back-off
---------------------------------------

A client receiving no reply within an implementation-defined
timeout MUST retransmit the search. pvxs uses an exponential
back-off: 30 ms, 60 ms, 120 ms, ..., capped at 30 seconds; retries
continue indefinitely until the application cancels the search.

Each retransmission MAY change the destination from the address
list (round-robin) and MAY combine multiple channels into a single
search packet (the search list supports up to 65535 channels per
packet).

----

8. Channel Lifecycle
====================

8.1. CREATE_CHANNEL Request
---------------------------

A client opens a channel via ``CMD_CREATE_CHANNEL`` (command 7):

.. table:: CMD_CREATE_CHANNEL request payload
   :widths: auto

   +-----------------+-----------------------------------------+
   | Field           | Type / value                            |
   +=================+=========================================+
   | channel_count   | u16 (always 1; reserved for batching)   |
   +-----------------+-----------------------------------------+
   | client_cid      | u32 client-chosen CID                   |
   +-----------------+-----------------------------------------+
   | channel_name    | String (PV name)                        |
   +-----------------+-----------------------------------------+

The ``channel_count`` field is reserved for future batched
channel-creation; current implementations MUST set it to 1.

8.2. CREATE_CHANNEL Response (Success)
--------------------------------------

The server responds:

.. table:: CMD_CREATE_CHANNEL response (success) payload
   :widths: auto

   +-----------------+-----------------------------------------+
   | Field           | Type / value                            |
   +=================+=========================================+
   | client_cid      | u32 (echoed from request)               |
   +-----------------+-----------------------------------------+
   | server_sid      | u32 server-chosen SID                   |
   +-----------------+-----------------------------------------+
   | status          | Status (Section 15.1)                   |
   +-----------------+-----------------------------------------+
   | access_rights   | u16 access-permission bitmask           |
   +-----------------+-----------------------------------------+

Access rights bitmask:

.. table:: PVA channel access rights
   :widths: auto

   +-------+-------------+--------------------------------------+
   | Bit   | Symbol      | Meaning                              |
   +=======+=============+======================================+
   | 0     | ``PUT``     | Client may PUT (write)               |
   +-------+-------------+--------------------------------------+
   | 1     | ``PUT_GET`` | Client may PUT_GET                   |
   +-------+-------------+--------------------------------------+
   | 2     | ``RPC``     | Channel supports RPC                 |
   +-------+-------------+--------------------------------------+

Read access is implicit on every successfully-created channel.

8.3. CREATE_CHANNEL Response (Failure)
--------------------------------------

If the server cannot create the channel, the response has the same
field layout but ``status`` indicates ERROR or FATAL with a
descriptive message. The ``server_sid`` field is undefined and
MUST NOT be used; the client MUST treat the channel as failed.

8.4. DESTROY_CHANNEL Request
----------------------------

A client closes a channel via ``CMD_DESTROY_CHANNEL`` (command 8):

.. table:: CMD_DESTROY_CHANNEL request
   :widths: auto

   +-----------------+-----------------------------------------+
   | Field           | Type / value                            |
   +=================+=========================================+
   | client_cid      | u32                                     |
   +-----------------+-----------------------------------------+
   | server_sid      | u32                                     |
   +-----------------+-----------------------------------------+

The server MUST respond with the same message form acknowledging,
then release all channel state. After this exchange, the client
MUST NOT use the SID for any further operation; the server MAY
reuse the SID for a future channel.

----

9. Operations on a Connected Channel
====================================

PVA operations follow a consistent pattern: ``Init`` sub-command
(fetch type info), then one or more ``Get`` / ``Process`` / etc.
sub-commands, then ``Destroy`` sub-command (tear down). The IOID
identifies the operation within its channel.

9.1. Common Operation Header
----------------------------

For all per-operation commands (``CMD_GET``, ``CMD_PUT``,
``CMD_PUT_GET``, ``CMD_MONITOR``, ``CMD_RPC``, ``CMD_PROCESS``,
``CMD_GET_FIELD``), the payload begins with:

::

    u32  server_sid       (which channel)
    u32  client_ioid      (which operation on it)
    u8   sub_command      (Init / Destroy / Get / etc.)
    [...subcommand-specific payload...]

9.2. CMD_GET
------------

9.2.1. Init
~~~~~~~~~~~

Client sends ``CMD_GET`` with sub-command ``Init`` (0x08):

::

    u32  server_sid
    u32  client_ioid       (new, unique among in-flight ops)
    u8   subcmd = 0x08     (Init)
    PVRequest  request     (FieldDesc + value, describes the
                            requested fields and pipeline options)

The server responds:

::

    u32  client_ioid       (echoed)
    u8   subcmd = 0x08     (echoed)
    Status status
    [if status OK:]
        FieldDesc  channel_type   (full type description)

If status is OK, the channel's type description is now in the
client's per-connection cache for reuse.

9.2.2. Get
~~~~~~~~~~

Client sends ``CMD_GET`` with sub-command ``Get`` (0x40):

::

    u32  server_sid
    u32  client_ioid       (matching Init)
    u8   subcmd = 0x40     (Get)

The server responds:

::

    u32  client_ioid
    u8   subcmd = 0x40
    Status status
    [if status OK:]
        BitSet     changed_fields   (which fields are valid in payload)
        Value      value            (encoded per channel_type)

The ``BitSet`` (Section 5.5) indicates which fields of the
structured value are present in the payload; fields whose bits are
clear retain their previously-known values at the receiver.

9.2.3. Destroy
~~~~~~~~~~~~~~

Client sends ``CMD_GET`` with sub-command ``Destroy`` (0x10):

::

    u32  server_sid
    u32  client_ioid
    u8   subcmd = 0x10     (Destroy)

The server releases per-operation state. No response.

9.3. CMD_PUT
------------

Same Init / Get-or-Put / Destroy pattern as ``CMD_GET``, but with
``Put`` sub-command bit (0x40) carrying a value FROM the client to
the server:

Init request: same as ``CMD_GET`` Init (PVRequest describes which
fields the client intends to write).

Init response: same as ``CMD_GET`` Init response.

Put request:

::

    u32  server_sid
    u32  client_ioid
    u8   subcmd = 0x40
    BitSet     changed_fields
    Value      value

Put response:

::

    u32  client_ioid
    u8   subcmd = 0x40
    Status status

The optional Get-after-Put: the client MAY also send a ``Get`` after
a successful Put, with the same IOID, to fetch the post-write value.

9.4. CMD_PUT_GET
----------------

``CMD_PUT_GET`` (command 12) atomically writes a value and returns
the resulting value. Its Init exchanges TWO type descriptions: the
"put structure" (input) and the "get structure" (output). Subsequent
operation messages carry both bitsets and both values.

The full sub-command set:

.. table:: CMD_PUT_GET sub-commands
   :widths: auto

   +---------+--------+-----------------------------------------+
   | Bit     | Name   | Purpose                                 |
   +=========+========+=========================================+
   | 0x08    | Init   | Fetch put-type and get-type             |
   +---------+--------+-----------------------------------------+
   | 0x40    | PutGet | Atomic put-then-get                     |
   +---------+--------+-----------------------------------------+
   | 0x80    | GetPut | Fetch current put structure (no put)    |
   +---------+--------+-----------------------------------------+
   | 0x10    | Destroy| Release operation state                 |
   +---------+--------+-----------------------------------------+

9.5. CMD_MONITOR (Subscriptions)
--------------------------------

A subscription is a long-lived operation that emits an unbounded
stream of value updates from server to client.

9.5.1. Init
~~~~~~~~~~~

Client sends ``CMD_MONITOR`` with sub-command ``Init`` (0x08) and
the same PVRequest payload as ``CMD_GET`` Init. The server responds
with the channel type description and an explicit OK status.

9.5.2. Start
~~~~~~~~~~~~

Client sends ``CMD_MONITOR`` with sub-command ``Start`` (0x44 — bit
0x40 + bit 0x04). The server begins emitting updates.

9.5.3. Update Stream (server → client)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The server emits a stream of update messages:

::

    u32  client_ioid
    u8   subcmd = 0x00     (data update)
    BitSet     changed_fields   (which fields changed)
    Value      value            (only changed fields' encoding)
    BitSet     overrun_mask     (queue-overflow indication per field)

Each update is identified by IOID. A field whose bit is set in
``overrun_mask`` indicates the server's per-field update queue
overflowed and one or more updates were merged.

9.5.4. Pipeline Flow Control (V2)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A monitor MAY operate in "pipeline" mode, where the client sends
periodic ``CMD_MONITOR`` ack messages with sub-command ``Pipeline``
(0x80) and a u32 ack count. The server emits at most ack_count
updates ahead of the last acknowledged. This is the recommended
flow-control mechanism for high-update-rate channels.

9.5.5. Stop / Destroy
~~~~~~~~~~~~~~~~~~~~~

Client sends ``CMD_MONITOR`` with sub-command ``Stop`` (0x84) to
pause updates without releasing the subscription. Sub-command
``Destroy`` (0x10) tears down the subscription completely.

9.6. CMD_RPC
------------

``CMD_RPC`` (command 20) is a request-response operation with
arbitrary structured payloads. The Init exchange delivers no type
information for RPC (each RPC call describes its argument and result
inline).

RPC request:

::

    u32  server_sid
    u32  client_ioid
    u8   subcmd = 0x40     (Invoke)
    PVRequest  request_value

RPC response:

::

    u32  client_ioid
    u8   subcmd = 0x40
    Status status
    [if status OK:]
        Value      response_value

9.7. CMD_PROCESS
----------------

Triggers record processing on the server side without reading or
writing the value. The Init request and response match
``CMD_GET``'s pattern but the Process sub-command (0x40) takes no
payload data.

9.8. CMD_GET_FIELD (Introspection)
----------------------------------

``CMD_GET_FIELD`` (command 17) fetches the type description of a
sub-field of a channel without subscribing or reading its value:

::

    u32  server_sid
    u32  client_ioid
    String     sub_field_name   (empty = root, ".substruct.field" = nested)

Response:

::

    u32  client_ioid
    Status status
    FieldDesc  field_type

Used by tooling to inspect a channel's structure before deciding
whether to subscribe or read.

9.9. CMD_DESTROY_REQUEST and CMD_CANCEL_REQUEST
-----------------------------------------------

``CMD_DESTROY_REQUEST`` (command 15) is a per-operation tear-down,
equivalent to sending the ``Destroy`` sub-command via the original
operation command. Implementations MAY use either form.

``CMD_CANCEL_REQUEST`` (command 21) is a SOFT cancel: the server
MAY complete an in-flight Get/Put before honoring the cancellation.
Distinguishes from Destroy, which is a HARD cancel.

----

10. Beacons and Server Announcement
===================================

10.1. CMD_BEACON Format
-----------------------

A PVA server periodically emits ``CMD_BEACON`` (command 0) UDP
datagrams to ``EPICS_PVA_BROADCAST_PORT`` (default 5076). Beacons
reach clients directly, not via a per-host repeater (PVA has no
analog of CA's repeater).

.. table:: CMD_BEACON payload
   :widths: auto

   +-----------------+-----------------------------------------+
   | Field           | Type / value                            |
   +=================+=========================================+
   | server GUID     | 12 octets                               |
   +-----------------+-----------------------------------------+
   | beacon_seq      | u8 monotonically increasing per server  |
   +-----------------+-----------------------------------------+
   | change_count    | u16 increments on server-side change    |
   |                 | (PV add/remove)                         |
   +-----------------+-----------------------------------------+
   | server_addr     | 16 octets (IPv6 or v4-mapped)           |
   +-----------------+-----------------------------------------+
   | server_port     | u16 server's TCP port                   |
   +-----------------+-----------------------------------------+
   | protocol        | String (e.g. "tcp" or "tls")            |
   +-----------------+-----------------------------------------+
   | server_status   | Variant: server-defined status fields,  |
   |                 | usually empty                           |
   +-----------------+-----------------------------------------+

10.2. Beacon Cadence
--------------------

A PVA server emits beacons:

- **Initial fast cadence**: every 100 ms for the first 5 beacons
  after server startup (rapid-presence-announcement).
- **Steady-state**: every ``EPICS_PVA_BEACON_PERIOD`` (default
  15 seconds).

10.3. Use of Beacons for Liveness Detection
-------------------------------------------

A client tracks beacons by ``(server_addr, server_port, GUID)``.
Detected events:

- **New server**: beacon from previously-unknown ``(addr, port)``
  prompts the client to re-search for any pending PV names.
- **Server restart**: GUID changes for a known ``(addr, port)``;
  client tears down all old channels on that server and re-searches.
- **Server failure**: N consecutive missed beacons and no TCP
  traffic; client closes any channels.
- **Server topology change**: ``change_count`` increments; client
  invalidates its negative-search cache for that server (it MAY
  now host PVs it previously didn't).

----

11. Segmentation and Large Messages
====================================

A single logical PVA application message MAY be split across
multiple on-wire frames using the segmentation flags (Section 4.2).

11.1. Segment Markers
---------------------

Header flags bits 4-5 indicate segment position:

.. table:: Segmentation flags
   :widths: auto

   +-----------+-----------+----------------------------------+
   | Bits 4-5  | Symbol    | Meaning                          |
   +===========+===========+==================================+
   | 00        | SegNone   | Standalone (not segmented)       |
   +-----------+-----------+----------------------------------+
   | 01 (0x10) | SegFirst  | First segment of a logical msg   |
   +-----------+-----------+----------------------------------+
   | 11 (0x30) | SegMid    | Middle segment                   |
   +-----------+-----------+----------------------------------+
   | 10 (0x20) | SegLast   | Last segment                     |
   +-----------+-----------+----------------------------------+

A receiver MUST accumulate segments by command code: all segments
of one logical message MUST share the same command code, and
segments from different logical messages MAY be interleaved.

11.2. Reassembly Rules
----------------------

- Segment with ``SegFirst`` starts a new logical message of the
  given command code; receiver creates a reassembly buffer.
- Segments with ``SegMid`` append to the in-progress reassembly
  buffer for the matching command.
- Segment with ``SegLast`` completes the reassembly; receiver
  passes the concatenated payload to the operation handler and
  destroys the reassembly buffer.

If a sender begins a segmented message (sends ``SegFirst``) and then
fails to send ``SegLast`` (e.g. connection closes), the receiver
MUST discard the partial reassembly without applying it.

11.3. Mixed Segmented and Standalone
------------------------------------

Standalone messages (``SegNone``) MAY be interleaved with the
segments of a different logical message. Implementations MUST NOT
allow two segmented messages of the SAME command code to be
in-flight simultaneously on the same connection.

----

12. Flow Control and Liveness
=============================

12.1. CMD_ECHO
--------------

``CMD_ECHO`` (command 2) is a request-response keepalive identical
in spirit to CA's. Either side MAY send ECHO; the receiver echoes
the payload (which is opaque from the protocol's perspective —
typically a few bytes for round-trip-time measurement).

A client that has received no traffic from the server within
``EPICS_PVA_CONN_TMO`` (default 30 seconds) SHOULD send ECHO and
treat lack of response within an implementation-defined window as
connection loss.

12.2. Marker-Based Flow Control
-------------------------------

Control messages ``SetMarker`` and ``AckMarker`` (Section 4.4)
implement byte-stream flow control complementary to TCP's. The
sender periodically inserts a ``SetMarker`` carrying a 4-octet
"position" (cumulative bytes sent); the receiver acknowledges the
highest-seen marker via ``AckMarker``. A sender that has sent
``M`` bytes since the last ``AckMarker`` SHOULD pause and wait for
acknowledgment if ``M`` exceeds the receiver's declared buffer
size (Section 6.1).

This mechanism is rarely exercised because TCP's native flow
control usually suffices; pvxs uses it only at very high data
rates.

12.3. SetEndian
---------------

``SetEndian`` is a server-to-client control message requesting that
the client switch byte-order policy for its outgoing messages. The
server uses this when it wishes to avoid byte-swapping; a server
on a big-endian host requests ``MSB`` of clients connecting to it.

Clients MUST honor ``SetEndian`` requests; servers MUST tolerate
clients that don't honor (rare).

12.4. CMD_MESSAGE
-----------------

The server MAY send ``CMD_MESSAGE`` (command 18) to deliver a log
message to the client:

::

    u32  client_ioid       (which operation; 0 = unrelated)
    u8   mtype             (severity: 0=info, 1=warn, 2=err, 3=fatal)
    String  message_text

Clients SHOULD log received messages at the equivalent severity.

----

13. ACL Change Notification
============================

The server MAY send ``CMD_ACL_CHANGE`` (command 6) at any time
after a channel is connected to update the client's understanding
of the channel's permissions. This is typically triggered by a
server-side policy reload (e.g. ASG reload).

.. table:: CMD_ACL_CHANGE payload
   :widths: auto

   +-----------------+-----------------------------------------+
   | Field           | Type / value                            |
   +=================+=========================================+
   | client_cid      | u32 affected channel's CID              |
   +-----------------+-----------------------------------------+
   | permissions     | u8 bitmask (PUT 0x01, PUT_GET 0x02,     |
   |                 | RPC 0x04)                               |
   +-----------------+-----------------------------------------+

The client MUST update its cached access-rights for the channel
and apply the new permissions to all subsequent operations.

----

14. Origin Tagging
==================

``CMD_ORIGIN_TAG`` (command 22) is a UDP-only message that
identifies the originating multicast group endpoint. Used in
multicast deployments where intermediate devices need to tag
forwarded packets with the original source.

The payload is a 16-octet IPv6-form address (IPv4 mapped if
applicable) of the original sender. ``CMD_ORIGIN_TAG`` typically
appears as the first message in a UDP datagram, prefixing the
``CMD_SEARCH`` or ``CMD_BEACON`` it tags.

----

15. Error Handling and Status
==============================

15.1. Status Encoding
---------------------

PVA's "Status" is a structured value embedded in many response
payloads:

.. table:: Status encoding
   :widths: auto

   +---------+--------------+----------------------------------+
   | Field   | Type         | Meaning                          |
   +=========+==============+==================================+
   | type    | u8           | 0=OK, 1=OK_WITH_WARN, 2=ERROR,   |
   |         |              | 3=FATAL, 0xFF=OK_NO_DETAIL       |
   +---------+--------------+----------------------------------+
   | message | String       | (only if type != OK_NO_DETAIL)   |
   +---------+--------------+----------------------------------+
   | callTree| String       | (only if type != OK_NO_DETAIL,   |
   |         |              | server-side stack trace, MAY be  |
   |         |              | empty)                           |
   +---------+--------------+----------------------------------+

The 0xFF (``OK_NO_DETAIL``) shortcut allows the common
no-error-no-message case to be encoded as a single byte.

15.2. Status Type Semantics
---------------------------

- **OK (0)**: operation succeeded; no message necessary.
- **OK_WITH_WARN (1)**: operation succeeded; message describes a
  non-fatal warning the client SHOULD log.
- **ERROR (2)**: operation failed; message describes the error;
  the client MAY retry; the connection remains usable.
- **FATAL (3)**: operation failed and the connection is now
  unusable; the server SHOULD close the TCP connection after
  sending; client MUST treat the connection as lost.
- **OK_NO_DETAIL (0xFF)**: like OK but with no message and no
  call tree; on-wire encoding shortcut.

15.3. Status in Operation Responses
-----------------------------------

Every operation response (``CMD_GET``, ``CMD_PUT``, ``CMD_RPC``,
etc.) carries a Status. Clients MUST inspect the Status type before
parsing any subsequent fields; if status is ERROR or FATAL, no
value follows.

----

16. Version Negotiation
=======================

16.1. Wire Version
------------------

The header version byte (offset 1) is the protocol version of the
sending peer. pvxs (this specification's normative implementation)
sends version 2 for both client and server messages. A receiver
seeing version != 2 and != 1 MUST close the connection with FATAL
status.

Version 1 is the historical EPICS V4 PVA implementation; pvxs is
backward-compatible with V1 clients in practice. New features that
would require a wire-format change beyond what version 2 supports
require a version 3 increment, which is reserved for future work.

16.2. Capability Negotiation
----------------------------

Beyond the version byte, capability negotiation happens via the
authentication-mechanism list and quality-of-service hints in
``CMD_CONNECTION_VALIDATION`` (Section 6).

16.3. Forward Compatibility
---------------------------

A peer receiving an unknown command code (>22) on an established
connection SHOULD log and skip the message, NOT close the
connection. The 4-octet length field in the header allows a
receiver to skip the unknown payload exactly. This permits a
server to introduce new commands without breaking older clients
(the older client simply does not exercise the new command).

----

17. Security Considerations
============================

17.1. PVA Provides No Authentication
------------------------------------

The "ca" authentication mechanism in
``CMD_CONNECTION_VALIDATION`` carries the client's user-name and
host-name as plaintext strings; there is no cryptographic
verification. Servers MUST treat these as advisory metadata only.

17.2. PVA Provides No Confidentiality
-------------------------------------

PVA traffic is plaintext. PV names, values, and authentication
data are all visible to on-path observers. Sites carrying
sensitive process data over PVA SHOULD use a private network or
SHALL switch to SPVA.

17.3. PVA Provides Limited Integrity
------------------------------------

PVA relies on TCP/UDP checksums. There is no message authentication
code; an active attacker can modify packets in flight.

17.4. Denial of Service
-----------------------

A PVA server is vulnerable to:

- UDP search flooding (one packet can carry up to 65535 channel
  searches).
- TCP connection exhaustion.
- Type-cache exhaustion via many distinct types per connection.

Implementations SHOULD provide configurable limits on per-client
search rate, max connections per source IP, and max distinct
type-IDs per connection.

17.5. When to Use SPVA Instead
------------------------------

Sites requiring cryptographic authentication, confidentiality,
integrity protection against active attackers, or per-channel
authorization tied to verified identity SHALL use SPVA
(:doc:`/protocol-spec/spva`).

----

18. IANA Considerations
=======================

The default PVA ports (5075 TCP, 5076 UDP) are NOT IANA-registered.
They are configurable via ``EPICS_PVA_SERVER_PORT`` and
``EPICS_PVA_BROADCAST_PORT`` environment variables and SHOULD be
left at default unless they conflict with a site-local
application.

PVA does not define a custom IP protocol number; it uses standard
TCP and UDP.

PVA does not define a URL scheme. Clients identify channels by
PV name, resolved to ``(server, port)`` at runtime via search.

----

19. References
==============

19.1. Normative References
--------------------------

- **RFC 2119** — Bradner, S., "Key words for use in RFCs to
  Indicate Requirement Levels", BCP 14, :rfc:`2119`, March 1997.
- **RFC 8174** — Leiba, B., "Ambiguity of Uppercase vs Lowercase in
  RFC 2119 Key Words", BCP 14, :rfc:`8174`, May 2017.

19.2. Informative References
----------------------------

- **EPICS pvData Normative Types** — informally specified at
  https://github.com/epics-base/pvDataWWW; defines the
  ``epics:nt/*`` type-id namespace.
- **pvxs implementation** — https://github.com/slac-epics/pvxs.
  Consulted in preparing this specification; in particular the
  files ``src/pvaproto.h``, ``src/conn.cpp``,
  ``src/serverconn.cpp``, ``src/clientconn.cpp``,
  ``src/dataencode.cpp``, ``src/clientdiscover.cpp``.
- **epics-base PVA implementation** — independent C++ reference
  implementation at ``epics-base/modules/pvAccess``. Consulted in
  preparing this specification.
- :doc:`/protocol-spec/ca` — Channel Access Protocol Specification.
- :doc:`/protocol-spec/spva` — Secure PVAccess Protocol Specification.

----

Authors' Addresses
==================

This specification is maintained by the slac-epics organization at
https://github.com/slac-epics/pvxs-docs. Issues and proposed
clarifications should be filed there.

The PVA protocol was designed by Marty Kraimer and contributors as
part of the EPICS V4 effort. The pvxs reference implementation is
maintained at SLAC. Attribution for the protocol design is to the
EPICS V4 working group; this document is a description, not the
design.
