.. _cert_management:

Certificate Management
======================

This page covers the application-developer view of Secure-PVAccess
certificate management: the shape of the request a client sends and what
it gets back. The protocol-level details (certificate format, lifecycle
states, on-the-wire status PVStructure schema, the wire-side CCR schema)
are in :doc:`/protocol-spec/cert-protocol` — read that first if you need
to know what the messages look like on the wire.

.. seealso::

   :doc:`/protocol-spec/cert-protocol` — protocol-level certificate
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
