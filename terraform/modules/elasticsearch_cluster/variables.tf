variable "name" {
  description = "Name prefix for cluster resources (also used as the ES cluster name)."
  type        = string
}

variable "node_count" {
  description = "Number of Elasticsearch nodes. 1 = single-node, 3 = HA cluster (all master-eligible)."
  type        = number

  validation {
    # Even numbers of master-eligible nodes add no fault tolerance for quorum.
    condition     = var.node_count == 1 || (var.node_count >= 3 && var.node_count % 2 == 1)
    error_message = "node_count must be 1 or an odd number >= 3 (quorum of master-eligible nodes)."
  }
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets to spread nodes across (round-robin), ideally one per AZ."
  type        = list(string)
}

variable "instance_type" {
  type = string
}

variable "architecture" {
  description = "CPU architecture of the AMI: amd64 (t2/t3) or arm64 (t4g)."
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.architecture)
    error_message = "architecture must be amd64 or arm64."
  }
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB. Free tier covers 30 GiB total across all volumes."
  type        = number
  default     = 10
}

variable "ssh_public_key" {
  description = "Contents of the SSH public key used by Ansible (SSH runs inside an SSM session)."
  type        = string
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic notified by CloudWatch alarms."
  type        = string
  default     = null
}
