{{- define "hubble-timescape-trimmer.name" -}}
{{- .Chart.Name }}-trimmer
{{- end }}

{{- define "hubble-timescape-trimmer.labels" -}}
helm.sh/chart: {{ include "hubble-timescape.chart" . }}
{{ include "hubble-timescape-trimmer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hubble-timescape-trimmer.selectorLabels" -}}
{{- if not .Values.lite.enabled -}}
app.kubernetes.io/name: {{ include "hubble-timescape-trimmer.name" . }}
app.kubernetes.io/instance: {{ include "hubble-timescape-trimmer.name" . }}-{{ .Release.Name }}
app.kubernetes.io/component: trimmer
app.kubernetes.io/part-of: {{ .Chart.Name }}
{{- else -}}
{{ include "hubble-timescape-lite.selectorLabels" . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-trimmer.podLabels" -}}
{{ include "hubble-timescape-trimmer.selectorLabels" . }}
{{- with .Values.trimmer.podLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-trimmer.podAnnotations" -}}
{{- with .Values.trimmer.podAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-trimmer.volumes" -}}
{{ include "hubble-timescape-trimmer.clickhouse-certs-volume" . }}
{{- with .Values.trimmer.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-trimmer.clickhouse-certs-volume" }}
{{- $clickhouse := merge dict .Values.trimmer.clickhouse .Values.clickhouse (dict "tls" .Values.tls) -}}
{{ include "hubble-timescape.clickhouse-certs-volume" $clickhouse }}
{{- end }}
