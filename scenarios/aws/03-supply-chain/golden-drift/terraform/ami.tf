#---------------------------------------
# Golden AMI baking
#
# Strategy:
#   1. Launch a temporary EC2 instance from Amazon Linux 2023.
#   2. Its user_data installs Flask, writes the ticketing app, and registers
#      it as a systemd service.
#   3. Wait long enough for user_data to complete.
#   4. aws_ami_from_instance snapshots the running instance into an AMI.
#   5. The AMI ID becomes the initial value of the SSM parameter that the
#      Launch Template resolves at ASG launch time.
#
# The temporary instance remains in the account after baking. It is not part
# of the ASG (no Auto Scaling group association, no target group) so it just
# sits idle until terraform destroy tears it down.
#---------------------------------------

#---------------------------------------
# Security Group — temporary baking instance
# Egress only (needs internet to dnf install + pip install).
# No ingress: the instance is never exposed publicly, only used as an AMI source.
#---------------------------------------
resource "aws_security_group" "ami_baker" {
  name        = "${local.scenario_name}-ami-baker-sg-${local.scenario_id}"
  description = "Egress-only SG for the temporary AMI baking instance"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All egress for package installation"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.scenario_name}-ami-baker-sg-${local.scenario_id}"
  })
}

#---------------------------------------
# Temporary instance for baking the golden AMI
#---------------------------------------
resource "aws_instance" "ami_baker" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.ami_baker.id]
  associate_public_ip_address = true
  user_data                   = local.golden_ami_user_data

  # The instance is launched only to be snapshotted. No production traffic.
  tags = merge(local.common_tags, {
    Name    = "${local.scenario_name}-ami-baker-${local.scenario_id}"
    Purpose = "ami-baking-source"
  })

  lifecycle {
    # Once the AMI is baked, the user_data has already run. Re-running terraform
    # apply should not destroy the source instance unless the user_data itself
    # changes (which would mean we want a fresh bake).
    ignore_changes = [ami]
  }
}

#---------------------------------------
# Wait for user_data to finish before snapshotting
#
# user_data does:
#   - dnf update (slow)
#   - dnf install python3 python3-pip
#   - pip3 install flask
#   - write app + systemd unit
#   - systemctl start ticketing
#
# Empirically this completes in ~90-120s on t2.micro. We sleep 180s to be safe.
#---------------------------------------
resource "time_sleep" "wait_for_userdata" {
  depends_on      = [aws_instance.ami_baker]
  create_duration = "180s"
}

#---------------------------------------
# Snapshot the baker instance into the golden AMI
#
# Naming: gnawlab-golden-ticketing-{scenario_id}-{YYYYMMDD}
# This prefix is exactly what the vulnerable Lambda filters on, and
# it is unique per deployment so other participants' malicious AMIs
# cannot be picked up by this Lambda.
#---------------------------------------
resource "aws_ami_from_instance" "golden" {
  name               = local.golden_ami_name
  source_instance_id = aws_instance.ami_baker.id

  depends_on = [time_sleep.wait_for_userdata]

  tags = merge(local.common_tags, {
    Name      = local.golden_ami_name
    Role      = "golden-ami"
    BakedFrom = aws_instance.ami_baker.id
  })

  lifecycle {
    # Reproducible name with timestamp(). Avoid rebaking on every apply.
    ignore_changes = [name]
  }
}
