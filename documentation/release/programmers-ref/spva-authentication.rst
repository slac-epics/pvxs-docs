.. _authn_and_authz:

|security| Authentication
==========================

:ref:`Authentication and Authorization<glossary_auth_vs_authz>` with Secure PVAccess.
**Authentication** (AuthN) determines and verifies identity; **Authorization** (AuthZ) enforces access rights to PV resources.

Secure PVAccess enhances EPICS access security with fine-grained control based on:

- Authentication Mode
- Authentication Method
- Certifying Authority
- Protocol

.. _authentication_modes:

Authentication Modes
------------------------

- ``Mutual`` (mTLS — mutual TLS): Both client and server present X.509 certificates and
  authenticate each other during the TLS 1.3 handshake. The connection is fully
  encrypted and both identities are cryptographically verified. In SPVA access control,
  ``METHOD`` is ``x509``. This is the recommended mode for all production deployments.
- ``Server-only`` (TLS with anonymous client): Only the server presents a certificate;
  the client verifies the server but sends no client certificate. The channel is
  encrypted but only the server identity is authenticated. In SPVA, ``METHOD`` is
  ``ca`` or ``anonymous`` with ``PROTOCOL`` set to ``tls``.
- ``Un-authenticated`` (legacy channel): Credentials supplied in the PVAccess
  ``AUTHZ`` message over a plain TCP connection (no TLS). In SPVA, ``METHOD`` is
  ``ca``. Backward-compatible with Classic Channel Access / legacy PVA clients.
- ``Unknown`` (anonymous legacy): No credentials and no TLS. In SPVA, ``METHOD``
  is ``anonymous``.

.. _determining_identity:

Legacy Authentication Mode
^^^^^^^^^^^^^^^^^^^^^^^^^^^

Methods:

- ``anonymous`` - ``Unknown``
- ``ca`` - ``Un-authenticated``

.. image:: pvaident.png
   :alt: Identity in PVAccess
   :align: center

1. Optional ``AUTHZ`` message from client:

.. code-block:: shell

    AUTHZ method: ca
    AUTHZ user: george
    AUTHZ host: McInPro.level-n.com

2. Server uses PeerInfo structure:

- :ref:`peer_info`

3. PeerInfo fields map to `asAddClient()` parameters ...
4. for authorization through the ``ACF`` definitions of ``UAG`` and ``ASG`` ...
5. to control access to PVs

Secure PVAccess Authentication Mode
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Methods:

- server: ``x509`` / client: ``x509`` - ``Mutual``
- server: ``x509`` - ``Server-Only``

.. image:: spvaident.png
   :alt: Identity in Secure PVAccess
   :align: center

1. Client identity optionally established via X.509 certificate during TLS handshake:

.. code-block:: shell

    CN: greg
    O: SLAC.stanford.edu
    OU: SLAC National Accelerator Laboratory
    C: US

2. EPICS agent optionally verifies certificate via trust chain

3. PeerCredentials structure provides peer information:

- :ref:`peer_credentials`

4. Extended ``asAddClientIdentity()`` function provides

- :ref:`identity_structure`

5. Secure authorization control enhanced with:

- ``METHOD``
- ``AUTHORITY``
- ``PROTOCOL``

through the ACF definitions of ASGs ...

6. to control access to PVs


.. _site_authenticators:

Site Authenticators
--------------------

Authenticators generate certificates and place them in the PKCS#12 keychain file using credentials (tickets, tokens, or other identity-affirming data) from existing authentication methods. Command-line tools prefixed with ``authn`` (e.g., ``authnstd``) are the interfaces to these authenticators.

Reference Authenticators
^^^^^^^^^^^^^^^^^^^^^^^^^

.. _pvacms_type_0_auth_methods:

TYPE ``0`` - Basic Credentials
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- Uses basic information:

  - CN: Common name

    - Commandline flag: ``-n`` ``--name``
    - Username

  - O: Organisation

    - Commandline flag: ``-o`` ``--organization``
    - Hostname
    - IP address

  - OU: Organisational Unit

    - Commandline flag: ``--ou``

  - C: Country

    - Commandline flag: ``-c`` ``--country``
    - Locale (not reliable)
    - Default = "US"

- No verification performed
- Certificates start in ``PENDING_APPROVAL`` state
- Requires administrator approval

.. _pvacms_type_1_auth_methods:

TYPE ``1`` - Independently Verifiable Tokens
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- Tokens verified independently or via endpoint
- Verification methods:

  - Token signature verification
  - Token payload validation
  - Verification endpoint calls

.. _pvacms_type_2_auth_methods:

TYPE ``2`` - Source Verifiable Tokens
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- Requires programmatic API integration (e.g., Kerberos)
- Adds verifiable data to :ref:`certificate_creation_request_CCR` message
- :ref:`pvacms` uses method-specific libraries for verification


Common Environment Variables for all Authenticators
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**Configuration options for Standard Authenticator**

+--------------------------------------------+------------------------------------+-----------------------------------------------------------------------+
| Name                                       | Keys and Values                    | Description                                                           |
+============================================+====================================+=======================================================================+
|| EPICS_PVA_AUTH_CERT_VALIDITY_MINS         || <duration string>                 || Requested certificate duration; see :ref:`duration_strings`.         |
||                                           || e.g. ``30``, ``1d``, ``1y6M``     || A plain number means minutes.                                        |
+--------------------------------------------+------------------------------------+-----------------------------------------------------------------------+
|| EPICS_PVA_AUTH_NAME                       || {name to use}                     || Name to use in new certificates                                      |
||                                           || e.g. ``archiver``                 ||                                                                      |
+--------------------------------------------+  e.g. ``IOC1``                     ||                                                                      |
|| EPICS_PVAS_AUTH_NAME                      || e.g. ``greg``                     ||                                                                      |
||                                           ||                                   ||                                                                      |
+--------------------------------------------+------------------------------------+-----------------------------------------------------------------------+
|| EPICS_PVA_AUTH_ORGANIZATION               || {organization to use}             || Organization to use in new certificates                              |
||                                           || e.g. ``site.epics.org``           ||                                                                      |
+--------------------------------------------+  e.g. ``SLAC.STANFORD.EDU``        ||                                                                      |
|| EPICS_PVAS_AUTH_ORGANIZATION              || e.g. ``KLYS:LI01:101``            ||                                                                      |
||                                           || e.g. ``centos07``                 ||                                                                      |
+--------------------------------------------+------------------------------------+-----------------------------------------------------------------------+
|| EPICS_PVA_AUTH_ORGANIZATIONAL_UNIT        || {organization unit to use}        || Organization Unit to use in new certificates                         |
||                                           || e.g. ``data center``              ||                                                                      |
+--------------------------------------------+  e.g. ``ops``                      ||                                                                      |
|| EPICS_PVAS_AUTH_ORGANIZATIONAL_UNIT       || e.g. ``prod``                     ||                                                                      |
||                                           || e.g. ``remote``                   ||                                                                      |
+--------------------------------------------+------------------------------------+-----------------------------------------------------------------------+
|| EPICS_PVA_AUTH_COUNTRY                    || {country to use}                  || Country to use in new certificates.                                  |
||                                           || e.g. ``US``                       || Must be a two digit country code                                     |
+--------------------------------------------+  e.g. ``CA``                       ||                                                                      |
|| EPICS_PVAS_AUTH_COUNTRY                   ||                                   ||                                                                      |
||                                           ||                                   ||                                                                      |
+--------------------------------------------+------------------------------------+-----------------------------------------------------------------------+
|| EPICS_PVA_AUTH_ISSUER                     || {issuer of cert. mgmt. service}   || The issuer ID to contact for any certificate operation.              |
||                                           || e.g. ``f0a9e1b8``                 || Must be am 8 character SKID                                          |
+--------------------------------------------+                                    ||                                                                      |
|| EPICS_PVAS_AUTH_ISSUER                    ||                                   || If there are PVACMS's from different certificate authorities         |
||                                           ||                                   || on the network, this allows you to specify the one you want          |
+--------------------------------------------+------------------------------------+-----------------------------------------------------------------------+
|| EPICS_PVA_CERT_PV_PREFIX                  || {certificate mgnt. prefix}        || Specify the prefix for the PVACMS PV to contact for new certificates |
||                                           || e.g. ``SLAC_CERTS``               || default ``CERT``                                                     |
+--------------------------------------------+                                    ||                                                                      |
|| EPICS_PVAS_CERT_PV_PREFIX                 ||                                   ||                                                                      |
||                                           ||                                   ||                                                                      |
+--------------------------------------------+------------------------------------+-----------------------------------------------------------------------+

Included Reference Authenticators
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

PVXS provides three reference authenticator implementations:

- ``authnstd`` : Standard Authenticator - unverified credentials, TYPE ``0``
- ``authnkrb`` : Kerberos Authenticator - Kerberos credentials verified by the KDC, TYPE ``2``
- ``authnldap``: LDAP Authenticator - LDAP directory login for identity verification, TYPE ``2``

authstd Configuration and Usage
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``authnstd`` is a TYPE ``0`` authenticator using explicitly specified, unverified credentials.

- ``CN``: logged-in username, overridden by ``-n``/``--name`` or ``EPICS_PVA_AUTH_NAME``/``EPICS_PVAS_AUTH_NAME``
- ``O``: hostname or IP address, overridden by ``-o``/``--organization`` or ``EPICS_PVA_AUTH_ORGANIZATION``/``EPICS_PVAS_AUTH_ORGANIZATION``
- ``OU``: not set by default, overridden by ``--ou`` or ``EPICS_PVA_AUTH_ORGANIZATIONAL_UNIT``/``EPICS_PVAS_AUTH_ORGANIZATIONAL_UNIT``
- ``C``: local country code, overridden by ``-c``/``--country`` or ``EPICS_PVA_AUTH_COUNTRY``/``EPICS_PVAS_AUTH_COUNTRY``

.. _authnstd_prior_approval:

**Prior-approval inheritance**

Because ``authnstd`` carries no cryptographic identity proof, PVACMS cannot verify the
caller's identity independently. When PVACMS is configured to require administrator
approval for a certificate type, a fresh CCR from ``authnstd`` initially lands in
``PENDING_APPROVAL``.

However, PVACMS checks the database for the most recent certificate whose subject
(CN, O, OU, C) exactly matches the incoming request and reads its ``approved`` flag. If
a prior certificate for the same subject was previously approved by an administrator,
the new certificate inherits that approval and moves directly to ``VALID`` — no
administrator intervention is needed again.

This means:

- First issuance for a new subject → ``PENDING_APPROVAL`` (admin must approve once)
- Subsequent requests with the same subject → automatically ``VALID``, inheriting
  the earlier approval

The match is purely on subject fields; a different public key (different SKID) for the
same subject still inherits the prior approval. If the prior certificate was **denied**
(``approved = 0``), the new request is also denied automatically.

**usage**

Uses the standard ``EPICS_PVA_TLS_<name>`` environment variables to determine the keychain and password file locations.

.. code-block:: shell

    authnstd - Secure PVAccess Standard Authenticator

    Generates client, server, or ioc certificates based on the Standard Authenticator.
    Uses specified parameters to create certificates that require administrator APPROVAL before becoming VALID.

    usage:
      authnstd [options]                         Create certificate in PENDING_APPROVAL state
      authnstd (-h | --help)                     Show this help message and exit
      authnstd (-V | --version)                  Print version and exit

    options:
      (-u | --cert-usage) <usage>                Specify the certificate usage.  client|server|ioc.  Default `client`
      (-n | --name) <name>                       Specify common name of the certificate. Default <logged-in-username>
      (-o | --organization) <organization>       Specify organisation name for the certificate. Default <hostname>
            --ou <org-unit>                      Specify organisational unit for the certificate. Default <blank>
      (-c | --country) <country>                 Specify country for the certificate. Default locale setting if detectable otherwise `US`
      (-t | --time) <duration>                   Duration of the certificate. e.g. 30 or 1d or 1y3M2d4m
            --cert-pv-prefix <cert_pv_prefix>     Specifies the pv prefix to use to contact PVACMS.  Default `CERT`
            --add-config-uri                      Add a config uri to the generated certificate
            --force                               Force overwrite if certificate exists
      (-a | --trust-anchor)                       Download Trust Anchor into keychain file.  Do not create a certificate
      (-s | --no-status)                          Request that status checking not be required for this certificate
      (-i | --issuer) <issuer_id>                 The issuer ID of the PVACMS service to contact.  If not specified (default) broadcast to any that are listening
      (-v | --verbose)                            Verbose mode
      (-d | --debug)                              Debug mode

The ``-t`` / ``--time`` value accepts :ref:`duration_strings`.


**Examples**

.. code-block:: shell

    # create a client certificate for greg@slac.stanford.edu
    authnstd -u client -n greg -o slac.stanford.edu

.. code-block:: shell

    # create a server certificate for IOC1
    authnstd -u server -n IOC1 -o "KLI:LI01:10" --ou "FACET"

.. code-block:: shell

    # create a client certificate for current user with no status monitoring
    authnstd --no-status


.. code-block:: shell

    # create a ioc certificate for gateway1
    authnstd -u ioc -n gateway1 -o bridge.ornl.gov --ou "Networking"


.. code-block:: shell

    # Download the Trust Anchor into your keychain file for server-only authenticated connections
    authnstd --trust-anchor

**Setup of standard authenticator in Docker Container for testing**

Source: ``/examples/docker/spva_std``

- users (unix)

  - ``pvacms`` - service
  - ``admin`` - principal with password "secret" (includes a configured PVACMS administrator certificate)
  - ``softioc`` - service principal with password "secret"
  - ``client`` - principal with password "secret"

- services

  - PVACMS


authkrb Configuration and Usage
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``authnkrb`` is a TYPE ``2`` authenticator. Certificates are generated from a Kerberos ticket obtained via ``kinit``.

.. code-block:: shell

    kinit -l 24h greg@SLAC.STANFORD.EDU

- ``CN``: Kerberos username
- ``O``: Kerberos realm
- ``OU``: not set
- ``C``: local country code

**usage**

Uses the standard ``EPICS_PVA_TLS_<name>`` environment variables to determine the keychain and password file locations.

.. code-block::

    authnkrb - Secure PVAccess Kerberos Authenticator

    Generates client, server, or ioc certificates based on the kerberos Authenticator.
    Uses current kerberos ticket to set the renewal date; certificate validity is set by PVACMS.

    usage:
      authnkrb [options]                         Create certificate
      authnkrb (-h | --help)                     Show this help message and exit
      authnkrb (-V | --version)                  Print version and exit

    options:
      (-u | --cert-usage) <usage>                Specify the certificate usage.  client|server|ioc.  Default ``client``
            --krb-validator <service-name>       Specify kerberos validator name.  Default ``pvacms``
            --krb-realm <krb-realm>              Specify the kerberos realm.  If not specified we'll take it from the ticket
            --cert-pv-prefix <cert_pv_prefix>    Specifies the pv prefix to use to contact PVACMS.  Default `CERT`
            --add-config-uri                     Add a config uri to the generated certificate
            --force                              Force overwrite if certificate exists
      (-s | --no-status)                         Request that status checking not be required for this certificate
      (-i | --issuer) <issuer_id>                The issuer ID of the PVACMS service to contact.  If not specified (default) broadcast to any that are listening
      (-v | --verbose)                           Verbose mode

**Extra options that are available in PVACMS**

.. code-block:: shell

    usage:
      pvacms [kerberos options]                  Run PVACMS.  Interrupt to quit

    kerberos options
            --krb-keytab <keytab file>           kerberos keytab file for non-interactive login`
            --krb-realm <realm>                  kerberos realm.  Default ``EPICS.ORG``
            --krb-validator <validator-service>  pvacms kerberos service name.  Default ``pvacms``

**Environment Variables for PVACMS AuthnKRB Verifier**

+----------------------+---------------------+--------------------------+----------------------+--------------------------------------+-----------------------------------------------------------------------+
| Env. *authnkrb*      | Env. *pvacms*       | Params. *authkrb*        | Params. *pvacms*     | Keys and Values                      | Description                                                           |
+======================+=====================+==========================+======================+======================================+=======================================================================+
||                     || KRB5_KTNAME        ||                         || ``--krb-keytab``    || {string location of keytab file}    || This is the keytab file shared with :ref:`pvacms` by the KDC so      |
||                     ||                    ||                         ||                     ||                                     || that it can verify kerberos tickets                                  |
||                     +---------------------+|                         ||                     ||                                     ||                                                                      |
||                     || KRB5_CLIENT_KTNAME ||                         ||                     ||                                     ||                                                                      |
||                     ||                    ||                         ||                     ||                                     ||                                                                      |
+----------------------+---------------------+--------------------------+----------------------+--------------------------------------+-----------------------------------------------------------------------+
|| EPICS_AUTH_KRB_VALIDATOR_SERVICE          || ``--krb-validator``                            || {this is validator service name}    || The name of the service user created in the KDC that the pvacms      |
||                                           ||                                                || e.g. ``pvacms``                     || service will log in as.  ``/cluster@{realm}`` will be added          |
+--------------------------------------------+-------------------------------------------------+--------------------------------------+-----------------------------------------------------------------------+
|| EPICS_AUTH_KRB_REALM                      || ``--krb-realm``                                || e.g. ``EPICS.ORG``                  || Kerberos REALM to authenticate against                               |
+--------------------------------------------+-------------------------------------------------+--------------------------------------+-----------------------------------------------------------------------+

**Setup of Kerberos in Docker Container for testing**

Source: ``/examples/docker/spva_krb``

- users (both unix and kerberos principals)

  - ``pvacms`` - service principal with private keytab file for authentication in ``~/.config/pva/1.5/pvacms.keytab``
  - ``admin`` - principal with password "secret" (includes a configured PVACMS administrator certificate)
  - ``softioc`` - service principal with password "secret"
  - ``client`` - principal with password "secret"

- services

  - KDC
  - kadmin Daemon
  - PVACMS


authldap Configuration and Usage
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``authnldap`` is a TYPE ``2`` authenticator. Identity is established by logging in to the LDAP directory service.

- ``CN``: LDAP username
- ``O``: LDAP domain parts concatenated with "."
- ``OU``: not set
- ``C``: local country code


**usage**

Uses the standard ``EPICS_PVA_TLS_<name>`` environment variables to determine the keychain and password file locations.

.. code-block:: shell

    authnldap - Secure PVAccess LDAP Authenticator

    Generates client, server, or ioc certificates based on the LDAP credentials.

    usage:
      authnldap [options]                        Create certificate in PENDING_APPROVAL state
      authnldap (-h | --help)                    Show this help message and exit
      authnldap (-V | --version)                 Print version and exit

    options:
      (-u | --cert-usage) <usage>                Specify the certificate usage.  client|server|ioc.  Default `client`
      (-n | --name) <name>                       Specify LDAP username for common name in the certificate.
                                                 e.g. name ==> LDAP: uid=name, ou=People ==> Cert: CN=name
                                                 Default <logged-in-username>
      (-o | --organization) <organization>       Specify LDAP org for organization in the certificate.
                                                 e.g. epics.org ==> LDAP: dc=epics, dc=org ==> Cert: O=epics.org
                                                 Default <hostname>
      (-p | --password) <name>                   Specify LDAP password. If not specified will prompt for password
            --ldap-host <hostname>               LDAP server host
            --ldap-port <port>                   LDAP serever port
            --cert-pv-prefix <cert_pv_prefix>    Specifies the pv prefix to use to contact PVACMS.  Default `CERT`
            --add-config-uri                     Add a config uri to the generated certificate
            --force                              Force overwrite if certificate exists
      (-s | --no-status)                         Request that status checking not be required for this certificate
      (-i | --issuer) <issuer_id>                The issuer ID of the PVACMS service to contact.  If not specified (default) broadcast to any that are listening
      (-v | --verbose)                           Verbose mode
      (-d | --debug)                             Debug mode


**Extra options that are available in PVACMS**

.. code-block:: shell

    usage:
      pvacms [ldap options]                      Run PVACMS.  Interrupt to quit

    ldap options
            --ldap-host <host>                   LDAP Host.  Default localhost
            --ldap-port <port>                   LDAP port.  Default 389


**Environment Variables for authnldap and PVACMS AuthnLDAP Verifier**

+--------------------+--------------------------+--------------------------+--------------------------+---------------------------------------+------------------------------------------------------------+
| Env. *authnldap*   | Env. *pvacms*            | Params. *authldap*       | Params. *pvacms*         | Keys and Values                       | Description                                                |
+====================+==========================+==========================+==========================+=======================================+============================================================+
|| EPICS_AUTH_LDAP   ||                         ||                         ||                         || {location of password file}          || file containing password for the given LDAP user account  |
|| _ACCOUNT_PWD_FILE ||                         ||                         ||                         || e.g. ``~/.config/pva/1.5/ldap.pass`` ||                                                           |
+--------------------+--------------------------+--------------------------+--------------------------+---------------------------------------+------------------------------------------------------------+
||                   ||                         || ``-p``                  ||                         || {LDAP account password}              || password for the given LDAP user account                  |
||                   ||                         || ``--password``          ||                         || e.g. ``secret``                      ||                                                           |
+--------------------+--------------------------+--------------------------+--------------------------+---------------------------------------+------------------------------------------------------------+
|| EPICS_AUTH_LDAP_HOST                         ||                                                    || {hostname of LDAP server}            || Trusted hostname of the LDAP server                       |
||                                              || ``--ldap-host``                                    || e.g. ``ldap.stanford.edu``           ||                                                           |
+-----------------------------------------------+-----------------------------------------------------+---------------------------------------+------------------------------------------------------------+
|| EPICS_AUTH_LDAP_PORT                         ||                                                    || <port_number>                        || LDAP server port number. Default is 389                   |
||                                              || ``--ldap-port``                                    || e.g. ``389``                         ||                                                           |
+-----------------------------------------------+-----------------------------------------------------+---------------------------------------+------------------------------------------------------------+

**Setup of LDAP in Docker Container for testing**

Source: ``/examples/docker/spva_ldap``

- users (both unix and LDAP users)

  - ``pvacms`` - service with verifier for LDAP service
  - ``admin`` - principal with password "secret" (includes a configured PVACMS administrator certificate)
  - ``softioc`` - service principal with password "secret"
  - ``client`` - principal with password "secret"

- services

  - LDAP service + example schemas
  - PVACMS
