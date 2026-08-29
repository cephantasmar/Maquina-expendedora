#!/bin/bash
# ==============================================================================
# Script de aprovisionamiento inicial para Máquina Virtual Azure (Ubuntu)
# Proyecto: Máquina Expendedora Inteligente (Grog Platform)
# ==============================================================================

set -e

echo "📦 1. Actualizando paquetes del sistema..."
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release git

echo "🐳 2. Instalando Docker y Docker Compose..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
fi

echo "👤 3. Configurando permisos de usuario para Docker..."
sudo usermod -aG docker "$USER"
sudo systemctl enable docker
sudo systemctl restart docker

echo "📁 4. Verificando versiones instaladas..."
docker --version
docker compose version

echo "=============================================================================="
echo "✅ Servidor aprovisionado con éxito."
echo "ℹ️  Cierra sesión y vuelve a conectarte por SSH para aplicar los permisos de Docker."
echo "=============================================================================="
