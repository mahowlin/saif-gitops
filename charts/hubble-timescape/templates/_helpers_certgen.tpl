{{- define "hubble-timescape-certgen.name" -}}
{{- .Chart.Name }}-certgen
{{- end }}

{{- define "hubble-timescape-certgen.labels" -}}
helm.sh/chart: {{ include "hubble-timescape.chart" . }}
{{ include "hubble-timescape-certgen.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hubble-timescape-certgen.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hubble-timescape-certgen.name" . }}
app.kubernetes.io/instance: {{ include "hubble-timescape-certgen.name" . }}-{{ .Release.Name }}
app.kubernetes.io/component: certgen
app.kubernetes.io/part-of: {{ .Chart.Name }}
{{- end }}

{{- define "hubble-timescape-certgen.podLabels" -}}
{{ include "hubble-timescape-certgen.selectorLabels" . }}
{{- with .Values.certgen.podLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-certgen.podAnnotations" -}}
{{- with .Values.certgen.podAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "hubble-timescape-certgen.enabled" -}}
{{- include "hubble-timescape-certgen.server-tls-enabled" . -}}
{{- include "hubble-timescape-certgen.ingester-tls-enabled" . -}}
{{- include "hubble-timescape-certgen.clickhouse-tls-enabled" . -}}
{{- end }}

{{- define "hubble-timescape-certgen.server-tls-enabled" -}}
{{- if .Values.server.enabled -}}
{{- $tls := merge dict .Values.server.tls .Values.tls -}}
{{- if and $tls.enabled $tls.auto.enabled (eq $tls.auto.method "cronJob") -}}
true
{{- end -}}
{{- end -}}
{{- end }}

{{- define "hubble-timescape-certgen.ingester-tls-enabled" -}}
{{- if or (eq (include "hubble-timescape-ingester.server.http.enabled" .) "true") (eq (include "hubble-timescape-ingester.server.grpc.enabled" .) "true") }}
{{- $tls := merge dict .Values.ingester.server.tls .Values.tls -}}
{{- if and $tls.enabled $tls.auto.enabled (eq $tls.auto.method "cronJob") -}}
true
{{- end -}}
{{- end -}}
{{- end }}

{{- define "hubble-timescape-certgen.clickhouse-tls-enabled" -}}
{{- if and .Values.clickhouse.cluster.enabled }}
{{- $tls := merge dict .Values.clickhouse.tls .Values.tls -}}
{{- if and $tls.enabled $tls.auto.enabled (eq $tls.auto.method "cronJob") -}}
true
{{- end -}}
{{- end -}}
{{- end }}

{{- define "hubble-timescape-certgen.jobSpec" -}}
backoffLimit: 10
template:
  metadata:
    {{- with include "hubble-timescape-certgen.podAnnotations" . }}
    annotations:
      {{- . | nindent 6 }}
    {{- end }}
    labels:
      {{- include "hubble-timescape-certgen.podLabels" . | nindent 6 }}
  spec:
    {{- $serviceAccountName := .Values.certgen.serviceAccount.name }}
    {{- if .useInitSA }}
    {{- $serviceAccountName = print $serviceAccountName "-init" }}
    {{- end }}
    serviceAccountName: {{ $serviceAccountName | quote }}
    {{- with .Values.certgen.image.pullSecrets }}
    imagePullSecrets:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    securityContext:
      {{- toYaml .Values.certgen.podSecurityContext | nindent 6 }}
    priorityClassName: {{ .Values.certgen.priorityClassName }}
    restartPolicy: OnFailure
    containers: {{- include "hubble-timescape-certgen.container" . | nindent 6 }}
    {{- with .Values.certgen.nodeSelector }}
    nodeSelector:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.certgen.affinity }}
    affinity:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.certgen.tolerations }}
    tolerations:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.certgen.extraVolumes }}
    volumes:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end -}}

{{- define "hubble-timescape-certgen.container" -}}
{{- $certValidityStr := printf "%dh" (mul 90 24) -}}
- name: certgen
  securityContext:
    {{- toYaml .Values.certgen.securityContext | nindent 4 }}
  image: {{ include "hubble-timescape.image" .Values.certgen.image | quote }}
  imagePullPolicy: {{ .Values.certgen.image.pullPolicy }}
  terminationMessagePolicy: FallbackToLogsOnError
  command:
    - "/usr/bin/cilium-certgen"
  # Because this is executed as a job, we pass the values as command
  # line args instead of via config map. This allows users to inspect
  # the values used in past runs by inspecting the completed pod.
  args:
    {{- if .Values.debug }}
    - "--debug"
    {{- end }}
    - "--ca-generate"
    - "--ca-reuse-secret"
    - "--ca-secret-namespace={{ .Release.Namespace }}"
    - "--ca-secret-name=hubble-timescape-ca"
    - "--ca-common-name=Hubble Timescape CA"
  env:
    - name: CILIUM_CERTGEN_CONFIG
      value: |
        certs:
        {{- if (include "hubble-timescape-certgen.server-tls-enabled" .) }}
          - name: hubble-timescape-server-cert
            namespace: {{ .Release.Namespace }}
            commonName: hubble-timescape
            hosts:
            - "localhost"
            - "hubble-timescape"
            - "hubble-timescape.{{ .Release.Namespace }}"
            - "hubble-timescape.{{ .Release.Namespace }}.svc.cluster.local"
            usage:
            - server auth
            validity: {{ $certValidityStr }}
        {{- end }}
        {{- if (include "hubble-timescape-certgen.ingester-tls-enabled" .) }}
          - name:  hubble-timescape-ingester-server-cert
            namespace: {{ .Release.Namespace }}
            commonName: hubble-timescape-ingester
            hosts:
            - "hubble-timescape-ingester"
            - "hubble-timescape-ingester.{{ .Release.Namespace }}"
            - "hubble-timescape-ingester.{{ .Release.Namespace }}.svc.cluster.local"
            - "hubble-timescape-export"
            - "hubble-timescape-export.{{ .Release.Namespace }}"
            - "hubble-timescape-export.{{ .Release.Namespace }}.svc.cluster.local"
            usage:
            - server auth
            validity: {{ $certValidityStr }}
        {{- end }}
        {{- if (include "hubble-timescape-certgen.clickhouse-tls-enabled" .) }}
          - name: hubble-timescape-clickhouse-cert
            namespace: {{ .Release.Namespace }}
            commonName: clickhouse-hubble-timescape
            hosts:
            - "clickhouse-hubble-timescape"
            - "clickhouse-hubble-timescape.{{ .Release.Namespace }}"
            - "clickhouse-hubble-timescape.{{ .Release.Namespace }}.svc.cluster.local"
            usage:
            - server auth
            validity: {{ $certValidityStr }}
        {{- end }}
  resources:
    {{- toYaml .Values.certgen.resources | nindent 4 }}
  volumeMounts:
  {{- with .Values.certgen.extraVolumeMounts }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end -}}
