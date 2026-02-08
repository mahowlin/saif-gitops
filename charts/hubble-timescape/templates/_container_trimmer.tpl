{{- define "hubble-timescape-trimmer.container" -}}
{{- $clickhouse := merge dict .Values.trimmer.clickhouse .Values.clickhouse (dict "tls" .Values.tls) -}}
{{- $localClickhouse := and .Values.lite.enabled .Values.lite.clickhouse.enabled -}}
- name: trimmer
  securityContext:
    {{- toYaml .Values.trimmer.securityContext | nindent 4 }}
  image: {{ include "hubble-timescape.image" .Values.trimmer.image | quote }}
  imagePullPolicy: {{ .Values.trimmer.image.pullPolicy }}
  terminationMessagePolicy: FallbackToLogsOnError
  command:
    - /usr/bin/hubble-timescape
    - trim
    - --flows-count={{ .Values.trimmer.flowsCount | int }}
    - --timeout={{ .Values.trimmer.timeout | default (printf "%.fm" .Values.trimmer.trimIntervalMinutes) }}
    {{- if (include "hubble-timescape.clickhouse-has-custom-ca" $clickhouse) }}
    - --tls-clickhouse-ca-files=/var/lib/hubble-timescape/clickhouse-certs/clickhouse-ca.crt
    {{- end }}
  env:
    {{- if not $localClickhouse }}
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_USERNAME
      value: {{ .Values.trimmer.clickhouse.credentials.username | quote }}
    - name: HUBBLE_TIMESCAPE_CLICKHOUSE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.trimmer.clickhouse.credentials.secretName }}
          key: CLICKHOUSE_PASSWORD
    {{- end }}
    - name: HUBBLE_TIMESCAPE_DSN
      value: "{{- include "hubble-timescape-dsn" $clickhouse }}"
  resources:
    {{- toYaml .Values.trimmer.resources | nindent 4 }}
  volumeMounts:
  {{- include "hubble-timescape.clickhouse-certs-volumemount" $clickhouse | nindent 2 }}
  {{- with .Values.trimmer.extraVolumeMounts }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end -}}
