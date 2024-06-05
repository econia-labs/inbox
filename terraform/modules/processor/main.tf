# https://github.com/hashicorp/terraform-provider-google/issues/5832
resource "terraform_data" "instance" {
  depends_on = [var.main_database]
  # Store zone since variables not accessible at destroy time.
  input = var.zone
  provisioner "local-exec" {
    command = join(" ", [
      "gcloud compute instances create-with-container processor",
      "--container-env",
      join(",", [
        "DATABASE_URL=${var.db_conn_str_private}",
        "CONTRACT_ADDRESS=${var.contract_address}",
        "GRPC_AUTH_TOKEN=${var.grpc_auth_token}",
        "GRPC_DATA_SERVICE_URL=${var.grpc_data_service_url}",
        "STARTING_VERSION=${var.starting_version}",
      ]),
      "--container-image econialabs/inbox:processor",
      "--network ${var.sql_network_id}",
      "--zone ${var.zone}"
    ])
  }
  provisioner "local-exec" {
    command = join("\n", [
      "result=$(gcloud compute instances list --filter NAME=processor)",
      "if [ -n \"$result\" ]; then",
      join(" ", [
        "gcloud compute instances delete processor",
        "--quiet",
        "--zone ${self.output}"
      ]),
      "fi"
    ])
    when = destroy
  }
}
