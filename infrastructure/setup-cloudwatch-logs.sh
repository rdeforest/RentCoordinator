#!/bin/bash
# Setup CloudWatch Logs for RentCoordinator
# Run this on the EC2 instance

set -e

echo "=== Setting up CloudWatch Logs Agent ==="

# Create log directory
echo "Creating log directory..."
sudo mkdir -p /var/log/rent-coordinator
sudo chown rent-coordinator:rent-coordinator /var/log/rent-coordinator

# Create systemd service to stream logs to file
echo "Creating log streaming service..."
sudo tee /etc/systemd/system/rent-coordinator-logs.service > /dev/null << 'EOF'
[Unit]
Description=RentCoordinator Log Streaming
After=rent-coordinator.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'journalctl -u rent-coordinator -f --no-pager >> /var/log/rent-coordinator/application.log 2>&1'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start log streaming
sudo systemctl daemon-reload
sudo systemctl enable rent-coordinator-logs
sudo systemctl start rent-coordinator-logs

# Install CloudWatch agent
echo "Installing CloudWatch agent..."
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# Update CloudWatch config to point to our log file
echo "Creating CloudWatch agent configuration..."
sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null << 'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/rent-coordinator/application.log",
            "log_group_name": "/rent-coordinator/application",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "RentCoordinator",
    "metrics_collected": {
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "rename": "MemoryUsage",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DiskUsage",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "/"
        ]
      }
    }
  }
}
EOF

# Start the agent
echo "Starting CloudWatch agent..."
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Enable on boot
echo "Enabling CloudWatch agent on boot..."
sudo systemctl enable amazon-cloudwatch-agent

echo "=== CloudWatch Logs setup complete ==="
echo ""
echo "Logs will be available in CloudWatch console:"
echo "  Log Group: /rent-coordinator/application"
echo "  Stream: $(ec2-metadata --instance-id | cut -d' ' -f2 2>/dev/null || echo 'unknown')"
echo ""
echo "View logs with:"
echo "  aws logs tail /rent-coordinator/application --follow"
echo ""
echo "Local log file: /var/log/rent-coordinator/application.log"
