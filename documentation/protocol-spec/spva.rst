.. _spva_protocol_spec:

==================================================
Secure PVAccess (SPVA) Protocol Specification
==================================================

:Status: Placeholder
:Protocol Version: TBD

.. note::

   This document is a placeholder. The SPVA protocol specification will
   be authored after the PVA specification (:doc:`/protocol-spec/pva`)
   has been reviewed and finalised. SPVA is a security profile of PVA
   that adds TLS 1.3 transport, X.509 mutual authentication, and a
   certificate-management RPC layer; it is layered on top of PVA and
   normatively references the PVA specification for everything not
   security-specific.

   When this document is written, it will follow the same RFC-style
   structure as the CA specification: numbered sections, RFC 2119
   keywords, and normative references to :rfc:`8446` (TLS 1.3),
   :rfc:`5280` (X.509 PKIX), :rfc:`6960` (OCSP), and other relevant
   specifications. SPVA-specific elements — the cert-status
   PVStructure schema, the Certificate Creation Request (CCR)
   PVStructure schema, the authenticator-extension framework, the
   ASG/ACF authorization extensions — will be specified in full;
   underlying TLS / X.509 mechanics will be referenced not redescribed.

   Existing SPVA implementation reference material (the SPVA TLS modes,
   authentication flows, authorization model, and certificate
   lifecycle) lives under :doc:`/programmers-ref/index` and is
   "how SPVA works in pvxs", not the protocol specification.

.. seealso::

   - :doc:`/protocol-spec/ca` — the predecessor of PVA.
   - :doc:`/protocol-spec/pva` — the underlying protocol that SPVA secures.
   - :doc:`/programmers-ref/spva-tls` — pvxs's implementation of SPVA's TLS layer.
   - :doc:`/programmers-ref/spva-authentication` — pvxs's implementation of SPVA authentication.
   - :doc:`/programmers-ref/spva-authorization` — pvxs's implementation of SPVA authorization.
   - :doc:`/programmers-ref/spva-cert-management-protocol` — pvxs's implementation of SPVA cert management.
