data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${var.architecture}-server-*"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.name}-ansible"
  public_key = var.ssh_public_key
}

resource "aws_instance" "es" {
  count = var.node_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.this.key_name
  iam_instance_profile   = aws_iam_instance_profile.es.name
  vpc_security_group_ids = [aws_security_group.es.id]
  # Round-robin across AZs so losing one AZ only loses one node.
  subnet_id = var.subnet_ids[count.index % length(var.subnet_ids)]

  # t3 defaults to "unlimited" credits, which bills for sustained bursting.
  # "standard" throttles instead, so we never leave the free tier by accident.
  credit_specification {
    cpu_credits = "standard"
  }

  # IMDSv2 only; hop limit 1 so containers can't reach instance credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true # AWS-managed aws/ebs key (no KMS cost)
    delete_on_termination = true
  }

  tags = {
    Name = "${var.name}-es-node-${count.index + 1}"
    Role = "elasticsearch"
  }

  lifecycle {
    # A newer Ubuntu AMI must not silently replace (and wipe) a running node.
    # Node replacement is a deliberate, rolling operation - see README.
    ignore_changes = [ami]
  }
}
