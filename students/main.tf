# students/main.tf - Loops over student_ids and creates student environments

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Generate student IDs (01, 02, ... N)
locals {
  student_ids = [for i in range(1, var.num_students + 1) : format("%02d", i)]
}

# Create student environments
module "student" {
  source   = "./modules/student"
  for_each = toset(local.student_ids)

  student_id          = each.value
  namespace           = "student${each.value}"
  domain_name         = var.domain_name
  acm_certificate_arn = var.acm_certificate_arn
  route53_zone_id     = var.route53_zone_id
  lenses_license      = var.lenses_license
  postgres_password   = var.postgres_password
  fin_gen_image       = var.fin_gen_image
}

# Outputs
output "student_hq_urls" {
  description = "Lenses HQ URLs per student"
  value = {
    for id in local.student_ids : "student${id}" => "https://student${id}-hq.${var.domain_name}"
  }
}

output "student_passwords" {
  description = "Student passwords"
  value = {
    for id in local.student_ids : "student${id}" => "$tudent${id}"
  }
  sensitive = true
}
