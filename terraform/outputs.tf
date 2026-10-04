output "allowed_cidrs" {
  value = local.allowed_cidrs
}

output "nodes" {
  value = module.elasticsearch.nodes
}

output "es_endpoints" {
  description = "HTTPS endpoints of every node."
  value       = [for n in module.elasticsearch.nodes : "https://${n.public_ip}:9200"]
}
