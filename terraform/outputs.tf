output "region" {
  value = var.region
}

output "nodes" {
  value = module.elasticsearch.nodes
}

output "security_group_id" {
  value = module.elasticsearch.security_group_id
}

output "nat_public_ip" {
  description = "Egress IP used by the nodes for outbound traffic."
  value       = module.network.nat_public_ip
}

output "es_endpoints" {
  description = "Private HTTPS endpoints (reach them via `make tunnel`)."
  value       = [for n in module.elasticsearch.nodes : "https://${n.private_ip}:9200"]
}
