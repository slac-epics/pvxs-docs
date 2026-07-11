.. _pva_protocol_spec:

======================================
PVAccess (PVA) Protocol Specification
======================================

The PVAccess (PVA) protocol is the EPICS 7 successor to Channel Access
(:doc:`/protocol-spec/ca`), extending the wire format to carry structured
(PVData) values with a richer type system and operation set.

.. note::

   The canonical PVAccess protocol specification is maintained by the EPICS
   community and is published at:

   https://docs.epics-controls.org/en/latest/pv-access/protocol.html

   That document is authoritative. This page is a pointer only; refer to the
   community specification for the normative protocol definition.

.. seealso::

   - :doc:`/protocol-spec/spva` — Secure PVAccess, the TLS 1.3 / X.509 security
     profile layered on top of PVA (specified in this manual).
   - :doc:`/shared/spvaglossary` — definitions of SPVA terms used across this manual.
