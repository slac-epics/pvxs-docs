.. _appendix:

Appendix
========

.. _expert_api:

EXPERT API Additions for Secure PVAccess
-----------------------------------------

Runtime Reconfiguration
^^^^^^^^^^^^^^^^^^^^^^^

Allows runtime reconfiguration of a TLS connection.  It does this by dropping all TLS connections and
then re-initialising them using the given configuration.  This means checking if the certificates
and keys exist, loading and verifying them, checking for status and status of peers, etc.

- `pvxs::client::Context::reconfigure` and
- `pvxs::server::Server::reconfigure`

Example of TLS configuration reconfiguration:

.. code-block:: c++

    // Initial client setup with certificate
    auto cli_conf(serv.clientConfig());
    cli_conf.tls_keychain_file = "client1.p12";
    auto cli(cli_conf.build());

    // Later reconfiguration with new certificate
    cli_conf = cli.config();
    cli_conf.tls_keychain_file = "client2.p12";
    cli_conf.tls_keychain_pwd = "pwd";
    cli.reconfigure(cli_conf);

ConfigCommon Expert Methods
^^^^^^^^^^^^^^^^^^^^^^^^^^^

The following methods on ``pvxs::impl::ConfigCommon`` are available when building with
``PVXS_ENABLE_EXPERT_API`` defined. They provide programmatic access to private configuration
fields that control certificate status checking, stapling, request timeouts, PV prefixes,
and keychain passwords.

Certificate Status Checking
~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: c++

    void disableStatusCheck(const bool disable = true);
    bool isStatusCheckDisabled() const;

Disable or query certificate revocation status monitoring from PVACMS.
When disabled, certificates will not be checked against the PVACMS for revocation status,
meaning that revoked certificates will still be accepted.

.. code-block:: c++

    auto conf = pvxs::server::Config::fromEnv();
    conf.disableStatusCheck();  // disable status checking

Certificate Stapling
~~~~~~~~~~~~~~~~~~~~

.. code-block:: c++

    void disableStapling(const bool disable = true);
    bool isStaplingDisabled() const;

Disable or query certificate status stapling. When disabled, servers will not staple
certificate status responses to TLS handshakes, and clients will not request stapled
status from servers.

.. code-block:: c++

    auto conf = pvxs::server::Config::fromEnv();
    conf.disableStapling();  // disable stapling

Request Timeout
~~~~~~~~~~~~~~~

.. code-block:: c++

    void setRequestTimeout(const double timeout);
    double getRequestTimeout() const;

Set or query the request timeout in seconds (default: 5.0). This timeout applies to
operations like certificate status queries. Cannot be set via environment variables —
only programmatically or via command line tool arguments.

.. code-block:: c++

    auto conf = pvxs::client::Config::fromEnv();
    conf.setRequestTimeout(10.0);  // 10 second timeout

Certificate PV Prefix
~~~~~~~~~~~~~~~~~~~~~

.. code-block:: c++

    void setCertPvPrefix(const std::string &prefix);
    std::string getCertPvPrefix() const;

Set or query the prefix used for certificate management PV names (default: ``"CERT"``).
The prefix is prepended to ``:STATUS:...``, ``:ROOT``, and ``:CREATE`` to form the
full PV names used for PVACMS communication.

.. code-block:: c++

    auto conf = pvxs::client::Config::fromEnv();
    conf.setCertPvPrefix("ORNL_CERTS");  // use site-specific prefix

Keychain Password
~~~~~~~~~~~~~~~~~

.. code-block:: c++

    void setKeychainPassword(const std::string &pwd);
    std::string getKeychainPassword() const;

Set or query the password used to decrypt the PKCS#12 keychain file. This provides
a programmatic alternative to the ``EPICS_PVA_TLS_KEYCHAIN_PWD_FILE`` environment variable.

.. code-block:: c++

    auto conf = pvxs::client::Config::fromEnv();
    conf.setKeychainPassword("my_password");

Wildcard PV Support
^^^^^^^^^^^^^^^^^^^

This addition is based on the Wildcard PV support included in epics-base since version 3.  It
extends this support to pvxs allowing PVs to be specified as wildcard patterns.  We use this
to provide individualised PVs for each certificate's status management.

- `pvxs::server::WildcardPV`

Example of support for pattern-matched PV names:

.. code-block:: c++

    // Define a server that responds to any SEARCH request with WILDCARD:PV:<4-characters>:<any-string>
    // It will extract the 4-character part of the PV name as the `id` and
    // the last string as the `name`

    WildcardPV wildcard_pv(WildcardPV::buildMailbox());
    wildcard_pv.onFirstConnect([](WildcardPV &pv, const std::string &pv_name,
                                const std::list<std::string> &parameters) {
        // Extract id and name from parameters
        auto it = parameters.begin();
        const std::string &id = *it;
        const std::string &name = *++it;

        // Process and post value
        if (pv.isOpen(pv_name)) {
            pv.post(pv_name, value);
        } else {
            pv.open(pv_name, value);
        }
    });
    wildcard_pv.onLastDisconnect([](WildcardPV &pv, const std::string &pv_name,
                                const std::list<std::string> &parameters) {
        pv.close(pv_name);
    });

    // Add wildcard PV to server
    auto wildcard_source = WildcardSource::build();
    wildcard_source->add("WILDCARD:PV:????:*", wildcard_pv);
    serv.addSource("__wildcard", wildcard_source);
