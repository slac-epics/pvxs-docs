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

SAG (SAN Access Group)
~~~~~~~~~~~~~~~~~~~~~~~

The ``SAG`` predicate restricts access based on Subject Alternative Name (SAN) entries
from the client's TLS certificate. This is distinct from ``HAG`` (which matches the
client's IP address or hostname at the network level) — ``SAG`` matches the
cryptographically bound identity embedded in the X.509 certificate.

**Defining a SAG**

``SAG`` definitions appear at the top level of the ACF file, alongside ``UAG`` and
``HAG``:

.. code-block:: text

   SAG(trusted_iocs) {
       IP(192.168.10.0/24),
       IP(172.16.0.1),
       IP(2001:db8::1),
       DNS(*.slac.stanford.edu),
       DNS(ioc01.example.com)
   }

Each entry is qualified with a type:

- ``IP(<address>)`` — matches an IP address SAN from the client certificate.
  Supports:

  - Exact IPv4 match: ``IP(192.168.10.5)``
  - IPv4 CIDR subnet: ``IP(192.168.10.0/24)`` (prefix length 0–32)
  - Exact IPv6 match: ``IP(2001:db8::1)`` (IPv6 CIDR is not supported)

- ``DNS(<hostname>)`` — matches a DNS name SAN from the client certificate.
  Supports:

  - Exact match: ``DNS(ioc01.example.com)``
  - Glob wildcard: ``DNS(*.slac.stanford.edu)`` (``*`` and ``?`` are supported)

All entry values are lowercased at parse time for case-insensitive matching.
Matching is type-aware: a client's IP SAN only matches ``IP(...)`` entries,
and a client's DNS SAN only matches ``DNS(...)`` entries.

Clients without SANs (e.g. non-TLS connections) automatically fail the SAG predicate.

**Using SAG in a RULE**

.. code-block:: text

   RULE(1,WRITE) {
       SAG(trusted_iocs)
       METHOD("x509")
       PROTOCOL("TLS")
   }

The above rule applies only to clients whose TLS certificate contains at least one SAN
that matches an entry in the ``trusted_iocs`` SAG. A match on any entry in any listed
SAG satisfies the predicate.

Multiple SAGs may be listed:

.. code-block:: text

   RULE(1,READ) {
       SAG(trusted_iocs, beamline_hosts)
   }

**Full example combining SAG, UAG, METHOD, AUTHORITY, and PROTOCOL**

.. code-block:: text

   AUTHORITY(AUTH_EPICS_ROOT, "EPICS Root Certificate Authority")

   SAG(control_subnet) {
       IP(192.168.0.0/16),
       DNS(*.ctrl.facility.org)
   }

   UAG(operators) {alice, bob}

   ASG(DEFAULT) {
       RULE(0, NONE)

       # Read access for operators on the control subnet using TLS
       RULE(1, READ) {
           UAG(operators)
           SAG(control_subnet)
           PROTOCOL("TLS")
       }

       # Write access requiring x509 auth from the facility CA
       RULE(2, WRITE) {
           UAG(operators)
           METHOD("x509")
           AUTHORITY(AUTH_EPICS_ROOT)
           SAG(control_subnet)
       }
   }

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

*Using SAG (SAN Access Groups) to restrict by certificate SAN*

.. code-block:: text

    SAG(control_subnet) {
        IP(192.168.0.0/16),
        IP(172.16.1.0/24),
        DNS(*.ctrl.facility.org),
        DNS(ioc01.example.com)
    }

    SAG(trusted_iocs) {
        IP(10.0.10.0/24),
        DNS(*.ioc.slac.stanford.edu)
    }

    UAG(operators) {alice, bob}
    UAG(admins)   {aqeel, pierrick}

    AUTHORITY(AUTH_FACILITY, "SLAC Certificate Authority")

    ASG(DEFAULT) {
        RULE(0, NONE)

        # Read access for operators on the control subnet, x509-authenticated over TLS
        RULE(1, READ) {
            UAG(operators, admins)
            SAG(control_subnet)
            METHOD("x509")
            PROTOCOL("tls")
        }

        # Write access only for IOCs on the trusted IOC subnet, from the facility CA
        RULE(2, WRITE) {
            SAG(trusted_iocs)
            METHOD("x509")
            AUTHORITY(AUTH_FACILITY)
        }

        # Admin RPC from any authenticated operator on the control subnet
        RULE(3, RPC) {
            UAG(admins)
            SAG(control_subnet)
            METHOD("x509")
            AUTHORITY(AUTH_FACILITY)
            PROTOCOL("tls")
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

``Credentials`` Structure (pvxsIoc API)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The ``pvxs::ioc::Credentials`` class provides the authenticated peer identity to
IOC-side access security. It is constructed from the ``server::ClientCredentials``
delivered by pvxs on each connection:

.. code-block:: c++

    class Credentials {
     public:
        std::vector<std::string> cred; // credentials list: e.g. {"ca/username"}, {"x509/CN=greg"}
        std::string method;            // "anonymous", "ca", or "x509"
        std::string authority;         // CA common name (x509 mode); empty otherwise
        std::string host;              // peer network address
        std::string issuer_id;         // 8-hex-digit issuer SKID prefix (x509 mode)
        std::string serial;            // zero-padded certificate serial number (x509 mode)
        bool isTLS = false;            // true if the connection is over TLS (Mutual or Server-Only)
    };

In mTLS (Mutual) mode, ``method`` is ``"x509"``, ``authority`` is the CA CN,
``issuer_id`` and ``serial`` identify the specific certificate, and ``isTLS`` is
``true``. In server-only TLS, ``isTLS`` is ``true`` but ``method`` is ``"ca"`` or
``"anonymous"`` and the certificate fields are empty. In legacy TCP mode, ``isTLS``
is ``false``.


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
It carries the full authenticated peer identity including Subject Alternative Names:

.. code-block:: c

   /** Client SAN descriptor — caller retains ownership for session lifetime */
   typedef struct {
       enum asSanType type;   /* asSanIP or asSanDNS */
       const char    *value;  /* e.g. "192.168.1.10" or "ioc01.example.com" */
   } ASSAN;

   typedef struct asIdentity {
       const char      *user;     /* CN from certificate (or username for legacy) */
       char            *host;     /* O from certificate (hostname / realm / IP) */
       const char      *method;   /* "anonymous", "ca", or "x509" */
       const char      *authority;/* CA common name (x509 mode); empty otherwise */
       enum AsProtocol  protocol; /* AS_PROTOCOL_TCP or AS_PROTOCOL_TLS */
       const ASSAN     *sans;     /* array of SAN entries from the client certificate */
       int              nsans;    /* number of entries in sans[] */
   } ASGIDENTITY;

   enum AsProtocol {
       AS_PROTOCOL_NOT_SET = -1,
       AS_PROTOCOL_TCP     =  0,  /* unencrypted plain-TCP connection */
       AS_PROTOCOL_TLS     =  1   /* TLS (server-only or mTLS) */
   };

The ``sans`` / ``nsans`` fields expose the client certificate's Subject Alternative
Names to the access security layer, enabling ``SAG`` rules (see :ref:`spvaauthorization`)
to be evaluated against the IP address and DNS name SANs in the certificate.

Protocol Enumeration
~~~~~~~~~~~~~~~~~~~~~

.. code-block:: c

   enum AsProtocol {
       AS_PROTOCOL_TCP = 0,     // Unencrypted connection
       AS_PROTOCOL_TLS = 1      // Encrypted connection
   };
