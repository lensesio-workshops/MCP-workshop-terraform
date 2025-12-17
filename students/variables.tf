variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "lenses-training"
}

variable "domain_name" {
  description = "Domain name for ingress"
  type        = string
  default     = "lenses.training"
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "num_students" {
  description = "Number of student environments to create (1-15)"
  type        = number
  default     = 15

  validation {
    condition     = var.num_students >= 1 && var.num_students <= 15
    error_message = "num_students must be between 1 and 15"
  }
}

variable "lenses_license" {
  description = "Lenses license key"
  type        = string
  sensitive   = true
}

variable "postgres_password" {
  description = "PostgreSQL password for all databases"
  type        = string
  default     = "lenses123"
  sensitive   = true
}

variable "key_pair_name" {
  description = "EC2 key pair name for MCP instances (SSH access)"
  type        = string
}

variable "mcp_instance_type" {
  description = "EC2 instance type for MCP servers"
  type        = string
  default     = "t3.medium"
}

variable "fin_gen_image" {
  description = "Docker image for financial data generator"
  type        = string
  default     = "sqdrew/drew-containers:fin-gen-plain"
}
