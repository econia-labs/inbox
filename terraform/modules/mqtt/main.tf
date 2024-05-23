resource "terraform_data" "instance" {
  # Store zone since variables not accessible at destroy time.
  input = var.zone
  provisioner "local-exec" {
    command = join(" ", [
      "gcloud compute instances create-with-container mqtt",
      "--container-env",
      join(",", [
        "MQTT_PASSWORD=${var.mosquitto_password}",
        "DATABASE_URL=${var.db_conn_str_private}"
      ]),
      "--container-image econialabs/inbox:mqtt",
      "--network ${var.sql_network_id}",
      "--zone ${var.zone}"
    ])
  }
  provisioner "local-exec" {
    command = join("\n", [
      "result=$(gcloud compute instances list --filter NAME=mqtt)",
      "if [ -n \"$result\" ]; then",
      join(" ", [
        "gcloud compute instances delete mqtt",
        "--quiet",
        "--zone ${self.output}"
      ]),
      "fi"
    ])
    when = destroy
  }
}

data "external" "ip" {
  depends_on = [terraform_data.instance]
  program = [
    "bash",
    "-c",
    join(" ", [
      # Query gcloud CLI for natural IP address field of MQTT instance.
      join(" ", [
        "gcloud compute instances list",
        "--filter name=mqtt",
        "--format 'json(networkInterfaces[0].accessConfigs[0].natIP)'",
      ]),
      # Parse natural IP address field from JSON output.
      "| jq '.[0].networkInterfaces[0].accessConfigs[0]'",
    ]),
  ]
}
