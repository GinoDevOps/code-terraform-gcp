# Internal TCP/UDP load balancer with a managed instance group backend

# VPC
resource "google_compute_network" "ilb_network" {
  name                    = "l4-ilb-network-${local.name_suffix}"
  provider                = google-beta
  auto_create_subnetworks = false
}

# backed subnet
resource "google_compute_subnetwork" "ilb_subnet" {
  name          = "l4-ilb-subnet-${local.name_suffix}"
  provider      = google-beta
  ip_cidr_range = "10.0.1.0/24"
  region        = "europe-west1"
  network       = google_compute_network.ilb_network.id
}

# forwarding rule
resource "google_compute_forwarding_rule" "google_compute_forwarding_rule" {
  name                  = "l4-ilb-forwarding-rule-${local.name_suffix}"
  backend_service       = google_compute_region_backend_service.default.id
  provider              = google-beta
  region                = "europe-west1"
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  allow_global_access   = true
  network               = google_compute_network.ilb_network.id
  subnetwork            = google_compute_subnetwork.ilb_subnet.id
}

# backend service
resource "google_compute_region_backend_service" "default" {
  name                  = "l4-ilb-backend-subnet-${local.name_suffix}"
  provider              = google-beta
  region                = "europe-west1"
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_region_health_check.default.id]
  backend {
    group           = google_compute_region_instance_group_manager.mig.instance_group
    balancing_mode  = "CONNECTION"
  }
}

# instance template
resource "google_compute_instance_template" "instance_template" {
  name         = "l4-ilb-mig-template-${local.name_suffix}"
  provider     = google-beta
  machine_type = "e2-small"
  tags         = ["allow-ssh","allow-health-check"]

  network_interface {
    network    = google_compute_network.ilb_network.id
    subnetwork = google_compute_subnetwork.ilb_subnet.id
    access_config {
      # add external ip to fetch packages
    }
  }
  disk {
    source_image = "debian-cloud/debian-10"
    auto_delete  = true
    boot         = true
  }

  # install nginx and serve a simple web page
  metadata = {
    startup-script = <<-EOF1
      #! /bin/bash
      set -euo pipefail

      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y nginx-light jq

      NAME=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/hostname")
      IP=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip")
      METADATA=$(curl -f -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/?recursive=True" | jq 'del(.["startup-script"])')

      cat <<EOF > /var/www/html/index.html
      <pre>
      Name: $NAME
      IP: $IP
      Metadata: $METADATA
      </pre>
      EOF
    EOF1
  }
  lifecycle {
    create_before_destroy = true
  }
}

# health check
resource "google_compute_region_health_check" "default" {
  name     = "l4-ilb-hc-${local.name_suffix}"
  provider = google-beta
  region   = "europe-west1"
  http_health_check {
    port = "80"
  }
}

# MIG
resource "google_compute_region_instance_group_manager" "mig" {
  name     = "l4-ilb-mig1-${local.name_suffix}"
  provider = google-beta
  region   = "europe-west1"
  version {
    instance_template = google_compute_instance_template.instance_template.id
    name              = "primary"
  }
  base_instance_name = "vm"
  target_size        = 2
}

# allow all access from health check ranges
resource "google_compute_firewall" "fw_hc" {
  name          = "l4-ilb-fw-allow-hc-${local.name_suffix}"
  provider      = google-beta
  direction     = "INGRESS"
  network       = google_compute_network.ilb_network.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "35.235.240.0/20"]
  allow {
    protocol = "tcp"
  }
  source_tags = ["allow-health-check"]
}

# allow communication within the subnet 
resource "google_compute_firewall" "fw_ilb_to_backends" {
  name          = "l4-ilb-fw-allow-ilb-to-backends-${local.name_suffix}"
  provider      = google-beta
  direction     = "INGRESS"
  network       = google_compute_network.ilb_network.id
  source_ranges = ["10.0.1.0/24"]
  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
}

# allow SSH
resource "google_compute_firewall" "fw_ilb_ssh" {
  name          = "l4-ilb-fw-ssh-${local.name_suffix}"
  provider      = google-beta
  direction     = "INGRESS"
  network       = google_compute_network.ilb_network.id
  allow {
    protocol = "tcp"
    ports = ["22"]
  }
  source_tags = ["allow-ssh"]
}

# test instance
resource "google_compute_instance" "vm_test" {
  name         = "l4-ilb-test-vm-${local.name_suffix}"
  provider     = google-beta
  zone         = "europe-west1-b"
  machine_type = "e2-small"
  network_interface {
    network    = google_compute_network.ilb_network.id
    subnetwork = google_compute_subnetwork.ilb_subnet.id
  }
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }
}
