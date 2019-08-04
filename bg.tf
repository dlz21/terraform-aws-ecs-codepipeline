resource "aws_iam_role_policy_attachment" "ecs_limited" {
  role       = "${aws_iam_role.default.id}"
  policy_arn = "${aws_iam_policy.ecs_limited.arn}"
}

module "codepipeline_ecs_limited_policy_label" {
  source     = "github.com/cloudposse/terraform-terraform-label.git?ref=0.2.1"
  attributes = ["${compact(concat(var.attributes, list("codepipeline", "ecs", "limited")))}"]
  delimiter  = "${var.delimiter}"
  name       = "${var.name}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  tags       = "${var.tags}"
}

resource "aws_iam_policy" "ecs_limited" {
  name   = "${module.codepipeline_ecs_limited_policy_label.id}"
  policy = "${data.aws_iam_policy_document.ecs_limited.json}"
}

data "aws_iam_policy_document" "ecs_limited" {
  statement {
    sid = ""

    actions = [
      "ecs:DescribeServices",
      "ecs:CreateTaskSet",
      "ecs:UpdateServicePrimaryTaskSet",
      "ecs:DeleteTaskSet",
      "cloudwatch:DescribeAlarms"
    ]

    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    actions   = ["sns:publish"]
    resources = ["${var.code_deploy_sns_topic_arn == "" ? "" : var.code_deploy_sns_topic_arn}", "arn:aws:sns:*:*:CodeDeployTopic_*"]
    effect    = "Allow"
  }

  statement {
    actions = [
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:ModifyRule"
    ]

    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    actions = [
      "lambda:InvokeFunction"
    ]

    resources = ["${var.code_deploy_lambda_hook_arns == "" ? "" : var.code_deploy_lambda_hook_arns}"]
    effect    = "Allow"
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectMetadata",
      "s3:GetObjectVersion"
    ]

    resources  = ["*"]

    condition {
      test     = "StringEquals"
      variable = "s3:ExistingObjectTag/UseWithCodeDeploy"
      values   = ["true"]
    }

    effect     = "Allow"
  }

  statement {
    actions = ["iam:PassRole"]

    resources = [
      "*"
    ]
  }
}

module "codepipeline_codedeploy_policy_label" {
  source     = "github.com/cloudposse/terraform-terraform-label.git?ref=0.2.1"
  attributes = ["${compact(concat(var.attributes, list("codepipeline", "codedeploy")))}"]
  delimiter  = "${var.delimiter}"
  name       = "${var.name}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  tags       = "${var.tags}"
}

resource "aws_iam_role_policy_attachment" "deploy" {
  role       = "${element(concat(aws_iam_role.default.*.id, list("")), 0)}"
  policy_arn = "${aws_iam_policy.deploy.arn}"
}

resource "aws_iam_policy" "deploy" {
  name   = "${module.codepipeline_codedeploy_policy_label.id}"
  policy = "${data.aws_iam_policy_document.deploy.json}"
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid = ""

    actions = [
      "codedeploy:CreateDeployment",
      "codedeploy:GetApplicationRevision",
      "codedeploy:RegisterApplicationRevision",
      "codedeploy:GetDeploymentConfig",
      "codedeploy:GetDeployment",
      "codedeploy:StopDeployment",
      "codedeploy:ContinueDeployment",
      "codedeploy:GetApplication"
    ]

    resources = ["*"]
    effect    = "Allow"
  }
}


resource "aws_codepipeline" "source_build_deploy_bg" {
  count    = "${local.enabled ? 1 : 0}"
  name     = "${module.codepipeline_label.id}"
  role_arn = "${aws_iam_role.default.arn}"

  artifact_store {
    location = "${aws_s3_bucket.default.bucket}"
    type     = "S3"
  }

  depends_on = [
    "aws_iam_role_policy_attachment.default",
    "aws_iam_role_policy_attachment.s3",
    "aws_iam_role_policy_attachment.codebuild",
    "aws_iam_role_policy_attachment.codebuild_s3",
    "aws_iam_role_policy_attachment.deploy",
    "aws_iam_role_policy_attachment.ecs_limited",
  ]

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["code"]

      configuration {
        OAuthToken           = "${var.github_oauth_token}"
        Owner                = "${var.repo_owner}"
        Repo                 = "${var.repo_name}"
        Branch               = "${var.branch}"
        PollForSourceChanges = "${var.poll_source_changes}"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name     = "Build"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts  = ["code"]
      output_artifacts = ["task"]

      configuration {
        ProjectName = "${module.build.project_name}"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      input_artifacts = ["task"]
      version         = "1"

      configuration {
        ApplicationName                = "${var.code_deploy_application_name}"
        DeploymentGroupName            = "${var.code_deploy_deployment_group_name}"
        TaskDefinitionTemplateArtifact = "task"
        TaskDefinitionTemplatePath     = "taskDef.json"
        AppSpecTemplateArtifact        = "task"
        AppSpecTemplatePath            = "appspec.yaml"
      }
    }
  }
}
