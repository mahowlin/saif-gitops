{{- define "hubble-timescape-ui.name" -}}
{{- .Chart.Name }}-ui
{{- end }}

{{- define "hubble-timescape-ui.fullname" -}}
{{- include "hubble-timescape.fullname" . }}-ui
{{- end }}

{{- define "hubble-timescape-ui.labels" -}}
helm.sh/chart: {{ include "hubble-timescape.chart" . }}
{{ include "hubble-timescape-ui.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hubble-timescape-ui.selectorLabels" -}}
{{- if not .Values.lite.enabled -}}
app.kubernetes.io/name: {{ include "hubble-timescape-ui.name" . }}
app.kubernetes.io/instance: {{ include "hubble-timescape-ui.name" . }}-{{ .Release.Name }}
app.kubernetes.io/component: ui
app.kubernetes.io/part-of: {{ .Chart.Name }}
{{- else -}}
{{ include "hubble-timescape-lite.selectorLabels" . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-ui.podLabels" -}}
{{ include "hubble-timescape-ui.selectorLabels" . }}
{{- with .Values.ui.podLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-ui.podAnnotations" -}}
{{- if .Values.ui.rollOutPods }}
{{- include "hubble-timescape-ui.name" . }}-config-configmap-checksum: {{ include (print $.Template.BasePath "/ui_configmap.yaml") . | sha256sum | quote }}
{{- end }}
{{- with .Values.ui.podAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-ui.service.name" -}}
{{- .Chart.Name }}-ui
{{- end }}

{{- define "hubble-timescape-ui.service.port" -}}
{{- if .Values.ui.service.port }}
{{- .Values.ui.service.port }}
{{- else }}
{{- 80 }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-ui.serverAddress" -}}
{{- if .Values.lite.enabled }}
{{- printf "localhost:%v" .Values.server.port -}}
{{- else }}
{{- include "hubble-timescape-server.service.address" . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-ui.containers" -}}
{{ include "hubble-timescape-ui.container" . }}
{{- end }}

{{- define "hubble-timescape-ui.volumes" -}}
{{ include "hubble-timescape-ui.config-volume" . }}
{{- $tls := merge dict .Values.server.tls .Values.tls -}}
{{- if $tls.enabled }}
{{ include "hubble-timescape-ui.certs-volume" . }}
{{- end -}}
{{- with .Values.ui.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-ui.config-volume" -}}
- name: ui-config
  configMap:
    name: {{ include "hubble-timescape-ui.name" . }}-config
    items:
    - key: config.yaml
      path: config.yaml
{{- end }}

{{- define "hubble-timescape-ui.certs-volume" -}}
- name: ui-tls
  projected:
    defaultMode: 0400
    sources: {{- include "hubble-timescape-ui.certs-volume.sources" . | nindent 4 }}
{{- end }}

{{- define "hubble-timescape-ui.certs-volume.sources" -}}
{{- $tls := merge dict .Values.ui.tls .Values.tls }}
{{- if $tls.caBundle.enabled }}
{{ include "hubble-timescape-ui.certs-volume.sources.server-ca-override" $tls }}
{{- else }}
{{ include "hubble-timescape-ui.certs-volume.sources.server-ca" . }}
{{- end }}
{{ include "hubble-timescape-ui.certs-volume.sources.oidc-provider-ca" . }}
{{- end }}

{{- define "hubble-timescape-ui.certs-volume.sources.server-ca" -}}
{{- $tlsClientCA := .Values.server.tls.clientCA }}
{{- if .Values.server.rbac.tls.clientCA.configMap.name }}
{{- $tlsClientCA = .Values.server.rbac.tls.clientCA }}
{{- end }}
{{- if $tlsClientCA.configMap.name }}
- configMap:
    name: {{ $tlsClientCA.configMap.name }}
    items:
    - key: {{ $tlsClientCA.configMap.key  }}
      path: ca.crt
{{- else -}}
- secret:
    name: {{ .Values.server.tls.secretName }}
    items:
    - key: ca.crt
      path: ca.crt
{{- end -}}
{{- end }}

{{- define "hubble-timescape-ui.certs-volume.sources.server-ca-override" -}}
- {{ .caBundle.useSecret | ternary "secret" "configMap" }}:
    name: {{ .caBundle.name }}
    items:
    - key: {{ .caBundle.key }}
      path: ca.crt
{{- end }}

{{- define "hubble-timescape-ui.certs-volume.sources.oidc-provider-ca" -}}
{{- $oidcCAConfigMapName := .Values.server.rbac.oidcCA.configMap.name }}
{{- $oidcCAConfigMapKey := .Values.server.rbac.oidcCA.configMap.key }}
{{- if .Values.ui.auth.oidc.issuerCA.configMap.name }}
{{- $oidcCAConfigMapName = .Values.ui.auth.oidc.issuerCA.configMap.name }}
{{- $oidcCAConfigMapKey = .Values.ui.auth.oidc.issuerCA.configMap.key }}
{{- end }}
{{- if $oidcCAConfigMapName }}
- configMap:
    name: {{ $oidcCAConfigMapName }}
    items:
    - key: {{ $oidcCAConfigMapKey }}
      path: oidc-provider-ca.pem
{{- end -}}
{{- end }}


{{- define "hubble-timescape-ui.auth.enabled" -}}
{{- or .Values.ui.auth.enabled .Values.server.rbac.enabled -}}
{{- end }}

{{- define "hubble-timescape-ui.prometheus.port" -}}
{{- if not .Values.lite.enabled -}}
{{ .Values.ui.prometheus.port }}
{{- else -}}
9091
{{- end }}
{{- end }}

{{- define "hubble-timescape-ui.gops.port" -}}
{{- if not .Values.lite.enabled -}}
{{ .Values.ui.gops.port }}
{{- else -}}
9899
{{- end }}
{{- end }}

{{- define "hubble-timescape-ui.pprof.port" -}}
{{- if not .Values.lite.enabled -}}
{{ .Values.ui.pprof.port }}
{{- else -}}
6061
{{- end }}
{{- end }}

{{- define "hubble-timescape-ui.loadBalancing.clusterRole.rules" -}}
- apiGroups:
  - isovalent.com
  resources:
  - lbbackendpools
  - lbdeployments
  - lbservices
  - lbvips
  verbs:
  - get
  - list
  - create
  - delete
  - update
{{- end }}
