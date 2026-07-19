###############################################################################
# Identity
###############################################################################

variable "name" {
 description = <<EOT
Name of the CloudWatch log group. FORCE-NEW — changing this destroys and
recreates the group and discards all retained log data, so treat it as immutable.
Mutually exclusive with name_prefix. Leave null to let either name_prefix or the
provider generate a unique name. Log group names are unique within an
account/Region. Convention: hierarchical, slash-delimited (e.g.
"/aws/lambda/<fn>", "/casey/<app>/<component>").
EOT
 type = string
 default = null

 validation {
 condition = !(var.name != null && var.name_prefix != null)
 error_message = "Set at most one of name or name_prefix; they are mutually exclusive."
 }
}

variable "name_prefix" {
 description = <<EOT
Creates a unique log group name beginning with this prefix. FORCE-NEW. Conflicts
with name. Prefer name_prefix for generated/ephemeral groups so plans never
collide on a hard-coded name.
EOT
 type = string
 default = null
}

###############################################################################
# Core configuration (secure-by-default)
###############################################################################

variable "retention_in_days" {
 description = <<EOT
Number of days to retain log events. Secure default is 365 (one year) — never
unbounded. Must be one of the discrete values CloudWatch Logs allows: 1, 3, 5, 7,
14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922,
3288, 3653, or 0 (retain forever — discouraged for PII/privacy-regulation workloads; choose a
bounded value unless a records-retention requirement dictates otherwise).
Ignored (forcibly 2) when log_group_class is DELIVERY.
EOT
 type = number
 default = 365

 validation {
 condition = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_in_days)
 error_message = "retention_in_days must be one of: 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
 }
}

variable "kms_key_arn" {
 description = <<EOT
ARN of a customer-managed KMS key (CMK) used to encrypt log data at rest. Null
(default) leaves the group encrypted with the AWS-owned CloudWatch Logs key — log
data is always encrypted at rest; supplying a CMK upgrades to full key control.
Wire from tf_mod_aws_kms (arn). The CMK's key policy MUST allow the CloudWatch
Logs service principal (logs.<region>.amazonaws.com) to Encrypt/Decrypt/
GenerateDataKey/Describe, ideally scoped with an
kms:EncryptionContext:aws:logs:arn condition to this group's ARN. After a CMK is
disassociated, newly ingested data stops being encrypted with it (previously
ingested data stays encrypted and still requires the CMK to read).
EOT
 type = string
 default = null

 validation {
 condition = var.kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:", coalesce(var.kms_key_arn, "x")))
 error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:...) or null."
 }
}

variable "log_group_class" {
 description = <<EOT
Log class of the group. STANDARD (default) supports all CloudWatch Logs features
incl. subscription/metric filters and real-time analytics. INFREQUENT_ACCESS is
cheaper for rarely-queried logs but supports a reduced feature set (no
subscription/metric filters, no Live Tail). DELIVERY is reserved for AWS vended
log delivery and forces retention to 2 days. FORCE-NEW.
EOT
 type = string
 default = "STANDARD"

 validation {
 condition = contains(["STANDARD", "INFREQUENT_ACCESS", "DELIVERY"], var.log_group_class)
 error_message = "log_group_class must be one of: STANDARD, INFREQUENT_ACCESS, DELIVERY."
 }
}

variable "skip_destroy" {
 description = <<EOT
When true, Terraform removes the log group from state on destroy WITHOUT deleting
the group or its logs in AWS (orphaning it). Defaults to false (a destroy truly
deletes the group). Use only when log retention must outlive the Terraform
lifecycle.
EOT
 type = bool
 default = false
}

###############################################################################
# Metric filters (child collection — for_each over map(object))
###############################################################################

variable "metric_filters" {
 description = <<EOT
Map of CloudWatch Logs metric filters to create on this group, keyed by metric
filter name. Each value:

 - filter_pattern: CloudWatch Logs filter pattern extracting metric data
 from ingested events ("" matches all).
 - metric_transformation: how matched events emit a metric:
 - name: CloudWatch metric name (e.g. "ErrorCount").
 - namespace: destination metric namespace (e.g. "App").
 - value: value published per match ("1" to count, or a token like
 "$size" to publish a field value).
 - default_value: value emitted when the pattern does not match. Conflicts
 with dimensions; leave null to omit.
 - unit: CloudWatch unit for the metric (default "None").
 - dimensions: up to 3 metric dimensions (field tokens). Conflicts with
 default_value.

Metric filters are not taggable. Not supported on INFREQUENT_ACCESS groups.

 metric_filters = {
 errors = {
 filter_pattern = "ERROR"
 metric_transformation = {
 name = "ErrorCount"
 namespace = "App"
 value = "1"
 }
 }
 }
EOT
 type = map(object({
 filter_pattern = string
 metric_transformation = object({
 name = string
 namespace = string
 value = string
 default_value = optional(string)
 unit = optional(string, "None")
 dimensions = optional(map(string))
 })
 }))
 default = {}

 validation {
 condition = alltrue([
 for k, v in var.metric_filters:
 contains([
 "Seconds", "Microseconds", "Milliseconds", "Bytes", "Kilobytes", "Megabytes",
 "Gigabytes", "Terabytes", "Bits", "Kilobits", "Megabits", "Gigabits", "Terabits",
 "Percent", "Count", "Bytes/Second", "Kilobytes/Second", "Megabytes/Second",
 "Gigabytes/Second", "Terabytes/Second", "Bits/Second", "Kilobits/Second",
 "Megabits/Second", "Gigabits/Second", "Terabits/Second", "Count/Second", "None"
 ], v.metric_transformation.unit)
 ])
 error_message = "Each metric_transformation.unit must be a valid CloudWatch metric unit (e.g. Count, Bytes, Seconds, Percent, None)."
 }

 validation {
 condition = alltrue([
 for k, v in var.metric_filters:
 v.metric_transformation.dimensions == null || length(coalesce(v.metric_transformation.dimensions, {})) <= 3
 ])
 error_message = "metric_transformation.dimensions allows at most 3 entries per metric filter."
 }
}

###############################################################################
# Subscription filters (child collection — for_each over map(object))
###############################################################################

variable "subscription_filters" {
 description = <<EOT
Map of CloudWatch Logs subscription filters to create on this group, keyed by
subscription filter name. AWS allows a MAXIMUM OF 2 subscription filters per log
group (a third fails at apply with LimitExceededException). Each value:

 - destination_arn: ARN of the delivery destination (Kinesis stream, Firehose
 delivery stream, or Lambda function). Required.
 - filter_pattern: CloudWatch Logs filter pattern ("" matches all). Required.
 - role_arn: IAM role ARN granting CloudWatch Logs permission to deliver
 to the destination. Required for Kinesis/Firehose; omit for
 a logical cross-account destination, and for Lambda use a
 lambda:AddPermission grant instead. Wire from
 tf_mod_aws_iam_role (arn).
 - distribution: "ByLogStream" (default) or "Random". Only applies to a
 Kinesis stream destination.

Subscription filters are not taggable. Not supported on INFREQUENT_ACCESS groups.

 subscription_filters = {
 to-firehose = {
 destination_arn = module.firehose.arn
 filter_pattern = ""
 role_arn = module.logs_delivery_role.arn
 }
 }
EOT
 type = map(object({
 destination_arn = string
 filter_pattern = string
 role_arn = optional(string)
 distribution = optional(string, "ByLogStream")
 }))
 default = {}

 validation {
 condition = length(var.subscription_filters) <= 2
 error_message = "CloudWatch Logs allows at most 2 subscription filters per log group."
 }

 validation {
 condition = alltrue([
 for k, v in var.subscription_filters: contains(["ByLogStream", "Random"], v.distribution)
 ])
 error_message = "Each subscription_filters distribution must be either \"ByLogStream\" or \"Random\"."
 }
}

###############################################################################
# Explicit log streams (child collection — for_each over set)
###############################################################################

variable "log_streams" {
 description = <<EOT
Set of explicit log stream names to pre-create within the group, each rendered as
one aws_cloudwatch_log_stream. Usually unnecessary — most producers create their
own streams on first write — but useful when a downstream consumer expects a
named stream to exist. Log streams are not taggable.
EOT
 type = set(string)
 default = []
}

###############################################################################
# Resource-based policy (optional, single)
###############################################################################

variable "resource_policy" {
 description = <<EOT
Optional CloudWatch Logs resource-based policy, rendered as one
aws_cloudwatch_log_resource_policy. Grants AWS service principals (e.g.
delivery.logs.amazonaws.com, es.amazonaws.com, Route 53 query logging) permission
to write to log groups in this account/Region. Leave null (default) when no such
delivery is needed.

NOTE: a resource policy is account/Region-scoped, not bound to this specific log
group; scope its policy_document's Resource to the intended group ARN(s).

 - policy_name: unique name for the resource policy in this account/Region.
 - policy_document: JSON-encoded resource policy (jsonencode() or
 aws_iam_policy_document).
EOT
 type = object({
 policy_name = string
 policy_document = string
 })
 default = null

 validation {
 condition = var.resource_policy == null || can(jsondecode(var.resource_policy.policy_document))
 error_message = "resource_policy.policy_document must be a valid JSON-encoded policy document."
 }
}

###############################################################################
# Universal tail
###############################################################################

variable "tags" {
 description = <<EOT
A map of tags to assign to the log group (the only taggable resource in this
module — metric filters, subscription filters, log streams, and resource policies
are not taggable). These merge with provider-level default_tags; resource tags
win on key conflict. The computed tags_all output reflects the merged set.
EOT
 type = map(string)
 default = {}
}
