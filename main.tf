provider "aws" {
  region = "ap-south-1"
}

# Default VPC & subnets 
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group (ECS + RDS)
resource "aws_security_group" "strapi_sg" {
  name   = "strapi-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 1337
    to_port     = 1337
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 80
    to_port   = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port   = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS PostgreSQL
resource "aws_db_subnet_group" "default" {
  name       = "default-db-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "strapi_db" {
  identifier              = "strapi-db"
  allocated_storage       = 20
  engine                  = "postgres"
  engine_version          = "17.5"
  instance_class          = "db.t3.micro"
  db_name                 = "strapidb"
  username                = "strapi"
  password                = "SuperSecret123"
  skip_final_snapshot     = true
  publicly_accessible     = true
  vpc_security_group_ids  = [aws_security_group.strapi_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.default.name
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "strapi" {
  name              = "/ecs/strapi"
  retention_in_days = 7
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Cluster
resource "aws_ecs_cluster" "strapi" {
  name = "strapi-cluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "strapi" {
  family                   = "strapi-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name  = "strapi"
    image = "300759653674.dkr.ecr.ap-south-1.amazonaws.com/strapi:latest"
    essential = true
    portMappings = [{
      containerPort = 1337
      hostPort      = 1337
    }]
    environment = [
      { name = "DATABASE_CLIENT", value = "postgres" },
      { name = "DATABASE_HOST", value = aws_db_instance.strapi_db.address },
      { name = "DATABASE_PORT", value = "5432" },
      { name = "DATABASE_NAME", value = "strapidb" },
      { name = "DATABASE_USERNAME", value = "strapi" },
      { name = "DATABASE_PASSWORD", value = "SuperSecret123" },
      { name = "DATABASE_SSL", value = "true" },
      { name = "PGSSLMODE", value = "require" },
      { name = "DATABASE_SSL_REJECT_UNAUTHORIZED", value = "false" },
      { name = "JWT_SECRET", value = "your-random-generated-secret" },
      { 
        name = "APP_KEYS", 
        value = "RlGyn2Rptbc7U5SHCpF6lWVs836slllny9LYygyxPkI=, /7LSST6yHffbrJqQ48zZrvBgKfBtb4rePULFer7isMw=,mdaCm4kheWI1DS7QvhvMgsOE03UcVYVA/Os/qzPivwk=" 
      } 
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.strapi.name
        awslogs-region        = "ap-south-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# ECS Service
resource "aws_ecs_service" "strapi" {
  name            = "strapi-service"
  cluster         = aws_ecs_cluster.strapi.id
  task_definition = aws_ecs_task_definition.strapi.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    assign_public_ip = true
    security_groups  = [aws_security_group.strapi_sg.id]
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_task_execution_role_policy]
}

# Outputs ---
output "strapi_db_endpoint" {
  value = aws_db_instance.strapi_db.address
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.strapi.name
}

output "strapi_service_name" {
  value = aws_ecs_service.strapi.name
}
