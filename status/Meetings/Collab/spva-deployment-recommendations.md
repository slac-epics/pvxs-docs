# Secure PVAccess deployment recommendations

Recommendations for running Secure PVAccess, organized by the kind of participant you
are configuring: a client, an IOC or other server, a gateway, a certificate manager, and
an administrator. Each participant needs a certificate, a place to keep it, a set of
trust anchors, and a few environment settings. The sections below say what each one
needs and why.

These are conventions and defaults, not a normative configuration reference. Exact
environment-variable spellings track the pvxs and pvxs-cms version you run; where a value
matters, this document uses the spelling the current libraries parse.

## Terms

- A certificate manager is the server that issues, lists, and revokes certificates. Its
  program is `pvacms`.
- A keychain is one file holding one identity certificate and one or more trust anchors.
- A trust anchor is a root certificate with no private key. It verifies what an authority
  signs and cannot sign anything, so it is safe to distribute.

## Conventions for every participant

Keychains live under the standard configuration directory, `~/.config/pva/1.5/`
(`$XDG_CONFIG_HOME/pva/1.5` when that is set) by convention. The library looks for `client.p12` for a
client and `server.p12` for an IOC or server by default.

| Participant         | Identity keychain                            | Points at it with        |
| ------------------- | -------------------------------------------- | ------------------------ |
| Client              | `~/.config/pva/1.5/client.p12`               | `EPICS_PVA_TLS_KEYCHAIN` |
| Server or IOC       | `~/.config/pva/1.5/server.p12`               | `EPICS_PVA_TLS_KEYCHAIN` |
| Gateway             | `~/.config/pva/1.5/gateway.p12` (convention) | gateway configuration    |
| Administrator       | `~/.config/pva/1.5/admin.p12` (convention)   | `EPICS_PVA_TLS_KEYCHAIN` |
| Certificate manager | `~/.config/pva/1.5/server.p12`               | `EPICS_PVA_TLS_KEYCHAIN` |

Rules that hold for all of them:

- Put site defaults in a **login profile**, not in one operator's shell. A login shell resets
  the environment, so a file that every login reads (for example under `/etc/profile.d/`)
  is where the shared `EPICS_PVA_*` settings and the tool paths belong.
- Set `EPICS_PVA_AUTH_ISSUER` to the **full 40-character issuer identifier** (the subject key
  identifier) of the authority the participant trusts. On first contact there is nothing
  yet to check a delivered authority against, so the whole identifier is required. The
  short 8-character form names an authority but cannot establish trust in one. For a
  participant that trusts more than one authority, the value is a list separated by spaces
  or commas.
- Make the **keychain directory writable** by, and owned by, the account that runs the
  participant. A certificate that is issued but cannot be saved is a directory-ownership
  problem, not a certificate problem.
- **Protect keychains** with file permissions (`600`, owned by the running account), and
  protect any keychain that holds a signing key more strongly still.
- The plaintext port is `5075` and the secure port is `5076` by default.

## Client

A client is an interactive tool or an application that reads and writes process variables:
`pvxget`, `pvxput`, `pvxmonitor`, and anything built on the client library.

- Get an identity with `authnstd -u client`. The command prints a request identifier; that
  identifier, reported out of band, is what proves to an administrator that a pending
  request is yours. Anyone can request any subject name, so the request alone proves
  nothing.
- Reading needs no certificate. Writing may. Access rules on the server decide what a
  given certificate may write.
- Discover local servers by broadcast: leave `EPICS_PVA_AUTO_ADDR_LIST=YES` on the local
  network. To reach servers across a boundary, set `EPICS_PVA_AUTO_ADDR_LIST=NO` and name
  the far side in `EPICS_PVA_NAME_SERVERS`.
- Name a secure name server with the `pvas://host:5076` scheme. The question then travels
  over the secure transport, so the client verifies what answers before it asks. A client
  outside a secure boundary must hold the trust anchor before it can ask anything at all.
- Revoke your own leaked key yourself with `pvxcert -R <identifier>`. A holder may revoke
  their own certificate without waiting for an administrator, and no other.
- Set `EPICS_PVA_TLS_OPTIONS=no_revocation_check` only for a client that cannot reach the
  certificate manager to check its own certificate, because the sole route runs through a
  boundary that the certificate is needed to cross. The server it connects to still checks
  what the client presents. Do not set it where the client has an ordinary route to the
  manager.

## IOC and other servers

An IOC hosts process variables. The same guidance covers any server built on the server
library.

- Get an identity with `authnstd -u ioc` for a participant that is both a server and a
  client, or `authnstd -u server` for one that only serves. A gateway needs the `ioc`
  form; a plain IOC can use either, and `ioc` is the safe default.
- When the server may be presented a certificate issued by a manager it cannot reach
  directly, set `EPICS_PVAS_STATUS_NAME_SERVERS` to a name server that can reach the
  issuing manager, such as a gateway that fronts it. The server checks a peer certificate
  with a separate inner client, and that inner client takes its name servers from this
  variable. Left unset, a server that meets an unreachable issuer hangs on
  `Wait for Client <peer> certificate status to become GOOD` and never validates the
  connection, while a plain connection to the same endpoint still works.
- Restart the server to pick up a newly issued keychain. It is ready when it answers over
  the secure transport, which `pvxinfo -v` shows as a `TLS` line on port `5076`. That is
  later than the certificate reading `VALID`, so wait for the secure answer, not for a
  fixed delay.
- A server whose own certificate is revoked stops offering the secure port and serves
  plain traffic, so readers fall back to anonymous reads and writers lose write access.

## Gateway

A gateway bridges two networks: it is a server to the clients on one side and a client to
the servers on the other.

- Give it an `ioc` certificate, because it is both a server and a client. A server
  certificate alone cannot act as a client, and a gateway that holds no usable certificate
  serves nothing.
- Set `EPICS_PVAS_STATUS_NAME_SERVERS` on the gateway too, so its server side can check a
  certificate issued by a manager on the far network.
- **Serve only the interface that faces the clients it fronts**. A gateway that also binds the
  network behind it answers those local broadcast searches a second time, and every local
  command there fails with `Duplicate PV name`. The servers behind it are reached directly
  and have no reason to ask their own gateway for them.
- **Start the servers behind the gateway first**, wait until each answers over the secure
  transport, then start the gateway. A gateway makes its upstream connections once, at
  start, and does not remake one it could not make or later lost. If reads through a
  running gateway stop, restart the gateway.
- For a boundary that must carry the secure transport only, control which ports listen
  with the port variables. Each accepts `NO` to stop that listener: set
  `EPICS_PVA_SERVER_PORT=NO` to close the plaintext port and `EPICS_PVA_UDP_PORT=NO` to
  close the search port, leaving only the secure port that `EPICS_PVA_TLS_PORT` names.
  Setting `EPICS_PVA_TLS_PORT=NO` closes the secure port instead. A gateway that serves
  only the secure port must already hold a certificate when it starts.
- `EPICS_PVA_TLS_OPTIONS=client_cert=require` applies during secure connection establishment, and
  requires that connection to be mutually authenticated: the client must present its own
  certificate, not only verify the server's. Without it, a boundary that carries the
  secure transport only still accepts an anonymous client over that transport.
- A request that crosses a gateway is **authorized twice**: once at the gateway against the
  certificate the client presents, and once at the upstream server, which sees the gateway
  rather than the original client. Say who the client is in the gateway's own access file,
  and let the upstream rule name the gateway or the shared authority. An upstream rule
  cannot name a client it never sees.
- In the gateway's process-variable list, forward only the certificate process variables
  (`CERT:CREATE`, `CERT:STATUS`, `CERT:LIST`) of the authority this gateway fronts. Where
  more than one authority is in play, qualify those names by issuer so a request reaches
  the manager that can answer it.

## PVACMS: Certificate manager

The certificate manager (`pvacms`) issues and revokes certificates for one authority.

- **Run one manager per authority**. Each manager holds only what it issued and answers only
  for its own authority. Where two managers share a network, each certificate-list view is
  named by issuer (`CERT:LIST:<issuer>:ALL`) so a request is never ambiguous.
- **Persist the certificate database** named by `EPICS_PVACMS_DB`. It is the record of every
  certificate issued.
- **Protect the authority's signing key**, and keep it off the hosts that serve traffic. If
  the manager creates its own authority on first start, that keychain is the only copy:
  back it up and do not lose it, because if it is gone, every certificate it already signed
  can no longer be trusted. If you give the manager an authority made elsewhere, keep the
  original safe, private, and read-only; the copy the manager runs from can be replaced.
- Create the administrator identity once, when the manager first starts. Without an
  administrator, nobody may approve or revoke a certificate.  Make new administrators by 
  updating the ACF rule to include new users.
- **Read the issuer identifier the manager prints at startup**, in both the short naming form
  and the full trust-establishing form, and distribute the full form to the participants
  that must trust this authority.
- To **keep serving when the OCSP responder that answers for a certificate root is unreachable**, set
  `EPICS_PVACMS_AUTHORITY_HOLD_LAST_KNOWN=YES`. The manager then serves the last answer it
  verified. The trade is deliberate: a revocation issued during the outage is not seen
  until the outage ends. Left off, the manager fails closed, and reads do not complete
  while the root's status is unknown.

## Administrator

An administrator approves, denies, and revokes certificates on one manager.

- Present a certificate over the secure transport to act. A decision attempted without a
  certificate is refused, whatever the user is named, because the manager's access rule
  names an administrator group, the manager's own authority, `PROTOCOL(TLS)`, and
  `METHOD(X509)`, and an anonymous connection matches none of them.
- Approve or deny pending requests, and revoke issued certificates. A denial is not a
  separate state: the manager records a denied request as `REVOKED`, and shows that before
  you confirm.
- You cannot revoke the administrator certificate the manager depends on to keep
  answering. The tool offers it like any other and reports the manager's refusal.
- Only an administrator sees the request-identifier column in a listing, which is what ties
  a pending request to the person who reported its identifier.
- Plan authority replacement with the ordinary expiry tools. A root appears in
  `pvxcert -l --expiring 30d` like any other certificate, because everything under it stops
  the day it expires.

## Group users by organizational unit

To let one rule cover many users, name an organizational unit from the certificate subject
in a user access group, instead of listing common names:

```
UAG(BEAMLINE) { "OU=beamline" }
```

Any certificate carrying that unit is a member, so you add a person by issuing them a
certificate with the unit (`authnstd -u client --ou beamline`), with no change to any
access file. Units nest innermost first, so `OU=staff,OU=beamline` sits inside `beamline`.
A rule that must never be crossed should also name the `AUTHORITY`, because the unit is
only a claim the issuing authority vouched for.

## Certificate status, briefly

- `VALID` is usable now. `PENDING_APPROVAL` is awaiting an administrator's decision.
  `PENDING` is approved but not yet within its validity dates. `EXPIRED` and `REVOKED` are
  terminal.
- `REVOKED` points at the holder's own certificate. `AUTHORITY_REVOKED` points further up
  the chain and means every holder under that authority is in the same state; the fix is a
  new authority and new certificates, not anything done to one holder's certificate.
- Revocation takes effect immediately and cannot be undone. It cuts a connection that is
  already established, because both ends watch the certificate for as long as the
  connection lasts, not only at the next attempt.
- Revoking a shared root stops every participant that chains to it. The only recovery is a
  new root and a re-issue to everyone. Treat it as the last resort.

## Trust models

The participants above assemble into one of three trust models. The model decides only how
trust anchors are distributed; the per-participant guidance is otherwise the same.

- **One authority**. A single manager holds one root and issues every certificate under it. A
  rule that names the authority means only "holds a certificate this site issued", and
  user groups tell holders apart.
- **Several authorities under one shared root**. Each authority has its own manager, and every
  certificate chains to the shared root, so a certificate from any of them is trusted
  everywhere. Each manager still administers only what it issued. The shared root carries
  the address of a status responder, and each manager asks that responder for the root's
  status.
- **Independent roots, no shared chain**. Nothing sits above the roots, so trust comes from
  every keychain holding all the roots as trust anchors. Build such a keychain with
  `authnstd --trust-anchor --issuer "SKID_1 SKID_2"`, which sets the anchor set to exactly
  the roots named. `authnstd --issuer` on its own adds an anchor and never removes one, so
  asking one authority for a certificate cannot drop a root the keychain already trusted.

Two cautions for keychains that hold several anchors:

- Network Security Services strips the extra anchors: `pk12util` keeps only one when it
  exports such a file. Java `keytool` keeps them all. Keep a multi-anchor keychain out of
  any workflow that passes it through `pk12util`.
- For a Java consumer, add the trusted-key-usage attribute when you build the file:
  `openssl pkcs12 -export -jdktrust anyExtendedKeyUsage ...`.

## Distributing a trust anchor

A participant that cannot reach the certificate manager, because a boundary sits between
them, must be given the anchor out of band before it can do anything over the secure
transport. Until the anchor arrives it cannot even ask for its own certificate.

- **Distribute the trust anchor, never the authority keychain**. The authority keychain carries
  the signing key, and handing it over hands over the power to issue certificates. The
  manager writes an anchor-only file for you to distribute.
- **Publish the anchor at a well-known read-only path** on every host that needs it, for
  example `/etc/epics/trust_anchor.p12`, and point consumers there.
- Do not copy an anchor over a keychain that already holds an identity. The anchor and the
  identity share one file, so overwriting the identity with an anchor-only file reduces the
  holder to anonymous.
- **Give a handed-over anchor file an empty password**. A non-empty password makes `authnstd`
  refuse to read it as a keychain and fetch the authority over the network instead, which
  is the thing the hand-off exists to avoid.
