serviceAccount:
  create: true
  name: lenses-hq

rbacEnable: true
namespaceScope: true

ingress:
  http:
    enabled: true
    host: "${hostname}"
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/certificate-arn: "${acm_certificate_arn}"
      alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06

lensesHq:
  auth:
    administrators:
      - "admin"
    users:
      - username: admin
        password: "${admin_password_hash}"

  storage:
    postgres:
      enabled: true
      host: "${postgres_host}"
      port: 5432
      username: lenses
      database: lenseshq
      schema: public
      tls: false
      passwordSecret:
        type: "precreated"
        name: "lenses-postgres-password"
        key: "password"

  license:
    stringData: "${lenses_license}"
    acceptEULA: true

resources:
  requests:
    memory: 2Gi
  limits:
    memory: 4Gi
