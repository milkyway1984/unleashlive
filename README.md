# Unleash live – AWS Multi-Region Assessment!

A production-ready, cost-optimised multi-region serverless stack deployed with Terraform.

## Architecture Overview

```
us-east-1 (primary)                    eu-west-1 (secondary)
──────────────────────────────         ──────────────────────────────
Cognito User Pool (auth)               ─────────── (auth consumer)
API Gateway HTTP API                   API Gateway HTTP API
  GET  /greet  ──► Lambda Greeter        GET  /greet  ──► Lambda Greeter
  POST /dispatch ► Lambda Dispatcher     POST /dispatch ► Lambda Dispatcher
Lambda Greeter                         Lambda Greeter
  ├── DynamoDB PutItem                   ├── DynamoDB PutItem
  └── SNS Publish ──────────────────────┘└── SNS Publish
Lambda Dispatcher                      Lambda Dispatcher
  └── ECS RunTask                        └── ECS RunTask
ECS Fargate Cluster                    ECS Fargate Cluster
  └── Task: aws-cli → SNS Publish        └── Task: aws-cli → SNS Publish
DynamoDB Table (GreetingLogs)          DynamoDB Table (GreetingLogs)
VPC + Public Subnets (no NAT)          VPC + Public Subnets (no NAT)
```

**Cost optimisations:**
- DynamoDB on-demand billing (PAY_PER_REQUEST) – zero cost when idle
- Fargate minimum CPU/memory (256 CPU / 512 MB)
- Public subnets for ECS tasks – eliminates NAT Gateway (~$32/month each)
- Lambda outside VPC – no ENI overhead or NAT required
- CloudWatch log retention set to 7 days

## Repository Structure

```
aws-assessment/
├── main.tf                        # Root: providers + module wiring
├── variables.tf                   # Root input variables
├── outputs.tf                     # API endpoints + Cognito IDs
├── terraform.tfvars.example       # Copy → terraform.tfvars and fill in
│
├── auth/                          # Cognito module (us-east-1 only)
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── modules/
│   ├── networking/                # VPC + public subnets (deployed per region)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── compute/                   # All compute resources (deployed per region)
│       ├── main.tf                # IAM, SGs, DynamoDB, ECS, Lambdas, API GW
│       ├── variables.tf
│       ├── outputs.tf
│       └── lambdas/
│           ├── greeter.py         # Lambda 1 – writes DynamoDB + publishes SNS
│           └── dispatcher.py      # Lambda 2 – triggers ECS RunTask
│
├── scripts/
│   └── test_deployment.py         # Automated test script
│
└── .github/
    └── workflows/
        └── deploy.yml             # CI/CD: lint → security → plan → apply → test
```

## Multi-Region Provider Strategy

Two aliased AWS providers are configured in `main.tf`:

```hcl
provider "aws" { alias = "us_east_1"; region = "us-east-1" }
provider "aws" { alias = "eu_west_1"; region = "eu-west-1" }
```

Each module invocation explicitly passes the correct provider alias. The `compute`
and `networking` modules accept any `aws` provider via `required_providers` with no
alias, allowing the root module to inject the region-specific provider. This makes the
modules reusable for any additional region with a single block addition in `main.tf`.

The Cognito User Pool (auth module) is intentionally deployed only in `us-east-1`.
Both regional API Gateways reference the same pool via its ARN – Cognito JWT
validation is stateless and works cross-region with no replication required.

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with credentials that have permissions to create:
  IAM roles, Lambda, API Gateway, DynamoDB, ECS, Cognito, VPC, CloudWatch
- Python 3.10+ with `boto3` and `requests` installed (for test script)

## Deployment

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/aws-assessment.git
cd aws-assessment
```

### 2. Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
candidate_email       = "your_email@example.com"
cognito_test_password = "YourSecurePass123!"
github_repo           = "https://github.com/YOUR_GITHUB_USERNAME/aws-assessment"
prefix                = "unleash"
```

### 3. Initialise and deploy

```bash
terraform init
terraform plan
terraform apply
```

Terraform will output the API endpoints and Cognito IDs after a successful apply:

```
cognito_user_pool_id    = "us-east-1_XXXXXXXXX"
cognito_client_id       = "XXXXXXXXXXXXXXXXXXXXXXXXXX"
api_endpoint_us_east_1  = "https://XXXXXXXX.execute-api.us-east-1.amazonaws.com"
api_endpoint_eu_west_1  = "https://XXXXXXXX.execute-api.eu-west-1.amazonaws.com"
```

### 4. Set the Cognito user permanent password

Because Cognito creates the user in `FORCE_CHANGE_PASSWORD` state, run this once:

```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username your_email@example.com \
  --password "YourSecurePass123!" \
  --permanent \
  --region us-east-1
```

## Running the Test Script

```bash
pip install boto3 requests

python scripts/test_deployment.py \
  --user-pool-id  $(terraform output -raw cognito_user_pool_id) \
  --client-id     $(terraform output -raw cognito_client_id) \
  --username      your_email@example.com \
  --password      "YourSecurePass123!" \
  --api-us        $(terraform output -raw api_endpoint_us_east_1) \
  --api-eu        $(terraform output -raw api_endpoint_eu_west_1)
```

Expected output:

```
── Step 1: Cognito Authentication ──────────────────────────────
  User Pool : us-east-1_XXXXXXXXX
  Username  : your_email@example.com
  ✓ PASS  JWT obtained (expires in 3600s)

── Step 2: Concurrent /greet calls ─────────────────────────────
  GET /greet  [us-east-1]
    HTTP Status    : 200  ✓ PASS
    Latency        : 142.3 ms
    Expected region: us-east-1
    Actual region  : us-east-1  ✓ PASS

  GET /greet  [eu-west-1]
    HTTP Status    : 200  ✓ PASS
    Latency        : 387.5 ms
    Expected region: eu-west-1
    Actual region  : eu-west-1  ✓ PASS

── Step 3: Concurrent /dispatch calls ──────────────────────────
  POST /dispatch [us-east-1]
    HTTP Status    : 200  ✓ PASS
    Latency        : 1243.8 ms
    Expected region: us-east-1
    Actual region  : us-east-1  ✓ PASS

  POST /dispatch [eu-west-1]
    HTTP Status    : 200  ✓ PASS
    Latency        : 1891.2 ms
    Expected region: eu-west-1
    Actual region  : eu-west-1  ✓ PASS

── Summary ─────────────────────────────────────────────────────
  ✓ PASS  All assertions passed.
```

## Tear Down

Once the SNS payloads have been successfully sent, destroy all resources:

```bash
terraform destroy
```

## CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/deploy.yml`) runs 5 jobs:

| Job | Trigger | Description |
|-----|---------|-------------|
| `lint-validate` | every push/PR | `terraform fmt -check` + `terraform validate` |
| `security-scan` | after lint | `checkov` static analysis scan |
| `plan` | after security | `terraform plan` (requires AWS credentials) |
| `deploy` | main branch push | `terraform apply` with manual approval gate |
| `integration-test` | after deploy | Runs `test_deployment.py` end-to-end |

AWS credentials are provided via **OIDC** (no long-lived keys):

```hcl
# In a real setup, create this IAM role with a trust policy scoped to your repo
role-to-assume: arn:aws:iam::ACCOUNT_ID:role/github-actions-terraform
```

Required GitHub Secrets:

| Secret | Description |
|--------|-------------|
| `CANDIDATE_EMAIL` | Your email address |
| `GITHUB_REPO` | Your repo URL |
| `COGNITO_USER_POOL_ID` | From `terraform output` |
| `COGNITO_CLIENT_ID` | From `terraform output` |
| `COGNITO_USERNAME` | Test user email |
| `COGNITO_PASSWORD` | Test user password |
| `API_ENDPOINT_US` | From `terraform output` |
| `API_ENDPOINT_EU` | From `terraform output` |
