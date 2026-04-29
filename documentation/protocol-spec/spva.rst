.. _spva_protocol_spec:

================================================
Secure PVAccess (SPVA) Protocol Specification
================================================

:Status: Draft
:Protocol Version: 2 (SPVA is layered on PVA wire-protocol version 2)
:Default TLS Server Port: 5076 (TCP)
:Default PVACMS Server Port: 5076 (TCP, with TLS)

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
(PVACMS) for certificate issuance, status monitoring, and lifecycle
management; and it extends the EPICS access security file (ACF) with
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
10. PVACMS Service
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
- **Provide a bootstrapping path** — PVACMS (Section 10) issues
  certificates to clients and servers that do not yet have them.
  The Certificate Creation Request (Section 9) carries an
  authenticator-specific verifier (Kerberos GSS-API token, LDAP-
  bind-then-sign signature, or administrator-approval-pending
  marker) that PVACMS uses to verify the requesting principal's
  identity at issuance time.

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
  ``x509``. The CCR issuance authenticators (Section 6.2):
  ``authnstd``, ``authnkrb``, ``authnldap``.
- The certificate-status protocol (Section 7): the cert-status
  PVStructure schema, the subscribe/publish flow, OCSP stapling
  (Section 13).
- Certificate lifecycle states (Section 8) and the ``CCR`` (Section
  9) used to request certificate issuance.
- The PVACMS service (Section 10): its PV namespace, its RPCs, its
  responsibilities.
- ACF authorization extensions (Section 11).
- Connection reconfiguration (Section 14) — runtime keychain
  rotation.

It does not cover:

- PVA wire format or operation semantics (see
  :doc:`/protocol-spec/pva`).
- The pvxs C++ API or pvxs-cms C++ API (see
  :doc:`/programmers-ref/index`).
- Operational concerns: PVACMS deployment, cluster setup,
  certificate-store management. These are
  :doc:`/user-manual/pvacms`.
- Site-specific PKI policy (root CA selection, intermediate-CA
  hierarchy, naming conventions). SPVA constrains the certificate
  *profile* but not the PKI organisation behind it.

1.4. Terminology
----------------

SPVA-specific terminology in addition to PVA's:

PVACMS
   The Process Variable Access Certificate Management Service. A
   long-running service that issues, monitors, and revokes X.509
   certificates for SPVA endpoints. PVACMS itself runs as a PVA
   server. It exposes some of its functions as remote procedure
   calls (RPCs) at well-known PV names — certificate creation,
   admin scheduling and approval — and other functions as
   conventional monitorable / readable PVs: per-certificate
   status (subscribable), service health, service metrics,
   issuer-cert info, and root-CA info (Section 10).

CMS
   Abbreviated PVACMS.

Authenticator
   An issuance mechanism by which a not-yet-certified principal
   proves its identity to PVACMS in order to obtain a certificate.
   Defined values: ``authnstd`` (administrator approval),
   ``authnkrb`` (Kerberos GSS-API), ``authnldap`` (LDAP-bind plus
   key signature).

CCR (Certificate Creation Request)
   A PVStructure that a principal sends to PVACMS to request
   issuance of a certificate. Carries the principal's public key,
   the requested subject DN, the chosen authenticator, and any
   authenticator-specific verifier payload.

Certificate Subject
   The X.509 Subject Distinguished Name of the certificate. SPVA
   constrains it to specific patterns (Section 4.4).

Cert-status PV
   A well-known PV name pattern, hosted by PVACMS, that publishes
   the current status of a specific certificate identified by its
   issuer and serial. Subscribed by the cert-status monitor in
   client and server runtimes.

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
- **PVACMS-driven certificate lifecycle**: clients and servers can
  request, renew, and rotate certificates via well-defined RPCs.
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
- ``PENDING_RENEWAL`` connection-state behaviour (Section 8.5).
- Renewal hint delivery (``renew_by``; Section 8.5).

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
entries at issuance time; PVACMS embeds them in the issued
certificate verbatim subject to site-policy filtering.

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

SPVA distinguishes the **cryptographic** validity of an entity
certificate (its X.509 ``notBefore`` and ``notAfter`` fields, fixed
at issuance and verifiable by any standard X.509 verifier) from its
**operational** validity (the cert-status protocol of Section 7
currently asserts a status mapped to a usable connection-state
class, Section 8.4).

Operational validity is enforced by the cert-status protocol, not
by ``notAfter``. The two are deliberately decoupled so that
``notAfter`` can be set very long (e.g. multiple years) without
weakening the security posture, while operational validity is
constrained by a much shorter window (the
``status_valid_until_date`` field of the cert-status PVStructure;
see Section 7.2). This decoupling is a core SPVA design choice; the
guidance below replaces the conventional "use short ``notAfter``"
advice that applies to PKI deployments without a live cert-status
channel.

4.7.1. Cryptographic Validity (notAfter)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The X.509 ``notAfter`` of an entity certificate marks the end of
the certificate's cryptographic life: after this instant any X.509
verifier MUST reject the certificate independently of any cert-
status check. PVACMS sets ``notAfter`` per its configured policy.
The configuration interface is the environment variables
``EPICS_PVACMS_CERT_VALIDITY`` (with per-role overrides
``EPICS_PVACMS_CLIENT_CERT_VALIDITY``,
``EPICS_PVACMS_SERVER_CERT_VALIDITY``, and
``EPICS_PVACMS_IOC_CERT_VALIDITY``); the value is a duration. Sites
are expected to set this to their preferred cryptographic lifetime,
which MAY be much longer than the duration any one implementation
defaults to.

Sites SHOULD treat ``notAfter`` as the rotation horizon — the
maximum time the same keypair MAY remain in service — not as the
operational expiry. A long ``notAfter`` is acceptable and
operationally desirable: it means a process holding a valid private
key does not need to re-engage the certificate-issuance flow on
every short-cycle renewal, and reduces PVACMS load.

There is no protocol-level upper bound on ``notAfter``. A site MAY
configure multi-year ``notAfter`` values where its key-protection
policy (hardware security module, sealed keychain, or equivalent)
warrants it. Sites with weaker key protection SHOULD configure
shorter ``notAfter`` values to bound the impact of a key
compromise that goes undetected long enough to outlast cert-status
revocation propagation.

4.7.2. Operational Validity
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Operational validity is the property checked by an SPVA endpoint
when establishing and maintaining a connection (Section 5.1,
Section 7). The current cert-status report drives the connection's
state per the mapping in Section 8.4; only the GOOD class permits
unrestricted SPVA traffic. The cert-status response's
``status_valid_until_date`` field defines the freshness window: a
report whose ``status_valid_until_date`` has passed MUST be
treated as ``UNKNOWN`` regardless of the underlying ``status``
value.

PVACMS sets ``status_valid_until_date`` per the duration
configured by ``EPICS_PVACMS_CERT_STATUS_VALIDITY_MINS``.
Endpoints obtain fresh status by maintaining a live cert-status
subscription (Section 7.3) or, if subscription is unavailable, by
re-querying.

4.7.3. Renewal Hint (PENDING_RENEWAL and renew_by)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Independent of both ``notAfter`` and
``status_valid_until_date``, each certificate MAY carry a
**renewal hint** — a separate ``renew_by`` time at which PVACMS
(or site policy) recommends the certificate-holder request a fresh
certificate. The renewal hint is conveyed:

- Implicitly via the cert-status state transition to
  ``PENDING_RENEWAL`` (Section 8.3) when the renewal threshold is
  reached.
- Explicitly via the ``renew_by`` field of the cert-status
  PVStructure (Section 7.2).

A certificate-holder receiving ``PENDING_RENEWAL`` SHOULD initiate
a renewal Certificate Creation Request (Section 9.4). While
``PENDING_RENEWAL`` is in effect the certificate's connections are
in the SUSPENDED class (Section 8.4): TLS sockets remain open but
SPVA channel operations are paused; plain-TCP fallback (where
negotiated) remains usable. The connections resume normal SPVA
operation when the renewal completes and the cert-status
transitions back to ``VALID``.

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
certificate must have been issued. PVACMS (Section 10) issues
certificates in response to a Certificate Creation Request
(Section 9). The CCR carries an authenticator-specific verifier
in its ``verifier`` sub-structure that PVACMS uses to verify the
requesting principal's identity at issuance time.

Three issuance authenticators are defined:

- ``authnstd`` — issuance with administrator approval. The CCR is
  submitted without external credential proof. PVACMS issues the
  certificate in ``PENDING_APPROVAL`` state (Section 8.2). The
  certificate becomes ``VALID`` only when an administrator
  performs a PUT to the certificate's status PV.
- ``authnkrb`` — Kerberos. The principal obtains a GSS-API token
  for the PVACMS service principal (output of
  ``gss_init_sec_context``) plus a Message Integrity Check; both
  travel in the CCR as ``verifier.token`` and ``verifier.mic``.
  PVACMS verifies via ``gss_accept_sec_context`` against its
  service keytab.
- ``authnldap`` — LDAP. The principal performs an LDAP bind
  locally to prove identity, then signs the CCR contents with the
  principal's own private key. The signature travels in the CCR
  as ``verifier.signature``. PVACMS verifies the signature against
  the LDAP-bound principal's public key.

The CCR submission to PVACMS uses PVA RPC (Section 9). The
issuance authenticators are not SPVA-protocol messages on their
own; they are CCR ``verifier`` payloads.

----

7. Certificate-Status Monitoring
================================

7.1. Cert-Status PV Naming
--------------------------

PVACMS publishes a cert-status PV per issued certificate. The PV
name follows the pattern:

::

    <prefix>:STATUS:<issuer-skid>:<cert-serial>

where:

- ``<prefix>`` is the configurable cert-PV prefix (default
  ``CERT``); set via ``EPICS_PVAS_CERT_PV_PREFIX``.
- ``<issuer-skid>`` is the hex-encoded Subject Key Identifier of
  the certificate's issuer (the issuing CA).
- ``<cert-serial>`` is the hex-encoded serial number of the
  certificate.

This deterministic naming allows any party with a certificate to
construct the corresponding cert-status PV name without any
out-of-band lookup.

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
        u64         renew_by             # per-certificate renew_by hint
                                         #  (UTC seconds; Section 8.5)
        bool        renewal_due          # convenience: now >= renew_by
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
                                         #  empty if PVACMS does not provide it
        string      pvacms_node_id       # PVACMS-cluster member that
                                         #  produced this update
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

The ``ocsp_response`` field is populated when PVACMS provides an
OCSP-style status response; otherwise it is empty (zero-length
byte array). Section 13 covers OCSP stapling separately.

A response whose ``timeStamp`` plus the configured cert-status
validity duration has passed MUST be treated as ``UNKNOWN`` per
Section 8.4.

7.3. Subscription Flow
----------------------

If the peer certificate carries the ``SPvaCertStatusURI``
extension (Section 4.3), the endpoint reads the PV name from the
extension and subscribes to that PV using PVA ``CMD_MONITOR``
(PVA Section 9.5) against the PVACMS server. The subscription
runs for the lifetime of the connection.

Each cert-status update drives the connection's state per the
mapping in Section 8.4. Updates and connection-state transitions
are asynchronous; the connection is not held open or torn down
synchronously with respect to handshake completion.

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
            ▼
     PENDING_APPROVAL  ◄────┐ (admin)
            │               │
            │ approve        │ deny
            │                │
            ▼                ▼
        PENDING          REVOKED  (terminal)
            │
            │ cert generated and delivered
            ▼
          VALID  ◄────────┐
            │ │ │         │
            │ │ └─ revoke (admin or CA policy) ─► REVOKED (terminal)
            │ │
            │ └─ admin pause ─► SCHEDULED_OFFLINE
            │                          │
            │                          ▼ admin resume
            │                        VALID
            │
            │ time crosses ``renew_by`` (Section 8.5)
            ▼
     PENDING_RENEWAL ──── renewal completed ────► VALID
            │
            │ no renewal in time
            ▼
        EXPIRED  (terminal)

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
   | ``UNKNOWN``            | PVACMS cannot determine status (e.g.    |
   |                        | certificate serial unknown to PVACMS,   |
   |                        | or status response not current).        |
   +------------------------+-----------------------------------------+
   | ``PENDING_APPROVAL``   | CCR submitted; awaiting administrator   |
   |                        | approval.                               |
   +------------------------+-----------------------------------------+
   | ``PENDING``            | CCR approved; certificate generation    |
   |                        | in progress (transient state).          |
   +------------------------+-----------------------------------------+
   | ``VALID``              | Certificate issued, in date, not        |
   |                        | revoked.                                |
   +------------------------+-----------------------------------------+
   | ``PENDING_RENEWAL``    | Time has crossed the per-certificate    |
   |                        | ``renew_by`` (Section 8.5); renewal     |
   |                        | requested.                              |
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

- ``[no entry]`` → ``PENDING_APPROVAL`` (CCR submitted, requires
  admin approval)
- ``[no entry]`` → ``PENDING`` (CCR auto-approved by site policy)
- ``PENDING_APPROVAL`` → ``PENDING`` (admin approval)
- ``PENDING_APPROVAL`` → ``REVOKED`` (admin denial)
- ``PENDING`` → ``VALID`` (certificate generated and delivered)
- ``VALID`` → ``REVOKED`` (admin revocation or CA policy
  revocation)
- ``VALID`` → ``SCHEDULED_OFFLINE`` (admin pause)
- ``SCHEDULED_OFFLINE`` → ``VALID`` (admin resume)
- ``SCHEDULED_OFFLINE`` → ``REVOKED`` (admin revocation while
  paused)
- ``VALID`` → ``PENDING_RENEWAL`` (auto, on time crossing
  ``renew_by``)
- ``PENDING_RENEWAL`` → ``VALID`` (renewal completed)
- ``PENDING_RENEWAL`` → ``REVOKED`` (admin revocation while
  renewing)
- ``VALID`` or ``PENDING_RENEWAL`` → ``EXPIRED`` (auto, on
  ``notAfter``)

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
   |                        |             | operations are paused. Plain-TCP fallback |
   |                        |             | (where negotiated) remains usable. The    |
   |                        |             | connection upgrades to GOOD on transition |
   |                        |             | to ``VALID`` or moves to BAD on           |
   |                        |             | revocation/expiry.                        |
   +------------------------+-------------+-------------------------------------------+
   | ``PENDING_RENEWAL``    | SUSPENDED   | Same as ``SCHEDULED_OFFLINE``: TLS socket |
   |                        |             | kept, channels paused, plain-TCP fallback |
   |                        |             | usable. Resumes on the renewal completing |
   |                        |             | (transition to ``VALID``).                |
   +------------------------+-------------+-------------------------------------------+
   | ``REVOKED``            | BAD         | Connection MUST be closed; the endpoint   |
   |                        |             | enters degraded mode and refuses further  |
   |                        |             | TLS connections involving this            |
   |                        |             | certificate.                              |
   +------------------------+-------------+-------------------------------------------+
   | ``EXPIRED``            | BAD         | Same as ``REVOKED``.                      |
   +------------------------+-------------+-------------------------------------------+
   | ``UNKNOWN``            | UNKNOWN     | TLS not yet ready; plain-TCP fallback     |
   |                        |             | (where negotiated) remains usable. The    |
   |                        |             | endpoint waits for a status update that   |
   |                        |             | resolves to GOOD, SUSPENDED, or BAD.      |
   +------------------------+-------------+-------------------------------------------+
   | ``PENDING``            | UNKNOWN     | Same as ``UNKNOWN``.                      |
   +------------------------+-------------+-------------------------------------------+
   | ``PENDING_APPROVAL``   | UNKNOWN     | Same as ``UNKNOWN``.                      |
   +------------------------+-------------+-------------------------------------------+

A non-current cert-status response (``status_valid_until_date``
in the past) MUST be treated as ``UNKNOWN`` regardless of the
underlying ``status`` field.

Status-class transitions take effect within an implementation-
defined window of the cert-status update arriving at the endpoint.

8.5. Renewal Hint (renew_by)
----------------------------

Each certificate carries a separate **renew_by** time published in
the cert-status PVStructure (Section 7.2's ``renew_by`` field), set
at issuance time by the chosen authenticator. ``renew_by`` is
distinct from ``status_valid_until_date`` (which controls cert-
status response freshness, Section 7.2) and from ``notAfter``
(which is the cryptographic expiry, Section 4.7.1).

When the current time crosses ``renew_by``, PVACMS transitions the
certificate's status from ``VALID`` to ``PENDING_RENEWAL``. The
certificate-holder SHOULD initiate a renewal Certificate Creation
Request (Section 9.4) on receiving this transition. ``renew_by``
is therefore a per-certificate, authenticator-set policy hint, not
a fixed global threshold; an authenticator MAY set ``renew_by``
equal to ``notAfter`` to suppress the renewal-hint mechanism for
certificates that should not auto-renew.

See Section 4.7.3 for the relationship between ``renew_by``,
``notAfter``, and ``status_valid_until_date``.

----

9. Certificate Creation Request (CCR)
======================================

9.1. CCR PVStructure Schema
---------------------------

A Certificate Creation Request is submitted to PVACMS via PVA RPC
(``CMD_RPC``, PVA Section 9.6) targeting the well-known PV name
``<prefix>:CREATE[:<issuer_id>]`` (default prefix ``CERT``). The
optional trailing ``:<issuer_id>`` selects a specific issuer in
multi-issuer PVACMS deployments; without it the deployment's
default issuer is used. The RPC's request value is a CCR
PVStructure:

::

    structure CCR
        string             type             # authenticator: "std", "krb", or "ldap"
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

The ``verifier`` sub-structure is per-authenticator (Section 6.2):

- ``type = "std"``: ``verifier`` is empty.
- ``type = "krb"``: ``verifier = { token: byte[], mic: byte[] }``
  — GSS-API initial-context token plus message integrity check.
- ``type = "ldap"``: ``verifier = { signature: byte[] }`` —
  base64-encoded signature over the CCR contents, made with the
  principal's own private key after a successful LDAP bind has
  proved identity.

9.2. CCR Submission
-------------------

A CCR is submitted via:

::

    Channel<RPC>: <prefix>:CREATE[:<issuer_id>]
    Request: CCR PVStructure
    Response: structure { string cert_pem; status }

On success, the response contains the PEM-encoded issued
certificate. On failure, the response Status is ERROR or FATAL
with a descriptive message.

9.3. CCR Authorization
----------------------

PVACMS applies site-defined policy to decide whether to approve a
CCR. The policy MAY:

- Auto-approve any CCR matching certain ``type``+``organization``
  combinations.
- Require admin approval (transition through ``PENDING_APPROVAL``)
  for any CCR not auto-approved.
- Reject CCRs based on ``name`` patterns (e.g. reserve
  ``CN=admin``).

The authorization policy is OUT OF SCOPE of this specification; it
is a deployment concern of PVACMS administrators.

9.4. Renewal CCR
----------------

A renewal CCR is identical to a fresh CCR but the requested
``name``, ``organization``, etc. match an existing certificate that
is in ``VALID`` or ``PENDING_RENEWAL`` state. PVACMS detects this
as a renewal and SHOULD auto-approve (assuming the requesting
principal can prove possession of the prior private key — typically
by signing the CCR itself).

----

10. PVACMS Service
==================

10.1. PVACMS as a PVA Server
----------------------------

PVACMS runs as a PVA server. It exposes its functions through
two distinct kinds of well-known PVs under a configurable
PV-name prefix (default ``CERT``):

- **Operational PVs** — conventional readable / monitorable PVs
  that publish PVACMS state. Clients access them with PVA's
  ``CMD_GET`` and ``CMD_MONITOR``. These cover per-certificate
  status, service health, service metrics, the issuer
  certificate's metadata, and the root Certification Authority
  (root CA) certificate's metadata. They are not RPC entry
  points — they are state PVs that any cert-bearing client may
  read or subscribe to (subject to the EPICS access security
  configuration file rules; see Section 11).

- **Action PVs** — RPC entry points (PVA ``CMD_RPC``) that
  cause PVACMS to perform a privileged operation. These cover
  certificate creation, admin approval of pending requests,
  admin revocation, and scheduled-operation submission.

PVACMS itself is an SPVA-secured server: clients connecting to
PVACMS MUST use Transport Layer Security (TLS), and PVACMS's own
server certificate MUST be issued by a trust anchor common to
all participating endpoints.

10.2. PVACMS PV Namespace
-------------------------

.. table:: PVACMS well-known PVs (operational)
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
   | ``<prefix>:ISSUER:<skid>``          | GET      | Issuer certificate metadata    |
   |                                     |          | (Subject Distinguished Name,   |
   |                                     |          | validity, public-key digest,   |
   |                                     |          | full chain).                   |
   +-------------------------------------+----------+--------------------------------+
   | ``<prefix>:ROOT:<skid>``            | GET      | Root CA certificate metadata.  |
   +-------------------------------------+----------+--------------------------------+

.. table:: PVACMS well-known PVs (action / RPC)
   :widths: auto

   +-------------------------------------+----------+--------------------------------+
   | PV name                             | Access   | Purpose                        |
   +=====================================+==========+================================+
   | ``<prefix>:CREATE``                 | RPC      | Submit a Certificate Creation  |
   |                                     |          | Request (Section 9). Open to   |
   |                                     |          | any client whose authenticator |
   |                                     |          | the PVACMS recognises.         |
   +-------------------------------------+----------+--------------------------------+
   | ``<prefix>:SCHEDULE``               | RPC      | Submit a scheduled-operation   |
   |                                     | (admin)  | request (e.g. scheduled        |
   |                                     |          | revocation).                   |
   +-------------------------------------+----------+--------------------------------+
   | ``<prefix>:APPROVE``                | RPC      | Approve a pending CCR (drives  |
   |                                     | (admin)  | the ``PENDING_APPROVAL`` →     |
   |                                     |          | ``PENDING`` state transition;  |
   |                                     |          | see Section 8.3).              |
   +-------------------------------------+----------+--------------------------------+
   | ``<prefix>:REVOKE``                 | RPC      | Revoke an issued certificate.  |
   |                                     | (admin)  |                                |
   +-------------------------------------+----------+--------------------------------+

Admin RPCs are gated by EPICS access security rules that require
the calling principal to be in the PVACMS administrators role
(Section 11).

The ``<prefix>:STATUS:<skid>:<serial>`` PV is implemented as a
*wildcard PV* — a single server-side PV pattern that
materialises one channel per actually-issued certificate, rather
than a fixed set of pre-registered PVs. This allows the channel
list to grow with the certificate population without redeploying
PVACMS.

10.3. PVACMS Identity
---------------------

PVACMS itself has an X.509 server certificate, issued by the same
CA chain as the endpoint certificates it issues. PVACMS's
certificate's Subject DN typically has CN matching ``pvacms`` or
the deployment's chosen service name; clients SHOULD verify that
the PVACMS they connect to has the expected DN before submitting
CCRs.

10.4. PVACMS Cluster Mode
-------------------------

A site MAY deploy PVACMS as a cluster of servers sharing the same
CA-signing private key (or operating as a hot-standby). Cluster
membership is OUT OF SCOPE of this specification; clients see only
"PVACMS" as a single logical service. In cluster deployments,
clients SHOULD discover the active PVACMS endpoint via DNS round-
robin or an explicit service-discovery mechanism.

10.5. PVACMS Certificate Authority Operations
---------------------------------------------

PVACMS performs these CA operations on every approved CCR:

1. Verify the requesting principal's identity via the CCR's
   ``verifier`` (authenticator-specific).
2. Generate a fresh certificate serial number (typically a 128-bit
   random integer).
3. Construct an X.509 certificate body matching the CCR's
   ``name`` / ``organization`` / etc., with validity per site
   policy (capped at the requested ``not_after``).
4. Sign the certificate with PVACMS's CA private key.
5. Insert the certificate's status entry into the PVACMS database
   with state ``VALID``.
6. Return the PEM-encoded certificate to the client in the CCR
   response.

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

A transition into the SUSPENDED or UNKNOWN class MUST NOT close
the underlying TLS socket; channel operations are paused per
Section 8.4 until the next transition.

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
- Insider attacks at PVACMS (a malicious operator can issue
  certificates).
- Denial-of-service against PVACMS. PVACMS unavailability prevents
  fresh cert-status updates; existing GOOD-class connections
  continue with cached cert-status until ``status_valid_until_date``
  expires, after which they transition to UNKNOWN class (Section
  8.4); new connections involving certificates with the
  ``SPvaCertStatusURI`` extension cannot acquire an initial
  cert-status update and proceed in the UNKNOWN class.

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
Section 7.1) allows any party with PVACMS access to enumerate
live certificates. Sites with stricter privacy needs SHOULD
restrict cert-status PV access via authorization rules
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
  the TLS-related fields of ``ConfigCommon``. Consulted in
  preparing this specification.
- **pvxs-cms implementation** — https://github.com/slac-epics/pvxs-cms;
  in particular ``src/common/certstatus.h`` (the cert-status
  PVStructure schema), ``src/common/certfactory.h`` (the
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
