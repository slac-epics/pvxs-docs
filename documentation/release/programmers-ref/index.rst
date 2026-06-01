.. _programmers_ref:

Programmers Reference
=====================

For application developers writing Secure-PVAccess-aware software. This manual
covers building the libraries, linking executables, writing clients, servers,
and IOCs, building custom authenticators, and understanding the monitoring and
performance hooks SPVA adds around the protocol.

Protocol implementations
------------------------

The :doc:`/protocol-spec/index` defines SPVA normatively: the wire format,
TLS 1.3 transport, certificate lifecycle, cert-status protocol, and
authentication/authorization semantics. What follows in this manual are
implementations of that protocol in three languages, each with a different
degree of coverage of the full specification.

.. list-table::
   :widths: 15 25 20 40
   :header-rows: 1

   * - Language
     - Library
     - Distribution
     - Protocol coverage notes
   * - **C++**
     - pvxs + pvxs-cms
     - Built from source (see :doc:`building`)
     - Full implementation. All SPVA features: mutual TLS, cert-status
       monitoring, CCR submission, renewal, authenticator plugins, IOC
       support, EXPERT API, OCSP stapling.
   * - **Python**
     - P4P (Cython/C++ wrapper over pvxs)
     - ``pip install p4p`` (PyPI)
     - Inherits all pvxs capabilities through the C++ binding. TLS and
       cert-status work transparently. CCR/renewal must be driven by
       the ``authnxxx`` tools; no Python-level CCR API is exposed.
       No EXPERT API surface.

       **ACF grammar note:** P4P has its own ACF parser (``p4p.asLib``,
       written in Python) used by the ``pvagw`` gateway. Support for the
       new SPVA predicates ``METHOD``, ``AUTHORITY``, and ``PROTOCOL``
       depends on which p4p branch is built. See
       :ref:`acf_implementation_coverage` and :doc:`building`.
   * - **Java**
     - Phoebus ``core-pva``
     - ``org.phoebus:core-pva`` (Maven Central)
     - Independent re-implementation of PVAccess and SPVA. Supports
       mutual TLS, cert-status monitoring, and server-side identity
       inspection. Does not implement CCR submission or renewal — use
       the ``authnxxx`` tools to obtain certificates.

All three implementations share the same wire protocol, the same PKCS#12
keychain file format, and the same environment variables for TLS
configuration. A certificate issued by PVACMS and installed by
``authnstd`` or ``authnkrb`` works unchanged with C++, Python, and Java
clients talking to each other or to a C++ IOC.

Start with :doc:`building` to get the libraries and tools built, then
:doc:`tools` for a map of all executables and a step-by-step guide to
standing up PVACMS, obtaining certificates, and verifying your
environment before writing any application code.

.. toctree::
   :maxdepth: 2

   building
   tools
   applications
   authenticator-plugins
   performance
   configuration
   spva-tls
   spva-authentication
   spva-authorization
   cert-management
   expert-api

.. seealso::

   :doc:`/shared/spvaglossary` — definitions of SPVA terms used across this manual.
