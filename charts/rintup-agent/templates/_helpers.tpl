{{/*
Common names, labels and environment variables. The agent is configured through environment variables only.
*/}}

{{- define "rintup-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rintup-agent.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else if contains (include "rintup-agent.name" .) .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "rintup-agent.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "rintup-agent.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "rintup-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
rintup.com/cluster: {{ .Values.cluster.name | quote }}
{{- end -}}

{{- define "rintup-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rintup-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "rintup-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (printf "%s-cluster-agent" (include "rintup-agent.fullname" .) | trunc 63 | trimSuffix "-") .Values.serviceAccount.name -}}
{{- else -}}
{{- required "serviceAccount.name is required when serviceAccount.create=false" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "rintup-agent.leaseName" -}}
{{- printf "%s-cluster-agent" (include "rintup-agent.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Image: repository@digest when a digest is set (pins the signed image), else repository:tag (appVersion when tag is empty). */}}
{{- define "rintup-agent.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) -}}
{{- end -}}
{{- end -}}

{{- define "rintup-agent.secretName" -}}
{{- default (include "rintup-agent.fullname" .) .Values.existingSecret -}}
{{- end -}}

{{- define "rintup-agent.secretKey" -}}
{{- if .Values.existingSecret -}}{{ .Values.existingSecretKey }}{{- else -}}apiKey{{- end -}}
{{- end -}}

{{/* Required values (the schema checks them too; this gives a readable error without schema validation). */}}
{{- define "rintup-agent.validate" -}}
{{- $_ := required "cluster.name is required (the cluster name shown in RintUp)" .Values.cluster.name -}}
{{- if and (not .Values.apiKey) (not .Values.existingSecret) -}}
{{- fail "apiKey or existingSecret is required (the rka_ key shown once when the cluster is added in RintUp)" -}}
{{- end -}}
{{- if and (not .Values.allowInsecureHttp) (not (hasPrefix "https://" .Values.endpoint)) -}}
{{- fail "endpoint must start with https://" -}}
{{- end -}}
{{- end -}}

{{/* Environment shared by both components. The key only comes from a Secret (never written into the manifest). */}}
{{- define "rintup-agent.commonEnv" -}}
- name: RINTUP_URL
  value: {{ .Values.endpoint | trimSuffix "/" | quote }}
- name: RINTUP_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "rintup-agent.secretName" . }}
      key: {{ include "rintup-agent.secretKey" . }}
{{- if .Values.allowInsecureHttp }}
- name: RINTUP_ALLOW_INSECURE_HTTP
  value: "true"
{{- end }}
{{- with .Values.proxy.https }}
- name: HTTPS_PROXY
  value: {{ . | quote }}
{{- end }}
{{- with .Values.proxy.noProxy }}
- name: NO_PROXY
  value: {{ . | quote }}
{{- end }}
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Restricted container security (both components): non-root, read-only root, no capabilities, no escalation. */}}
{{- define "rintup-agent.containerSecurityContext" -}}
runAsNonRoot: true
runAsUser: 65532
runAsGroup: 65532
readOnlyRootFilesystem: true
allowPrivilegeEscalation: false
privileged: false
capabilities:
  drop: ["ALL"]
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "rintup-agent.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 65532
runAsGroup: 65532
fsGroup: 65532
seccompProfile:
  type: RuntimeDefault
{{- end -}}
