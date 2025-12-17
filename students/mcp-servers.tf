# v. 6 - MCP Servers for Student Training Environment
# Fixed: SSE transport, simplified LENSES_URL env var
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get subnets from VPC (uses vpc_id from main.tf's data.aws_eks_cluster.cluster)
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_eks_cluster.cluster.vpc_config[0].vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = ["*public*"]
  }
}

locals {
  mcp_vpc_id            = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
  mcp_public_subnet_ids = data.aws_subnets.public.ids
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

resource "aws_security_group" "mcp_alb" {
  name        = "lenses-training-mcp-alb-sg"
  description = "MCP ALB Security Group"
  vpc_id      = local.mcp_vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP redirect"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lenses-training-mcp-alb-sg"
  }
}

resource "aws_security_group" "mcp_instance" {
  name        = "lenses-training-mcp-instance-sg"
  description = "MCP Instance Security Group"
  vpc_id      = local.mcp_vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.mcp_alb.id]
    description     = "MCP from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lenses-training-mcp-instance-sg"
  }
}

# -----------------------------------------------------------------------------
# Shared Application Load Balancer
# -----------------------------------------------------------------------------

resource "aws_lb" "mcp" {
  name               = "lenses-training-mcp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.mcp_alb.id]
  subnets            = local.mcp_public_subnet_ids

  tags = {
    Name = "lenses-training-mcp-alb"
  }
}

# HTTPS Listener (main)
resource "aws_lb_listener" "mcp_https" {
  load_balancer_arn = aws_lb.mcp.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "MCP Server - Use studentXX-mcp.lenses.training"
      status_code  = "404"
    }
  }
}

# HTTP to HTTPS redirect
resource "aws_lb_listener" "mcp_http" {
  load_balancer_arn = aws_lb.mcp.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# -----------------------------------------------------------------------------
# Per-Student Resources
# -----------------------------------------------------------------------------

# Target Group per student
resource "aws_lb_target_group" "mcp" {
  for_each = toset(local.student_ids)

  name     = "mcp-student${each.value}-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = local.mcp_vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    path                = "/"
    matcher             = "200-299,404,405"
  }

  tags = {
    Name    = "mcp-student${each.value}-tg"
    Student = each.value
  }
}

# Listener Rule per student (host-based routing)
resource "aws_lb_listener_rule" "mcp" {
  for_each = toset(local.student_ids)

  listener_arn = aws_lb_listener.mcp_https.arn
  priority     = 100 + tonumber(each.value)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mcp[each.value].arn
  }

  condition {
    host_header {
      values = ["student${each.value}-mcp.${var.domain_name}"]
    }
  }
}

# EC2 Instance per student
resource "aws_instance" "mcp" {
  for_each = toset(local.student_ids)

  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.mcp_instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = local.mcp_public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.mcp_instance.id]
  associate_public_ip_address = true

  user_data = <<-EOF
#!/bin/bash
set -e

# Log output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting MCP setup for student${each.value}..."

# Update system
dnf update -y
dnf install -y git python3.12 python3.12-pip

# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="/root/.local/bin:$PATH"

# Clone MCP repository
cd /opt
git clone https://github.com/lensesio/lenses-mcp.git
cd lenses-mcp

# Create .env file - empty template for students to configure
cat > .env <<ENVFILE
# Lenses MCP Configuration
# Students: Fill in these values from your Lenses HQ instance

LENSES_URL=
LENSES_API_KEY=

# After editing, restart the service:
# sudo systemctl restart lenses-mcp
ENVFILE

# Install Python dependencies
/root/.local/bin/uv sync

# Create systemd service - using SSE transport
cat > /etc/systemd/system/lenses-mcp.service <<'SERVICE'
[Unit]
Description=Lenses MCP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/lenses-mcp
Environment="PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin"
EnvironmentFile=/opt/lenses-mcp/.env
ExecStart=/root/.local/bin/uv run fastmcp run /opt/lenses-mcp/src/lenses_mcp/server.py --transport=sse --port=8080 --host=0.0.0.0
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

# Start service
systemctl daemon-reload
systemctl enable lenses-mcp.service
systemctl start lenses-mcp.service

echo "MCP setup complete for student${each.value}!"
EOF

  tags = {
    Name    = "lenses-training-mcp-student${each.value}"
    Student = each.value
  }
}

# Target Group Attachment
resource "aws_lb_target_group_attachment" "mcp" {
  for_each = toset(local.student_ids)

  target_group_arn = aws_lb_target_group.mcp[each.value].arn
  target_id        = aws_instance.mcp[each.value].id
  port             = 8080
}

# Route53 DNS Record per student
resource "aws_route53_record" "mcp" {
  for_each = toset(local.student_ids)

  zone_id = var.route53_zone_id
  name    = "student${each.value}-mcp.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.mcp.dns_name
    zone_id                = aws_lb.mcp.zone_id
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "mcp_alb_dns" {
  description = "MCP ALB DNS name"
  value       = aws_lb.mcp.dns_name
}

output "mcp_urls" {
  description = "MCP URLs per student (use in Claude settings)"
  value = {
    for id in local.student_ids : "student${id}" => "https://student${id}-mcp.${var.domain_name}/sse"
  }
}

output "mcp_ssh_commands" {
  description = "SSH commands per student"
  value = {
    for id in local.student_ids : "student${id}" => "ssh -i ${var.key_pair_name}.pem ec2-user@${aws_instance.mcp[id].public_ip}"
  }
}

output "mcp_instance_ips" {
  description = "Public IPs per student"
  value = {
    for id in local.student_ids : "student${id}" => aws_instance.mcp[id].public_ip
  }
}
