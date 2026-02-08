{{- define "hubble-timescape-lite.name" -}}
{{- .Chart.Name }}-lite
{{- end }}

{{- define "hubble-timescape-lite.fullname" -}}
{{- include "hubble-timescape.fullname" . }}-lite
{{- end }}

{{- define "hubble-timescape-lite.labels" -}}
helm.sh/chart: {{ include "hubble-timescape.chart" . }}
{{ include "hubble-timescape-lite.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hubble-timescape-lite.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hubble-timescape-lite.name" . }}
app.kubernetes.io/instance: {{ include "hubble-timescape-lite.name" . }}-{{ .Release.Name }}
app.kubernetes.io/component: lite
app.kubernetes.io/part-of: {{ .Chart.Name }}
{{- end }}

{{- define "hubble-timescape-lite.podLabels" -}}
{{ include "hubble-timescape-lite.selectorLabels" . }}
{{- if and .Values.lite.clickhouse.enabled }}
hubble-timescape-lite-clickhouse: "true"
{{- end }}
{{- with .Values.lite.podLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-lite.podAnnotations" -}}
{{- if .Values.lite.rollOutPods }}
{{ include "hubble-timescape-lite.name" . }}-config-configmap-checksum: {{ include (print $.Template.BasePath "/lite_configmap.yaml") . | sha256sum | quote }}
{{- if .Values.lite.clickhouse.enabled }}
{{- if .Values.lite.clickhouse.rollOutPods }}
{{ include "hubble-timescape-lite.name" . }}-clickhouse-settings-configmap-checksum: {{ include (print $.Template.BasePath "/lite_clickhouse_configmap.yaml") . | sha256sum | quote }}
{{- end }}
{{- /* This annotation will ensure that the pod is restarted on pvc size change */}}
{{- if .Values.lite.clickhouse.volumes.data }}
{{- with .Values.lite.clickhouse.volumes.data.size }}
{{ include "hubble-timescape-lite.name" $ }}-clickhouse-volume-size: {{ . }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- with .Values.lite.podAnnotations }}
{{ toYaml . }}
{{- end }}

{{- end }}

{{- define "hubble-timescape-lite.service.name" -}}
{{- .Chart.Name }}-lite
{{- end }}

{{- define "hubble-timescape-lite.affinity" -}}
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchExpressions:
      - key: app.kubernetes.io/name
        operator: In
        values: ["{{ .Chart.Name }}-clickhouse"]
    topologyKey: kubernetes.io/hostname
{{- end }}


{{- define "hubble-timescape-clickhouse.volumes" }}
- configMap:
    name: {{ include "hubble-timescape-lite.name" . }}-clickhouse-settings
    items:
    - key: clickhouse-settings.xml
      path: clickhouse-settings.xml
  name: clickhouse-config
- configMap:
    name: {{ include "hubble-timescape-lite.name" . }}-clickhouse-settings
    items:
    - key: clickhouse-profiles.xml
      path: clickhouse-profiles.xml
    - key: clickhouse-users.xml
      path: clickhouse-user.xml
  name: clickhouse-user
{{- if .Values.lite.clickhouse.volumes.data }}
{{- /*  We're using a separate PVC instead of a volumeClaimTemplates as volumeClaimTemplates can't be added, removed or changed.
        For our purposes with replicas: 1 there is no difference if we use a separate PVC, but it allows us to upgrade from no
        PVC to some PVC and we can resize it (if the storage class allows it)
*/}}
- name: clickhouse-data
  persistentVolumeClaim:
    claimName: data-storage-template-chi-hubble-timescape-hubble-data-0-0-0
{{- else }}
- name: clickhouse-data
  emptyDir: {}
{{- end }}

{{- with .Values.lite.clickhouse.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end }}


{{- define "hubble-timescape-lite.volumes" -}}
{{- $serverTLS := merge dict .Values.server.tls .Values.tls -}}
{{- $ingesterTLS := merge dict .Values.ingester.server.tls .Values.tls -}}
{{- $uiTLS := merge dict .Values.server.tls .Values.tls -}}

{{ include "hubble-timescape-lite.config-volume" . }}

{{- $clickhouseLocal := merge dict .Values.lite.clickhouse .Values.clickhouse -}}
{{ include "hubble-timescape.clickhouse-certs-volume" $clickhouseLocal }}
{{/* ingester-secret volume is only needed for GCS */}}
{{ include "hubble-timescape-ingester.secret-volume" . }}

{{- if .Values.ingester.bucket.tls.ca.configMap.name }}
{{ include "hubble-timescape-ingester.bucket-certs-volume" . }}
{{- end }}

{{- if .Values.server.rbac.enabled }}
{{ include "hubble-timescape-rbac.policy-volume" .  }}
{{- end -}}

{{- if or $serverTLS.enabled $ingesterTLS.enabled}}
{{ include "hubble-timescape-lite.tls-volume" . }}
{{- end -}}

{{- if and .Values.ui.enabled $uiTLS.enabled }}
{{ include "hubble-timescape-ui.certs-volume" . }}
{{- end -}}

{{- if and .Values.lite.tracing.otlp.tls.enabled .Values.lite.tracing.otlp.tls.ca.configMap.name }}
{{ include "hubble-timescape-server.otlp-certs-volume" . }}
{{- end }}

{{- with .Values.lite.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end }}


{{- define "hubble-timescape-lite.config-volume" -}}
- name: config
  configMap:
    name: {{ include "hubble-timescape-lite.name" . }}-config
    items:
    - key: config.yaml
      path: config.yaml
{{- end }}

{{- define "hubble-timescape-lite.tls-volume" -}}
{{- $serverTLS := merge dict .Values.server.tls .Values.tls -}}
{{- $ingesterTLS := merge dict .Values.ingester.server.tls .Values.tls -}}
- name: tls
  projected:
    defaultMode: 0400
    sources:
    {{- if $serverTLS.enabled }}
    {{- include "hubble-timescape-server.tls-volume.sources" . | nindent 4 }}
    {{- end }}
    {{- if $ingesterTLS.enabled }}
    {{- include "hubble-timescape-ingester.server-certs-volume.sources" . | nindent 4 }}
    {{- end }}
{{- end }}
