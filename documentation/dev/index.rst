.. _secure_pvaccess:

|security| Secure PVAccess Documentation
==========================================

.. admonition:: What's new in dev
   :class: important

   You are reading the **dev** variant of the SPVA documentation
   (pvxs ``1.5.1``). The dev variant covers features that are in flight
   for the next release and not yet shipping in the current release
   (``1.4.1``). Switch the sidebar dropdown to **release** to see only
   the currently-shipping behaviour.

   Features in this dev cut that are not in release:

   - **Disk-OCSP cache.** Signed OCSP cert-status responses persisted
     to disk so process restart does not trigger a cold-start
     ``UNKNOWN`` window. Configured via ``EPICS_PVA_STATUS_CACHE_DIR``
     and ``EPICS_PVA_NO_STATUS_CACHE``.
   - **SAN support.** Multi-SAN certificates with ``dNSName`` and
     ``iPAddress`` entries, exposed to the application/authorization
     layer (``ASGIDENTITY.sans``) and matched by the new ``SAG`` ACF
     predicate.
   - **``signalRights`` and ``aclChange``** server-side hooks for
     re-evaluating authorization on connected sessions.
   - **SUSPENDED connection-state class.** Cert-status states
     ``PENDING_RENEWAL`` and ``SCHEDULED_OFFLINE`` map to the
     SUSPENDED class — TLS socket stays open, monitors paused, GET
     continues, PUT/RPC rejected, until status returns to ``GOOD``.
   - **TCP-only context state (``TcpOnly`` / ``TcpReady``).**
     Optimistic-bootstrap and recoverable-non-operational TLS context
     states; plain-TCP connections continue while status monitoring
     waits for the certificate to become ``VALID``.
   - **Active tear-down on BAD and resume on GOOD.** Process-wide
     peer-status store that observes cert-status transitions across
     connection lifetimes and tears down or restarts TLS connections
     to the affected peer.
   - **Scheduled-offline certificates.** ``SCHEDULED_OFFLINE`` status
     and ``CERT:SCHEDULE`` RPC + ``pvxcert --schedule`` for
     time-windowed certificate validity. Useful for shift-based
     access and planned facility downtime.
   - **Renewal cadence.** ``renew_by`` deadline + ``renewal_due`` hint
     + ``PENDING_RENEWAL`` past-due state, with the proactive renewal
     daemon mode (``authn{std,krb,ldap} -D``) that re-authenticates
     under a long ``notAfter`` envelope. Re-issuance is not required
     for normal short-cadence rotation; the existing keypair stays
     in service.
   - **``cms::`` namespace.** The PVACMS C++ symbols have moved from
     ``pvxs::cms::*`` to ``cms::*``. API-reference pages reflect the
     renamed namespace.
   - **pvacms test harness.** ``PVXS_CMS_BUILD_TEST_HARNESS`` build
     flag and supporting end-to-end test scaffolding for verifying
     PVACMS + authenticator interactions.

For protocol implementers — wire-level transport, message encodings,
state machines, normative protocol semantics:

.. toctree::
   :maxdepth: 1
   :caption: Protocol Specification

   protocol-spec/index

For application developers using pvxs (C++), P4P (Python), or phoebus
(Java) PVA APIs to build libraries and executables, write IOCs,
servers, clients, authenticators, and monitor SPVA-aware software:

.. toctree::
   :maxdepth: 1
   :caption: Programmers Reference

   programmers-ref/index

For network operators and IOC administrators deploying SPVA — day-to-day
configuration, quick-start recipes, PVACMS server setup, the
operator-facing CLIs, gateway, interoperability, and migration:

.. toctree::
   :maxdepth: 1
   :caption: SPVA User Manual

   user-manual/index

For readers who need cross-repository API detail — architecture,
build internals, design notes, and generated class/symbol reference
material:

.. toctree::
   :maxdepth: 1
   :caption: EPICS API Reference

   maintainer-docs/index

Shared reference material used across all manuals:

.. toctree::
   :maxdepth: 1
   :caption: Shared Reference

   shared/spvaglossary
   shared/durations
