# This file contains variable values for the GCP DB, Cloud Run, and Load Balancer configuration.
# It overrides the default values specified in main.tf.
# Use this file to override default variable values defined in main.tf

resource_name = "my-new-service"
db_tier              = "db-g1-small"
db_version           = "MYSQL_8_0"
cloudrun_image       = "us-docker.pkg.dev/cloudrun/container/hello"
cloudrun_location    = "us-central1"
allow_unauthenticated_cloudrun = false