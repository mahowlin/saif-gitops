{{- define "hubble-timescape-analyzer.container" -}}
{{- $clickhouse := merge dict .Values.analyzer.clickhouse .Values.clickhouse (dict "tls" .Values.tls) -}}
{{- $localClickhouse := and .Values.lite.enabled .Values.lite.clickhouse.enabled -}}
- name: analyzer
  securityContext:
    {{- toYaml .Values.analyzer.securityContext | nindent 4 }}
  image: {{ include "hubble-timescape.image" .Values.analyzer.image | quote }}
  imagePullPolicy: {{ .Values.analyzer.image.pullPolicy }}
  terminationMessagePolicy: FallbackToLogsOnError
  command:
    - /usr/bin/hubble-timescape
  args:
    - analyze
  env:
    {{- if not $localClickhouse }}
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_USERNAME
      value: {{ .Values.analyzer.clickhouse.credentials.username | quote }}
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.analyzer.clickhouse.credentials.secretName }}
          key: CLICKHOUSE_PASSWORD
    {{- end }}
    - name: HUBBLE_TIMESCAPE_DSN
      value: "{{- include "hubble-timescape-dsn" $clickhouse }}"
    {{- with .Values.analyzer.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  ports:
    - name: analyze-health
      containerPort: {{ .Values.analyzer.healthCheckPort }}
      protocol: TCP
    {{- if .Values.analyzer.prometheus.enabled }}
    - name: analyze-metrics
      containerPort: {{ include "hubble-timescape-analyzer.prometheus.port" . }}
      protocol: TCP
    {{- end }}
    {{- if .Values.analyzer.pprof.enabled }}
    - name: analyze-pprof
      containerPort: {{ include "hubble-timescape-analyzer.pprof.port" . }}
      protocol: TCP
    {{- end }}
  startupProbe:
    {{- include "hubble-timescape.probe-analyzer" . | nindent 4 }}

    # The Timescape analyzer implement a retry logic to connect to
    # ClickHouse with a timeout of 10s retrying 30 times before giving
    # up and crashing. Thus, it is expected to exit on its own after 5
    # minutes if it can't be ready. Since the default k8s periodSeconds
    # is 10s, a failureThreshold of 32 leave to the container a little
    # over 5m. See https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#when-should-you-use-a-startup-probe
    failureThreshold: 32
  readinessProbe:
    {{- include "hubble-timescape.probe-analyzer" . | nindent 4 }}
  livenessProbe:
    {{- include "hubble-timescape.probe-analyzer" . | nindent 4 }}
  resources:
    {{- toYaml .Values.analyzer.resources | nindent 4 }}
  volumeMounts:
  - mountPath: "/etc/hubble-timescape"
    name: analyzer-config
    readOnly: true
  {{- include "hubble-timescape.clickhouse-certs-volumemount" $clickhouse | nindent 2 }}
  {{- with .Values.analyzer.extraVolumeMounts }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
