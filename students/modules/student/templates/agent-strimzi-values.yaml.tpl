# v.2 - Fixed HQ connection using env var substitution
serviceAccount:
  create: true
  name: lenses-agent-strimzi

rbacEnable: true
namespaceScope: true

lensesAgent:
  hq:
    agentKey:
      secret:
        type: "precreated"
        name: "lenses-agent-strimzi-key"
        key: "agent-key"

  provision:
    path: /mnt/provision-secrets
    connections:
      lensesHq:
        - name: lenses-hq
          version: 1
          tags: ['hq']
          configuration:
            server:
              value: lenses-hq.${namespace}.svc.cluster.local
            port:
              value: 10000
            agentKey:
              value: $${LENSESHQ_AGENT_KEY}
            sslEnabled:
              value: false

      kafka:
        - name: kafka
          version: 1
          tags: ['staging', 'strimzi']
          configuration:
            kafkaBootstrapServers:
              value:
                - PLAINTEXT://kafka-kafka-bootstrap.${namespace}.svc.cluster.local:9092

  storage:
    postgres:
      enabled: true
      host: "${postgres_host}"
      port: 5432
      username: lenses
      password: "${postgres_password}"
      database: lensesagent02
      schema: public

  sql:
    mode: IN_PROC

resources:
  requests:
    memory: 4Gi
  limits:
    memory: 5Gi
