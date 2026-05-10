.. _programmers_performance:

Performance, Monitoring, and Debugging
======================================

SPVA adds work that plain PVAccess does not do: TLS handshakes,
certificate-chain validation, certificate-status subscriptions, optional
status stapling, and disk caching of signed status responses. Application
performance work should separate those costs from ordinary get, put,
monitor, and RPC costs.

What changes under SPVA
-----------------------

The main costs are:

* **connection setup** — TLS setup and certificate validation happen when
  a connection is established;
* **certificate status** — peers must be checked against PVACMS unless
  status checking is explicitly disabled;
* **stapling** — servers may staple cached status to reduce the first
  client-side status lookup;
* **fallback or holding states** — ``UNKNOWN`` and ``SUSPENDED`` status
  classes can delay operations while pvxs waits for a fresh status;
* **disk cache** — signed status responses are persisted under the XDG
  data directory so restart does not always mean a cold status lookup.

These costs mostly affect connection churn. Long-lived monitors and
clients that reuse a
:doc:`pvxs::client::Context </maintainer-docs/api-reference-pvxs-client-context>`
amortize the setup cost.

Benchmarking with pvaperf
-------------------------

Use :ref:`pvxperf` when you need an operator-visible benchmark across
plain Channel Access, plain PVAccess, SPVA, and SPVA with certificate
monitoring. It can run with an in-process source or external IOC
processes, and it records the configuration used for each comparison.

For programmer investigations, benchmark at three levels:

1. the application operation you care about, such as monitor update rate
   or RPC latency;
2. the same operation with a reused client context and warm status cache;
3. connection setup with a fresh client/server cycle, which exposes TLS
   and certificate-status overhead most strongly.

Avoid drawing conclusions from a benchmark that silently changes more
than one variable, such as switching both protocol and server
implementation at the same time.

Tuning rules
------------

Prefer these changes before disabling security features:

* reuse :doc:`pvxs::client::Context </maintainer-docs/api-reference-pvxs-client-context>`
  objects instead of creating one context
  per operation;
* keep monitors long-lived rather than repeatedly connecting and
  disconnecting;
* keep ``EPICS_PVA_STATUS_CACHE_DIR`` on local storage with owner-only
  permissions;
* enable stapling unless you are debugging status behaviour;
* make PVACMS reachable through a stable address list so status lookups do
  not depend on broad network search;
* use runtime reconfiguration for keychain rotation instead of process
  restarts when possible.

Use ``EPICS_PVA_NO_STATUS_CACHE=YES``, ``no_revocation_check``, or
``no_stapling`` only for controlled tests or a documented operational
exception. They change the security/performance tradeoff and can hide the
cost you intended to measure.

Monitoring and logs
-------------------

For application-level health, expose explicit process variables from your
own service and use PVACMS operational process variables for certificate
authority health. PVACMS publishes health, metrics, certificate-status,
validity-schedule, and audit-related endpoints described under
:ref:`pvacms_operational_pvs`.

For protocol and TLS debugging, enable the narrowest useful log category:

.. code-block:: shell

   export PVXS_LOG="pvxs.auth.mon=DEBUG pvxs.stapling=DEBUG"

Useful categories are listed in :ref:`protocol_debugging`. If pvxs was
built with ``PVXS_ENABLE_SSLKEYLOGFILE=YES``, set ``SSLKEYLOGFILE`` to
capture TLS session keys for packet inspection in a controlled lab:

.. code-block:: shell

   export SSLKEYLOGFILE=/tmp/pva-secrets.log

Never leave TLS key logging enabled in production. The file allows packet
captures from the same session to be decrypted.
