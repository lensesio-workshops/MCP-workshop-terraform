# v.2 - Fixed HQ connection using env var substitution
serviceAccount:
  create: true
  name: lenses-agent-fdd

rbacEnable: true
namespaceScope: true

lensesAgent:
  hq:
    agentKey:
      secret:
        type: "precreated"
        name: "lenses-agent-fdd-key"
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
          tags: ['dev', 'fdd']
          configuration:
            kafkaBootstrapServers:
              value:
                - PLAINTEXT://fast-data-dev.${namespace}.svc.cluster.local:9092

      confluentSchemaRegistry:
        - name: schema-registry
          version: 1
          tags: ['dev', 'fdd']
          configuration:
            schemaRegistryUrls:
              value:
                - http://fast-data-dev.${namespace}.svc.cluster.local:8081

      connect:
        - name: connect
          version: 1
          tags: ['dev', 'fdd']
          configuration:
            workers:
              value:
                - http://fast-data-dev.${namespace}.svc.cluster.local:8083

  storage:
    postgres:
      enabled: true
      host: "${postgres_host}"
      port: 5432
      username: lenses
      password: "${postgres_password}"
      database: lensesagent01
      schema: public

  sql:
    mode: IN_PROC

resources:
  requests:
    memory: 4Gi
  limits:
    memory: 5Gi
