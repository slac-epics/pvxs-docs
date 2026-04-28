.. _pvxs_overview:

Shape of pvxs as a C++ Library
==============================

This page is part of the maintainer manual. Its purpose is to give a
contributor reading this site for the first time an orientation to the
code shape of pvxs and pvxs-cms — what the public client API looks like,
what the server-side counterpart looks like, and one example of a
PVACMS-side type that the two halves both depend on. It is intentionally
brief; full per-subsystem coverage is the follow-up change
``pvxs-docs-maintainer-content``.

Every C++ symbol on this page is pulled live from the corresponding
sibling repo's source comments (Doxygen `@brief` / `@param` / `@return`
blocks) via the :doc:`Breathe </maintainer-docs/index>` directive, so the
prose you are reading and the API box below it stay correlated as the
C++ evolves.

Public client API surface
-------------------------

The entry point most pvxs users start from is
``pvxs::client::Context``: a long-lived client handle that owns the
connection state to one or more PVA servers, dispatches asynchronous
operations (get / put / monitor / RPC), and tracks per-server certificate
status when TLS is in play. A typical IOC keeps exactly one ``Context``
for its lifetime; spinning up additional contexts is rare and reserved
for tests or unusual deployments where independent connection pools
matter.

.. doxygenclass:: pvxs::client::Context
   :no-link:

The ``reconfigure()`` method is the operational hook for runtime
keychain rotation: when an external process (PVACMS-driven renewal,
admin recovery, scheduled rotation) changes the keychain file backing
the context, calling ``reconfigure(newConfig)`` drops in-progress TLS
connections and re-establishes them under the new identity without
tearing down the surrounding pvxs::Context object. The on-the-wire
consequences of that — what the peer sees, when status checks resume —
are described in :doc:`/protocol-spec/cert-protocol`.

Public server API surface
-------------------------

Mirrored on the server side is ``pvxs::server::Server``: the long-lived
server handle holding the PVA listener, the source registry (the things
that answer GETs / serve monitors / accept PUTs), and the same TLS state
machinery the client has — including the same ``reconfigure()`` for
keychain rotation.

.. doxygenclass:: pvxs::server::Server
   :no-link:

PVACMS-side types
-----------------

The certificate-management side of the stack lives in the sibling
``pvxs-cms`` repo, in the ``cms::cert::`` namespace. Most types there
are PVACMS-internal, but a few (notably the date types used in the
on-the-wire status PVStructure and the certificate creation request)
are referenced from headers that pvxs itself includes — which is why
``pvxs-docs`` extracts pvxs-cms's API surface alongside pvxs's.

The smallest example is ``cms::cert::CertDate``: a thin convertibility
wrapper around ``time_t`` and ``ASN1_TIME*`` that PVACMS uses everywhere
a certificate timestamp shows up (issuance, expiration, renewal-due
hint, status-effective-from). Authoring against it from pvxs needs the
``:project: PVXS_CMS`` flag because it is not part of the default
project (which is pvxs).

.. doxygenstruct:: cms::cert::CertDate
   :project: PVXS_CMS
   :no-link:

See also
--------

* :doc:`/protocol-spec/cert-protocol` — the on-the-wire protocol behind
  certificate management; the C++ types above are how pvxs / pvxs-cms
  speak that protocol.
* :doc:`/programmers-ref/cert-management` — how an application
  developer drives a CCR submission from pvxs against PVACMS.
