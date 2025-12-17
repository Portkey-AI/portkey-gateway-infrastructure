terraform {
  backend "s3" { # Declares you're using S3 backend
    # Enable state locking
    use_lockfile = true
  }
}