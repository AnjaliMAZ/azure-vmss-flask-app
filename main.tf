terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

provider "azurerm" {
  features {}
}

# RESOURCE GROUP
resource "azurerm_resource_group" "rg" {
  name     = "MYWEB_RG"
  location = "centralindia"
}

#  VNET
resource "azurerm_virtual_network" "vnet" {
  name                = "my-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

# SUBNET
resource "azurerm_subnet" "subnet" {
  name                 = "my-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

#  SQL SERVER
resource "azurerm_mssql_server" "sqlserver" {
  name                         = "my-sql-server-aura123"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "sqladminaura"
  administrator_login_password = "P@ssword1234!"
}

#  SQL DATABASE
resource "azurerm_mssql_database" "sqldb" {
  name      = "my-sqldb"
  server_id = azurerm_mssql_server.sqlserver.id
  sku_name  = "Basic"
}

#  FIREWALL FIX (NO CONNECTION ISSUE)
resource "azurerm_mssql_firewall_rule" "allow_azure" {
  name             = "AllowAzure"
  server_id        = azurerm_mssql_server.sqlserver.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# PUBLIC IP
resource "azurerm_public_ip" "pip" {
  name                = "lb-ip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

#  LOAD BALANCER
resource "azurerm_lb" "lb" {
  name                = "lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.pip.id
  }
}

#  BACKEND POOL
resource "azurerm_lb_backend_address_pool" "pool" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "backend"
}

#  STABLE HTTP PROBE (NO BUG)
resource "azurerm_lb_probe" "probe" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "probe"
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

#  LB RULE (STABLE ORDER)
resource "azurerm_lb_rule" "rule" {
  depends_on = [azurerm_lb_probe.probe]

  loadbalancer_id                = azurerm_lb.lb.id
  name                           = "http-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.pool.id]
  probe_id                       = azurerm_lb_probe.probe.id
}

#  NSG
resource "azurerm_network_security_group" "nsg" {
  name                = "vmss-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

#  NSG ASSOCIATION
resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

#  VMSS (FULLY FIXED)
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "vmss"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard_D2s_v4"
  instances           = 2

  admin_username = "azureaura"
  admin_password = "P@ssword1234!"

  disable_password_authentication = false

  custom_data = base64encode(<<EOF
#!/bin/bash

apt update -y
apt install -y nginx python3 python3-pip curl apt-transport-https ca-certificates gnupg unixodbc unixodbc-dev odbcinst

# Microsoft repo
curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
curl https://packages.microsoft.com/config/ubuntu/18.04/prod.list > /etc/apt/sources.list.d/msprod.list

apt update -y
ACCEPT_EULA=Y apt install -y msodbcsql17

pip3 install flask pyodbc

mkdir -p /app

cat <<EOL > /app/app.py
from flask import Flask, request
import pyodbc

app = Flask(__name__)

conn = pyodbc.connect(
    'DRIVER={ODBC Driver 17 for SQL Server};'
    'SERVER=my-sql-server-aura123.database.windows.net,1433;'
    'DATABASE=my-sqldb;'
    'UID=sqladminaura;'
    'PWD=P@ssword1234!'
)

@app.route('/save', methods=['POST'])
def save():
    username = request.form['username']
    cursor = conn.cursor()
    cursor.execute("INSERT INTO users (username) VALUES (?)", username)
    conn.commit()
    return "Saved in Azure DB: " + username

app.run(host='0.0.0.0', port=5000)
EOL

# start backend
nohup python3 /app/app.py > /app/app.log 2>&1 &

# frontend
cat <<EOL > /var/www/html/index.html
<html>
<body>
<h2>Enter Username</h2>
<form action="/save" method="post">
<input type="text" name="username">
<button type="submit">Save</button>
</form>
</body>
</html>
EOL

# nginx config
cat <<EOL > /etc/nginx/sites-available/default
server {
    listen 80;
    location / {
        root /var/www/html;
        index index.html;
    }
    location /save {
        proxy_pass http://localhost:5000/save;
    }
}
EOL

systemctl restart nginx
EOF
)

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "nic"
    primary = true

    ip_configuration {
      name      = "ipconfig"
      subnet_id = azurerm_subnet.subnet.id
      primary   = true

      load_balancer_backend_address_pool_ids = [
        azurerm_lb_backend_address_pool.pool.id
      ]
    }
  }
}

# OUTPUT
output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}
