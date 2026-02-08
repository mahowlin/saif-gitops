{{- define "hubble-timescape-analyzer.name" -}}
{{- .Chart.Name }}-analyzer
{{- end }}


{{- define "hubble-timescape-analyzer.labels" -}}
helm.sh/chart: {{ include "hubble-timescape.chart" . }}
{{ include "hubble-timescape-analyzer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}


{{- define "hubble-timescape-analyzer.selectorLabels" -}}
{{- if not .Values.lite.enabled -}}
app.kubernetes.io/name: {{ include "hubble-timescape-analyzer.name" . }}
app.kubernetes.io/instance: {{ include "hubble-timescape-analyzer.name" . }}-{{ .Release.Name }}
app.kubernetes.io/component: analyzer
app.kubernetes.io/part-of: {{ .Chart.Name }}
{{- else -}}
{{ include "hubble-timescape-lite.selectorLabels" . }}
{{- end }}
{{- end }}


{{- define "hubble-timescape-analyzer.podLabels" -}}
{{ include "hubble-timescape-analyzer.selectorLabels" . }}
{{- with .Values.analyzer.podLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}


{{- define "hubble-timescape-analyzer.podAnnotations" -}}
{{- if .Values.analyzer.rollOutPods }}
{{- include "hubble-timescape-analyzer.name" . }}-configmap-checksum: {{ include (print $.Template.BasePath "/analyzer_configmap.yaml") . | sha256sum | quote }}
{{- end }}
{{- with .Values.analyzer.podAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-analyzer.containers" -}}
{{ include "hubble-timescape-analyzer.container" . }}
{{- end }}


{{- define "hubble-timescape-analyzer.volumes" -}}
{{ include "hubble-timescape-analyzer.config-volume" . }}

{{- $clickhouse := merge dict .Values.analyzer.clickhouse .Values.clickhouse (dict "tls" .Values.tls) -}}
{{ include "hubble-timescape.clickhouse-certs-volume" $clickhouse }}

{{- with .Values.analyzer.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end }}


{{- define "hubble-timescape-analyzer.config-volume" -}}
- name: analyzer-config
  configMap:
    name: {{ include "hubble-timescape-analyzer.name" . }}-config
    items:
    - key: config.yaml
      path: config.yaml
{{- end }}

{{- define "hubble-timescape-analyzer.prometheus.port" -}}
{{ .Values.analyzer.prometheus.port }}
{{- end }}

{{- define "hubble-timescape-analyzer.gops.port" -}}
{{ .Values.analyzer.gops.port }}
{{- end }}

{{- define "hubble-timescape-analyzer.pprof.port" -}}
{{ .Values.analyzer.pprof.port }}
{{- end }}
