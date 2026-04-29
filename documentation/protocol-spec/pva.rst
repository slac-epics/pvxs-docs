.. _pva_protocol_spec:

==========================================
PVAccess (PVA) Protocol Specification
==========================================

:Status: Placeholder
:Protocol Version: TBD

.. note::

   This document is a placeholder. The PVA protocol specification will
   be authored after the CA specification (:doc:`/protocol-spec/ca`)
   has been reviewed and finalised. PVA is the EPICS 7 successor to
   CA; it carries structured PVData values and uses a different
   wire format. See the existing PVA implementation reference
   material under :doc:`/programmers-ref/index` for now.

   When this document is written, it will follow the same RFC-style
   structure as the CA specification: numbered sections, RFC 2119
   keywords, normative references to TLS / X.509 only insofar as PVA
   itself uses them, and a complete description of the wire format,
   state machines, message types, and error handling.

.. seealso::

   - :doc:`/protocol-spec/ca` — the predecessor protocol.
   - :doc:`/protocol-spec/spva` — the security profile of PVA.
