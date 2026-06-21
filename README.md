# AWS Observability Platform with AI Incident Response

A serverless observability platform on AWS that automatically generates structured incident runbooks when something breaks — using distributed tracing, CloudWatch alarms, and Claude via AWS Bedrock.

Built to demonstrate end-to-end AWS engineering: Lambda, CloudWatch, X-Ray, SNS, Bedrock, Terraform, and GitHub Actions.

---

## The problem this solves

A CloudWatch alarm fires. It tells you an error rate crossed a threshold. It doesn't tell you why, what's affected, or where to start looking. The engineer on call has to open the console, pull logs, correlate traces, and reconstruct the story manually — every single time.

This platform automates that investigation step. When an alarm fires, the system reads the alarm details and recent distributed traces, sends them to Claude through AWS Bedrock, and generates a full incident runbook: root cause hypothesis, immediate actions with exact AWS CLI commands, an investigation checklist, and clear resolution criteria — delivered by email in under 30 seconds.

This builds on an earlier project where I did something similar on Azure using Prometheus and Claude API, but takes it further with distributed tracing and structured, actionable remediation steps instead of just an explanation.

---

## How it works

```
app-service Lambda → calls → order-service Lambda
         (both instrumented with OpenTelemetry + X-Ray)
                          ↓
         order-service fails at a fixed rate (simulated)
                          ↓
         CloudWatch tracks error count per minute
                          ↓
         Alarm fires when errors exceed threshold
                          ↓
         SNS topic receives the alarm notification
                          ↓
         ┌────────────────┴────────────────┐
         ↓                                  ↓
   Email subscriber              runbook-generator Lambda
   (raw alarm notification)              ↓
                              Reads alarm + X-Ray traces
                                          ↓
                              Calls Claude via AWS Bedrock
                                          ↓
                              Generates structured runbook
                                          ↓
                              Publishes back to SNS
                                          ↓
                              Email: full AI-generated runbook
```

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    app-service-dev                        │
│         (Lambda, OpenTelemetry, X-Ray tracing)             │
└───────────────────────────┬────────────────────────────────┘
                            │ invokes
┌───────────────────────────▼────────────────────────────────┐
│                   order-service-dev                         │
│   (Lambda, intentional 30% failure rate, X-Ray tracing)     │
└───────────────────────────┬────────────────────────────────┘
                            │ errors tracked
┌───────────────────────────▼────────────────────────────────┐
│              CloudWatch Alarm: high-error-rate-dev          │
│         Errors > 2 in 1 minute → ALARM                      │
└───────────────────────────┬────────────────────────────────┘
                            │ publishes
┌───────────────────────────▼────────────────────────────────┐
│         SNS Topic: runbook-notifications-dev                │
└──────────┬────────────────────────────────────┬─────────────┘
           │                                    │
┌──────────▼──────────┐          ┌──────────────▼──────────────┐
│   Email subscriber   │          │   runbook-generator-dev      │
│   (raw alarm email)  │          │   Lambda                     │
└───────────────────────┘          │                              │
                                    │ 1. Fetch alarm + X-Ray traces│
                                    │ 2. Call Claude via Bedrock   │
                                    │ 3. Generate structured       │
                                    │    runbook                   │
                                    │ 4. Publish via SNS           │
                                    └──────────────┬──────────────┘
                                                    │
                                    ┌───────────────▼───────────────┐
                                    │   Email: AI-generated runbook  │
                                    │   - Severity                   │
                                    │   - Root cause hypothesis      │
                                    │   - Immediate actions + CLI    │
                                    │   - Investigation steps        │
                                    │   - Resolution criteria        │
                                    └─────────────────────────────────┘
```

---

## Tech stack

| Component | Technology |
|-----------|-----------|
| Compute | AWS Lambda (Python 3.11) |
| Distributed tracing | OpenTelemetry SDK + AWS X-Ray |
| Monitoring | CloudWatch Metrics + Alarms |
| Messaging | SNS (alarm routing + email delivery) |
| AI | AWS Bedrock (Claude Sonnet 4.6) |
| Infrastructure as Code | Terraform |
| CI/CD | GitHub Actions |
| Storage | S3 (Lambda packages, Terraform state) |

---

## Screenshots

### AI-generated incident runbook
The full structured response Claude generates from a CloudWatch alarm — severity, root cause, and exact remediation commands:

![AI runbook email](docs/screenshots/runbook-email.png)

### Live invocation — terminal log
Real-time CloudWatch logs showing the runbook generator successfully calling Bedrock and publishing the response:

![Terminal logs](docs/screenshots/terminal-logs.png)

### CloudWatch alarm state history
OK → ALARM → OK transitions tracked over multiple test runs:

![Alarm history](docs/screenshots/alarm-history.png)

### Deployed Lambda functions
![Lambda functions](docs/screenshots/lambda-functions.png)

---

## Repository structure

```
aws-observability/
├── terraform/
│   ├── main.tf          # SNS, IAM, CloudWatch alarm, S3 references
│   ├── lambdas.tf        # Lambda function definitions
│   ├── variables.tf
│   └── outputs.tf
├── lambdas/
│   ├── app_service/
│   │   ├── main.py       # Entry service, calls order-service
│   │   └── requirements.txt
│   ├── order_service/
│   │   ├── main.py       # Downstream service, simulated failures
│   │   └── requirements.txt
│   └── runbook_generator/
│       ├── main.py       # Alarm reader + Bedrock + SNS publisher
│       └── requirements.txt
└── .github/workflows/
    └── deploy.yml         # Package, upload, terraform apply, deploy
```

---

## Running it yourself

**Prerequisites:** AWS account, Terraform, AWS CLI, Python 3.11+

**1. Create S3 buckets for state and Lambda packages**
```bash
aws s3api create-bucket --bucket <your-tfstate-bucket> --region us-east-1
aws s3api create-bucket --bucket <your-lambda-bucket> --region us-east-1
```

**2. Enable Bedrock model access**

Go to AWS Console → Bedrock → Model catalog → request access to an active (non-legacy) Claude model. Verify it works:
```bash
aws bedrock list-foundation-models --region us-east-1 --by-provider anthropic
```

**3. Add GitHub secrets**
```
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_ACCOUNT_ID
AWS_REGION
SNS_EMAIL
```

**4. Push to main — GitHub Actions deploys everything**

**5. Confirm the SNS email subscription** in your inbox, then trigger test invocations:
```bash
aws lambda invoke --function-name app-service-dev --payload '{"order_id":"ORD-1001","customer_id":"CUST-501"}' out.json
```

Run it 15-20 times to cross the error threshold and trigger the alarm.

---

## What I learned debugging this

Most of the real difficulty wasn't application code — it was AWS Bedrock access. Several legacy models returned identical-looking access errors regardless of model ID format (raw ID vs inference profile). The actual root cause was a missing AWS Marketplace subscription permission on the Lambda execution role, which is required for every Anthropic model on Bedrock independently.

The fix that actually worked: testing the simplest possible Bedrock call directly with boto3 outside of Lambda, which isolated the problem from the application code and confirmed which models had genuine access versus which were blocked regardless of configuration.

---

## What I'd add next

- Teams notification channel alongside email for faster triage
- Multi-channel routing — critical alerts to a different channel than warnings
- Auto-remediation for known safe fixes (e.g., restarting a stuck function) with confirmation
- Cost tracking for Bedrock token usage per incident
- Cross-account alarm aggregation for multi-environment observability


