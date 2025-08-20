############################################
# Networking (VPC, Subnet, IGW, Route Table)
############################################
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "${var.project}-${var.env}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "${var.project}-${var.env}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone != "" ? var.availability_zone : null
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.env}-public-1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.project}-${var.env}-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

############################################
# ECS Fargate
############################################
data "aws_ecr_repository" "existing" {
  count = var.ecr_repo_url == "" ? 1 : 0
  name  = var.ecr_repo_name
}

locals {
  ecr_repo_url = var.ecr_repo_url != "" ? var.ecr_repo_url : (
    var.ecr_repo_name != "" ? data.aws_ecr_repository.existing[0].repository_url : var.initial_image
  )
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-${var.env}-cluster"
}

resource "aws_iam_role" "task_exec_role" {
  name = "${var.project}-${var.env}-task-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_exec_attachment" {
  role       = aws_iam_role.task_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project}-${var.env}"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "task" {
  family                   = "${var.project}-${var.env}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_exec_role.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = local.ecr_repo_url
      essential = true
      portMappings = [{
        containerPort = var.container_port,
        hostPort      = var.container_port,
        protocol      = "tcp"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_security_group" "svc_sg" {
  name   = "${var.project}-${var.env}-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow inbound HTTP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.env}-sg" }
}

resource "aws_ecs_service" "svc" {
  name            = "${var.project}-${var.env}-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public.id]
    security_groups  = [aws_security_group.svc_sg.id]
    assign_public_ip = true
  }

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_iam_role_policy_attachment.task_exec_attachment]
}

############################################
# IAM for Vault AWS Engine + Deploy Role
############################################

data "aws_caller_identity" "current" {}

# IAM User for Vault AWS Engine
resource "aws_iam_user" "vault_aws_engine" {
  name = "${var.project}-${var.env}-vault-aws-engine"
}

resource "aws_iam_access_key" "vault_aws_engine" {
  user = aws_iam_user.vault_aws_engine.name
}

resource "aws_iam_user_policy" "vault_aws_engine_assume" {
  name = "${var.project}-${var.env}-vault-assume-deployrole"
  user = aws_iam_user.vault_aws_engine.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "sts:AssumeRole",
      Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-${var.env}-ECR_ECS_DeployRole"
    }]
  })
}

# IAM Role for ECS/ECR Deployment
resource "aws_iam_role" "ecr_ecs_deploy_role" {
  name = "${var.project}-${var.env}-ECR_ECS_DeployRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        AWS = aws_iam_user.vault_aws_engine.arn
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecr_ecs_deploy_policy" {
  name = "${var.project}-${var.env}-ECR_ECS_DeployPolicy"
  role = aws_iam_role.ecr_ecs_deploy_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "EcrPushPull",
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories"
        ],
        Resource = "*"
      },
      {
        Sid    = "EcsRegisterAndDeploy",
        Effect = "Allow",
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTaskDefinitions",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService"
        ],
        Resource = "*"
      }
    ]
  })
}

############################################
# Vault EC2 Configuration
############################################

# Vault EC2 Instance Security Group (ports 22, 8200, 8201)
resource "aws_security_group" "vault_sg" {
  vpc_id = aws_vpc.this.id
  name   = "${var.project}-${var.env}-vault-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow inbound SSH"
  }

  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow inbound Vault HTTP"
  }

  ingress {
    from_port   = 8201
    to_port     = 8201
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow inbound Vault Cluster"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-vault-sg"
  }
}

# Generate SSH Key Pair for AWS Vault
resource "tls_private_key" "aws_vault_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "aws_vault_key_pair" {
  key_name   = "${var.name}-key"
  public_key = tls_private_key.aws_vault_key.public_key_openssh
}

# Save the private key to a local file (optional)
resource "local_file" "aws_vault_private_key" {
  content         = tls_private_key.aws_vault_key.private_key_pem
  filename        = "${path.module}/aws_vault_key.pem"
  file_permission = "0600"
}

# EC2 Vault Instance
resource "aws_instance" "vault" {
  ami                    = var.vault_ami_id
  instance_type          = var.vault_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.vault_sg.id]
  key_name               = aws_key_pair.aws_vault_key_pair.key_name
  user_data              = file("vault.sh")

  tags = {
    Name = "${var.project}-${var.env}-vault"
  }
}