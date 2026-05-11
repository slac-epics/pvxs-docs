.. _user_operation:

Operating Secure PVAccess
=========================

This page is the operator checklist. It tells you what has to be
configured and what has to be running before clients, IOCs, and services
can use Secure PVAccess. The quick-start pages show complete lab
walkthroughs; this page is the shorter day-to-day map.

Minimal deployment pieces
-------------------------

A working SPVA deployment has these pieces:

1. **PVACMS** — the certificate-management service and site certificate
   authority. It publishes certificate creation, status, health, metrics,
   and administration process variables.
2. **A certificate for each identity** — clients use client certificates;
   IOCs and servers use server certificates; gateways usually need IOC
   certificates because they act as both client and server.
3. **A trust anchor** — each participant must trust the PVACMS root
   certificate that signed the peer certificates.
4. **Address-list configuration** — clients and servers must be able to
   find PVACMS for certificate status and, separately, find the process
   variables they use.
5. **Access security rules** — write and administration permissions should
   check authenticated identity, authority, protocol, and method where
   appropriate.

Happy-path build
----------------

If you are trying SPVA rather than developing it, use the prepackaged
container in :doc:`spvaqstart`. If you need a local build, the shortest
path is:

.. code-block:: shell

   make -C epics-base -j
   make -C pvxs -j
   make -C pvxs-cms -j

The programmer reference has the detailed build variants and link rules:
:doc:`/programmers-ref/building`.

Start PVACMS
------------

PVACMS can create its own initial root certificate, administrator
certificate, server certificate, database, and access security file on
first start:

.. code-block:: shell

   export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
   export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
   pvacms -v

Common files created on first start are:

.. list-table::
   :header-rows: 1

   * - File
     - Purpose
   * - ``$XDG_CONFIG_HOME/pva/1.4/cert_auth.p12``
     - PVACMS root certificate authority keychain.
   * - ``$XDG_CONFIG_HOME/pva/1.4/pvacms.p12``
     - PVACMS server keychain.
   * - ``$XDG_CONFIG_HOME/pva/1.4/admin.p12``
     - Initial administrator client keychain.
   * - ``$XDG_CONFIG_HOME/pva/1.4/pvacms.acf``
     - PVACMS access security file.
   * - ``$XDG_DATA_HOME/pva/1.4/certs.db``
     - Certificate database.

See :doc:`pvacms` for full PVACMS configuration, clustering, backup,
health, and audit options.

Create certificates
-------------------

Use the authenticator that matches your site:

.. code-block:: shell

   # Standard authenticator, usually requires administrator approval.
   authnstd -u client
   authnstd -u server
   authnstd -u ioc

   # Kerberos or LDAP sites use their matching tools.
   authnkrb -u client
   authnldap -u client

The resulting keychain is normally written under
``$XDG_CONFIG_HOME/pva/1.4/``. Client tools use ``client.p12`` by default;
servers use ``server.p12`` by default. Use ``pvxcert`` to inspect,
approve, revoke, renew, or query certificate status. See :doc:`cli`.

Configure clients
-----------------

For command-line clients such as ``pvxget``, ``pvxput``, ``pvxinfo``, and
``pvxcall``:

.. code-block:: shell

   export EPICS_PVA_TLS_KEYCHAIN=$HOME/.config/pva/1.4/client.p12
   export EPICS_PVA_ADDR_LIST="pvacms-host ioc-host"
   export EPICS_PVA_AUTO_ADDR_LIST=NO

Then use the normal PVAccess commands:

.. code-block:: shell

   pvxinfo test:spec
   pvxget test:spec
   pvxput test:spec 1

Configure IOCs and servers
--------------------------

For an IOC or server process:

.. code-block:: shell

   export EPICS_PVAS_TLS_KEYCHAIN=/path/to/server.p12
   export EPICS_PVAS_TLS_OPTIONS="client_cert=require on_expiration=standby"
   export EPICS_PVA_ADDR_LIST="pvacms-host"
   export EPICS_PVA_AUTO_ADDR_LIST=NO

``client_cert=require`` is the normal mutually-authenticated setting.
``on_expiration=standby`` keeps the process alive but stops secure service
until a usable certificate is available. Use ``fallback-to-tcp`` only
where plain PVAccess fallback is an intentional compatibility choice.

Run through a gateway
---------------------

The Secure PVA Gateway bridges networks while preserving identity-based
access control. Use it when clients outside the controls network need
controlled access to internal process variables. The gateway needs its
own certificate, upstream address-list configuration, downstream listener
configuration, and access security rules. The full deployment walkthrough
is :doc:`spvaqsgw`.

Routine checks
--------------

Useful operator checks are:

.. code-block:: shell

   pvxcert -f ~/.config/pva/1.4/client.p12
   pvxcert <certificate-id>
   pvxinfo -v test:spec

Use PVACMS health and metrics process variables for service monitoring,
and keep a backup of the PVACMS database and certificate authority
keychain. Losing the certificate authority keychain means existing trust
relationships cannot be recreated from the database alone.
