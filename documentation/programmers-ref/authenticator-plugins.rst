.. _programmers_authenticator_plugins:

Building Authenticator Plugins
==============================

PVACMS authenticators are C++ implementations that do two jobs:

* a user-facing executable creates a certificate creation request;
* PVACMS links the matching verifier so it can approve or reject that
  request when it arrives.

The existing authenticators are the templates to follow:

* ``pvxs-cms/src/authn/std`` — standard self-declared identity,
  normally requiring administrator approval;
* ``pvxs-cms/src/authn/krb`` — Kerberos-backed identity verification;
* ``pvxs-cms/src/authn/ldap`` — LDAP-backed identity verification.

Build wiring
------------

Authenticator build fragments are included from
``pvxs-cms/src/authn/Makefile``. A new authenticator normally needs a new
subdirectory and a Makefile fragment modelled on the existing ones:

.. code-block:: make

   SRC_DIRS += $(AUTHN)/site

   PROD += authnsite
   authnsite_SRCS += authnsite.cpp
   authnsite_SRCS += authnsitemain.cpp
   authnsite_SRCS += configsite.cpp
   authnsite_SRCS += certstatusfactory.cpp
   authnsite_SRCS += certstatus.cpp
   authnsite_SRCS += certstatusmanager.cpp
   authnsite_SRCS += certfactory.cpp
   authnsite_SRCS += certfilefactory.cpp
   authnsite_SRCS += p12filefactory.cpp
   authnsite_SRCS += auth.cpp
   authnsite_SRCS += configauthn.cpp
   authnsite_SRCS += ccrmanager.cpp

   pvacms_SRCS += authnsite.cpp
   pvacms_SRCS += configsite.cpp

   authnsite_LIBS += pvxs Com
   authnsite_SYS_LIBS += site_dependency
   pvacms_SYS_LIBS += site_dependency

Then include that fragment from ``src/authn/Makefile`` behind a feature
flag if the authenticator depends on optional site libraries:

.. code-block:: make

   ifeq ($(PVXS_ENABLE_SITE_AUTH),YES)
   include $(AUTHN)/site/Makefile
   endif

Keep optional dependencies out of the default build unless every target
platform has them.

Code shape
----------

An authenticator implementation follows the ``cms::auth`` namespace and
the existing
:doc:`cms::auth::Auth </maintainer-docs/api-reference-pvxs-cms-auth>`
framework. The user-facing executable should:

1. read common options such as certificate usage, name, organization,
   validity duration, certificate process variable prefix, issuer, and
   keychain path;
2. build a certificate creation request with the common fields;
3. add an authenticator-specific ``verifier`` payload;
4. send the request to PVACMS using the shared certificate creation
   request manager;
5. write the returned certificate and trust anchor into the configured
   keychain.

The PVACMS-side verifier should:

1. verify that the request type belongs to the authenticator;
2. verify the external identity proof, such as a Kerberos token or LDAP
   signature;
3. compare that proof with the identity requested in the certificate;
4. reject malformed or inconsistent certificate creation requests with a
   clear exception;
5. return success only when PVACMS may issue the certificate without an
   extra administrator approval step.

Certificate creation request contract
-------------------------------------

The wire shape of the request belongs to the protocol documentation:
:ref:`certificate_creation_request_CCR`. Plugin code should not invent a
parallel request path. Put authenticator-specific data under the request's
``verifier`` structure and keep the common certificate fields common.

Operational behaviour
---------------------

Authenticator tools should support the same operational conventions as
the built-in tools:

* ``-u`` / ``--cert-usage`` selects client, server, or IOC usage;
* ``-n`` / ``--name`` controls the certificate common name when the
  identity provider allows it;
* ``--cert-pv-prefix`` selects the PVACMS process variable prefix;
* ``-i`` / ``--issuer`` selects one PVACMS issuer when more than one is
  discoverable;
* ``-D`` / ``--daemon`` keeps a renewal helper running when that model is
  appropriate for the authenticator;
* ``--schedule`` and subject alternative name options should be preserved
  if the authenticator supports certificates that carry those fields.

Testing
-------

Test both halves. A useful test matrix is:

* request generation rejects missing or inconsistent identity inputs;
* PVACMS verifier rejects a tampered verifier payload;
* a successful request issues a certificate with the expected subject and
  usage;
* renewal works when the existing certificate is past its renewal date;
* the authenticator is absent from the build when its feature flag is not
  enabled.

For end-to-end tests, use the pvxs-cms test harness rather than a mock
PVACMS when possible. It exercises the real certificate-status and
PVAccess paths.
