{{- define "hubble-timescape-ingester.container" -}}
{{- $clickhouseIngester := merge dict .Values.ingester.clickhouse .Values.clickhouse (dict "tls" .Values.tls) -}}
{{- $pushIngestionOnly := and (not .Values.ingester.bucket.uri) (not .Values.config.buckets) -}}
{{- $tls := merge dict .Values.ingester.server.tls .Values.tls -}}
- name: ingester
  securityContext:
    {{- toYaml .Values.ingester.securityContext | nindent 4 }}
  image: {{ include "hubble-timescape.image" .Values.ingester.image | quote }}
  imagePullPolicy: {{ .Values.ingester.image.pullPolicy }}
  terminationMessagePolicy: FallbackToLogsOnError
  command:
    - /usr/bin/hubble-timescape
    - ingest
  {{- if not $pushIngestionOnly }}
  envFrom:
    # needed for blob storage credentials env-vars
    - secretRef:
        name: {{ .Values.ingester.clickhouse.credentials.secretName }}
  {{- end }}
  env:
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_USERNAME
      value: {{ .Values.ingester.clickhouse.credentials.username | quote }}
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.ingester.clickhouse.credentials.secretName }}
          key: CLICKHOUSE_PASSWORD
    - name: GOOGLE_APPLICATION_CREDENTIALS
      value: /var/lib/hubble-timescape/secrets/google-credentials.json
    - name: HUBBLE_TIMESCAPE_DSN
      value: "{{- include "hubble-timescape-dsn" $clickhouseIngester }}"
    {{- if and (eq (include "hubble-timescape-ingester.server.http.enabled" .) "true") (eq .Values.ingester.server.authMethod "basic-auth") }}
    - name: HUBBLE_TIMESCAPE_PUSH_API_USERNAME
      value: {{ .Values.ingester.server.http.basicAuth.username | quote }}
    - name: HUBBLE_TIMESCAPE_PUSH_API_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.ingester.server.http.basicAuth.secretName }}
          key: PUSH_API_PASSWORD
    {{- end }}
    {{- with .Values.ingester.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  readinessProbe:
    {{- include "hubble-timescape.probe-ingester" . | nindent 4 }}
  resources:
    {{- toYaml .Values.ingester.resources | nindent 4 }}
  ports:
    - name: ingest-health
      containerPort: {{ .Values.ingester.healthCheckPort }}
      protocol: TCP
    - name: push
      containerPort: 4260 # TODO: do not hardcode
      protocol: TCP
    - name: stream
      containerPort: 4261 # TODO: do not hardcode
      protocol: TCP
    {{- if .Values.ingester.prometheus.enabled }}
    - name: ingest-metrics
      containerPort: {{ include "hubble-timescape-ingester.prometheus.port" . }}
      protocol: TCP
    {{- end }}
    {{- if .Values.ingester.pprof.enabled }}
    - name: ingest-pprof
      containerPort: {{ include "hubble-timescape-ingester.pprof.port" . }}
      protocol: TCP
    {{- end }}
  volumeMounts:
  - mountPath: "/etc/hubble-timescape"
    name: ingester-config
    readOnly: true
  {{- if and (or (eq (include "hubble-timescape-ingester.server.http.enabled" .) "true") (eq (include "hubble-timescape-ingester.server.grpc.enabled" .) "true")) $tls.enabled }}
  - mountPath: "/var/lib/hubble-timescape/tls"
    name: ingester-server-tls
    readOnly: true
  {{- end }}
  {{- if not $pushIngestionOnly }}
  {{/* ingester-secret volume is only needed for GCS */}}
  - mountPath: "/var/lib/hubble-timescape/secrets"
    name: ingester-secret
    readOnly: true
  {{- end }}
  {{- include "hubble-timescape.clickhouse-certs-volumemount" $clickhouseIngester | nindent 2 }}
  {{- if .Values.ingester.bucket.tls.ca.configMap.name }}
  - mountPath: "/var/lib/hubble-timescape/bucket-certs"
    name: ingester-bucket-certs
    readOnly: true
  {{- end }}
  {{- with .Values.ingester.extraVolumeMounts }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end -}}
