{{- define "hubble-timescape-migrate.name" -}}
{{- .Chart.Name }}-migrate
{{- end }}

{{- define "hubble-timescape-migrate.labels" -}}
helm.sh/chart: {{ include "hubble-timescape.chart" . }}
{{ include "hubble-timescape-migrate.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hubble-timescape-migrate.selectorLabels" -}}
{{- if not .Values.lite.enabled -}}
app.kubernetes.io/name: {{ include "hubble-timescape-migrate.name" . }}
app.kubernetes.io/instance: {{ include "hubble-timescape-migrate.name" . }}-{{ .Release.Name }}
app.kubernetes.io/component: ingester
app.kubernetes.io/part-of: {{ .Chart.Name }}
{{- else -}}
{{ include "hubble-timescape-lite.selectorLabels" . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-migrate.podLabels" -}}
{{ include "hubble-timescape-migrate.selectorLabels" . }}
{{- end }}

{{- define "hubble-timescape-migrate.volumes" -}}
{{ include "hubble-timescape-migrate.config-volume" . }}
{{- with .Values.migrate.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end }}


{{- define "hubble-timescape-migrate.config-volume" -}}
- configMap:
    name: {{ include "hubble-timescape-migrate.name" . }}-config
    items:
    - key: config.yaml
      path: config.yaml
  name: migrate-config
{{- end }}

{{- define "hubble-timescape-migrate.gops.port" -}}
{{ .Values.migrate.gops.port }}
{{- end }}

{{- define "hubble-timescape-migrate.pprof.port" -}}
{{ .Values.migrate.pprof.port }}
{{- end }}
