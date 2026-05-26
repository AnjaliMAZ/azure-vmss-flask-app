# azure-vmss-flask-app
Production-style cloud application using Azure VM Scale Set, Load Balancer, Flask, and SQL with full debugging and deployment automation.

## Project Overview
This project demonstrates an end-to-end cloud application deployed using Terraform on Microsoft Azure.

## Architecture
User → Load Balancer → VM Scale Set → Nginx → Flask → Azure SQL Database

## Features
- Infrastructure as Code using Terraform
- Azure Virtual Machine Scale Set for scalability
- Load Balancer for traffic distribution
- Flask backend API
- Azure SQL Database integration
- Data persistence
- End-to-end automation

## Debugging & Learning
This project includes real-world troubleshooting of:
- 504 Gateway Timeout (backend not responding)
- 502 Bad Gateway (backend crash)
- 500 Internal Server Error (application issues)
- SQL firewall and connectivity issues
- Missing dependencies and drivers

## Technologies Used
- Terraform
- Azure (VMSS, Load Balancer, SQL)
- Python (Flask)
- Nginx
- pyodbc (DB connectivity)

## How to Run
```bash
terraform init
terraform apply
