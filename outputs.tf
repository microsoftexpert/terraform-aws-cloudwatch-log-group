###############################################################################
# Primary outputs (id + arn)
###############################################################################

output "id" {
 description = "The log group id (the log group name)."
 value = aws_cloudwatch_log_group.this.id
}

output "arn" {
 description = <<EOT
ARN of the log group (cross-resource reference type). The provider returns the
form WITHOUT the trailing ":*" stream suffix
(arn:aws:logs:<region>:<account>:log-group:<name>) for compatibility with
services that reject the suffix. Use arn_with_suffix for consumers that require
":*" (e.g. CloudTrail's cloud_watch_logs_group_arn).
EOT
 value = aws_cloudwatch_log_group.this.arn
}

output "arn_with_suffix" {
 description = <<EOT
The log group ARN with the trailing ":*" stream suffix
(arn:aws:logs:<region>:<account>:log-group:<name>:*). Required by some consumers
(CloudTrail CloudWatch Logs integration, certain IAM resource scopes) that expect
the all-streams form.
EOT
 value = "${aws_cloudwatch_log_group.this.arn}:*"
}

output "name" {
 description = "The name of the log group. Consumed as the log-destination by VPC flow logs, Lambda, ECS/EKS, CloudTrail, etc."
 value = aws_cloudwatch_log_group.this.name
}

output "kms_key_id" {
 description = "ARN of the KMS CMK encrypting log data, or null when using the AWS-owned CloudWatch Logs key."
 value = aws_cloudwatch_log_group.this.kms_key_id
}

output "retention_in_days" {
 description = "Effective retention period in days (0 means never expire)."
 value = aws_cloudwatch_log_group.this.retention_in_days
}

output "log_group_class" {
 description = "The log class of the group (STANDARD, INFREQUENT_ACCESS, or DELIVERY)."
 value = aws_cloudwatch_log_group.this.log_group_class
}

###############################################################################
# Child collections
###############################################################################

output "metric_filter_ids" {
 description = "Map of metric filter name => metric filter id for every metric filter created. Consumed by CloudWatch alarms."
 value = { for k, mf in aws_cloudwatch_log_metric_filter.this: k => mf.id }
}

output "subscription_filter_names" {
 description = "Set of subscription filter names created on this group."
 value = toset(keys(aws_cloudwatch_log_subscription_filter.this))
}

output "log_stream_arns" {
 description = "Map of log stream name => ARN for every explicit log stream created."
 value = { for k, s in aws_cloudwatch_log_stream.this: k => s.arn }
}

output "resource_policy_id" {
 description = "Id (policy name) of the resource-based policy when created; null otherwise."
 value = try(aws_cloudwatch_log_resource_policy.this["this"].id, null)
}

###############################################################################
# Tags
###############################################################################

output "tags_all" {
 description = "All tags on the log group, including those inherited from provider default_tags (resource tags win on key conflict)."
 value = aws_cloudwatch_log_group.this.tags_all
}
