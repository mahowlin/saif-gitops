{{- define "hubble-timescape-server.name" -}}
{{- .Chart.Name }}-server
{{- end }}

{{- define "hubble-timescape-server.labels" -}}
helm.sh/chart: {{ include "hubble-timescape.chart" . }}
{{ include "hubble-timescape-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hubble-timescape-server.selectorLabels" -}}
{{- if not .Values.lite.enabled -}}
app.kubernetes.io/name: {{ include "hubble-timescape-server.name" . }}
app.kubernetes.io/instance: {{ include "hubble-timescape-server.name" . }}-{{ .Release.Name }}
app.kubernetes.io/component: server
app.kubernetes.io/part-of: {{ .Chart.Name }}
{{- else -}}
{{ include "hubble-timescape-lite.selectorLabels" . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-server.podLabels" -}}
{{ include "hubble-timescape-server.selectorLabels" . }}
{{- with .Values.server.podLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-server.podAnnotations" -}}
{{- if .Values.server.rollOutPods }}
{{- include "hubble-timescape-server.name" . }}-configmap-checksum: {{ include (print $.Template.BasePath "/server_configmap.yaml") . | sha256sum | quote }}
{{- end }}
{{- with .Values.server.podAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-server.service.name" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "hubble-timescape-server.service.port" -}}
{{- $tls := merge dict .Values.server.tls .Values.tls -}}
{{- if .Values.server.service.port }}
{{- .Values.server.service.port }}
{{- else }}
{{- $tls.enabled | ternary 443 80 }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-server.service.address" -}}
{{ include "hubble-timescape-server.service.name" . -}}.{{ .Release.Namespace }}.svc.cluster.local:{{ include "hubble-timescape-server.service.port" . -}}
{{- end }}


{{- define "hubble-timescape-server.containers" -}}
{{ include "hubble-timescape-server.container" . }}
{{- end }}


{{- define "hubble-timescape-server.volumes" -}}
{{- $tls := merge dict .Values.server.tls .Values.tls -}}
{{ include "hubble-timescape-server.config-volume" . }}

{{- if .Values.server.rbac.enabled }}
{{ include "hubble-timescape-rbac.policy-volume" .  }}
{{- end -}}

{{- if $tls.enabled }}
{{ include "hubble-timescape-server.tls-volume" . }}
{{- end -}}

{{- $clickhouse := merge dict .Values.server.clickhouse .Values.clickhouse (dict "tls" .Values.tls) -}}
{{ include "hubble-timescape.clickhouse-certs-volume" $clickhouse }}

{{- if and .Values.server.tracing.otlp.tls.enabled .Values.server.tracing.otlp.tls.ca.configMap.name }}
{{ include "hubble-timescape-server.otlp-certs-volume" . }}
{{- end }}

{{- with .Values.server.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end }}


{{- define "hubble-timescape-server.config-volume" -}}
- name: server-config
  configMap:
    name: {{ include "hubble-timescape-server.name" . }}-config
    items:
    - key: config.yaml
      path: config.yaml
{{- end }}

{{- define "hubble-timescape-server.tls-volume" -}}
- name: server-tls
  projected:
    defaultMode: 0400
    sources: {{- include "hubble-timescape-server.tls-volume.sources" . | nindent 4 }}
{{- end }}

{{- define "hubble-timescape-server.tls-volume.sources" -}}
- secret:
    name: {{ .Values.server.tls.secretName }}
    items:
    - key: tls.crt
      path: server.crt
    - key: tls.key
      path: server.key
{{- $tlsClientCA := .Values.server.tls.clientCA }}
{{- if .Values.server.rbac.tls.clientCA.configMap.name }}
{{- $tlsClientCA = .Values.server.rbac.tls.clientCA }}
{{- end }}
{{- if $tlsClientCA.configMap.name }}
- configMap:
    name: {{ $tlsClientCA.configMap.name }}
    items:
    - key: {{ $tlsClientCA.configMap.key  }}
      path: client-ca.crt
{{- end -}}
{{- if .Values.server.rbac.oidcCA.configMap.name }}
- configMap:
    name: {{ .Values.server.rbac.oidcCA.configMap.name }}
    items:
    - key: {{ .Values.server.rbac.oidcCA.configMap.key  }}
      path: oidc-provider-ca.pem
{{- end -}}
{{- end }}

{{- define "hubble-timescape-server.otlp-certs-volume" -}}
- name: server-otlp-certs
  configMap:
    name: {{ .Values.server.tracing.otlp.tls.ca.configMap.name }}
    items:
    - key: {{ .Values.server.tracing.otlp.tls.ca.configMap.key }}
      path: ca.crt
{{- end }}

{{- define "hubble-timescape-server.prometheus.port" -}}
{{ .Values.server.prometheus.port }}
{{- end }}

{{- define "hubble-timescape-server.gops.port" -}}
{{ .Values.server.gops.port }}
{{- end }}

{{- define "hubble-timescape-server.pprof.port" -}}
{{ .Values.server.pprof.port }}
{{- end }}

{{- define "hubble-timescape-server.query-cache.disabled" -}}
{{- if .Values.server.queryCache.enabled -}}
false
{{- else -}}
{{/*
Disable query caching for timescape lite or when the push API/Stream API is enabled.
This is to ensure that the latest data is always available as lite is typically used
for more real-time use-cases like Hubble Relay.
*/}}
{{- or (eq (include "hubble-timescape-ingester.server.http.enabled" .) "true") (eq (include "hubble-timescape-ingester.server.grpc.enabled" .) "true") -}}
{{- end -}}
{{- end }}

{{- define "hubble-timescape-rbac.policy-volume" -}}
- name: server-timescape-rbac-policy
  configMap:
    name: {{ .Values.server.rbac.policy.configMap.name }}
    defaultMode: 0400
{{- end }}
