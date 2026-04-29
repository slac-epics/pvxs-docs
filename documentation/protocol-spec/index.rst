.. _protocol_spec:

Protocol Specification
======================

Normative wire-protocol specifications for the three EPICS network
protocols. Each document fully and unambiguously defines its protocol
in the style of an IETF RFC: numbered sections, RFC 2119 keywords
(MUST / SHALL / SHOULD / MAY), explicit message formats, complete
state machines, and references to other normative documents (TLS,
X.509, etc.) rather than redescribing them.

The three protocols are layered historically:

- **CA** (Channel Access) — the original EPICS network protocol. Designed
  for typed scalar/array transport of process variables.
- **PVA** (PVAccess) — successor to CA. Extends the wire format to
  carry structured (PVData) values; introduces a richer type system
  and operation set. Independent of CA on the wire.
- **SPVA** (Secure PVAccess) — security profile of PVA. Adds TLS 1.3,
  X.509 mutual authentication, and a certificate-management RPC layer
  on top of PVA. References PVA for everything not security-specific.

.. toctree::
   :maxdepth: 1

   ca
   pva
   spva

.. seealso::

   :doc:`/shared/spvaglossary` — definitions of SPVA terms used across this manual.
