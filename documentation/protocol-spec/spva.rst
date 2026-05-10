.. _spva_protocol_spec:

================================================
Secure PVAccess (SPVA) Protocol Specification
================================================

:Status: Draft
:Protocol Version: 2 (SPVA is layered on PVA wire-protocol version 2)
:Default TLS Server Port: 5076 (TCP)
:Default Certificate Management Service Port: 5076 (TCP, with TLS)

.. note::

   This document is the normative specification of Secure PVAccess
   (SPVA), the security profile of PVAccess. SPVA inherits PVA's
   wire format and adds TLS 1.3 transport, X.509 mutual
   authentication, certificate-status monitoring,
   certificate-creation RPC, and access-control extensions to the
   EPICS access security file.

   This document specifies what SPVA adds to PVA. The PVA
   specification (:doc:`/protocol-spec/pva`) applies in full for
   everything not security-specific. Underlying cryptographic
   protocols are normatively referenced where used (see Section
   19.1) — most importantly :rfc:`8446` (TLS 1.3), :rfc:`5280`
   (X.509 Public Key Infrastructure), and :rfc:`6960` / :rfc:`6961`
   (Online Certificate Status Protocol). Implementations conform to
   this specification; where an implementation's behavior differs
   from this specification the implementation is in error.

   Specific implementations of SPVA — pvxs and pvxs-cms — were
   consulted in preparing this specification and are listed under
   Informative References (Section 19.2); they have no normative
   weight.

Abstract
========

Secure PVAccess (SPVA) is a security profile of PVAccess that adds
cryptographic authentication, confidentiality, and integrity to the
PVA wire protocol. SPVA replaces PVA's plaintext TCP transport with
TLS 1.3 (:rfc:`8446`) using mutual X.509 authentication
(:rfc:`5280`); it adds a certificate-management RPC interface
to a Certificate Management Service for certificate issuance,
status monitoring, and lifecycle management; and it extends the
EPICS access security file (ACF) with
authenticated-identity-based authorization rules. SPVA preserves PVA's
operation set, type system, and beacon mechanism unchanged. This
document specifies SPVA wire-protocol version 2.

Status of This Document
=======================

This document specifies the SPVA-specific additions to PVA. It is
intended to be read in conjunction with :doc:`/protocol-spec/pva`,
which defines the underlying wire protocol. Where this document is
silent on a wire-format detail, the PVA specification applies.

Pre-existing implementations of SPVA — notably pvxs (slac-epics
fork) and pvxs-cms — and the prior implementation reference
material at :doc:`/programmers-ref/spva-tls`,
:doc:`/programmers-ref/spva-authentication`,
:doc:`/programmers-ref/spva-authorization`, and
:doc:`/programmers-ref/spva-cert-management-protocol` were
consulted in preparing this specification (see Section 19.2). The
specification's authority derives from this document, not from
those implementations or that prior reference material.

Conventions Used in This Document
=================================

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in :rfc:`2119` and
:rfc:`8174`.

This document uses PVA-style notation (Sections 5.1–5.4 of
:doc:`/protocol-spec/pva`):

- ``Size`` — PVA's variable-length unsigned size encoding.
- ``String`` — UTF-8 string with ``Size`` length prefix.
- ``PVStructure`` — a PVData structured value with associated
  FieldDesc.
- ``Status`` — PVA's status struct (Section 15.1 of PVA spec).
- ``time_t`` — POSIX seconds-since-epoch as a 64-bit signed integer.

The phrase **the protocol** refers throughout this document to SPVA
as layered on PVA wire-protocol version 2.

Table of Contents
=================

1. Introduction
2. Protocol Overview
3. Transport Layer (TLS 1.3)
4. X.509 Certificates and Trust
5. Connection Validation with TLS
6. Authentication Mechanisms
7. Certificate-Status Monitoring
8. Certificate Lifecycle States
9. Certificate Creation Request (CCR)
10. Certificate Management Service
11. Authorization (ACF Extensions)
12. Discovery and Search with TLS
13. OCSP Stapling
14. Connection Reconfiguration
15. Error Handling
16. Version Negotiation
17. Security Considerations
18. IANA Considerations
19. References

----

1. Introduction
===============

1.1. Purpose
------------

SPVA enables a PVA client to access PVs hosted by a PVA server with
the following cryptographic guarantees:

- **Authentication of the server to the client** via X.509 server
  certificate validated against a configured trust anchor.
- **Authentication of the client to the server** via X.509 client
  certificate validated against the same (or different) trust
  anchor — mutual TLS (mTLS).
- **Confidentiality** of all wire traffic via TLS 1.3 record-layer
  encryption.
- **Integrity** via TLS 1.3 record-layer authentication tags.
- **Identity-bound authorization**: the cryptographically-verified
  identity from the X.509 certificate is the principal name used in
  ASG/ACF rules for read/write/RPC permission decisions.
- **Certificate-status awareness**: connections whose endpoint
  certificate has been revoked or suspended are torn down within an
  implementation-defined window of the status change.

SPVA does NOT change PVA's wire format, command set, type system, or
beacon mechanism. An SPVA endpoint speaks PVA inside the TLS
record layer, with negotiation hooks at PVA's
``CMD_CONNECTION_VALIDATION`` (Section 6 of the PVA spec) to declare
the cryptographic identity and supported authentication mechanisms.

1.2. Design Philosophy
----------------------

SPVA is designed to:

- **Reuse PVA on the wire** — the entire PVA message vocabulary works
  inside the TLS tunnel without modification.
- **Be optional per channel** — a PVA server MAY accept both
  plain TCP and TLS connections; clients MAY use one or the other
  per channel based on configuration.
- **Be compatible with X.509 PKI** — sites with existing X.509
  infrastructure (corporate CA, IPA, freeIPA, internal AD CS) can
  reuse it.
- **Provide a bootstrapping path** — a Certificate Management
  Service (Section 10) issues certificates to clients and servers
  that do not yet have them. The Certificate Creation Request
  (Section 9) carries an authenticator-specific verifier (Kerberos
  GSS-API token, LDAP-bind-then-sign signature, or administrator-
  approval-pending marker) that the Service uses to verify the
  requesting principal's identity at issuance time.

1.3. Scope
----------

This specification covers:

- The TLS 1.3 transport profile for SPVA (Section 3) — what cipher
  suites, what extensions, what handshake behaviors.
- The X.509 certificate profile (Section 4) — required extensions,
  Subject DN form, Subject Alternative Name conventions,
  EKU constraints.
- The connection-validation handshake additions for SPVA
  (Section 5).
- The single SPVA authentication mechanism (Section 6.1):
  ``x509``. The CCR issuance authenticator plugin framework
  (Section 6.2), including the currently registered ``std``, ``krb``,
  and ``ldap`` authenticator types.
- The certificate-status protocol (Section 7): the cert-status
  PVStructure schema, the subscribe/publish flow, OCSP stapling
  (Section 13).
- Certificate lifecycle states (Section 8) and the ``CCR`` (Section
  9) used to request certificate issuance.
- The Certificate Management Service (Section 10): its PV
  namespace, its RPCs, its responsibilities.
- ACF authorization extensions (Section 11).
- Connection reconfiguration (Section 14) — runtime keychain
  rotation.

It does not cover:

- PVA wire format or operation semantics (see
  :doc:`/protocol-spec/pva`).
- The pvxs C++ API or pvxs-cms C++ API (see
  :doc:`/programmers-ref/index`).
- Operational concerns: deployment of the Certificate Management
  Service, cluster setup, certificate-store management. These are
  :doc:`/user-manual/pvacms`.
- Site-specific PKI policy (root CA selection, intermediate-CA
  hierarchy, naming conventions). SPVA constrains the certificate
  *profile* but not the PKI organisation behind it.

1.4. Terminology
----------------

SPVA-specific terminology in addition to PVA's:

Certificate Management Service
   A long-running service that issues, monitors, and revokes X.509
   certificates for SPVA endpoints. The Certificate Management
   Service itself runs as a PVA server. It exposes some of its
   functions as remote procedure calls (RPCs) at well-known PV
   names — certificate creation, admin scheduling and approval —
   and other functions as conventional monitorable / readable PVs:
   per-certificate status (subscribable), service health, service
   metrics, issuer-cert info, and root-CA info (Section 10). The
   protocol does not mandate any specific implementation; the
   reference implementation is PVACMS (see
   :doc:`/user-manual/pvacms`).

Authenticator
   An issuance mechanism by which a not-yet-certified principal
   proves its identity to the Certificate Management Service in
   order to obtain a certificate. Defined values: ``authnstd``
   (administrator approval), ``authnkrb`` (Kerberos GSS-API),
   ``authnldap`` (LDAP-bind plus key signature).

CCR (Certificate Creation Request)
   A PVStructure that a principal sends to the Certificate
   Management Service to request issuance of a certificate. Carries
   the principal's public key, the requested subject DN, the chosen
   authenticator, and any authenticator-specific verifier payload.

Certificate Subject
   The X.509 Subject Distinguished Name of the certificate. SPVA
   constrains it to specific patterns (Section 4.4).

Cert-status PV
   A well-known PV name pattern, hosted by the Certificate
   Management Service, that publishes the current status of a
   specific certificate identified by its issuer and serial.
   Subscribed by the cert-status monitor in client and server
   runtimes.

Status states
   The set ``PENDING_APPROVAL``, ``PENDING``, ``VALID``,
   ``EXPIRED``, ``REVOKED``, ``PENDING_RENEWAL``,
   ``SCHEDULED_OFFLINE``. See Section 8 for the full state machine.

Trust Anchor
   An X.509 root CA certificate that an SPVA endpoint considers
   authoritative. Configured via keychain file
   (``EPICS_PVA_TLS_KEYCHAIN``).

Keychain
   A file (typically PKCS#12) containing one private key + the
   matching certificate chain + trust anchor(s), used as the
   single configuration source for an SPVA endpoint's TLS identity.

----

2. Protocol Overview
====================

2.1. Layering
-------------

SPVA inserts a TLS 1.3 record layer between PVA and TCP:

::

    +-------------------+ +-------------------+
    |   PVA Search /    | |   PVA Operations  |
    |   Beacon          | |   on a Channel    |
    +-------------------+ +-------------------+
    |        UDP        | |        TLS 1.3    |
    +-------------------+ +-------------------+
                          |        TCP        |
                          +-------------------+
    |               IPv4 / IPv6                |
    +------------------------------------------+

The UDP-side traffic (search and beacon) is unchanged from PVA —
it remains plaintext UDP. SPVA endpoints declare TLS-capability in
their ``CMD_BEACON`` and ``CMD_SEARCH`` "protocols" lists by
including ``"tls"`` alongside or instead of ``"tcp"``.

The TCP-side traffic for SPVA channels is encapsulated in TLS 1.3.
Inside the TLS record layer, the byte stream is exactly the PVA byte
stream of :doc:`/protocol-spec/pva`, with no additional framing.

2.2. A Typical SPVA Exchange
----------------------------

End-to-end SPVA connect-and-get:

1. **Client**: send ``CMD_SEARCH`` with ``protocols = ["tls", "tcp"]``
   (TLS preferred, plain TCP fallback) to the broadcast or unicast
   search destination.

2. **Server**: receive search; send ``CMD_SEARCH_RESPONSE`` with
   ``protocol = "tls"`` and ``server_port = 5076``.

3. **Client**: TCP connect to ``(server_IP, 5076)``.

4. **Client**: initiate TLS 1.3 handshake (ClientHello). The
   ClientHello includes:

   - ``signature_algorithms`` extension limited to algorithms
     SPVA-acceptable (Section 3.3).
   - ``status_request`` extension requesting OCSP stapling
     (:rfc:`6066`, Section 13).

   The ClientHello does NOT carry a ``server_name`` (SNI)
   extension — connection targets are IP-based, not hostname-
   based (Section 3.6).

5. **Server**: respond with TLS ServerHello, server certificate
   chain, and (if available) stapled OCSP response covering the
   server certificate (Section 13).

6. **Server**: request client certificate via TLS ``CertificateRequest``.

7. **Client**: send TLS ``Certificate`` message containing the
   client's X.509 certificate chain.

8. Both sides verify peer certificates against their configured
   trust anchor and against the cert-status protocol (Sections 4
   and 7).

9. TLS handshake completes; encrypted record layer is now active.

10. Inside the TLS tunnel, PVA's ``CMD_CONNECTION_VALIDATION`` is
    exchanged. The auth-method list now includes ``"x509"``; client
    selects ``"x509"`` and sends an empty auth_data (the certificate
    has already authenticated).

11. ``CMD_CONNECTION_VALIDATED`` indicates success; channel
    operations proceed exactly as PVA.

12. Throughout the connection's lifetime, both endpoints subscribe
    to each other's cert-status PV and tear down the connection if
    the status transitions to a non-good state (Section 7).

2.3. What SPVA Provides Beyond PVA
----------------------------------

- **Mutual cryptographic authentication**: both endpoints have
  X.509 certificates verified against trust anchors.
- **Encrypted transport**: TLS 1.3 ChaCha20-Poly1305 or AES-GCM.
- **Tamper detection**: TLS 1.3 record MACs.
- **Live revocation**: cert-status monitor closes connections on
  revocation/suspension.
- **Service-driven certificate lifecycle**: clients and servers can
  request, renew, and rotate certificates via well-defined RPCs to
  the Certificate Management Service.
- **Identity-bound authorization**: the X.509 Subject's CN+O
  becomes the principal name used in ASG/ACF rules.

2.4. What SPVA Does Not Change
------------------------------

- Beacon format, search format, CMD_* command codes, sub-commands,
  type system, IOID handling, segmentation rules — all unchanged
  from PVA.
- Default UDP broadcast port 5076 — unchanged.
- The PV namespace — SPVA endpoints expose the same PVs as plain
  PVA endpoints; SPVA is a transport layer, not a name layer.

----

3. Transport Layer (TLS 1.3)
============================

3.1. TLS Version
----------------

SPVA endpoints SHALL use TLS 1.3 (:rfc:`8446`) exclusively for the
record-layer transport. Implementations MUST refuse TLS 1.2 or
earlier; sites with TLS 1.2-only infrastructure SHALL upgrade. The
rationale for the strict version requirement is that TLS 1.3
mandates Authenticated Encryption with Associated Data (AEAD)
ciphers and removes the cipher-mix vulnerabilities of earlier
versions.

3.2. Default Port
-----------------

SPVA listens on TCP port 5076 by default (configurable via
``EPICS_PVAS_TLS_PORT``). This collides intentionally with PVA's
UDP broadcast port 5076 — TCP and UDP have separate port spaces and
both listeners coexist on a single host.

3.3. Cipher Suites
------------------

SPVA endpoints MUST support and SHOULD prefer the following TLS 1.3
cipher suites:

- ``TLS_AES_256_GCM_SHA384``
- ``TLS_CHACHA20_POLY1305_SHA256``
- ``TLS_AES_128_GCM_SHA256``

Implementations MUST NOT enable export-grade or null-encryption
cipher suites. Implementations SHOULD disable any cipher suite not
in the recommended TLS 1.3 set.

3.4. Key Exchange Groups
------------------------

SPVA endpoints MUST support the following TLS 1.3 named groups for
key exchange:

- ``x25519`` (REQUIRED)
- ``secp256r1`` (REQUIRED)
- ``secp384r1`` (RECOMMENDED)

3.5. Signature Algorithms
-------------------------

SPVA certificates MAY use any of these signature algorithms:

- ``rsa_pss_rsae_sha256``, ``rsa_pss_rsae_sha384``, ``rsa_pss_rsae_sha512``
- ``ecdsa_secp256r1_sha256``, ``ecdsa_secp384r1_sha384``
- ``ed25519``

PKCS#1 v1.5 RSA signatures are deprecated by TLS 1.3 and SHOULD NOT
be used in newly-issued SPVA certificates.

3.6. Server Name Indication (SNI)
---------------------------------

SNI is not currently supported. Clients MUST NOT send the TLS
``server_name`` extension. Servers MUST ignore it if received.

Server authenticity is established by chain validation against the
configured trust anchor (Section 4.6), cert-status PV monitoring
(Section 7), and (when offered) OCSP stapling (Section 13).

3.7. Session Resumption
-----------------------

Session resumption is not currently supported. Every TLS connection
performs a full handshake. Servers MAY emit ``NewSessionTicket``
messages; clients MUST discard them and MUST NOT present a session
ticket or PSK on a subsequent connection.

3.8. 0-RTT (Early Data)
-----------------------

SPVA endpoints MUST NOT send 0-RTT (early data, :rfc:`8446` Section
2.3). The replay-vulnerability of 0-RTT is incompatible with PVA's
side-effect-bearing operations (PUT, RPC, PROCESS).

3.9. ALPN
---------

SPVA does not currently use TLS Application-Layer Protocol
Negotiation (:rfc:`7301`). The protocol inside the TLS tunnel is
determined by the connecting port (5076 = SPVA). A future extension
MAY introduce an ``"spva/2"`` ALPN identifier.

----

4. X.509 Certificates and Trust
================================

4.1. Certificate Format
-----------------------

SPVA endpoints use X.509 v3 certificates (:rfc:`5280`). Section
4.2 lists the standard PKIX extensions every SPVA certificate
carries; Section 4.3 specifies the SPVA-specific custom extension.

4.1.1. PKCS#12 Keychain Profile
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

SPVA deployments commonly distribute endpoint identity and trust
material as a PKCS#12 (``.p12`` / ``.pfx``) keychain file. For
interoperability with the current C++ and Java implementations, an
SPVA keychain file SHALL use the following bag-level profile:

- The endpoint's private key SHALL be stored in a
  ``pkcs8ShroudedKeyBag``.
- The endpoint's leaf certificate SHALL be stored in a ``certBag``.
- The private-key bag and the matching leaf-certificate bag SHALL
  carry the same ``localKeyId`` attribute so the pair is
  unambiguously linked.
- Additional issuer / intermediate / trust-anchor certificates MAY
  be present as additional ``certBag`` entries.
- A file used as an endpoint identity file MUST contain the private
  key and the matching leaf certificate. A trust-only file MAY omit
  the private key and contain only certificate bags.

The bags MAY be distributed across one or more ``AuthenticatedSafe``
containers. The interoperable layout used by OpenSSL, PVXS, PVACMS,
and Java ``keytool`` places the ``pkcs8ShroudedKeyBag`` in one safe
and the certificate bags in another safe.

Additional bag attributes are required for interoperability:

- ``friendlyName`` SHOULD be present on the private-key bag and on
  the matching leaf-certificate bag. It is the bag alias used by
  Java tooling. SPVA does not assign any protocol meaning to the
  alias string itself.
- Certificate bags that represent trust-only certificates (that is,
  certificate bags without a matching ``localKeyId``) SHOULD carry
  the Java-defined ``oracle-jdk-trustedkeyusage`` attribute so Java
  keystore tooling treats them as trusted certificates.

Ordering rules:

- When a certificate chain is present, the leaf certificate is the
  certificate linked to the private key by ``localKeyId``.
- Additional chain certificates SHOULD be ordered from the issuing
  intermediate certificate toward the trust anchor.

Java considerations:

- A Java implementation MUST NOT depend on any fixed alias name. It
  SHALL inspect all aliases in the keystore.
- A key entry intended for Java consumption SHOULD carry its
  certificate chain in the same PKCS#12 file.
- If a deployment uses an empty password for the PKCS#12 file, Java
  loaders SHOULD pass the empty string password rather than ``null``;
  a ``null`` password can cause encrypted certificate safes to be
  skipped.

4.2. Standard PKIX Extensions
-----------------------------

REQUIRED. Every SPVA certificate MUST contain:

- **Basic Constraints** (``id-ce-basicConstraints``): ``CA = FALSE``
  for entity certificates; ``CA = TRUE`` for Certification Authority
  certificates.
- **Key Usage** (``id-ce-keyUsage``): for entity certificates,
  the bits ``digitalSignature`` and ``keyEncipherment`` (or
  ``keyAgreement`` for Elliptic Curve Digital Signature Algorithm)
  MUST be set; ``keyCertSign`` MUST NOT be set.
- **Extended Key Usage** (``id-ce-extKeyUsage``): MUST include
  ``id-kp-serverAuth`` for server certificates and
  ``id-kp-clientAuth`` for client certificates. A certificate
  intended for both roles MUST include both Extended Key Usage
  values.
- **Authority Key Identifier** (``id-ce-authorityKeyIdentifier``):
  REQUIRED for entity certificates.
- **Subject Key Identifier** (``id-ce-subjectKeyIdentifier``):
  REQUIRED.

OPTIONAL.

- **Subject Alternative Name** (``id-ce-subjectAltName``): MAY be
  omitted entirely. When present, see Section 4.5 for SPVA's
  handling of its entries.

4.3. SPVA Custom X.509 Extension
--------------------------------

SPVA defines one custom X.509 extension:

.. table:: SPVA custom X.509 extension
   :widths: auto

   +---------------------+----------------------------+
   | Extension name      | Object Identifier          |
   +=====================+============================+
   | SPvaCertStatusURI   | ``1.3.6.1.4.1.37427.1``    |
   +---------------------+----------------------------+

OPTIONAL. Issued non-critical (``critical = FALSE``). Carries an
``IA5String`` value (:rfc:`5280` Section 4.2.1.6) holding a PV
name. The sub-arc is not currently IANA-registered.

Value: the PV name where the certificate-status PV for this
certificate is published. Default form
``<cert_pv_prefix>:STATUS:<issuer_id>:<serial>`` (Section 7.1); the
extension's IA5String is authoritative.

A certificate MUST carry this extension if it participates in any
of:

- Live revocation (Section 7).
- ``SCHEDULED_OFFLINE`` connection suspension (Section 8.4).
- ``PENDING_RENEWAL`` past-due connection-state behaviour
  (Section 8.5).
- Renewal-due hint delivery (``renewal_due``; Section 8.5).

A certificate without this extension MUST NOT be subscribed to.
Connections involving such a certificate proceed without
certificate-status monitoring; revocation, suspension, and
renewal-hint mechanisms do not apply to that certificate.

A non-SPVA-aware verifier MAY ignore the extension. A certificate
carrying it remains a fully-conformant X.509 v3 certificate per
:rfc:`5280` and is usable by non-SPVA software, provided the
Extended Key Usage and Subject Alternative Name fields are
appropriate for the non-SPVA use.

4.4. Subject Distinguished Name
-------------------------------

The Subject DN of an SPVA certificate identifies the principal. SPVA
constrains the DN form to:

::

    Subject:  CN=<principal-name>, O=<org-name>[, OU=<unit>]

The ``CN`` (Common Name) is the principal's identity string. For
host-bound principals, CN MUST default to the fully-qualified DNS
name. For user-bound principals, CN MUST default to the username.

The ``CN`` value is used as the principal name in authorization
predicates (Section 11).

4.5. Subject Alternative Name
-----------------------------

A certificate's primary identity in SPVA is its Subject
Distinguished Name (Section 4.4). Subject Alternative Name (SAN)
entries are supplementary identity metadata the certificate
carries; SPVA reads them at the TLS layer, exposes them to the
application layer as connection-time peer credentials, and matches
them against authorization rules (Section 11).

SPVA does NOT use the SAN at TLS-handshake time as a hostname-vs-
certificate match (no Server Name Indication / Section 3.6). The
SAN is informational at the transport layer and authoritative at
the authorization layer.

The two SAN types SPVA recognises:

- ``dNSName`` — a Domain Name System (DNS) host name. Stored in
  the certificate and exposed to the application via the
  per-connection peer-credentials structure. An access security
  configuration file (ACF) rule MAY match against a ``dNSName``
  entry to grant or deny access (Section 11).
- ``iPAddress`` — an IPv4 or IPv6 address. Same handling as
  ``dNSName``: stored, exposed, available for ACF matching.

A certificate MAY contain multiple ``dNSName`` and/or
``iPAddress`` SAN entries (for example: a server that operates
under multiple hostnames or on a multi-homed host). Client
certificates' SAN entries are read with the same handling; the
``rfc822Name`` (email) and ``otherName`` SAN types MAY be
included for site-specific principal-naming conventions but are
not consumed by the standard ACF rule set.

The CCR (Section 9) lets the requesting principal supply SAN
entries at issuance time; the Certificate Management Service
embeds them in the issued certificate verbatim subject to
site-policy filtering.

4.6. Trust Anchors
------------------

Each SPVA endpoint SHALL be configured with one or more trust
anchors — X.509 certificates with ``CA = TRUE`` that the endpoint
considers authoritative for verifying peer certificates. The trust
anchors are typically loaded from the keychain file
(``EPICS_PVA_TLS_KEYCHAIN``).

A peer certificate is **path-validated** per :rfc:`5280` Section 6:
the certificate chain from the peer's leaf certificate up to a
configured trust anchor MUST be cryptographically valid (each
certificate's signature verifies against its issuer's public key)
and MUST NOT contain any revoked or expired certificate.

4.7. Validity Period: Cryptographic vs Operational
--------------------------------------------------

SPVA distinguishes two independent notions of certificate validity.

**Cryptographic validity** is the property an X.509 verifier checks
against the certificate alone: the current time falls within
``[notBefore, notAfter]``, the chain is well-formed, and signatures
verify. The detailed rules are specified in :rfc:`5280`.

**Operational validity** is the property an SPVA endpoint checks
against the live cert-status protocol of Section 7. It is determined
by the most recent cert-status report's ``status`` field, classified
by Section 8.4 into one of the connection-state classes
(``GOOD``, ``SUSPENDED``, ``UNKNOWN``, ``BAD``). Only ``GOOD``
permits unrestricted SPVA traffic.

The two notions are deliberately decoupled. ``notAfter`` MAY be
set very long (years) without weakening the security posture
because revocation, suspension, and renewal are signalled in real
time over the cert-status channel rather than by waiting for
``notAfter`` to elapse. The conventional "use short ``notAfter``"
advice that applies to PKI deployments without a live cert-status
channel does not apply to SPVA.

This decoupling lets an SPVA deployment combine a long
cryptographic lifetime with a short operational renewal cadence.
A typical configuration is a cryptographic lifetime of years
(``notAfter`` set well into the future) paired with a short
``renew_by`` cadence (Section 4.7.3) — for example 24 hours, or
whatever cadence site IT policy requires. Each renewal cycle
re-authenticates the certificate-holder and extends the next
``renew_by`` horizon within the same long cryptographic window,
without re-issuing the keypair or certificate on each cycle.

The same decoupling lets an SPVA deployment apply on/off
operational validity to a long-lived certificate. The Certificate
Management Service MAY hold the certificate's ``notAfter`` years in
the future while toggling the cert-status between ``VALID`` and
``SCHEDULED_OFFLINE`` (Section 4.7.4) on a schedule — for example,
valid only during configured shift windows, or invalid during a
planned facility downtime. The operational state changes purely
through cert-status transitions over the live channel; the
certificate itself is not re-issued and ``notAfter`` is not
modified.

4.7.1. Cryptographic Validity
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Cryptographic validity is bounded by the certificate's
``notBefore`` and ``notAfter`` fields. Outside this interval any
:rfc:`5280` verifier MUST reject the certificate independently of
any cert-status check. The issuer sets these fields per its
configured policy; sites are expected to set the configured
cryptographic lifetime to their preferred value, which MAY be much
longer than any one implementation's default. (Configuration of the
reference implementation is documented in
:doc:`/programmers-ref/cert-management`.)

Sites SHOULD treat ``notAfter`` as the **rotation horizon** — the
maximum time the same keypair MAY remain in service — not as the
operational expiry. The short-cycle rotation that IT policy
typically requires is provided separately by the renewal hint
(``renewal_due``, Section 4.7.3): an endpoint observing
``renewal_due = true`` re-authenticates promptly so the Service can
move ``renew_by`` forward and clear the hint while the same
certificate and keypair remain in service within the same long
``notAfter`` window.

There is no protocol-level upper bound on ``notAfter``. A site MAY
configure multi-year ``notAfter`` values where its key-protection
policy (hardware security module, sealed keychain, or equivalent)
warrants it. Sites with weaker key protection SHOULD configure
shorter ``notAfter`` values to bound the impact of a key compromise
that goes undetected long enough to outlast cert-status revocation
propagation.

For all other rules governing cryptographic validity (path
construction, name constraints, policy mapping, signature
verification), see :rfc:`5280`.

4.7.2. Operational Validity
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Operational validity is determined by the most recent cert-status
report received over the cert-status PV (Section 7). The report's
``status`` field classifies the certificate into one of four
connection-state classes — ``GOOD``, ``SUSPENDED``, ``UNKNOWN``,
or ``BAD`` — each with specific per-connection effects. The
authoritative mapping from cert-status states to connection-state
classes and the effects of each class are specified in
Section 8.4. The state definitions are in Section 8.2.

A separate condition arises when no fresh status is available —
either because the endpoint has not yet received any report, or
because the Certificate Management Service has become unreachable
and stopped delivering updates. The ``status_valid_until_date``
field of the most recent report defines a **freshness horizon**:
until that instant the last received status MAY continue to be
used as the operational status, even if the Service is currently
silent. Once ``status_valid_until_date`` has passed, the cached
status MUST be treated as ``UNKNOWN`` until a fresh report arrives,
regardless of what the cached ``status`` value was.

Worked example: a client receives ``status = VALID`` with
``status_valid_until_date`` set 30 minutes in the future, then
loses contact with the Certificate Management Service. For the
next 30 minutes the client still treats the certificate as
operationally ``GOOD`` (the cached status is still within its
freshness horizon). At the 30-minute mark, with no fresh report
received, the client transitions the certificate to ``UNKNOWN``
until contact is restored and a fresh report arrives.

The Certificate Management Service publishes
``status_valid_until_date`` per its configured freshness duration.
(Configuration of the reference implementation is documented in
:doc:`/programmers-ref/cert-management`.) Endpoints obtain
fresh status by maintaining a live cert-status subscription
(Section 7.3) or, if subscription is unavailable, by re-querying.

4.7.3. Renewal Cadence (``renew_by``, ``renewal_due``, and ``PENDING_RENEWAL``)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Independent of ``notAfter``,
the protocol supports a short renewal cadence under a long
cryptographic envelope. The renewal cadence is conveyed by three
distinct on-the-wire elements of the cert-status protocol
(Section 7), each with its own semantics. They MUST NOT be
conflated.

``renew_by`` is a ``UInt64`` field of the cert-status
PVStructure (Section 7.2). It carries the time at which renewal
is due. The Certificate Management Service publishes ``renew_by``
per its configured renewal cadence; the certificate-holder SHOULD
use ``renew_by`` to plan its renewal request.

``renewal_due`` is a ``Bool`` field of the cert-status
PVStructure (Section 7.2) and is the **renewal hint**. The
Certificate Management Service publishes ``renewal_due = true``
once the current time is more than halfway between the last status
update time and the current ``renew_by`` time. While
``renewal_due = true`` and the ``status`` field remains ``VALID``,
the certificate is still operationally valid (connection-state
class ``GOOD``, Section 8.4) and SPVA traffic proceeds normally;
the flag is purely advisory. A certificate-holder observing
``renewal_due = true`` SHOULD initiate a renewal Certificate
Creation Request (Section 9.4) promptly so that renewal completes
before the past-due status is reported.

Each cert-status publication that moves ``renew_by`` forward is
itself a new cert-status update. It therefore resets the reference
"last status update time" used by the halfway-point calculation and
allows a fresh ``renewal_due`` hint to be emitted later in the next
renewal interval.

``PENDING_RENEWAL`` is a ``certstatus_t`` value (Section 8.3)
returned in the ``status`` field. The Certificate Management
Service publishes ``status = PENDING_RENEWAL`` once the renewal
date has passed *and* the certificate-holder has not completed a
renewal in time; the renewal is past-due. ``PENDING_RENEWAL`` is
semantically parallel to ``PENDING_APPROVAL``: both are
SUSPENDED-class states (Section 8.4) that name the action the
holder MUST take to return to ``VALID`` — for ``PENDING_RENEWAL``,
complete a renewal; for ``PENDING_APPROVAL``, obtain administrator
approval. The per-connection effects of the SUSPENDED class are
specified in Section 8.4.

The intended sequence under nominal operation is therefore:

1. ``status = VALID``, ``renewal_due = false`` — certificate is
   operationally valid; no action required.
2. Time passes the halfway point between the last status update and
   ``renew_by``. The Certificate Management Service
   publishes ``renewal_due = true``; ``status`` remains ``VALID``.
   The certificate-holder, observing the hint, initiates renewal.
3. The holder re-authenticates successfully. The next cert-status
   report carries ``status = VALID`` with ``renewal_due = false``
   and a fresh ``renew_by`` further in the future. The certificate
   and keypair are unchanged, and operation continues
   uninterrupted. Because that publication is itself the new last
   status update, it resets the halfway-point calculation for the
   next ``renewal_due`` hint.

``PENDING_RENEWAL`` is the off-nominal path taken only when step 2
does not result in a completed renewal before the Service
escalates: the renewal is past-due, the certificate is suspended
(connection-state class ``SUSPENDED``, Section 8.4), and the
holder MUST complete a renewal to return the certificate to
``VALID``. A holder in ``PENDING_RENEWAL`` MAY do this by
submitting a renewal Certificate Creation Request again; on success
the Service returns the certificate's status to ``VALID`` and the
connection-state class returns from ``SUSPENDED`` to ``GOOD``.

When renewal is submitted as a direct Certificate Creation Request,
that request MUST be sent without Transport Layer Security (TLS).
Otherwise the suspended secure session can prevent the renewal
request from reaching the Certificate Management Service. Tools that
exist specifically to perform authenticator-driven Certificate
Creation Requests, such as ``authnstd`` and the other ``authnXXX``
tools, automatically disable TLS for those renewal requests.

``renew_by`` is a per-certificate, authenticator-set policy time,
not a fixed global threshold. It is distinct from
``status_valid_until_date`` (which controls cert-status response
freshness, Section 7.2) and from ``notAfter`` (which is the
cryptographic expiry, Section 4.7.1). A ``renew_by`` value of
zero disables the renewal cadence: no ``renewal_due`` hint is
emitted and the certificate does not transition to
``PENDING_RENEWAL``. A Certificate Management Service MAY normalize
``renew_by == notAfter`` to zero, because renewing at cryptographic
expiry provides no useful operational renewal window.

Worked example: a site requires 24-hour renewal re-authentication but wants to
avoid re-engaging the full certificate-issuance flow daily.
Certificates are issued with a 10-year ``notAfter`` and a
``renew_by`` 24 hours in the future. After roughly 12 hours (more
than halfway from the last status update to ``renew_by``) the
Certificate Management Service publishes ``renewal_due = true``
(status still ``VALID``); the certificate-holder requests a
renewal, re-authenticates successfully, and the Service clears the
hint and publishes a fresh 24-hour ``renew_by`` for the same
certificate. The connection continues without interruption. Only if
the holder fails to renew before the Service escalates does the
status transition to ``PENDING_RENEWAL`` and connections enter the
SUSPENDED class until renewal completes.

4.7.4. Scheduled Validity (SCHEDULED_OFFLINE)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Independent of ``notAfter``, the protocol
permits the operational validity of a certificate to be gated
against a schedule. At configured times the Certificate Management
Service publishes ``status = SCHEDULED_OFFLINE`` (mapped to the
SUSPENDED connection-state class, Section 8.4); at other
configured times it publishes ``status = VALID``. The certificate
itself is not re-issued, its ``notAfter`` is not modified, and its
keypair is not changed; only the live cert-status state changes.

This mechanism supports two common deployment patterns:

- **Shift-based access.** A certificate issued to an account that
  is only authorised to operate during specific shift windows can
  be left ``VALID`` during those windows and transitioned to
  ``SCHEDULED_OFFLINE`` outside them. SPVA traffic is permitted
  on-shift and suspended off-shift without operator intervention
  and without certificate re-issuance.
- **Planned facility downtime.** Ahead of a scheduled outage,
  the Certificate Management Service transitions affected
  certificates to ``SCHEDULED_OFFLINE`` for the duration of the
  downtime, then back to ``VALID`` when normal operation resumes.

While ``SCHEDULED_OFFLINE`` is in effect the certificate's
connections behave as defined in Section 8.4 for the SUSPENDED
class: TLS sockets remain open but SPVA channel operations are
paused; plain-TCP fallback (where negotiated) remains usable.

Worked example: a beam-line operator account holds a certificate
issued with a 5-year ``notAfter``. The site policy authorises
operation only during weekday day-shift hours. The Certificate
Management Service publishes ``status = VALID`` from 08:00–18:00
Monday through Friday and transitions to ``SCHEDULED_OFFLINE`` at
18:00 on each weekday and all day on weekends. Operator
workstations using this certificate see SPVA traffic permitted
during shift hours and suspended otherwise; the certificate itself
is unchanged across all such transitions for its full 5-year
cryptographic lifetime.

4.8. Key Algorithms
-------------------

End-entity SPVA certificates MAY use:

- RSA with 2048-bit or larger modulus.
- ECDSA with P-256 or P-384 curves.
- Ed25519.

CA certificates SHOULD use 4096-bit RSA or P-384 ECDSA for added
security margin.

----

5. Connection Validation with TLS
=================================

5.1. Order of Operations
------------------------

When an SPVA client connects to an SPVA server:

1. TCP three-way handshake to the SPVA server port.
2. TLS 1.3 mutual-authentication handshake (Section 3) with peer
   certificate chain validation against the configured trust
   anchor (Section 4.6). A failed chain validation MUST cause TLS
   handshake abort with a TLS Alert.
3. PVA ``CMD_CONNECTION_VALIDATION`` (PVA Section 6) is exchanged
   inside the TLS tunnel.

Cert-status monitoring (Section 7) runs asynchronously alongside
the connection. If the peer certificate carries the
``SPvaCertStatusURI`` extension (Section 4.3), each side installs
a cert-status subscription against the named PV; the subscription's
updates drive the connection's per-status behaviour as specified
in Section 8.4. If the extension is absent, no cert-status
monitoring is installed and the connection runs without it.

5.2. Auth-Method List Includes ``x509``
---------------------------------------

The server's ``CMD_CONNECTION_VALIDATION`` (PVA Section 6.1) lists
``"x509"`` first in its supported authentication mechanisms. The
client selects ``"x509"`` in its
``CMD_CONNECTION_VALIDATION`` response (PVA Section 6.2).

The ``auth_data`` field for ``x509`` is empty (zero-length): the
TLS-handshake certificate already carries the identity, no further
data needs to be exchanged.

5.3. Identity Extraction
------------------------

After successful TLS handshake, both endpoints extract the peer's
principal identity from the peer certificate's Subject DN (Section
4.4). The identity is normalised to the form ``CN=<x>, O=<y>[,
OU=<z>]`` for use in:

- Authorization rule lookup (Section 11).
- Cert-status monitor key (issuer + serial; not the DN directly).
- Audit logs (typically the full DN string).

----

6. Authentication
=================

6.1. SPVA Authentication: ``x509``
----------------------------------

SPVA uses one authentication mechanism: ``x509``. The peer
certificate presented during the TLS handshake is the
authenticator. The PVA ``CMD_CONNECTION_VALIDATION`` exchange
(Section 5.2) carries ``auth_data = empty`` for the ``x509``
mechanism.

PVA's ``CMD_AUTHNZ`` (command 5; PVA Section 6.4) is not used by
SPVA. Implementations MUST tolerate receiving it (the PVA spec
permits it for mechanism continuation) but MUST NOT depend on it.

6.2. Certificate Issuance Authenticators
----------------------------------------

Before an endpoint can present an ``x509`` certificate, the
certificate must have been issued. The Certificate Management
Service (Section 10) issues certificates in response to a
Certificate Creation Request (Section 9). The CCR carries an
authenticator-specific verifier in its ``verifier`` sub-structure
that the Service uses to verify the requesting principal's
identity at issuance time.

Three issuance authenticators are defined:

- ``authnstd`` — issuance with administrator approval. The CCR is
  submitted without external credential proof. The Service issues
  the certificate in ``PENDING_APPROVAL`` state (Section 8.2). The
  certificate becomes ``VALID`` only when an administrator
  performs a PUT to the certificate's status PV.
- ``authnkrb`` — Kerberos. The principal obtains a GSS-API token
  for the Service's principal (output of
  ``gss_init_sec_context``) plus a Message Integrity Check; both
  travel in the CCR as ``verifier.token`` and ``verifier.mic``.
  The Service verifies via ``gss_accept_sec_context`` against its
  service keytab.
- ``authnldap`` — LDAP. The principal performs an LDAP bind
  locally to prove identity, then signs the CCR contents with the
  principal's own private key. The signature travels in the CCR
  as ``verifier.signature``. The Service verifies the signature
  against the LDAP-bound principal's public key.

The CCR submission uses PVA RPC (Section 9). The issuance
authenticators are not SPVA-protocol messages on their own; they
are CCR ``verifier`` payloads.

----

7. Certificate-Status Monitoring
================================

7.1. Cert-Status PV Naming
--------------------------

The Certificate Management Service publishes a cert-status PV per
issued certificate. The PV name follows the pattern:

::

    <prefix>:STATUS:<issuer-skid>:<cert-serial>

where:

- ``<prefix>`` is the configurable cert-PV prefix (default
  ``CERT``); set via ``EPICS_PVAS_CERT_PV_PREFIX``.
- ``<issuer-skid>`` is the first 8 hexadecimal characters of the
  Subject Key Identifier of the certificate's issuer (the issuing
  Certification Authority).
- ``<cert-serial>`` is the certificate serial number rendered in
  decimal and left-padded with leading zeroes to a width of 20
  characters.

Given the configured cert-PV prefix, this deterministic naming
allows any party with a certificate to construct the corresponding
cert-status PV name without any further out-of-band lookup.

7.2. Cert-Status PVStructure Schema
-----------------------------------

The cert-status PV is published with type ID
``epics:nt/NTEnum:1.0``. Its value is a PVStructure with the
following fields:

::

    structure (type ID "epics:nt/NTEnum:1.0")
        struct      value                # NTEnum: cert-status state
            int32       index            #   index into choices
            string[]    choices          #   {UNKNOWN, VALID, PENDING,
                                         #    PENDING_APPROVAL,
                                         #    PENDING_RENEWAL,
                                         #    SCHEDULED_OFFLINE,
                                         #    EXPIRED, REVOKED}
        struct      alarm                # NTEnum-standard alarm
        struct      timeStamp            # NTEnum-standard timestamp
        struct      display
            string      description
        u64         serial               # certificate serial number
        string      state                # cert-status state name
                                         #  (= choices[value.index]; convenience)
        u64         renew_by             # time at which renewal is due
                                         #  (UTC seconds; Section 8.5)
        bool        renewal_due          # renewal-due hint: true once
                                         #  now is at or beyond the halfway
                                         #  point between the last cert-status
                                         #  update time and renew_by
                                         #  (Section 8.5)
        struct      ocsp_status          # NTEnum: OCSP status
            int32       index            #   index into choices
            string[]    choices          #   {OCSP_CERTSTATUS_GOOD,
                                         #    OCSP_CERTSTATUS_REVOKED,
                                         #    OCSP_CERTSTATUS_UNKNOWN}
        string      ocsp_state           # OCSP status state name
        string      ocsp_status_date
        string      ocsp_certified_until
        string      ocsp_revocation_date
        u8[]        ocsp_response        # raw OCSP response (RFC 6960);
                                         #  empty if not provided
        string      pvacms_node_id       # Certificate Management Service
                                         #  cluster member that produced
                                         #  this update
        struct[]    schedule             # SCHEDULED_OFFLINE windows
                                         #  (matches CCR.schedule, Section 9.1)
            string      day_of_week
            string      start_time
            string      end_time
        struct[]    san                  # Subject Alternative Name entries
                                         #  carried in the certificate
                                         #  (matches CCR.san, Section 9.1)
            string      type
            string      value

The cert-status state values (the contents of ``value.choices``)
are normative and exactly: ``UNKNOWN``, ``VALID``, ``PENDING``,
``PENDING_APPROVAL``, ``PENDING_RENEWAL``, ``SCHEDULED_OFFLINE``,
``EXPIRED``, ``REVOKED``. Their semantics are in Section 8.2;
their connection-state effects are in Section 8.4.

The ``ocsp_response`` field is populated when the Certificate
Management Service provides an OCSP-style status response;
otherwise it is empty (zero-length byte array). Section 13 covers
OCSP stapling separately.

A response whose ``timeStamp`` plus the configured cert-status
validity duration has passed MUST be treated as ``UNKNOWN`` per
Section 8.4.

7.3. Subscription Flow
----------------------

If the peer certificate carries the ``SPvaCertStatusURI``
extension (Section 4.3), the endpoint reads the PV name from the
extension and subscribes to that PV using PVA ``CMD_MONITOR``
(PVA Section 9.5) against the publishing PVA server. The
subscription runs for the lifetime of the connection.

Each cert-status update drives the connection's state per the
mapping in Section 8.4. Updates and connection-state transitions
are asynchronous; the connection is not held open or torn down
synchronously with respect to handshake completion.

When a cert-status update places the peer in the ``SUSPENDED``
class, the TLS socket remains open but the secure PVA session is not
fully operational. Monitor delivery is paused until the peer returns
to ``GOOD``. ``GET`` operations MAY continue. ``PUT`` and ``RPC``
operations MUST be rejected while the peer remains suspended. A
connection that has not yet completed secure channel admission MUST
enter ``TcpOnly``, continue status monitoring, and upgrade to TLS
when the peer's cert-status returns to ``GOOD``.

7.3.1. Pre-Admission Give-Up Rule
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A TLS connection that has completed the TLS handshake but has NOT
yet completed secure channel admission (the connection is in the
"pre-Validated" state) is subject to a **give-up rule**: if the
first authoritative cert-status delivery for the local entity
certificate or the peer's certificate resolves to a class other
than ``GOOD``, the endpoint SHALL abandon the TLS attempt for that
connection rather than waiting indefinitely for the status to
become ``GOOD``.

The give-up rule applies at each of the three admission gates where
a pre-Validated connection waits for cert-status:

- The **local-cert gate**, where the connection waits for the local
  TLS context to reach ``TlsReady`` (own cert status ``GOOD``).
- The **client peer-cert gate**, where a client connection waits
  for the peer's cert-status to become ``GOOD`` before creating
  channels.
- The **server peer-cert gate**, where a server connection waits
  for the peer's cert-status to become ``GOOD`` before completing
  connection validation.

On give-up, the endpoint SHALL:

1. Tear down the pre-Validated TLS connection.
2. Return attached channels to the searching state so they may
   re-resolve over plain TCP.
3. Log the give-up at WARN level, including the peer identity and
   the non-``GOOD`` cert-status that triggered the give-up.

The give-up rule does NOT apply to connections that have already
completed secure channel admission (state ``Validated`` or later).
For those connections, the existing live-transition rules of
Section 8.4 apply — ``SUSPENDED`` keeps the TLS socket open and
pauses operations; ``BAD`` tears down the connection.

The give-up rule does NOT introduce a timeout. If no cert-status
delivery arrives at all (the Certificate Management Service is
unreachable and no cached status exists), the pre-Validated
connection continues to wait. A bounded timeout for "no status
delivery" is out of scope of this specification.

The cached-status fast path (Section 7.4) reduces the frequency
of the give-up case: a process that has previously observed
``VALID`` for its own certificate (and the disk-cached status is
still within its freshness horizon) boots directly into
``TlsReady`` and never enters the optimistic ``TcpReady`` window.
The give-up rule fires only when the cache miss path is taken and
the first authoritative delivery is non-``GOOD``.

``UNKNOWN`` is distinct from both ``SUSPENDED`` and ``BAD``. It means
the endpoint lacks a current usable status decision, either because no
status report has yet arrived or because the last report has aged past
``status_valid_until_date``. ``UNKNOWN`` therefore has two operational
cases:

- before secure admission completes, the endpoint MUST treat TLS as not
  yet ready. If plain-PVAccess fallback was negotiated, the endpoint
  MAY continue in that plain-TCP mode while waiting for status to
  resolve to ``GOOD``; otherwise it waits for a fresh cert-status
  update and does not complete secure channel admission.
- after a TLS session is already live, a transition to ``UNKNOWN`` MUST
  preserve the underlying TLS socket and treat the session as
  recoverable. Monitor delivery is paused until status recovers; the
  endpoint MUST NOT treat the condition as terminal solely because the
  Certificate Management Service is silent.

If the peer certificate does not carry the ``SPvaCertStatusURI``
extension, no subscription is installed and the connection runs
without cert-status monitoring (Section 4.3).

7.4. Cert-Status Cache
----------------------

To avoid each fresh SPVA connection spawning a new cert-status
subscription, endpoint runtimes maintain a per-process cache of
cert-status subscriptions, keyed by ``(issuer-skid, cert-serial)``.
A new SPVA connection that names a peer certificate already in the
cache reuses the existing subscription.

The cache MAY persist cert-status responses to disk (configurable
via ``EPICS_PVA_TLS_STATUS_CACHE_DIR``) so a process restart does
not require re-subscribing. Cached entries are honored only until
their ``status_valid_until_date`` expires; beyond that, fresh
subscription is required.

----

8. Certificate Lifecycle States
================================

8.1. State Diagram
------------------

::

    [CCR submission]
            │
            │  (the issuer evaluates whether administrator approval
            │   is required: a non-default authenticator's own verifier
            │   replaces approval; for the default authenticator the
            │   per-usage site policy ``cert_<usage>_require_approval``
            │   may waive approval. See Section 9.x.)
            │
            ├─ approval required
            │      ▼
            │  PENDING_APPROVAL  ──── deny ──► REVOKED  (terminal)
            │      │
            │      │ approve
            │      ▼
            │  ┌───┴────────────────────────────────────────┐
            │  │ The Certificate Management Service         │
            └──┤ publishes the time-based status that the   │
               │ cryptographic clock dictates at the        │
               │ instant of issuance / approval:            │
               │                                            │
               │   PENDING   if now < notBefore             │
               │   VALID     if notBefore ≤ now < notAfter  │
               │   EXPIRED   if now ≥ notAfter   (terminal) │
               └────────────────────────────────────────────┘

    PENDING ──── now reaches notBefore ────► VALID

    From VALID:
            │
            ├─ scheduled pause ─► SCHEDULED_OFFLINE ──► VALID  (resume)
            │                          │
            │                          ├──► REVOKED  (admin revocation)
            │                          │
            │                          └──► EXPIRED  (now reaches
            │                                        notAfter; terminal)
            │
            ├─ admin revoke ─► REVOKED  (terminal)
            │
            ├─ renewal not completed before ``renew_by``
            │  elapsed (Section 8.5)
            │      ▼
            │   PENDING_RENEWAL ──► VALID    (renewal completed)
            │       │           ──► REVOKED  (admin revocation)
            │       │           ──► EXPIRED  (now reaches notAfter;
            │       │                        terminal)
            │
            └─ now reaches notAfter ─► EXPIRED  (terminal)

The Certificate Management Service emits the time-based
transitions ``PENDING → VALID`` (at ``notBefore``) and
``VALID → EXPIRED`` (at ``notAfter``) as courtesy notifications
when the wall clock crosses each boundary for a certificate it
manages. Any client holding a current cert-status response MAY
derive the same transitions locally from the certificate's
``notBefore`` / ``notAfter`` fields without waiting for the
published update.

8.2. State Definitions
----------------------

The cert-status states are lifecycle labels. Each state's
connection-state effect is given by the class mapping in
Section 8.4; it is not duplicated here.

.. table:: SPVA certificate lifecycle states
   :widths: auto

   +------------------------+-----------------------------------------+
   | State                  | Meaning                                 |
   +========================+=========================================+
   | ``UNKNOWN``            | Cert-status authority cannot determine  |
   |                        | current status (e.g. certificate serial |
   |                        | unknown to the authority, no status yet |
   |                        | received, or the last status response   |
   |                        | is no longer current).                  |
   +------------------------+-----------------------------------------+
   | ``PENDING_APPROVAL``   | CCR submitted; awaiting administrator   |
   |                        | approval.                               |
   +------------------------+-----------------------------------------+
   | ``PENDING``            | Time-based status meaning               |
   |                        | ``now < notBefore`` (and all other      |
   |                        | conditions for ``VALID`` hold).         |
   |                        | Certificate is issued and approved but  |
   |                        | not yet cryptographically valid. The    |
   |                        | cert-status authority emits this as a   |
   |                        | courtesy; clients MAY derive it locally |
   |                        | from the certificate.                   |
   +------------------------+-----------------------------------------+
   | ``VALID``              | Time-based status meaning               |
   |                        | ``notBefore ≤ now < notAfter`` and the  |
   |                        | certificate is not revoked, not         |
   |                        | scheduled-offline, and not past-due for |
   |                        | renewal.                                |
   +------------------------+-----------------------------------------+
   | ``PENDING_RENEWAL``    | Renewal date (``renew_by``) has passed  |
   |                        | and the holder has not completed a      |
   |                        | renewal; renewal required to return to  |
   |                        | ``VALID`` (Section 8.5). Parallel to    |
   |                        | ``PENDING_APPROVAL``.                   |
   +------------------------+-----------------------------------------+
   | ``EXPIRED``            | Validity period (``notAfter``) has      |
   |                        | passed. Terminal.                       |
   +------------------------+-----------------------------------------+
   | ``REVOKED``            | Certificate has been revoked. Terminal. |
   +------------------------+-----------------------------------------+
   | ``SCHEDULED_OFFLINE``  | Certificate has been administratively   |
   |                        | paused.                                 |
   +------------------------+-----------------------------------------+

8.3. State Transitions
----------------------

Permitted transitions:

- ``[no entry]`` → ``PENDING_APPROVAL`` (CCR submitted using the
  default authenticator AND the matching site policy
  ``cert_<usage>_require_approval`` is true)
- ``PENDING_APPROVAL`` → ``REVOKED`` (admin denial)
- ``PENDING_APPROVAL`` → ``PENDING`` | ``VALID`` | ``EXPIRED``
  (admin approval; the Certificate Management Service publishes
  whichever time-based status the cryptographic clock dictates at
  the instant of approval — ``PENDING`` if ``now < notBefore``,
  ``VALID`` if ``notBefore ≤ now < notAfter``, ``EXPIRED`` if
  ``now ≥ notAfter``)
- ``[no entry]`` → ``PENDING`` | ``VALID`` | ``EXPIRED``
  (CCR issued without a ``PENDING_APPROVAL`` step: either a
  non-default authenticator successfully verified the request,
  or the default authenticator's matching
  ``cert_<usage>_require_approval`` policy is false; the Service
  publishes whichever time-based status the cryptographic clock
  dictates at issuance per the rule above)
- ``PENDING`` → ``VALID`` (auto, time-based, when ``now`` reaches
  ``notBefore``; emitted by the Service as a courtesy and
  derivable by any client holding the certificate)
- ``VALID`` → ``REVOKED`` (admin revocation)
- ``VALID`` → ``SCHEDULED_OFFLINE`` (scheduled pause; schedule may
  be defined by the holder in the CCR or set/modified/removed by an
  administrator)
- ``SCHEDULED_OFFLINE`` → ``VALID`` (scheduled resume)
- ``SCHEDULED_OFFLINE`` → ``REVOKED`` (admin revocation while
  paused)
- ``VALID`` → ``PENDING_RENEWAL`` (auto, when the renewal date
  ``renew_by`` has passed and the holder has not completed a
  renewal)
- ``PENDING_RENEWAL`` → ``VALID`` (renewal completed)
- ``PENDING_RENEWAL`` → ``REVOKED`` (admin revocation while
  renewing)
- ``VALID``, ``PENDING_RENEWAL``, or ``SCHEDULED_OFFLINE`` →
  ``EXPIRED`` (auto, time-based, when ``now`` reaches
  ``notAfter``; emitted by the Certificate Management Service as
  a courtesy and derivable by any client holding the certificate)

8.4. Cert-Status to Connection-State Mapping
--------------------------------------------

Each cert-status state maps to one of four *status classes*. A
status class drives the per-connection behaviour the endpoint
applies for the affected peer:

.. table:: Status-class mapping
   :widths: auto

   +------------------------+-------------+-------------------------------------------+
   | Cert status            | Class       | Connection-state effect                   |
   +========================+=============+===========================================+
   | ``VALID``              | GOOD        | TLS connection ready; SPVA traffic        |
   |                        |             | proceeds normally.                        |
   +------------------------+-------------+-------------------------------------------+
   | ``SCHEDULED_OFFLINE``  | SUSPENDED   | TLS socket kept open; SPVA channel        |
   |                        |             | monitor delivery paused; ``GET`` MAY      |
   |                        |             | continue; ``PUT`` and ``RPC`` MUST be     |
   |                        |             | rejected. New secure channel admission is |
   |                        |             | deferred until transition to ``VALID``.   |
   |                        |             | Plain-TCP fallback (where negotiated)     |
   |                        |             | remains usable.                           |
   +------------------------+-------------+-------------------------------------------+
   | ``PENDING_RENEWAL``    | SUSPENDED   | Same as ``SCHEDULED_OFFLINE``: TLS socket |
   |                        |             | kept, monitors paused, ``GET`` allowed,   |
   |                        |             | ``PUT``/``RPC`` rejected, and new secure  |
   |                        |             | channel admission deferred until renewal  |
   |                        |             | completes (transition to ``VALID``).      |
   +------------------------+-------------+-------------------------------------------+
   | ``REVOKED``            | BAD         | Connection MUST be closed; the endpoint   |
   |                        |             | enters degraded mode and refuses further  |
   |                        |             | TLS connections involving this            |
   |                        |             | certificate.                              |
   +------------------------+-------------+-------------------------------------------+
   | ``EXPIRED``            | BAD         | Same as ``REVOKED``.                      |
   +------------------------+-------------+-------------------------------------------+
   | ``UNKNOWN``            | UNKNOWN     | Not terminal. Before secure admission,    |
   |                        |             | TLS is not yet ready; plain-TCP fallback  |
   |                        |             | (where negotiated) remains usable while   |
   |                        |             | the endpoint waits for status to resolve  |
   |                        |             | to GOOD. After TLS is already live, the   |
   |                        |             | TLS socket is preserved and active secure |
   |                        |             | operations are paused until fresh status  |
   |                        |             | arrives.                                  |
   +------------------------+-------------+-------------------------------------------+
   | ``PENDING``            | UNKNOWN     | Same as ``UNKNOWN``.                      |
   +------------------------+-------------+-------------------------------------------+
   | ``PENDING_APPROVAL``   | UNKNOWN     | Before initial secure admission, enter    |
   |                        |             | ``TcpOnly`` and keep monitoring until the |
   |                        |             | status becomes ``VALID``.                 |
   +------------------------+-------------+-------------------------------------------+

A non-current cert-status response (``status_valid_until_date``
in the past) MUST be treated as ``UNKNOWN`` regardless of the
underlying ``status`` field.

The ``SUSPENDED`` class has one operational meaning independent of
whether the underlying cert-status is ``SCHEDULED_OFFLINE`` or
``PENDING_RENEWAL``:

- the TLS socket stays open;
- existing monitor subscriptions remain installed but do not deliver
  events until the status returns to ``GOOD``;
- ``GET`` requests MAY continue;
- ``PUT`` and ``RPC`` requests MUST fail while suspension is in
  effect;
- a new secure connection or channel setup MUST NOT advance to the
  fully admitted state until the peer's cert-status returns to
  ``GOOD``.

The ``UNKNOWN`` class has a different operational meaning from both
``SUSPENDED`` and ``BAD``:

- it is recoverable and non-terminal; it MUST NOT by itself tear down
  the TLS session;
- before TLS has become ready, it means secure admission is still
  pending. The endpoint waits for a fresh cert-status update that
  resolves to ``GOOD``; if plain-TCP fallback is available, that
  fallback MAY continue while waiting;
- after TLS is already live, it means the last usable status has gone
  stale. The endpoint keeps the TLS socket open and pauses active
  secure operations until a fresh update arrives;
- unlike ``SUSPENDED``, ``UNKNOWN`` does not assert that the
  certificate has been deliberately paused or is past-due for renewal;
  it says only that no current usable status decision is available.

Status-class transitions take effect within an implementation-
defined window of the cert-status update arriving at the endpoint.

**Pre-Validated connection behaviour.** The table above describes
steady-state behaviour for connections that have already completed
secure channel admission. For connections still in the
pre-Validated state (TLS handshake complete, secure channel
admission not yet done), the give-up rule of Section 7.3.1
applies:

- ``SUSPENDED`` class (own cert): the local TLS context enters
  ``TcpOnly``. Any pre-Validated TLS connection waiting for
  ``TlsReady`` SHALL be torn down; attached channels return to
  the searching state and re-resolve over plain TCP.
  ``reconnect_for_tls_when_ready`` is set so that recovery to
  ``VALID`` triggers a re-search that can commit to TLS.
- ``BAD`` class (own cert): the local TLS context enters
  ``DegradedMode``. Any pre-Validated TLS connection SHALL be
  torn down. Channels return to searching and connect over
  plain TCP. Recovery requires a new certificate (explicit
  reconfiguration).
- ``SUSPENDED`` or ``UNKNOWN`` class (peer cert, pre-Validated):
  the pre-Validated connection SHALL be torn down; the client
  returns the channel to searching. The server drops the
  connection. No waiting — the peer is known to be non-``GOOD``
  and will not become ``GOOD`` on the same handshake.
- ``BAD`` class (peer cert, pre-Validated): same as
  ``SUSPENDED`` — the pre-Validated connection is torn down
  immediately.

This pre-Validated give-up behaviour ensures that an endpoint does
not wait indefinitely for a cert-status that cannot become
``GOOD`` within the current connection attempt. The channel
re-searches and connects over plain TCP; subsequent recovery is
handled by Section 12.5.

8.5. Renewal Cadence
--------------------

The renewal cadence — ``renew_by``, ``renewal_due``, and
``PENDING_RENEWAL`` — is specified in Section 4.7.3. That section
is the single authoritative definition for all three on-the-wire
elements, the nominal and off-nominal sequences, and the
disabling rules (``renew_by == 0``). The connection-state effect
of ``PENDING_RENEWAL`` is the ``SUSPENDED`` class (Section 8.4).

----

9. Certificate Creation Request (CCR)
======================================

9.1. CCR PVStructure Schema
---------------------------

A Certificate Creation Request is submitted via PVA RPC
(``CMD_RPC``, PVA Section 9.6) to the Certificate Management
Service, targeting the well-known PV name
``<prefix>:CREATE[:<issuer_id>]`` (default prefix ``CERT``). The
optional trailing ``:<issuer_id>`` selects a specific issuer in
multi-issuer deployments. Without it, the issuer is discovered by
using the undistinguished ``<prefix>:CREATE`` RPC endpoint. In a
single-issuer deployment this resolves to that issuer. In a
multi-issuer deployment, all eligible Certificate Management Service
instances may listen on the undistinguished endpoint, so selection is
first-responder-wins and can select an unintended issuer. Clients
that require a particular issuer SHOULD use the explicit
``:<issuer_id>`` suffix. The RPC's request value is a CCR
PVStructure:

::

    structure CCR
        string             type             # authenticator plugin selector
        string             name             # principal name (CN of Subject)
        string             country          # 2-letter ISO country code
        string             organization     # O component of Subject
        string             organization_unit # OU component of Subject
        u16                usage            # bitmask: CLIENT (0x01),
                                            #   SERVER (0x02), CMS (0x04),
                                            #   IOC (0x08); bits OR-able
        u64                not_before       # requested validity start (UTC seconds)
        u64                not_after        # requested validity end (UTC seconds)
        string             pub_key          # PEM-encoded public key
        bool               no_status        # true ⇒ omit SPvaCertStatusURI
                                            #   (Section 4.3); status monitoring
                                            #   not bound to this certificate
        structure          verifier         # authenticator-specific (Section 6.2)
            ...                             # per-authenticator fields
        struct[]           schedule         # SCHEDULED_OFFLINE windows
                                            #   (Section 8); empty ⇒ none
            string         day_of_week      # e.g. "MON"
            string         start_time       # HH:MM
            string         end_time         # HH:MM
        struct[]           san              # Subject Alternative Name entries to
                                            #   embed in the issued certificate
                                            #   (Section 4.5); empty ⇒ no SAN ext
            string         type             # "dns" or "ip"
            string         value            # DNS name or IP address

The ``type`` field selects the Certificate Management Service
authenticator plugin that verifies the CCR. Its value is an
extensible string namespace, not a closed enum; future deployments MAY
define additional values such as ``jwt``. The ``verifier``
sub-structure is interpreted by the selected authenticator (Section
6.2). The currently registered verifier forms are:

- ``type = "std"``: ``verifier`` is empty.
- ``type = "krb"``: ``verifier = { token: byte[], mic: byte[] }``
  — GSS-API initial-context token plus message integrity check.
- ``type = "ldap"``: ``verifier = { signature: byte[] }`` —
  base64-encoded signature over the CCR contents, made with the
  principal's own private key after a successful LDAP bind has
  proved identity.

For ``ldap``, the client-side authenticator performs the identity
bootstrap before sending the CCR: it binds to LDAP as the named user,
then reads or writes that user's well-known public-key attribute in
the user's LDAP entry. The LDAP domain administrator must permit users
to manage that attribute. The authenticator signs the canonical CCR
payload with the corresponding private key and carries the signature
in ``verifier.signature``. The Certificate Management Service-side
LDAP verifier performs an anonymous/public LDAP lookup of the same
user entry, retrieves the registered public key, and verifies the CCR
signature against it. A successful verification proves that the CCR
sender both authenticated to LDAP as that user when registering the
key and currently holds the matching private key.

9.2. CCR Submission
-------------------

A CCR is submitted via:

::

    Channel<RPC>: <prefix>:CREATE[:<issuer_id>]
    Request: CCR PVStructure
    Response: structure { ..., string cert, ... }

On success for a fresh issuance, the response contains the
PEM-encoded issued certificate in ``cert``. On success for a
renewal, the response omits ``cert`` and instead returns updated
state for the existing certificate (including its serial number,
state, status process variable name, expiration, and, when
applicable, the updated ``renew_by``). On failure, the response
Status is ERROR or FATAL with a descriptive message.

9.3. CCR Authorization
----------------------

The Certificate Management Service applies site-defined policy to
decide whether to approve a CCR. The policy MAY:

- Auto-approve any CCR matching certain ``type``+``organization``
  combinations.
- Require admin approval (transition through ``PENDING_APPROVAL``)
  for any CCR not auto-approved.
- Reject CCRs based on ``name`` patterns (e.g. reserve
  ``CN=admin``).

The authorization policy is OUT OF SCOPE of this specification; it
is a site deployment concern.

9.4. Renewal CCR
----------------

A renewal CCR is identical to a fresh CCR but the requested
``name``, ``organization``, ``organization_unit``, and ``country``
match an existing certificate. The Service detects renewal by
finding an existing certificate row with the same Subject
Distinguished Name fields, a different serial number, a status in
the set ``VALID``, ``PENDING_APPROVAL``, ``PENDING``, or
``PENDING_RENEWAL``, and ``renewal_due != 0``.

When a CCR is handled as a renewal, the Service updates the
existing certificate record instead of issuing a replacement
certificate. Specifically:

- if the existing certificate is in ``PENDING_RENEWAL``, the Service
  returns it to ``VALID`` and updates ``renew_by``;
- if the existing certificate is already in ``VALID``,
  ``PENDING_APPROVAL``, or ``PENDING``, the Service updates
  ``renew_by`` if the new authenticated horizon extends it;
- the response reuses the existing certificate's serial number and
  omits the ``cert`` field.

Renewal does not re-enter the approval workflow. The existing
certificate's approval state is preserved: an already-``VALID``
certificate remains approved and returns to or stays in ``VALID``
when the renewal verifier succeeds. This is not a separate
auto-approval decision; approval is simply not required again for an
existing approved certificate. A site that no longer accepts the
certificate SHOULD revoke it through the Certificate Management
Service's administrator operation.

----

10. Certificate Management Service
==================================

10.1. Service as a PVA Server
-----------------------------

The Certificate Management Service runs as a PVA server. It
exposes its functions through two distinct kinds of well-known
PVs under a configurable PV-name prefix (default ``CERT``):

- **Operational PVs** — conventional readable / monitorable PVs
  that publish service state. Clients access them with PVA's
  ``CMD_GET`` and ``CMD_MONITOR``. These cover per-certificate
  status, service health, service metrics, the issuer
  certificate's metadata, and the root Certification Authority
  (root CA) certificate's metadata. They are not RPC entry
  points — they are state PVs that any cert-bearing client may
  read or subscribe to (subject to the EPICS access security
  configuration file rules; see Section 11).

- **Action PVs** — RPC entry points (PVA ``CMD_RPC``) that
  cause the Service to perform a privileged operation. These
  cover certificate creation, admin approval of pending
  requests, admin revocation, and scheduled-operation submission.

The Service is itself an SPVA-secured server: clients connecting
to it MUST use Transport Layer Security (TLS), and the Service's
own server certificate MUST be issued by a trust anchor common to
all participating endpoints.

10.2. PV Namespace
------------------

.. table:: Well-known PVs (operational)
   :widths: auto

   +-------------------------------------+----------+--------------------------------+
   | PV name                             | Access   | Purpose                        |
   +=====================================+==========+================================+
   | ``<prefix>:STATUS:<skid>:<serial>`` | GET /    | Per-certificate status updates |
   |                                     | MONITOR  | (one PV per issued cert; see   |
   |                                     |          | Section 7).                    |
   +-------------------------------------+----------+--------------------------------+
   | ``<prefix>:HEALTH``                 | GET /    | Service health (NTEnum:        |
   |                                     | MONITOR  | "OK" / "Not OK") plus          |
   |                                     |          | ancillary fields (database     |
   |                                     |          | connectivity, signing-key      |
   |                                     |          | validity, uptime, current      |
   |                                     |          | issued-cert count, cluster     |
   |                                     |          | member count, last self-check  |
   |                                     |          | timestamp).                    |
   +-------------------------------------+----------+--------------------------------+
   | ``<prefix>:METRICS``                | GET /    | Service metrics (NTScalar:     |
   |                                     | MONITOR  | currently-VALID certificate    |
   |                                     |          | count) plus ancillary counters |
   |                                     |          | (request rates, error rates,   |
   |                                     |          | signing latencies).            |
   +-------------------------------------+----------+--------------------------------+
   | ``<prefix>:ISSUER[:<skid>]``        | GET      | Issuer certificate metadata    |
   |                                     |          | (Subject Distinguished Name,   |
   |                                     |          | validity, public-key digest,   |
   |                                     |          | full chain).                   |
   +-------------------------------------+----------+--------------------------------+
   | ``<prefix>:ROOT[:<skid>]``          | GET      | Root Certification Authority   |
   |                                     |          | certificate metadata.          |
   +-------------------------------------+----------+--------------------------------+

For ``ISSUER``, ``ROOT``, and ``CREATE``, the optional trailing
``:<skid>`` / ``:<issuer_id>`` selects a specific issuer. The
unsuffixed names are discovery forms suitable for single-issuer
deployments. In multi-issuer deployments, more than one Certificate
Management Service instance may answer an unsuffixed name, making the
result first-responder-wins. Clients that require a specific issuer
SHOULD use the issuer-qualified form.

.. table:: Well-known PVs (action / RPC)
   :widths: auto

   +-------------------------------------+----------+--------------------------------+
   | PV name                             | Access   | Purpose                        |
   +=====================================+==========+================================+
   | ``<prefix>:CREATE``                 | RPC      | Submit a Certificate Creation  |
   |                                     |          | Request (Section 9). Open to   |
   |                                     |          | any client whose authenticator |
   |                                     |          | the Service recognises.        |
   +-------------------------------------+----------+--------------------------------+
   | ``<prefix>:SCHEDULE``               | RPC      | Submit a scheduled-operation   |
   |                                     | (admin)  | request (e.g. scheduled        |
   |                                     |          | revocation).                   |
   +-------------------------------------+----------+--------------------------------+
   | ``<prefix>:APPROVE``                | RPC      | Approve a pending CCR (drives  |
   |                                     | (admin)  | the ``PENDING_APPROVAL`` exit  |
   |                                     |          | to ``PENDING`` / ``VALID`` /   |
   |                                     |          | ``EXPIRED`` per the            |
   |                                     |          | cryptographic clock; see       |
   |                                     |          | Section 8.3).                  |
   +-------------------------------------+----------+--------------------------------+
   | ``<prefix>:REVOKE``                 | RPC      | Revoke an issued certificate.  |
   |                                     | (admin)  |                                |
   +-------------------------------------+----------+--------------------------------+

Admin RPCs are gated by the Certificate Management Service's access-
security rules. A calling principal is an administrator exactly when
its authenticated connection matches the rule set the Service applies
to those admin PVs (Section 11); there is no protocol-level
administrator certificate type.

The ``<prefix>:STATUS:<skid>:<serial>`` PV is implemented as a
*wildcard PV* — a single server-side PV pattern that
materialises one channel per actually-issued certificate, rather
than a fixed set of pre-registered PVs. This allows the channel
list to grow with the certificate population without redeploying
the Service.

10.3. Service Identity
----------------------

The Certificate Management Service has an X.509 server
certificate, issued by the same CA chain as the endpoint
certificates it issues. The Service's certificate Subject DN
carries a CN identifying the deployment's service name; clients
SHOULD verify that the Service they connect to presents the
expected DN before submitting CCRs.

----

11. Authorization
=================

11.1. Per-Connection Authorization Inputs
-----------------------------------------

For every TLS-authenticated connection, SPVA exposes the
following peer-credential fields to the server's authorization
layer. These are the protocol-level inputs an access-security
configuration MAY match against; the configuration syntax itself
(EPICS access security configuration files, or any other) is out
of scope.

.. table:: Per-peer authorization inputs
   :widths: auto

   +------------------+-----------------------------------------------+
   | Field            | Value                                         |
   +==================+===============================================+
   | ``method``       | ``"x509"`` for SPVA-authenticated peers;      |
   |                  | ``"ca"`` for plain-PVA peers presenting an    |
   |                  | advisory user name; ``"anonymous"`` for       |
   |                  | peers presenting no credentials.              |
   +------------------+-----------------------------------------------+
   | ``account``      | For ``method = "x509"``: the peer             |
   |                  | certificate's CN value (Section 4.4). For     |
   |                  | ``method = "ca"``: the user-name string the   |
   |                  | peer supplied in PVA                          |
   |                  | ``CMD_CONNECTION_VALIDATION``. For            |
   |                  | ``method = "anonymous"``: ``"anonymous"``.    |
   +------------------+-----------------------------------------------+
   | ``authority``    | For ``method = "x509"``: a list (one per      |
   |                  | line) of CN values from the peer's            |
   |                  | certificate chain, ordered from the issuing   |
   |                  | CA up to the root. Empty for ``method =       |
   |                  | "ca"`` and ``method = "anonymous"``.          |
   +------------------+-----------------------------------------------+
   | ``peer``         | Peer network address (numeric).               |
   +------------------+-----------------------------------------------+
   | ``iface``        | Local interface address through which this    |
   |                  | peer is connected (numeric); MAY be a         |
   |                  | wildcard.                                     |
   +------------------+-----------------------------------------------+
   | ``san``          | Subject Alternative Name entries (Section     |
   |                  | 4.5) extracted from the peer certificate;     |
   |                  | each entry is ``{type, value}`` with type     |
   |                  | ``"dns"`` or ``"ip"``. Empty if no SAN        |
   |                  | extension is present or for non-x509 peers.   |
   +------------------+-----------------------------------------------+
   | ``isTLS``        | True if the connection is TLS-protected.      |
   +------------------+-----------------------------------------------+

The peer certificate's issuer SKID and serial are kept in the
endpoint runtime for cert-status monitoring (Section 7) but are
NOT exposed to the authorization layer.

An *administrator* is not identified by any intrinsic certificate
bit, extension, or dedicated protocol role. For the Certificate
Management Service's admin PVs, administrator status is purely an
authorization outcome: the peer presents a keychain whose
certificate-backed connection matches the Service's access-security
rule set for those PVs. A common rule set matches ``method =
"x509"``, ``isTLS = true``, the ``account`` field (typically the
certificate Subject CN), and one or more ``authority`` values from
the certificate chain back to a shared trust anchor. However, the
Service MAY define any rule set it chooses; the protocol does not
mandate a particular administrator-matching policy.

11.2. ACL Change Notification
-----------------------------

A PVA server emits ``CMD_ACL_CHANGE`` (PVA Section 13) to a
connected client when the effective permissions for one of that
client's open channels change. The 5-octet payload carries the
client channel ID (CID; 4 octets) followed by a permissions
bitmask (1 octet) with bits ``PUT = 0x01``, ``PUT_GET = 0x02``,
and ``RPC = 0x04`` (per ``epics-docs/epics-docs#140``). SPVA does
not change the ``CMD_ACL_CHANGE`` wire format.

----

12. Discovery and Search with TLS
==================================

12.1. Protocol List in Search
-----------------------------

A client wishing to use SPVA includes ``"tls"`` in its
``CMD_SEARCH`` ``protocols`` list (PVA Section 7.1). To
preferentially negotiate SPVA but accept fallback to plain PVA, the
list is ``["tls", "tcp"]``.

12.2. Server Selection Logic
----------------------------

A server receiving a search whose ``protocols`` list contains
``"tls"`` AND whose own configuration enables SPVA SHALL respond
with ``CMD_SEARCH_RESPONSE`` carrying ``protocol = "tls"`` and
``server_port`` set to its TLS-listening port (default 5076).

If the server cannot speak TLS but the search list includes
``"tcp"`` as fallback, the server MAY respond with
``protocol = "tcp"`` instead.

If neither protocol matches, the server MUST silently ignore the
search.

12.3. TLS-Only Discovery
------------------------

A client MAY send searches with ``protocols = ["tls"]`` (no
``"tcp"`` fallback). Servers that cannot speak TLS will silently
ignore the search; the client will only connect to SPVA-capable
servers.

12.4. TLS Search-Reply Filter
------------------------------

A ``CMD_SEARCH_RESPONSE`` carries exactly one protocol per reply
(``"tls"`` or ``"tcp"``; there is no per-reply fallback). When a
client receives a search reply with ``protocol = "tls"`` and the
client's own local TLS context state is ``TcpOnly`` or
``DegradedMode`` (the client has already given up on TLS for its
own certificate; Section 7.3.1), the client SHALL discard the
entire reply. The channel remains in the searching state; the
next search cycle will emit a search listing only ``["tcp"]``
(because the TLS context is no longer ready) and the server will
respond with ``protocol = "tcp"``.

This filter closes a race where a delayed TLS search reply arrives
after the client's give-up handler has returned a channel to the
searching state. Without the filter, the stale reply would
re-commit the channel to TLS, trigger give-up again, and repeat
until the in-flight reply drains.

12.5. Per-Peer Status Memory and Search Partitioning
----------------------------------------------------

An implementation SHOULD maintain a process-wide, in-memory cache
of peer certificate status (a "peer status store") to avoid
repeated TLS handshake failures to the same non-``GOOD`` peer.

**Store population.** Whenever a connection (client or server)
receives a fresh peer cert-status delivery via the per-connection
status subscription (Section 7.3), the endpoint records the peer
certificate identity (issuer + serial) and the delivered status
class in the process-wide store. The entry's expiration is the
cert-status response's ``status_valid_until_date`` — the
PVACMS-signed freshness boundary. When
``status_valid_until_date`` passes, the entry expires and is
removed on the next lookup.

**Store population at handshake completion.** The store also
records an auxiliary binding from the server's PVA GUID (present
in the ``CMD_SEARCH_RESPONSE``; Section 12.1 of the PVA spec) to
the peer certificate identity. This binding is populated at TLS
handshake completion, once the peer certificate is available.

**Client search-reply filter (peer cert).** When a client
processes a ``CMD_SEARCH_RESPONSE`` with ``protocol = "tls"``,
it SHOULD consult the peer status store using the reply's server
GUID (via the GUID-to-peer-cert auxiliary map). If a current
non-``GOOD`` entry exists for the peer, the client SHALL discard
the reply. Before discarding, the client records the reply's GUID
on the channel so that subsequent search cycles can partition
the channel into the TCP-only bucket (Section 12.5.1). The
channel remains in the searching state.

**Server handshake-completion filter.** When a server's TLS
handshake completes and the peer certificate is available, the
server SHOULD consult the peer status store by the peer
certificate identity. If a current non-``GOOD`` entry exists, the
server SHALL reject the connection immediately (close the TCP
socket). The peer client's symmetric store lookup will have
recorded the non-``GOOD`` entry, so the peer client's next search
cycle will list ``["tcp"]`` only for this channel and the server
will respond with ``protocol = "tcp"``.

12.5.1. Per-Channel Search Protocol Partitioning
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A ``CMD_SEARCH`` packet carries a process-wide protocol list
(``["tls", "tcp"]`` or ``["tcp"]``) that applies to all channels
in the packet. An implementation SHOULD partition channels into
sub-buckets based on the peer status store so that channels
targeting known non-``GOOD`` peers emit searches with
``["tcp"]`` only:

- For each channel in the searching state, the implementation
  consults the peer status store using the channel's last-known
  server GUID (recorded on the channel at search-reply time).
  If the lookup returns a current non-``GOOD`` entry, the channel
  is placed in a TCP-only sub-bucket; otherwise it remains in
  the default sub-bucket.
- The implementation emits one search packet for the default
  sub-bucket (with the process-wide protocol list, typically
  ``["tls", "tcp"]``) and one search packet for the TCP-only
  sub-bucket (with ``["tcp"]``). Either packet is omitted if
  its sub-bucket is empty.

This partitioning ensures that a channel known to target a
non-``GOOD`` peer stops emitting ``"tls"`` in its searches. The
server responds with ``protocol = "tcp"`` and the channel commits
to TCP without a wasted TLS handshake or discarded reply.

Channels with no last-known GUID (first contact) are placed in
the default sub-bucket. The first contact with a non-``GOOD``
peer costs one wasted search round-trip; from the second search
cycle onward the channel is correctly partitioned.

When a peer's status recovers to ``GOOD`` (the store entry is
overwritten by a fresh ``GOOD`` delivery or expires), the next
search cycle automatically returns the channel to the default
sub-bucket — no explicit reset is required.

12.5.2. Active Upgrade on Peer Recovery
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When the peer status store observes a transition from a
non-``GOOD`` class to ``GOOD`` for a peer certificate (detected
by comparing the prior store entry's class against the new
delivery's class), the implementation SHOULD tear down all
existing plain-TCP connections to that peer. The tear-down
returns attached channels to the searching state; the next search
cycle places them in the default sub-bucket (because the store
now holds ``GOOD``), the search lists ``["tls", "tcp"]``, and
the server responds with ``protocol = "tls"``. The channels
commit to TLS.

This active-upgrade mechanism requires that at least one TLS
connection to the recovering peer exists (so that a peer cert-
status subscription is alive and delivering updates to the store).
If no TLS connection exists to the peer (all channels were
TCP-downgraded), the store entry sits until its
``status_valid_until_date`` expires, at which point the next
search cycle returns the channel to the default sub-bucket and
the normal search/reply flow re-evaluates the peer. Recovery in
this case is bounded by the OCSP validity period (typically
minutes to hours, configurable in the Certificate Management
Service).

The active-upgrade tear-down MUST NOT tear down TLS connections.
It applies only to plain-TCP connections whose peer certificate
identity matches the recovered peer. This invariant ensures that
the delivering TLS connection (whose subscription triggered the
recovery notification) is not self-destructed.

----

13. OCSP Stapling
=================

OCSP stapling is OPTIONAL. The mechanism follows :rfc:`6066`
(``status_request`` extension) and :rfc:`6066` Section 8 / :rfc:`6961`
(stapled response carried in the TLS handshake).

13.1. Client Behaviour
----------------------

A client MAY include the TLS ``status_request`` extension in its
ClientHello.

A client receiving a stapled OCSP response in the handshake MUST:

- parse the response per :rfc:`6960`;
- verify its signature against the configured trust anchor
  (Section 4.6);
- treat the response as not-current if its ``thisUpdate`` is older
  than the cert-status validity duration (Section 4.7.2);
- map the stapled ``certStatus`` to the cert-status mapping in
  Section 8.4 (GOOD → GOOD class; REVOKED → BAD class; UNKNOWN →
  UNKNOWN class).

A stapled response in the BAD class MUST cause the TLS handshake
to abort.

13.2. Server Behaviour
----------------------

A server MAY supply a stapled OCSP response in its TLS Certificate
message. The server obtains the OCSP response from the
``ocsp_response`` field of its own cert-status PV (Section 7.2).
The server MUST NOT staple a response whose freshness window
(Section 4.7.2) has passed.

13.3. Relationship to Cert-Status Monitoring
--------------------------------------------

A peer with a stapled OCSP response and a peer with no stapled
response are subject to the same cert-status monitoring (Section 7)
post-handshake. The stapled response affects only the initial
handshake decision; subsequent transitions in the cert-status PV
drive the connection state per Section 8.4 in either case.

----

14. Keychain Rotation
=====================

An SPVA endpoint MAY rotate its TLS identity (the keychain
backing its certificate) at runtime without process restart. The
wire-protocol consequence is that all TLS connections at that
endpoint close (with a TLS ``close_notify`` alert) and the PVA
layer re-establishes them per the standard PVA reconnection
flow: fresh search → fresh TCP connect → fresh TLS handshake (now
using the new certificate) → fresh ``CMD_CONNECTION_VALIDATION``
→ re-create channels → re-subscribe monitors.

There is no SPVA wire mechanism for in-place keychain swap on an
existing connection; rotation is always observed by peers as a
disconnect followed by a fresh handshake.

----

15. Error Handling
==================

15.1. TLS Handshake Failures
----------------------------

A failed TLS handshake (chain validation, expired peer cert, no
common cipher suite, etc.) MUST result in a TLS Alert per
:rfc:`8446`. Clients SHOULD apply exponential backoff before
retry.

15.2. Cert-Status Mid-Connection
--------------------------------

A peer cert-status transition during a connection drives the
connection-state effect per Section 8.4. The transition takes
effect within an implementation-defined window of the update
arriving at the endpoint.

A transition into the BAD class MUST cause connection close
(clean TLS close or TCP RST). The closing party MAY include a
TLS Alert ``certificate_revoked`` (:rfc:`8446`) before the close.

A transition into the ``UNKNOWN`` class before a secure connection is
fully admitted keeps TLS not-ready and MAY leave plain-TCP fallback in
service if it was negotiated. A transition into ``UNKNOWN`` after a
TLS session is already live MUST NOT close the underlying TLS socket;
the runtime treats the condition as recoverable and pauses active
secure operations until a fresh cert-status update arrives.

15.2.1. Pre-Validated Give-Up
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A pre-Validated TLS connection (TLS handshake complete, secure
channel admission not yet done) that receives an authoritative
cert-status delivery resolving to any class other than ``GOOD``
(for either its own or the peer's certificate) SHALL abandon the
TLS attempt per Section 7.3.1. The abandoning endpoint tears
down the TLS connection and returns attached channels to the
searching state. The endpoint SHOULD log the give-up at WARN
level.

The give-up applies once per connection attempt. The channels
re-search and MAY commit to plain TCP on the next search reply.
If the peer status store (Section 12.5) is populated, subsequent
search cycles avoid re-attempting TLS to the same non-``GOOD``
peer until the store entry expires or is overwritten by a
``GOOD`` delivery.

15.3. CCR Failures
------------------

A failed CCR (Section 9) is reported via the standard PVA RPC
response with Status type ``ERROR`` or ``FATAL``. The Status
message is implementation-defined diagnostic text and is not
normative.

----

16. Version Negotiation
=======================

This specification defines SPVA wire-protocol version 2,
comprising PVA wire-protocol version 2 (:doc:`/protocol-spec/pva`
Section 16), TLS 1.3 (:rfc:`8446`) as the only acceptable
transport (Section 3.1), the cert-status and CCR PVStructure
schemas (Sections 7.2 and 9.1), and the authentication mechanism
(Section 6).

There is no SPVA-level version negotiation. PVA's version
negotiation governs the PVA layer; TLS 1.3's version negotiation
governs the transport layer; both are constrained to single
values by this specification. Future SPVA versions that change
any of the above MUST increment this specification's version
number.

----

17. Security Considerations
============================

17.1. Threat Model
------------------

SPVA assumes:

- The network MAY contain on-path active attackers (eavesdropping,
  injection, modification).
- The CA's private key is held in trusted infrastructure.
- Endpoint private keys are protected per site policy.
- Authenticator credentials (Kerberos tickets, LDAP-bind
  credentials, etc.) are protected by their respective underlying
  mechanisms.

SPVA defends against:

- Eavesdropping (TLS confidentiality).
- Modification in transit (TLS integrity).
- Identity spoofing (X.509 mutual authentication).
- Use of revoked credentials (cert-status monitoring; Section 7).

SPVA does NOT defend against:

- Compromise of an endpoint's private key. The attacker can
  impersonate the endpoint until the certificate is marked
  ``REVOKED`` and the revocation reaches the affected peer (within
  one cert-status validity window, Section 4.7.2).
- CA compromise.
- Insider attacks at the Certificate Management Service (a
  malicious operator can issue certificates).
- Denial-of-service against the Certificate Management Service.
  Service unavailability prevents fresh cert-status updates;
  existing GOOD-class connections continue with cached cert-status
  until ``status_valid_until_date`` expires, after which they
  transition to UNKNOWN class (Section 8.4); new connections
  involving certificates with the ``SPvaCertStatusURI`` extension
  cannot acquire an initial cert-status update and proceed in the
  UNKNOWN class.

17.2. Cipher Suites
-------------------

SPVA mandates TLS 1.3 (Section 3.1) and the cipher suites of
Section 3.3.

17.3. 0-RTT (Early Data)
------------------------

SPVA forbids 0-RTT (early data; :rfc:`8446` Section 2.3 / Section
8). PVA operations carry side-effects (PUT, RPC, PROCESS) and
0-RTT is replay-vulnerable.

Session resumption is also not supported (Section 3.7).

17.4. Cert-Status Privacy
-------------------------

The cert-status PV name pattern (``<prefix>:STATUS:<issuer-skid>:<cert-serial>``;
Section 7.1) allows any party with Certificate Management Service
access to enumerate live certificates. Sites with stricter privacy
needs SHOULD restrict cert-status PV access via authorization rules
(Section 11).

17.5. Side-Channel Considerations
---------------------------------

SPVA's cryptographic operations are subject to standard
side-channel considerations (timing, cache, power). Implementations
SHOULD use constant-time crypto libraries.

17.6. Downgrade via Search-Reply Suppression
--------------------------------------------

A client whose search ``protocols`` list is ``["tls", "tcp"]``
(Section 12) is vulnerable to a downgrade attack: an active
attacker on the UDP search path can suppress the TLS-capable
server's reply and let only a plain-PVA server's reply through.
A client requiring SPVA SHOULD send searches with
``protocols = ["tls"]`` only.

----

18. IANA Considerations
=======================

SPVA uses TCP port 5076 by default. This is NOT IANA-registered;
it is configurable via ``EPICS_PVAS_TLS_PORT``.

SPVA does not define a custom URI scheme.

SPVA does not currently use TLS ALPN.

The two custom X.509 OID arcs used by SPVA (``1.3.6.1.4.1.37427.1``
for ``SPvaCertStatusURI``; see Section 4.3) are issued under the
IANA Private Enterprise Number arc but are not currently
IANA-registered to the EPICS community.

----

19. References
==============

19.1. Normative References
--------------------------

- **RFC 2119** — Bradner, S., "Key words for use in RFCs to
  Indicate Requirement Levels", BCP 14, :rfc:`2119`, March 1997.
- **RFC 2578** — McCloghrie, K. et al., "Structure of Management
  Information Version 2 (SMIv2)", :rfc:`2578`, April 1999. Defines
  the Private Enterprise Number arc ``1.3.6.1.4.1`` referenced in
  Section 4.3 for SPVA's custom X.509 extension Object Identifiers.
- **RFC 5280** — Cooper, D. et al., "Internet X.509 Public Key
  Infrastructure Certificate and Certificate Revocation List (CRL)
  Profile", :rfc:`5280`, May 2008.
- **RFC 6066** — Eastlake, D., "Transport Layer Security (TLS)
  Extensions: Extension Definitions", :rfc:`6066`, January 2011.
- **RFC 6960** — Santesson, S. et al., "X.509 Internet Public Key
  Infrastructure Online Certificate Status Protocol - OCSP",
  :rfc:`6960`, June 2013.
- **RFC 6961** — Pettersen, Y., "The Transport Layer Security
  (TLS) Multiple Certificate Status Request Extension",
  :rfc:`6961`, June 2013.
- **RFC 8174** — Leiba, B., "Ambiguity of Uppercase vs Lowercase in
  RFC 2119 Key Words", BCP 14, :rfc:`8174`, May 2017.
- **RFC 8446** — Rescorla, E., "The Transport Layer Security (TLS)
  Protocol Version 1.3", :rfc:`8446`, August 2018.
- **PVA Specification** — :doc:`/protocol-spec/pva`.

19.2. Informative References
----------------------------

- **CA Specification** — :doc:`/protocol-spec/ca`.
- **RFC 7301** — Friedl, S. et al., "Transport Layer Security (TLS)
  Application-Layer Protocol Negotiation Extension", :rfc:`7301`,
  July 2014. (For potential future ALPN use.)
- **pvxs implementation** — https://github.com/slac-epics/pvxs;
  in particular the SPVA-specific code under ``src/secure/`` and
  the TLS-related fields of
  :doc:`pvxs::impl::ConfigCommon </maintainer-docs/api-reference-pvxs-configcommon>`.
  Consulted in
  preparing this specification.
- **pvxs-cms implementation** — https://github.com/slac-epics/pvxs-cms;
  in particular ``src/common/certstatus.h`` (the cert-status
  PVStructure schema),
  :doc:`cms::cert::CertFactory </maintainer-docs/api-reference-pvxs-cms-certfactory>` (the
  certificate-issuance code path), and ``src/pvacms/opensslgbl.h``
  (the custom Object Identifier definitions referenced in
  Section 4.3). Consulted in preparing this specification.
- :doc:`/programmers-ref/spva-tls` — pvxs's SPVA TLS implementation.
- :doc:`/programmers-ref/spva-authentication` — pvxs's
  authentication implementation.
- :doc:`/programmers-ref/spva-authorization` — pvxs's authorization
  implementation.
- :doc:`/programmers-ref/spva-cert-management-protocol` — pvxs's
  cert-management implementation.
- :doc:`/user-manual/pvacms` — PVACMS deployment and operation.

----

Authors' Addresses
==================

This specification is maintained by the slac-epics organization at
https://github.com/slac-epics/pvxs-docs. Issues and proposed
clarifications should be filed there.

SPVA was designed by SLAC EPICS team based on the underlying PVA
protocol design by the EPICS V4 working group.
