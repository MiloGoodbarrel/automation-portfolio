variable "bucket_name" {
  description = "Name of the S3 bucket."
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default     = {}
}

variable "versioning_enabled" {
  description = "Enable versioning on the bucket."
  type        = bool
  default     = true
}

variable "block_public_acls" {
  description = "Block public ACLs."
  type        = bool
  default     = true
}

variable "block_public_policy" {
  description = "Block public bucket policies."
  type        = bool
  default     = true
}

variable "ignore_public_acls" {
  description = "Ignore public ACLs."
  type        = bool
  default     = true
}

variable "restrict_public_buckets" {
  description = "Restrict public buckets."
  type        = bool
  default     = true
}

variable "sse_algorithm" {
  description = "Server-side encryption algorithm."
  type        = string
  default     = "AES256"
}

variable "abort_multipart_days" {
  description = "Days before aborting incomplete multipart uploads."
  type        = number
  default     = 7
}
