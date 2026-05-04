#---------------------------------------
# EBS Volume with sensitive data
# (Simulates a decommissioned server's data volume)
#---------------------------------------
resource "aws_ebs_volume" "data" {
  availability_zone = local.availability_zone
  size              = 1 # 1 GB - minimum size
  type              = "gp3"

  tags = merge(local.common_tags, {
    Name        = local.volume_name
    Description = "Decommissioned server data volume - contains legacy database backups"
  })
}

#---------------------------------------
# Null resource to write flag to volume
# We create a temporary EC2 to write data, then terminate it
#---------------------------------------
resource "aws_key_pair" "setup" {
  key_name   = "${local.key_name}-setup"
  public_key = tls_private_key.setup.public_key_openssh

  tags = local.common_tags
}

resource "tls_private_key" "setup" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Temporary instance to write data to volume
resource "aws_instance" "setup" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh.id]
  key_name               = aws_key_pair.setup.key_name

  # Wait for volume to be available
  depends_on = [aws_ebs_volume.data]

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Wait for the volume to be attached
    while [ ! -e /dev/xvdf ]; do sleep 1; done

    # Format and mount the volume
    mkfs -t ext4 /dev/xvdf
    mkdir -p /mnt/data
    mount /dev/xvdf /mnt/data

    # Create realistic directory structure
    mkdir -p /mnt/data/backups/db
    mkdir -p /mnt/data/logs
    mkdir -p /mnt/data/config

    # Create some decoy files
    echo "2024-01-15 03:00:01 - Backup started" > /mnt/data/logs/backup.log
    echo "2024-01-15 03:05:23 - Database dump completed" >> /mnt/data/logs/backup.log
    echo "2024-01-15 03:05:24 - Backup finished successfully" >> /mnt/data/logs/backup.log

    echo "[database]" > /mnt/data/config/app.conf
    echo "host=prod-db.internal.beavertech.local" >> /mnt/data/config/app.conf
    echo "port=5432" >> /mnt/data/config/app.conf
    echo "name=beavertech_prod" >> /mnt/data/config/app.conf

    # Create the flag file (hidden in a realistic location)
    cat > /mnt/data/backups/db/credentials.bak << 'FLAGEOF'
    # Database Credentials Backup
    # Created: 2024-01-15
    # Server: prod-db-01.beavertech.local
    # WARNING: This file contains sensitive information

    DB_HOST=prod-db.internal.beavertech.local
    DB_PORT=5432
    DB_NAME=beavertech_prod
    DB_USER=admin
    DB_PASSWORD=B3@v3rT3ch_Pr0d_2024!

    # API Keys
    STRIPE_API_KEY=sk_live_fake_key_for_training
    AWS_INTERNAL_KEY=AKIA_FAKE_KEY_FOR_TRAINING

    # Flag for GnawLab scenario
    ${var.flag_value}
    FLAGEOF

    # Unmount the volume
    umount /mnt/data

    # Signal completion
    touch /tmp/setup_complete
  EOF

  tags = merge(local.common_tags, {
    Name        = "${local.scenario_name}-setup-${local.scenario_id}"
    Description = "Temporary instance for volume setup - will be terminated"
  })
}

# Attach volume to setup instance
resource "aws_volume_attachment" "setup" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.setup.id

  # Force detach on destroy
  force_detach = true
}

# Wait for setup to complete
resource "time_sleep" "wait_for_setup" {
  depends_on = [aws_volume_attachment.setup]

  create_duration = "90s"
}

# Detach volume from setup instance
resource "null_resource" "detach_volume" {
  depends_on = [time_sleep.wait_for_setup]

  provisioner "local-exec" {
    command = <<-EOT
      aws ec2 detach-volume \
        --volume-id ${aws_ebs_volume.data.id} \
        --force \
        --profile ${var.profile} \
        --region ${var.region} || true

      # Wait for volume to be available
      sleep 30
    EOT
  }
}

#---------------------------------------
# EBS Snapshot (The target for the attacker)
#---------------------------------------
resource "aws_ebs_snapshot" "data" {
  volume_id = aws_ebs_volume.data.id

  depends_on = [null_resource.detach_volume]

  tags = merge(local.common_tags, {
    Name        = local.snapshot_name
    Description = "Backup of decommissioned prod-db-01 server - 2024-01-15"
    Server      = "prod-db-01.beavertech.local"
    BackupType  = "full"
    RetainUntil = "2025-01-15"
  })
}

#---------------------------------------
# Terminate setup instance after snapshot
#---------------------------------------
resource "null_resource" "cleanup_setup" {
  depends_on = [aws_ebs_snapshot.data]

  provisioner "local-exec" {
    command = <<-EOT
      aws ec2 terminate-instances \
        --instance-ids ${aws_instance.setup.id} \
        --profile ${var.profile} \
        --region ${var.region} || true
    EOT
  }
}
