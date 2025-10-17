#!/bin/sh
# POSIX shell: create ECS task definition JSON and register it

set -eu

# Defaults (allow override from env)
AWS_REGION="${AWS_REGION:-ap-southeast-1}"

# Ensure AWS CLI is available
if ! command -v aws >/dev/null 2>&1; then
  echo "Error: aws CLI not found. Install and configure it first." >&2
  exit 1
fi

# Resolve account ID
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
if [ -z "$ACCOUNT_ID" ] || [ "$ACCOUNT_ID" = "None" ]; then
  echo "Error: could not determine AWS account (run 'aws configure')." >&2
  exit 1
fi

# Write task definition JSON (variables expand in this heredoc)
cat <<EOF > retail-store-ecs-ui-taskdef.json
{
    "family": "retail-store-ecs-ui",
    "networkMode": "awsvpc",
    "requiresCompatibilities": [
        "FARGATE"
    ],
    "cpu": "1024",
    "memory": "2048",
    "runtimePlatform": {
        "cpuArchitecture": "X86_64",
        "operatingSystemFamily": "LINUX"
    },
    "containerDefinitions": [
        {
            "name": "application",
            "image": "public.ecr.aws/aws-containers/retail-store-sample-ui:1.2.3",
            "portMappings": [
                {
                    "name": "application",
                    "containerPort": 8080,
                    "hostPort": 8080,
                    "protocol": "tcp",
                    "appProtocol": "http"
                }
            ],
            "essential": true,
            "linuxParameters": {
                "initProcessEnabled": true
            },
            "healthCheck": {
                "command": [
                    "CMD-SHELL",
                    "curl -f http://localhost:8080/actuator/health || exit 1"
                ],
                "interval": 10,
                "timeout": 5,
                "retries": 3,
                "startPeriod": 60
            },
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "retail-store-ecs-tasks",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ui-service"
                }
            }
        }
    ],
    "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/retailStoreEcsTaskExecutionRole",
    "taskRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/retailStoreEcsTaskRole"
}
EOF

# Optional JSON validation (only if jq is installed)
if command -v jq >/dev/null 2>&1; then
  jq . retail-store-ecs-ui-taskdef.json >/dev/null
else
  echo "Note: jq not found; skipping JSON validation." >&2
fi

# Register the task definition
aws ecs register-task-definition --cli-input-json file://retail-store-ecs-ui-taskdef.json --region "$AWS_REGION"

echo "Registered task definition using ACCOUNT_ID=$ACCOUNT_ID, AWS_REGION=$AWS_REGION"
