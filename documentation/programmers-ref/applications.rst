.. _programmers_applications:

Writing IOCs, Servers, and Clients
==================================

SPVA does not require a different application API for ordinary get, put,
monitor, and RPC operations. You write a pvxs client or server in the
normal way, then enable secure transport by providing keychains and TLS
configuration through the process environment or the pvxs configuration
objects described in :doc:`configuration`.

Client applications
-------------------

The usual client entry point is
:doc:`pvxs::client::Context </maintainer-docs/api-reference-pvxs-client-context>`.
Start with ``Context::fromEnv()`` so address lists, TLS keychains, certificate
status settings, and timeouts follow the same rules as the command-line
tools:

.. code-block:: c++

   #include <iostream>
   #include <pvxs/client.h>
   #include <pvxs/log.h>

   int main() {
       pvxs::logger_config_env();

       auto ctxt = pvxs::client::Context::fromEnv();
       auto value = ctxt.get("test:spec")
           .exec()
           ->wait(5.0);

       std::cout << value << "\n";
       return 0;
   }

For secure operation the process needs a client keychain or trust-anchor
keychain:

.. code-block:: shell

   export EPICS_PVA_TLS_KEYCHAIN=$HOME/.config/pva/1.5/client.p12
   export EPICS_PVA_ADDR_LIST="pvacms-host ioc-host"
   export EPICS_PVA_AUTO_ADDR_LIST=NO

If certificate status checking is enabled, pvxs creates the internal
status-monitoring subscriptions needed to validate the local and peer
certificates. Your application code continues to use the same client
operation builders.

Server applications
-------------------

The usual server entry point is
:doc:`pvxs::server::Server </maintainer-docs/api-reference-pvxs-server-server>`.
Use ``Server::fromEnv()`` so the same process can run as plain PVAccess in a
development shell and as Secure PVAccess when a server keychain is
present:

.. code-block:: c++

   #include <pvxs/nt.h>
   #include <pvxs/server.h>
   #include <pvxs/sharedpv.h>
   #include <pvxs/log.h>

   int main() {
       pvxs::logger_config_env();

       auto initial = pvxs::nt::NTScalar{pvxs::TypeCode::Float64}.create();
       initial["value"] = 42.0;

       auto pv = pvxs::server::SharedPV::buildMailbox();
       pv.open(initial);

       pvxs::server::Server::fromEnv()
           .addPV("my:pv:name", pv)
           .run();
       return 0;
   }

For secure operation the process needs a server keychain:

.. code-block:: shell

   export EPICS_PVAS_TLS_KEYCHAIN=$HOME/.config/pva/1.5/server.p12
   export EPICS_PVAS_TLS_OPTIONS="client_cert=require"

Set ``client_cert=optional`` only when the server intentionally supports
server-authenticated TLS or fallback clients. A mutually-authenticated
deployment should require client certificates.

IOC applications
----------------

An IOC uses the same SPVA runtime configuration as a standalone server,
but the process is linked with ``pvxsIoc`` and loads ``pvxsIoc.dbd``.
From a programmer's point of view, the important distinction is where the
server is created: IOC shell startup loads records and the pvxs IOC
support publishes them, while standalone servers add
:doc:`pvxs::server::SharedPV </maintainer-docs/api-reference-pvxs-server-sharedpv>` or
custom :doc:`pvxs::server::Source </maintainer-docs/api-reference-pvxs-server-source>`
objects directly in C++.

Typical startup environment for a secure IOC:

.. code-block:: shell

   export EPICS_PVAS_TLS_KEYCHAIN=/ioc/private/server.p12
   export EPICS_PVAS_TLS_OPTIONS="client_cert=require on_expiration=standby"
   export EPICS_PVA_ADDR_LIST="pvacms-host"
   export EPICS_PVA_AUTO_ADDR_LIST=NO
   export XDG_DATA_HOME=/var/lib/ioc
   export XDG_CONFIG_HOME=/etc/ioc

Use ``on_expiration=standby`` when an IOC must stop serving securely if
its certificate cannot be refreshed. Use ``fallback-to-tcp`` only for a
planned compatibility period where unauthenticated PVAccess is still
acceptable.

RPC and management PVs
----------------------

pvxs servers can expose RPC-style process variables with the
:doc:`pvxs::server::SharedPV </maintainer-docs/api-reference-pvxs-server-sharedpv>`
API, including ``onRPC()``. PVACMS uses the same PVAccess operation
family for
certificate creation, approval, revocation, health, metrics, and validity
schedule management. Application services that need management endpoints
should follow this model:

* publish normal data through ``SharedPV`` or a custom ``Source``;
* publish administrative actions as RPC process variables;
* protect those actions with EPICS access security rules that check the
  authenticated identity described in :doc:`spva-authorization`.

Runtime reconfiguration
-----------------------

Long-running clients and servers should prefer runtime reconfiguration
over process restarts when the keychain file changes. The
:doc:`pvxs::client::Context </maintainer-docs/api-reference-pvxs-client-context>` and
:doc:`pvxs::server::Server </maintainer-docs/api-reference-pvxs-server-server>`
APIs add ``reconfigure()`` for this purpose. See :doc:`expert-api` for
the exact API and constraints.

Monitoring certificate status
-----------------------------

Most applications should let pvxs manage certificate status internally.
The connection layer subscribes to status process variables, caches signed
status responses on disk, and reacts to ``VALID``, ``UNKNOWN``,
``SUSPENDED``, and ``BAD`` status classes as described in
:doc:`spva-tls`.

Applications that need operator visibility should expose their own health
or metrics process variables rather than scraping pvxs internals. PVACMS
already publishes health, metrics, certificate-status, and audit-oriented
process variables; see :ref:`pvacms_operational_pvs`.
