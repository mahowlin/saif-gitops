{{- define "hubble-timescape-server.container" -}}
{{- $clickhouse := merge dict .Values.server.clickhouse .Values.clickhouse (dict "tls" .Values.tls) -}}
{{- $localClickhouse := and .Values.lite.enabled .Values.lite.clickhouse.enabled -}}
{{- $tls := merge dict .Values.server.tls .Values.tls -}}
- name: server
  securityContext:
    {{- toYaml .Values.server.securityContext | nindent 4 }}
  image: {{ include "hubble-timescape.image" .Values.server.image | quote }}
  imagePullPolicy: {{ .Values.server.image.pullPolicy }}
  terminationMessagePolicy: FallbackToLogsOnError
  command:
    - /usr/bin/hubble-timescape
  args:
    - serve
  env:
    {{- if not $localClickhouse }}
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_USERNAME
      value: {{ .Values.server.clickhouse.credentials.username | quote }}
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.server.clickhouse.credentials.secretName }}
          key: CLICKHOUSE_PASSWORD
    {{- end }}
    - name: HUBBLE_TIMESCAPE_DSN
      value: "{{- include "hubble-timescape-dsn" $clickhouse }}"
    {{- with .Values.server.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  ports:
    - name: server-health
      containerPort: {{ .Values.server.healthCheckPort }}
      protocol: TCP
    - name: server-grpc
      containerPort: {{ .Values.server.port }}
      protocol: TCP
    {{- if .Values.server.prometheus.enabled }}
    - name: server-metrics
      containerPort: {{ .Values.server.prometheus.port }}
      protocol: TCP
    {{- end }}
    {{- if .Values.server.pprof.enabled }}
    - name: server-pprof
      containerPort: {{ include "hubble-timescape-server.pprof.port" . }}
      protocol: TCP
    {{- end }}
  startupProbe:
    {{- include "hubble-timescape.probe-server" . | nindent 4 }}

    # The Timescape server implement a retry logic to connect to
    # ClickHouse with a timeout of 10s retrying 30 times before giving
    # up and crashing. Thus, it is expected to exit on its own after 5
    # minutes if it can't be ready. Since the default k8s periodSeconds
    # is 10s, a failureThreshold of 32 leave to the container a little
    # over 5m. See https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#when-should-you-use-a-startup-probe
    failureThreshold: 32
  readinessProbe:
    {{- include "hubble-timescape.probe-server" . | nindent 4 }}
  livenessProbe:
    {{- include "hubble-timescape.probe-server" . | nindent 4 }}
  resources:
    {{- toYaml .Values.server.resources | nindent 4 }}
  volumeMounts:
  - mountPath: "/etc/hubble-timescape"
    name: server-config
    readOnly: true
  {{- if $tls.enabled }}
  - mountPath: "/var/lib/hubble-timescape/tls"
    name: server-tls
    readOnly: true
  {{- end }}
  {{- if .Values.server.rbac.enabled }}
  - name: server-timescape-rbac-policy
    mountPath: /etc/timescape-rbac/policy
    readOnly: true
  {{- end }}
  {{- include "hubble-timescape.clickhouse-certs-volumemount" $clickhouse | nindent 2 }}
  {{- if and .Values.server.tracing.otlp.tls.enabled .Values.server.tracing.otlp.tls.ca.configMap.name }}
  - mountPath: "/var/lib/hubble-timescape/otlp-certs"
    name: server-otlp-certs
    readOnly: true
  {{- end }}
  {{- with .Values.server.extraVolumeMounts }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
