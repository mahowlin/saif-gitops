{{- define "hubble-timescape-lite.container" -}}
{{- $clickhouse := merge dict .Values.lite.clickhouse .Values.clickhouse -}}
{{- $localClickhouse := and .Values.lite.enabled .Values.lite.clickhouse.enabled -}}
{{- $serverTLS := merge dict .Values.server.tls .Values.tls -}}
{{- $ingesterTLS := merge dict .Values.ingester.server.tls .Values.tls -}}
{{- $uiTLS := merge dict .Values.server.tls .Values.tls -}}
{{- $pushIngestionOnly := and (not .Values.ingester.bucket.uri) (not .Values.config.buckets) -}}
- name: timescape
  securityContext:
    {{- toYaml .Values.lite.securityContext | nindent 4 }}
  image: {{ include "hubble-timescape.image" .Values.lite.image | quote }}
  imagePullPolicy: {{ .Values.lite.image.pullPolicy }}
  terminationMessagePolicy: FallbackToLogsOnError
  command:
    - /usr/bin/hubble-timescape
  args:
    - run
  {{- if or (not $localClickhouse) (not $pushIngestionOnly) }}
  envFrom:
    # needed for blob storage credentials env-vars
    - secretRef:
        name: {{ .Values.ingester.clickhouse.credentials.secretName }}
  {{- end }}
  env:
    {{- if not $localClickhouse }}
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_USERNAME
      value: {{ .Values.lite.clickhouse.credentials.username | quote }}
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.lite.clickhouse.credentials.secretName }}
          key: CLICKHOUSE_PASSWORD
    {{- else }}
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_USERNAME
      value: timescape_lite
    {{- end }}
    - name: HUBBLE_TIMESCAPE_DSN
      value: "{{- include "hubble-timescape-dsn" $clickhouse }}"
    - name: GOOGLE_APPLICATION_CREDENTIALS
      value: /var/lib/hubble-timescape/secrets/google-credentials.json
    {{- if (eq .Values.ingester.server.authMethod "basic-auth") }}
    - name: HUBBLE_TIMESCAPE_INGESTER__PUSH_API_USERNAME
      value: {{ .Values.ingester.server.http.basicAuth.username | quote }}
    - name: HUBBLE_TIMESCAPE_INGESTER__PUSH_API_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.ingester.server.http.basicAuth.secretName }}
          key: PUSH_API_PASSWORD
    {{- end }}
    {{- with .Values.server.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- with .Values.ingester.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- if .Values.ui.enabled }}
    {{- if (eq (include "hubble-timescape-ui.auth.enabled" .) "true") }}
    {{- if not .Values.ui.auth.oidc.clientAssertionFile }}
    - name: HUBBLE_TIMESCAPE_UI__OAUTH2__OIDC__CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: {{ .Values.ui.auth.oidc.clientSecret.secretName }}
          key:  {{ .Values.ui.auth.oidc.clientSecret.secretKey }}
    {{- end }}
    - name: HUBBLE_TIMESCAPE_UI__SESSION_KEY
      valueFrom:
        secretKeyRef:
          name: {{ .Values.ui.auth.sessionKey.secretName }}
          key:  {{ .Values.ui.auth.sessionKey.secretKey }}
    {{- end }}
    {{- with .Values.ui.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- end }}
  ports:
    - name: health-grpc
      containerPort: {{ .Values.lite.healthCheckPort }}
      protocol: TCP
    - name: server-grpc
      containerPort: {{ .Values.server.port }}
      protocol: TCP
    - name: push
      containerPort: {{ include "hubble-timescape-ingester.service.push.port" . }}
      protocol: TCP
    - name: stream
      containerPort: {{ include "hubble-timescape-ingester.service.stream.port" . }}
      protocol: TCP
    {{- if .Values.ui.enabled }}
    - name: ui-http
      containerPort: {{ .Values.ui.port }}
      protocol: TCP
    {{- end }}
    {{- if .Values.lite.prometheus.enabled }}
    - name: metrics
      containerPort: {{ .Values.lite.prometheus.port }}
      protocol: TCP
    {{- end }}
    {{- if .Values.lite.pprof.enabled }}
    - name: pprof
      containerPort: {{ .Values.lite.pprof.port }}
      protocol: TCP
    {{- end }}
  startupProbe:
    {{- include "hubble-timescape.probe-lite" . | nindent 4 }}

    # The Timescape server implement a retry logic to connect to
    # ClickHouse with a timeout of 10s retrying 30 times before giving
    # up and crashing. Thus, it is expected to exit on its own after 5
    # minutes if it can't be ready. Since the default k8s periodSeconds
    # is 10s, a failureThreshold of 32 leave to the container a little
    # over 5m. See https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#when-should-you-use-a-startup-probe
    failureThreshold: 32
  readinessProbe:
    {{- include "hubble-timescape.probe-lite" . | nindent 4 }}
  livenessProbe:
    {{- include "hubble-timescape.probe-lite" . | nindent 4 }}
  resources:
    {{- toYaml .Values.lite.resources | nindent 4 }}
  volumeMounts:
  - mountPath: "/etc/hubble-timescape"
    name: config
    readOnly: true
  {{- if or $serverTLS.enabled $ingesterTLS.enabled}}
  - mountPath: "/var/lib/hubble-timescape/tls"
    name: tls
    readOnly: true
  {{- end }}
  {{- if and .Values.ui.enabled $uiTLS.enabled }}
  - mountPath: /var/lib/hubble-timescape-ui/tls
    name: ui-tls
    readOnly: true
  {{- end }}
  {{- if .Values.server.rbac.enabled }}
  - name: server-timescape-rbac-policy
    mountPath: /etc/timescape-rbac/policy
    readOnly: true
  {{- end }}
  {{- include "hubble-timescape.clickhouse-certs-volumemount" $clickhouse | nindent 2 }}
  {{- if and .Values.lite.tracing.otlp.tls.enabled .Values.lite.tracing.otlp.tls.ca.configMap.name }}
  - mountPath: "/var/lib/hubble-timescape/otlp-certs"
    name: server-otlp-certs
    readOnly: true
  {{- end }}
  {{- if .Values.ingester.bucket.tls.ca.configMap.name }}
  - mountPath: "/var/lib/hubble-timescape/bucket-certs"
    name: ingester-bucket-certs
    readOnly: true
  {{- end }}
  {{- if not $pushIngestionOnly }}
  {{/* ingester-secret volume is only needed for GCS */}}
  - mountPath: "/var/lib/hubble-timescape/secrets"
    name: ingester-secret
    readOnly: true
  {{- end }}
  {{- with .Values.lite.extraVolumeMounts }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
