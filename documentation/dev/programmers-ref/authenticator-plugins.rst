.. _programmers_authenticator_plugins:

Building Authenticator Plugins
==============================

PVACMS authenticators are C++ implementations that do two jobs:

* a user-facing executable creates a certificate creation request (CCR)
  and sends it to PVACMS;
* PVACMS links the matching verifier so it can approve or reject that
  request when it arrives.

The existing authenticators are the canonical templates:

* ``pvxs-cms/src/authn/std`` — standard self-declared identity (Type 0),
  normally requiring administrator approval;
* ``pvxs-cms/src/authn/krb`` — Kerberos-backed identity verification (Type 2);
* ``pvxs-cms/src/authn/ldap`` — LDAP-backed identity verification (Type 2).

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

The ``Auth`` base class
-----------------------

Every authenticator subclasses ``cms::auth::Auth``
(``pvxs-cms/src/authn/auth.h``). The interface the subclass must
implement is:

.. code-block:: c++

   namespace cms { namespace auth {

   class Auth {
    public:
       // type_ is the wire-level type string ("std", "krb", "ldap", "site", …)
       // verifier_fields_ names the extra fields your verifier adds to the CCR
       Auth(const std::string &type,
            const std::vector<pvxs::Member> &verifier_fields);

       // --- called on the authenticator-tool side ---

       // Return credentials derived from whatever identity source you use.
       // Return nullptr if credentials are unavailable.
       virtual std::shared_ptr<AuthnCredentials> getCredentials(
           const pvxs::client::Config &config, bool for_client) const = 0;

       // Populate a CCR from the credentials and key pair.
       virtual std::shared_ptr<CertCreationRequest> createCertCreationRequest(
           const std::shared_ptr<AuthnCredentials> &credentials,
           const std::shared_ptr<KeyPair> &key_pair,
           const uint16_t &usage,
           const ConfigAuthN &config) const = 0;

       // Read any authenticator-specific env vars into config.
       virtual void fromEnv(
           std::unique_ptr<pvxs::client::Config> &config) = 0;

       // --- called on the PVACMS verifier side ---

       // Inspect the incoming CCR value.  Throw to reject.
       // Set authorized_validity to the maximum you will authorise (0 = PVACMS default).
       // Return true to authorise issuance without admin approval.
       virtual bool verify(pvxs::Value &ccr,
                           time_t &authorized_validity) const = 0;
   };

   }} // namespace cms::auth

The tool-side ``main()`` uses the ``cms::auth::runAuthenticator<ConfigT, AuthT>``
template (also in ``auth.h``), which takes care of arg parsing, key-pair
management, CCR submission, and P12 file writing.  You do not need to
call any of those steps yourself.

Registration in PVACMS
-----------------------

PVACMS discovers verifiers through a static registrar placed in the
authenticator's ``.cpp`` file.  The convention is a file-scope struct
whose constructor calls ``AuthRegistry::instance().registerAuth()``:

.. code-block:: c++

   // In authnsite.cpp, compiled into BOTH authnsite and pvacms
   #define PVXS_SITE_AUTH_TYPE "site"

   struct AuthNSiteRegistrar {
       AuthNSiteRegistrar() {
           AuthRegistry::instance().registerAuth(
               PVXS_SITE_AUTH_TYPE,
               std::unique_ptr<cms::auth::Auth>(new AuthNSite()));
       }
   } auth_n_site_registrar;

This file must be listed in both ``authnsite_SRCS`` and ``pvacms_SRCS``
in the Makefile so the registrar fires in both the tool process and the
PVACMS process.

Type 0 — self-declared identity (no external verification)
-----------------------------------------------------------

A Type 0 authenticator (like ``authnstd``) carries no cryptographic
identity proof.  The ``verifier`` sub-structure in the CCR is empty
(``verifier_fields_`` is an empty vector).

PVACMS cannot confirm the caller's identity independently, so
``verify()`` returns ``false``, telling PVACMS to gate issuance on the
``cert_<usage>_require_approval`` site policy.

Boilerplate: ``getCredentials`` for a Type 0 authenticator
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: c++

   std::shared_ptr<AuthnCredentials> AuthNSite::getCredentials(
       const pvxs::client::Config &config, bool for_client) const
   {
       auto creds = std::make_shared<DefaultCredentials>();
       // Fill in subject fields from config or from the environment.
       // ConfigAuthN carries the parsed flags from the command line.
       const auto &cfg = static_cast<const ConfigAuthN &>(config);
       creds->name             = cfg.name.empty()         ? getUsername()  : cfg.name;
       creds->organization     = cfg.organization.empty() ? getHostname()  : cfg.organization;
       creds->organization_unit = cfg.organization_unit;
       creds->country          = cfg.country.empty()      ? getLocale()    : cfg.country;

       const time_t now = time(nullptr);
       creds->not_before = now;
       // not_after = 0 means "let PVACMS decide".
       creds->not_after  = (cfg.cert_validity_mins > 0)
                           ? now + cfg.cert_validity_mins * 60
                           : 0;
       return creds;
   }

Boilerplate: ``createCertCreationRequest`` (shared by all types)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

All types call the base-class implementation, which fills in the common
CCR fields from the credentials and key pair.  Type-specific code then
adds verifier-specific fields:

.. code-block:: c++

   std::shared_ptr<CertCreationRequest> AuthNSite::createCertCreationRequest(
       const std::shared_ptr<AuthnCredentials> &credentials,
       const std::shared_ptr<KeyPair> &key_pair,
       const uint16_t &usage,
       const ConfigAuthN &config) const
   {
       // Base class handles name/org/country/usage/pub_key/not_before/not_after.
       auto ccr = Auth::createCertCreationRequest(
           credentials, key_pair, usage, config);
       // Type 0: nothing extra goes into ccr->ccr["verifier.*"]
       return ccr;
   }

Boilerplate: ``verify`` for a Type 0 authenticator
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: c++

   bool AuthNSite::verify(pvxs::Value &ccr, time_t &authorized_validity) const
   {
       // No proof to check.  Returning false means PVACMS applies the
       // cert_<usage>_require_approval site policy before issuing.
       return false;
   }

Type 1 — independently verifiable token (signature against configured key)
--------------------------------------------------------------------------

A Type 1 authenticator embeds a payload in the CCR that PVACMS can verify
without contacting any external service — for example, a signature over
the CCR fields made with a well-known public key.

This pattern is useful for automated provisioning or CI pipelines where a
signing key can be distributed to the tool side, and the matching public
key is configured in PVACMS.

Tool side: sign the CCR fields
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Add a ``signature`` field to ``verifier_fields_``:

.. code-block:: c++

   AuthNSiteType1::AuthNSiteType1()
       : Auth("site1", {pvxs::Member(pvxs::TypeCode::Int8A, "signature")})
   {}

In ``createCertCreationRequest``, sign a canonical representation of the
CCR and attach the signature:

.. code-block:: c++

   std::shared_ptr<CertCreationRequest> AuthNSiteType1::createCertCreationRequest(
       const std::shared_ptr<AuthnCredentials> &credentials,
       const std::shared_ptr<KeyPair> &key_pair,
       const uint16_t &usage,
       const ConfigAuthN &config) const
   {
       auto ccr = Auth::createCertCreationRequest(credentials, key_pair, usage, config);

       // ccrToString() produces the canonical byte string used for signing.
       // Use Auth::ccrToString (protected helper) for consistency with verify().
       const std::string canonical = ccrToString(ccr, usage);

       // Sign with the private signing key for this site.
       std::vector<uint8_t> sig = signWithSiteKey(canonical, config.site_signing_key);

       pvxs::shared_array<const uint8_t> sig_arr(sig.begin(), sig.end());
       ccr->ccr["verifier.signature"] = sig_arr;

       return ccr;
   }

PVACMS verifier side: check the signature against the configured public key
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: c++

   bool AuthNSiteType1::verify(pvxs::Value &ccr, time_t &authorized_validity) const
   {
       if (ccr["type"].as<std::string>() != "site1")
           throw std::runtime_error("CCR type mismatch");

       // Reconstruct the canonical string from the CCR.
       const std::string canonical = ccrToString(ccr);

       // Extract the signature bytes from the CCR.
       auto sig_arr = ccr["verifier.signature"].as<pvxs::shared_array<const uint8_t>>();
       const std::vector<uint8_t> sig(sig_arr.begin(), sig_arr.end());

       // Verify against the site public key configured in PVACMS.
       if (!verifyWithSitePublicKey(canonical, sig, configured_public_key_)) {
           throw std::runtime_error("CCR signature verification failed");
       }

       // Authorise for a site-specific duration; return true to skip admin approval.
       authorized_validity = time(nullptr) + 365 * 24 * 60 * 60; // one year
       return true;
   }

Type 2 — authority-verifiable token (requires external endpoint)
----------------------------------------------------------------

A Type 2 authenticator (like ``authnkrb``) embeds a token that only an
external authority (KDC, LDAP server, OAuth endpoint) can validate.
The ``verify()`` implementation contacts that authority at PVACMS startup
time, which means PVACMS must be able to reach the authority service.

The Kerberos authenticator is the reference implementation.  The tool
side obtains a GSS-API service ticket and a MIC over the public key
(``authnkrb.cpp``), and the PVACMS verifier contacts the KDC via the
keytab to accept the token (``authnkrb.cpp:verify()``).

Tool side: acquire token from KDC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The relevant CCR fields are declared in the constructor:

.. code-block:: c++

   AuthNKrb::AuthNKrb()
       : Auth(PVXS_KRB_AUTH_TYPE,
              {pvxs::Member(pvxs::TypeCode::Int8A, "token"),
               pvxs::Member(pvxs::TypeCode::Int8A, "mic")})

``createCertCreationRequest`` calls ``gss_init_sec_context`` to get the
service ticket and ``gss_get_mic`` over the public key string, then
stores both in the CCR:

.. code-block:: c++

   cert_creation_request->ccr["verifier.token"] = token_bytes;
   cert_creation_request->ccr["verifier.mic"]   = mic_bytes;

PVACMS verifier side: accept the token via the KDC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: c++

   bool AuthNKrb::verify(pvxs::Value &ccr, time_t &authorized_validity) const
   {
       // 1. Check that the keytab is configured.
       if (krb_keytab_file.empty())
           throw std::runtime_error("KRB5_KTNAME not set");

       // 2. Acquire PVACMS server credentials from the keytab.
       gss_name_t serverName = GSS_C_NO_NAME;
       // ... (gss_import_name + gss_acquire_cred) ...

       // 3. Extract the client token from the CCR.
       auto token_bytes = ccr["verifier.token"].as<pvxs::shared_array<const uint8_t>>();

       // 4. Accept the client token — this validates with the KDC.
       // gss_accept_sec_context establishes the context if the token is valid.
       auto context = GSS_C_NO_CONTEXT;
       // major_status = gss_accept_sec_context(...)
       // throw on GSS_ERROR(major_status)

       // 5. Retrieve the peer principal name and compare it with the CCR name/org.
       // If mismatch, throw.

       // 6. Verify the MIC over the public key to confirm it was not tampered.
       auto mic_arr = ccr["verifier.mic"].as<pvxs::shared_array<const uint8_t>>();
       // gss_verify_mic(...) — throw on GSS_ERROR

       // 7. Set authorized_validity from the KDC-granted ticket lifetime.
       authorized_validity = time(nullptr) + peer_lifetime;

       // Return true: KDC validation substitutes for admin approval.
       return true;
   }

See ``pvxs-cms/src/authn/krb/authnkrb.cpp`` for the full implementation.

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
