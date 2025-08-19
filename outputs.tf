output "vpc_id" {
  value = aws_vpc.this.id
}
output "public_subnet_id" {
  value = aws_subnet.public.id
}
output "ecr_repo_url" {
  value = local.ecr_repo_url
}
output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}
output "ecs_service_name" {
  value = aws_ecs_service.svc.name
}
output "task_execution_role_arn" {
  value = aws_iam_role.task_exec_role.arn
}
output "vault_aws_access_key_id" {
  value     = aws_iam_access_key.vault_aws_engine.id
  sensitive = false
}

output "vault_aws_secret_access_key" {
  value     = aws_iam_access_key.vault_aws_engine.secret
  sensitive = true
}

output "vault_deploy_role_arn" {
  value = aws_iam_role.ecr_ecs_deploy_role.arn
}
