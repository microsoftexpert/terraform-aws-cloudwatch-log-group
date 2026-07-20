# terraform-aws-cloudwatch-log-group — SCOPE

Composite module for a secure-by-default Amazon CloudWatch Logs log group. It owns
the log group (retention enforced, optional SSE-KMS encryption) plus its optional
metric filters, subscription filters, resource policy, and log streams, so that a
single module call produces an encrypted, retention-bounded logging target aligned
with the Casey's (NPI / GLBA / FCA) baseline.

- **Module type:** Composite
- **Primary resource (keystone):** `aws_cloudwatch_log_group.this`

## In-scope resources

The module manages **all** of the following (allow-list):

- `aws_cloudwatch_log_group` — keystone
- `aws_cloudwatch_log_metric_filter` — metric filters (`for_each` over `map(object(...))`)
- `aws_cloudwatch_log_subscription_filter` — subscription filters (`for_each`)
- `aws_cloudwatch_log_resource_policy` — optional resource-based policy granting AWS services log-delivery access
- `aws_cloudwatch_log_stream` — optional explicit log streams (`for_each`)

## Out-of-scope resources (consumed by reference)

Referenced by `arn`/`id`/`name`, never created here:

- KMS CMK for log encryption — `kms_key_arn` (from `terraform-aws-kms`)
- Subscription-filter destination (Kinesis stream, Firehose, or Lambda) —
  `destination_arn` (by ARN)
- IAM role CloudWatch Logs assumes to deliver to a cross-account destination —
  `role_arn` on a subscription filter (from `terraform-aws-iam-role`)
- CloudWatch metric namespace targeted by metric filters (logical, not a resource)

## Consumes

| Input | Type | Source module |
|---|---|---|
| `kms_key_arn` | `string` (KMS key ARN) | `terraform-aws-kms` |
| `subscription_filters[*].destination_arn` | `string` (Kinesis/Firehose/Lambda ARN) | app integration / analytics modules |
| `subscription_filters[*].role_arn` | `string` (IAM role ARN) | `terraform-aws-iam-role` |

> Foundation logging target: this module is consumed *by* many others
> (`terraform-aws-vpc` flow logs, Lambda, ECS, EKS, `terraform-aws-cloudtrail`) which pass
> this group's `arn`/`name` as their log destination.

## Required IAM permissions

Least-privilege actions the Terraform identity needs:

| Action | Required for |
|---|---|
| `logs:CreateLogGroup`, `logs:DeleteLogGroup` | Log group lifecycle |
| `logs:PutRetentionPolicy`, `logs:DeleteRetentionPolicy` | Retention enforcement |
| `logs:AssociateKmsKey`, `logs:DisassociateKmsKey` | SSE-KMS association |
| `logs:DescribeLogGroups`, `logs:ListTagsForResource` | Read/refresh |
| `logs:TagResource`, `logs:UntagResource` | Tagging |
| `logs:PutMetricFilter`, `logs:DeleteMetricFilter`, `logs:DescribeMetricFilters` | Metric filters |
| `logs:PutSubscriptionFilter`, `logs:DeleteSubscriptionFilter`, `logs:DescribeSubscriptionFilters` | Subscription filters |
| `logs:PutResourcePolicy`, `logs:DeleteResourcePolicy`, `logs:DescribeResourcePolicies` | Resource policy |
| `logs:CreateLogStream`, `logs:DeleteLogStream`, `logs:DescribeLogStreams` | Explicit log streams |
| `iam:PassRole` (on a subscription filter `role_arn`) | Pass the cross-account delivery role to a subscription filter |
| `kms:DescribeKey` (on `kms_key_arn`) | Validate the CMK at association |

## AWS Prerequisites

- **No service-linked role** required for CloudWatch Logs itself.
- **KMS key policy (when `kms_key_arn` set).** The CMK policy must allow the
  CloudWatch Logs service principal `logs.<region>.amazonaws.com`
  `kms:Encrypt*` / `kms:Decrypt*` / `kms:GenerateDataKey*` / `kms:Describe*`, scoped
  with an `kms:EncryptionContext:aws:logs:arn` condition to this log group ARN.
- **Subscription-filter destination (optional).** The Kinesis/Firehose/Lambda
  target must exist and (for cross-account) carry a destination policy; a Lambda
  target needs a resource-based permission allowing `logs.amazonaws.com` to invoke.
- **Quotas.** Default soft limits include a maximum of **2 subscription filters per
  log group** and a per-region cap on metric filters; retention is one of the
  allowed discrete day values (1…3653) or never-expire.
- **Region:** provider-inherited; no `region` variable. Not a us-east-1 global.

## Emits

| Output | Description | Consumed by |
|---|---|---|
| `id` | Log group id (the group name) | metric/subscription filters |
| `arn` | Log group ARN **without** the `:*` suffix (`arn:aws:logs:<region>:<account>:log-group:<name>`) — cross-resource reference type | VPC flow logs, IAM policy resources, services that reject the suffix |
| `arn_with_suffix` | Log group ARN **with** the trailing `:*` (`…:log-group:<name>:*`) | CloudTrail `cloud_watch_logs_group_arn`, all-streams IAM scopes |
| `name` | Log group name | service log-destination wiring |
| `metric_filter_ids` | Map of metric filter ids | alarms |
| `subscription_filter_names` | Set of subscription filter names | inspection |
| `log_stream_arns` | Map of log stream name → ARN | producers expecting a named stream |
| `resource_policy_id` | Resource-policy id when created; else `null` | inspection |
| `tags_all` | All tags incl. provider `default_tags` | governance/audit |

## Provider gotchas

- **`name` is FORCE-NEW.** Renaming the log group destroys and recreates it (and
  discards retained log data) — prefer `name_prefix` when churn is expected.
- **ARN `:*` suffix.** The provider returns `arn` **without** the trailing `:*`;
  the module exposes the all-streams form separately as `arn_with_suffix`. Some
  consumers (e.g. CloudTrail's `cloud_watch_logs_group_arn`) require the suffix,
  others reject it — pass the correct output per consumer.
- **`log_group_class` is FORCE-NEW**, and `INFREQUENT_ACCESS` groups do not
  support metric or subscription filters (or Live Tail).
- **`tags` vs `tags_all`.** `var.tags` flows to `aws_cloudwatch_log_group.this.tags`;
  `tags_all` is the computed merge over provider `default_tags` (resource tags win).
  `default_tags` is the **caller's** provider-block concern.
- **`arn` is the cross-resource reference type.**
- **Two-subscription-filter cap.** A third `aws_cloudwatch_log_subscription_filter`
  on the same group will fail at apply (`LimitExceededException`).
- **KMS disassociation on destroy.** Deleting the group while a CMK is associated is
  fine, but rotating to a new key requires disassociate-then-associate.

## Secure-by-default decisions

| Posture | Default | Opt-out |
|---|---|---|
| Retention | `retention_in_days = 365` (1 year) — never unbounded | set a different allowed value |
| Encryption at rest | SSE-KMS when `kms_key_arn` set; AWS-owned key otherwise | supply/omit `kms_key_arn` |
| Resource policy | none unless explicitly configured | n/a |

> CloudWatch Logs are always encrypted at rest by an AWS-owned key by default;
> supplying `kms_key_arn` upgrades to a customer-managed CMK for full key control.

## Design decisions

- One composite owns the group plus its filters, resource policy, and streams so a
  single call produces a complete, retention-bounded, encrypted logging target.
- Metric filters, subscription filters, the resource policy, and explicit log
  streams are all **optional** (`map(object(...))` / `optional(...)` defaulting
  empty) and rendered via `dynamic`/`for_each` — absent unless configured.
- The CMK, subscription destinations, and delivery roles are referenced by `arn`,
  keeping this foundation module's blast radius to a single log group.
