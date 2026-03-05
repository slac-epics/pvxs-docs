.. _authorization:

|security| Authorization
=========================

:ref:`Authentication and Authorization<glossary_auth_vs_authz>` with Secure PVAccess.

- **Authentication** (AuthN) determines and verifies the identity of a client or server.
- **Authorization** (AuthZ) defines and enforces access rights to PV resources.

Secure PVAccess extends :ref:`epics_security` with access control based on authentication method,
certifying authority, and transport protocol.

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

New ``PeerCredentials`` Structure
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. code-block:: c++

    struct PeerCredentials {
        std::string peer;      // network address
        std::string iface;     // network interface
        std::string method;    // "anonymous", "ca", or "x509"
        std::string authority; // Certificate Authority common name for x509 if mode is `Mutual` or blank
        std::string account;   // User account if mode is `Mutual` or blank
        bool isTLS;            // Secure transport status.  True is mode is `Mutual` or `Server-Only`
    };


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

This unified structure replaces separate user/host parameters:

.. code-block:: c

   typedef struct asIdentity {
       const char *user;         // User identifier (CN from certificate)
       char *host;               // Host identifier (O from certificate)
       const char *method;       // Authentication method ("ca", "x509", "anonymous")
       const char *authority;    // Certificate authority
       enum AsProtocol protocol; // Connection protocol (TCP/TLS)
   } ASIDENTITY;

Protocol Enumeration
~~~~~~~~~~~~~~~~~~~~~

.. code-block:: c

   enum AsProtocol {
       AS_PROTOCOL_TCP = 0,     // Unencrypted connection
       AS_PROTOCOL_TLS = 1      // Encrypted connection
   };
