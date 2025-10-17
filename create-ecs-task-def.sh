#!/bin/sh
# POSIX script: create CloudWatch log group and ECS task definition

set -eu

AWS_REGION="${AWS_REGION:-ap-southeast-1}"

# Check for AWS CLI
if ! command -v aws >/dev/null 2>&1; then
  echo "Error: aws CLI not found. Install it and run 'aws configure' first." >&2
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
if [ -z "$ACCOUNT_ID" ] || [ "$ACCOUNT_ID" = "None" ]; then
  echo "Error: could not determine AWS account." >&2
  exit 1
fi

LOG_GROUP_NAME="retail-store-ecs-tasks"

echo "Ensuring CloudWatch log group: $LOG_GROUP_NAME ..."
aws logs create-log-group --log-group-name "$LOG_GROUP_NAME" --region "$AWS_REGION" 2>/dev/null || true
aws logs put-retention-policy --log-group-name "$LOG_GROUP_NAME" --retention-in-days 14 --region "$AWS_REGION" || true

echo "Writing ECS task definition JSON..."

cat <<EOF > retail-store-ecs-ui-taskdef.json
{
    "family": "retail-store-ecs-ui",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
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
            "linuxParameters": { "initProcessEnabled": true },
            "healthCheck": {
                "command": ["CMD-SHELL", "curl -f http://localhost:8080/actuator/health || exit 1"],
                "interval": 10,
                "timeout": 5,
                "retries": 3,
                "startPeriod": 60
            },
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "${LOG_GROUP_NAME}",
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

# Validate JSON (if jq installed)
if command -v jq >/dev/null 2>&1; then
  jq . retail-store-ecs-ui-taskdef.json >/dev/null
else
  echo "Note: jq not found, skipping JSON validation."
fi

echo "Registering ECS task definition..."
aws ecs register-task-definition --cli-input-json file://retail-store-ecs-ui-taskdef.json --region "$AWS_REGION"

echo "✅ Done. Task definition registered and log group ensured."
