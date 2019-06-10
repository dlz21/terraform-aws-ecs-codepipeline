resource "aws_codepipeline" "source_build_deploy_bg" {
  count    = "${local.enabled && local.blue_green_enabled ? 1 : 0}"
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
