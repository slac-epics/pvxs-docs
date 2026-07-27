.. _authorization:
.. _spvaauthorization:

|security| Authorization
=========================

:ref:`Authentication and Authorization<glossary_auth_vs_authz>` with Secure PVAccess.

- **Authentication** (AuthN) determines and verifies the identity of a client or server.
- **Authorization** (AuthZ) defines and enforces access rights to PV resources.

Secure PVAccess extends EPICS access security with access control based on authentication method,
certifying authority, and transport protocol.

Reading the peer identity in server code
-----------------------------------------

Each SPVA implementation exposes the authenticated peer identity through its
own server-side API.  The information available is the same in all three
languages: authentication method (``anonymous``, ``ca``, or ``x509``),
the peer's identity string (username or certificate CN), the remote address,
and whether the connection is over TLS.

**C++**

pvxs delivers the identity through
:doc:`pvxs::server::ClientCredentials </maintainer-docs/api-reference-pvxs-server-clientcredentials>`,
available from any operation callback:

.. code-block:: c++

   #include <pvxs/server.h>

   serv.addSource("mysrc",
       pvxs::server::StaticSource::build()
           .add("MY:PV", pvxs::server::SharedPV::buildMailbox())
           .onOp([](std::unique_ptr<pvxs::server::ConnectOp> &&op) {
               const auto &creds = op->credentials();

               if (creds.method == "x509") {
                   // mTLS: creds.account is the peer's certificate CN
                   // creds.isTLS is true
                   // creds.roles() contains group memberships
                   if (creds.account == "alice") { /* authorised */ }
               } else if (creds.isTLS) {
                   // Server-only TLS: encrypted but client has no cert
               } else {
                   // Plain TCP: legacy PVA
               }

               op->connect(pvxs::nt::NTScalar{pvxs::TypeCode::Float64}.create());
           }));

**Python (P4P)**

P4P delivers the identity through the ``op`` argument passed to put and
RPC handler functions:

.. code-block:: python

   from p4p.nt import NTScalar
   from p4p.server import Server
   from p4p.server.thread import SharedPV

   pv = SharedPV(nt=NTScalar('d'), initial=0.0)

   @pv.put
   def handle(pv, op):
       account = op.account()   # str: peer identity (cert CN or username)
       peer    = op.peer()      # str: "ip:port"
       roles   = op.roles()     # set of str: group memberships

       if 'engineers' not in roles:
           op.done(error='access denied')
           return
       pv.post(op.value())
       op.done()

   Server.forever(providers=[{'MY:PV': pv}])

In mTLS mode, ``op.account()`` returns the Common Name from the client's
X.509 certificate.  In ``ca`` mode it returns ``user@host``.  In
``anonymous`` mode it returns an empty string.  There is no direct
``isTLS`` flag at the Python level; instead, check whether
``op.account()`` contains an ``@`` separator — its absence in an
``x509``-authenticated request indicates a cert CN without a realm.
Alternatively, check ``op.roles()`` against a group known to require TLS.

**Java (Phoebus core-pva)**

Phoebus delivers the identity through ``ClientAuthentication``, passed to
the write event handler and available from ``PVAServer.getClientInfos()``:

.. code-block:: java

   import org.epics.pva.server.*;

   try (PVAServer server = new PVAServer()) {
       // Install a custom authorization handler:
       server.configureAuthorization(new ServerAuthorization() {
           @Override
           public boolean hasWriteAccess(String pv_name,
                                         ClientAuthentication auth) {
               // auth.getType()  — PVAAuth.anonymous | ca | x509
               // auth.getUser()  — cert CN (x509) or username (ca)
               // auth.getHost()  — client InetAddress

               if (auth.getType() == PVAAuth.x509) {
                   return auth.getUser().equals("alice");
               }
               // Deny anonymous and ca (non-TLS) writes:
               return false;
           }
       });

       PVAStructure data = new PVAStructure("demo", "demo_t",
                                            new PVADouble("value", 0.0));
       server.createPV("MY:PV", data, (tcp, pv, changes, written) -> {
           // tcp.getAuthentication() gives the same ClientAuthentication
           pv.update(written);
       });

       Thread.sleep(Long.MAX_VALUE);
   }

To inspect which clients are currently connected and their identity:

.. code-block:: java

   for (PVAServer.ClientInfo info : server.getClientInfos()) {
       System.out.printf("  %s  auth=%s%n",
           info.address(), info.authentication());
   }

.. _site_authentication_methods:

Authentication Method
-----------------------

anonymous Method
^^^^^^^^^^^^^^^^^^

No credentials are supplied.

ca Method
^^^^^^^^^^

Unauthenticated credentials are supplied in the ``AUTHZ`` message.

x509 Method
^^^^^^^^^^^^

The ``x509`` method authenticates clients using an X.509 certificate. Clients may obtain
certificates from site authenticators (Kerberos, LDAP, or a standard username/organization
authenticator). The x509 method integrates with Secure PVAccess via a PKCS#12 keychain file.


Certifying Authority
--------------------

The Certifying Authority (Certificate Authority or Trust Anchor) attests to the identity of
EPICS agents. A client and server must share a common trust anchor. Certificates issued by
the PVACMS service are signed by a common CA, so clients and servers agree implicitly. When
providing your own certificates, the trust anchor certificate must be distributed to all
communicating clients and servers.


Protocol
--------

- ``TLS`` - Transport Layer Security (Secure PVAccess)
- ``TCP`` - Transmission Control Protocol (legacy)

The TLS protocol is negotiated during the TLS handshake using the X.509 certificate provided
by the server and, optionally, by the client.


Access Control
--------------

Secure PVAccess integrates with EPICS Security's authorization system via extensions to the
Access Control File (ACF) syntax. New rule predicates (``METHOD``, ``AUTHORITY``, ``PROTOCOL``)
and a new ``RPC`` permission type enable fine-grained control while preserving backward
compatibility with legacy clients.

.. _acf_implementation_coverage:

ACF implementation coverage by language
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The three SPVA implementations parse and evaluate ACF files independently.
Their support for the new ``METHOD``, ``AUTHORITY``, and ``PROTOCOL``
predicates differs:

.. list-table::
   :widths: 20 18 62
   :header-rows: 1

   * - Implementation
     - New ACF predicates
     - Notes
   * - **C++ pvxs / pvxsIoc**
     - Supported
     - Implemented in epics-base ``asLib`` when built against a base that
       defines ``EPICS_ASLIB_HAS_IDENTITY``.  Requires the SPVA fork:
       ``slac-epics/epics-base-tls`` branch ``7.0-secure-pvaccess``.
       The new predicates evaluate to ``false`` (deny) on older base builds
       that lack ``EPICS_ASLIB_HAS_IDENTITY``.
   * - **Python P4P gateway**
     - ``feature/acf-grammar-7.0.10`` branch only
     - P4P has its **own** ACF parser (``p4p.asLib``, implemented in
       Python with PLY).  The ``master`` and ``tls`` branches of
       ``slac-epics/p4p-tls`` support only the classic keywords
       (``UAG``, ``HAG``, ``ASG``, ``RULE``, ``CALC``, ``INP``).
       ``METHOD``, ``AUTHORITY``, and ``PROTOCOL`` are **not** parsed
       or evaluated on those branches — the predicates are silently
       treated as unknown and cause the enclosing ``RULE`` to be
       disabled (fail-secure).

       To use the new predicates in a P4P gateway ACF, check out
       ``feature/acf-grammar-7.0.10`` from ``slac-epics/p4p-tls``
       (see :doc:`building`).  That branch adds ``METHOD``,
       ``AUTHORITY``, and ``PROTOCOL`` tokens to the lexer and evaluates
       them in ``Engine.create()``, receiving the method, authority CN,
       and protocol from the pvxs client credentials on every channel
       open.
   * - **Java Phoebus core-pva**
     - Not applicable
     - Phoebus uses its own ``ServerAuthorization`` callback API rather
       than ACF files.  ACF-based access control is not part of the Java
       implementation.  Use ``hasWriteAccess(pv_name, auth)`` and inspect
       ``ClientAuthentication.getType()`` / ``getUser()`` to enforce
       equivalent policies.

.. warning::

   If you write an ACF with ``METHOD``, ``AUTHORITY``, or ``PROTOCOL``
   predicates and use it with a P4P gateway built from ``master`` or
   ``tls``, those predicates will not take effect.  The ``RULE`` that
   contains an unrecognised predicate is disabled entirely (the parser
   treats unknown predicates as fail-secure).  No parse error or warning
   is emitted — the rules are silently skipped.  Always verify ACF
   behaviour with the implementation you are actually deploying.

EPICS Security Access Control File (ACF) Extensions
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

METHOD
~~~~~~~

The ``METHOD`` predicate restricts access based on authentication method:

- ``x509``: Certificate-based authentication
- ``ca``: Legacy PVAccess AUTHZ with user-specified account
- ``anonymous``: Access without a specified name

Values may be quoted or unquoted strings.

Example:

.. code-block:: text

   RULE(1,READ) {
       METHOD("x509")
   }

The above rule matches any client that presents an x509 certificate to assert its identity.

AUTHORITY
~~~~~~~~~

``AUTHORITY`` serves two roles in ACF files.

**1. Top-level declaration**

Declares the hierarchy of Certificate Authorities, tracing back to the root CA. Intermediate
nodes need not be named. The ``CN`` field of each CA certificate's subject provides the name.

Example:

.. code-block:: text

    AUTHORITY(AUTH_EPICS_ROOT, "EPICS Root Certificate Authority") {
        AUTHORITY("SNS Intermediate CA") {
            AUTHORITY(AUTH_SNS_CTRL, "SNS Control Systems CA")
            AUTHORITY(AUTH_BEAMLINE, "SNS Beamline Operations CA")
       }
    }

    AUTHORITY(AUTH_EPICS_IT_ROOT, "EPICS IT Root Certificate Authority") {
    	AUTHORITY(AUTH_EPICS_USERS, "EPICS Users Certificate Authority")
    }

**2. Rule predicate**

References a top-level ``AUTHORITY`` declaration to constrain a rule. Applicable only for
x509 authentication. Multiple authorities may be listed; any one match is sufficient.

Example:

.. code-block:: text

   RULE(1,READ) {
       AUTHORITY(AUTH_EPICS_USERS, AUTH_EPICS_ROOT)
   }

The above rule matches any client presenting an x509 certificate signed by the EPICS Root
Certificate Authority or the EPICS Users Certificate Authority.

.. code-block:: text

   RULE(1,WRITE) {
       AUTHORITY(AUTH_SNS_CTRL)
   }

The above rule matches any client presenting an x509 certificate signed by the SNS Control
Systems CA.

PROTOCOL
~~~~~~~~

The ``PROTOCOL`` predicate restricts access based on transport:

- ``TCP``: Unencrypted connection (default)
- ``TLS``: Encrypted connection

Values may be quoted or unquoted strings, upper or lower case.

Example:

.. code-block:: text

   RULE(1,READ) {
       PROTOCOL("TLS")
   }

The above rule matches any client connecting over TLS. This is always true when a client
presents an x509 certificate, but also applies to server-only authenticated connections where
the METHOD may be ``ca`` or ``anonymous``.

Example:

.. code-block:: text

   RULE(1,NONE) {
       PROTOCOL("TCP")
   }

The above rule explicitly denies any client connecting over an unencrypted TCP connection.

RPC Permission
~~~~~~~~~~~~~~~

The ``RPC`` permission type supplements ``NONE``, ``READ`` (GET), and ``WRITE`` (PUT) to
control access to PVAccess RPC messages.

Note: ACF syntax for ``RPC`` is implemented, but enforcement of RPC access control is not
yet available.

Example:

.. code-block:: text

   RULE(1,RPC) {
       UAG(admins)
   }

Full ACF Examples
~~~~~~~~~~~~~~~~~

*Authorization based on PROTOCOL, METHOD, and AUTHORITY*

.. code-block:: text

    UAG(operators) {greg, karen, ralph}
    UAG(engineers) {kay, george, michael}
    UAG(admins) {aqeel, earnesto, pierrick}

    AUTHORITY(AUTH_EPICS_ROOT, "EPICS Root Certificate Authority") {
        AUTHORITY("Intermediate CA") {
            AUTHORITY(AUTH_LBNL_CTRL, "LBNL Certificate Authority")
        }
        AUTHORITY(AUTH_SLAC_ROOT, "SLAC Certificate Authority") {
            AUTHORITY(AUTH_EPICS_USERS, "EPICS Users Certificate Authority")
        }
    }


    ASG(DEFAULT) {
    # Default - No access
       RULE(0,NONE)

    # Read-only access for operators, requiring TLS
       RULE(1,READ) {
           UAG(operators,engineers,admins)
           PROTOCOL(tls)
       }

    # Write access for engineers from SLAC or LBNL using x509 auth
       RULE(2,WRITE) {
           UAG(engineers,admins)
           METHOD(x509)
           AUTHORITY(AUTH_LBNL_CTRL, AUTH_SLAC_ROOT)
       }

    # RPC access for admins using specific Cert Auth and TLS
       RULE(3,RPC) {
           UAG(admins)
           METHOD("x509")
           AUTHORITY(AUTH_EPICS_ROOT)
       }
    }

*Legacy compatible with Enhanced Security*

.. code-block:: text

    AUTHORITY(AUTH_EPICS_ROOT, "EPICS Root Certificate Authority")

    # Support both legacy and SPVA clients
    ASG(backward_compatible) {
       RULE(0,NONE)
       # Legacy access - read only
       RULE(1,READ) {
           METHOD("ca", "anonymous")
           PROTOCOL(tcp)
       }
       # Enhanced access - write with secure authentication
       RULE(2,WRITE) {
           UAG(operators)
           METHOD("x509")
           AUTHORITY(AUTH_EPICS_ROOT)
           PROTOCOL("tls")
       }
    }


New APIs
--------

Secure PVAccess introduces APIs for managing security with authenticated identities.

.. _peer_info:

Legacy ``PeerInfo`` Structure
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. code-block:: c++

    struct PeerInfo {
        std::string peer;      // network address
        std::string transport; // protocol (e.g., "pva")
        std::string authority; // auth mechanism
        std::string realm;     // authority scope
        std::string account;   // user name
    }


.. _peer_credentials:

``ClientCredentials`` Structure
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The :doc:`pvxs::server::ClientCredentials </maintainer-docs/api-reference-pvxs-server-clientcredentials>`
delivered by pvxs on each connection provides the authenticated peer
identity used to build an asLib access-security check.  Its
authentication-relevant fields are:

.. code-block:: c++

    struct PeerCredentials {
        std::string peer;       // peer network address ("host:port")
        std::string method;     // "anonymous", "ca", or "x509"
        std::string authority;  // CA common name (x509 mode); empty otherwise
        std::string account;    // remote user account name
        bool isTLS = false;     // true if the connection is over TLS (Mutual or Server-Only)
        std::set<std::string> roles() const; // locally-resolved groups for account
    };

In mTLS (Mutual) mode, ``method`` is ``"x509"``, ``authority`` is the CA CN,
and ``isTLS`` is ``true``. In server-only TLS, ``isTLS`` is ``true`` but
``method`` is ``"ca"`` or ``"anonymous"`` and ``authority`` is empty. In legacy
TCP mode, ``isTLS`` is ``false``.


Enhanced Client Management
^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. code-block:: c

   long epicsStdCall asAddClientIdentity(
        ASCLIENTPVT *pasClientPvt, ASMEMBERPVT asMemberPvt, int asl,
        ASIDENTITY identity);

   long epicsStdCall asChangeClientIdentity(
        ASCLIENTPVT asClientPvt, int asl,
        ASIDENTITY identity);

Enhanced Auditing
^^^^^^^^^^^^^^^^^^

.. code-block:: c

   void * epicsStdCall asTrapWriteBeforeWithIdentityData(
        ASIDENTITY identity,
        dbChannel *addr, int dbrType, int no_elements, void *data);

.. _identity_structure:

Identity Structure for APIs
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The ``ASIDENTITY`` / ``ASGIDENTITY`` structure is passed to
``asAddClientIdentity()`` and ``asChangeClientIdentity()`` for each connection.
It carries the authenticated peer identity:

.. code-block:: c

   typedef struct asIdentity {
       const char      *user;     /* CN from certificate (or username for legacy) */
       char            *host;     /* O from certificate (hostname / realm / IP) */
       const char      *method;   /* "anonymous", "ca", or "x509" */
       const char      *authority;/* CA common name (x509 mode); empty otherwise */
       enum AsProtocol  protocol; /* AS_PROTOCOL_TCP or AS_PROTOCOL_TLS */
   } ASGIDENTITY;

   enum AsProtocol {
       AS_PROTOCOL_NOT_SET = -1,
       AS_PROTOCOL_TCP     =  0,  /* unencrypted plain-TCP connection */
       AS_PROTOCOL_TLS     =  1   /* TLS (server-only or mTLS) */
   };

Protocol Enumeration
~~~~~~~~~~~~~~~~~~~~~

.. code-block:: c

   enum AsProtocol {
       AS_PROTOCOL_TCP = 0,     // Unencrypted connection
       AS_PROTOCOL_TLS = 1      // Encrypted connection
   };
