.. _secure_pvaccess:

|security| Overview
=====================

Secure PVAccess (SPVA) enhances the existing PVAccess protocol by integrating :ref:`transport_layer_security` (TLS)
with comprehensive :ref:`certificate_management`, enabling encrypted communication channels and authenticated connections
between EPICS clients and servers (EPICS agents) - see :ref:`authn_and_authz`.

For a glossary of terms see: :ref:`glossary`

Key Features:

- Encrypted communication using ``TLS 1.3``
- Certificate-based authentication
- Comprehensive certificate lifecycle management
- Backward compatibility with existing PVAccess deployments
- Integration with site authentication systems

Note: This release requires specific unmerged changes to epics-base.

See :ref:`quick_start` to get started.

For PVXS library documentation see `PVXS Docs <https://slac-epics.github.io/pvxs-tls/>`_.

.. toctree::
   :maxdepth: 3
   :caption: Contents:

   protocol-spec/spva
   programmers-ref/configuration
   protocol-spec/spvaauth
   protocol-spec/spvaauthorization
   spvacerts
   user-manual/pvacms
   user-manual/cli
   user-manual/spvaqstart
   user-manual/spvaqstartstd
   user-manual/spvaqstartkrb
   user-manual/spvaqstartldap
   user-manual/spvaqsgw
   shared/spvaglossary
   appendix


Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
