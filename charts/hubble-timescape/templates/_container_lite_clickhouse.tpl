{{- define "hubble-timescape-clickhouse.containers" }}
- name: clickhouse
  image: {{ include "hubble-timescape.image" .Values.clickhouse.cluster.image | quote }}
  env:
    # The official ClickHouse Docker image now always setup a default-user.xml file under
    # `/etc/clickhouse-server/users.d`, which fails if we mount a RO volume at that path.
    # This environment variable skips this setup entirely, avoiding the error.
    # https://github.com/ClickHouse/ClickHouse/pull/75259
    - name: CLICKHOUSE_SKIP_USER_SETUP
      value: "1"
  {{- with .Values.lite.clickhouse.resources }}
  resources: {{- toYaml . | nindent 4 }}
  {{- end }}
  terminationMessagePolicy: FallbackToLogsOnError
  volumeMounts:
  - mountPath: "/etc/clickhouse-server/config.d/"
    name: clickhouse-config
    readOnly: true
  - mountPath: "/etc/clickhouse-server/users.d/"
    name: clickhouse-user
    readOnly: true
  - name: clickhouse-data
    mountPath: /var/lib/clickhouse
  {{- with .Values.lite.clickhouse.extraVolumeMounts }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
  readinessProbe:
    httpGet:
      path: /ping
      port: ch-http
      scheme: HTTP
  livenessProbe:
    httpGet:
      path: /ping
      port: ch-http
      scheme: HTTP
    initialDelaySeconds: 60
    periodSeconds: 3
  ports:
  - containerPort: 8123
    name: ch-http
    protocol: TCP
  - containerPort: 8001
    name: ch-metrics
    protocol: TCP
  {{- with .Values.lite.clickhouse.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
