#!/bin/bash
set -euxo pipefail

# Install AWS CLI
sudo apt-get update -y
sudo apt-get install -y unzip curl gnupg
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install Docker
# Add Docker's official GPG key:
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
# timeout 60 
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo usermod -aG docker ubuntu
sudo chmod 777 /var/run/docker.sock
# sudo newgrp docker
docker --version

# NOTE: SonarQube requires >=2GB RAM and may fail on t3.micro.
# Skipping SonarQube container on small instances to keep the instance healthy.
# If you want SonarQube, run it on a larger instance or external service.
# docker run -d --name sonar -p 9000:9000 sonarqube:lts-community

# Install Trivy
sudo apt-get install -y wget apt-transport-https gnupg
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update -y
sudo apt-get install trivy -y

# Install Java 17
# REF: https://www.rosehosting.com/blog/how-to-install-java-17-lts-on-ubuntu-20-04/
sudo apt update -y
sudo apt install openjdk-17-jdk openjdk-17-jre -y
java -version

# Install Jenkins
# REF: https://www.jenkins.io/doc/book/installing/linux/#debianubuntu

sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt update -y                                   # to update package
sudo apt install jenkins -y                          # to install jenkins

sudo systemctl start jenkins                         # to start jenkins service
# sudo systemctl status jenkins                        # to check the status if jenkins is running or not

# Install/enable Amazon SSM Agent so we can manage the instance without SSH
# Try snap first (works for modern Ubuntu), fall back to downloading the deb package
if command -v snap >/dev/null 2>&1; then
  sudo snap install amazon-ssm-agent --classic || true
  # enable and start the service if snap created it
  if systemctl list-units --full -all | grep -q snap.amazon-ssm-agent.amazon-ssm-agent.service; then
    sudo systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || true
  fi
fi

# Fallback: try apt (if available in repositories) or download the package from S3
if ! command -v amazon-ssm-agent >/dev/null 2>&1; then
  sudo apt-get update -y || true
  sudo apt-get install -y amazon-ssm-agent || true
fi

if ! command -v amazon-ssm-agent >/dev/null 2>&1; then
  REGION="us-east-1"
  DEB_URL="https://s3.${REGION}.amazonaws.com/amazon-ssm-${REGION}/latest/debian_amd64/amazon-ssm-agent.deb"
  curl -sS "$DEB_URL" -o /tmp/amazon-ssm-agent.deb || true
  if [ -f /tmp/amazon-ssm-agent.deb ]; then
    sudo dpkg -i /tmp/amazon-ssm-agent.deb || true
    sudo systemctl enable --now amazon-ssm-agent || true
  fi
fi

# Ensure the agent is running (best-effort)
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl daemon-reload || true
  sudo systemctl enable --now amazon-ssm-agent || true
  sudo systemctl restart amazon-ssm-agent || true
fi

# Wait a little for SSM agent to register
sleep 10
# Get Jenkins_Public_IP
ip=$(curl -s ifconfig.me || curl -s ifconfig.co || hostname -I | awk '{print $1}')
port1=8080
port2=9000

# Wait for Jenkins initialAdminPassword file to appear (cloud-init may reach here before Jenkins is ready)
for i in {1..30}; do
  if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    pass=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)
    break
  fi
  echo "Waiting for Jenkins initial password... ($i)"
  sleep 10
done

echo "Access Jenkins Server here --> http://$ip:$port1"
if [ -n "${pass-}" ]; then
  echo "Jenkins Initial Password: $pass"
else
  echo "Jenkins Initial Password: (not available yet)" >&2
fi
echo
echo "SonarQube is skipped on this instance (requires more RAM). If you want it, run SonarQube on a larger instance or externally."

# Create a swapfile (4G) to help SonarQube on small instances
if [ ! -f /swapfile ]; then
  sudo fallocate -l 4G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# Start SonarQube container with conservative JVM options (adjust as needed)
sudo docker pull sonarqube:lts-community || true
sudo docker run -d --name sonar --restart unless-stopped -p 9000:9000 \
  -e SONAR_ES_JAVA_OPTS="-Xms512m -Xmx1024m -XX:+UseG1GC -XX:+UseStringDeduplication" \
  sonarqube:lts-community || true
