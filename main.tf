###############################################################################
# CloudWatch log group (keystone)
#
# Secure by default: a bounded retention period (never unbounded) and, when a CMK
# is supplied, SSE-KMS encryption at rest. Log data is always encrypted at rest by
# the AWS-owned CloudWatch Logs key even when kms_key_arn is null.
###############################################################################

resource "aws_cloudwatch_log_group" "this" {
 name = var.name
 name_prefix = var.name_prefix

 retention_in_days = var.retention_in_days
 kms_key_id = var.kms_key_arn
 log_group_class = var.log_group_class

 skip_destroy = var.skip_destroy

 tags = var.tags
}

###############################################################################
# Metric filters — emit CloudWatch metrics from matched log events
###############################################################################

resource "aws_cloudwatch_log_metric_filter" "this" {
 for_each = var.metric_filters

 name = each.key
 log_group_name = aws_cloudwatch_log_group.this.name
 pattern = each.value.filter_pattern

 metric_transformation {
 name = each.value.metric_transformation.name
 namespace = each.value.metric_transformation.namespace
 value = each.value.metric_transformation.value
 default_value = try(each.value.metric_transformation.default_value, null)
 unit = each.value.metric_transformation.unit
 dimensions = try(each.value.metric_transformation.dimensions, null)
 }
}

###############################################################################
# Subscription filters — stream matched events to Kinesis / Firehose / Lambda
#
# AWS caps this at 2 per log group (enforced by a validation on the input).
###############################################################################

resource "aws_cloudwatch_log_subscription_filter" "this" {
 for_each = var.subscription_filters

 name = each.key
 log_group_name = aws_cloudwatch_log_group.this.name
 destination_arn = each.value.destination_arn
 filter_pattern = each.value.filter_pattern
 role_arn = each.value.role_arn
 distribution = each.value.distribution
}

###############################################################################
# Explicit log streams (optional)
###############################################################################

resource "aws_cloudwatch_log_stream" "this" {
 for_each = var.log_streams

 name = each.value
 log_group_name = aws_cloudwatch_log_group.this.name
}

###############################################################################
# Resource-based policy (optional, single)
#
# Guarded via for_each (no count): the "this" key materializes only when the
# caller supplies a resource_policy object.
###############################################################################

resource "aws_cloudwatch_log_resource_policy" "this" {
 for_each = var.resource_policy != null ? { this = var.resource_policy }: {}

 policy_name = each.value.policy_name
 policy_document = each.value.policy_document
}
