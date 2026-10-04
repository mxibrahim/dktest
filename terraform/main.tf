# Auto-detect the operator's public IP so the API is never opened to 0.0.0.0/0.
data "http" "my_ip" {
  count = length(var.allowed_cidrs) == 0 ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

locals {
  allowed_cidrs = length(var.allowed_cidrs) > 0 ? var.allowed_cidrs : ["${chomp(data.http.my_ip[0].response_body)}/32"]

  ssh_public_key_path  = pathexpand(var.ssh_public_key_path)
  ssh_private_key_path = trimsuffix(local.ssh_public_key_path, ".pub")
}

module "network" {
  source = "./modules/network"

  name     = var.name
  az_count = min(var.node_count, 3)
}

module "elasticsearch" {
  source = "./modules/elasticsearch_cluster"

  name                = var.name
  node_count          = var.node_count
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.public_subnet_ids
  instance_type       = var.instance_type
  architecture        = var.architecture
  root_volume_size    = var.root_volume_size
  ssh_public_key      = file(local.ssh_public_key_path)
  allowed_cidrs       = local.allowed_cidrs
  alarm_sns_topic_arn = var.alarm_sns_topic_arn
}

# Hand-off to Ansible: Terraform owns the infrastructure, Ansible owns the OS
# and Elasticsearch configuration. The inventory is the contract between them.
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.yml"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    nodes                = module.elasticsearch.nodes
    cluster_name         = var.name
    ssh_private_key_path = local.ssh_private_key_path
  })
}
