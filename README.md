# CodeBuild Webhook Rename Repro

[![Build Status](https://codebuild.ap-southeast-2.amazonaws.com/badges?uuid=eyJlbmNyeXB0ZWREYXRhIjoiLzRBeDArTUNjU3dyTkttSS9SSjhtVUNXWDhYdTJhTmQ3T1RZYXROSE9DOVJNaEh6V2lqYTdEd2ZOdkh6bUdYVUdsQXhBQjBWOVY1KzkxMkQ3K1VUM0RVPSIsIml2UGFyYW1ldGVyU3BlYyI6IkJ4L3BmN3ZhMDF4TEo4TDAiLCJtYXRlcmlhbFNldFNlcmlhbCI6MX0%3D&branch=main)](https://ap-southeast-2.codebuild.aws.amazon.com/project/eyJlbmNyeXB0ZWREYXRhIjoidmZkREJWTCtKZFJzK3B6RUxtTWlYUDFrQjg3RGl5ajJGNXVMU3M5ZzJwaUptTUEwcUM0THovZk9TeDhpV3NyaUtiQk5WYm9tNVhrZmxJZCtIeXFvUGQxRUNiV0VHS2c4T200Z0VKTWJ4RWRsMi9LQTQ1YUNLR2d1ZFgveEpHYXNCVnpoM1E9PSIsIml2UGFyYW1ldGVyU3BlYyI6ImFwckVBQTBMdFhFZ2t6RFAiLCJtYXRlcmlhbFNldFNlcmlhbCI6MX0%3D)

Minimal reproduction of an issue with `aws_codebuild_webhook` where renaming a GitHub repository breaks the webhook without any detectable Terraform drift, and requires manual intervention to restore.

This repo now includes the Terraform workaround recommended by the AWS provider maintainers: the CodeBuild webhook is replaced whenever the CodeBuild project source repository URL changes.

> **Note:**
> This repo is already in the post-rename state. It was originally created as:

* `codebuild-webhook-rename-test`
* renamed to `codebuild-webhook-rename-test-updated`
* renamed again to `codebuild-webhook-rename-test-renamed-again`
* renamed again to `codebuild-webhook-rename-test-renamed-again-and-again`

The steps below describe the full lifecycle from a clean state.

---

## Summary

Renaming a GitHub repository breaks the webhook created by AWS CodeBuild.

* CodeBuild stops triggering builds
* Terraform reports no drift (`plan -refresh-only`)
* Updating the repo URL alone does not fix the issue
* Webhook must be explicitly recreated, or configured to replace when the source URL changes

---

## Lifecycle of the Issue

### 1. Initial state (working)

* CodeBuild project + webhook created via Terraform
* GitHub webhook exists
* Push events trigger builds ✅

---

### 2. Repository rename

* Repository renamed (GitHub redirect works for git operations)
* GitHub removes or invalidates the webhook
* CodeBuild no longer receives events ❌

Observations:

* No errors in AWS
* No errors in Terraform
* Git operations continue working (redirects)
* Integration appears healthy

---

### 3. Terraform refresh

```
terraform plan -refresh-only
```

Result:

* ❌ No changes detected
* Terraform still believes webhook exists

---

### 4. Update repository source (partial fix)

```
source {
  type     = "GITHUB"
  location = var.repo_url
}
```

```
terraform apply
```

Result:

* CodeBuild project updates to new repo
* ❌ Webhook is NOT recreated
* ❌ Builds still do not trigger

---

## Root Cause

The webhook lifecycle is not fully reconciled by Terraform or AWS CodeBuild.

* GitHub deletes or invalidates the webhook on repo rename
* Terraform state still believes the webhook exists
* AWS CodeBuild does not recreate the webhook when the source repo changes
* No drift is detected

This creates a **silent failure mode**.

---

## Workaround Baked Into This Repo

Updating the source location alone is NOT sufficient unless the webhook is also forced to replace.

This repo now does that with `replace_triggered_by`:

```hcl
resource "aws_codebuild_webhook" "example" {
  project_name = aws_codebuild_project.example.name

  lifecycle {
    replace_triggered_by = [
      aws_codebuild_project.example.source[0].location,
    ]
  }
}
```

Result:

* Webhook recreated in GitHub
* Integration restored
* Builds trigger again ✅

### Verified workaround result

After renaming the repository from `codebuild-webhook-rename-test-renamed-again` to `codebuild-webhook-rename-test-renamed-again-and-again`, updating `repo_url`, and running Terraform again, the workaround behaved as intended:

* `aws_codebuild_project.example` updated the source URL in place
* `aws_codebuild_webhook.example` was replaced due to `replace_triggered_by`
* Terraform applied `1 added, 1 changed, 1 destroyed`
* A follow-up `terraform plan -detailed-exitcode` reported no changes
* GitHub showed the recreated webhook on the renamed repository

This confirms the workaround fixes the rename recovery path for this repro: updating the repository URL now also recreates the CodeBuild webhook, instead of leaving the integration silently broken.

---

## Steps to Reproduce

1. Create a GitHub repo (e.g. `codebuild-webhook-rename-test`)
2. Set `repo_url` in `terraform.tfvars` to the original repo URL
3. Apply Terraform to create:

   * CodeBuild project
   * `aws_codebuild_webhook`
4. Push commit → verify build triggers
5. Rename the GitHub repository
6. Push commit → no builds triggered
7. Run `terraform plan -refresh-only` → no drift detected
8. Update `repo_url` in `terraform.tfvars`
9. Run `terraform plan`

```
terraform plan
```

Expected with the workaround:

* CodeBuild project is updated
* `aws_codebuild_webhook.example` is replaced

10. Run `terraform apply`
11. Push commit → builds resume

---

## Expected

* Missing or invalid webhook should be detected as drift
  OR
* Webhook should be recreated when repository source changes. This repo now encodes that behavior with `replace_triggered_by`.

---

## Actual

* No drift detected after webhook is removed/invalidated
* Updating repository source does not recreate webhook unless lifecycle replacement is explicitly configured
* CodeBuild stops triggering builds silently
* Integration appears healthy from AWS/Terraform

---

## Public Build History

https://ap-southeast-2.codebuild.aws.amazon.com/project/eyJlbmNyeXB0ZWREYXRhIjoidmZkREJWTCtKZFJzK3B6RUxtTWlYUDFrQjg3RGl5ajJGNXVMU3M5ZzJwaUptTUEwcUM0THovZk9TeDhpV3NyaUtiQk5WYm9tNVhrZmxJZCtIeXFvUGQxRUNiV0VHS2c4T200Z0VKTWJ4RWRsMi9LQTQ1YUNLR2d1ZFgveEpHYXNCVnpoM1E9PSIsIml2UGFyYW1ldGVyU3BlYyI6ImFwckVBQTBMdFhFZ2t6RFAiLCJtYXRlcmlhbFNldFNlcmlhbCI6MX0%3D

---

## Triggering Builds (for testing)

```
git commit --allow-empty -m "trigger build"
git push
```

Expected behavior:

* Before rename → builds trigger ✅
* After rename → builds do NOT trigger ❌
* After repo URL update + Terraform apply with this workaround → builds trigger again ✅

---

## Related issue

https://github.com/hashicorp/terraform-provider-aws/issues/47546
