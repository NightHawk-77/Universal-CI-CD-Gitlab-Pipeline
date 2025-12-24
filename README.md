# Universal GitLab CI/CD Pipeline

This project provides a universal GitLab CI/CD pipeline that works with any technology stack using Docker as the deployment mechanism.
It includes automated testing, security scanning, deployment, and monitoring with Prometheus and Grafana.

##  Pipeline Configuration

Key variables in `.gitlab-ci.yml`:

- `APP_NAME`: "my-app"              
- `CONTAINER_PORT`: "80"            
- `HOST_PORT`: "5004"               
- `SECURITY_FAIL_ON`: "CRITICAL,HIGH" 
- `TRIVY_VERSION`: "0.48.3"        

##  Scripts

All pipeline logic is located in the `./scripts/` directory:

### Core CI/CD
- `install-deps.sh` → Installs required dependencies
- `build.sh` → Only to build Java applications
- `test.sh` → Runs automated tests

### Security
- `scan-docker.sh` → Scans Docker images with Trivy

### Deployment & Maintenance
- `deploy.sh` → Deploys the Docker container
- `cleanup.sh` → Cleans up old containers/images

### Monitoring & Networking
- `monitoring.sh` → Sets up Prometheus & Grafana
- `nginx-certbot.sh` → Configures Nginx + Certbot for SSL

##  Requirements

To run this pipeline, ensure the following:

- GitLab Runner with both Docker and Shell executors
- Docker installed on the target VM
- Network access to your container registry

## Important Notes

- SSL Setup → Requires manual execution of `nginx-certbot.sh`
- Database Connections → Must be configured manually
- Deployment Scope → Designed for single-machine/VM deployments only

##  Monitoring Setup

This project includes Prometheus + Grafana integration.
Metrics are collected from:

- Prometheus itself
- Grafana
- Node Exporter
- cAdvisor (for container monitoring)

## Summary

- Build → Test → Scan → Deploy → Monitor
- Technology-agnostic and reusable pipeline
- Includes security and monitoring best practices
- Flexible but requires some manual setup (SSL, DB)
