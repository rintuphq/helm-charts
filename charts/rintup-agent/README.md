# rintup-agent Helm chart

The RintUp Kubernetes agent: node metrics (DaemonSet) and cluster health findings (Deployment). Nodes show up in
RintUp under **Servers** with a cluster label; cluster problems (NotReady, CrashLoopBackOff, OOMKilled...) open
incidents in the **incident center** and resolve themselves once fixed.

Agent source code and image: [rintuphq/agents](https://github.com/rintuphq/agents).

## Install

The **Servers > Add Kubernetes** screen in RintUp asks for a cluster name and generates the command with the key:

```bash
helm install rintup-agent oci://ghcr.io/rintuphq/charts/rintup-agent \
  --namespace rintup --create-namespace \
  --set cluster.name=prod-ist \
  --set apiKey=rka_...
```

To keep the key out of your shell history and the Helm release record, create a Secret first:

```bash
kubectl create namespace rintup
kubectl -n rintup create secret generic rintup-agent --from-literal=apiKey=rka_...
helm install rintup-agent oci://ghcr.io/rintuphq/charts/rintup-agent -n rintup \
  --set cluster.name=prod-ist --set existingSecret=rintup-agent
```

Pin a chart version with `--version X.Y.Z`. Within a few minutes the cluster, its nodes and their health appear in
RintUp. Check:

```bash
kubectl -n rintup get pods -l app.kubernetes.io/instance=rintup-agent
kubectl -n rintup logs -l app.kubernetes.io/component=cluster-agent --tail=20
```

If the namespace enforces Pod Security (`pod-security.kubernetes.io/enforce`), the node agent needs **privileged**
(see Security). To install only the cluster agent: `--set nodeAgent.enabled=false` (then "restricted" is enough).

## Uninstall

```bash
helm uninstall rintup-agent -n rintup
```

Everything the chart created is removed: DaemonSet, Deployment, Secret, ServiceAccount, ClusterRole/Binding,
Role/Binding and the leader election Lease (the Lease belongs to the chart; the agent only updates it). An
`existingSecret` you created yourself and the namespace stay. To remove the history as well, delete the cluster in
RintUp (its nodes, metrics and cluster integration are deleted; incidents remain).

## Components

| Component | Kind | What it does |
| -- | -- | -- |
| `node-agent` | DaemonSet (every node; default toleration `operator: Exists`) | Host CPU, memory, disk, network, load. On its first heartbeat the node registers as a "server". A node not seen for 15 minutes is **archived without an alert** (no autoscaling noise). |
| `cluster-agent` | Deployment (`replicas` 1; with 2+ a Lease elects one leader) | Lists the Kubernetes API read-only every 30 s: node NotReady (3 min), pod CrashLoopBackOff, OOMKilled (last 15 min), Pending (10 min), image pull failure (5 min), Deployment/StatefulSet/DaemonSet missing replicas (5 min), failed Job (last 1 h), PVC Pending (10 min)/Lost, actionable Warning events (FailedMount, Evicted, SystemOOM...; noise such as Unhealthy/BackOff is filtered). |

Findings arrive in the incident center on the default service through a per-cluster "Kubernetes: &lt;cluster&gt;"
integration. The deduplication key is cluster + namespace + resource + reason; pods of the same Deployment are one
finding. Each report is a full snapshot: a finding that disappears is resolved.

## Values

| Value | Default | Description |
| -- | -- | -- |
| `cluster.name` | none (required) | Cluster name in RintUp (letters, digits, `.`, `_`, `-`; at most 63). |
| `apiKey` | `""` | Cluster key `rka_...` (shown once in RintUp). |
| `existingSecret` | `""` | Existing Secret holding the key; when set, `apiKey` is ignored. |
| `existingSecretKey` | `apiKey` | Key name inside the Secret. |
| `endpoint` | `https://rintup.com` | RintUp address (https only). |
| `allowInsecureHttp` | `false` | Plain http for local tests only (kind + fake endpoint). |
| `image.repository` | `ghcr.io/rintuphq/agent` | Agent image (amd64 + arm64, distroless, cosign signed). |
| `image.tag` | `""` (appVersion) | Tag. |
| `image.digest` | `""` | `sha256:...`; used instead of the tag when set. |
| `image.pullPolicy` | `IfNotPresent` | |
| `imagePullSecrets` | `[]` | |
| `priorityClassName` | `""` | Default for both components (e.g. `system-node-critical`). |
| `proxy.https` / `proxy.noProxy` | `""` | Egress proxy to RintUp (`HTTPS_PROXY`, `NO_PROXY`). Not used for the Kubernetes API. |
| `extraEnv` | `[]` | Extra environment variables (cannot override the agent's own variables). |
| `podAnnotations` / `podLabels` | `{}` | |
| `serviceAccount.create` / `.name` / `.annotations` | `true` / `""` / `{}` | Service account of the cluster agent. |
| `rbac.create` | `true` | ClusterRole + Lease Role. |
| `nodeAgent.enabled` | `true` | |
| `nodeAgent.intervalSeconds` | `60` | 10-3600. |
| `nodeAgent.processes` | `[]` | Host processes to watch (e.g. `[kubelet, containerd]`). |
| `nodeAgent.mountHostRoot` | `true` | `/` read-only at `/host/root` (for disk usage). |
| `nodeAgent.resources` | 50m / 64Mi | Request = limit. |
| `nodeAgent.tolerations` | `[{operator: Exists}]` | Every node, including the control plane. |
| `nodeAgent.nodeSelector` | `kubernetes.io/os: linux` | |
| `nodeAgent.affinity` / `.priorityClassName` / `.updateStrategy` | | |
| `clusterAgent.enabled` | `true` | |
| `clusterAgent.replicas` | `1` | 1-3; with 2+ a Lease elects a single leader. |
| `clusterAgent.resources` | 50m / 64Mi request, 192Mi limit | Raise memory for large clusters (5000+ pods). |
| `clusterAgent.tolerations` / `.nodeSelector` / `.affinity` / `.priorityClassName` | | |

Invalid values are caught at install time (`values.schema.json`): missing cluster name or key, wrong key format,
`http://` endpoint, unknown value names, numbers out of range...

## Security

- **Kubernetes permissions (cluster agent):** the ClusterRole has only `get/list/watch` on `nodes`, `pods`, `events`,
  `persistentvolumeclaims`, `deployments`, `statefulsets`, `daemonsets`, `replicasets`, `jobs`. **No access to
  Secrets, ConfigMaps or pod log/exec/proxy; no write access.** The only write is `get/update` on the Lease the chart
  creates (this name only, this namespace only). No service account token is mounted into the node agent.
- **Container:** non-root (65532), `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, all capabilities
  dropped, `seccompProfile: RuntimeDefault`; `hostNetwork`, `hostPID` and `hostIPC` are off.
- **hostPath (node agent only):** `/proc` at `/host/proc` and `/` at `/host/root`, both **read-only**. The agent only
  reads metric files (`/proc/stat`, `meminfo`, `loadavg`, `uptime`, `1/mounts`, `1/net/dev`, `<pid>/comm|cmdline` for
  process names; `statvfs` for disk size). Pod Security "baseline" does not allow hostPath, so the node agent's
  namespace must be **privileged** (like node-exporter and similar agents). `nodeAgent.mountHostRoot=false` turns off
  disk metrics and mounts only `/proc`.
- **Key:** the `rka_` cluster key can only register nodes, send heartbeats and send cluster reports (no access to the
  panel or the API, no writes to other workspaces). RintUp stores only its SHA-256 hash; rotating it in RintUp
  invalidates the old key immediately. It is never written into the manifest in plain text (Secret) and never logged.
- **Network:** HTTPS only to RintUp (TLS 1.2+, certificate validation cannot be disabled, redirects are not
  followed). The Kubernetes API is reached only with the service account CA (custom root trust).
- **Image:** `ghcr.io/rintuphq/agent` is multi-arch, distroless (chiseled), with SBOM and provenance attestations,
  signed with cosign (keyless). Verify:

  ```bash
  cosign verify ghcr.io/rintuphq/agent@sha256:... \
    --certificate-identity-regexp '^https://github.com/rintuphq/agents/.github/workflows/release.yml@refs/tags/v' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```

- **Chart:** published as an OCI artifact at `oci://ghcr.io/rintuphq/charts/rintup-agent`. When a release is signed,
  verify it with:

  ```bash
  cosign verify ghcr.io/rintuphq/charts/rintup-agent:0.1.0 \
    --certificate-identity-regexp '^https://github.com/rintuphq/helm-charts/.github/workflows/release.yml@refs/heads/main$' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```

## Development

```bash
bash scripts/verify.sh   # helm lint --strict, kubeconform (1.29 + 1.33), schema negative cases, security checks
```
