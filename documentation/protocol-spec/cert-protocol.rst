.. _certificate_management:

|security| Cert Management
===========================

.. _certificates_and_private_keys:

Public and Private Keys
-----------------------

Each EPICS agent maintains a public/private key pair for identification:

- The public key identifies the agent to peers. Its shorthand representation is an 8-character SKID.
- The private key must be protected like a password.
- Both keys are stored in the keychain file.
- If the keychain file contains no key pair, any ``authnxxx`` tool will generate one automatically and store it there.
- An established key pair is reused for all subsequent certificate requests.

Identity assertion works as follows: each peer presents a certificate and signs a challenge with its private key. The verifying peer checks the signature against the public key in the certificate, then validates the certificate's chain of trust back to its own Trust Anchor (Root CA).

Private keys must be stored in a keychain file inaccessible to other users or processes. Use a separate keychain file per certificate.

Trust Establishment
-------------------

Each EPICS agent must have a copy of the Root CA certificate in its keychain file to verify certificates presented by peers. A certificate signed by an untrusted CA is rejected.

Even agents that do not hold their own certificate must have a copy of the Root CA, referred to here as the ``Trust Anchor``.

Administrators distribute PKCS#12 files containing the Root certificate to all clients. These files must be stored at the path specified by ``EPICS_PVA_TLS_KEYCHAIN`` or its equivalent.

Certificates
------------

A certificate is the document exchanged with a peer to establish identity. It contains the agent's subject name and public key.

- A certificate is not private and can be shared with any peer. The keychain file that stores it also contains the private key and must not be shared.
- A certificate is valid for a fixed time period.
- A certificate can be revoked by an administrator (status monitoring is included by default).

Certificate Attributes
----------------------

- ``subject``: The entity to which the certificate was issued

  - ``name``: Common name (username, application name, or other identifier)
  - ``organization``: Hostname, institution, domain, or realm
  - ``organizational unit``: Optional subdivision of the organization
  - ``country``: Two-letter country code. Default: ``US``

- ``issuer``: The certificate authority that issued the certificate
- ``serial number``: Unique serial number for the certificate
- ``validity period``:

  - ``notBefore``: Date and time before which the certificate is not valid
  - ``notAfter``: Date and time after which the certificate is not valid

- ``public key``: Public key of the certificate subject
- ``private key``: Private key of the certificate subject. Not stored in the certificate; stored in the keychain file.
- ``SPVA certificate status extension``: PV name where certificate status can be monitored
- ``SPVA config uri extension``: PV name where certificate configuration can be monitored

Certificate States
------------------

.. figure:: certificate_states.png
    :alt: Certificate States
    :width: 75%
    :align: left
    :name: certificate-states

- ``PENDING_APPROVAL``: Awaiting administrative approval
- ``PENDING``: Not yet valid (before ``notBefore`` date)
- ``VALID``: Currently valid and usable
- ``PENDING_RENEWAL``: Valid but past its ``renew_by`` date; a renewed certificate is
  expected to be issued shortly. Treated as :ref:`SUSPENDED <suspended_cert_status>` by
  pvxs clients. Before this state is entered, PVACMS posts a :ref:`renewal_due_hint`
  to prompt authenticators to renew proactively.
- ``SCHEDULED_OFFLINE``: Certificate is within a configured offline schedule window (see
  :ref:`validity_schedules`). The certificate will return to ``VALID`` when the window
  ends. Treated as :ref:`SUSPENDED <suspended_cert_status>` by pvxs clients.
- ``EXPIRED``: Past ``notAfter`` date; permanently non-operational.
- ``REVOKED``: Permanently revoked by an administrator.

.. _certificate_status_message:

Certificate Status Message
--------------------------

Status response structure:

.. code-block:: console

    Structure
        enum_t     status               # PENDING_APPROVAL, PENDING, VALID, PENDING_RENEWAL,
                                        # SCHEDULED_OFFLINE, EXPIRED, REVOKED
        UInt64     serial               # Certificate serial number
        string     state                # String representation of status
        enum_t     ocsp_status          # GOOD, REVOKED, UNKNOWN
        string     ocsp_state           # OCSP state string
        string     ocsp_status_date     # Status timestamp
        string     ocsp_certified_until # Validity period end
        string     ocsp_revocation_date # Revocation date if applicable
        UInt8A     ocsp_response        # Signed PKCS#7 encoded OCSP response
        string     pvacms_node_id       # "<issuer_id>:<node_id>" of the serving PVACMS node
                                        # (empty for single-node deployments)
        UInt64     renew_by             # Epoch seconds: deadline by which a renewal CCR should
                                        # be submitted to avoid entering PENDING_RENEWAL
        bool       renewal_due          # true once now >= midpoint(last_status_date, renew_by);
                                        # a hint to authenticators to submit a renewal CCR now
        StructA    schedule             # Current validity schedule windows (if any)
            string     day_of_week      # "0"–"6" (Sun–Sat) or "*" (every day)
            string     start_time       # "HH:MM" UTC
            string     end_time         # "HH:MM" UTC

.. _renewal_due_hint:

Renewal-Due Hint (``renewal_due``)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``renewal_due`` is a proactive renewal signal published by PVACMS on the ``CERT:STATUS``
PV while the certificate is still ``VALID``. Its purpose is to give authenticators
(``authnstd``, ``authnkrb``, ``authnldap``) enough advance warning to submit a new
Certificate Creation Request (CCR) *before* the certificate enters ``PENDING_RENEWAL``,
keeping renewal transparent to end users.

**Trigger condition**

PVACMS sets ``renewal_due = true`` and re-posts the status PV when:

.. code-block:: text

    now  >=  midpoint(last_status_date, renew_by)
    i.e. 2 × now  >=  last_status_date + renew_by

In other words, once the current time is at least halfway between the timestamp of the
last status update and the ``renew_by`` deadline. Only ``VALID`` certificates that have
not yet had ``renewal_due`` set are considered. PVACMS processes at most one such
certificate per status-monitor cycle to spread load. Once posted, the flag is cleared in
the database so the same certificate is not re-posted on the next cycle.

**Client behaviour**

Authenticators subscribe to their own entity certificate's ``CERT:STATUS`` PV. When a
status update arrives with ``renewal_due = true``, the authenticator automatically
submits a CCR to PVACMS. PVACMS first performs full identity verification on the CCR
(Kerberos ticket, LDAP signature, etc.), then looks up an existing certificate with
matching subject fields (CN, O, OU, C) that has ``renewal_due`` set in the database.
When found, it extends the ``renew_by`` deadline — **no new certificate is issued and
the keychain file is not modified**. The match is on subject fields, not on the SKID
or public key; the cryptographic assurance comes entirely from the authenticator's
``verify()`` step. The updated ``renew_by`` date is broadcast on the
``CERT:STATUS`` PV; the ``CERT:CONFIG`` PV is also updated. If the CCR fails, the
authenticator logs an error and waits for the next status update before retrying. The
certificate remains ``VALID`` throughout; ``PENDING_RENEWAL`` is only entered if
``renew_by`` passes without a successful renewal CCR.

**Timeline**

.. code-block:: text

    Certificate issued (keychain file written once)
         │
         ▼  [VALID]   renewal_due = false
         │
         │   ... time passes ...
         │
         ▼  now >= midpoint(last_status_date, renew_by)
         │  [VALID]   renewal_due = true  ← posted on CERT:STATUS
         │                ↑
         │          authenticator sees renewal_due=true, submits CCR
         │          PVACMS extends renew_by on the *existing* certificate
         │          (no new cert issued, keychain file unchanged)
         │
         ├── CCR succeeds ──►  [VALID]  extended renew_by, renewal_due=false
         │                     status broadcast on CERT:STATUS
         │
         └── renew_by passes without CCR ──►  [PENDING_RENEWAL]

**pvxcert output**

Both fields appear in the ``pvxcert`` certificate status block:

.. code-block:: text

    Renewal Due    : Yes
    Renew By       : 2026-09-01 00:00:00 UTC

.. _certificate_creation_request_CCR:

Certificate Creation Request (CCR)
-----------------------------------

Sent to :ref:`pvacms` to request a new certificate. The request is a PVStructure with the following fields:

.. code-block:: console

    Structure
        string     type               # std, krb, ldap
        string     name               # Certificate subject name
        string     country            # Optional: Country code
        string     organization       # Optional: Organization name
        string     organization_unit  # Optional: Unit name
        UInt16     usage              # Certificate usage flags:
                                        #   0x01: Client
                                        #   0x02: Server
                                        #   0x03: Client and Server
                                        #   0x04: Intermediate Certificate Authority
                                        #   0x08: CMS
                                        #   0x0A: Any Server
                                        #   0x10: Certificate Authority
        UInt32     not_before         # Validity start time (epoch seconds)
        UInt32     not_after          # Validity end time (epoch seconds)
        string     pub_key            # Public key data
        enum_t     status_monitoring_extension  # Include status monitoring
        structure  verifier           # Optional: Authenticator specific data

The ``verifier`` sub-structure is present only when ``type`` references a
:ref:`pvacms_type_1_auth_methods` or :ref:`pvacms_type_2_auth_methods` authenticator.

.. seealso::

   :doc:`/programmers-ref/cert-management` — how a programmer drives the
   certificate-request flow against the protocol described above.
