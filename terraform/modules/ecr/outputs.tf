output "repository_urls" {
  value = { for name, repo in aws_ecr_repository.repos : name => repo.repository_url }
}

output "repository_arns" {
  value = [for repo in aws_ecr_repository.repos : repo.arn]
}
