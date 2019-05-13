output "asg_id" {
  value = "${module.bastion_asg.autoscaling_group_id}"
}

output "asg_arn" {
  value = "${module.bastion_asg.autoscaling_group_arn}"
}

output "aws_security_group_allow_ssh_id" {
  value = "${aws_security_group.allow_ssh_sg.id}"
}

output "autoscaling_group_desired_capacity" {
  value = "${module.bastion_asg.autoscaling_group_desired_capacity}"
}

output "autoscaling_group_health_check_grace_period" {
  value = "${module.bastion_asg.autoscaling_group_health_check_grace_period}"
}

output "autoscaling_group_name" {
  value = "${module.bastion_asg.autoscaling_group_name}"
}

output "launch_template_arn" {
  value = "${module.bastion_asg.launch_template_arn}"
}

output "launch_template_id" {
  value = "${module.bastion_asg.launch_template_id}"
}

output "ssh_user" {
  value       = "${var.ssh_user}"
  description = "SSH user"
}

output "security_group_id" {
  value       = "${aws_security_group.allow_ssh_sg.id}"
  description = "Security group ID"
}

output "role" {
  value       = "${aws_iam_role.bastion_role.name}"
  description = "Name of AWS IAM Role associated with the instance"
}

output "public_ip" {
  value       = "${aws_eip.bastion.public_ip}"
  description = "Public IP of the instance (or EIP)"
}

output "private_ip" {
  value       = "${aws_eip.bastion.private_ip}"
  description = "Private IP of the instance"
}
