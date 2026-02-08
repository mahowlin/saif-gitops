{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hubble-timescape.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "hubble-timescape.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "hubble-timescape-clickhouse.labels" -}}
helm.sh/chart: {{ include "hubble-timescape.chart" . }}
{{ include "hubble-timescape-clickhouse.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hubble-timescape-clickhouse.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}-clickhouse
app.kubernetes.io/instance: {{ .Chart.Name }}-clickhouse-{{ .Release.Name }}
app.kubernetes.io/component: database
app.kubernetes.io/part-of: {{ .Chart.Name }}
{{- end }}

{{- define "hubble-timescape-clickhouse.podLabels" -}}
{{ include "hubble-timescape-clickhouse.selectorLabels" . }}
{{- with .Values.clickhouse.cluster.podLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-clickhouse.annotations" -}}
{{- with .Values.clickhouse.cluster.podAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-dsn" -}}
{{- $dsnHost := "" }}
{{- if .client.dsn.host }}
{{- $dsnHost = .client.dsn.host }}
{{- else if .cluster.enabled }}
{{- $dsnHost = "clickhouse-hubble-timescape" }}
{{- else }}
{{- $dsnHost = "localhost" }}
{{- end }}
{{- $dsnPort := 9000 }}
{{- if .tls.enabled }}
{{- $dsnPort = 9440 }}
{{- end }}
{{- if .client.dsn.port }}
{{- $dsnPort = .client.dsn.port }}
{{- end }}
{{- $dsnDatabase := "hubble" }}
{{- if .client.dsn.database }}
{{- $dsnDatabase = .client.dsn.database }}
{{- end }}
{{- /*
NOTE:
We explicitly do NOT support multiple hosts as, in a Kubernetes context, the
ClickHouse service should be specified. In addition, options that are either
irrelevant in this context (such as connection_open_strategy) or too low level
(such as block_buffer_size) are not supported, on purpose.
*/ -}}
{{- $dsnExtra := list }}
{{- if .client.dsn.debug }}
{{- $dsnExtra = append $dsnExtra "debug=true" -}}
{{- end }}
{{- if .client.dsn.dialTimeout }}
{{- $dsnExtra = append $dsnExtra (print "dial_timeout=" .client.dsn.dialTimeout) -}}
{{- end }}
{{- if .client.dsn.readTimeout }}
{{- $dsnExtra = append $dsnExtra (print "read_timeout=" .client.dsn.readTimeout) -}}
{{- end }}
{{- if .client.dsn.compression.method }}
{{- $dsnExtra = append $dsnExtra (print "compress=" .client.dsn.compression.method) -}}
{{- end }}
{{- if .client.dsn.send_logs.level }}
{{- $dsnExtra = append $dsnExtra (print "send_logs_level=" .client.dsn.send_logs.level) -}}
{{- end }}
{{- if .tls.enabled }}
{{- $dsnExtra = append $dsnExtra "secure=true" }}
{{- /* TODO(chancez): add support for skip_verify */ -}}
{{- end }}
{{- $dsnExtra = gt (len $dsnExtra) 0 | ternary (print "?" (join "&" $dsnExtra)) "" -}}
{{- $dsn := print "clickhouse://" $dsnHost ":" $dsnPort "/" $dsnDatabase $dsnExtra -}}
{{- $dsn | trim }}
{{- end }}
{{/*
Render full image name from given values, e.g:
```
image:
  repository: quay.io/isovalent/my-image
  override:
  tag: latest
  useDigest: true
  digest: abcdefgh
```
Then `include "hubble-timescape.image" .Values.server.image`
will return `quay.io/isovalent/my-image:latest@abcdefgh`.
If `override` is included, only that value will be returned.
*/}}
{{- define "hubble-timescape.image" -}}
{{- $digest := (.useDigest | default false) | ternary (printf "@%s" .digest) "" -}}
{{- if .override -}}
{{- printf "%s" .override -}}
{{- else -}}
{{- printf "%s:%s%s" .repository .tag $digest -}}
{{- end -}}
{{- end -}}

{{/*
Converts a Go time.Duration into an integer number of seconds
*/}}
{{- define "durationSeconds" -}}
{{/* The value of `before` doesn't matter, we just need a date object to work with so we can extract a duration from it */}}
{{- $before := mustToDate "2006-01-02" "2017-12-31" }}
{{- $after := ($before | mustDateModify .) }}
{{- sub (unixEpoch $after) (unixEpoch $before) }}
{{- end }}

{{- define "hubble-timescape.ttl" -}}
{{ $defaultTTL := "336h0m0s" }} {{/* 2 weeks */}}
{{- if and .vals.lite.enabled .vals.lite.clickhouse.enabled .vals.lite.clickhouse.volumes.data }}
{{/* use lower default ttl when using timescape lite */}}
{{ $defaultTTL = "6h0m0s" }}
{{- else if and .vals.lite.enabled .vals.lite.clickhouse.enabled (not .vals.lite.clickhouse.volumes.data) }}
{{/* use even lower default ttl if there is no persistent clickhouse database */}}
{{ $defaultTTL = "1h0m0s" }}
{{- end }}
{{- .ttl | default .vals.migrate.ttl | default $defaultTTL }}
{{- end }}

{{- define "hubble-timescape.connection-logs.ttl" -}}
{{- $data := dict "ttl" .Values.migrate.connectionLogs.ttl "vals" .Values }}
{{- include "hubble-timescape.ttl" $data | trim }}
{{- end }}

{{- define "hubble-timescape.connection-logs.hourlyRollupAge" -}}
{{- $ttl := include "hubble-timescape.connection-logs.ttl" .}}
{{- $ttlSeconds := include "durationSeconds" $ttl | int }}
{{- /* Only enable hourly rollup if: it has been configured */}}
{{- if .Values.migrate.connectionLogs.hourlyRollupAge }}
{{- $hourlyRollupSeconds := include "durationSeconds" .Values.migrate.connectionLogs.hourlyRollupAge | int}}
{{- $dailyRollupSeconds := include "durationSeconds" .Values.migrate.connectionLogs.dailyRollupAge | int}}
{{- if and (ne $hourlyRollupSeconds 0) (lt $hourlyRollupSeconds (include "durationSeconds" "1h" | int)) }}
{{- fail (printf "migrate.connectionLogs.hourlyRollupAge (%s) must be at least 1 hour" .Values.migrate.connectionLogs.hourlyRollupAge) -}}
{{- end }}
{{- if and (ne $ttlSeconds 0) (ge $hourlyRollupSeconds $ttlSeconds) }}
{{- fail (printf "migrate.connectionLogs.hourlyRollupAge (%s) must be less than migrate.connectionLogs.ttl (%s)" .Values.migrate.connectionLogs.hourlyRollupAge $ttl) -}}
{{- end }}
{{- .Values.migrate.connectionLogs.hourlyRollupAge }}
{{- end }}
{{- end }}

{{- define "hubble-timescape.connection-logs.dailyRollupAge" -}}
{{- $ttl := include "hubble-timescape.connection-logs.ttl" .}}
{{- $ttlSeconds := include "durationSeconds" $ttl | int }}
{{- /* Only enable daily rollup if: it has been configured */}}
{{- if .Values.migrate.connectionLogs.dailyRollupAge }}
{{- $hourlyRollupSeconds := include "durationSeconds" .Values.migrate.connectionLogs.hourlyRollupAge | int}}
{{- $dailyRollupSeconds := include "durationSeconds" .Values.migrate.connectionLogs.dailyRollupAge | int}}
{{- if and (ne $dailyRollupSeconds 0) (lt $dailyRollupSeconds (include "durationSeconds" "24h" | int)) }}
{{- fail (printf "migrate.connectionLogs.dailyRollupAge (%s) must be at least 1 day" .Values.migrate.connectionLogs.dailyRollupAge) -}}
{{- end }}
{{- if and (ne $ttlSeconds 0) (ge $dailyRollupSeconds $ttlSeconds) }}
{{- fail (printf "migrate.connectionLogs.dailyRollupAge (%s) must be less than migrate.connectionLogs.ttl (%s)" .Values.migrate.connectionLogs.dailyRollupAge $ttl) -}}
{{- end }}
{{- if and (ne $dailyRollupSeconds 0) (ge $hourlyRollupSeconds $dailyRollupSeconds) }}
{{- fail (printf "migrate.connectionLogs.hourlyRollupAge (%s) must be less than migrate.connectionLogs.dailyRollupAge (%s)" .Values.migrate.connectionLogs.dailyRollupAge $ttl) -}}
{{- end }}
{{- .Values.migrate.connectionLogs.dailyRollupAge }}
{{- end }}
{{- end }}

{{- define "hubble-timescape.flows.ttl" -}}
{{- $data := dict "ttl" .Values.migrate.flows.ttl "vals" .Values }}
{{- include "hubble-timescape.ttl" $data | trim }}
{{- end }}

{{- define "hubble-timescape.k8s.ttl" -}}
{{- $data := dict "ttl" .Values.migrate.k8s.ttl "vals" .Values }}
{{- include "hubble-timescape.ttl" $data | trim }}
{{- end }}

{{- define "hubble-timescape.k8s.aggregation-ttl" -}}
{{- if .Values.migrate.k8s.aggregationTTL }}
{{- $k8sTTL := include "hubble-timescape.k8s.ttl" .}}
{{- $k8sTTLSeconds := include "durationSeconds" $k8sTTL | int }}
{{- $k8sAggregationTTLSeconds := include "durationSeconds" .Values.migrate.k8s.aggregationTTL | int}}
{{- if and (ne $k8sTTLSeconds 0) (ge $k8sAggregationTTLSeconds $k8sTTLSeconds) }}
{{- fail (printf "migrate.k8s.aggregationTTL (%s) must be less than migrate.k8s.ttl (%s)" .Values.migrate.k8s.aggregationTTL $k8sTTL) -}}
{{- end }}
{{- end }}
{{- .Values.migrate.k8s.aggregationTTL }}
{{- end }}

{{- define "hubble-timescape.assessment-reports.ttl" -}}
{{ $defaultTTL := "730h0m0s" }} {{/* 1 month */}}
{{- .Values.migrate.assessmentReports.ttl | default $defaultTTL }}
{{- end }}

{{- define "hubble-timescape.system-status.ttl" -}}
{{ $defaultTTL := "24h" }} {{/* 24 hours */}}
{{- .Values.migrate.systemStatus.ttl | default $defaultTTL }}
{{- end }}

{{- define "hubble-timescape-tracing.config" -}}
enable-tracing: {{ .tracing.enabled }}
log-traces: {{ .tracing.logTraces }}
{{- with .tracing.sampling }}
sampling: {{- . | toYaml | nindent 2 }}
{{- end }}
otlp-enabled: {{ .tracing.otlp.enabled }}
otlp-endpoint: {{ .tracing.otlp.endpoint | quote }}
otlp-transport: {{ .tracing.otlp.transport | quote }}
otlp-secure: {{ .tracing.otlp.tls.enabled | quote }}
{{- if and .tracing.otlp.tls.enabled .tracing.otlp.tls.ca.configMap.name }}
otlp-ca-files: "/var/lib/hubble-timescape/otlp-certs/ca.crt"
{{- end }}
otlp-url-path: {{ .tracing.otlp.urlPath | quote }}
{{- end -}}

{{- define "hubble-timescape.clickhouse-has-custom-ca" -}}
{{- if and .tls.enabled (or .tls.ca.configMap.name (and .cluster.enabled .tls.auto.enabled)) -}}
true
{{- end -}}
{{- end }}

{{- define "hubble-timescape.clickhouse-certs-volume" -}}
{{- if .tls.enabled }}
{{- if .tls.ca.configMap.name }}
- configMap:
    name: {{ .tls.ca.configMap.name }}
    items:
    - key: {{ .tls.ca.configMap.key }}
      path: clickhouse-ca.crt
  name: clickhouse-certs
{{- else if and .cluster.enabled .tls.auto.enabled }}
- secret:
    secretName: hubble-timescape-clickhouse-cert
    items:
    - key: ca.crt
      path: clickhouse-ca.crt
  name: clickhouse-certs
{{- end -}}
{{- end -}}
{{- end }}

{{- define "hubble-timescape.clickhouse-certs-volumemount" -}}
{{- if (include "hubble-timescape.clickhouse-has-custom-ca" .) -}}
- mountPath: "/var/lib/hubble-timescape/clickhouse-certs"
  name: clickhouse-certs
  readOnly: true
{{- end }}
{{- end }}

{{- define "hubble-timescape.probe" -}}
{{- if .vals.useKubernetesGrpcProbes }}
grpc:
  port: {{ .port }}
{{- else }}
tcpSocket:
  port: {{ .port }}
{{- end }}
{{- end }}

{{- define "hubble-timescape.probe-ingester" -}}
{{- $data := dict "port" .Values.ingester.healthCheckPort "vals" .Values }}
{{- include "hubble-timescape.probe" $data | trim }}
{{- end }}
{{- define "hubble-timescape.probe-server" -}}
{{- $data := dict "port" .Values.server.healthCheckPort "vals" .Values }}
{{- include "hubble-timescape.probe" $data | trim }}
{{- end }}
{{- define "hubble-timescape.probe-analyzer" -}}
{{- $data := dict "port" .Values.analyzer.healthCheckPort "vals" .Values }}
{{- include "hubble-timescape.probe" $data | trim }}
{{- end }}
{{- define "hubble-timescape.probe-lite" -}}
{{- $data := dict "port" .Values.lite.healthCheckPort "vals" .Values }}
{{- include "hubble-timescape.probe" $data | trim }}
{{- end }}
