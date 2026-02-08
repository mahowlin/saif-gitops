{{- define "hubble-timescape-ingester.name" -}}
{{- .Chart.Name }}-ingester
{{- end }}

{{- define "hubble-timescape-ingester.fullname" -}}
{{- include "hubble-timescape.fullname" . }}-ingester
{{- end }}

{{- define "hubble-timescape-ingester.labels" -}}
helm.sh/chart: {{ include "hubble-timescape.chart" . }}
{{ include "hubble-timescape-ingester.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hubble-timescape-ingester.selectorLabels" -}}
{{- if not .Values.lite.enabled -}}
app.kubernetes.io/name: {{ include "hubble-timescape-ingester.name" . }}
app.kubernetes.io/instance: {{ include "hubble-timescape-ingester.name" . }}-{{ .Release.Name }}
app.kubernetes.io/component: ingester
app.kubernetes.io/part-of: {{ .Chart.Name }}
{{- else -}}
{{ include "hubble-timescape-lite.selectorLabels" . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-ingester.podLabels" -}}
{{ include "hubble-timescape-ingester.selectorLabels" . }}
{{- with .Values.ingester.podLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-ingester.podAnnotations" -}}
{{- if .Values.ingester.rollOutPods }}
{{- include "hubble-timescape-ingester.name" . }}-configmap-checksum: {{ include (print $.Template.BasePath "/ingester_configmap.yaml") . | sha256sum | quote }}
{{ include "hubble-timescape-migrate.name" . }}-configmap-checksum: {{ include (print $.Template.BasePath "/migrate_configmap.yaml") . | sha256sum | quote }}
{{- end }}
{{- with .Values.ingester.podAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}


{{- define "hubble-timescape-ingester.service.name" -}}
{{- .Chart.Name }}-ingester
{{- end }}

{{- define "hubble-timescape-ingester.service.push.port" -}}
{{- .Values.ingester.service.pushPort }}
{{- end }}

{{- define "hubble-timescape-ingester.service.stream.port" -}}
{{- .Values.ingester.service.streamPort }}
{{- end }}

{{- define "hubble-timescape-ingester.server.http.enabled" -}}
{{- or .Values.ingester.server.http.enabled .Values.lite.enabled -}}
{{- end }}

{{/*
Ingester grpc server is disabled when basic-auth is configured because it does not support
this authentication method and we don't want to expose an unauthenticated server by default.
*/}}
{{- define "hubble-timescape-ingester.server.grpc.enabled" -}}
{{- and
  (or .Values.ingester.server.grpc.enabled .Values.lite.enabled)
  (not (eq .Values.ingester.server.authMethod "basic-auth"))
-}}
{{- end }}

{{- define "hubble-timescape-ingester.volumes" -}}
{{- $tls := merge dict .Values.ingester.server.tls .Values.tls -}}
{{ include "hubble-timescape-migrate.volumes" . }}
{{ include "hubble-timescape-ingester.config-volume" . }}

{{- if and (or (eq (include "hubble-timescape-ingester.server.http.enabled" .) "true") (eq (include "hubble-timescape-ingester.server.grpc.enabled" .) "true")) $tls.enabled }}
{{ include "hubble-timescape-ingester.server-certs-volume" . }}
{{- end -}}

{{/* ingester-secret volume is only needed for GCS */}}
{{ include "hubble-timescape-ingester.secret-volume" . }}

{{- $clickhouseIngester := merge dict .Values.ingester.clickhouse .Values.clickhouse (dict "tls" .Values.tls) -}}
{{ include "hubble-timescape.clickhouse-certs-volume" $clickhouseIngester }}

{{- if .Values.ingester.bucket.tls.ca.configMap.name }}
{{ include "hubble-timescape-ingester.bucket-certs-volume" . }}
{{- end }}

{{- with .Values.ingester.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-ingester.config-volume" -}}
- configMap:
    name: {{ include "hubble-timescape-ingester.name" . }}-config
    items:
    - key: config.yaml
      path: config.yaml
  name: ingester-config
{{- end }}

{{- define "hubble-timescape-ingester.secret-volume" -}}
- secret:
    secretName: {{ .Values.ingester.clickhouse.credentials.secretName }}
  name: ingester-secret
{{- end }}

{{- define "hubble-timescape-ingester.server-certs-volume" -}}
- name: ingester-server-tls
  projected:
    defaultMode: 0400
    sources: {{- include "hubble-timescape-ingester.server-certs-volume.sources" . | nindent 4 }}
{{- end }}

{{- define "hubble-timescape-ingester.server-certs-volume.sources" -}}
{{- $tls := merge dict .Values.ingester.server.tls .Values.tls -}}
- secret:
    items:
    - key: tls.crt
      path: push-server.crt
    - key: tls.key
      path: push-server.key
    name: {{ $tls.secretName }}
{{- if and (eq .Values.ingester.server.authMethod "mtls") .Values.ingester.server.tls.clientCA.configMap.name }}
- configMap:
    name: {{ .Values.ingester.server.tls.clientCA.configMap.name }}
    items:
    - key: {{ .Values.ingester.server.tls.clientCA.configMap.key  }}
      path: push-server-client-ca.crt
{{- end -}}
{{- end }}

{{- define "hubble-timescape-ingester.bucket-certs-volume" -}}
- name: ingester-bucket-certs
  projected:
    defaultMode: 0400
    sources:
    - configMap:
        name: {{ .Values.ingester.bucket.tls.ca.configMap.name }}
        items:
        - key: {{ .Values.ingester.bucket.tls.ca.configMap.key }}
          path: bucket-ca.crt
{{- end }}

{{- define "hubble-timescape-ingester.prometheus.port" -}}
{{ .Values.ingester.prometheus.port }}
{{- end }}

{{- define "hubble-timescape-ingester.gops.port" -}}
{{ .Values.ingester.gops.port }}
{{- end }}

{{- define "hubble-timescape-ingester.pprof.port" -}}
{{ .Values.ingester.pprof.port }}
{{- end }}

{{- define "hubble-timescape-ingester.k8sImporter.clusterRole.rules" -}}
{{- if .Values.ingester.k8sImporter.k8sNetworkPolicies }}
- apiGroups:
  - networking.k8s.io
  resources:
  - networkpolicies
  verbs:
  - get
  - list
  - watch
{{- end }}
{{- if .Values.ingester.k8sImporter.k8sEndpoints }}
- apiGroups:
  - ""
  resources:
  - endpoints
  verbs:
  - get
  - list
  - watch
{{- end }}

{{- $ciliumioResources := list }}
{{- if .Values.ingester.k8sImporter.ciliumNetworkPolicies }}
{{- $ciliumioResources = mustAppend $ciliumioResources "ciliumnetworkpolicies" }}
{{- $ciliumioResources = mustAppend $ciliumioResources "ciliumclusterwidenetworkpolicies" }}
{{- end }}
{{- if .Values.ingester.k8sImporter.ciliumEndpoints }}
{{- $ciliumioResources = mustAppend $ciliumioResources "ciliumendpoints" }}
{{- end }}
{{- if .Values.ingester.k8sImporter.ciliumIdentities }}
{{- $ciliumioResources = mustAppend $ciliumioResources "ciliumidentities" }}
{{- end }}
{{- if .Values.ingester.k8sImporter.tetragonNetworkPolicies }}
{{- $ciliumioResources = mustAppend $ciliumioResources "tetragonnetworkpolicies" }}
{{- $ciliumioResources = mustAppend $ciliumioResources "tetragonnetworkpoliciesnamespaced" }}
{{- end }}
{{- if .Values.ingester.k8sImporter.ciliumNodes }}
{{- $ciliumioResources = mustAppend $ciliumioResources "ciliumnodes" }}
{{- end }}
{{- if gt (len $ciliumioResources) 0 }}
- apiGroups:
  - cilium.io
  resources: {{- $ciliumioResources | toYaml | nindent 2 }}
  verbs:
  - get
  - list
  - watch
{{- end }}
{{- $isovalentResources := list }}
{{- if .Values.ingester.k8sImporter.tetragonNodes }}
{{- $isovalentResources = mustAppend $isovalentResources "tetragonnodes" }}
{{- end }}
{{- if .Values.ingester.k8sImporter.smartSwitches }}
{{- $isovalentResources = mustAppend $isovalentResources "smartswitches" }}
{{- end }}
{{- if .Values.ingester.k8sImporter.smartSwitchNetworkPolicies }}
{{- $isovalentResources = mustAppend $isovalentResources "smartswitchnetworkpolicies" }}
{{- end }}
{{- if gt (len $isovalentResources) 0 }}
- apiGroups:
  - isovalent.com
  resources: {{- $isovalentResources | toYaml | nindent 2 }}
  verbs:
  - get
  - list
  - watch
{{- end }}
{{- end }}
