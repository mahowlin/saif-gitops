{{- define "hubble-timescape-ui.container" -}}
{{- $tls := merge dict .Values.server.tls .Values.tls -}}
- name: ui
  securityContext:
    {{- toYaml .Values.ui.securityContext | nindent 4 }}
  image: {{ include "hubble-timescape.image" .Values.ui.image | quote }}
  imagePullPolicy: {{ .Values.ui.image.pullPolicy }}
  terminationMessagePolicy: FallbackToLogsOnError
  command:
    - /usr/bin/hubble-timescape-ui
  args:
    - serve
  env:
    {{- if (eq (include "hubble-timescape-ui.auth.enabled" .) "true") }}
    {{- if not .Values.ui.auth.oidc.clientAssertionFile }}
    - name: HUBBLE_TIMESCAPE_UI_OAUTH2__OIDC__CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: {{ .Values.ui.auth.oidc.clientSecret.secretName }}
          key:  {{ .Values.ui.auth.oidc.clientSecret.secretKey }}
    {{- end }}
    - name: HUBBLE_TIMESCAPE_UI_SESSION_KEY
      valueFrom:
        secretKeyRef:
          name: {{ .Values.ui.auth.sessionKey.secretName }}
          key:  {{ .Values.ui.auth.sessionKey.secretKey }}
    {{- end }}
    {{- with .Values.ui.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  ports:
    - name: ui-http
      containerPort: {{ .Values.ui.port }}
    {{- if .Values.ui.prometheus.enabled }}
    - name: ui-metrics
      containerPort: {{ include "hubble-timescape-ui.prometheus.port" . }}
      protocol: TCP
    {{- end }}
    {{- if .Values.ui.pprof.enabled }}
    - name: ui-pprof
      containerPort: {{ include "hubble-timescape-ui.pprof.port" . }}
      protocol: TCP
    {{- end }}
  livenessProbe:
    httpGet:
      path: /healthz
      port: ui-http
      scheme: HTTP
    initialDelaySeconds: 0
    timeoutSeconds: 1
  resources:
    {{- toYaml .Values.ui.resources | nindent 4 }}
  volumeMounts:
  - mountPath: /etc/hubble-timescape-ui
    name: ui-config
    readOnly: true
  {{- if $tls.enabled }}
  - mountPath: /var/lib/hubble-timescape-ui/tls
    name: ui-tls
    readOnly: true
  {{- end }}
  {{- with .Values.ui.extraVolumeMounts }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
