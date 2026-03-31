{{/*
Expand the name of the chart.
*/}}
{{- define "claude-code-env.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "claude-code-env.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "claude-code-env.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "claude-code-env.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "claude-code-env.selectorLabels" -}}
app.kubernetes.io/name: {{ include "claude-code-env.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Teleport node name — uses .Values.teleport.nodeName if set, otherwise auto-generates.
*/}}
{{- define "claude-code-env.nodeName" -}}
{{- if .Values.teleport.nodeName }}
{{- .Values.teleport.nodeName }}
{{- else }}
{{- printf "claude-code-%s" .Release.Name }}
{{- end }}
{{- end }}
