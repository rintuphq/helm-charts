#!/usr/bin/env bash
# Chart verification (CI and local): helm lint --strict, helm template | kubeconform -strict
# (Kubernetes 1.29 and 1.33 schemas), negative cases for values.schema.json and template checks (a wrong value must
# make helm template FAIL), and security defaults (no Secret access, hostNetwork/hostPID off, read-only mounts).
# Requires: helm (3.14+ or 4), kubeconform. Schemas are downloaded on first run (KUBECONFORM_SCHEMA for a local path).
set -uo pipefail

cd "$(dirname "$0")/../charts"
chart=rintup-agent
ci=$chart/ci
key="rka_0123456789abcdefghijABCDEFGHIJ0123456789abc"
status=0
fail() { echo "ERROR: $*"; status=1; }

schema_args=()
if [ -n "${KUBECONFORM_SCHEMA:-}" ]; then
  schema_args=(-schema-location "$KUBECONFORM_SCHEMA")
fi

echo "==> helm lint"
for values in "$ci"/*.yaml; do
  helm lint "$chart" --strict -f "$values" >/dev/null || fail "lint: $values"
done

echo "==> kubeconform"
for version in 1.29.0 1.33.0; do
  for values in "$ci"/*.yaml; do
    out=$(helm template t "$chart" -n rintup -f "$values" | kubeconform -strict -summary -kubernetes-version "$version" "${schema_args[@]}" 2>&1) \
      || fail "kubeconform $version $values: $out"
    echo "    $version $(basename "$values"): ${out##*$'\n'}"
  done
done

echo "==> negative cases (all must be rejected)"
negative() {
  local name=$1; shift
  if helm template t "$chart" -n rintup "$@" >/dev/null 2>&1; then fail "accepted: $name"; else echo "    rejected: $name"; fi
}
negative "missing cluster.name" --set apiKey=$key
negative "missing key" --set cluster.name=prod
negative "key format" --set cluster.name=prod --set apiKey=srv_wrong
negative "space in cluster name" --set cluster.name="prod ist" --set apiKey=$key
negative "http endpoint" --set cluster.name=prod --set apiKey=$key --set endpoint=http://rintup.example
negative "unknown value" --set cluster.name=prod --set apiKey=$key --set clusterAgnet.enabled=true
negative "interval" --set cluster.name=prod --set apiKey=$key --set nodeAgent.intervalSeconds=5
negative "digest" --set cluster.name=prod --set apiKey=$key --set image.digest=latest
negative "replicas" --set cluster.name=prod --set apiKey=$key --set clusterAgent.replicas=0
negative "process name" --set cluster.name=prod --set apiKey=$key --set "nodeAgent.processes[0]=rm -rf"
negative "extraEnv overriding the key" --set cluster.name=prod --set apiKey=$key --set "extraEnv[0].name=RINTUP_TOKEN" --set "extraEnv[0].value=x"

echo "==> security defaults"
rendered=$(helm template t "$chart" -n rintup -f "$ci/default-values.yaml")
grep -q 'secrets' <<<"$(awk '/kind: ClusterRole$/,/^---/' <<<"$rendered")" && fail "ClusterRole includes Secrets"
grep -qE 'verbs: \[.*"(create|update|patch|delete)"' <<<"$(awk '/kind: ClusterRole$/,/^---/' <<<"$rendered")" && fail "ClusterRole has write verbs"
grep -qE 'host(Network|PID|IPC): true' <<<"$rendered" && fail "hostNetwork/hostPID/hostIPC enabled"
[ "$(grep -c 'readOnlyRootFilesystem: true' <<<"$rendered")" -eq 2 ] || fail "readOnlyRootFilesystem not set on both containers"
[ "$(grep -c 'readOnly: true' <<<"$rendered")" -eq 2 ] || fail "hostPath mounts are not read-only"
grep -q "$key" <<<"$rendered" && fail "key written into the manifest in plain text"
grep -q 'drop: \["ALL"\]' <<<"$rendered" || fail "capabilities drop ALL missing"
existing=$(helm template t "$chart" -n rintup -f "$ci/existing-secret-values.yaml")
grep -q 'kind: Secret' <<<"$existing" && fail "Secret rendered although existingSecret is set"
grep -q 'ghcr.io/rintuphq/agent@sha256:' <<<"$existing" || fail "digest not used"

[ "$status" -eq 0 ] && echo "verify: ok."
exit "$status"
