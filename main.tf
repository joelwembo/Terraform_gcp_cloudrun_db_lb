# This Terraform configuration provisions a Google Cloud SQL database, a Cloud Run service, and a Load Balancer.

############################################################
# ── PROVIDERs ─────────────────────────────────────────────
############################################################
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
    random = {
      source = "hashicorp/random"
      version = ">= 3.0.0"
    }
  }
}

provider "google" {
  # Ensure you have authenticated with `gcloud auth application-default login`
  credentials = file("${path.module}/service-account-key.json")
  project     = "project-frontend"
  region      = "us-east1" # This sets the default region for regional resources
}

############################################################
# ── VARIABLES ─────────────────────────────────────────────
############################################################
variable "resource_name" {
  type        = string
  default     = "my-service"
  description = "Prefix for naming resources (e.g., DB, Cloud Run, LB)."
}

variable "db_tier" {
  type        = string
  default     = "db-f1-micro"
  description = "The tier of the Cloud SQL instance."
}

variable "db_version" {
  type        = string
  default     = "POSTGRES_14"
  description = "The database version to use (e.g., POSTGRES_14, MYSQL_8_0)."
}

variable "cloudrun_image" {
  type        = string
  default     = "gcr.io/cloudrun/hello"
  description = "The container image URL for the Cloud Run service."
}

variable "cloudrun_location" {
  type        = string
  default     = "us-east1"
  description = "The region for the Cloud Run service. This also influences the SQL region."
}

variable "allow_unauthenticated_cloudrun" {
  type        = bool
  default     = true
  description = "Set to true to allow unauthenticated access to the Cloud Run service."
}

############################################################
# ── SERVICE ACCOUNT & KEY ─────────────────────────────────
############################################################
resource "random_uuid" "sa_uuid" {}

resource "google_service_account" "default" {
  account_id   = "${var.resource_name}-sa-${substr(random_uuid.sa_uuid.result, 0, 6)}"
  display_name = "${var.resource_name} Service Account"
}

# IMPORTANT: Storing service account keys directly in source control or
# generating them via Terraform is generally not recommended for production environments
# due to security risks. Consider using Workload Identity or external secret management.
resource "google_service_account_key" "default" {
  service_account_id = google_service_account.default.name
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
  # This output will contain the private key. Make sure to handle it securely.
  # Do not commit this to version control if you are using it to directly authenticate.
  # public_key_data is also available if needed.
}

############################################################
# ── CLOUD SQL INSTANCE ────────────────────────────────────
############################################################
resource "google_sql_database_instance" "main" {
  name             = "${var.resource_name}-db"
  region           = var.cloudrun_location # Use cloudrun_location variable here
  database_version = var.db_version
  settings {
    tier = var.db_tier
    # Optional: Enable IP V4 for public access. For private services, use Private IP.
    ip_configuration {
      ipv4_enabled = true
      # You can add authorized networks here if needed for direct access
      # authorized_networks {
      #   value = "0.0.0.0/0" # WARNING: This allows access from anywhere!
      # }
    }
  }
}

# Optional: Create a specific database within the instance
resource "google_sql_database" "app_db" {
  name     = "${var.resource_name}-app-db"
  instance = google_sql_database_instance.main.name
  
  # Use conditional values based on database type
  charset   = var.db_version == "POSTGRES_14" ? "UTF8" : "utf8"
  collation = var.db_version == "POSTGRES_14" ? "en_US.UTF8" : "utf8_general_ci"
}

############################################################
# ── CLOUD RUN SERVICE ─────────────────────────────────────
############################################################
resource "google_cloud_run_v2_service" "main" {
  name     = "${var.resource_name}-run"
  location = var.cloudrun_location

  template {
    containers {
      image = var.cloudrun_image
    }
    service_account = google_service_account.default.email
    # For Cloud Run v2, min_instance_count in scaling block is used for always-on instances
    # and allows better cold start behavior.
    scaling {
      min_instance_count = 0 # Default to 0, scales up on demand
    }
  }

  # For Cloud Run v2, traffic block specifies traffic routing.
  # It does NOT control unauthenticated access directly.
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

# Grant 'roles/run.invoker' to 'allUsers' if allow_unauthenticated_cloudrun is true
# This is the correct way to allow public access for Cloud Run v2.
resource "google_cloud_run_service_iam_member" "main_invoker_binding" {
  count = var.allow_unauthenticated_cloudrun ? 1 : 0

  location = google_cloud_run_v2_service.main.location
  project  = google_cloud_run_v2_service.main.project
  service  = google_cloud_run_v2_service.main.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

############################################################
# ── LOAD BALANCER (HTTP/S to Cloud Run) ───────────────────
############################################################

# 1. Global static IP address for the Load Balancer frontend
resource "google_compute_global_address" "main" {
  name = "${var.resource_name}-ip"
}

# 2. Serverless Network Endpoint Group (NEG) pointing to Cloud Run
# FIXED: Using correct syntax for Cloud Run NEG
resource "google_compute_region_network_endpoint_group" "cloudrun_neg" {
  name                  = "${var.resource_name}-cloudrun-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.cloudrun_location

  cloud_run {
    service = google_cloud_run_v2_service.main.name
  }
}

# 3. Backend Service that references the Serverless NEG
resource "google_compute_backend_service" "main" {
  name                  = "${var.resource_name}-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED" # For global external load balancers

  # Associate the Cloud Run NEG as a backend
  backend {
    group = google_compute_region_network_endpoint_group.cloudrun_neg.id
    # No balancing mode or capacity settings are typically needed for Serverless NEGs
  }

  # Optional: Add health check if needed, though Cloud Run often handles this internally
  # for the service itself. For the LB, it might be beneficial if you have
  # more complex routing scenarios.
  # health_checks = [
  #   google_compute_health_check.default.id
  # ]
}

# 4. URL Map to route traffic to the backend service
resource "google_compute_url_map" "main" {
  name            = "${var.resource_name}-url-map"
  default_service = google_compute_backend_service.main.id
}

# 5. Target HTTP Proxy
resource "google_compute_target_http_proxy" "main" {
  name    = "${var.resource_name}-proxy"
  url_map = google_compute_url_map.main.id
}

# 6. Global Forwarding Rule to connect IP to the proxy
resource "google_compute_global_forwarding_rule" "main" {
  name                  = "${var.resource_name}-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.main.id
  ip_address            = google_compute_global_address.main.id
}

############################################################
# ── OUTPUTS ──────────────────────────────────────────────
############################################################
output "db_instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.main.name
}

output "db_instance_connection_name" {
  description = "Connection name of the Cloud SQL instance (for connecting applications)."
  value       = google_sql_database_instance.main.connection_name
}

output "cloudrun_service_name" {
  description = "Name of the Cloud Run service."
  value       = google_cloud_run_v2_service.main.name
}

output "cloudrun_service_url" {
  description = "URL of the Cloud Run service."
  value       = google_cloud_run_v2_service.main.uri
}

output "load_balancer_ip_address" {
  description = "The static IP address of the Load Balancer."
  value       = google_compute_global_address.main.address
}

output "load_balancer_url_map" {
  description = "Self-link of the URL map."
  value       = google_compute_url_map.main.self_link
}

output "service_account_email" {
  description = "Email of the created service account."
  value       = google_service_account.default.email
}

output "service_account_key_id" {
  description = "ID of the created service account key."
  value       = google_service_account_key.default.id
  sensitive   = true
}