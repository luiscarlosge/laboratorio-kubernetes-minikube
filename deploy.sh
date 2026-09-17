#!/usr/bin/env bash
# =============================================================================
#  Despliegue del laboratorio de Kubernetes en Azure
#
#  Uso:   ./deploy.sh
#  Variables opcionales:
#    RG_NAME        nombre del grupo de recursos   (por defecto rg-k8s-lab)
#    LOCATION       region                          (por defecto eastus2)
#    VM_NAME        nombre de la VM                 (por defecto vm-k8s-lab)
#    VM_SIZE        SKU                             (por defecto Standard_B2ms)
#    ALLOWED_IP     IP o CIDR autorizado en el NSG  (por defecto, su IP publica)
#    SCRIPT_URI     URL cruda de install-minikube.sh (si se omite, se instala a mano)
# =============================================================================
set -euo pipefail

RG_NAME="${RG_NAME:-rg-k8s-lab}"
LOCATION="${LOCATION:-eastus2}"
VM_NAME="${VM_NAME:-vm-k8s-lab}"
VM_SIZE="${VM_SIZE:-Standard_B2ms}"
ADMIN_USER="${ADMIN_USER:-azureuser}"
SCRIPT_URI="${SCRIPT_URI:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa.pub}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

command -v az >/dev/null || { echo "Falta Azure CLI: https://aka.ms/azure-cli" >&2; exit 1; }
az account show >/dev/null 2>&1 || az login

# --- Llave SSH ---------------------------------------------------------------
if [[ ! -f "$SSH_KEY" ]]; then
  log "No se encontro $SSH_KEY; generando una llave nueva"
  ssh-keygen -t rsa -b 4096 -f "${SSH_KEY%.pub}" -N "" -q
fi

# --- IP autorizada -----------------------------------------------------------
if [[ -z "${ALLOWED_IP:-}" ]]; then
  ALLOWED_IP="$(curl -fsSL https://api.ipify.org)/32"
  log "IP publica detectada: $ALLOWED_IP"
  echo "    Si trabaja desde Cloud Shell, esta NO es la IP de su navegador."
  echo "    Consultela en https://api.ipify.org y relance con: ALLOWED_IP=<ip>/32 ./deploy.sh"
fi
[[ "$ALLOWED_IP" == "0.0.0.0/0" ]] && {
  echo "ERROR: 0.0.0.0/0 deja el Dashboard de Kubernetes abierto a Internet sin autenticacion." >&2
  exit 1
}

# --- Despliegue --------------------------------------------------------------
log "Creando el grupo de recursos $RG_NAME en $LOCATION"
az group create --name "$RG_NAME" --location "$LOCATION" --output none

log "Desplegando la plantilla ARM"
az deployment group create \
  --resource-group "$RG_NAME" \
  --name "despliegue-k8s-lab" \
  --template-file "$(dirname "$0")/azuredeploy.json" \
  --parameters \
      vmName="$VM_NAME" \
      vmSize="$VM_SIZE" \
      adminUsername="$ADMIN_USER" \
      adminPublicKey="$(cat "$SSH_KEY")" \
      allowedSourceIp="$ALLOWED_IP" \
      installScriptUri="$SCRIPT_URI" \
  --output none

FQDN="$(az deployment group show -g "$RG_NAME" -n despliegue-k8s-lab --query properties.outputs.fqdn.value -o tsv)"

cat <<FIN

========================================================================
 Despliegue terminado.
------------------------------------------------------------------------
 Conexion      : ssh ${ADMIN_USER}@${FQDN}
 Guia (30080)  : http://${FQDN}:30080
 Dashboard     : http://${FQDN}:30090
 IP autorizada : ${ALLOWED_IP}
FIN

if [[ -z "$SCRIPT_URI" ]]; then
  cat <<FIN
------------------------------------------------------------------------
 La VM quedo sin instalar. Copie el paquete e instale a mano:
   scp -r $(dirname "$0") ${ADMIN_USER}@${FQDN}:~/
   ssh ${ADMIN_USER}@${FQDN}
   sudo bash ~/$(basename "$(dirname "$0")")/install-minikube.sh
FIN
fi

cat <<FIN
------------------------------------------------------------------------
 Al terminar el laboratorio, borre todo con:
   az group delete --name ${RG_NAME} --yes --no-wait
========================================================================

FIN
