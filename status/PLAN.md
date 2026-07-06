# FY26 / FY27 Secure EPICS - Status & Plan

## 1. FY26 deliverable status - Development vs Delivery

Status on **two separate axes**:

- **Dev status = has the code been written?** (implemented and merged into the SLAC repos -
  `slac-epics/pvxs-tls`, `pvxs-cms`, `epics-base-tls`, `p4p`, `pvxs-docs`, `phoebus`).
- **Delivery status = is it accepted/landed?** (review comments resolved, and - where the
  deliverable is upstream - **merged into the community `epics-base/*` repos**).

Per-axis states: ✅ done · 🟡 partial · ⬜ not started.

| FY26 Deliverable                                                   | Dev status                        | Delivery status                                                                                                                             | Notes / gap                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------------------ | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Upgrade EPICS ACL Semantics for Authentication**                 | ✅ Written                         | ⬜ **Not yet** - upstream **epics-base #886** OPEN / CHANGES_REQUESTED, **10 unresolved** review threads; slac/epics-base-tls #1 in progress | METHOD/AUTHORITY/PROTOCOL + PVXS AS impl. done. Blocked on upstream review; still to demonstrate production use case SLAC.                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| **Improve Code Modularity and Maintainability**                    | ✅ Written & merged (SLAC)         | 🟡 **Partial** - dev-merged in pvxs-cms; upstream cleanup asks open in pvxs #171 family                                                     | SPVA implementation split to pvxs and pvxs-cms.  Namespace split to `cms::*`, module boundaries, EXPERT_API (pvxs-cms #6, MERGED). Many issues in `epics-base/pvxs` #171 speak to modularity and maintainability - substantial work to complete.                                                                                                                                                                                                                                                                                                               |
| **Implement Features for Managing Reliability and Robustness**     | ✅ Written & merged (SLAC)         | 🟡 **Partial** - landed in SLAC train; upstream acceptance rides pvxs #171                                                                  | Validity schedules, **Subject Alternative Name (SAN) in the Certificate Creation Request - written & merged** (validated/normalised in the CCR and propagated end-to-end into the issued cert; openspec `san-in-ccr`, pvxs-cms #6), health/metrics (NTEnum/NTScalar), degraded-mode/reconnect, BAD/UNKNOWN teardown (pvxs-cms #5/#6, pvxs-tls #7/#8, all MERGED). FY26 target = FEDERATED; cluster → FY27.                                                                                                                                                                                                                                                                                                                                                                |
| **Implement Secure EPICS Gateway Integration**                     | 🟡 Partial                        | ⬜ **Not yet** - depends on ACL semantics landing upstream (#886)                                                                            | New-ACF parser works. SOW 4.2.1.2 PV-authority cert extension - **verify; likely open.**                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| **Integrate Secure EPICS with Enterprise Security Infrastructure** | ✅ Written (OCSP)                  | 🟡 **Partial** - OCSP in upstream review (pvxs #171)                                                                                        | **FY26 scope now = OCSP only.** OCSP over PVAccess written, in upstream review. **CMP/SCEP + IAM/PKI (KeyCloak) recommendation moved to FY27**, joining the `authnjwt` build (see §3A/§3B).                                                                                                                                                                                                                                                                                                                                                                    |
| **Streamline Certificate Management**                              | ✅ Written (SLAC; fixes in flight) | 🟡 **Partial** - daemon reuse/renew fixes not all merged (pvxs-cms #10/#11/#25)                                                             | Auto issue/renew/revoke (SLAC) + diskless/non-persistent IOC (FNAL) support present. **FEDERATED multi-CMS is complete** - two PVACMS on one network with distinct CA (or distinct intermediates under a common CA) certs, each with its own issuer id; clients select via `--issuer` flag / env var. **Improvement in progress:** add `--issuer` to `pvxcert`'s issuer-less query commands (`--health`/`--metrics`) for explicit targeting in multi-issuer setups (pvxs-cms #28) - a convenience enhancement, not a functional gap. Cluster deferred to FY27. |
| **Kubernetes Support**                                             | 🟡 Partial                        | 🟡 **Partial** - lab cluster running; productised tooling not finalised; **needs more testing at SLAC**                                     | k8s lab demo (Helm/Docker, 3 zones) exists; Secure SoftIOC service + shared-secret X.509 tooling (helm/kubectl) to do; further SLAC-environment testing required.                                                                                                                                                                                                                                                                                                                                                                                              |
| **Measure Performance and Scalability**                            | ✅ Written (instrumentation)       | 🟡 **Partial** - the written report artifact is the deliverable                                                                             | `PVXS_ENABLE_PERF` + perf paths in place. **report** (loopback / client→server / client→gw→server; seq + 1000-parallel GET/s vs baseline) - **executable produced and tests run**                                                                                                                                                                                                                                                                                                                                                                              |
| **General Documentation**                                          | 🟡 Partial                        | 🟡 **Partial**                                                                                                                              | **`pvxs-docs` is the staging area for SPVA docs before they move into the main community `epics-docs`.** The CA and PVA Protocol specs will be **removed** (they duplicate work already in `epics-docs`;  pvxs-docs #5/. The remaining SPVA docs stay the **reference until their final home is found**. Dual-version site + API pipeline shipped. **Still to write (SOW 4.9): IOC Access Security design doc** (METHOD/AUTHORITY/PROTOCOL in UAG/HAG/ASG) and **C++ SPVA programmers doc**.                                                                   |
|                                                                    |                                   |                                                                                                                                             |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |


## 2. What remains to complete in FY26

These are **still FY26** - the meeting resolutions did not remove them, only re-scoped the multi-CMS model to federated.

1. **Upgrade EPICS ACL Semantics** - land epics-base #886 (address the 10 review comments via
   epics-base-tls #1); demonstrate augmented AS in an IOC controlling **LCLS production QUADs**
   for S3DF in SLAC
2. **Enterprise Security Infrastructure (FY26 = OCSP only)** - complete **OCSP** (in upstream
   review). **CMP/SCEP integration, the IAM/PKI recommendation (KeyCloak), and the `authnjwt`
   build are all moved to FY27.
3. **Streamline Certificate Management** - finalize automatic create/distribute/renew/revoke
   incl. diskless & non-persistent (softIOC) certs; land the authn daemon reuse/renew fixes
   (pvxs-cms #10/#11, #25). **The FEDERATED two-CMS model is complete** (distinct CA/intermediate
   certs, per-issuer IDs, `--issuer` client selection), with a convenience **improvement in
   progress** (`pvxcert --issuer` on query commands, pvxs-cms #28); run the two-CMS demo
   (independent cert DBs, mitigated by long cert-status validity).
4. **Kubernetes Support** - Secure SoftIOC service (single X.509 identity, many pods);
   shared-secret X.509 tooling/guidance (helm/kubectl); ingress best-practices.
5. **Documentation** - IOC Access Security **design doc** (METHOD/AUTHORITY/PROTOCOL in
   UAG/HAG/ASG) and **C++ SPVA programmers doc**.
6. **Punch-list on already-delivered work:** upstream review comments on **pvxs #171** (51 open)
   and **epics-base #886** (10 open); the open SLAC fix-PRs in `ISSUES.md` (several
   APPROVED-but-unmerged or awaiting review).

### Explicitly re-scoped for FY26 (per 2‑Jul minutes)
- **Multi-CMS = FEDERATED, not CLUSTER.** Two PVACMS with **non-shared** usage-cert DBs (may or
  may not share a CA), mitigating CMS downtime via long cert-status validity. **Complete**
  (distinct CA/intermediate certs, per-issuer IDs, `--issuer` client selection), with a
  convenience improvement in progress (`pvxcert --issuer`, pvxs-cms #28).
- **STD (Standard Authenticator) must work at SLAC and LBNL.** Per EW, SLAC "still has issues
  with std and cannot yet say it satisfies FY26 deliverables for SLAC" (see `ISSUES.md`:
  pvxs-cms #35/#24/#7 authn/renew items).
- **SLAC-specific FY26 targets** (from minutes): STD working; Gateway I/O with ACF upgrades;
  SLAC STD integrated in ML HPC support + gateway; SLAC Kubernetes demonstrated.
- **FY26 deliverable-objectives list** to be assembled by EW/MD/GW/GM and agreed **13 Jul 09:00**
  (what each lab tests: STD vs Krb vs both; independent CMS vs cluster; what each implements;
  what each writes up).

---

## 3. FY26 → FY27: what moves, what's still owed, what's new

Three distinct buckets - kept separate because they tell very different stories.

### 3A. Built in FY26, but moving to FY27 (work already exists - not a restart)

These are **substantially implemented** already; the 2‑Jul decisions move them out of the FY26
*demonstration* target, not out of existence.

| Deferred item | What's already built (evidence) | Why it moves to FY27 |
|---|---|---|
| **PVACMS clustering** (shared-DB, multi-node convergence/relay/sync) | **Built & tested**: `src/pvacms/clusterctrl`, `clusterdiscovery`, `clustersync`, `clustertypes`; `testcluster.cpp` + `testtlswithcmscluster`; design docs `CLUSTER.md` / `CLUSTER_DESIGN_PATTERNS.md`; merged PRs pvxs-cms #12/#14/#15/#16. | 2‑Jul resolution: **FY26 demonstrates FEDERATED (independent DBs)**, not cluster; "next year revert to dev of cluster." The cluster code stays in-tree and matures in FY27 - FY26 simply doesn't gate on it. |
| **`authnjwt` authenticator (JWT/OIDC)** | **Fully specified, not yet built**: OpenSpec change `add-authnjwt-oauth-authenticator` with proposal + design + tasks + specs (`jwt-client`, `san-in-ccr`). No source implementation yet (`pvxs-cms/src/authn` has no jwt module). | 2‑Jul CONSENSUS ("JWT not now … next year"). **Design is done**, so FY27 starts from build, not from a blank page. FY26 §4.3 is met without it (via OCSP). |

> Clustering is code-complete-and-tested; `authnjwt` is design-complete with build pending. Both
> are deferred to FY27.

### 3B. FY27 new development (not started - genuinely next-year)

| FY27 item | Source | Note |
|---|---|---|
| **Enterprise Security: CMP/SCEP integration** | SOW 4.3.1 | Cert-lifecycle protocol integrations beyond OCSP. **Moved from FY26 by decision** - FY26 §4.3 delivers OCSP only. Not yet started. |
| **Enterprise Security: IAM/PKI recommendation (KeyCloak)** | SOW 4.3.2 | Investigate IAM/PKI integrations, recommend which to support (e.g. KeyCloak). **Moved from FY26 by decision.** Pairs naturally with the `authnjwt` build (OIDC). Not yet started. |
| **Dynamic Distributed Access Control** | SOW 4.10.1 / Proposal 4.1.1 | Replace static ACFs with an online Access Control **Service**: IOCs subscribe to policy updates over secure PVAccess and enforce at runtime; role-based rules, validity schedules, dynamic roles, no-downtime policy change. |
| **Extended Security Features & Policy Customization** | SOW 4.10.2 / Proposal 4.1.2 | Site-tailored extension points: custom authorization logic, MFA, per-zone encryption requirements, per-destination client-cert requirements, site RULE plugins; stronger compliance + auditing. |
| **Stretch (may slip from FY26):** Gateway auto-discovery & secure ACF distribution; secure write-proxy mode (embed client credential in payload, backwards-compatible) | SOW 4.2.1.3‑5 (stretch) / Proposal §3 | Not required for FY26; "best efforts." Likely FY27 if not reached. |

### 3C. Still to do THIS FY (FY26 - not deferred)

The concrete FY26 close-out list (detail in §2):

- **Land ACL semantics upstream** - resolve epics-base #886 review (via epics-base-tls #1); prove
  augmented AS on **LCLS production QUADs** (S3DF).
- **Enterprise Security (OCSP only for FY26)** - finish **OCSP** (in upstream review). CMP/SCEP,
  the IAM/PKI (KeyCloak) recommendation, and the `authnjwt` build are all FY27.
- **Certificate management** - automatic create/distribute/renew/revoke incl. diskless &
  non-persistent softIOC; land authn daemon reuse/renew fixes (pvxs-cms #10/#11/#25).
  **FEDERATED two-CMS is complete** (convenience improvement `pvxcert --issuer` in progress,
  pvxs-cms #28); run the demo.
- **Kubernetes** - Secure SoftIOC service (one X.509 identity, many pods) + shared-secret X.509
  tooling (helm/kubectl) + ingress guidance; **needs more testing at SLAC**.
- **The two documents** - IOC Access Security **design doc** and **C++ SPVA programmers doc**
  (the only outright-not-started FY26 deliverables).
- **Performance report** - confirm the written SOW‑4.8 report artifact is produced.
- **Punch-list** - upstream review comments (pvxs #171: 51; epics-base #886: 10) and the open
  SLAC fix-PRs in `ISSUES.md`.
- **STD working at SLAC** (pvxs-cms #35/#24/#7) - not yet satisfying FY26 deliverables per EW.

### Open FY27-shaping decisions raised on 2‑Jul (not yet resolved)
- **Repo rename `pvxs-docs` → `secure-epics`** (RESOLVED to do) with broadened scope:
  non-normative guides, lab experience notes, meeting minutes, project management; protocol
  specs to **link to community/epics-docs** rather than duplicate (ties to [pvxs-docs #5](https://github.com/slac-epics/pvxs-docs/issues/5)).
- **New-repo approval process** (RESOLVED): public-facing Secure EPICS repos approved by
  devs/collab as relevant, **plus PI (GW)** approval.
- **Stable-interface agreement process** (MD to start the interfaces list); form of agreement
  (minutes vs interface spec doc) TBD.
- **Possible "Technical Note"** on how SPVA + CMS work (message pathways, prefixes, config/status
  PVs) - raised, not yet decided.

---

## 4. Summary

- Development: most deliverables have their code written and merged in the SLAC repos. No
  deliverable is fully accepted upstream yet; the upstream gates are **epics-base #886 (10
  unresolved)** and **epics-base/pvxs #171 (51 unresolved)**, both CHANGES_REQUESTED. (§1)
- Still to complete this FY (§3C): land ACL upstream, finish OCSP, cert-management + federated
  demo, Kubernetes, the two documents, performance report.
- Deferred to FY27, already built (§3A): **clustering** is code-complete and tested (FY26 demos
  FEDERATED instead); **`authnjwt`** is design-complete with the build pending.
- FY26 multi-CMS = FEDERATED, not cluster; the cluster code stays in-tree and matures in FY27.
- New FY27 work (§3B): CMP/SCEP; IAM/PKI (KeyCloak) recommendation; Dynamic Distributed Access
  Control; Extended Security Features & Policy Customization.
- STD at SLAC (pvxs-cms #35/#24/#7): not yet satisfying FY26 deliverables per EW.
- FY26 objective list to be agreed 13 Jul 09:00.
