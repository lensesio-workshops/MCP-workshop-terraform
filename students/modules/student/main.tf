# v. 8 - Added fin-gen data generators for FDD and Strimzi
# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------
locals {
  student_password      = "$tudent${var.student_id}"
  hq_hostname           = "student${var.student_id}-hq.${var.domain_name}"
  env_dev_name          = "financial-transactions-dev"
  env_staging_name      = "financial-transactions-staging"
}

# Generate bcrypt hash for student password
resource "bcrypt_hash" "admin_password" {
  cleartext = local.student_password
  cost      = 12
}

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "student" {
  metadata {
    name = var.namespace
    labels = {
      student = var.student_id
    }
  }
}

# -----------------------------------------------------------------------------
# PostgreSQL Secret
# -----------------------------------------------------------------------------
resource "kubernetes_secret" "postgres_password" {
  metadata {
    name      = "lenses-postgres-password"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  data = {
    password = var.postgres_password
  }
}

# -----------------------------------------------------------------------------
# PostgreSQL StatefulSet
# -----------------------------------------------------------------------------
resource "kubernetes_stateful_set" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  spec {
    service_name = "postgres"
    replicas     = 1

    selector {
      match_labels = {
        app = "postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:15"

          env {
            name  = "POSTGRES_DB"
            value = "lenses"
          }
          env {
            name  = "POSTGRES_USER"
            value = "lenses"
          }
          env {
            name  = "POSTGRES_PASSWORD"
            value = var.postgres_password
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          port {
            container_port = 5432
          }

          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }

          resources {
            requests = {
              memory = "512Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "500m"
            }
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "postgres-data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "gp2"
        resources {
          requests = {
            storage = "5Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  spec {
    selector = {
      app = "postgres"
    }

    port {
      port = 5432
    }
  }
}

# -----------------------------------------------------------------------------
# PostgreSQL Database Init Job
# -----------------------------------------------------------------------------
resource "kubernetes_job" "postgres_init" {
  metadata {
    name      = "postgres-init"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  spec {
    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"

        container {
          name  = "init"
          image = "postgres:15"

          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            until pg_isready -h postgres -U lenses; do
              echo "Waiting for postgres..."
              sleep 2
            done
            
            PGPASSWORD=${var.postgres_password} psql -h postgres -U lenses -d lenses -c "CREATE DATABASE lenseshq;" || true
            PGPASSWORD=${var.postgres_password} psql -h postgres -U lenses -d lenses -c "CREATE DATABASE lensesagent01;" || true
            PGPASSWORD=${var.postgres_password} psql -h postgres -U lenses -d lenses -c "CREATE DATABASE lensesagent02;" || true
            
            echo "Databases created successfully"
          EOT
          ]
        }
      }
    }

    backoff_limit = 4
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
  }

  depends_on = [kubernetes_stateful_set.postgres, kubernetes_service.postgres]
}

# -----------------------------------------------------------------------------
# Fast Data Dev
# -----------------------------------------------------------------------------
resource "kubernetes_deployment" "fast_data_dev" {
  metadata {
    name      = "fast-data-dev"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "fast-data-dev"
      }
    }

    template {
      metadata {
        labels = {
          app = "fast-data-dev"
        }
      }

      spec {
        container {
          name  = "fast-data-dev"
          image = "lensesio/fast-data-dev:latest"

          env {
            name  = "ADV_HOST"
            value = "fast-data-dev.${var.namespace}.svc.cluster.local"
          }
          env {
            name  = "SAMPLEDATA"
            value = "1"
          }

          port {
            container_port = 9092
          }
          port {
            container_port = 8081
          }
          port {
            container_port = 8082
          }
          port {
            container_port = 8083
          }
          port {
            container_port = 2181
          }
          port {
            container_port = 3030
          }

          resources {
            requests = {
              memory = "4Gi"
              cpu    = "2"
            }
            limits = {
              memory = "6Gi"
              cpu    = "4"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "fast_data_dev" {
  metadata {
    name      = "fast-data-dev"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  spec {
    selector = {
      app = "fast-data-dev"
    }

    port {
      name = "kafka"
      port = 9092
    }
    port {
      name = "schema-registry"
      port = 8081
    }
    port {
      name = "rest-proxy"
      port = 8082
    }
    port {
      name = "connect"
      port = 8083
    }
    port {
      name = "zookeeper"
      port = 2181
    }
    port {
      name = "webui"
      port = 3030
    }
  }
}

# -----------------------------------------------------------------------------
# Strimzi Kafka (KRaft mode - no ZooKeeper)
# -----------------------------------------------------------------------------
resource "kubernetes_manifest" "strimzi_kafka" {
  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaNodePool"
    metadata = {
      name      = "dual-role"
      namespace = kubernetes_namespace.student.metadata[0].name
      labels = {
        "strimzi.io/cluster" = "kafka"
      }
    }
    spec = {
      replicas = 1
      roles    = ["controller", "broker"]
      storage = {
        type  = "persistent-claim"
        size  = "10Gi"
        class = "gp2"
      }
      resources = {
        requests = {
          memory = "2Gi"
          cpu    = "500m"
        }
        limits = {
          memory = "4Gi"
          cpu    = "2"
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.student]
}

resource "kubernetes_manifest" "strimzi_kafka_cluster" {
  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "Kafka"
    metadata = {
      name      = "kafka"
      namespace = kubernetes_namespace.student.metadata[0].name
      annotations = {
        "strimzi.io/kraft"      = "enabled"
        "strimzi.io/node-pools" = "enabled"
      }
    }
    spec = {
      kafka = {
        version = "4.1.1"
        listeners = [
          {
            name = "plain"
            port = 9092
            type = "internal"
            tls  = false
          },
          {
            name = "tls"
            port = 9093
            type = "internal"
            tls  = true
          }
        ]
        config = {
          "offsets.topic.replication.factor"         = 1
          "transaction.state.log.replication.factor" = 1
          "transaction.state.log.min.isr"            = 1
          "default.replication.factor"               = 1
          "min.insync.replicas"                      = 1
        }
      }
      entityOperator = {
        topicOperator = {}
        userOperator  = {}
      }
    }
  }

  depends_on = [kubernetes_manifest.strimzi_kafka]
}

# -----------------------------------------------------------------------------
# Lenses HQ Helm Release
# -----------------------------------------------------------------------------
resource "helm_release" "lenses_hq" {
  name       = "lenses-hq"
  repository = "https://helm.repo.lenses.io"
  chart      = "lenses-hq"
  namespace  = kubernetes_namespace.student.metadata[0].name

  values = [templatefile("${path.module}/templates/hq-values.yaml.tpl", {
    admin_password_hash = bcrypt_hash.admin_password.id
    postgres_host       = "postgres.${var.namespace}.svc.cluster.local"
    postgres_password   = var.postgres_password
    lenses_license      = var.lenses_license
    hostname            = local.hq_hostname
    acm_certificate_arn = var.acm_certificate_arn
  })]

  depends_on = [kubernetes_job.postgres_init]
}

# -----------------------------------------------------------------------------
# Route53 Record for HQ
# -----------------------------------------------------------------------------

# Poll until the ingress has an ALB hostname assigned
resource "null_resource" "wait_for_ingress_alb" {
  depends_on = [helm_release.lenses_hq]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for ingress ALB to be provisioned..."
      for i in $(seq 1 60); do
        HOSTNAME=$(kubectl get ingress lenses-hq-http -n ${var.namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [ -n "$HOSTNAME" ]; then
          echo "ALB hostname found: $HOSTNAME"
          exit 0
        fi
        echo "Attempt $i/60: ALB not ready yet, waiting 10s..."
        sleep 10
      done
      echo "ERROR: Timed out waiting for ALB after 10 minutes"
      exit 1
    EOT
  }
}

data "kubernetes_ingress_v1" "lenses_hq" {
  metadata {
    name      = "lenses-hq-http"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  depends_on = [null_resource.wait_for_ingress_alb]
}

resource "aws_route53_record" "hq" {
  zone_id = var.route53_zone_id
  name    = local.hq_hostname
  type    = "CNAME"
  ttl     = 300
  records = [data.kubernetes_ingress_v1.lenses_hq.status[0].load_balancer[0].ingress[0].hostname]
}

# -----------------------------------------------------------------------------
# Config Job - Creates Environments and Agent Keys
# -----------------------------------------------------------------------------
resource "kubernetes_job" "lenses_config" {
  metadata {
    name      = "lenses-config"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  spec {
    template {
      metadata {}
      spec {
        restart_policy       = "OnFailure"
        service_account_name = kubernetes_service_account.config_job.metadata[0].name

        container {
          name  = "config"
          image = "alpine:3.19"

          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            set -e
            
            # Install dependencies
            apk add --no-cache curl jq
            
            # Download kubectl
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            chmod +x kubectl
            mv kubectl /usr/local/bin/
            
            echo "Waiting for Lenses HQ to be ready..."
            until curl -sf http://lenses-hq:80/ > /dev/null 2>&1; do
              echo "HQ not ready, waiting..."
              sleep 10
            done
            echo "HQ is ready!"
            
            # Login and get token
            echo "Logging in to Lenses HQ..."
            TOKEN=$(curl -s -X POST http://lenses-hq:80/api/v1/login \
              -H "Content-Type: application/json" \
              -d '{"username":"admin","password":"${local.student_password}"}' | jq -r '.token // .access_token // empty')
            
            if [ -z "$TOKEN" ]; then
              echo "Failed to get auth token, trying basic auth..."
              AUTH_HEADER="Authorization: Basic $(echo -n 'admin:${local.student_password}' | base64)"
            else
              AUTH_HEADER="Authorization: Bearer $TOKEN"
            fi
            
            # Create dev environment
            echo "Creating dev environment..."
            DEV_RESPONSE=$(curl -s -X POST http://lenses-hq:80/api/v1/environments \
              -H "Content-Type: application/json" \
              -H "$AUTH_HEADER" \
              -d '{
                "name": "${local.env_dev_name}",
                "tier": "development"
              }')
            
            echo "Dev response: $DEV_RESPONSE"
            DEV_KEY=$(echo "$DEV_RESPONSE" | jq -r '.agentKey // .agent_key // empty')
            
            if [ -z "$DEV_KEY" ]; then
              echo "Warning: Could not extract dev agent key"
              DEV_KEY="placeholder-dev-key"
            fi
            echo "Dev agent key: $DEV_KEY"
            
            # Create staging environment
            echo "Creating staging environment..."
            STAGING_RESPONSE=$(curl -s -X POST http://lenses-hq:80/api/v1/environments \
              -H "Content-Type: application/json" \
              -H "$AUTH_HEADER" \
              -d '{
                "name": "${local.env_staging_name}",
                "tier": "staging"
              }')
            
            echo "Staging response: $STAGING_RESPONSE"
            STAGING_KEY=$(echo "$STAGING_RESPONSE" | jq -r '.agentKey // .agent_key // empty')
            
            if [ -z "$STAGING_KEY" ]; then
              echo "Warning: Could not extract staging agent key"
              STAGING_KEY="placeholder-staging-key"
            fi
            echo "Staging agent key: $STAGING_KEY"
            
            # Create secrets for agent keys
            kubectl create secret generic lenses-agent-fdd-key \
              --from-literal=agent-key="$DEV_KEY" \
              --namespace=${var.namespace} \
              --dry-run=client -o yaml | kubectl apply -f -
            
            kubectl create secret generic lenses-agent-strimzi-key \
              --from-literal=agent-key="$STAGING_KEY" \
              --namespace=${var.namespace} \
              --dry-run=client -o yaml | kubectl apply -f -
            
            echo "Configuration complete!"
          EOT
          ]
        }
      }
    }

    backoff_limit = 6
  }

  wait_for_completion = true

  timeouts {
    create = "15m"
  }

  depends_on = [helm_release.lenses_hq]
}

# Service account for config job (needs secret creation permissions)
resource "kubernetes_service_account" "config_job" {
  metadata {
    name      = "lenses-config"
    namespace = kubernetes_namespace.student.metadata[0].name
  }
}

resource "kubernetes_role" "config_job" {
  metadata {
    name      = "lenses-config"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "create", "update", "patch"]
  }
}

resource "kubernetes_role_binding" "config_job" {
  metadata {
    name      = "lenses-config"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.config_job.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.config_job.metadata[0].name
    namespace = kubernetes_namespace.student.metadata[0].name
  }
}

# -----------------------------------------------------------------------------
# Lenses Agent - Fast Data Dev
# -----------------------------------------------------------------------------
resource "helm_release" "lenses_agent_fdd" {
  name       = "lenses-agent-fdd"
  repository = "https://helm.repo.lenses.io"
  chart      = "lenses-agent"
  namespace  = kubernetes_namespace.student.metadata[0].name

  values = [templatefile("${path.module}/templates/agent-fdd-values.yaml.tpl", {
    namespace         = var.namespace
    postgres_host     = "postgres.${var.namespace}.svc.cluster.local"
    postgres_password = var.postgres_password
  })]

  depends_on = [kubernetes_job.lenses_config]
}

# -----------------------------------------------------------------------------
# Lenses Agent - Strimzi
# -----------------------------------------------------------------------------
resource "helm_release" "lenses_agent_strimzi" {
  name       = "lenses-agent-strimzi"
  repository = "https://helm.repo.lenses.io"
  chart      = "lenses-agent"
  namespace  = kubernetes_namespace.student.metadata[0].name

  values = [templatefile("${path.module}/templates/agent-strimzi-values.yaml.tpl", {
    namespace         = var.namespace
    postgres_host     = "postgres.${var.namespace}.svc.cluster.local"
    postgres_password = var.postgres_password
  })]

  depends_on = [kubernetes_job.lenses_config, kubernetes_manifest.strimzi_kafka_cluster]
}

# -----------------------------------------------------------------------------
# Financial Data Generator - Fast Data Dev
# -----------------------------------------------------------------------------
resource "kubernetes_deployment" "fin_gen_fdd" {
  metadata {
    name      = "fin-gen-fdd"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "fin-gen-fdd"
      }
    }

    template {
      metadata {
        labels = {
          app = "fin-gen-fdd"
        }
      }

      spec {
        container {
          name  = "generator"
          image = var.fin_gen_image

          env {
            name  = "KAFKA_BOOTSTRAP_SERVERS"
            value = "fast-data-dev.${var.namespace}.svc.cluster.local:9092"
          }
          env {
            name  = "REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name  = "RATE_MULTIPLIER"
            value = "0.1"
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment.fast_data_dev]
}

# -----------------------------------------------------------------------------
# Financial Data Generator - Strimzi
# -----------------------------------------------------------------------------
resource "kubernetes_deployment" "fin_gen_strimzi" {
  metadata {
    name      = "fin-gen-strimzi"
    namespace = kubernetes_namespace.student.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "fin-gen-strimzi"
      }
    }

    template {
      metadata {
        labels = {
          app = "fin-gen-strimzi"
        }
      }

      spec {
        container {
          name  = "generator"
          image = var.fin_gen_image

          env {
            name  = "KAFKA_BOOTSTRAP_SERVERS"
            value = "kafka-kafka-bootstrap.${var.namespace}.svc.cluster.local:9092"
          }
          env {
            name  = "REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name  = "RATE_MULTIPLIER"
            value = "0.1"
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.strimzi_kafka_cluster]
}
