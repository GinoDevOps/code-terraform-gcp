resource "google_compute_resource_policy" "hourly" {
  name   = "policy-${local.name_suffix}"
  region = "us-central1"
  description = "chain name snapshot"
  snapshot_schedule_policy {
    schedule {
      hourly_schedule {
        hours_in_cycle = 20
        start_time     = "23:00"
      }
    }
    retention_policy {
      max_retention_days    = 14
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
    snapshot_properties {
      labels = {
        my_label = "value"
      }
      storage_locations = ["us"]
      guest_flush       = true
      chain_name = "test-schedule-chain-name"
    }
  }
}
