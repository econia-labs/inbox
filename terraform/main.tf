terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.8.0"
    }
  }
  required_version = ">= 0.12, < 2.0.0"
}

provider "google" {
  credentials = "creds.json"
  project     = var.project_id
  region      = var.region
  zone        = var.zone
}

provider "google-beta" {
  credentials = "creds.json"
  project     = var.project_id
  region      = var.region
  zone        = var.zone
}

module "db" {
  db_root_password = var.db_root_password
  credentials_file = var.credentials_file
  region           = var.region
  source           = "./modules/db"
}

module "migrations" {
  db_conn_str_auth_proxy = module.db.db_conn_str_auth_proxy
  db_connection_name     = module.db.db_connection_name
  main_database          = module.db.main_database
  credentials_file       = var.credentials_file
  source                 = "./modules/migrations"
}

module "processor" {
  db_conn_str_private   = module.db.db_conn_str_private
  contract_address      = var.contract_address
  main_database         = module.db.main_database
  grpc_auth_token       = var.grpc_auth_token
  grpc_data_service_url = var.grpc_data_service_url
  source                = "./modules/processor"
  sql_network_id        = module.db.sql_network_id
  starting_version      = var.starting_version
  zone                  = var.zone
}

module "no_auth_policy" {
  source = "./modules/no_auth_policy"
}

module "postgrest" {
  db_conn_str_private  = module.db.db_conn_str_private
  migrations_complete  = module.migrations.migrations_complete
  no_auth_policy_data  = module.no_auth_policy.policy_data
  postgrest_max_rows   = var.postgrest_max_rows
  project_id           = var.project_id
  region               = var.region
  source               = "./modules/postgrest"
  sql_vpc_connector_id = module.db.sql_vpc_connector_id
}

module "grafana" {
  db_conn_str_private_grafana = module.db.db_conn_str_private_grafana
  db_private_ip_and_port      = module.db.db_private_ip_and_port
  grafana_admin_password      = var.grafana_admin_password
  grafana_public_password     = var.grafana_public_password
  migrations_complete         = module.migrations.migrations_complete
  no_auth_policy_data         = module.no_auth_policy.policy_data
  region                      = var.region
  source                      = "./modules/grafana"
  sql_vpc_connector_id        = module.db.sql_vpc_connector_id
}
