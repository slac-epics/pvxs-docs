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
  certificates to clients and servers that do not yet have them,
  using site-defined authentication mechanisms (Kerberos, LDAP,
  password) to verify the requesting principal's identity.

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
- The set of authentication mechanisms (Section 6): the standard
  ``x509`` mechanism, and the bootstrapping mechanisms
  ``authnstd`` (password), ``authnkrb`` (Kerberos),
  ``authnldap`` (LDAP).
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
   A bootstrap mechanism by which a non-yet-certified principal
   proves its identity to PVACMS in order to obtain a certificate.
   Examples: ``authnstd`` (administrator-pre-approved password),
   ``authnkrb`` (Kerberos service ticket), ``authnldap`` (LDAP
   bind).

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

   - ``server_name`` extension naming the server's expected DNS or
     IP name (per :rfc:`6066`).
   - ``signature_algorithms`` extension limited to algorithms
     SPVA-acceptable (Section 3.3).
   - ``status_request`` extension requesting OCSP stapling
     (:rfc:`6066`, Section 13).

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

A client SHALL send the TLS ``server_name`` extension (:rfc:`6066`)
identifying the server it expects to connect to. The server's
certificate Subject Alternative Name (SAN) MUST contain a matching
DNS name or IP address (Section 4.5).

3.7. Session Resumption
-----------------------

TLS 1.3 session tickets are PERMITTED but OPTIONAL. Implementations
SHOULD support them for performance. Tickets MUST NOT be reused
across server restarts; servers MUST issue fresh
PSK/resumption secrets on each startup.

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

SPVA endpoints use X.509 v3 certificates (:rfc:`5280`). All
extensions referenced below are standard PKIX extensions; SPVA does
not introduce custom OIDs.

4.2. Required Standard PKIX Extensions
--------------------------------------

Every SPVA certificate MUST contain:

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
- **Subject Alternative Name** (``id-ce-subjectAltName``):
  Section 4.5.
- **Authority Key Identifier** (``id-ce-authorityKeyIdentifier``):
  REQUIRED for entity certificates.
- **Subject Key Identifier** (``id-ce-subjectKeyIdentifier``):
  REQUIRED.

4.3. SPVA Custom X.509 Extensions
---------------------------------

In addition to the standard Public Key Infrastructure for X.509
(PKIX) extensions of Section 4.2, SPVA defines two custom X.509
extensions that embed the names of the per-certificate management
Process Variables (PVs) directly into the issued certificate. This
allows endpoints to discover the certificate-status PV and the
configuration PV without having to construct the names from the
issuer Subject Key Identifier and serial number — the certificate
itself carries the Universal Resource Identifier (URI) for each.

Both extensions are issued under the IANA Private Enterprise
Number arc ``1.3.6.1.4.1`` (see :rfc:`2578`). The two enterprise
sub-arcs used (``37427.1`` and ``72473.1``) are not yet
IANA-registered to the EPICS community; sites deploying SPVA MUST
treat the values given below as the normative Object Identifiers
for these extensions, and registration with IANA is anticipated.

.. table:: SPVA custom X.509 extensions
   :widths: auto

   +-----------------------------+----------------------------+--------------------------------------+
   | Extension name              | Object Identifier          | Description                          |
   +=============================+============================+======================================+
   | SPvaCertStatusURI           | ``1.3.6.1.4.1.37427.1``    | EPICS SPVA Certificate Status URI    |
   +-----------------------------+----------------------------+--------------------------------------+
   | SPvaCertConfigURI           | ``1.3.6.1.4.1.72473.1``    | EPICS SPVA Certificate Config URI    |
   +-----------------------------+----------------------------+--------------------------------------+

4.3.1. SPvaCertStatusURI Extension
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Object Identifier: ``1.3.6.1.4.1.37427.1``

Critical: ``FALSE`` (a non-SPVA-aware verifier MAY ignore the
extension safely; SPVA-aware code MUST honor it).

Value type: ``IA5String`` (American Standard Code for Information
Interchange characters; see :rfc:`5280` Section 4.2.1.6).

Value: the PV name (full URI, no transport prefix) where the
certificate-status PV for this certificate is published. The
default form is ``<cert_pv_prefix>:STATUS:<issuer_id>:<serial>``
where:

- ``<cert_pv_prefix>`` is the configurable Process Variable Access
  Certificate Management Service (PVACMS) PV prefix
  (default ``CERT``; configurable via
  ``EPICS_PVAS_CERT_PV_PREFIX``).
- ``<issuer_id>`` is the issuer's Subject Key Identifier, hex-
  encoded.
- ``<serial>`` is the certificate's serial number, hex-encoded.

A site MAY use any URI form it pleases; the string in the extension
is authoritative. The ``<prefix>:STATUS:<issuer>:<serial>``
construction described in Section 7.1 is the conventional default,
not a wire-protocol requirement.

The extension MAY be omitted when the issuing PVACMS is configured
with status-subscription disabled for this entity (the
``no_status`` issuance flag); endpoints reading a certificate
without this extension MUST treat it as having no status-monitoring
binding and MUST decide locally whether to accept connections to or
from that entity in the absence of certificate-status information.

4.3.2. SPvaCertConfigURI Extension
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Object Identifier: ``1.3.6.1.4.1.72473.1``

Critical: ``FALSE``.

Value type: ``IA5String``.

Value: the PV name of the entity's configuration PV, an SPVA-only
PV that publishes per-entity runtime configuration the entity
should pick up at startup or on subscription updates (for example:
the Online Certificate Status Protocol responder URL, the
recommended renewal-threshold window, the cert-status cache time-
to-live). The default form is
``<cert_pv_prefix>:CONFIG:<issuer_id>:<skid>`` where ``<skid>`` is
the entity's own Subject Key Identifier, hex-encoded.

This extension is OPTIONAL. PVACMS adds it only when the issuance
configuration provides a non-empty configuration URI base
(``cert_config_uri_base_`` in the issuer code path); endpoints
processing a certificate without this extension MUST NOT subscribe
to a configuration PV for that entity. The configuration PV's
content is out of scope of this specification (it is a deployment
concern of PVACMS, documented in :doc:`/user-manual/pvacms`).

4.3.3. Critical Bit and Backward Compatibility
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Both custom extensions are issued with the ``critical`` bit
``FALSE`` per :rfc:`5280` Section 4.2. This means a generic X.509
verifier (e.g. a TLS library on a non-SPVA endpoint) MAY ignore the
extension without rejecting the certificate. SPVA-aware endpoints
MUST honor the extensions when present.

A certificate carrying these extensions remains a fully-conformant
X.509 v3 certificate per :rfc:`5280` and may be used as such by
non-SPVA software (e.g. the certificate is also valid for use as a
generic Transport Layer Security server certificate, provided the
Extended Key Usage and Subject Alternative Name fields are
appropriate for the non-SPVA use).

4.4. Subject Distinguished Name
-------------------------------

The Subject DN of an SPVA certificate identifies the principal. SPVA
constrains the DN form to:

::

    Subject:  CN=<principal-name>, O=<org-name>[, OU=<unit>]

The ``CN`` (Common Name) is the principal's identity string. For
host-bound principals (e.g. an IOC certificate), CN is the
fully-qualified DNS name. For user-bound principals (e.g. an
operator's client certificate), CN is the username or service-account
name. The ``O`` (Organization) is the site or facility identifier.
The optional ``OU`` (Organizational Unit) MAY be used to distinguish
sub-organisations.

The full ``CN=…, O=…[, OU=…]`` string is the principal name used in
ASG/ACF authorization rules (Section 11).

4.5. Subject Alternative Name
-----------------------------

The SAN extension carries the network identities the certificate is
authoritative for. SPVA supports two SAN types:

- ``dNSName``: a DNS host name. For server certificates, this MUST
  match the hostname the client uses to connect (the
  ``server_name`` extension in TLS ClientHello).
- ``iPAddress``: an IPv4 or IPv6 address. Used for SPVA endpoints
  identified by IP rather than DNS.

A server certificate MAY contain multiple ``dNSName`` and/or
``iPAddress`` SAN entries (e.g. for multi-homed servers). A client
certificate's SAN, if present, MAY contain ``rfc822Name`` (email)
or ``otherName`` for site-specific principal naming, but its primary
identity is the Subject DN.

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
**operational** validity (whether the cert-status protocol of
Section 7 currently asserts the certificate is in an
operationally-good state, Section 8.4).

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
when admitting or maintaining a connection (Section 5.1, Section
7). An operationally-valid certificate is one whose cert-status
PV currently reports a status in the operationally-good set
(``VALID``, ``PENDING_RENEWAL``; see Section 8.4) AND whose
status response's ``status_valid_until_date`` has not passed.

The cert-status response's ``status_valid_until_date`` field
defines the freshness window: a cached or stapled cert-status
response is honored only until this time, after which a fresh
response MUST be obtained. PVACMS sets ``status_valid_until_date``
per its configured cert-status validity duration; the
configuration interface is the environment variable
``EPICS_PVACMS_CERT_STATUS_VALIDITY_MINS`` (a duration in
minutes). Endpoints obtain fresh status either by maintaining a
live cert-status subscription (Section 7.3, the typical case) or,
if subscription is unavailable, by re-querying.

This design — long cryptographic lifetime, short operational
window — means that revocation, suspension, and policy changes
propagate within the cert-status validity window (typically tens of
minutes) rather than being bounded by the certificate's
``notAfter``. A revoked certificate becomes operationally invalid
within at most one ``status_valid_until_date`` interval after
PVACMS records the revocation, regardless of whether the
certificate's ``notAfter`` is days or years away.

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
a renewal Certificate Creation Request (Section 9.4) but MAY
continue using the current certificate for operations until the
renewal completes; ``PENDING_RENEWAL`` is in the operationally-good
set so existing connections are not disrupted while the holder
arranges renewal. The renewal hint is policy-driven, not
cryptographic: it gives the operator a controlled re-key cadence
that is independent of (and typically much shorter than)
``notAfter``.

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

When a client connects to an SPVA server:

1. TCP three-way handshake to the SPVA server port.
2. TLS 1.3 handshake (Section 3) with mutual authentication and
   peer certificate path validation (Section 4.5).
3. Cert-status check: each side queries (or has cached) the other's
   certificate status (Section 7) and rejects the connection if
   the status is not ``VALID`` or ``PENDING_RENEWAL`` (the
   "operationally good" set; Section 8.4).
4. PVA ``CMD_CONNECTION_VALIDATION`` (PVA Section 6) is exchanged
   inside the TLS tunnel.

The TLS handshake MUST complete before any PVA byte is exchanged.
A failed peer certificate validation (chain verification fails,
status is ``REVOKED`` or ``EXPIRED``) MUST cause TLS handshake
abort with a TLS Alert.

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
4.3). The identity is normalized to the form ``CN=<x>, O=<y>[,
OU=<z>]`` for use in:

- Authorization rule lookup (Section 11).
- Cert-status monitor key (issuer + serial; not the DN directly).
- Audit logs (typically the full DN string).

----

6. Authentication Mechanisms
============================

6.1. Standard Mechanism: ``x509``
---------------------------------

The default and primary SPVA authentication mechanism is ``x509`` —
mutual TLS authentication with X.509 certificates as described in
Sections 3 through 5. Once both endpoints have valid certificates
(issued by PVACMS or any trusted CA), ``x509`` requires no
additional protocol round-trips beyond the TLS handshake itself.

6.2. Bootstrap Mechanisms (For Cert Issuance)
---------------------------------------------

Before an endpoint can use ``x509``, it must HAVE an X.509
certificate. PVACMS (Section 10) issues certificates to endpoints
that authenticate via one of three bootstrap mechanisms:

- ``authnstd`` (Standard) — administrator-pre-approved password.
  The principal supplies a password to the ``authnstd`` tool, which
  verifies it against PVACMS-side ACL and submits a CCR.
- ``authnkrb`` (Kerberos) — the principal obtains a Kerberos
  service ticket for PVACMS, sends it to the ``authnkrb`` tool,
  which forwards the ticket to PVACMS in the CCR. PVACMS verifies
  the ticket against its keytab.
- ``authnldap`` (LDAP) — the principal supplies LDAP credentials;
  ``authnldap`` performs an LDAP bind, on success submits a CCR
  with an LDAP-signed assertion of the bound DN.

The bootstrap mechanisms run OUTSIDE the SPVA-protected channel —
they connect to PVACMS via plain TCP and rely on PVACMS to bind
the bootstrap identity to the issued certificate. Once the
certificate is issued and installed in the principal's keychain,
all subsequent SPVA traffic uses ``x509``.

6.3. CMD_AUTHNZ in SPVA
-----------------------

PVA's ``CMD_AUTHNZ`` (command 5, PVA Section 6.4) is reserved for
SPVA bootstrap-mechanism continuation. The format of its payload is
authenticator-specific:

- For ``authnstd``: ``CMD_AUTHNZ`` is not used; the password is
  carried in the CCR's ``verifier`` sub-structure (Section 9).
- For ``authnkrb``: ``CMD_AUTHNZ`` payload is the Kerberos AP-REQ
  service ticket (binary, opaque to PVA).
- For ``authnldap``: ``CMD_AUTHNZ`` payload is the LDAP bind
  challenge/response (handled by the underlying LDAP library).

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

The cert-status PV's value is a PVStructure with the following
fields:

::

    structure PVACertificateStatus
        enum_t      status               # certificate state (Section 8)
        time_t      status_date          # when this status was set
        time_t      status_valid_until_date  # when this status entry expires
        time_t      status_set_at        # when the certificate was issued
        time_t      revocation_date      # if REVOKED, when (else 0)
        structure   ocsp                 # optional OCSP response data
            byte[]      ocsp_bytes       # raw OCSP response (RFC 6960)
            enum_t      ocsp_status      # GOOD / REVOKED / UNKNOWN
            time_t      status_date
            time_t      status_valid_until_date
            time_t      revocation_date

The ``status`` enum has values from ``certstatus_t``: ``UNKNOWN``,
``PENDING_APPROVAL``, ``PENDING``, ``VALID``, ``EXPIRED``,
``REVOKED``, ``PENDING_RENEWAL``, ``SCHEDULED_OFFLINE``.

The ``ocsp`` sub-structure is populated when PVACMS provides an
OCSP-style status response (Section 13). It allows the
cert-status PV to act as a cache for OCSP responses, avoiding a
separate OCSP query.

7.3. Subscription Flow
----------------------

When an SPVA endpoint completes a TLS handshake, it constructs the
cert-status PV name for the peer's certificate (Section 7.1) and
subscribes to that PV using PVA ``CMD_MONITOR`` (PVA Section 9.5)
against the PVACMS server.

The first monitor update delivers the certificate's current
status. The endpoint MUST wait for this first update before
considering the connection operational. If the first update has
``status`` outside the operationally-good set (Section 8.4), the
endpoint MUST close the SPVA connection.

For the lifetime of the SPVA connection, the endpoint maintains
the cert-status subscription. If a subsequent update transitions
the status to a non-operationally-good state, the endpoint MUST
close the SPVA connection within an implementation-defined window
(typically a few hundred milliseconds).

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

    [requesting party submits CCR]
              │
              ▼
       PENDING_APPROVAL  ◄─────┐ (admin can approve)
              │                │
              │ approve        │ deny
              │                │
              ▼                ▼
          PENDING          REVOKED  (terminal)
              │
              │ certificate generation
              │ + delivery to subject
              ▼
            VALID  ◄─────────┐
              │ │  │         │
              │ │  └──── revoke (admin) ──┐
              │ │                         ▼
              │ │                     REVOKED  (terminal)
              │ │                         ▲
              │ ├────── auto-revoke ──────┤  (CA policy)
              │ │
              │ └────── pause/maintenance ───►  SCHEDULED_OFFLINE
              │              │
              │              ▼ resume
              │            VALID
              │
              │ near-expiry (7 days before)
              ▼
       PENDING_RENEWAL ────────► VALID  (after renewal)
              │
              │ no renewal in time
              ▼
           EXPIRED  (terminal)

8.2. State Definitions
----------------------

.. table:: SPVA certificate lifecycle states
   :widths: auto

   +------------------------+-----------------------------------------+
   | State                  | Meaning                                 |
   +========================+=========================================+
   | ``UNKNOWN``            | PVACMS cannot determine status (e.g.    |
   |                        | the certificate's serial is not in its  |
   |                        | database). Connections MUST be          |
   |                        | rejected.                               |
   +------------------------+-----------------------------------------+
   | ``PENDING_APPROVAL``   | A CCR has been submitted but PVACMS     |
   |                        | requires administrator approval before  |
   |                        | issuance.                               |
   +------------------------+-----------------------------------------+
   | ``PENDING``            | CCR approved; certificate generation    |
   |                        | in progress (transient state).          |
   +------------------------+-----------------------------------------+
   | ``VALID``              | Certificate issued, in date, not        |
   |                        | revoked. Connections accepted.          |
   +------------------------+-----------------------------------------+
   | ``PENDING_RENEWAL``    | Certificate still valid but approaching |
   |                        | expiry; renewal recommended.            |
   |                        | Connections accepted.                   |
   +------------------------+-----------------------------------------+
   | ``EXPIRED``            | Validity period has passed. Terminal.   |
   |                        | Connections rejected.                   |
   +------------------------+-----------------------------------------+
   | ``REVOKED``            | Certificate has been revoked by CA      |
   |                        | action. Terminal. Connections rejected. |
   +------------------------+-----------------------------------------+
   | ``SCHEDULED_OFFLINE``  | Certificate temporarily inactive (e.g.  |
   |                        | scheduled maintenance). Connections     |
   |                        | rejected during this window.            |
   +------------------------+-----------------------------------------+

8.3. State Transitions
----------------------

The full set of permitted transitions:

- ``[no entry]`` → ``PENDING_APPROVAL`` (CCR submitted, requires
  admin)
- ``[no entry]`` → ``PENDING`` (CCR auto-approved by site policy)
- ``PENDING_APPROVAL`` → ``PENDING`` (admin approval)
- ``PENDING_APPROVAL`` → ``REVOKED`` (admin denial)
- ``PENDING`` → ``VALID`` (certificate generated and delivered)
- ``VALID`` → ``REVOKED`` (admin revocation, CA policy revocation,
  or compromise notification)
- ``VALID`` → ``SCHEDULED_OFFLINE`` (admin pause)
- ``SCHEDULED_OFFLINE`` → ``VALID`` (admin resume)
- ``VALID`` → ``PENDING_RENEWAL`` (auto, near-expiry)
- ``PENDING_RENEWAL`` → ``VALID`` (renewal completed)
- ``VALID`` or ``PENDING_RENEWAL`` → ``EXPIRED`` (auto, on
  ``notAfter`` date)

8.4. Operationally-Good Set
---------------------------

For purposes of admitting an SPVA connection, the
"operationally-good" status set is:

::

    {VALID, PENDING_RENEWAL}

Any other status MUST cause the connection to be rejected (or
torn down if already established).

``PENDING_RENEWAL`` is included because the certificate is still
in date and validly issued; it is just approaching expiry. Tearing
down operational connections during the renewal window would
disrupt service unnecessarily.

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
``<prefix>:CCR:CREATE`` (default prefix ``CERT``). The RPC's
request value is a CCR PVStructure:

::

    structure CCR
        string      type                   # authenticator name (e.g. "x509", "krb")
        string      name                   # principal name (CN component of Subject)
        string      organization           # site / facility (O component)
        string      organization_unit      # optional OU
        string      country                # 2-letter ISO country code
        string      pub_key                # PEM-encoded public key (PKCS#1 or SPKI)
        time_t      not_before             # requested validity start
        time_t      not_after              # requested validity end
        enum_t      use                    # CLIENT, SERVER, or BOTH
        u32         status_monitoring_extension  # 0 = disabled, 1 = enabled
        structure   verifier               # optional, authenticator-specific
            ...                            # type-specific fields

The ``verifier`` sub-structure carries data the chosen authenticator
needs to validate the requesting principal's identity:

- ``authnstd``: empty or ``{ password: string }``.
- ``authnkrb``: ``{ ap_req: byte[] }`` carrying the Kerberos
  service ticket.
- ``authnldap``: ``{ ldap_dn: string, ldap_signature: byte[] }``.

9.2. CCR Submission
-------------------

A CCR is submitted via:

::

    Channel<RPC>: <prefix>:CCR:CREATE
    Request: CCR PVStructure
    Response: structure { string cert_pem; status }

The response, on success, contains the PEM-encoded issued
certificate that the client installs in its keychain. On failure,
the response Status is ERROR or FATAL with a descriptive message.

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

11. Authorization (ACF Extensions)
==================================

11.1. ASG/ACF Background
------------------------

EPICS uses an "Access Security Group" (ASG) configuration in an
"Access Control File" (ACF) to control which principals may read,
write, or otherwise act on which PVs. ASG/ACF was designed for CA
where the principal name was advisory; SPVA elevates the principal
name to cryptographically-verified status.

11.2. ASG Rule Form (Standard EPICS)
------------------------------------

A standard ASG rule:

::

    ASG(group_name) {
        RULE(asg_level, READ|WRITE|RPC) {
            UAG(allowed_users)
            HAG(allowed_hosts)
        }
    }

Where ``UAG`` is "user access group" and ``HAG`` is "host access
group", referring to lists defined elsewhere in the ACF.

11.3. SPVA Extensions
---------------------

SPVA extends ASG/ACF rules with:

- **Verified principal names**. The ``UAG`` membership now refers
  to the ``CN=…, O=…`` DN extracted from the X.509 certificate
  (Section 5.3), not the PVA ``CMD_CONNECTION_VALIDATION``
  user-name string.
- **Authentication-method match** (``METHOD``). A rule MAY require
  the connection to use a specific authenticator (e.g.
  ``METHOD=x509`` or ``METHOD=krb``).
- **Authorisation-list match** (``AUTHORITY``). A rule MAY require
  the certificate's issuing CA's Subject DN to match a configured
  pattern.

Example SPVA-extended ASG rule:

::

    ASG(spva_admin) {
        RULE(1, WRITE) {
            UAG(operators)            # CN=...,O=... matches operators list
            METHOD(x509)              # only mTLS-authenticated connections
            AUTHORITY(my-site-ca)     # cert issued by named CA
        }
    }

11.4. ACL Change Notification
-----------------------------

When the ACF is reloaded at the server, PVACMS or the affected
PVA server MAY emit ``CMD_ACL_CHANGE`` (PVA Section 13) to
already-connected clients to update their cached access rights.
SPVA does not change the ``CMD_ACL_CHANGE`` wire format.

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

12.3. TLS-First Discovery
-------------------------

For SPVA-required deployments, clients MAY send searches with only
``protocols = ["tls"]`` (no fallback). Servers without SPVA support
will silently ignore; the client will only connect to SPVA-capable
servers. This provides a hard policy guarantee that no plaintext
connection is ever attempted.

----

13. OCSP Stapling
=================

13.1. Stapling Rationale
------------------------

OCSP stapling (:rfc:`6066` Section 8, :rfc:`6961`) embeds the OCSP
response into the TLS handshake itself. This avoids the latency and
privacy issues of a client-initiated OCSP query at handshake time:
the server includes a recent OCSP response (signed by the issuing CA)
in its TLS Certificate message.

13.2. Stapled Status Format
---------------------------

The stapled OCSP response is a standard OCSP response per
:rfc:`6960`. SPVA does not modify the OCSP format. The client MUST
verify:

- The OCSP response's signature against the issuing CA.
- The OCSP response's ``thisUpdate`` is recent (typically within
  the last hour).
- The OCSP response's ``certStatus`` is ``GOOD``.

A stapled OCSP with ``certStatus`` ``REVOKED`` MUST cause the TLS
handshake to abort.

13.3. Stapling Source
---------------------

PVACMS provides OCSP responses via the ocsp sub-structure of the
cert-status PV (Section 7.2). An SPVA server SHOULD obtain its own
stapling response by subscribing to its own cert-status PV and
caching the most recent OCSP response. Implementations MAY refresh
the stapled response on each TLS handshake or MAY cache for the
``status_valid_until_date`` window.

13.4. Stapling Optional
-----------------------

SPVA endpoints SHOULD support OCSP stapling but MAY operate without
it. When stapling is unavailable, endpoints fall back to the
cert-status monitor (Section 7) for revocation awareness.

----

14. Connection Reconfiguration
==============================

14.1. Runtime Keychain Rotation
-------------------------------

SPVA endpoints support runtime certificate rotation without process
restart via the ``reconfigure()`` API (see
:doc:`/programmers-ref/expert-api`). When called, the endpoint:

1. Closes all existing TLS connections (with a clean TLS Alert).
2. Re-reads the keychain file.
3. Re-establishes connections under the new identity.

The wire-protocol consequence is that all SPVA peers see TLS
connection close, followed by a new TLS handshake (with the new
certificate) when the connection is re-established.

14.2. Triggers
--------------

Reconfiguration is typically triggered by:

- The cert-status monitor reporting ``PENDING_RENEWAL``, after
  which the endpoint completes a renewal CCR (Section 9.4) and
  reconfigures with the new certificate.
- An administrator manually replacing the keychain file (e.g. for
  an emergency revocation recovery).
- A scheduled rotation policy.

14.3. Connection Re-Establishment Sequence
------------------------------------------

After ``reconfigure()``:

1. All TLS connections close; PVA channels enter DISCONNECTED state.
2. The endpoint's PVA connection-management logic re-attempts
   connections per its standard reconnection policy.
3. New TLS handshakes use the new keychain.
4. Channels re-create on the new connections.
5. Subscriptions re-establish.

The application code that depends on the channels SHOULD be
prepared for a brief disconnection during reconfiguration; pvxs
provides reconnection-aware monitor wrappers
(see :doc:`/programmers-ref/expert-api`).

----

15. Error Handling
==================

15.1. TLS Handshake Failures
----------------------------

A failed TLS handshake (cert validation fails, cert expired, no
common cipher suite, etc.) MUST result in a TLS Alert per
:rfc:`8446`. The client SHOULD log the alert and SHOULD NOT retry
immediately; backoff per implementation.

15.2. Cert-Status Mid-Connection
--------------------------------

If a peer's cert-status transitions to a non-operationally-good
state during a connection, the endpoint MUST close the SPVA
connection (TCP RST or clean TLS close) within an
implementation-defined window, with a descriptive log message.

The closing party MAY include a TLS Alert ``certificate_revoked``
(:rfc:`8446`) before the close.

15.3. CCR Failures
------------------

A CCR may fail with these statuses (returned in the CCR RPC
response):

- ``ERROR`` with message "verifier validation failed": the
  authenticator could not verify the principal's identity.
- ``ERROR`` with message "policy denied": site policy rejects the
  CCR.
- ``ERROR`` with message "duplicate certificate": a certificate
  with the requested name already exists and is not in
  ``PENDING_RENEWAL`` state.
- ``FATAL`` with message "PVACMS internal error": an unexpected
  PVACMS-side failure.

----

16. Version Negotiation
=======================

16.1. SPVA Wire Version
-----------------------

SPVA wire-protocol version 2 is defined by:

- PVA wire-protocol version 2 (:doc:`/protocol-spec/pva` Section 16).
- TLS 1.3 (:rfc:`8446`) as the only acceptable transport.
- The cert-status PVStructure schema and CCR PVStructure schema
  defined in this document.
- The set of authentication mechanisms in Section 6.

16.2. TLS Version Restriction
-----------------------------

SPVA endpoints MUST refuse TLS 1.2 or earlier (Section 3.1). There
is no negotiation here; TLS 1.3 is mandatory.

16.3. Future Wire Versions
--------------------------

Future SPVA versions MAY add new authentication mechanisms (e.g.
hardware-token-based bootstrapping), new cert-status fields (e.g.
hardware-attestation evidence), or new EKU restrictions. Any
such addition that would break compatibility with this version
MUST increment the SPVA wire-protocol version.

----

17. Security Considerations
============================

17.1. Threat Model
------------------

SPVA's threat model assumes:

- The network MAY contain on-path active attackers (eavesdropping
  + injection + modification).
- The CA's private key is held in trusted infrastructure.
- Endpoint private keys are protected by the OS keychain or HSM
  (per site policy).
- Authenticator credentials (passwords, Kerberos tickets) are
  protected by their underlying mechanisms.

SPVA defends against:

- Eavesdropping (TLS confidentiality).
- Modification (TLS integrity).
- Identity spoofing (X.509 mutual authentication).
- Stale credentials (cert-status monitoring + revocation).

SPVA does NOT defend against:

- Compromise of an endpoint's private key. The attacker can
  impersonate the endpoint until PVACMS marks the certificate
  ``REVOKED`` and the revocation propagates through the cert-status
  protocol. SPVA's design point here is that the impact window is
  bounded by ``status_valid_until_date`` (default 30 minutes,
  Section 7.2), NOT by ``notAfter`` — a long cryptographic lifetime
  (Section 4.7.1) does not extend the post-revocation impact
  window. The defence relies on the operator detecting the
  compromise; SPVA itself provides the revocation-propagation
  channel but cannot detect the compromise.
- CA compromise (catastrophic; recoverable only by re-issuing
  every endpoint certificate from a fresh CA).
- Insider attacks at PVACMS (a malicious admin can issue arbitrary
  certificates).
- Denial-of-service against PVACMS (no PVA connection can complete
  without cert-status check; PVACMS down → no new connections).

17.2. Cipher Suite Choice
-------------------------

SPVA mandates TLS 1.3 specifically because TLS 1.2 and earlier
versions allow choosing weak cipher suites (RC4, 3DES, DES,
NULL-encryption, EXPORT). All TLS 1.3 cipher suites are AEAD and
forward-secret.

17.3. PSK and 0-RTT
-------------------

SPVA forbids 0-RTT (early data) because PVA operations have
side-effects (PUT, RPC, PROCESS) and 0-RTT is replay-vulnerable
(:rfc:`8446` Section 8). PSK without 0-RTT is permitted as a
performance optimisation across reconnects.

17.4. Cert-Status Privacy
-------------------------

The cert-status PV name pattern (``<prefix>:STATUS:<skid>:<serial>``)
allows any party with a valid PVACMS connection to enumerate live
certificates by issuer. This is acceptable in the SPVA threat model
(insider-trust assumption); sites with stricter privacy needs
SHOULD restrict cert-status PV access via ACF rules to require an
authenticated principal in the PVACMS observers role.

17.5. Side-Channel Considerations
---------------------------------

SPVA's cryptographic operations are subject to standard side-channel
considerations (timing, cache, power). Implementations SHOULD use
constant-time crypto libraries (OpenSSL with appropriate
configuration; pvxs uses OpenSSL by default).

17.6. Fallback to Plain PVA
---------------------------

A client configured for ``["tls", "tcp"]`` fallback (Section 12) is
vulnerable to a downgrade attack: an active attacker on the search
path can suppress the TLS-capable server's reply and let only a
plaintext server's reply through. Sites requiring guaranteed SPVA
SHOULD configure clients with ``protocols = ["tls"]`` only.

----

18. IANA Considerations
=======================

18.1. Port Assignment
---------------------

SPVA uses TCP port 5076 by default. This is NOT IANA-registered. It
is configurable via ``EPICS_PVAS_TLS_PORT``.

18.2. URI Scheme
----------------

SPVA does not define a custom URI scheme.

18.3. ALPN
----------

SPVA does not currently use TLS ALPN (Section 3.9).

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
