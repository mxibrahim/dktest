variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "dktest"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-southeast-2" # region assigned to this AWS account (new sign-up experience)
}

variable "node_count" {
  description = "Number of Elasticsearch nodes: 1 (single-node) or 3 (cluster)."
  type        = number
  default     = 3
}

variable "instance_type" {
  description = <<-EOT
    Free-tier eligible type. Accounts on the legacy 12-month free tier: t2.micro
    (or t3.micro in regions without t2). Accounts on the newer credit-based free
    plan: t3.micro / t3.small / t4g.micro / t4g.small (t4g needs architecture = "arm64").
  EOT
  type        = string
  default     = "t3.micro"
}

variable "architecture" {
  description = "AMI architecture: amd64 or arm64 (for t4g)."
  type        = string
  default     = "amd64"
}

variable "root_volume_size" {
  description = "Root volume GiB per node. 3 x 10 GiB stays within the 30 GiB free tier."
  type        = number
  default     = 10
}

variable "ssh_public_key_path" {
  description = "SSH public key installed on the nodes; the matching private key (same path without .pub) is used by Ansible."
  type        = string
  default     = "~/.ssh/dktest_ed25519.pub"
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach 9200/22. Empty = auto-detect the caller's public IP (/32)."
  type        = list(string)
  default     = []
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic for CloudWatch alarm notifications."
  type        = string
  default     = null
}
