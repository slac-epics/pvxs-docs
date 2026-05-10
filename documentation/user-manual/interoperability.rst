.. _user_interoperability:

Interoperability and Backwards Compatibility
============================================

SPVA is Secure PVAccess. It secures PVAccess connections with TLS and
X.509 certificates, but it does not change Channel Access and it does not
make plain PVAccess clients magically secure. Mixed deployments are
therefore normal during migration.

What remains compatible
-----------------------

.. list-table::
   :header-rows: 1

   * - Tool or component
     - Compatibility rule
   * - Existing Channel Access clients
     - Continue to use Channel Access. They do not use SPVA certificates.
   * - Existing plain PVAccess clients
     - Can still connect to servers that advertise or allow plain TCP.
   * - SPVA-capable pvxs tools
     - Use TLS when configured with a keychain and when the server offers
       TLS.
   * - IOCs built with pvxs IOC support
     - Can serve securely when configured with a server keychain and SPVA
       options.
   * - Secure PVA Gateway
     - Can bridge networks and enforce access rules using authenticated
       identity.
   * - Phoebus / CS-Studio
     - Java-side SPVA support is planned for this documentation set.
       Until that lands, treat Java client TLS behaviour as deployment-
       specific and verify it against your Phoebus build.

Mixed secure and plain operation
--------------------------------

SPVA deployments commonly run in one of three modes:

* **Plain compatibility period** — servers still answer plain PVAccess so
  old clients keep working while certificates are rolled out.
* **Server-authenticated TLS** — clients verify the server but do not
  present client certificates. This protects against passive observation
  and server spoofing, but it does not give the server a user identity for
  access security.
* **Mutual TLS** — both sides present certificates. This is the normal
  end state for identity-based authorization.

For a server that must support old clients temporarily:

.. code-block:: shell

   export EPICS_PVAS_TLS_OPTIONS="client_cert=optional on_expiration=fallback-to-tcp"

For a server that should require authenticated clients:

.. code-block:: shell

   export EPICS_PVAS_TLS_OPTIONS="client_cert=require on_expiration=standby"

Do not leave fallback enabled by accident. If plain clients can write to a
process variable, access security must explicitly allow that risk.

Gateway deployments
-------------------

The gateway is the preferred compatibility boundary when different
network zones have different trust levels. A common pattern is:

* internal IOCs require SPVA and trust PVACMS;
* the gateway has an IOC certificate and is authorized to reach internal
  process variables;
* external clients connect to the gateway, optionally with their own
  certificates;
* gateway access security rules decide what external identities may read
  or write.

See :doc:`spvaqsgw` for the worked example with internal users,
external clients, certificate approval, and role-based write checks.

Phoebus and CS-Studio
---------------------

Phoebus is the current CS-Studio generation and has its own Java PVAccess
implementation. It does not link against the C++ pvxs library. That means
Java-side SPVA support must match the same wire-level protocol, but it is
implemented independently.

Operationally, check three things before relying on a Phoebus deployment
for SPVA:

1. the Phoebus build includes Java PVAccess TLS support;
2. the Java process can read the expected keychain and trust anchor;
3. certificate-status monitoring semantics match the PVACMS deployment.

The central SPVA protocol semantics are in :doc:`/protocol-spec/spva`.
User-facing Phoebus setup will be documented here when the Java-side SPVA
work lands.

Migration checklist
-------------------

1. Start PVACMS and verify administrator access with ``pvxcert``.
2. Issue certificates for a small client/server pair and test with
   ``pvxinfo`` and ``pvxget``.
3. Enable SPVA on one non-critical IOC or service.
4. Decide whether plain PVAccess fallback is allowed during migration.
5. Move cross-zone access behind the Secure PVA Gateway.
6. Convert access security rules to check authenticated identity where
   writes or administrative operations are involved.
7. Disable fallback once all required clients have a secure path.
