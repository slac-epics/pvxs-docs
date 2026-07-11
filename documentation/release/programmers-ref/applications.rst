.. _programmers_applications:

Writing IOCs, Servers, and Clients
====================================

This page is a practical cookbook for the most common tasks when writing
EPICS applications and services using pvxs (C++), P4P (Python), or Phoebus
``core-pva`` (Java).

SPVA does not require a different application API for ordinary get, put,
monitor, and RPC operations. You write a client or server in the normal way,
then enable secure transport by providing keychains and TLS configuration
through the process environment or the language binding's configuration
objects (see :doc:`configuration`).

The same TLS environment variables (``EPICS_PVA_TLS_KEYCHAIN``,
``EPICS_PVAS_TLS_KEYCHAIN``, etc.) work across all three implementations.
A PKCS#12 keychain file produced by any of the ``authnxxx`` certificate
tools works unchanged with C++, Python, and Java clients.  For a map of
all available tools and a step-by-step guide to standing up PVACMS and
obtaining certificates, see :doc:`tools` before reading this cookbook.

----

Simple GET
----------

Read the current value of a PV once and return.  The call blocks until the
server replies or the timeout expires.

**C++**

.. code-block:: c++

   #include <iostream>
   #include <pvxs/client.h>
   #include <pvxs/log.h>

   int main() {
       pvxs::logger_config_env();
       auto ctxt = pvxs::client::Context::fromEnv();
       try {
           auto val = ctxt.get("MY:PV").exec()->wait(5.0);
           std::cout << val << "\n";
       } catch (const std::exception& e) {
           std::cerr << "GET failed: " << e.what() << "\n";
           return 1;
       }
   }

**Python (P4P)**

.. code-block:: python

   from p4p.client.thread import Context, RemoteError, TimeoutError

   with Context('pva') as ctxt:
       try:
           val = ctxt.get('MY:PV', timeout=5.0)
           print(val)
       except RemoteError as e:
           print('Server error:', e)
       except TimeoutError:
           print('Timed out')

**Java (Phoebus core-pva)**

.. code-block:: java

   import org.epics.pva.client.*;
   import java.util.concurrent.TimeUnit;

   try (PVAClient client = new PVAClient()) {
       PVAChannel ch = client.getChannel("MY:PV");
       ch.connect().get(5, TimeUnit.SECONDS);
       System.out.println(ch.read("").get(5, TimeUnit.SECONDS));
   }

----

Simple PUT
----------

Write a new value to a PV.  These examples show scalar assignment; structured
PVs (NTScalar, NTArray, etc.) work the same way by specifying a field path.

**C++**

.. code-block:: c++

   #include <pvxs/client.h>

   auto ctxt = pvxs::client::Context::fromEnv();
   try {
       ctxt.put("MY:PV")
           .set("value", 3.14)
           .exec()
           ->wait(5.0);
   } catch (const pvxs::client::RemoteError& e) {
       // Server rejected the PUT (e.g. access denied)
       std::cerr << "PUT rejected: " << e.what() << "\n";
   }

**Python (P4P)**

.. code-block:: python

   from p4p.client.thread import Context, RemoteError

   with Context('pva') as ctxt:
       try:
           ctxt.put('MY:PV', 3.14)
       except RemoteError as e:
           print('PUT rejected by server:', e)

**Java (Phoebus core-pva)**

.. code-block:: java

   import org.epics.pva.client.*;
   import java.util.concurrent.TimeUnit;

   try (PVAClient client = new PVAClient()) {
       PVAChannel ch = client.getChannel("MY:PV");
       ch.connect().get(5, TimeUnit.SECONDS);
       ch.write(false, "value", 3.14).get(5, TimeUnit.SECONDS);
   }

----

Monitoring a PV
---------------

Subscribe to value changes.  The callback fires for every update until the
subscription is cancelled or the channel disconnects.

**C++**

.. code-block:: c++

   #include <iostream>
   #include <csignal>
   #include <pvxs/client.h>
   #include <pvxs/log.h>

   static std::atomic<bool> running{true};

   int main() {
       pvxs::logger_config_env();
       auto ctxt = pvxs::client::Context::fromEnv();

       auto sub = ctxt.monitor("MY:PV")
           .event([](pvxs::client::Subscription& s) {
               try {
                   auto val = s.pop();
                   std::cout << "Update: " << val << "\n";
               } catch (const pvxs::client::Disconnect&) {
                   std::cout << "Disconnected\n";
               } catch (const pvxs::client::Finished&) {
                   running = false;
               } catch (const std::exception& e) {
                   std::cerr << "Error: " << e.what() << "\n";
               }
           })
           .exec();

       std::signal(SIGINT, [](int){ running = false; });
       while (running) epicsThreadSleep(0.1);
   }

**Python (P4P)**

Pass ``notify_disconnect=True`` to receive ``Disconnected`` and
``RemoteError`` in the same callback as normal value updates:

.. code-block:: python

   import time, signal
   from p4p.client.thread import Context, Disconnected, RemoteError

   running = True
   signal.signal(signal.SIGINT, lambda *a: globals().__setitem__('running', False))

   with Context('pva') as ctxt:
       def on_update(v):
           if isinstance(v, Disconnected):
               print('Disconnected')
           elif isinstance(v, RemoteError):
               print('Server error:', v)
           else:
               print('Update:', v)

       sub = ctxt.monitor('MY:PV', on_update, notify_disconnect=True)
       while running:
           time.sleep(0.1)
       sub.close()

Without ``notify_disconnect=True``, ``Disconnected`` events are silently
swallowed and your callback only sees value updates.

**Java (Phoebus core-pva)**

``MonitorListener`` receives ``null`` for all three parameters when the
server ends the subscription normally:

.. code-block:: java

   import org.epics.pva.client.*;
   import java.util.concurrent.CountDownLatch;

   try (PVAClient client = new PVAClient()) {
       CountDownLatch done = new CountDownLatch(1);
       PVAChannel ch = client.getChannel("MY:PV",
           (channel, state) -> {
               System.out.println("State: " + state);
               if (state == ClientChannelState.CLOSED)
                   done.countDown();
           });

       ch.connect().get(5, TimeUnit.SECONDS);
       ch.subscribe("", (channel, changes, overruns, data) -> {
           if (data == null) {
               System.out.println("Subscription ended");
               done.countDown();
           } else {
               System.out.println(channel.getName() + " = " + data);
           }
       });
       done.await();
   }

----

Error handling
--------------

Common failure modes and how to handle them in each language.

**C++ — RemoteError vs Timeout vs Disconnect**

.. code-block:: c++

   #include <pvxs/client.h>

   auto ctxt = pvxs::client::Context::fromEnv();

   try {
       auto val = ctxt.get("MY:PV").exec()->wait(5.0);
   }
   catch (const pvxs::client::RemoteError& e) {
       // Server explicitly rejected the request
       std::cerr << "Server error: " << e.what() << "\n";
   }
   catch (const pvxs::client::Disconnect& e) {
       // Channel disconnected before the reply arrived
       std::cerr << "Disconnected: " << e.what() << "\n";
   }
   catch (const std::runtime_error& e) {
       // Timeout or other local failure
       std::cerr << "Failed: " << e.what() << "\n";
   }

In a PUT handler on the server side, call ``op->error()`` to send the error
string back to the client as a ``RemoteError``:

.. code-block:: c++

   pv.onPut([](pvxs::server::SharedPV& pv,
               std::unique_ptr<pvxs::server::ExecOp>&& op,
               pvxs::Value&& val) {
       if (val["value"].as<double>() < 0.0) {
           op->error("Value must be non-negative");
           return;
       }
       pv.post(val);
       op->reply();
   });

**Python (P4P)**

.. code-block:: python

   from p4p.client.thread import Context, RemoteError, TimeoutError, Disconnected

   with Context('pva') as ctxt:
       # GET — throw=True (default): raises on error
       try:
           v = ctxt.get('MY:PV')
       except RemoteError as e:
           print('server said:', e)
       except TimeoutError:
           print('timed out')

       # GET — throw=False: returns Exception object instead of raising
       result = ctxt.get('MY:PV', throw=False)
       if isinstance(result, Exception):
           print('error:', result)

       # PUT: same pattern
       err = ctxt.put('MY:PV', 99.0, throw=False)
       if isinstance(err, Exception):
           print('PUT failed:', err)

**Java (Phoebus core-pva)**

.. code-block:: java

   import org.epics.pva.client.*;
   import java.util.concurrent.*;

   try (PVAClient client = new PVAClient()) {
       PVAChannel ch = client.getChannel("MY:PV");
       ch.connect().get(5, TimeUnit.SECONDS);

       try {
           ch.read("").get(5, TimeUnit.SECONDS);
       } catch (ExecutionException e) {
           // Unwrap: e.getCause() is the actual server error
           System.err.println("Server error: " + e.getCause().getMessage());
       } catch (TimeoutException e) {
           System.err.println("Timed out");
       }
   }

----

Server: hard-coded inline permission checks
-------------------------------------------

The simplest way to enforce access policy is to inspect the client's
credentials directly in the PUT or RPC handler and call ``op->error()``
to reject the request.  This approach is fast and requires no external
configuration, but the policy is compiled into the executable.  To
express policy in a malleable configuration file that can be updated
without recompiling, use asLib with an ACF file — see the
`Using asLib for ACF-based access control`_ section below.

A server-side PUT handler receives the client's credentials on every
operation.  Check ``credentials()->isTLS``, ``method``, ``account``, or
``roles()`` to enforce policy before applying the write.

**C++**

.. code-block:: c++

   #include <pvxs/server.h>
   #include <pvxs/sharedpv.h>
   #include <pvxs/nt.h>

   auto pv = pvxs::server::SharedPV::buildMailbox();
   pv.open(pvxs::nt::NTScalar{pvxs::TypeCode::Float64}.create());

   pv.onPut([](pvxs::server::SharedPV& pv,
               std::unique_ptr<pvxs::server::ExecOp>&& op,
               pvxs::Value&& val) {
       const auto& cred = *op->credentials();

       // Require TLS with a named account
       if (!cred.isTLS || cred.method != "x509") {
           op->error("TLS client certificate required");
           return;
       }
       // Check group membership
       auto roles = cred.roles();
       if (roles.find("operators") == roles.end()) {
           op->error("Not in 'operators' group");
           return;
       }
       pv.post(val);
       op->reply();
   });

   pvxs::server::Server::fromEnv()
       .addPV("MY:PV", pv)
       .run();

**Python (P4P)**

.. code-block:: python

   from p4p.nt import NTScalar
   from p4p.server import Server
   from p4p.server.thread import SharedPV

   pv = SharedPV(nt=NTScalar('d'), initial=0.0)

   @pv.put
   def handle(pv, op):
       # op.account() is the cert CN (x509) or user@host (ca)
       # op.roles() is the set of group memberships
       if 'operators' not in op.roles():
           op.done(error='Not in operators group')
           return
       pv.post(op.value())
       op.done()

   Server.forever(providers=[{'MY:PV': pv}])

**Java (Phoebus core-pva)**

Override ``ServerAuthorization.hasWriteAccess()`` to control write access
globally, or check inside the write event handler:

.. code-block:: java

   import org.epics.pva.server.*;
   import org.epics.pva.data.*;

   try (PVAServer server = new PVAServer()) {
       server.configureAuthorization(new ServerAuthorization() {
           @Override
           public boolean hasWriteAccess(String pv_name,
                                         ClientAuthentication auth) {
               // Require x509 (TLS with client cert)
               return auth.getType() == PVAAuth.x509;
           }
       });

       PVAStructure data = new PVAStructure("demo", "demo_t",
                                            new PVADouble("value", 0.0));
       server.createPV("MY:PV", data.cloneData(),
           (tcp, pv, changes, written) -> pv.update(written));

       Thread.sleep(Long.MAX_VALUE);
   }

----

.. _using_aslib_acf:

Using asLib for ACF-based access control
-----------------------------------------

asLib is not limited to IOC processes.  Any standalone pvxs server can
load an ACF file and evaluate it per-request, giving you a malleable
access-control policy that can be updated by editing the ACF file and
restarting the process — no recompile needed.  This is how PVACMS
itself controls administrative access to its certificate-management PVs.

.. seealso::

   :ref:`acf_implementation_coverage` — which implementations support the
   ``METHOD``, ``AUTHORITY``, and ``PROTOCOL`` ACF predicates.

Standalone server (no IOC)
~~~~~~~~~~~~~~~~~~~~~~~~~~~

The pattern used by PVACMS:

1. **Call** ``asInitFile()`` **once at startup**, before creating the pvxs
   server or registering any PVs.  The ACF file path comes from a
   configuration file, environment variable, or command-line flag.

2. **Create one** ``ASMEMBERPVT`` **per access group** (usually just
   ``"DEFAULT"``) using ``asAddMember()``, typically as a ``static``
   local inside the handler lambda so it is created on first call and
   lives for the process lifetime.

3. **Per request, on the handler stack**, map the operation's
   credentials (``op->credentials()``) to an asLib identity with
   ``asAddClientIdentity()`` (or ``asAddClient()`` on older base), then
   call ``asCheckPut()`` to test write permission.  Remove the client
   handle with ``asRemoveClient()`` when done.

.. note::

   This pattern uses only the access-security API from epics-base
   (``asLib.h`` in ``Com``); it does not require the pvxsIoc library or
   ``iocInit()``.

.. code-block:: c++

   #include <asLib.h>
   #include <pvxs/server.h>
   #include <pvxs/sharedpv.h>
   #include <pvxs/nt.h>

   // --- At process startup, before building the server: ---

   if (asInitFile("/etc/myapp/myapp.acf", "")) {
       throw std::runtime_error("Failed to load ACF file");
   }

   // --- In the PUT handler: ---

   auto pv = pvxs::server::SharedPV::buildMailbox();
   pv.open(pvxs::nt::NTScalar{pvxs::TypeCode::Float64}.create());

   pv.onPut([](pvxs::server::SharedPV& pv,
               std::unique_ptr<pvxs::server::ExecOp>&& op,
               pvxs::Value&& val) {

       // Register the ASG member once (static — lives for process lifetime).
       static ASMEMBERPVT as_member = []() {
           ASMEMBERPVT m{};
           if (asAddMember(&m, "DEFAULT"))
               throw std::runtime_error("asAddMember failed");
           return m;
       }();

       // Per-request: map pvxs credentials to an asLib identity and check.
       const auto& cred = *op->credentials();

       // asLib wants the peer host without the port; cred.peer is
       // "address:port", so strip the trailing ":port" (the last colon,
       // which leaves bracketed IPv6 literals like "[::1]" intact).
       std::string host = cred.peer;
       const auto colon = host.find_last_of(':');
       if (colon != std::string::npos)
           host.resize(colon);

       ASCLIENTPVT client{};
       ASIDENTITY id{};
       id.user      = cred.account.c_str();
       id.host      = const_cast<char*>(host.c_str());
       id.method    = cred.method.c_str();
       id.authority = cred.authority.c_str();
       id.protocol  = cred.isTLS ? AS_PROTOCOL_TLS : AS_PROTOCOL_TCP;
       asAddClientIdentity(&client, as_member, ASL1, id);

       const bool allowed = asCheckPut(client); // calls the asLib check
       asRemoveClient(&client);

       if (!allowed) {
           op->error("access denied");
           return;
       }

       pv.post(val);
       op->reply();
   });

   pvxs::server::Server::fromEnv().addPV("MY:PV", pv).run();

``asAddClientIdentity()`` (or ``asAddClient()`` on older base) registers
the client's identity with asLib, and ``asCheckPut()`` tests write
permission; ``asRemoveClient()`` releases the client handle.

The example checks the account identity only.  To also honour ACF
``UAG`` groups, repeat the add/check for each role returned by
``cred.roles()`` (as the ``role/<group>`` identity) and allow the write
if any of them passes.

A minimal two-group ACF to allow ``x509``-authenticated administrators
to write while giving everyone read-only access:

.. code-block:: text

   UAG(ADMINS) {alice, bob}

   ASG(DEFAULT) {
       RULE(0, READ)
       RULE(1, WRITE) {
           UAG(ADMINS)
           METHOD("x509")
           PROTOCOL("tls")
       }
   }

To pick up ACF changes, restart the process.  There is no built-in
runtime reload — ``asInitFile`` must be called again from the start,
which requires a restart.  If hot-reload is needed, wire a SIGHUP
handler to ``asFreeAll()`` followed by ``asInitFile()`` and then
retrigger ``asAddMember()`` for each registered group.

In an IOC (pvxsIoc)
~~~~~~~~~~~~~~~~~~~~

Inside an IOC, pvxsIoc handles steps 1–3 automatically using the
standard EPICS ``asInitFile``/``asAddClient`` machinery driven by the
IOC shell.  Your record-support or device-support code receives a
populated ``ASCLIENTPVT`` and calls the check macros directly:

.. code-block:: c++

   #include <asLib.h>

   // asLib calls this via the ASCLIENTPVT registered by pvxsIoc:
   if (!asCheckPut(asClientPvt)) {
       // denied
       return S_db_noWrite;
   }

When pvxsIoc is compiled against epics-base with
``EPICS_ASLIB_HAS_IDENTITY``, the full SPVA identity — method,
authority, and protocol — is passed to asLib and the new ACF predicates
(``METHOD``, ``AUTHORITY``, ``PROTOCOL``) become available:

.. code-block:: c

   // What pvxsIoc calls on your behalf for each client connection:
   ASIDENTITY id = {
       .user      = "alice",            // CN from cert, or username
       .host      = "192.168.1.10",     // client IP
       .method    = "x509",             // or "ca", "anonymous"
       .authority = "EPICS Root CA",    // CA common name (x509 only)
       .protocol  = AS_PROTOCOL_TLS     // or AS_PROTOCOL_TCP
   };
   asAddClientIdentity(&asClientPvt, asMemberPvt, asl, id);

Without ``EPICS_ASLIB_HAS_IDENTITY`` (older epics-base), pvxsIoc falls
back to passing ``x509/<CN>`` as the username to ``asAddClient()``,
which preserves read/write distinctions but the new ACF predicates have
no effect.

----

Accepting only TLS connections — rejecting plain TCP
-----------------------------------------------------

There is no configuration flag that causes a pvxs server to refuse all
plain-TCP connections at the transport level.  The approach is to check
``credentials()->isTLS`` at the point where each operation arrives and
reject it explicitly.  This accepts the TCP connection at the transport
level but refuses operations at the application level.

For a **SharedPV**, check in the PUT handler:

**C++**

.. code-block:: c++

   #include <pvxs/server.h>
   #include <pvxs/sharedpv.h>
   #include <pvxs/nt.h>

   auto pv = pvxs::server::SharedPV::buildMailbox();
   pv.open(pvxs::nt::NTScalar{pvxs::TypeCode::Float64}.create());

   // Reject any PUT that did not arrive over TLS
   pv.onPut([](pvxs::server::SharedPV& pv,
               std::unique_ptr<pvxs::server::ExecOp>&& op,
               pvxs::Value&& val) {
       if (!op->credentials()->isTLS) {
           op->error("TLS required: plain TCP connections not accepted");
           return;
       }
       pv.post(val);
       op->reply();
   });

For a custom ``Source``, the channel-level check in ``onCreate()``
closes the channel before any operation is submitted:

.. code-block:: c++

   struct TlsOnlySource : public pvxs::server::Source {
       void onCreate(std::unique_ptr<pvxs::server::ChannelControl>&& op) override {
           if (!op->credentials()->isTLS) {
               op->close();    // reject non-TLS channels before any op
               return;
           }
           op->onOp([](std::unique_ptr<pvxs::server::ConnectOp>&& cop) {
               cop->connect(pvxs::nt::NTScalar{pvxs::TypeCode::Float64}.create());
           });
       }
       pvxs::server::Source::List onSearch(const pvxs::server::Source::Search& op) override {
           return {};
       }
   };

   pvxs::server::Server::fromEnv()
       .addSource("tlsonly", std::make_shared<TlsOnlySource>())
       .run();

.. note::

   ``EPICS_PVAS_TLS_OPTIONS="client_cert=require"`` ensures that every
   *TLS* connection presents a client certificate, but it does not refuse
   plain-TCP connections at the transport level.  Plain-TCP clients can
   still reach the server port.  Combine it with the handler check above.

**Python (P4P)**

P4P does not expose ``isTLS`` to Python-level handlers.  The nearest
equivalent is to check the auth method — ``x509`` authentication is only
possible over TLS, so it serves as a reliable proxy:

.. code-block:: python

   @pv.put
   def handle(pv, op):
       acct = op.account()
       if not acct or '/' not in acct:
           op.done(error='TLS client certificate required')
           return
       method, user = acct.split('/', 1)
       if method != 'x509':
           op.done(error='TLS client certificate required')
           return
       pv.post(op.value())
       op.done()

**Java (Phoebus core-pva)**

``hasWriteAccess`` receives the ``ClientAuthentication`` which includes the
auth type.  ``x509`` implies TLS; ``anonymous`` and ``ca`` may be either:

.. code-block:: java

   server.configureAuthorization(new ServerAuthorization() {
       @Override
       public boolean hasWriteAccess(String pv_name, ClientAuthentication auth) {
           // Only allow writes from mTLS-authenticated clients
           return auth.getType() == PVAAuth.x509;
       }
   });

----

Runtime reconfiguration (C++)
------------------------------

To reload the TLS configuration (for example after a new keychain file has
been installed), call ``reconfigure()``.  This drops all current connections
and re-establishes them using the updated configuration.

.. code-block:: c++

   // Server
   auto serv = pvxs::server::Server::fromEnv().start();
   // ...
   serv.reconfigure(serv.config());

   // Client
   auto cli_conf = pvxs::client::Config::fromEnv();
   auto cli = cli_conf.build();
   // ...
   cli.reconfigure(cli_conf);

----

Access rights change notifications (Java client)
-------------------------------------------------

The PVAccess protocol defines a ``CMD_ACL_CHANGE`` message that a server
sends to connected clients when a channel's write-access rights change.
GUI clients such as Phoebus / CS-Studio use this to update their
read-only indicator without needing to attempt a PUT first.

The Phoebus ``core-pva`` Java client receives these notifications via a
``ClientAccessRightsListener`` registered at channel creation:

.. code-block:: java

   import org.epics.pva.client.*;

   try (PVAClient client = new PVAClient()) {
       PVAChannel ch = client.getChannel(
           "MY:PV",
           (channel, state) -> System.out.println("State: " + state),
           (channel, isWritable) -> System.out.println("Writable: " + isWritable));

       ch.connect().get(5, TimeUnit.SECONDS);
       System.out.println("Writable: " + ch.isWritable());
   }

----

IOC applications (C++ only)
----------------------------

An IOC uses the same SPVA runtime configuration as a standalone server,
but the process is linked with ``pvxsIoc`` and loads ``pvxsIoc.dbd``.
IOC processes are C++ only; P4P and Phoebus do not implement the EPICS
IOC shell or record layer.

Building an IOC
~~~~~~~~~~~~~~~

Add ``pvxsIoc`` and ``pvxs`` to your IOC Makefile and load ``pvxsIoc.dbd``
in the application DBD:

.. code-block:: make

   # iocApp/src/Makefile
   PROD_IOC += myioc
   myioc_SRCS += myioc_registerRecordDeviceDriver.cpp
   myioc_SRCS_DEFAULT += myiocMain.cpp

   myioc_DBD += base.dbd
   myioc_DBD += pvxsIoc.dbd

   myioc_LIBS += pvxsIoc pvxs
   myioc_LIBS += $(EPICS_BASE_IOC_LIBS)

In ``configure/RELEASE.local``:

.. code-block:: make

   EPICS_BASE = /path/to/epics-base
   PVXS       = /path/to/pvxs

The minimal IOC main:

.. code-block:: c++

   // iocApp/src/myiocMain.cpp
   #include <iocsh.h>
   #include <epicsExit.h>

   extern "C" int myioc_registerRecordDeviceDriver(struct dbBase *);

   int main(int argc, char *argv[]) {
       if (argc >= 2) {
           iocsh(argv[1]);
       } else {
           iocshBody("", "");
       }
       epicsExit(0);
       return 0;
   }

Startup script
~~~~~~~~~~~~~~

.. code-block:: shell

   ## iocBoot/iocmyioc/st.cmd
   #!../../bin/linux-x86_64/myioc

   < envPaths
   cd "${TOP}"
   dbLoadDatabase "dbd/myioc.dbd"
   myioc_registerRecordDeviceDriver pdbbase

   dbLoadRecords "db/myrecs.db", "P=MYIOC:"

   epicsEnvSet("EPICS_PVAS_TLS_KEYCHAIN", "/ioc/private/server.p12")
   epicsEnvSet("EPICS_PVAS_TLS_OPTIONS",  "client_cert=require on_expiration=standby")
   epicsEnvSet("EPICS_PVA_ADDR_LIST",     "pvacms-host")
   epicsEnvSet("EPICS_PVA_AUTO_ADDR_LIST","NO")

   iocInit

Use ``on_expiration=standby`` when the IOC must stop serving if its
certificate cannot be refreshed.  Use ``fallback-to-tcp`` only during a
planned compatibility period.

----

RPC and management PVs
----------------------

pvxs servers can expose management actions as RPC process variables using
``SharedPV::onRPC()``.  PVACMS uses this same pattern for certificate
creation, approval, revocation, health, and metrics.  Application services
that need management endpoints should follow this model:

* publish normal data through ``SharedPV`` or a custom ``Source``;
* publish administrative actions as RPC process variables;
* protect those actions with ACF rules or inline credential checks as
  shown in :doc:`spva-authorization`.

.. code-block:: c++

   #include <pvxs/server.h>
   #include <pvxs/sharedpv.h>

   auto rpc_pv = pvxs::server::SharedPV::buildReadonly();

   // RPC PVs can be called even before open()
   rpc_pv.onRPC([](pvxs::server::SharedPV&,
                   std::unique_ptr<pvxs::server::ExecOp>&& op,
                   pvxs::Value&& args) {
       const auto& cred = *op->credentials();
       if (!cred.isTLS || cred.method != "x509") {
           op->error("Admin RPC requires TLS client certificate");
           return;
       }
       // ... handle the RPC ...
       auto result = pvxs::nt::NTScalar{pvxs::TypeCode::String}.create();
       result["value"] = std::string("ok");
       op->reply(result);
   });

   pvxs::server::Server::fromEnv()
       .addPV("MY:ADMIN:RPC", rpc_pv)
       .run();

----

Server applications — full lifecycle
-------------------------------------

**C++**

.. code-block:: c++

   #include <pvxs/nt.h>
   #include <pvxs/server.h>
   #include <pvxs/sharedpv.h>
   #include <pvxs/log.h>

   int main() {
       pvxs::logger_config_env();

       auto initial = pvxs::nt::NTScalar{pvxs::TypeCode::Float64}.create();
       initial["value"] = 42.0;

       auto pv = pvxs::server::SharedPV::buildMailbox();
       pv.open(initial);

       pv.onFirstConnect([](pvxs::server::SharedPV&) {
           std::cout << "First client connected\n";
       });
       pv.onLastDisconnect([](pvxs::server::SharedPV&) {
           std::cout << "Last client disconnected\n";
       });

       pvxs::server::Server::fromEnv()
           .addPV("MY:PV", pv)
           .run();
       return 0;
   }

For secure operation, set the server keychain:

.. code-block:: shell

   export EPICS_PVAS_TLS_KEYCHAIN=$HOME/.config/pva/1.4/server.p12
   export EPICS_PVAS_TLS_OPTIONS="client_cert=require"

**Python (P4P)**

.. code-block:: python

   from p4p.nt import NTScalar
   from p4p.server import Server
   from p4p.server.thread import SharedPV

   pv = SharedPV(nt=NTScalar('d'), initial=0.0)

   @pv.put
   def handle(pv, op):
       pv.post(op.value())
       op.done()

   # TLS from environment: EPICS_PVAS_TLS_KEYCHAIN=/path/to/server.p12
   Server.forever(providers=[{'MY:PV': pv}])

To configure TLS programmatically:

.. code-block:: python

   with Server(providers=[{'MY:PV': pv}], conf={
       'EPICS_PVAS_TLS_KEYCHAIN': '/path/to/server.p12',
       'EPICS_PVAS_TLS_OPTIONS': 'client_cert=require',
   }) as srv:
       import time; time.sleep(3600)

**Java (Phoebus core-pva)**

.. code-block:: java

   import org.epics.pva.data.*;
   import org.epics.pva.server.*;

   // TLS from environment: EPICS_PVAS_TLS_KEYCHAIN=/path/to/server.p12
   try (PVAServer server = new PVAServer()) {
       PVAStructure data = new PVAStructure("demo", "demo_t",
                                            new PVADouble("value", 42.0));
       ServerPV pv = server.createPV("MY:PV", data.cloneData(),
           (tcp, p, changes, written) -> p.update(written));

       Thread.sleep(Long.MAX_VALUE);
   }
