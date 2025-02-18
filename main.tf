locals {
  enabled = "${var.enabled == "true" ? true : false}"
}

module "codepipeline_label" {
  source     = "github.com/cloudposse/terraform-terraform-label.git?ref=0.4.0"
  attributes = "${compact(concat(var.attributes, list("codepipeline")))}"
  delimiter  = "${var.delimiter}"
  name       = "${var.name}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  tags       = "${var.tags}"
}

resource "aws_s3_bucket" "default" {
  count         = "${local.enabled ? 1 : 0}"
  bucket        = "${module.codepipeline_label.id}"
  acl           = "private"
  force_destroy = "${var.s3_bucket_force_destroy}"
  tags          = "${module.codepipeline_label.tags}"

  lifecycle_rule {
    id      = "code"
    enabled = "${var.pipeline_bucket_lifecycle_enabled}"
    prefix  = "${format("%.20s/code/", module.codepipeline_label.id)}"

    abort_incomplete_multipart_upload_days = "7"
    noncurrent_version_expiration {
      days = "${var.pipeline_bucket_lifecycle_expiration_days}"
    }
    expiration {
      days = "${var.pipeline_bucket_lifecycle_expiration_days}"
      expired_object_delete_marker = "false"
    }
  }

  lifecycle_rule {
    id      = "task"
    enabled = "${var.pipeline_bucket_lifecycle_enabled}"
    prefix  = "${format("%.20s/task/", module.codepipeline_label.id)}"

    abort_incomplete_multipart_upload_days = "7"
    noncurrent_version_expiration {
      days = "${var.pipeline_bucket_lifecycle_expiration_days}"
    }
    expiration {
      days = "${var.pipeline_bucket_lifecycle_expiration_days}"
      expired_object_delete_marker = "false"
    }
  }
}

module "codepipeline_assume_label" {
  source     = "github.com/cloudposse/terraform-terraform-label.git?ref=0.4.0"
  attributes = "${compact(concat(var.attributes, list("codepipeline", "assume")))}"
  delimiter  = "${var.delimiter}"
  name       = "${var.name}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  tags       = "${var.tags}"
}

resource "aws_iam_role" "default" {
  count              = "${local.enabled ? 1 : 0}"
  name               = "${module.codepipeline_assume_label.id}"
  assume_role_policy = "${data.aws_iam_policy_document.assume.json}"
}

data "aws_iam_policy_document" "assume" {
  statement {
    sid = ""

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com", "codedeploy.amazonaws.com"]
    }

    effect = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "default" {
  count      = "${local.enabled ? 1 : 0}"
  role       = "${element(concat(aws_iam_role.default.*.id, list("")), 0)}"
  policy_arn = "${element(concat(aws_iam_policy.default.*.arn, list("")), 0)}"
}

resource "aws_iam_policy" "default" {
  count  = "${local.enabled ? 1 : 0}"
  name   = "${module.codepipeline_label.id}"
  policy = "${data.aws_iam_policy_document.default.json}"
}

data "aws_iam_policy_document" "default" {
  statement {
    sid = ""

    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "cloudwatch:*",
      "s3:*",
      "sns:*",
      "cloudformation:*",
      "rds:*",
      "sqs:*",
      "ecs:*",
      "iam:PassRole",
    ]

    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "s3" {
  count      = "${local.enabled ? 1 : 0}"
  role       = "${element(concat(aws_iam_role.default.*.id, list("")), 0)}"
  policy_arn = "${element(concat(aws_iam_policy.s3.*.arn, list("")), 0)}"
}

module "codepipeline_s3_policy_label" {
  source     = "github.com/cloudposse/terraform-terraform-label.git?ref=0.4.0"
  attributes = "${compact(concat(var.attributes, list("codepipeline", "s3")))}"
  delimiter  = "${var.delimiter}"
  name       = "${var.name}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  tags       = "${var.tags}"
}

resource "aws_iam_policy" "s3" {
  count  = "${local.enabled ? 1 : 0}"
  name   = "${module.codepipeline_s3_policy_label.id}"
  policy = "${element(concat(data.aws_iam_policy_document.s3.*.json, list("")), 0)}"
}

data "aws_iam_policy_document" "s3" {
  count = "${local.enabled ? 1 : 0}"

  statement {
    sid = ""

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject",
    ]

    resources = [
      "${element(concat(aws_s3_bucket.default.*.arn, list("")), 0)}",
      "${format("%s/*", element(concat(aws_s3_bucket.default.*.arn, list("")), 0))}"
    ]

    effect = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  count      = "${local.enabled ? 1 : 0}"
  role       = "${element(concat(aws_iam_role.default.*.id, list("")), 0)}"
  policy_arn = "${element(concat(aws_iam_policy.codebuild.*.arn, list("")), 0)}"
}

module "codebuild_label" {
  source     = "github.com/cloudposse/terraform-terraform-label.git?ref=0.4.0"
  attributes = "${compact(concat(var.attributes, list("codebuild")))}"
  delimiter  = "${var.delimiter}"
  name       = "${var.name}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  tags       = "${var.tags}"
}

resource "aws_iam_policy" "codebuild" {
  count  = "${local.enabled ? 1 : 0}"
  name   = "${module.codebuild_label.id}"
  policy = "${data.aws_iam_policy_document.codebuild.json}"
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid = ""

    actions = [
      "codebuild:*",
    ]

    resources = ["${module.build.project_id}"]
    effect    = "Allow"
  }
}

data "aws_caller_identity" "default" {}

data "aws_region" "default" {}

module "build" {
  source                = "git::https://github.com/cloudposse/terraform-aws-codebuild.git?ref=tags/0.17.0"
  enabled               = "${var.enabled}"
  namespace             = "${var.namespace}"
  name                  = "${var.name}"
  stage                 = "${var.stage}"
  build_image           = "${var.build_image}"
  build_compute_type    = "${var.build_compute_type}"
  build_timeout         = "${var.build_timeout}"
  buildspec             = "${var.buildspec}"
  delimiter             = "${var.delimiter}"
  attributes            = "${concat(var.attributes, list("build"))}"
  tags                  = "${var.tags}"
  privileged_mode       = "${var.privileged_mode}"
  aws_region            = "${signum(length(var.aws_region)) == 1 ? var.aws_region : data.aws_region.default.name}"
  aws_account_id        = "${signum(length(var.aws_account_id)) == 1 ? var.aws_account_id : data.aws_caller_identity.default.account_id}"
  image_repo_name       = "${var.image_repo_name}"
  image_tag             = "${var.image_tag}"
  github_token          = "${var.github_oauth_token}"
  environment_variables = "${var.environment_variables}"
  badge_enabled         = "${var.badge_enabled}"
}

resource "aws_iam_role_policy_attachment" "codebuild_s3" {
  count      = "${local.enabled ? 1 : 0}"
  role       = "${module.build.role_id}"
  policy_arn = "${element(concat(aws_iam_policy.s3.*.arn, list("")), 0)}"
}

resource "random_string" "webhook_secret" {
  count  = "${local.enabled && var.webhook_enabled == "true" ? 1 : 0}"
  length = 32

  # Special characters are not allowed in webhook secret (AWS silently ignores webhook callbacks)
  special = false
}

locals {
  webhook_secret = "${join("", random_string.webhook_secret.*.result)}"
  webhook_url    = "${join("", aws_codepipeline_webhook.webhook.*.url)}"
}

resource "aws_codepipeline_webhook" "webhook" {
  count           = "${local.enabled && var.webhook_enabled == "true" ? 1 : 0}"
  name            = "${module.codepipeline_label.id}"
  authentication  = "${var.webhook_authentication}"
  target_action   = "${var.webhook_target_action}"
  target_pipeline = "${join("", aws_codepipeline.source_build_deploy_bg.*.name)}"

  authentication_configuration {
    secret_token = "${local.webhook_secret}"
  }

  filter {
    json_path    = "${var.webhook_filter_json_path}"
    match_equals = "${var.webhook_filter_match_equals}"
  }
}

module "github_webhooks" {
  source               = "git::https://github.com/cloudposse/terraform-github-repository-webhooks.git?ref=tags/0.5.0"
  enabled              = "${local.enabled && var.webhook_enabled == "true" ? "true" : "false"}"
  github_organization  = "${var.repo_owner}"
  github_repositories  = ["${var.repo_name}"]
  github_token         = "${var.github_webhooks_token}"
  webhook_url          = "${local.webhook_url}"
  webhook_secret       = "${local.webhook_secret}"
  webhook_content_type = "json"
  events               = "${var.github_webhook_events}"
}
