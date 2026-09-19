output "instance_id" {
  value = aws_instance.traefik.id
}

output "private_ip" {
  value = aws_instance.traefik.private_ip
}
