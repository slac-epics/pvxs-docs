.. _ca_protocol_spec:

==========================================
Channel Access (CA) Protocol Specification
==========================================

Channel Access (CA) is the original EPICS network protocol for accessing
process variables (PVs) on Input/Output Controllers (IOCs), defining a
connection lifecycle, name resolution, and read/write/monitor operations
over UDP and TCP.

.. note::

   The canonical Channel Access protocol specification is maintained by the
   EPICS community and is published at:

   https://docs.epics-controls.org/en/latest/internal/ca_protocol.html

   That document is authoritative. This page is a pointer only; refer to the
   community specification for the normative protocol definition.

.. seealso::

   - :doc:`/protocol-spec/pva` — PVAccess, the EPICS 7 successor to CA
     (pointer page).
   - :doc:`/shared/spvaglossary` — definitions of SPVA terms used across this manual.
