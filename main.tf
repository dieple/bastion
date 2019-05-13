module "label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.3"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  name       = "${var.name}"
  delimiter  = "${var.delimiter}"
  attributes = "${var.attributes}"
  tags       = "${var.tags}"
}

resource "aws_iam_role" "bastion_role" {
  name = "${module.label.id}-role"

  assume_role_policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": ["ec2.amazonaws.com"]
        },
        "Effect": "Allow"
      }
    ]
}
EOF
}

resource "aws_iam_role_policy" "bastion_role_policy" {
  name   = "${module.label.id}-role-policy"
  role   = "${aws_iam_role.bastion_role.id}"
  policy = "${data.aws_iam_policy_document.bastion_policy_document.json}"
}

data "aws_iam_policy_document" "bastion_policy_document" {
  statement {
    actions = [
      "ec2:AssociateAddress",
      "ec2:DescribeAddresses",
      "ec2:AllocateAddress",
      "ec2:EIPAssociation",
      "ec2:DisassociateAddress",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "bastion_policy" {
  name   = "${module.label.id}-iam-policy"
  policy = "${data.aws_iam_policy_document.bastion_policy_document.json}"
}

resource "aws_iam_instance_profile" "bastion_instance_profile" {
  name = "${module.label.id}-instance-profile"
  path = "/"
  role = "${aws_iam_role.bastion_role.name}"
}

# Get the name of the latest AMI for Amazon Linux
data "aws_ami" "ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami*_64-gp2"]
  }
}

# EIP for instances
resource "aws_eip" "bastion" {
  vpc = true
}

data "local_file" "public_key" {
  filename = "${path.module}/key.pub"
}

data "template_file" "bastion_init_script" {
  template = "${file("${path.module}/user_data/user_data.sh")}"

  vars {
    allocation_id   = "${aws_eip.bastion.id}"
    welcome_message = "${var.stage}"
    publict_key     = "${var.public_key_data == "" ? data.local_file.public_key.content: var.public_key_data}"
    ssh_user        = "${var.ssh_user}"
    environment     = "${var.environment}"
    user_data       = "${join("\n", var.user_data)}"
  }
}

resource "aws_route53_record" "bastion" {
  zone_id = "${var.zone_id}"
  name    = "bastion"
  ttl     = "60"
  type    = "A"
  records = ["${aws_eip.bastion.public_ip}"]
}

#----------------------------------------------------
# This creates a new security group
#---------------------------------------------------

resource "aws_security_group" "allow_ssh_sg" {
  name        = "${module.label.id}-allow-ssh-sg"
  description = "Allow all SSH only inbound"
  vpc_id      = "${var.vpc_id}"
  tags        = "${var.tags}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = "${var.allowed_cidr_blocks}"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

//module "bastion_asg" {
//  source = "git::https://github.com/cloudposse/terraform-aws-ec2-autoscale-group.git?ref=tags/0.1.3"
//
//  namespace                   = "${var.namespace}"
//  stage                       = "${var.stage}"
//  name                        = "${var.name}"
//  delimiter                   = "${var.delimiter}"
//  attributes                  = "${var.attributes}"
//  tags                        = "${var.tags}"
//  image_id                    = "${data.aws_ami.ami.id}"
//  instance_type               = "${var.instance_type}"
//  key_name                    = "${var.key_name}"
//  security_groups_ids             = ["${aws_security_group.allow_ssh_sg.id}"]
//  iam_instance_profilei_name        = "${aws_iam_instance_profile.bastion_instance_profile.name}"
//  enable_monitoring           = true
//  health_check_type           = "EC2"
//  subnet_ids                  = "${var.public_subnets}"
//  max_size                    = "${var.max_size}"
//  min_size                    = "${var.min_size}"
//  wait_for_capacity_timeout   = "${var.wait_for_capacity_timeout}"
////  associate_public_ip_address = true
//  default_cooldown            = "${var.cooldown}"
//  health_check_grace_period   = "${var.health_check_grace_period }"
//  termination_policies        = ["ClosestToNextInstanceHour", "OldestInstance", "Default"]
//  enabled_metrics             = ["GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances", "GroupPendingInstances", "GroupStandbyInstances", "GroupTerminatingInstances", "GroupTotalInstances"]
//
//  # Auto-scaling policies and CloudWatch metric alarms
//  autoscaling_policies_enabled           = "true"
//  cpu_utilization_high_threshold_percent = "${var.cpu_utilization_high_threshold_percent}"
//  cpu_utilization_low_threshold_percent  = "${var.cpu_utilization_low_threshold_percent}"
//
//  block_device_mappings {
//    ebs {
//      volume_type = "gp2"
//      volume_size = "${var.volume_size}"
//    }
//  }
//
//  user_data_base64 = "${base64encode(data.template_file.bastion_init_script.rendered)}"
//}

# Create the configuration for an ASG
resource "aws_launch_configuration" "as_conf" {
  image_id             = "${data.aws_ami.ami.id}"
  instance_type        = "${var.instance_type}"
  key_name             = "${var.key_name}"
  security_groups      = ["${aws_security_group.allow_ssh_sg.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.bastion_instance_profile.name}"
  enable_monitoring    = true

  lifecycle {
    create_before_destroy = true
  }

  root_block_device {
    volume_type = "gp2"
    volume_size = "${var.volume_size}"
  }

  user_data = "${data.template_file.bastion_init_script.rendered}"
}

resource "aws_autoscaling_group" "bastion_asg" {
  name                      = "${module.label.id}-bastion"
  vpc_zone_identifier       = ["${var.public_subnets}"]
  health_check_type         = "EC2"
  launch_configuration      = "${aws_launch_configuration.as_conf.name}"
  max_size                  = "${var.max_size}"
  min_size                  = "${var.min_size}"
  default_cooldown          = "${var.cooldown}"
  health_check_grace_period = "${var.health_check_grace_period }"
  desired_capacity          = "${var.desired_capacity}"
  termination_policies      = ["ClosestToNextInstanceHour", "OldestInstance", "Default"]
  enabled_metrics           = ["GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances", "GroupPendingInstances", "GroupStandbyInstances", "GroupTerminatingInstances", "GroupTotalInstances"]
  tags                      = "${var.tags}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_schedule" "scale_up" {
  autoscaling_group_name = "${aws_autoscaling_group.bastion_asg.name}"
  scheduled_action_name  = "Scale Up"
  recurrence             = "${var.scale_up_cron}"
  min_size               = "${var.min_size}"
  max_size               = "${var.max_size}"
  desired_capacity       = "${var.desired_capacity}"
}

resource "aws_autoscaling_schedule" "scale_down" {
  autoscaling_group_name = "${aws_autoscaling_group.bastion_asg.name}"
  scheduled_action_name  = "Scale Down"
  recurrence             = "${var.scale_down_cron}"
  min_size               = "${var.scale_down_min_size}"
  max_size               = "${var.max_size}"
  desired_capacity       = "${var.scale_down_desired_capacity}"
}
