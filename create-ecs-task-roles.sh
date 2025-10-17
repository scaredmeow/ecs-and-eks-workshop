#!/bin/sh

# Simple POSIX script to create ECS Task Execution & Task roles

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
PARTITION="${PARTITION:-aws}"

echo "Detecting AWS account..."
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
if [ -z "$ACCOUNT_ID" ] || [ "$ACCOUNT_ID" = "None" ]; then
  echo "Error: unable to determine AWS account. Is AWS CLI configured?" >&2
  exit 1
fi

EXEC_ROLE_NAME="retailStoreEcsTaskExecutionRole"
TASK_ROLE_NAME="retailStoreEcsTaskRole"
EXEC_POLICY_ARN="arn:${PARTITION}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"

TRUST_FILE="./ecs-trust-policy.json"

# Write trust policy to a file (portable; avoids non-POSIX tricks)
cat > "$TRUST_FILE" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ecs-tasks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

echo "Using account: $ACCOUNT_ID  region: $AWS_REGION  partition: $PARTITION"

# --- Execution Role (pull images, push logs) ---
if aws iam get-role --role-name "$EXEC_ROLE_NAME" >/dev/null 2>&1; then
  echo "Updating trust policy for $EXEC_ROLE_NAME..."
  aws iam update-assume-role-policy \
    --role-name "$EXEC_ROLE_NAME" \
    --policy-document "file://$TRUST_FILE"
else
  echo "Creating $EXEC_ROLE_NAME..."
  aws iam create-role \
    --role-name "$EXEC_ROLE_NAME" \
    --assume-role-policy-document "file://$TRUST_FILE" \
    --description "Execution role for ECS Fargate tasks (pull images, push logs)" >/dev/null
fi

# Attach the managed policy (safe to call multiple times)
echo "Attaching AmazonECSTaskExecutionRolePolicy to $EXEC_ROLE_NAME (if not already)..."
aws iam attach-role-policy \
  --role-name "$EXEC_ROLE_NAME" \
  --policy-arn "$EXEC_POLICY_ARN" >/dev/null 2>&1 || true

# --- Task Role (your app's AWS access; no policies by default) ---
if aws iam get-role --role-name "$TASK_ROLE_NAME" >/dev/null 2>&1; then
  echo "Updating trust policy for $TASK_ROLE_NAME..."
  aws iam update-assume-role-policy \
    --role-name "$TASK_ROLE_NAME" \
    --policy-document "file://$TRUST_FILE"
else
  echo "Creating $TASK_ROLE_NAME..."
  aws iam create-role \
    --role-name "$TASK_ROLE_NAME" \
    --assume-role-policy-document "file://$TRUST_FILE" \
    --description "Application role for ECS Fargate tasks" >/dev/null
fi

EXEC_ROLE_ARN="arn:${PARTITION}:iam::${ACCOUNT_ID}:role/${EXEC_ROLE_NAME}"
TASK_ROLE_ARN="arn:${PARTITION}:iam::${ACCOUNT_ID}:role/${TASK_ROLE_NAME}"

echo
echo "Done. Use these in your task definition:"
echo "\"executionRoleArn\": \"${EXEC_ROLE_ARN}\","
echo "\"taskRoleArn\": \"${TASK_ROLE_ARN}\""

# Clean up file (optional)
# rm -f "$TRUST_FILE"
