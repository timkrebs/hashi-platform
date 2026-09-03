output "application_name" {
  description = "Name of the root Application."
  value       = var.name
}

output "release_name" {
  description = "Name of the Helm release that renders the root Application."
  value       = helm_release.this.name
}

output "source" {
  description = "Repository, revision and path the root Application tracks."
  value = {
    repo_url        = var.repo_url
    target_revision = var.target_revision
    path            = var.path
  }
}
