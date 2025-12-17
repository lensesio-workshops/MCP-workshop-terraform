variable "student_id" {
  description = "Student ID (e.g., 01, 02)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "domain_name" {
  description = "Domain name for ingress"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "lenses_license" {
  description = "Lenses license key"
  type        = string
  sensitive   = true
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "fin_gen_image" {
  description = "Docker image for financial data generator"
  type        = string
  default     = "sqdrew/drew-containers:fin-gen-plain"
}