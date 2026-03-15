# aws-assessment

Multi-region serverless infrastructure on AWS, built with Terraform. Deploys an authenticated API backed by Lambda, DynamoDB, and ECS Fargate across **us-east-1** and **eu-west-1**.

---

## What this does

- Cognito User Pool in us-east-1 handles auth for both regions
- Two API Gateway endpoints (`/greet` and `/dispatch`) deployed identically in each region
- `/greet` writes a record to a regional DynamoDB table and publishes a verification message to SNS
- `/dispatch` triggers a short-lived Fargate task that also publishes to SNS then exits
- All endpoints are JWT-protected via the Cognito authorizer

---

## Repo structure

```
unleashlive-assessment/
├── terraform/
│   ├── main.tf                   # root config, provider aliases, module calls
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── auth/                 # Cognito user pool, client, test user
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── versions.tf
│       └── compute/              # API GW, Lambdas, DynamoDB, ECS, VPC
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── versions.tf
├── lambdas/
│   ├── greeter/
│   │   ├── index.js
│   │   └── package.json
│   └── dispatcher/
│       ├── index.js
│       └── package.json
├── tests/
│   └── run_tests.js              # end-to-end test script, no extra dependencies
├── .github/
│   └── workflows/
│       └── deploy.yml
└── README.md
```

---

## How the multi-region setup works

The approach is straightforward — two provider aliases in the root module, one per region:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}
```

The `compute` module is then called twice, each time with a different provider passed in:

```hcl
module "compute_us_east_1" {
  source     = "./modules/compute"
  providers  = { aws = aws.us_east_1 }
  aws_region = "us-east-1"
  ...
}

module "compute_eu_west_1" {
  source     = "./modules/compute"
  providers  = { aws = aws.eu_west_1 }
  aws_region = "eu-west-1"
  ...
}
```

This way there's a single module definition and both regions stay in sync automatically. The `aws_region` variable is passed explicitly because Terraform doesn't automatically expose the provider's region to resources — Lambda env vars, resource names, and the ECS task payload all need to know which region they're running in.

Cognito only lives in us-east-1. Both API Gateways use the same User Pool for JWT validation by pointing their authorizer at the same issuer URL.

Each child module has its own `versions.tf` declaring `required_providers`. This is needed when a parent passes aliased providers into a child — without it Terraform warns it can't verify the provider source.

---

## Prerequisites

- Terraform >= 1.10.0
- Node.js >= 20.x
- AWS CLI v2
- An AWS account with permissions for Cognito, Lambda, API Gateway, DynamoDB, ECS, IAM, VPC, CloudWatch, SNS

---

## Deploying manually

### 1. Clone and install Lambda dependencies

```bash
git clone https://github.com/dubebygaurav-Tech/unleashlive-assessment.git
cd unleashlive-assessment

(cd lambdas/greeter    && npm install)
(cd lambdas/dispatcher && npm install)
```

### 2. Create the S3 backend bucket

Only needs to be done once. `use_lockfile = true` handles state locking natively so no DynamoDB table is needed.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="aws-assessment-tfstate-${ACCOUNT_ID}"

aws s3 mb s3://${BUCKET} --region us-east-1
aws s3api put-bucket-versioning \
  --bucket ${BUCKET} \
  --versioning-configuration Status=Enabled
```

Then update the bucket name in the `backend` block in `terraform/main.tf`.

### 3. Set your variables
Create a new tfvars file and fill in your email, passwords, and GitHub repo URL

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

### 4. Apply

```bash
terraform init
terraform plan
terraform apply
```

After apply, the outputs will show the API URLs and Cognito IDs needed for testing:

```
api_endpoint_us_east_1 = "https://xxxx.execute-api.us-east-1.amazonaws.com"
api_endpoint_eu_west_1 = "https://xxxx.execute-api.eu-west-1.amazonaws.com"
cognito_user_pool_id   = "us-east-1_XXXXXXXXX"
cognito_client_id      = "xxxxxxxxxxxxxxxxxxxxxxxxxx"
```

---

## Running the test script

The script has no npm dependencies — just Node.js built-ins. It authenticates with Cognito, then hits both regions concurrently for both endpoints and asserts the region in each response.

```bash
node tests/run_tests.js \
  --user-pool-id "$(cd terraform && terraform output -raw cognito_user_pool_id)" \
  --client-id    "$(cd terraform && terraform output -raw cognito_client_id)" \
  --username     "your.email@example.com" \
  --password     "YourPassword1!" \
  --api-us       "$(cd terraform && terraform output -raw api_endpoint_us_east_1)" \
  --api-eu       "$(cd terraform && terraform output -raw api_endpoint_eu_west_1)"
```

Or export everything as env vars first:

```bash
export COGNITO_USER_POOL_ID="us-east-1_XXXXXXXXX"
export COGNITO_CLIENT_ID="xxxxxxxxxxxxxxxxxxxxxxxxxx"
export COGNITO_USERNAME="your.email@example.com"
export COGNITO_PASSWORD="YourPassword1!"
export API_URL_US_EAST_1="https://xxxx.execute-api.us-east-1.amazonaws.com"
export API_URL_EU_WEST_1="https://xxxx.execute-api.eu-west-1.amazonaws.com"

node tests/run_tests.js
```

Expected output:

```
╔══════════════════════════════════════╗
║   AWS Assessment – E2E Test Suite    ║
╚══════════════════════════════════════╝
  Regions : us-east-1 + eu-west-1

═══ Step 1: Cognito Authentication ═══
  ✔  JWT obtained (1081 chars, latency: 312 ms)

═══ Step 2: Concurrent GET /greet ═══
  ✔  [us-east-1] HTTP 200 | region="us-east-1" ✓ | latency: 187 ms
  ✔  [eu-west-1] HTTP 200 | region="eu-west-1" ✓ | latency: 341 ms
  ℹ  Geographic latency delta: 154 ms

═══ Step 3: Concurrent POST /dispatch ═══
  ✔  [us-east-1] HTTP 200 | region="us-east-1" ✓ | latency: 1923 ms
  ✔  [eu-west-1] HTTP 200 | region="eu-west-1" ✓ | latency: 2107 ms

═══ Summary ═══
  All tests PASSED ✔
```

---

## CI/CD pipeline

The pipeline in `.github/workflows/deploy.yml` runs five jobs in sequence:

- **lint-validate** — `terraform fmt -check`, `terraform validate`, npm checks on both Lambdas
- **security-scan** — checkov scans the Terraform code and uploads SARIF to GitHub Security
- **plan** — `terraform plan`, saves the plan as an artifact, posts a diff comment on PRs
- **deploy** — `terraform apply` on merges to main, gated behind a manual approval in GitHub Environments
- **test** — runs `run_tests.js` post-deploy using the Terraform outputs from the previous job

### GitHub Secrets needed

| Secret | What it's for |
|--------|---------------|
| `AWS_ACCESS_KEY_ID` | IAM access key |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key |
| `CANDIDATE_EMAIL` | Cognito username and SNS payload email |
| `TEST_USER_TEMP_PASSWORD` | Initial Cognito password |
| `TEST_USER_PASSWORD` | Permanent Cognito password |

### GitHub Variables needed

| Variable | Example |
|----------|---------|
| `GITHUB_REPO` | `https://github.com/dubeygaurav-Tech/unleashlive-assessment` |

---

## Cost considerations

Kept deliberately cheap:

- DynamoDB on `PAY_PER_REQUEST` — no cost when idle
- Fargate tasks use `FARGATE_SPOT` — up to 70% cheaper than standard Fargate
- ECS tasks run in public subnets with `assignPublicIp: ENABLED` — no NAT Gateway needed
- Lambda and API Gateway HTTP API are effectively free at this scale

---

## Troubleshooting

**`HTTP 000` from curl** — the API URL variable is empty. Re-export it:
```bash
export API_US=$(terraform output -raw api_endpoint_us_east_1)
```

**`401 Unauthorized`** — JWT has expired (1hr TTL). Re-run the Cognito auth step.

**`403 Forbidden`** — make sure you're using the `IdToken` not the `AccessToken` from Cognito.

**ECS task shows as `STOPPED` immediately** — this is expected. The task runs `aws sns publish` and exits. Check the logs at `/ecs/aws-assessment-publisher-<region>` in CloudWatch if you want to confirm it ran.

**`jq: parse error`** — the `-w` timing string from curl is being piped into jq. Use `-o /tmp/r.json` to write the body separately:
```bash
curl -s -o /tmp/r.json -w "HTTP %{http_code}\n" -H "Authorization: $TOKEN" $API_US/greet
jq . /tmp/r.json
```

---

## Tear down

```bash
cd terraform
terraform destroy \
  -var="candidate_email=your.email@example.com" \
  -var="test_user_temp_password=TempPass1!" \
  -var="test_user_password=SecurePass1!"
```