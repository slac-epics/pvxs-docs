.. _glossary:

|security| SPVA Glossary
==========================

.. _glossary_spva:

- SPVA — Secure PVAccess.

  The set of extensions to the PVAccess protocol that add TLS 1.3 transport
  encryption, mutual X.509 certificate authentication, certificate lifecycle
  management (via PVACMS), and fine-grained access control (via SAG/METHOD/AUTHORITY
  ACF predicates). SPVA is the umbrella term for the combination of pvxs TLS
  transport, pvxs-cms certificate authority tools, and EPICS Base access-security
  extensions described in this documentation.

.. _glossary_auth_vs_authz:

- Auth or ``AuthN`` (Authentication) vs ``AuthZ`` (Authorization).

  In cybersecurity, these abbreviations are commonly used to differentiate between two distinct aspects of the security process.

  - ``Authentication`` refers to the process of verifying the validity of the credentials and claims presented within a security token, ensuring that the entity is who or what it claims to be.
  - ``Authorization``, on the other hand, is the process of determining and granting the appropriate access permissions to resources based on the authenticated entity's credentials and associated privileges.

.. _glossary_certificate_subject:

- Certificate’s Subject.

  This is a way of referring to all the fields in the X.509 certificate that identify the entity.  These are:-

  - ``CN``: common name e.g. ``slac.stanford.edu``;
  - ``O``: organization e.g. ``Stanford National Laboratory``;
  - ``OU``: organizational unit e.g. ``SLAC Certificate Authority``;
  - ``C``: country e.g. ``US``.

  In Secure PVAccess:

  - the ``CN`` common name stores

    - the device name e.g. ``KLYS:LI16:21``,
    - or username e.g. ``greg``,
    - or process name  e.g. ``archiver``.

    For Certificate Authorities the ``CN`` field will be

    - the name of the Certificate Authority, e.g. ``SLAC Certificate Authority`` or ``ORNL Certificate Authority``.
      This field value is used in an ``ASG`` ``AUTHORITY`` rule to identify the certificate issuer.

  - the ``O`` organization field stores

    - the hostname e.g. ``centos01``,
    - the IP Address e.g. ``192.168.3.2``,
    - the realm e.g. ``SLAC.STANFORD.EDU``,
    - or another domain identifier.

  - the ``OU`` organizational unit field stores

    - is optional but can be used to store the organizational unit e.g. ``PEP II``, or ``LCLS``.

  - the ``C`` country field stores

    - the country e.g. ``US``

.. _glossary_client_certificate:

- Client Certificate, Server Certificate, X.509.

  In cryptography, a client certificate is a type of digital certificate that is used by client systems
  to make authenticated requests to a remote server which itself has a server certificate.
  They contain claims that are signed by a Certificate Authority that is trusted by the peer certificate user.
  All Secure PVAccess certificates are ``X.509`` certificates.

.. _glossary_custom_extension:

- Custom Extension, for X.509 Certificates.

  The ``X.509`` certificate format allows for the inclusion of custom extensions, (``RFC 5208``),
  which are data blobs encoded within certificates and signed alongside other certificate claims.
  In Secure PVAccess, we use a custom extension ``status_monitoring_extension``.
  If present, the extension mandates that a certificate shall only be considered valid only if
  its status is successfully verified retrieved from the PV provided within the extension and that the certificate status received is ``VALID``.

.. _glossary_diskless_server:
.. _glossary_diskless_node:
.. _glossary_network_computer:
.. _glossary_ioc_client:

- Diskless Server, Diskless Node, Network Computer, IOC.

  A network device without disk drives, which employs network booting to load its operating system from a server, and network mounted drives for storage.

.. _glossary_epics_agents:

- EPICS Agents.

  Refers to any EPICS client, server, gateway, or tool.

.. _glossary_epics_security:

- EPICS Security.

  The EPICS technology that provides user Authorization.  It is configured using an Access Control File (ACF).



.. _glossary_ccr:

- CCR — Certificate Creation Request.

  The PVAccess RPC message sent by an authenticator tool (``authnstd``,
  ``authnkrb``, ``authnldap``) to PVACMS to request a signed X.509 certificate.
  The CCR carries the public key, requested subject fields (CN/O/OU/C), desired
  validity period, SANs, schedule windows, and authenticator-specific verifier
  data (e.g. a Kerberos GSSAPI token). PVACMS verifies the CCR, signs the
  certificate, and returns it to the requester.

.. _glossary_cert_status_pv:

- Certificate Status PV (``CERT:STATUS``).

  A PVAccess channel published by PVACMS for each managed certificate, named
  ``CERT:STATUS:<issuer_id>:<serial>``. Clients and servers subscribe to this
  PV to receive live certificate status updates (``VALID``, ``PENDING_RENEWAL``,
  ``SCHEDULED_OFFLINE``, ``REVOKED``, etc.) and the ``renewal_due`` hint.
  The SPVA status monitoring extension embedded in the X.509 certificate provides
  the PV name so that peers can subscribe automatically on first connection.

.. _glossary_degraded_mode:

- DegradedMode.

  A TLS context state in which TLS is not offered or accepted because the entity's
  own certificate is permanently invalid (``REVOKED`` or ``EXPIRED``) or no
  certificate or Trust Anchor is configured. The entity falls back to plain TCP.
  This is a terminal state for a given certificate; recovery requires a new
  certificate to be provisioned.

.. _glossary_keychain:

- Keychain file (PKCS#12 / ``.p12``).

  The PKCS#12 file that stores an EPICS agent's private key, its X.509
  certificate, and the certificate chain up to the Trust Anchor (Root CA). The
  keychain file path is configured via ``EPICS_PVA_TLS_KEYCHAIN`` (client) or
  ``EPICS_PVAS_TLS_KEYCHAIN`` (server). The private key never leaves this file;
  it is used locally for the TLS handshake and CCR signing.

.. _glossary_kerberos:
.. _glossary_kerberos_ticket:

- Kerberos, Kerberos Ticket.

  - A protocol for authenticating service requests between trusted hosts across an untrusted network, such as the internet.
  - Kerberos support is built into all major computer operating systems, including Microsoft Windows, Apple macOS, FreeBSD and Linux.
  - A Kerberos ticket is a certificate issued by an authentication server (Key Distribution Center - ``KDC``) and encrypted using that server’s key.
  - Two ticket types:

    - A Ticket Granting Ticket (``TGT``) allows clients to subsequently request Service Tickets
    - Service Tickets are passed to servers as the client’s credentials.

  - An important distinction with Kerberos is that it uses a symmetric key system where the same key used
    to encode data is used to decode it therefore that key is never shared and so only the KDC
    can verify a Kerberos ticket that it has issued – clients or servers can’t independently verify that a ticket is valid.

.. _glossary_mtls:

- mTLS — Mutual TLS.

  A TLS connection mode in which both the client and the server present X.509
  certificates and authenticate each other during the TLS 1.3 handshake. In SPVA
  this is the ``Mutual`` authentication mode; access-control rules see
  ``METHOD("x509")`` and ``PROTOCOL("tls")``. Contrast with *server-only TLS*
  where only the server certificate is presented.

.. _glossary_ocsp:

- OCSP — Online Certificate Status Protocol.

  A modern alternative to the Certificate Revocation List (CRL) for checking
  whether a digital certificate is valid or has been revoked. While standard
  OCSP is served over HTTP, SPVA adapts the OCSP response format and delivers
  signed OCSP responses over PVAccess via the ``CERT:STATUS`` PV, including
  OCSP stapling (embedding a signed status response in the TLS handshake).

.. _glossary_ocsp_stapling:

- OCSP Stapling.

  A TLS extension (RFC 6066) in which the server attaches a cached, CA-signed
  OCSP response to the TLS handshake, saving the client a separate status-check
  round-trip. In SPVA, PVACMS signs OCSP responses for each certificate, and
  servers can staple them in the TLS handshake so clients receive an immediately
  trusted status without contacting PVACMS at connection time.

.. _glossary_pending_renewal:

- ``PENDING_RENEWAL``.

  A certificate status indicating that the certificate's ``renew_by`` deadline
  has passed without a renewal CCR being received. The certificate is still
  technically valid (``not_after`` has not been reached) but is treated as
  ``SUSPENDED`` by pvxs: no new TLS connections are established, but existing
  mTLS connections remain open. The status automatically returns to ``VALID``
  when a valid renewal CCR arrives.

.. _glossary_pvacms:

- PVACMS — PVAccess Certificate Management System.

  The certificate authority server provided by the ``pvxs-cms`` module. PVACMS
  issues, stores, renews, and revokes X.509 certificates for EPICS agents. It
  publishes certificate status over PVAccess (``CERT:STATUS``, ``CERT:HEALTH``,
  ``CERT:METRICS``) and accepts certificate management commands via ``pvxcert``.

.. _glossary_renewal_daemon:

- Renewal daemon (``authn<method> -D``).

  A long-running mode of the SPVA authenticator tools (``authnstd -D``,
  ``authnkrb -D``, ``authnldap -D``) that monitors the entity's own
  ``CERT:STATUS`` PV and automatically submits a renewal CCR when
  ``renewal_due = true`` is received. The renewal extends the ``renew_by``
  deadline on the existing certificate without issuing a new certificate or
  modifying the keychain file.

.. _glossary_renewal_due:

- ``renewal_due``.

  A boolean field in the ``CERT:STATUS`` PV, set to ``true`` by PVACMS when the
  current time passes the midpoint between the last status-date and the
  ``renew_by`` deadline. It is a proactive hint: the certificate is still
  ``VALID``, but authenticators (and the renewal daemon) should submit a CCR
  now to avoid the certificate entering ``PENDING_RENEWAL``.

.. _glossary_renew_by:

- ``renew_by``.

  A soft expiry date embedded in a certificate's PVACMS database record and
  broadcast on its ``CERT:STATUS`` PV. When ``now >= renew_by``, the certificate
  transitions to ``PENDING_RENEWAL``. For Kerberos-authenticated certificates,
  ``renew_by`` is set to ``now + remaining_ticket_lifetime`` at issuance,
  effectively tying the SPVA certificate's renewal cycle to the Kerberos ticket
  lifecycle.

.. _glossary_pkcs12:

- PKCS#12 - Public Key Cryptography Standard.

  In cryptography, ``PKCS#12`` defines an archive file format for storing many cryptography objects as a single file.
  It is commonly used to bundle a private key with its ``X.509`` certificate and/or to bundle all the members of a chain of trust.
  It is defined in ``RFC 7292``.
  We use PKCS#12 files to store:

  - the Root Certificate Authority's Certificate that is the trust anchor for all TLS operations in an EPICS agent
  - the EPICS agent's public / private key pair,
  - the EPICS agent's certificate created using the public key.
  - the Certificate Authority keychain

  The PKCS#12 files are referenced by environment variables described in the :ref:`configuration`.

.. _glossary_sag:

- SAG — SAN Access Group.

  An EPICS access-security predicate (defined in an ACF file alongside ``UAG``
  and ``HAG``) that restricts access based on Subject Alternative Name (SAN)
  entries from the client's TLS certificate. ``SAG`` entries can match IP
  addresses (exact or CIDR subnet) and DNS names (exact or glob). A client
  without SANs — e.g. a plain-TCP connection — automatically fails the SAG
  predicate. See :ref:`spvaauthorization` for the full syntax.

.. _glossary_scheduled_offline:

- ``SCHEDULED_OFFLINE``.

  A certificate status indicating that the certificate is within a configured
  offline schedule window (see :ref:`validity_schedules`). The certificate is
  operationally suspended during the window and returns to ``VALID``
  automatically when the window ends. Treated as ``SUSPENDED`` by pvxs.

.. _glossary_tcponly:

- TcpOnly.

  A TLS context state in which the entity has a certificate but it is not yet
  operationally usable (status ``PENDING``, ``PENDING_APPROVAL``,
  ``SCHEDULED_OFFLINE``, or ``PENDING_RENEWAL`` before TLS was ever established).
  Plain-TCP connections are accepted while the status monitor waits for ``VALID``.
  Once confirmed, the context upgrades automatically to ``TlsReady``.

.. _glossary_tcpready:

- TcpReady.

  A TLS context state in which the entity's certificate was previously ``GOOD``
  (``TlsReady``) but the most recent status is ``UNKNOWN`` (e.g. PVACMS is
  momentarily unreachable). TCP connections are accepted while waiting for
  status to recover to ``GOOD``.

.. _glossary_trust_anchor:

- Trust Anchor (Root CA certificate).

  The self-signed Root CA certificate that an EPICS agent uses to verify peer
  certificate chains. Any certificate whose chain does not trace back to the
  Trust Anchor is rejected at the TLS handshake. Distributed as a PKCS#12 file
  via ``authnstd --trust-anchor`` or ``authnkrb --trust-anchor``.

.. _glossary_skid:

- SKID — Subject Key Identifier.

  - Uniquely identifies a key pair by hashing the public key, linking the
    certificate to the underlying key pair.
  - In SPVA, the SKID is the persistent identity for an entity across certificate
    renewals: because the same private key is reused, the SKID remains constant.
  - For display, only the first 8 hex characters are shown — the ``issuer_id``
    prefix in ``<issuer_id>:<serial>`` certificate IDs.

