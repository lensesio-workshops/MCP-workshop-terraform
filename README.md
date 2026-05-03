# Lenses Training Infrastructure - Students

Deploys student environments on the EKS foundation.

## What This Creates (Per Student)

Each student namespace (`student01`, `student02`, etc.) contains:

- **PostgreSQL** - StatefulSet with 3 databases (lenseshq, lensesagent01, lensesagent02)
- **Fast Data Dev** - Kafka + Schema Registry + Connect (port 8083!)
- **Strimzi Kafka** - Single broker cluster
- **Lenses HQ** - Web UI at `studentXX-hq.lenses.training`
- **Lenses Agent (FDD)** - Connected to Fast Data Dev environment
- **Lenses Agent (Strimzi)** - Connected to Strimzi environment
- **Config Job** - Creates environments and agent keys automatically

## Prerequisites

1. Foundation terraform applied (`../foundation`)
2. EKS cluster running
3. Strimzi operator installed
4. ACM certificate validated
5. Lenses license key

## Configuration

```bash
# Copy example config
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# From foundation terraform output
acm_certificate_arn = "arn:aws:acm:us-east-2:..."  
route53_zone_id     = "Z0338660G6GCIF4RK08Z"

# Number of students (1-15)
num_students = 15

# Lenses license
lenses_license = "license_key_..."
```

Get foundation outputs:
```bash
cd ../foundation
terraform output acm_certificate_arn
terraform output route53_zone_id
```

## Deploy

```bash
terraform init
terraform plan
terraform apply
```

This will take 15-20 minutes for all 15 students.

## Student Access

After deployment:

| Student | HQ URL | Username | Password |
|---------|--------|----------|----------|
| 01 | https://student01-hq.lenses.training | admin | $tudent01 |
| 02 | https://student02-hq.lenses.training | admin | $tudent02 |
| ... | ... | ... | ... |
| 15 | https://student15-hq.lenses.training | admin | $tudent15 |

Get all URLs:
```bash
terraform output student_urls
```

Get full details (including passwords):
```bash
terraform output -json student_environments
```

## Environments Per Student

Each student has two Kafka environments in their Lenses HQ:

1. **financial-transactions-dev** (Fast Data Dev)
   - Kafka: `fast-data-dev.studentXX.svc:9092`
   - Schema Registry: `fast-data-dev.studentXX.svc:8081`
   - Connect: `fast-data-dev.studentXX.svc:8083`

2. **financial-transactions-staging** (Strimzi)
   - Kafka: `kafka-kafka-bootstrap.studentXX.svc:9092`

## Troubleshooting

### Check student namespace
```bash
kubectl get pods -n student01
```

### Check HQ logs
```bash
kubectl logs -n student01 -l app.kubernetes.io/name=lenses-hq
```

### Check agent logs
```bash
kubectl logs -n student01 -l app.kubernetes.io/instance=lenses-agent-fdd
kubectl logs -n student01 -l app.kubernetes.io/instance=lenses-agent-strimzi
```

### Check config job
```bash
kubectl logs -n student01 job/lenses-config
```

### Rerun config job (if needed)
```bash
kubectl delete job lenses-config -n student01
terraform apply
```

## Scaling

To add/remove students, update `num_students` and re-apply:

```bash
# Edit terraform.tfvars
num_students = 10

terraform apply
```

## Destroy

```bash
terraform destroy
```

Note: This only destroys student environments. The EKS foundation remains.

## Cost Estimate

Each student environment uses approximately:
- 4Gi memory (Fast Data Dev)
- 4Gi memory (Strimzi)
- 4Gi memory (Agents)
- 2Gi memory (HQ)
- 1Gi memory (PostgreSQL)
- ~15Gi total

15 students = ~225Gi memory across the cluster.
