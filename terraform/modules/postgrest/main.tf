resource "google_cloud_run_v2_service" "postgrest" {
  depends_on = [var.migrations_complete]
  location   = var.region
  name       = "postgrest"
  template {
    containers {
      image = "postgrest/postgrest:v11.2.1"
      env {
        name  = "PGRST_DB_ANON_ROLE"
        value = "web_anon"
      }
      env {
        name  = "PGRST_DB_MAX_ROWS"
        value = var.postgrest_max_rows
      }
      env {
        name  = "PGRST_DB_URI"
        value = var.db_conn_str_private
      }
      ports {
        container_port = 3000
      }
    }
    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }
    vpc_access {
      connector = var.sql_vpc_connector_id
      egress    = "ALL_TRAFFIC"
    }
  }
  custom_audiences = ["vercel"]
}

resource "google_cloud_run_service_iam_policy" "auth_postgrest" {
  location    = google_cloud_run_v2_service.postgrest.location
  project     = google_cloud_run_v2_service.postgrest.project
  service     = google_cloud_run_v2_service.postgrest.name
  policy_data = data.google_iam_policy.auth_postgrest.policy_data
}

resource "google_service_account" "vercel" {
  account_id   = "vercel"
  display_name = "Vercel"
}

data "google_iam_policy" "auth_postgrest" {
  binding {
    role = "roles/run.invoker"
    members = [
      join("", ["serviceAccount:vercel@", var.project_id, ".iam.gserviceaccount.com"]),
    ]
  }
}
