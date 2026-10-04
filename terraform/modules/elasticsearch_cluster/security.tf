resource "aws_security_group" "es" {
  name        = "${var.name}-es-nodes"
  description = "Elasticsearch nodes"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-es-nodes" }
}

# --- Ingress -----------------------------------------------------------------

# REST API (HTTPS) only from operator CIDRs.
resource "aws_vpc_security_group_ingress_rule" "https_api" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.es.id
  description       = "Elasticsearch HTTPS API"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 9200
  to_port           = 9200
}

# SSH only from operator CIDRs, used by Ansible. Session Manager is also
# enabled (IAM role below) as a break-glass path that needs no open port.
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.es.id
  description       = "SSH for Ansible"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

# Node-to-node transport layer: only from other members of this SG.
resource "aws_vpc_security_group_ingress_rule" "transport" {
  security_group_id            = aws_security_group.es.id
  description                  = "Elasticsearch transport (node-to-node)"
  referenced_security_group_id = aws_security_group.es.id
  ip_protocol                  = "tcp"
  from_port                    = 9300
  to_port                      = 9300
}

# --- Egress (restricted instead of allow-all) --------------------------------

resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.es.id
  description       = "apt mirrors"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.es.id
  description       = "Elastic artifacts, SSM agent, AWS APIs"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "transport" {
  security_group_id            = aws_security_group.es.id
  description                  = "Elasticsearch transport (node-to-node)"
  referenced_security_group_id = aws_security_group.es.id
  ip_protocol                  = "tcp"
  from_port                    = 9300
  to_port                      = 9300
}
