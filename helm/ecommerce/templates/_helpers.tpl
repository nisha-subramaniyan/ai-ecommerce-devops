{{- define "shop.backendImage" -}}
{{ .Values.image.registry }}/shop-backend:{{ .Values.image.tag }}
{{- end -}}

{{- define "shop.frontendImage" -}}
{{ .Values.image.registry }}/shop-frontend:{{ .Values.image.tag }}
{{- end -}}

{{/* Pod spec shared by stable / canary / green backend Deployments. Args: dict "root" $ "image" "<img>" "version" "<tag>" */}}
{{- define "shop.backendContainer" -}}
- name: backend
  image: {{ .image }}
  imagePullPolicy: {{ .root.Values.image.pullPolicy }}
  ports:
    - { name: http, containerPort: {{ .root.Values.backend.port }} }
  env:
    - { name: PORT, value: "{{ .root.Values.backend.port }}" }
    - { name: NODE_ENV, value: production }
    - { name: APP_VERSION, value: "{{ .version }}" }
    - { name: ENABLE_CHAOS, value: "{{ .root.Values.backend.enableChaos }}" }
    - name: DB_PASSWORD
      valueFrom: { secretKeyRef: { name: shop-secret, key: DB_PASSWORD } }
    - name: DATABASE_URL
      value: postgres://shop:$(DB_PASSWORD)@shop-postgres:5432/shop
  livenessProbe:  { httpGet: { path: /health, port: http }, initialDelaySeconds: 10, periodSeconds: 10 }
  readinessProbe: { httpGet: { path: /ready,  port: http }, initialDelaySeconds: 5,  periodSeconds: 5 }
  resources:
    {{- toYaml .root.Values.backend.resources | nindent 4 }}
  securityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities: { drop: ["ALL"] }
{{- end -}}
