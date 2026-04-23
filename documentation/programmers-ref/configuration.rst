.. _spva_configuration:

|guide| Configuration
======================

.. _environment_variables:

Environment Variables
---------------------

The following environment variables control SPVA behavior.

.. note::

   The PVAS variant of each environment variable supersedes the PVA variant when both are set.
   For example, ``EPICS_PVAS_TLS_KEYCHAIN`` takes precedence over ``EPICS_PVA_TLS_KEYCHAIN``.


+--------------------------+----------------------------+-------------------------------------+---------------------------------------------------------------+
| Name                     | Key                        | Value                               | Description                                                   |
+==========================+============================+=====================================+===============================================================+
| EPICS_PVA_CERT_PV_PREFIX | {string prefix for certificate management PVs}                   | Replaces the default ``CERT`` prefix. Combined with           |
|                          | e.g. ``ORNL_CERTS``                                              | ``:STATUS:...``, ``:ROOT``, or ``:CREATE`` to form PV names.  |
+--------------------------+------------------------------------------------------------------+---------------------------------------------------------------+
| EPICS_PVA_TLS_KEYCHAIN   | {fully qualified path  to keychain file}                         | Fully qualified path to the keychain file containing the      |
+--------------------------+                                                                  | certificate and private keys used in the TLS handshake.       |
| EPICS_PVAS_TLS_KEYCHAIN  | e.g. ``~/.config/client.p12``,                                   | If not specified, TLS is disabled.                            |
|                          | ``~/.config/server.p12``                                         |                                                               |
+--------------------------+------------------------------------------------------------------+---------------------------------------------------------------+
| EPICS_PVA_TLS_KEYCHAIN   | {fully qualified path to keychain password file}                 | Fully qualified path to a file containing the password that   |
| _PWD_FILE                |                                                                  | decrypts the keychain file. Optional. If not specified, the   |
+--------------------------+ e.g. ``~/.config/client.pass``,                                  | keychain file is treated as unencrypted. Omitting a password  |
| EPICS_PVAS_TLS_KEYCHAIN  | ``~/.config/server.pass``                                        | file is not recommended.                                      |
| _PWD_FILE                |                                                                  |                                                               |
+--------------------------+----------------------------+-------------------------------------+---------------------------------------------------------------+
| EPICS_PVA_TLS_OPTIONS    | ``client_cert``            | ``optional`` (default)              | During TLS handshake require client certificate to be         |
|                          |                            |                                     | presented                                                     |
|                          | Controls whether client    +-------------------------------------+---------------------------------------------------------------+
| Space-separated          | certificates are required. | ``require``                         | Don't require client certificate to be presented.             |
| key=value pairs.         +----------------------------+-------------------------------------+---------------------------------------------------------------+
|                          | ``on_expiration``          | ``fallback-to-tcp``  (default)      | For servers only tcp search requests will be responded to.    |
|                          |                            |                                     | For clients then no client certificate will be presented      |
|                          | Behavior when a            |                                     | in the TLS handshake (but searches will still offer both tls  |
|                          | certificate has expired    |                                     | and tcp as supported protocols)                               |
|                          | and cannot be              +-------------------------------------+---------------------------------------------------------------+
|                          | automatically              | ``shutdown``                        | The process will exit gracefully.                             |
|                          | reprovisioned.             +-------------------------------------+---------------------------------------------------------------+
|                          |                            | ``standby``                         | Servers will not respond to any requests until a new          |
|                          |                            |                                     | certificate is successfully provisioned.  It will keep        |
|                          |                            |                                     | retrying the keychain file periodically.  When a valid        |
|                          |                            |                                     | certificate is available it will continue as normal.          |
|                          |                            |                                     |                                                               |
|                          |                            |                                     | For a client standby has the same effect as shutdown.         |
|                          +----------------------------+-------------------------------------+---------------------------------------------------------------+
|                          | ``no_revocation_check``    |                                     | Disables certificate revocation status monitoring. The        |
|                          |                            |                                     | certificate cannot be revoked while this flag is set.         |
|                          | Controls certificate       |                                     | Default: revocation status monitoring is enabled.             |
|                          | revocation monitoring.     |                                     |                                                               |
|                          +----------------------------+-------------------------------------+---------------------------------------------------------------+
|                          | ``no_stapling``            | ``yes``, ``true``, ``1``            | Servers won't staple certificate status, clients won't        |
|                          |                            |                                     | request stapling information during TLS handshake             |
|                          | Controls OCSP stapling.    +-------------------------------------+---------------------------------------------------------------+
|                          |                            | ``no``, ``false``, ``0`` (default)  | Stapling is enabled.                                          |
+--------------------------+----------------------------+-------------------------------------+---------------------------------------------------------------+
| EPICS_PVA_TLS_PORT       | {port number} default ``5076``                                   | Port number for Secure PVAccess. For clients, the server port |
|                          |                                                                  | to connect to (PVA). For servers, the local port to listen on |
+--------------------------+ e.g. ``8076``                                                    | (PVAS).                                                       |
| EPICS_PVAS_TLS_PORT      |                                                                  |                                                               |
+--------------------------+------------------------------------------------------------------+---------------------------------------------------------------+
| EPICS_PVA_STATUS         | {fully qualified path to status cache directory}                 | Override the default OCSP status cache directory.             |
| _CACHE_DIR               |                                                                  | When TLS is enabled, pvxs caches signed OCSP responses to     |
|                          | e.g. ``/var/cache/pva/status``                                   | disk so that certificate status is available immediately on   |
|                          |                                                                  | process restart, eliminating the cold-start window where      |
|                          |                                                                  | status is UNKNOWN.                                            |
|                          |                                                                  |                                                               |
|                          |                                                                  | default: ``${XDG_DATA_HOME}/pva/1.5/status_cache/``           |
|                          |                                                                  | (typically ``~/.local/share/pva/1.5/status_cache/``)          |
+--------------------------+------------------------------------------------------------------+---------------------------------------------------------------+
| EPICS_PVA_NO_STATUS      | ``yes``, ``true``, ``1``                                         | Disable OCSP status caching entirely.  When set, no cache     |
| _CACHE                   |                                                                  | files are read or written and the process always waits for    |
|                          |                                                                  | a live PV subscription to obtain certificate status.          |
|                          |                                                                  |                                                               |
|                          |                                                                  | default: caching is enabled                                   |
+--------------------------+------------------------------------------------------------------+---------------------------------------------------------------+
| SSLKEYLOGFILE            | {fully qualified path to key log file}                           | Path to the SSL key log file. When defined and the library is |
|                          |                                                                  | built with the ``PVXS_ENABLE_SSLKEYLOGFILE`` macro, TLS       |
|                          | e.g. ``~/.config/keylog``                                        | session keys are written to this file.                        |
|                          |                                                                  |                                                               |
+--------------------------+------------------------------------------------------------------+---------------------------------------------------------------+

.. _configuration:

API Configuration Options
-------------------------

The following configuration options are available in both `pvxs::server::Config` and `pvxs::client::Config`
via their public base class `pvxs::impl::ConfigCommon`:

- `pvxs::impl::ConfigCommon::expiration_behaviour` - Set certificate expiration behavior
- `pvxs::impl::ConfigCommon::tls_keychain_file` - Set keychain file path
- `pvxs::impl::ConfigCommon::tls_client_cert_required` - Control client certificate requirements
- `pvxs::impl::ConfigCommon::tls_port` - Set TLS port number
