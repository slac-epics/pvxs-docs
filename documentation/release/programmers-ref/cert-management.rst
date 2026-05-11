.. _cert_management:

Certificate Management
======================

This page covers the application-developer view of Secure-PVAccess
certificate management: the shape of the request a client sends and what
it gets back. The protocol-level details (certificate format, lifecycle
states, on-the-wire status PVStructure schema, the wire-side CCR schema)
are in :doc:`/programmers-ref/spva-cert-management-protocol` — read that first if you need
to know what the messages look like on the wire.

.. seealso::

   :doc:`/programmers-ref/spva-cert-management-protocol` — protocol-level certificate
   management: keys, trust establishment, certificate format, lifecycle
   states, on-the-wire status and CCR schemas.

How a programmer requests a certificate
---------------------------------------

A client requests a certificate from :doc:`/user-manual/pvacms` by
submitting a Certificate Creation Request (CCR) containing its public
key. The flow is:

1. Generate a key pair (typically the first ``authnxxx`` invocation does
   this automatically and stores it in the configured keychain file).
2. Submit a CCR. The CCR's ``verifier`` sub-structure carries the
   authenticator-specific payload (Kerberos ticket, LDAP signature, etc.)
   when the request comes from a Type 1 or Type 2 authenticator. See
   :ref:`certificate_creation_request_CCR` for the wire-level schema.
3. Receive the signed certificate from PVACMS.
4. Install the certificate at the keychain location configured by
   ``EPICS_PVA_TLS_KEYCHAIN`` (see
   :doc:`/programmers-ref/configuration`).

The resulting certificate is then used by pvxs's TLS context for
mutual-authentication handshakes, and its status is monitored against
PVACMS for the lifetime of the connection (see
:ref:`certificate_status_message`).

PVACMS-specific behaviour
-------------------------

The protocol specification (:doc:`/protocol-spec/spva`) describes the
Certificate Management Service abstractly — the states a certificate
can be in, the transitions clients can observe, and the PVStructure
schemas exchanged on the wire. The information below is specific to
**PVACMS**, the reference implementation of that service shipped with
``pvxs-cms``. Programmers writing client code against a PVACMS-backed
deployment will need it; programmers writing portable code against any
conforming Certificate Management Service should rely on the
protocol spec instead.

Certificate validity defaults (PVACMS configuration)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

PVACMS supplies default validity periods for issued certificates per
usage class. The relevant deployment-side environment variables are:

- ``EPICS_PVACMS_CERT_VALIDITY`` — default validity for all certificate
  usages unless a usage-specific setting overrides it.

- ``EPICS_PVACMS_CERT_VALIDITY_CLIENT`` — maximum validity for
  CLIENT certificates.
- ``EPICS_PVACMS_CERT_VALIDITY_SERVER`` — maximum validity for
  SERVER certificates.
- ``EPICS_PVACMS_CERT_VALIDITY_IOC`` — maximum validity for IOC
  certificates.

These settings accept :ref:`duration_strings`; a plain number means
minutes.

PVACMS uses these defaults when a certificate creation request omits
``not_after`` or when the corresponding ``disallow custom duration``
policy is enabled.

Cert-status freshness (PVACMS configuration)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The freshness horizon a cert-status update advertises via its
``status_valid_until_date`` field is set by PVACMS deployment
configuration:

- ``EPICS_PVACMS_CERT_STATUS_VALIDITY_MINS`` — number of minutes a
  PVACMS-issued cert-status response remains valid before clients
  must treat it as stale and downgrade the connection class to
  UNKNOWN (see protocol spec Section 8.4). Default 30 minutes.

Despite the historical ``_MINS`` suffix, this setting accepts
:ref:`duration_strings`; a plain number means minutes.

The protocol does not mandate this number — only that PVACMS attach
*some* finite ``status_valid_until_date`` to every status update.

Approval-bypass (issuance directly to ``VALID`` / ``PENDING``)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The protocol allows a CCR to issue directly into the post-approval
state set without passing through ``PENDING_APPROVAL``. PVACMS
selects this path when either condition holds (source:
``pvxs-cms/src/pvacms/pvacms.cpp:1815-1829``):

1. The CCR's authenticator is non-default (Kerberos, LDAP, …) and
   its ``verifier`` validates successfully — the authenticator's
   own verifier substitutes for administrator approval.
2. The CCR's authenticator is the default ``std`` authenticator and
   the matching site policy ``cert_<usage>_require_approval``
   (one of ``cert_ioc_require_approval``,
   ``cert_client_require_approval``, ``cert_server_require_approval``)
   is false.

In both cases, the cert-status the client first observes is whichever
time-based status the cryptographic clock dictates at issuance:
``PENDING`` if ``now < notBefore``, ``VALID`` if
``notBefore ≤ now < notAfter``, or (in the degenerate case of a
backdated short-lived certificate) ``EXPIRED`` if ``now ≥ notAfter``.

PVACMS cluster mode
~~~~~~~~~~~~~~~~~~~

A site MAY deploy PVACMS as a cluster of servers sharing the same
CA-signing private key (or operating as a hot-standby pair). Cluster
membership is opaque to clients — they see only one logical service.
In cluster deployments, clients SHOULD discover the active PVACMS
endpoint via DNS round-robin or an explicit service-discovery
mechanism. The wire-level ``pvacms_node_id`` field of a cert-status
update identifies which cluster member produced the update, useful
for debugging but not for client routing.

PVACMS Certificate Authority operations
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

On every approved CCR, PVACMS performs the following CA operations:

1. Verify the requesting principal's identity via the CCR's
   ``verifier`` (authenticator-specific).
2. Generate a fresh certificate serial number (typically a 128-bit
   random integer).
3. Construct an X.509 certificate body matching the CCR's
   ``name`` / ``organization`` / etc., with validity per site
   policy (capped at the requested ``not_after`` and at the
   per-usage ``EPICS_PVACMS_CERT_VALIDITY_*`` setting).
4. Sign the certificate with PVACMS's CA private key.
5. Insert the certificate's status entry into the PVACMS database
   with state ``VALID`` (or ``PENDING`` / ``PENDING_APPROVAL`` per
   the rules above).
6. Return the PEM-encoded certificate to the client in the CCR
   response.

Authenticator-specific verification
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The protocol spec (Section 6.2) defines the ``verifier`` payload
for each authenticator. The PVACMS-side verification logic is:

- ``std`` — no verifier; PVACMS trusts the supplied
  ``name``/``organization`` and gates issuance on the
  ``cert_<usage>_require_approval`` site policy described above.
- ``krb`` — PVACMS validates the GSS-API ``token`` against its
  configured Kerberos service principal and verifies the ``mic``
  over the CCR contents. A successful verification substitutes for
  administrator approval.
- ``ldap`` — PVACMS validates the ``signature`` over the CCR
  contents against the public key registered in LDAP for the
  requesting principal (which itself was retrieved after the
  principal completed an LDAP bind). A successful verification
  substitutes for administrator approval.

For the full set of authenticator runtime options (Kerberos keytabs,
LDAP base DN, etc.) see :doc:`/user-manual/pvacms`.
