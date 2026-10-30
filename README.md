# RintUp Helm charts

Helm charts for [RintUp](https://rintup.com), published as OCI artifacts on GitHub Container Registry.

| Chart | Description |
| -- | -- |
| [rintup-agent](charts/rintup-agent) | RintUp Kubernetes agent: node metrics (DaemonSet) and cluster health findings (Deployment). |

## Usage

Charts are served from `oci://ghcr.io/rintuphq/charts` (Helm 3.8 or newer; no `helm repo add` needed):

```bash
helm install rintup-agent oci://ghcr.io/rintuphq/charts/rintup-agent \
  --namespace rintup --create-namespace \
  --set cluster.name=prod-ist \
  --set apiKey=rka_...
```

The cluster name and the `rka_` key come from the RintUp panel (**Servers > Add Kubernetes**), which also generates
this command. See the [chart README](charts/rintup-agent/README.md) for all values, the `existingSecret` option and
the security model.

Show the latest chart metadata and the default values of a version:

```bash
helm show chart oci://ghcr.io/rintuphq/charts/rintup-agent
helm show values oci://ghcr.io/rintuphq/charts/rintup-agent --version 0.1.0
```

## Verifying signatures

Chart releases are signed with [cosign](https://github.com/sigstore/cosign) (keyless, GitHub OIDC) by this
repository's release workflow:

```bash
cosign verify ghcr.io/rintuphq/charts/rintup-agent:0.1.0 \
  --certificate-identity 'https://github.com/rintuphq/helm-charts/.github/workflows/release.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The agent image (`ghcr.io/rintuphq/agent`) is built and signed in [rintuphq/agents](https://github.com/rintuphq/agents):

```bash
cosign verify ghcr.io/rintuphq/agent@sha256:... \
  --certificate-identity-regexp '^https://github.com/rintuphq/agents/.github/workflows/release.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Development

Requirements: [helm](https://helm.sh) and [kubeconform](https://github.com/yannh/kubeconform).

```bash
bash scripts/verify.sh
```

`scripts/verify.sh` runs `helm lint --strict` with every file in `charts/rintup-agent/ci/`, validates the rendered
manifests with kubeconform against Kubernetes 1.29 and 1.33, checks that invalid values are rejected, and checks
the security defaults (no Secret access, no write verbs, no host namespaces, read-only mounts, no key in plain text).
The chart requires `cluster.name` and a key, so a bare `helm lint charts/rintup-agent` without values reports them
as missing; use the CI values: `helm lint charts/rintup-agent --strict -f charts/rintup-agent/ci/default-values.yaml`.

## Workflows

- `.github/workflows/lint.yml`: runs `scripts/verify.sh` on pull requests and pushes to main; on pull requests a
  changed chart must also bump `version` in its `Chart.yaml`.
- `.github/workflows/release.yml`: on a push to main that touches `charts/`, packages every chart whose version is
  not yet in the registry, pushes it to `oci://ghcr.io/rintuphq/charts` with the built-in `GITHUB_TOKEN`
  (`packages: write`) and signs it with cosign (keyless). Published versions are never overwritten.

To release: bump `version` (and `appVersion` for a new agent release) in `charts/rintup-agent/Chart.yaml` and merge.

## Security

See [SECURITY.md](SECURITY.md). Report vulnerabilities privately to security@rintup.com.

## License

[Apache-2.0](LICENSE)
