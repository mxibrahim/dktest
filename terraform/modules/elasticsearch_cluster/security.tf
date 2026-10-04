# No ingress from any IP range: operators reach the nodes through SSM Session
# Manager, which the SSM agent opens as an outbound HTTPS connection. The only
# inbound rules are node-to-node, scoped to this security group.
resource "aws_security_group" "es" {
  name        = "${var.name}-es-nodes"
  description = "Elasticsearch nodes"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-es-nodes" }
}

# --- Ingress (members of this SG only) ---------------------------------------

resource "aws_vpc_security_group_ingress_rule" "transport" {
  security_group_id            = aws_security_group.es.id
  description                  = "Elasticsearch transport (node-to-node)"
  referenced_security_group_id = aws_security_group.es.id
  ip_protocol                  = "tcp"
  from_port                    = 9300
  to_port                      = 9300
}

# Lets a client tunnelled in through one node (SSM) reach every node's REST
# API, the same path an internal load balancer would use.
resource "aws_vpc_security_group_ingress_rule" "https_api" {
  security_group_id            = aws_security_group.es.id
  description                  = "Elasticsearch HTTPS API within the cluster"
  referenced_security_group_id = aws_security_group.es.id
  ip_protocol                  = "tcp"
  from_port                    = 9200
  to_port                      = 9200
}

# --- Egress (restricted instead of allow-all) --------------------------------

resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.es.id
  description       = "apt mirrors (via NAT)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.es.id
  description       = "Elastic artifacts, SSM endpoints, AWS APIs (via NAT)"
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

resource "aws_vpc_security_group_egress_rule" "https_api" {
  security_group_id            = aws_security_group.es.id
  description                  = "Elasticsearch HTTPS API within the cluster"
  referenced_security_group_id = aws_security_group.es.id
  ip_protocol                  = "tcp"
  from_port                    = 9200
  to_port                      = 9200
}
