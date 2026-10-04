output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
  # Consumers (instances) must not boot before egress works, or cloud-init
  # and the SSM agent start without internet access.
  depends_on = [aws_route_table_association.private, aws_nat_gateway.this]
}

output "nat_public_ip" {
  description = "Egress IP of the private subnets (useful for allow-listing)."
  value       = aws_eip.nat.public_ip
}
