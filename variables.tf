variable "aws_region" { default = "us-west-2" }
variable "project"    { default = "vault-cicd-2048" }
variable "env"        { default = "dev" }

# ECR: Provide either name (repo must exist) or full repo URL (registry URI)
variable "ecr_repo_name" {
  description = "Existing ECR repository name (example: dunedwell). Leave empty if using repo_url."
  type        = string
  default     = "vault-cicd-2048"
}
variable "ecr_repo_url" {
  description = "Full ECR repository URI (example: 123456789012.dkr.ecr.us-east-1.amazonaws.com/dunedwell). Optional."
  type        = string
  default     = "293088445135.dkr.ecr.us-west-2.amazonaws.com/vault-cicd-2048"
}

# Fargate capacity provider: "FARGATE" or "FARGATE_SPOT"
variable "capacity_provider" {
  description = "Use FARGATE or FARGATE_SPOT"
  type        = string
  default     = "FARGATE"
}


# Single public subnet only
variable "vpc_cidr" { 
    description = "VPC CIDR" 
    default = "10.20.0.0/16" 
}

variable "public_subnet_cidr" { 
    description = "Public subnet CIDR (single AZ demo)" 
    default = "10.20.1.0/24" 
}
variable "availability_zone" { 
    description = "AZ for the public subnet (optional). Leave blank to let AWS pick." 
    type = string 
    default = "us-west-2a" 
}

# App container port
variable "container_port" { 
    description = "Container port exposed by your app" 
    default = 8000 
}

# initial image placeholder used for first task definition (CI will update it)
variable "initial_image" { 
    default = "amazon/amazon-ecs-sample" 
}