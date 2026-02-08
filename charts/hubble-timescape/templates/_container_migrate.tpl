{{- define "hubble-timescape-migrate.container" -}}
{{- $clickhouseIngester := merge dict .Values.ingester.clickhouse .Values.clickhouse (dict "tls" .Values.tls) -}}
{{- $clickhouseMigrate := merge dict .Values.migrate.clickhouse .Values.clickhouse (dict "tls" .Values.tls) -}}
- name: migrate
  securityContext:
    {{- toYaml .Values.migrate.securityContext | nindent 4 }}
  image: {{ include "hubble-timescape.image" .Values.migrate.image | quote }}
  imagePullPolicy: {{ .Values.migrate.image.pullPolicy }}
  terminationMessagePolicy: FallbackToLogsOnError
  command:
    - /usr/bin/hubble-timescape
    - migrate
  env:
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_USERNAME
      value: {{ .Values.migrate.clickhouse.credentials.username | quote }}
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.migrate.clickhouse.credentials.secretName }}
          key: CLICKHOUSE_PASSWORD
    - name: HUBBLE_TIMESCAPE_DSN
      value: "{{- include "hubble-timescape-dsn" $clickhouseMigrate }}"
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_NODES_COUNT
      {{- if .Values.clickhouse.cluster.enabled }}
      value: "1"
      {{- else }}
      value: "0"
      {{- end }}
  resources:
    {{- toYaml .Values.migrate.resources | nindent 4 }}
  volumeMounts:
  - mountPath: "/etc/hubble-timescape"
    name: migrate-config
    readOnly: true
  # using $clickhouseIngester because the volume is using $clickhouseIngester
  {{- include "hubble-timescape.clickhouse-certs-volumemount" $clickhouseIngester | nindent 2 }}
  {{- with .Values.migrate.extraVolumeMounts }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end -}}
