{{/*
Chart name, truncated for use in Kubernetes object names.
*/}}
{{- define "pingpong.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name, e.g. "<release>-pingpong" or just "pingpong"
when the release is named the same as the chart.
*/}}
{{- define "pingpong.fullname" -}}
{{- if eq .Release.Name .Chart.Name }}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels applied to every resource.
*/}}
{{- define "pingpong.labels" -}}
app.kubernetes.io/name: {{ include "pingpong.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
Selector labels, used to match Pods to the Deployment/Service.
*/}}
{{- define "pingpong.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pingpong.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
