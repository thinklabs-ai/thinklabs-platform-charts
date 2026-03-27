{{- define "mlflow.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mlflow.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "mlflow.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "mlflow.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "mlflow.fullname" . -}}
{{- end -}}
{{- else -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
default
{{- end -}}
{{- end -}}
{{- end -}}