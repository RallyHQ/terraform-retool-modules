/**
* Agents services are currently in beta and are not yet supported in the Terraform module.
* This file is a placeholder for future implementation. Agents services will be supported in the upstream Terraform module, remove this file once agents are supported.
*/

resource "aws_ecs_service" "agent_worker" {
  count                  = var.agents_enabled ? 1 : 0
  name                   = "${var.deployment_name}-agent-worker-service"
  cluster                = aws_ecs_cluster.this.id
  desired_count          = 1
  task_definition        = aws_ecs_task_definition.retool_agent_worker[0].arn
  propagate_tags         = var.task_propagate_tags
  enable_execute_command = var.enable_execute_command

  # Need to explictly set this in aws_ecs_service to avoid destructive behavior: https://github.com/hashicorp/terraform-provider-aws/issues/22823
  capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = var.launch_type == "FARGATE" ? "FARGATE" : aws_ecs_capacity_provider.this[0].name
  }

  dynamic "network_configuration" {
    for_each = var.launch_type == "FARGATE" ? toset([1]) : toset([])

    content {
      subnets = var.private_subnet_ids
      security_groups = [
        aws_security_group.containers.id
      ]
      assign_public_ip = true
    }
  }
}

resource "aws_ecs_service" "agent_eval_worker" {
  count                  = var.agents_enabled ? 1 : 0
  name                   = "${var.deployment_name}-agent-eval-worker-service"
  cluster                = aws_ecs_cluster.this.id
  desired_count          = 1
  task_definition        = aws_ecs_task_definition.retool_agent_eval_worker[0].arn
  propagate_tags         = var.task_propagate_tags
  enable_execute_command = var.enable_execute_command

  # Need to explictly set this in aws_ecs_service to avoid destructive behavior: https://github.com/hashicorp/terraform-provider-aws/issues/22823
  capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = var.launch_type == "FARGATE" ? "FARGATE" : aws_ecs_capacity_provider.this[0].name
  }

  dynamic "network_configuration" {
    for_each = var.launch_type == "FARGATE" ? toset([1]) : toset([])

    content {
      subnets = var.private_subnet_ids
      security_groups = [
        aws_security_group.containers.id
      ]
      assign_public_ip = true
    }
  }
}

resource "aws_ecs_task_definition" "retool_agent_worker" {
  count                    = var.agents_enabled ? 1 : 0
  family                   = "retool-agent-worker"
  task_role_arn            = aws_iam_role.task_role.arn
  execution_role_arn       = var.launch_type == "FARGATE" ? aws_iam_role.execution_role[0].arn : null
  requires_compatibilities = var.launch_type == "FARGATE" ? ["FARGATE"] : null
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  cpu                      = var.launch_type == "FARGATE" ? var.ecs_task_resource_map["agent_worker"]["cpu"] : null
  memory                   = var.launch_type == "FARGATE" ? var.ecs_task_resource_map["agent_worker"]["memory"] : null

  container_definitions = jsonencode(concat(
    local.common_containers,
    [
      {
        name      = "retool-agent-worker"
        essential = true
        image     = var.ecs_retool_image
        cpu       = var.launch_type == "EC2" ? var.ecs_task_resource_map["agent_worker"]["cpu"] : null
        memory    = var.launch_type == "EC2" ? var.ecs_task_resource_map["agent_worker"]["memory"] : null
        command = [
          "./docker_scripts/start_api.sh"
        ]

        logConfiguration = local.task_log_configuration

        portMappings = [
          {
            containerPort = 3005
            hostPort      = 3005
            protocol      = "tcp"
          }
        ]

        environment = concat(
          local.environment_variables,
          [
            {
              name  = "SERVICE_TYPE"
              value = "WORKFLOW_TEMPORAL_WORKER"
            },
            {
              name  = "WORKER_TEMPORAL_TASKQUEUE"
              value = "agent"
            },
            {
              name  = "NODE_OPTIONS"
              value = "--max_old_space_size=1024"
            },
            {
              "name"  = "COOKIE_INSECURE",
              "value" = tostring(var.cookie_insecure)
            }
          ]
        )
      }
    ]
  ))
}

resource "aws_ecs_task_definition" "retool_agent_eval_worker" {
  count                    = var.agents_enabled ? 1 : 0
  family                   = "retool-agent-eval-worker"
  task_role_arn            = aws_iam_role.task_role.arn
  execution_role_arn       = var.launch_type == "FARGATE" ? aws_iam_role.execution_role[0].arn : null
  requires_compatibilities = var.launch_type == "FARGATE" ? ["FARGATE"] : null
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  cpu                      = var.launch_type == "FARGATE" ? var.ecs_task_resource_map["agent_eval_worker"]["cpu"] : null
  memory                   = var.launch_type == "FARGATE" ? var.ecs_task_resource_map["agent_eval_worker"]["memory"] : null

  container_definitions = jsonencode(concat(
    local.common_containers,
    [
      {
        name      = "retool-agent-eval-worker"
        essential = true
        image     = var.ecs_retool_image
        cpu       = var.launch_type == "EC2" ? var.ecs_task_resource_map["agent_eval_worker"]["cpu"] : null
        memory    = var.launch_type == "EC2" ? var.ecs_task_resource_map["agent_eval_worker"]["memory"] : null
        command = [
          "./docker_scripts/start_api.sh"
        ]

        logConfiguration = local.task_log_configuration

        portMappings = [
          {
            containerPort = 3005
            hostPort      = 3005
            protocol      = "tcp"
          }
        ]

        environment = concat(
          local.environment_variables,
          [
            {
              name  = "SERVICE_TYPE"
              value = "AGENT_EVAL_TEMPORAL_WORKER"
            },
            {
              name  = "WORKER_TEMPORAL_TASKQUEUE"
              value = "agent-eval"
            },
            {
              name  = "NODE_OPTIONS"
              value = "--max_old_space_size=1024"
            },
            {
              "name"  = "COOKIE_INSECURE",
              "value" = tostring(var.cookie_insecure)
            }
          ]
        )
      }
    ]
  ))
}
