.. _cli_tools:

|cli| Command Line Tools
=========================

SPVA provides two command line tools for certificate management and performance benchmarking.

.. _pvxcert:

|terminal| pvxcert — Certificate Management
--------------------------------------------

``pvxcert`` is a certificate management utility for querying certificate status and performing
administrative operations such as approving, denying, or revoking certificates managed by :ref:`pvacms`.

Usage
^^^^^

.. code-block:: text

   pvxcert [options] <cert_id>                          Get certificate status
   pvxcert [file_options] [options] -f <cert_file>      Get certificate info from file
   pvxcert [options] -A <cert_id>                       Approve pending request (admin)
   pvxcert [options] -D <cert_id>                       Deny pending request (admin)
   pvxcert [options] -R <cert_id>                       Revoke certificate (admin)
   pvxcert -h                                           Show help
   pvxcert -V                                           Print version

Certificate ID Format
^^^^^^^^^^^^^^^^^^^^^

Certificates are identified by a compound ``<issuer>:<serial>`` string:

- ``<issuer>`` — first 8 hex digits of the issuer's Subject Key Identifier
- ``<serial>`` — certificate serial number

For example::

   27975e6b:7246297371190731775

This ID is displayed when certificates are created or can be found in the certificate details
of PKCS#12 keychain files.

Options
^^^^^^^

.. list-table::
   :widths: 30 70
   :header-rows: 1

   * - Option
     - Description
   * - ``<cert_id>``
     - Certificate identifier in ``<issuer>:<serial>`` format
   * - ``-f``, ``--file`` ``<cert_file>``
     - Read certificate information from a PKCS#12 keychain file
   * - ``-p``, ``--password``
     - Prompt for keychain file password (use with ``-f``)
   * - ``-A``, ``--approve`` ``<cert_id>``
     - Approve a pending certificate request (**admin only**)
   * - ``-D``, ``--deny`` ``<cert_id>``
     - Deny a pending certificate request (**admin only**)
   * - ``-R``, ``--revoke`` ``<cert_id>``
     - Revoke an active certificate (**admin only**)
   * - ``-w``, ``--timeout`` ``<seconds>``
     - Operation timeout in seconds (default: 5.0)
   * - ``-d``, ``--debug``
     - Enable debug logging (sets ``PVXS_LOG="pvxs.*=DEBUG"``)
   * - ``-v``, ``--verbose``
     - Enable verbose output
   * - ``-h``, ``--help``
     - Show help message
   * - ``-V``, ``--version``
     - Print version information

Examples
^^^^^^^^

**Check certificate status:**

.. code-block:: shell

   # Query status by certificate ID
   pvxcert 27975e6b:7246297371190731775

   # Query status from a keychain file
   pvxcert -f ~/.config/pva/1.5/client.p12

   # Query a password-protected keychain file
   pvxcert -p -f /path/to/server.p12

**Administrative operations:**

.. code-block:: shell

   # Approve a pending certificate request
   pvxcert -A 27975e6b:7246297371190731775

   # Deny a pending certificate request
   pvxcert -D 27975e6b:7246297371190731775

   # Revoke an active certificate
   pvxcert -R 27975e6b:7246297371190731775

.. note::

   Administrative operations (approve, deny, revoke) require appropriate access
   control permissions configured in the :ref:`pvacms` ACF.

Under the hood, ``pvxcert`` sends a ``PUT`` to the :ref:`pvacms` on the PV associated with the certificate:

.. code-block:: console

    Structure
        string     state    # APPROVE, DENY, REVOKE

.. _pvxperf:

|terminal| pvxperf — Performance Benchmarking
----------------------------------------------

``pvxperf`` is a self-contained performance benchmarking tool that measures monitor subscription
throughput (updates/second) across four protocol modes. It runs server and client in-process
to eliminate network variability, producing repeatable measurements on the same hardware.

Protocol Modes
^^^^^^^^^^^^^^

.. list-table::
   :widths: 20 50 15 15
   :header-rows: 1

   * - Mode
     - Description
     - TLS
     - CMS
   * - ``ca``
     - Channel Access (embedded IOC)
     - No
     - No
   * - ``pva``
     - PVAccess without TLS
     - No
     - No
   * - ``spva``
     - Secure PVAccess with TLS, no certificate monitoring
     - Yes
     - No
   * - ``spva_certmon``
     - Secure PVAccess with TLS and real PVACMS certificate monitoring
     - Yes
     - Yes

Usage
^^^^^

.. code-block:: text

   pvxperf [options]           Run benchmarks
   pvxperf -h                  Show help
   pvxperf -V                  Print version

Benchmark Options
^^^^^^^^^^^^^^^^^

.. list-table::
   :widths: 35 65
   :header-rows: 1

   * - Option
     - Description
   * - ``--duration`` ``<seconds>``
     - Measurement duration per data point (default: 5)
   * - ``--warmup`` ``<count>``
     - Warm-up updates before measurement begins (default: 100)
   * - ``--subscriptions`` ``<list>``
     - Comma-separated subscriber counts to sweep (default: ``1,10,100,500,1000``)
   * - ``--sizes`` ``<list>``
     - Comma-separated payload sizes in bytes (default: ``1,10,100,1000,10000,100000``)
   * - ``--modes`` ``<list>``
     - Comma-separated protocol modes to run (default: ``ca,pva,spva,spva_certmon``)
   * - ``--nt-payload``
     - Use NT types for PVA payload (adds metadata overhead)
   * - ``--output`` ``<file>``
     - CSV output file (default: stdout)

TLS / CMS Options
^^^^^^^^^^^^^^^^^

.. list-table::
   :widths: 35 65
   :header-rows: 1

   * - Option
     - Description
   * - ``--keychain`` ``<path>``
     - TLS keychain file for SPVA modes
   * - ``--setup-cms``
     - Auto-bootstrap PVACMS with temporary certificates (see :ref:`cms_bootstrap`)
   * - ``--external-cms``
     - Use an already-running PVACMS instance (skip child-process launch)
   * - ``--cms-db`` ``<path>``
     - Path to existing PVACMS SQLite database
   * - ``--cms-keychain`` ``<path>``
     - Path to existing PVACMS server keychain
   * - ``--cms-acf`` ``<path>``
     - Path to existing PVACMS ACF file

General Options
^^^^^^^^^^^^^^^

.. list-table::
   :widths: 35 65
   :header-rows: 1

   * - Option
     - Description
   * - ``-d``, ``--debug``
     - Enable PVXS debug logging
   * - ``-v``, ``--verbose``
     - Enable verbose output
   * - ``-h``, ``--help``
     - Show help message
   * - ``-V``, ``--version``
     - Print version information

Examples
^^^^^^^^

**Basic benchmark with auto-bootstrapped CMS:**

.. code-block:: shell

   # Run all modes with auto-bootstrapped PVACMS and temp certificates
   pvxperf --setup-cms

**Benchmark specific modes and payload sizes:**

.. code-block:: shell

   # Compare PVA vs SPVA with specific payload sizes
   pvxperf --modes pva,spva --sizes 100,1000,10000 --keychain /path/to/keychain.p12

**Use an existing PVACMS instance:**

.. code-block:: shell

   # Run with an already-running PVACMS
   pvxperf --external-cms --keychain /path/to/keychain.p12

**Save results to CSV for analysis:**

.. code-block:: shell

   # Output to file with extended duration for stable measurements
   pvxperf --setup-cms --duration 10 --output results.csv

.. _cms_bootstrap:

CMS Bootstrap (``--setup-cms``)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The ``--setup-cms`` option provides zero-configuration PVACMS bootstrapping for benchmarking.
It creates a fully isolated temporary environment so it will not interfere with any existing
PVACMS installation on the machine:

1. Creates a temporary directory for all CMS state
2. Launches a real ``pvacms`` child process with auto-certificate-approval enabled
3. Provisions server and client keychains via ``authnstd``
4. Runs the benchmarks
5. Cleans up the PVACMS process and temporary directory on exit

This is the recommended way to run ``spva_certmon`` benchmarks without manual CMS setup.

Alternatively, use ``--external-cms`` to point at an already-running PVACMS, or provide
explicit paths with ``--cms-db``, ``--cms-keychain``, and ``--cms-acf``.

.. _benchmark_methodology:

Measurement Methodology
^^^^^^^^^^^^^^^^^^^^^^^

``pvxperf`` uses monitor subscriptions with counter-based integrity checking:

1. **Server** posts updates as fast as possible, each containing a monotonic counter and timestamp
2. **Clients** subscribe with pipelining enabled (``pipeline=true``, ``queueSize=4``)
3. **Warm-up phase** establishes connections, TLS handshakes, and certificate monitoring subscriptions
4. **Measurement phase** runs for the configured duration, verifying counter sequences to detect drops
5. **Drop detection** — any gap in the counter sequence indicates the server squashed an update
   because a subscriber's queue was full

For each combination of protocol mode, payload size, and subscriber count, ``pvxperf`` reports
throughput (updates/second), total updates, drops, and errors.

CSV Output Schema
^^^^^^^^^^^^^^^^^

.. code-block:: text

   protocol,payload_mode,subscribers,payload_bytes,updates_per_second,per_sub_updates_per_second,total_updates,drops,errors,duration_seconds

- ``protocol`` — ``CA``, ``PVA``, ``SPVA``, or ``SPVA_CERTMON``
- ``drops`` — counter-sequence gaps (squashed updates); filter to ``drops == 0`` for clean throughput
- ``per_sub_updates_per_second`` — per-subscriber throughput for fan-out analysis

The CSV can be processed with standard tools (Python/matplotlib, R, Excel) to produce
throughput comparison charts across protocol modes.

.. warning::

   Run ``pvxperf`` on a network with no other active PVACMS to avoid interference
   with benchmark results. The ``--setup-cms`` option isolates CMS traffic to loopback
   but other PVACMS instances on the broadcast domain could still be discovered.
