.. _programmers_tools:

Tools and Development Setup
============================

This page lists every executable that comes with the SPVA repositories
and walks through standing up a working SPVA environment from scratch.
Read this before the cookbook sections — many of them reference these
tools by name without re-explaining what they are.

Tools provided
--------------

**From pvxs** (built in step 2 of :doc:`building`):

.. list-table::
   :widths: 20 80
   :header-rows: 1

   * - Tool
     - Purpose
   * - ``pvxget``
     - One-shot GET of one or more PVs
   * - ``pvxput``
     - One-shot PUT to a PV
   * - ``pvxmonitor``
     - Subscribe and print updates until interrupted
   * - ``pvxinfo``
     - Print the type structure of a PV
   * - ``pvxcall``
     - PVAccess RPC call
   * - ``pvxlist``
     - Discover servers and list PVs
   * - ``pvxvct``
     - Virtual Cable Tester — diagnose UDP search/beacon traffic
   * - ``softIocPVX``
     - Soft IOC using the pvxs server

**From pvxs-cms** (built in step 3 of :doc:`building`):

.. list-table::
   :widths: 20 80
   :header-rows: 1

   * - Tool
     - Purpose
   * - ``pvacms``
     - **Certificate Management Service** — the server process that
       acts as a Certificate Authority for your EPICS network.  It
       issues, approves, revokes, and monitors the status of
       certificates.  Every SPVA deployment needs at least one running
       instance.  See :doc:`/user-manual/pvacms` for full configuration
       reference.
   * - ``pvxcert``
     - **Certificate management client** — query the live status of a
       certificate, approve or deny pending requests, and revoke active
       ones.  See :doc:`/user-manual/cli` for the full option set.
   * - ``authnstd``
     - **Standard authenticator** — requests a certificate from PVACMS
       using self-declared credentials (username and hostname).
       Certificates normally start in ``PENDING_APPROVAL`` and require
       an administrator to run ``pvxcert --approve``.  Used for IOC and
       service accounts in most deployments.
   * - ``authnkrb``
     - **Kerberos authenticator** — requests a certificate using a
       Kerberos ticket obtained via ``kinit``.  PVACMS verifies the
       ticket against the KDC; certificates are issued directly to
       ``VALID`` without administrator approval.
   * - ``authnldap``
     - **LDAP authenticator** — requests a certificate by
       authenticating against an LDAP directory.  Certificates are
       issued directly to ``VALID`` without administrator approval.
   * - ``pvxperf``
     - Benchmark tool measuring GET latency and throughput across
       protocol modes (plain PVA, SPVA, SPVA with cert-status
       monitoring).

**From p4p** (optional, step 4):

.. list-table::
   :widths: 20 80
   :header-rows: 1

   * - Tool
     - Purpose
   * - ``pvagw``
     - PVAccess Gateway — bridges two PVA network segments, with
       optional TLS on either or both sides.

The full command-line reference — usage strings, all flags, examples —
is in :doc:`/user-manual/cli`.

Standing up SPVA for development
----------------------------------

Running SPVA end-to-end requires three things a programmer sets up
themselves: a running PVACMS instance, certificate keychains for each
process, and verification that the certificates are valid.  This is
distinct from the operator quick-start recipes in the User Manual because
you are building and configuring the infrastructure, not just deploying
a pre-packaged system.

Step 1 — Build and start PVACMS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

PVACMS must be running before any certificate can be issued.  Build
pvxs-cms (see :doc:`building`), then start the server.  For
development, the minimal invocation auto-generates a self-signed CA, an
admin keychain, and a SQLite certificate database:

.. code-block:: shell

   pvacms --certs-dont-require-approval \
          --acf pvacms.acf \
          --db  pvacms.db

The ``--certs-dont-require-approval`` flag bypasses the
``PENDING_APPROVAL`` gate so certificates become ``VALID`` immediately —
useful during development to avoid a manual approval round-trip for
every new certificate.  Remove it in production.

``pvacms.acf`` is a standard EPICS Access Security File that controls
who may perform administrative operations (approve, revoke, etc.).  A
minimal development ACF that allows any ``x509``-authenticated client to
write:

.. code-block:: text

   ASG(DEFAULT) {
       RULE(0, READ)
       RULE(1, WRITE) {
           METHOD("x509")
       }
   }

See :doc:`/user-manual/pvacms` for the full set of ``pvacms`` options,
clustering configuration, and production ACF examples.

Step 2 — Obtain certificates for your processes
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Each process that uses TLS needs a PKCS#12 keychain file containing its
certificate, its private key, and the CA chain.  Use the appropriate
``authnxxx`` tool to request a certificate from PVACMS:

.. code-block:: shell

   # Client certificate — written to $EPICS_PVA_TLS_KEYCHAIN
   # (default: ~/.config/pva/1.4/client.p12)
   authnstd -u client -n myapp -o mysite.example.com

   # Server / IOC certificate — written to $EPICS_PVAS_TLS_KEYCHAIN
   # (default: ~/.config/pva/1.4/server.p12)
   authnstd -u ioc -n myioc -o mysite.example.com

Each ``authnxxx`` invocation:

1. Generates or reuses the key pair already in the keychain file.
2. Submits a Certificate Creation Request (CCR) to PVACMS.
3. Receives the signed certificate and writes it, together with the CA
   trust chain, into the keychain file.

The required bag layout and X.509 extensions are specified in
:doc:`/protocol-spec/spva` §4.1 and §4.2.  The ``authnxxx`` tools are
a convenience — certificates can equally be created manually when
PVACMS is not available, using OpenSSL or Java keytool as shown below.
See :doc:`cert-management` for the programmatic C++ flow.

.. _manual_keychain_creation:

Creating keychain files manually (without PVACMS)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Use this procedure when you do not have a PVACMS instance, are
integrating with an existing PKI, or are writing tests that need
certificates without standing up a full SPVA infrastructure.

.. note::

   Certificates created this way will not carry the
   ``SPvaCertStatusURI`` extension, so pvxs will not subscribe to
   a certificate-status PV for them.  As a consequence, neither the
   revocation mechanism nor the renewal mechanism (``renewal_due``
   hint and ``PENDING_RENEWAL`` state) will apply — those features
   depend on an active cert-status subscription.  This is acceptable
   for development and testing.

**Using OpenSSL**

*Step 1 — Create a development CA:*

.. code-block:: shell

   openssl genrsa -out ca.key 4096
   openssl req -new -x509 -days 3650 -key ca.key \
       -subj "/CN=SPVA Dev Root CA/O=dev.example.com" \
       -addext "basicConstraints=critical,CA:TRUE" \
       -addext "keyUsage=critical,cRLSign,keyCertSign" \
       -addext "subjectKeyIdentifier=hash" \
       -out ca.crt

*Step 2 — Issue a client certificate:*

.. code-block:: shell

   openssl genrsa -out client.key 2048
   openssl req -new -key client.key \
       -subj "/CN=myapp/O=dev.example.com" -out client.csr
   openssl x509 -req -days 365 -in client.csr \
       -CA ca.crt -CAkey ca.key -CAcreateserial \
       -extfile <(printf '%s\n' \
           'basicConstraints=CA:FALSE' \
           'keyUsage=critical,digitalSignature' \
           'extendedKeyUsage=clientAuth' \
           'subjectKeyIdentifier=hash' \
           'authorityKeyIdentifier=keyid:always,issuer:always') \
       -out client.crt

*Step 3 — Issue a server certificate:*

.. code-block:: shell

   openssl genrsa -out server.key 2048
   openssl req -new -key server.key \
       -subj "/CN=myserver/O=dev.example.com" -out server.csr
   openssl x509 -req -days 365 -in server.csr \
       -CA ca.crt -CAkey ca.key -CAcreateserial \
       -extfile <(printf '%s\n' \
           'basicConstraints=CA:FALSE' \
           'keyUsage=critical,digitalSignature,keyEncipherment' \
           'extendedKeyUsage=serverAuth' \
           'subjectKeyIdentifier=hash' \
           'authorityKeyIdentifier=keyid:always,issuer:always') \
       -out server.crt

*Step 4 — Issue an IOC certificate (client + server):*

An IOC acts as both a TLS server (serving PVs) and a TLS client
(connecting to PVACMS for cert-status).  It requires both
``clientAuth`` and ``serverAuth`` in Extended Key Usage:

.. code-block:: shell

   openssl genrsa -out ioc.key 2048
   openssl req -new -key ioc.key \
       -subj "/CN=myioc/O=dev.example.com" -out ioc.csr
   openssl x509 -req -days 365 -in ioc.csr \
       -CA ca.crt -CAkey ca.key -CAcreateserial \
       -extfile <(printf '%s\n' \
           'basicConstraints=CA:FALSE' \
           'keyUsage=critical,digitalSignature,keyEncipherment' \
           'extendedKeyUsage=clientAuth,serverAuth' \
           'subjectKeyIdentifier=hash' \
           'authorityKeyIdentifier=keyid:always,issuer:always') \
       -out ioc.crt

*Step 5 — Assemble into PKCS#12:*

.. code-block:: shell

   # Identity keychain (private key + certificate + CA chain)
   openssl pkcs12 -export \
       -name "myapp" \
       -inkey client.key -in client.crt -certfile ca.crt \
       -passout pass:mypassword \
       -out client.p12

   # Trust-anchor-only (no private key — for clients needing only the CA)
   openssl pkcs12 -export -nokeys \
       -in ca.crt -passout pass: -out ca-trust.p12

*Step 6 — Verify:*

.. code-block:: shell

   openssl pkcs12 -in client.p12 -nokeys -passin pass:mypassword \
       2>/dev/null | openssl x509 -noout -text | grep -A4 "Key Usage"

   # Or use pvxcert to inspect the file contents (-X dumps the full certificate).
   # Note: PVACMS will report the certificate serial number as unknown because
   # this certificate was created manually and was never registered with PVACMS.
   pvxcert -X -f client.p12 -p

----

**Using Java keytool**

Java keytool can create PKCS#12 keystores natively (``-storetype PKCS12``).
This is the natural choice when the certificates will be consumed by
Phoebus or other Java-based EPICS clients.

*Step 1 — Create a CA key pair:*

.. code-block:: shell

   keytool -genkeypair \
     -alias ca \
     -keyalg RSA -keysize 4096 \
     -dname "CN=SPVA Dev Root CA, O=dev.example.com" \
     -validity 3650 \
     -ext "bc:critical=ca:true" \
     -ext "ku:critical=keyCertSign,cRLSign" \
     -storetype PKCS12 \
     -keystore ca.p12 \
     -storepass capassword \
     -keypass capassword

*Step 2 — Export the CA certificate:*

.. code-block:: shell

   keytool -exportcert \
     -alias ca \
     -keystore ca.p12 \
     -storepass capassword \
     -rfc \
     -file ca.crt

*Step 3 — Generate entity key pair and CSR:*

.. code-block:: shell

   # Client keystore
   keytool -genkeypair \
     -alias client \
     -keyalg RSA -keysize 2048 \
     -dname "CN=myapp, O=dev.example.com" \
     -validity 365 \
     -storetype PKCS12 \
     -keystore client.p12 \
     -storepass clientpass \
     -keypass clientpass

   keytool -certreq \
     -alias client \
     -keystore client.p12 \
     -storepass clientpass \
     -keypass clientpass \
     -file client.csr

*Step 4 — CA signs the CSR with the correct extensions:*

For a client certificate (``clientAuth`` only):

.. code-block:: shell

   keytool -gencert \
     -alias ca \
     -keystore ca.p12 \
     -storepass capassword \
     -keypass capassword \
     -infile client.csr \
     -outfile client-signed.crt \
     -rfc \
     -validity 365 \
     -ext "bc:critical=ca:false" \
     -ext "ku:critical=digitalSignature" \
     -ext "eku=clientAuth"

For a server certificate (``serverAuth`` only), change ``eku``:

.. code-block:: shell

   -ext "ku:critical=digitalSignature,keyEncipherment" \
   -ext "eku=serverAuth"

For an IOC certificate (both roles):

.. code-block:: shell

   -ext "ku:critical=digitalSignature,keyEncipherment" \
   -ext "eku=clientAuth,serverAuth"

*Step 5 — Import the CA and signed certificate into the keystore:*

.. code-block:: shell

   # Import CA as a trusted certificate
   keytool -importcert \
     -alias ca \
     -keystore client.p12 \
     -storepass clientpass \
     -file ca.crt \
     -noprompt

   # Import the signed certificate (replaces the self-signed stub)
   keytool -importcert \
     -alias client \
     -keystore client.p12 \
     -storepass clientpass \
     -keypass clientpass \
     -file client-signed.crt \
     -noprompt

*Step 6 — Verify:*

.. code-block:: shell

   keytool -list -v -keystore client.p12 -storepass clientpass

.. note::

   keytool does not automatically add Subject Key Identifier or
   Authority Key Identifier extensions via ``-gencert``.  pvxs
   requires both extensions (§4.2 of the SPVA specification).
   If strict compliance is required, use OpenSSL to sign the CSR
   (Step 4 in the OpenSSL procedure above) even when the keystore
   is otherwise managed with keytool.

Step 3 — Verify and manage certificates
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Use ``pvxcert`` to confirm that a certificate is ``VALID`` before
starting your processes:

.. code-block:: shell

   # Check the certificate at $EPICS_PVA_TLS_KEYCHAIN (no arguments)
   pvxcert

   # Check a specific keychain file
   pvxcert -f ~/.config/pva/1.4/server.p12

   # Check by certificate ID (issuer:serial)
   pvxcert 27975e6b:07246297371190731775

   # Approve a pending certificate (if --certs-dont-require-approval is not set)
   pvxcert --approve 27975e6b:07246297371190731775

   # Revoke a certificate
   pvxcert --revoke 27975e6b:07246297371190731775

Once processes have ``VALID`` certificates and PVACMS is reachable,
TLS connections are established automatically by the library.  No
application code changes are needed to enable secure transport.  See
:doc:`applications` for the programming cookbook.
