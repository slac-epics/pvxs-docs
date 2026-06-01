.. _programmers_building:

Building Libraries and Executables
==================================

This page is the programmer path through the build. It assumes you are
building code that links against pvxs, pvxs-cms, or both — for example,
if you are:

* building and deploying IOCs in your production network;
* writing a client service or data-pipeline tool that uses pvxs directly;
* embedding pvxs in a device driver or support module;
* building a custom authenticator plugin against pvxs-cms; or
* building the Python (P4P) or Java (Phoebus) bindings from source.

If you only need to install and run the existing SPVA tools as an operator
— configuring PVACMS, issuing certificates, running IOCs — use the
:doc:`/user-manual/spvaqstart` quick start instead.

Build order
-----------

Build the repositories in dependency order:

1. ``epics-base`` — provides EPICS Base libraries and the EPICS make
   system.
2. ``pvxs`` — provides the C++ PVAccess client/server library,
   ``pvxsIoc``, and command-line tools such as ``pvxget`` and
   ``softIocPVX``.
3. ``pvxs-cms`` — provides PVACMS, ``pvxcert``, ``pvaperf``, and the
   authenticator executables.
4. ``p4p`` is optional. It builds Python bindings over pvxs and provides
   the ``pvagw`` PVAccess Gateway executable.
5. Phoebus / CS-Studio is optional and independent. It does not link to
   pvxs; it implements PVAccess and Secure PVAccess in Java under
   ``core/pva`` and interoperates over the wire.

Which source branch or tag to use
---------------------------------

Use matching SPVA branches or release tags across the repositories. The
stable branch choices are:

.. list-table::
   :header-rows: 1

   * - Repository
     - Stable branch
     - Development or feature branch
     - Snapshot tag pattern
   * - ``epics-base``
     - ``7.0-secure-pvaccess``
     - ``7.0-secure-pvaccess``
     - ``epics-base-<version>-spva.<yyyymmdd>``
   * - ``pvxs-tls`` cloned as ``pvxs``
     - ``main``
     - ``dev``
     - ``pvxs-<version>-spva.<yyyymmdd>``
   * - ``pvxs-cms``
     - ``main``
     - ``dev``
     - ``pvxs-cms-<version>-spva.<yyyymmdd>``
   * - ``p4p-tls`` cloned as ``p4p``
     - ``master``
     - ``feature/acf-grammar-7.0.10`` for advanced SPVA access-security grammar
     - ``p4p-<version>-spva.<yyyymmdd>``
   * - ``phoebus``
     - ``master``
     - ``master``; Secure PVAccess changes are already integrated
     - use the branch

The ``main`` branch of ``pvxs-tls`` (renamed from ``tls`` on 2026-05) and
the ``main`` branch of ``pvxs-cms`` are the stable release branches. The
``dev`` branches contain
the latest development work, including experimental features.

For ``p4p-tls``, the ``master`` branch works with whichever pvxs checkout
you build and link against. Use ``feature/acf-grammar-7.0.10`` when you
need the advanced Secure PVAccess access-security grammar, including
``METHOD``, ``PROTOCOL``, ``AUTHORITY``, and related fields. Phoebus has
the relevant Secure PVAccess changes integrated into ``master``.

Snapshot tags are the recommended starting point for production builds and
new deployments. Each snapshot is an immutable, named point in the release
history. Using a snapshot means your build is reproducible, and if you
report a problem the maintainers can identify the exact code you were
running from the tag name alone.

The tag grammar is:

.. code-block:: text

   <project-name>-<project-version>-spva.<yyyymmdd>

where:

* ``<project-name>`` is ``epics-base``, ``pvxs``, ``pvxs-cms``, or
  ``p4p``;
* ``<project-version>`` is the project version captured by the snapshot,
  such as ``1.4.1`` or ``1.4.0``;
* ``spva`` marks the tag as a Secure PVAccess snapshot;
* ``<yyyymmdd>`` is the snapshot date.

For example, ``pvxs-1.4.1-spva.20260423`` means: project ``pvxs``, pvxs
version ``1.4.1``, SPVA snapshot, dated ``2026-04-23``.
``pvxs-cms-1.4.0-spva.20260423`` means: project ``pvxs-cms``, pvxs-cms
version ``1.4.0``, SPVA snapshot, dated ``2026-04-23``.

Always keep all repositories on tags from the same snapshot date.  Do not
mix a snapshot tag in one repository with a moving branch in another; the
repositories are co-versioned and a mismatch can produce subtle build
failures or wire-protocol incompatibilities.

**Recommended: snapshot tag checkout.** Replace the example tags with the
current release tags published on the project's GitHub releases page:

.. code-block:: shell

   git clone --branch 7.0-secure-pvaccess https://github.com/slac-epics/epics-base-tls.git epics-base
   git clone --branch pvxs-1.4.1-spva.20260423 https://github.com/slac-epics/pvxs-tls.git pvxs
   git clone --branch pvxs-cms-1.4.0-spva.20260423 https://github.com/slac-epics/pvxs-cms.git pvxs-cms
   git clone --branch master https://github.com/slac-epics/p4p-tls.git p4p
   git clone --branch master https://github.com/ControlSystemStudio/phoebus.git phoebus

**Tracking the stable branch** (latest tagged release, plus any patches
applied since): use this when you want to follow the release line closely
and can tolerate occasional source changes between builds.

.. code-block:: shell

   git clone --branch 7.0-secure-pvaccess https://github.com/slac-epics/epics-base-tls.git epics-base
   git clone --branch main https://github.com/slac-epics/pvxs-tls.git pvxs
   git clone --branch main https://github.com/slac-epics/pvxs-cms.git pvxs-cms
   git clone --branch master https://github.com/slac-epics/p4p-tls.git p4p
   git clone --branch master https://github.com/ControlSystemStudio/phoebus.git phoebus

**Latest development checkout** (experimental features, may be unstable):
use only when you need a feature that has not yet appeared in a snapshot.

.. code-block:: shell

   git clone --branch 7.0-secure-pvaccess https://github.com/slac-epics/epics-base-tls.git epics-base
   git clone --branch dev https://github.com/slac-epics/pvxs-tls.git pvxs
   git clone --branch dev https://github.com/slac-epics/pvxs-cms.git pvxs-cms
   git clone --branch feature/acf-grammar-7.0.10 https://github.com/slac-epics/p4p-tls.git p4p
   git clone --branch master https://github.com/ControlSystemStudio/phoebus.git phoebus

Always clone ``pvxs-tls`` into a directory named ``pvxs`` and ``p4p-tls``
into a directory named ``p4p``. The build examples, ``RELEASE.local``
snippets, and documentation paths assume those directory names.

There are two normal EPICS GNU make layouts for these repositories:

* a **sibling build**, where ``epics-base``, ``pvxs``, and optionally
  ``pvxs-cms`` are separate checkouts under one project root;
* an **EPICS Base module build**, where ``pvxs`` and optionally
  ``pvxs-cms`` are checked out under ``epics-base/modules`` and are built
  by Base's module rules.

The builds below use EPICS GNU make.

Sibling build
-------------

A sibling build keeps all repositories next to each other under a project
root. The local ``RELEASE.local`` and ``CONFIG_SITE.local`` files live at
that project root and are included by the sibling modules.

.. code-block:: shell

   mkdir spva-work
   cd spva-work

   git clone --branch 7.0-secure-pvaccess https://github.com/slac-epics/epics-base-tls.git epics-base

   # Clone the pvxs TLS fork into a directory named "pvxs" so the build
   # paths match the EPICS RELEASE examples and the rest of this manual.
   git clone --branch main https://github.com/slac-epics/pvxs-tls.git pvxs

   git clone --branch main https://github.com/slac-epics/pvxs-cms.git pvxs-cms

In this layout, the project-root release file is usually:

.. code-block:: make

   # spva-work/RELEASE.local, included by pvxs and pvxs-cms
   EPICS_BASE = $(TOP)/../epics-base
   PVXS       = $(TOP)/../pvxs

``PVXS`` is only needed by repositories that link to pvxs, such as
``pvxs-cms`` and application modules. ``epics-base`` itself does not use
that variable.

Put sibling-build feature macros in the project-root
``CONFIG_SITE.local``:

.. code-block:: make

   # spva-work/CONFIG_SITE.local
   EVENT2_HAS_OPENSSL = YES
   PVXS_ENABLE_PVACMS = YES
   PVXS_ENABLE_KRB_AUTH = YES
   PVXS_ENABLE_LDAP_AUTH = YES
   PVXS_ENABLE_SSLKEYLOGFILE = YES

Then build in dependency order:

.. code-block:: shell

   make -C epics-base -j

   # Optional when your system does not provide a suitable libevent.
   make -C pvxs/bundle libevent

   make -C pvxs -j
   make -C pvxs-cms -j

The installed outputs are under each repository: for example
``epics-base/bin``, ``epics-base/lib``, ``epics-base/include``,
``pvxs/bin``, ``pvxs/lib``, ``pvxs/include``, and the corresponding
``pvxs-cms`` directories.

EPICS Base module build
-----------------------

A module build starts with a clone of ``epics-base``. Then clone ``pvxs``
and optionally ``pvxs-cms`` inside ``epics-base/modules``. Base's
``modules/Makefile`` builds ``libcom``, ``ca``, ``database``, and the
bundled submodules, then includes ``modules/Makefile.local`` immediately
before ``RULES_MODULES`` so sites can add more modules.

.. code-block:: shell

   git clone --branch 7.0-secure-pvaccess https://github.com/slac-epics/epics-base-tls.git epics-base
   cd epics-base/modules

   # Clone the pvxs TLS fork into a directory named "pvxs" for consistency
   # with RELEASE paths, installed names, and the rest of this manual.
   git clone --branch main https://github.com/slac-epics/pvxs-tls.git pvxs

   git clone --branch main https://github.com/slac-epics/pvxs-cms.git pvxs-cms

   cd ../..

For pvxs alone, create ``epics-base/modules/Makefile.local`` with:

.. code-block:: make

   SUBMODULES += pvxs
   pvxs_DEPEND_DIRS = database

To include PVACMS in the same module build, make ``pvxs-cms`` another
Base module that depends on pvxs:

.. code-block:: make

   SUBMODULES += pvxs
   pvxs_DEPEND_DIRS = database

   SUBMODULES += pvxs-cms
   pvxs-cms_DEPEND_DIRS = pvxs

Put module-build feature macros in
``epics-base/configure/CONFIG_SITE.local``:

.. code-block:: make

   # epics-base/configure/CONFIG_SITE.local
   EVENT2_HAS_OPENSSL = YES
   PVXS_ENABLE_PVACMS = YES
   PVXS_ENABLE_KRB_AUTH = YES
   PVXS_ENABLE_LDAP_AUTH = YES
   PVXS_ENABLE_SSLKEYLOGFILE = YES

Then build Base; Base drives the module dependency graph:

.. code-block:: shell

   make -C epics-base -j

The installed outputs are under the Base tree: ``epics-base/bin``,
``epics-base/lib``, ``epics-base/include``, ``epics-base/dbd``, and so
on. pvxs and pvxs-cms do not install into separate top-level output trees
in this layout.

Where build macros go
---------------------

The important build switches are site settings, not source edits. The
usual locations are:

* ``spva-work/CONFIG_SITE.local`` for sibling builds, next to
  ``RELEASE.local``;
* ``epics-base/configure/CONFIG_SITE.local`` for module builds driven by
  Base;
* the make command line for temporary one-off builds.

For either layout, the common SPVA-related feature macros are:

.. code-block:: make

   EVENT2_HAS_OPENSSL = YES
   PVXS_ENABLE_PVACMS = YES
   PVXS_ENABLE_KRB_AUTH = YES
   PVXS_ENABLE_LDAP_AUTH = YES
   PVXS_ENABLE_SSLKEYLOGFILE = YES

``EVENT2_HAS_OPENSSL`` is normally detected automatically from the
libevent build. Set ``EVENT2_HAS_OPENSSL=YES`` only when you need to
override detection and force the OpenSSL-backed SPVA paths in pvxs.
Detection or override does not build libevent; it only controls whether
pvxs compiles and links the OpenSSL-backed source files once libevent is
available.
``PVXS_ENABLE_PVACMS=YES`` builds the PVACMS server and related
certificate-management code in pvxs-cms. Kerberos and LDAP authenticators
are optional because they add site-library dependencies.

The tracked defaults live in each module's ``configure/CONFIG_SITE``.
pvxs defines ``PVXS_ENABLE_SSLKEYLOGFILE`` there. pvxs-cms defines
``PVXS_ENABLE_PVACMS``, ``PVXS_ENABLE_KRB_AUTH``, and
``PVXS_ENABLE_LDAP_AUTH`` there; the PVACMS default is ``YES`` for host
builds and ``NO`` for cross builds.

Windows builds
--------------

Windows builds use EPICS GNU make from a Windows command prompt with a
compiler environment. The commands below are a manual native Visual
Studio build.

Install these tools first:

* Git for Windows;
* Visual Studio 2022 with the Desktop development with C++ workload;
* Strawberry Perl, with ``perl.exe`` on ``PATH``;
* GNU make on ``PATH`` as ``make.exe``; substitute ``gmake`` or
  ``gnumake`` in the commands below if that is how it is installed;
* vcpkg, used here to install libevent and OpenSSL.

The examples use a sibling checkout layout under ``C:\spva-work``.

Clone the sources and install dependencies:

.. code-block:: bat

   mkdir C:\spva-work
   cd /d C:\spva-work

   git clone --branch 7.0-secure-pvaccess https://github.com/slac-epics/epics-base-tls.git epics-base
   git clone --branch main https://github.com/slac-epics/pvxs-tls.git pvxs
   git clone --branch main https://github.com/slac-epics/pvxs-cms.git pvxs-cms

   git clone https://github.com/microsoft/vcpkg.git C:\vcpkg
   cd /d C:\vcpkg
   bootstrap-vcpkg.bat
   vcpkg install "libevent[openssl]" openssl

Set the build environment. Run this in a normal ``cmd.exe`` window, or in
a Visual Studio x64 developer command prompt and skip the ``vcvarsall``
line. EPICS Base also provides ``startup\windows.bat`` as an example, but
it contains site-specific paths and may need local editing.

.. code-block:: bat

   cd /d C:\spva-work
   call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x64
   set EPICS_HOST_ARCH=windows-x64

   set LIBEVENT=C:\vcpkg\installed\x64-windows
   set OPENSSL=C:\vcpkg\installed\x64-windows
   set PATH=%PATH%;C:\vcpkg\installed\x64-windows\bin

Create the sibling release file:

.. code-block:: bat

   cd /d C:\spva-work
   > RELEASE.local echo EPICS_BASE=$(TOP)/../epics-base
   >> RELEASE.local echo PVXS=$(TOP)/../pvxs

Create the sibling build-configuration file. PVACMS itself is not
supported on Windows, so ``pvxs-cms`` must be built with PVACMS, Kerberos,
and LDAP support disabled:

.. code-block:: bat

   > CONFIG_SITE.local echo EVENT2_HAS_OPENSSL = YES
   >> CONFIG_SITE.local echo LIBEVENT = C:/vcpkg/installed/x64-windows
   >> CONFIG_SITE.local echo OPENSSL = C:/vcpkg/installed/x64-windows
   >> CONFIG_SITE.local echo PVXS_ENABLE_SSLKEYLOGFILE = YES
   >> CONFIG_SITE.local echo PVXS_ENABLE_PVACMS = NO
   >> CONFIG_SITE.local echo PVXS_ENABLE_KRB_AUTH = NO
   >> CONFIG_SITE.local echo PVXS_ENABLE_LDAP_AUTH = NO
   >> CONFIG_SITE.local echo USR_CXXFLAGS_WIN32 += /std:c++20
   >> CONFIG_SITE.local echo USR_CPPFLAGS_WIN32 += -DWIN32_LEAN_AND_MEAN

Build in dependency order with GNU make. Because this example uses vcpkg
for libevent and OpenSSL, do not also build pvxs' bundled libevent.

.. code-block:: bat

   cd /d C:\spva-work\epics-base
   make

   cd /d C:\spva-work\pvxs
   make

   cd /d C:\spva-work\pvxs-cms
   make

The installed outputs are under each checkout, using the Windows host
architecture directory. For example:

.. code-block:: text

   C:\spva-work\epics-base\bin\windows-x64
   C:\spva-work\epics-base\lib\windows-x64
   C:\spva-work\pvxs\bin\windows-x64
   C:\spva-work\pvxs\lib\windows-x64
   C:\spva-work\pvxs-cms\bin\windows-x64
   C:\spva-work\pvxs-cms\lib\windows-x64

Use ``make runtests`` in ``pvxs`` to run the pvxs tests. Full PVACMS
server tests require the unsupported PVACMS server and should be run on a
Unix-like host. For a debug build, set ``EPICS_HOST_ARCH=windows-x64-debug``
before building, or pass it on the GNU make command line.

If you do not want to use vcpkg's libevent, build pvxs' bundled libevent
instead and leave ``LIBEVENT`` unset:

.. code-block:: bat

   cd /d C:\spva-work\pvxs
   make -C bundle libevent
   make

Keep ``OPENSSL`` set if OpenSSL is installed outside the compiler's
default include and library search paths.

p4p — Python bindings
---------------------

``p4p`` is the Python binding layer over pvxs. It exposes the full PVAccess
client and server API from Python, and also builds the ``pvagw`` gateway
executable. Because it wraps the C++ pvxs library, it inherits SPVA
capabilities — TLS, certificate-status monitoring, the same
environment-variable configuration — from the pvxs it is built against.

**PyPI package:** ``p4p`` — published at https://pypi.org/project/p4p/.

.. warning::

   The wheels published on PyPI are built against the **upstream pvxs
   library** (``slac-epics/pvxs``, plain PVAccess), not the SPVA fork
   (``slac-epics/pvxs-tls``). Installing ``pip install p4p`` gives you a
   working PVAccess client and server, but **none of the SPVA features are
   present**: no TLS, no certificate-status monitoring, no
   ``EPICS_PVA_TLS_KEYCHAIN`` support.

   To use SPVA features from Python you must build p4p from source against
   the SPVA pvxs checkout, as described in the source build section below.

The PyPI wheel is useful for environments where plain PVAccess is sufficient
and you do not need TLS or certificate management:

.. code-block:: shell

   python3 -m venv p4p-plain
   . p4p-plain/bin/activate
   pip install -U pip
   pip install p4p

To verify:

.. code-block:: shell

   pip install nose2
   python -m nose2 p4p

**For SPVA features**, skip the PyPI wheel and use the source build below
against the SPVA ``pvxs`` checkout instead.

For a source build against the sibling ``epics-base`` and ``pvxs`` trees,
install the Python build prerequisites first:

.. code-block:: shell

   # Debian / Ubuntu package names used by the Kubernetes gateway image.
   sudo apt-get install python3-dev python3-numpy python3-nose2 \
       python-is-python3 python3-ply cython3

   # Or use Python packages when system packages are not available.
   python3 -m pip install numpy nose2 Cython ply

Clone and build ``p4p`` as an EPICS module:

.. code-block:: shell

   cd spva-work
   git clone --branch master https://github.com/slac-epics/p4p-tls.git p4p

   cat > p4p/configure/RELEASE.local <<EOF
   PVXS       = \$(TOP)/../pvxs
   EPICS_BASE = \$(TOP)/../epics-base
   EOF

   make -C p4p distclean || true
   make -C p4p -j

If you need to choose a specific Python interpreter, pass ``PYTHON`` on
every make invocation except ``distclean``:

.. code-block:: shell

   make -C p4p PYTHON=/usr/bin/python3 -j

The gateway executable installs under ``p4p/bin/<host-arch>/pvagw``. For
example:

.. code-block:: shell

   EPICS_HOST_ARCH=$(epics-base/startup/EpicsHostArch)
   export PATH="$PWD/pvxs/bin/$EPICS_HOST_ARCH:$PATH"
   export PATH="$PWD/pvxs-cms/bin/$EPICS_HOST_ARCH:$PATH"
   export PATH="$PWD/p4p/bin/$EPICS_HOST_ARCH:$PATH"

Generate an example gateway configuration and run the gateway:

.. code-block:: shell

   pvagw --example-config gateway.conf
   pvagw gateway.conf

For a systemd-managed Linux gateway:

.. code-block:: shell

   sudo python -m p4p.gw --example-config /etc/pvagw/mygw.conf
   sudo python -m p4p.gw --example-systemd /etc/systemd/system/pvagw@.service
   sudo systemctl daemon-reload
   sudo systemctl start pvagw@mygw.service

For Secure PVAccess, the gateway uses an IOC certificate — a single
PKCS#12 file that carries both client and server key usage, allowing the
gateway to connect upstream as a TLS client and serve downstream clients
as a TLS server.  TLS is configured in the gateway JSON configuration
file via ``tls_keychain`` in each ``clients`` and ``servers`` block; do
not use environment variables for this:

.. code-block:: json

   {
     "version": 2,
     "clients": [
       {
         "name": "upstream",
         "addrlist": "ioc-host",
         "autoaddrlist": false,
         "tls_keychain": "/home/gateway/.config/pva/1.5/gateway.p12"
       }
     ],
     "servers": [
       {
         "name": "downstream",
         "clients": ["upstream"],
         "tls_keychain": "/home/gateway/.config/pva/1.5/gateway.p12"
       }
     ]
   }

Obtain an IOC certificate for the gateway using ``authnstd -u ioc`` (or
the appropriate authenticator for your site).  The same keychain file is
referenced in both ``clients`` and ``servers`` blocks.  The path in
``tls_keychain`` is resolved relative to the directory containing the
``gateway.conf`` file.

The Kubernetes gateway image uses the same build shape: install Python
development packages, copy the ``p4p`` source, run ``make distclean`` and
``make``, then run ``/opt/epics/p4p/bin/<host-arch>/pvagw
/home/gateway/gateway.conf``.

Phoebus / CS-Studio — Java PVA
--------------------------------

Phoebus (also known as CS-Studio) contains an independent Java implementation
of PVAccess and Secure PVAccess under ``core/pva``. It does not depend on
the C++ pvxs, p4p, epics-base, or pvxs-cms libraries at build time — it
speaks the same wire protocol but is implemented entirely in Java.

**Maven Central coordinates:**

.. code-block:: xml

   <dependency>
       <groupId>org.phoebus</groupId>
       <artifactId>core-pva</artifactId>
       <version><!-- see https://central.sonatype.com/artifact/org.phoebus/core-pva --></version>
   </dependency>

Phoebus releases are published to Maven Central via Sonatype.  Check the
Maven Central search for the latest stable version.  The artifact carries
BouncyCastle (``bcpkix-jdk18on``, ``bcprov-jdk18on``) as a transitive
dependency, which is used for OCSP certificate-status checking.

If you only need the ``core-pva`` Java PVA library (without the full Phoebus
display-builder application), add the above dependency to your project's
``pom.xml`` and use the API shown in :doc:`applications`.

Building from source
~~~~~~~~~~~~~~~~~~~~

Install Java and Maven first:

* Java Development Kit 17 or later.
* Maven 3.x.

To use the ``core-pva`` library independently of the full Phoebus product,
build just that module:

.. code-block:: shell

   git clone --branch master https://github.com/ControlSystemStudio/phoebus.git phoebus

   # Build only core-pva and its dependencies:
   mvn install -f phoebus/pom.xml -pl core/pva -am -DskipTests

The resulting jar installs to your local Maven cache at:
``~/.m2/repository/org/phoebus/core-pva/<version>/core-pva-<version>.jar``

To build the full Phoebus product (display-builder application):

.. code-block:: shell

   cd phoebus
   mvn clean verify -f dependencies/pom.xml
   mvn clean install -DskipTests

   cd phoebus-product/target
   java -jar product-*-SNAPSHOT.jar

To exercise the Java PVAccess client from the command line without the
display-builder UI, use ``PVAClientMain``:

.. code-block:: shell

   java -cp '/opt/phoebus/lib/*' org.epics.pva.client.PVAClientMain \
       monitor -r 'field()' test:aiExample

For Secure PVAccess, set the same environment variables used by C++ clients:

.. code-block:: shell

   export EPICS_PVA_TLS_KEYCHAIN=$HOME/.config/pva/1.5/client.p12
   export EPICS_PVA_ADDR_LIST="pvacms-host ioc-host"
   export EPICS_PVA_AUTO_ADDR_LIST=NO

   java -cp '/opt/phoebus/lib/*' org.epics.pva.client.PVAClientMain \
       get MY:PV

Phoebus reads ``EPICS_PVA_TLS_KEYCHAIN`` and ``EPICS_PVAS_TLS_KEYCHAIN``
(or the equivalent Java system properties ``-DEPICS_PVA_TLS_KEYCHAIN=...``)
directly in its Java PVAccess implementation. It does not load the C++ pvxs
library.

.. note::

   Java system properties take precedence over environment variables in
   Phoebus: ``-DEPICS_PVA_TLS_KEYCHAIN=/path/to/client.p12`` overrides the
   shell environment variable of the same name.

Standalone executables
----------------------

For a host executable that links pvxs but is not an IOC, add ``PVXS`` and
``EPICS_BASE`` to your application's ``configure/RELEASE.local`` and link
with ``pvxs`` plus ``Com``:

.. code-block:: make

   # configure/RELEASE.local
   PVXS       = /path/to/pvxs
   EPICS_BASE = /path/to/epics-base

.. code-block:: make

   # src/Makefile
   PROD_HOST += myclient
   myclient_SRCS += myclient.cpp
   myclient_LIBS += pvxs
   myclient_LIBS += Com

The pvxs module installs build fragments under ``cfg/`` so libevent and
other required system libraries are pulled in by the EPICS build. Do not
copy the pvxs internal link line into your application.

IOC executables and support modules
-----------------------------------

For an IOC that uses pvxs server support, link both ``pvxsIoc`` and
``pvxs`` and load the ``pvxsIoc.dbd`` database definition:

.. code-block:: make

   PROD_IOC += myioc
   myioc_SRCS += myioc_registerRecordDeviceDriver.cpp
   myioc_SRCS_DEFAULT += myiocMain.cpp

   myioc_DBD += base.dbd
   myioc_DBD += pvxsIoc.dbd

   myioc_LIBS += pvxsIoc pvxs
   myioc_LIBS += $(EPICS_BASE_IOC_LIBS)

Use ``pvxsIoc`` only for IOC processes. Standalone clients, service
programs, and graphical tools should link ``pvxs`` directly and omit
``pvxsIoc``.

Building examples
-----------------

pvxs ships small example programs under ``pvxs/example``. They are built
as test host products, not installed system tools:

.. code-block:: shell

   make -C pvxs/example -j

Look under ``pvxs/example/O.<host-arch>/`` for example binaries such as
``simplesrv``, ``client``, ``simpleget``, ``rpc_server``, and
``rpc_client``. These examples are the shortest source paths for learning
the pvxs client/server API before adding SPVA-specific configuration.

Validation
----------

After a local build, run the tests at the level you changed:

.. code-block:: shell

   make -C pvxs runtests
   make -C pvxs-cms -C test

When you add, remove, or rename source files in an EPICS module, do a
``make distclean`` before rebuilding. The EPICS dependency files remember
old include paths, and ``make clean`` is not always enough to clear them.
