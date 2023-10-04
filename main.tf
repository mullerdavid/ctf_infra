provider "google" {
  project = "ctf-infra-400618"
  region  = "europe-west1"
  zone    = "europe-west1-b"
}

variable "machine-type" {
  type = string
  default = "e2-highmem-8"
}

variable "externaldisk" {
  type = bool
  default = false
}

variable "gcp_service_list" {
  type = list(string)
  default = [
    "compute.googleapis.com"
  ]
}

resource "google_project_service" "gcp_services" {
  for_each = toset(var.gcp_service_list)
  service = each.key
}

resource "google_compute_network" "vpc-vulnbox" {
  name                      = "vpc-vulnbox"
  auto_create_subnetworks   = false
  enable_ula_internal_ipv6  = true
  depends_on = [google_project_service.gcp_services]
}

resource "google_compute_subnetwork" "vpc-vulnbox-ipv6" {
  name          = "vpc-vulnbox-ipv6"

  ip_cidr_range = "10.100.0.0/24"

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "INTERNAL"

  network       = google_compute_network.vpc-vulnbox.id
}

resource "google_compute_disk" "disk-routerbox-data" {
  count = var.externaldisk ? 1 : 0
  name  = "disk-routerbox-data"
  type  = "pd-standard"
  physical_block_size_bytes = 4096
  size = 2048
  depends_on = [google_project_service.gcp_services]
}

resource "google_compute_address" "static-ipv4-routerbox" {
  name         = "static-ipv4-routerbox"
  subnetwork   = google_compute_subnetwork.vpc-vulnbox-ipv6.name
  address_type = "INTERNAL"
  ip_version   = "IPV4"
}

/*
resource "google_compute_address" "static-ipv6-routerbox" {
  name         = "static-ipv6-routerbox"
  subnetwork   = google_compute_subnetwork.vpc-vulnbox-ipv6.name
  address_type = "INTERNAL"
  ip_version   = "IPV6"
}
*/

resource "tls_private_key" "provision_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "google_compute_instance" "vm-routerbox" {
  name = "vm-routerbox"
  machine_type = var.machine-type

  boot_disk {
    #auto_delete = var.externaldisk
    initialize_params {
      image = "ubuntu-2204-lts"
      size = var.externaldisk ? 20 : 200
      type = "pd-ssd"
    }
  }

  dynamic "attached_disk" {
    for_each = var.externaldisk ? [1] : []
    content {
      source = google_compute_disk.disk-routerbox-data[0].name
      mode = "READ_WRITE"
    }
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral public IP
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.vpc-vulnbox-ipv6.name
    network_ip = google_compute_address.static-ipv4-routerbox.address
    stack_type = "IPV4_IPV6"
  }

  can_ip_forward = true

  metadata = {
    ssh-keys = join("\n",[
      #"root:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCwCgYPjzHAfrWz8uRBjQ9kI0XaPUxyehRyU8WHOdv8utPWKlacAf6KbT5mWQXTMEqGeEoT0qxrQ1T0mYns6A8OmRrMD0Y1YkB31tKgNKVhGnzUiYGz7s2rBheQQ7S3crNmKADh6w1kSmvJSmNfNmOk5xETTKJHDzmlCZ89l15xNZ0+nXmyHBrJVrhFSKbljWTadjdQUu77mzCZXcH2uTnPpIlPk9ZzOjfGHZpycQ35sgGZi7X1O+QGd18b75ozPB5KhCyQcw1vLcxE+OliJQ4+qFxCBkllltLwiLCWPxpa3G64JxS93iy9FwKl/NvqAxoc4omZB8u7kE65PVQIIdmn root@routerbox",
      "root:${file("~/.ssh/id_rsa.pub")}",
      "root:${tls_private_key.provision_ssh_key.public_key_openssh}",
    ])
  }

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "root"
      host = self.network_interface[0].access_config[0].nat_ip
      private_key = tls_private_key.provision_ssh_key.private_key_openssh
    }

    script = "provision_routerbox.sh"
  }

  depends_on = [google_project_service.gcp_services]
}

resource "google_compute_route" "vpc-vulnbox-ipv4-route" {
  name        = "vpc-vulnbox-ipv4-route"
  dest_range  = "0.0.0.0/0"
  network     = google_compute_network.vpc-vulnbox.name
  next_hop_instance = google_compute_instance.vm-routerbox.name
  next_hop_instance_zone = google_compute_instance.vm-routerbox.zone
  priority    = 99
}

resource "google_compute_route" "vpc-vulnbox-ipv6-route" {
  name        = "vpc-vulnbox-ipv6-route"
  dest_range  = "::/0"
  network     = google_compute_network.vpc-vulnbox.name
  next_hop_instance = google_compute_instance.vm-routerbox.name
  next_hop_instance_zone = google_compute_instance.vm-routerbox.zone
  priority    = 99
}

resource "google_compute_firewall" "vpc-vulnbox-ipv4-allow-all" {
  name    = "vpc-vulnbox-ipv4-allow-all"
  network = google_compute_network.vpc-vulnbox.name

  allow {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
} 

resource "google_compute_firewall" "vpc-vulnbox-ipv6-allow-all" {
  name    = "vpc-vulnbox-ipv6-allow-all"
  network = google_compute_network.vpc-vulnbox.name

  allow {
    protocol = "all"
  }

  source_ranges = ["::/0"]
  depends_on = [google_project_service.gcp_services]
} 

resource "google_compute_firewall" "default-allow-services" {
  name    = "default-allow-services"
  network = "default"

  allow {
    protocol = "tcp"
    ports = [22, 8005, 8006, 8007]
  }

  source_ranges = ["0.0.0.0/0"]
  depends_on = [google_project_service.gcp_services]
} 

locals {
  external-ip-routerbox = google_compute_instance.vm-routerbox.network_interface[0].access_config[0].nat_ip
}

resource "local_file" "provision_ssh_key_priv" {
  content  = tls_private_key.provision_ssh_key.private_key_openssh
  filename = "provision_ssh_key"
}

resource "local_file" "provision_ssh_key_pub" {
  content  = tls_private_key.provision_ssh_key.public_key_openssh
  filename = "provision_ssh_key.pub"
}

output "routerbox" {
  value = local.external-ip-routerbox
}