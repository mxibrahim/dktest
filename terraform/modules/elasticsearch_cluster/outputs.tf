output "security_group_id" {
  value = aws_security_group.es.id
}

output "nodes" {
  description = "Per-node connection details, consumed by the Ansible inventory."
  value = [
    for i, inst in aws_instance.es : {
      name        = "es-node-${i + 1}"
      instance_id = inst.id
      az          = inst.availability_zone
      public_ip   = inst.public_ip
      public_dns  = inst.public_dns
      private_ip  = inst.private_ip
    }
  ]
}
