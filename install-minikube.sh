#!/usr/bin/env bash
# =============================================================================
#  Laboratorio de Kubernetes con minikube  ·  instalador de la maquina virtual
#  Ubuntu 24.04 LTS  ·  se ejecuta como root (sudo)
#
#  Uso:  sudo bash install-minikube.sh [usuario]
#        Si no se pasa usuario, se usa el primer usuario con UID 1000.
# =============================================================================
set -euo pipefail

MINIKUBE_VERSION="${MINIKUBE_VERSION:-v1.39.0}"
PUERTOS_PUBLICADOS="${PUERTOS_PUBLICADOS:-30080 30081 30090}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 0. Usuario duenio del clUster
# ---------------------------------------------------------------------------
LAB_USER="${1:-$(getent passwd 1000 | cut -d: -f1)}"
if [[ -z "$LAB_USER" ]] || ! id "$LAB_USER" &>/dev/null; then
  echo "ERROR: no se pudo determinar el usuario del laboratorio." >&2
  exit 1
fi
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
log "Usuario del laboratorio: $LAB_USER  (home: $LAB_HOME)"

# Ejecuta un comando como el usuario del laboratorio, con su entorno.
como_usuario() { sudo -u "$LAB_USER" -H env "HOME=$LAB_HOME" PATH=/usr/local/bin:/usr/bin:/bin "$@"; }

# ---------------------------------------------------------------------------
# 1. Paquetes base
# ---------------------------------------------------------------------------
log "Instalando paquetes base"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  ca-certificates curl gnupg jq socat conntrack tree unzip bash-completion apt-transport-https

# ---------------------------------------------------------------------------
# 2. Docker Engine  (driver de minikube)
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
  log "Instalando Docker Engine desde el repositorio oficial"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin
fi
systemctl enable --now docker
usermod -aG docker "$LAB_USER"

# ---------------------------------------------------------------------------
# 3. kubectl  (version estable publicada por el proyecto)
# ---------------------------------------------------------------------------
if ! command -v kubectl &>/dev/null; then
  KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  log "Instalando kubectl $KUBECTL_VERSION"
  curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  curl -fsSL -o /tmp/kubectl.sha256 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
  echo "$(cat /tmp/kubectl.sha256)  /usr/local/bin/kubectl" | sha256sum --check --status
  chmod 0755 /usr/local/bin/kubectl
fi

# ---------------------------------------------------------------------------
# 4. minikube
# ---------------------------------------------------------------------------
if ! command -v minikube &>/dev/null; then
  log "Instalando minikube $MINIKUBE_VERSION"
  if ! curl -fsSL -o /usr/local/bin/minikube \
        "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64"; then
    echo "Version ${MINIKUBE_VERSION} no disponible; se usa la ultima estable."
    curl -fsSL -o /usr/local/bin/minikube \
      "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
  fi
  chmod 0755 /usr/local/bin/minikube
fi

# ---------------------------------------------------------------------------
# 5. Dimensionamiento segUn la RAM disponible
# ---------------------------------------------------------------------------
RAM_TOTAL_MB="$(free -m | awk '/^Mem:/ {print $2}')"
CPUS="$(nproc)"
if (( RAM_TOTAL_MB >= 7000 )); then
  MK_MEM=5000          # Standard_B2ms (8 GiB)
elif (( RAM_TOTAL_MB >= 3500 )); then
  MK_MEM=2600          # Standard_B2s  (4 GiB)
else
  echo "ERROR: se necesitan al menos 4 GiB de RAM. Detectados: ${RAM_TOTAL_MB} MiB." >&2
  exit 1
fi
log "RAM detectada: ${RAM_TOTAL_MB} MiB  ->  minikube usara ${MK_MEM}m y ${CPUS} vCPU"

# ---------------------------------------------------------------------------
# 6. Arranque del clUster
# ---------------------------------------------------------------------------
log "Creando el clUster minikube (esto toma varios minutos)"
como_usuario minikube start \
  --driver=docker \
  --container-runtime=containerd \
  --cpus="$CPUS" \
  --memory="${MK_MEM}mb" \
  --extra-config=kubelet.housekeeping-interval=10s

log "Habilitando complementos: metrics-server, dashboard, ingress"
como_usuario minikube addons enable metrics-server
como_usuario minikube addons enable dashboard
como_usuario minikube addons enable ingress || echo "AVISO: el complemento ingress no quedo habilitado; es opcional."

# ---------------------------------------------------------------------------
# 7. Autocompletado y alias
# ---------------------------------------------------------------------------
kubectl completion bash > /etc/bash_completion.d/kubectl
minikube completion bash > /etc/bash_completion.d/minikube
if ! grep -q "alias k=" "$LAB_HOME/.bashrc" 2>/dev/null; then
  cat >> "$LAB_HOME/.bashrc" <<'BASHRC'

# --- Laboratorio de Kubernetes ---
alias k='kubectl'
complete -o default -F __start_kubectl k
export EDITOR=nano
BASHRC
fi

# ---------------------------------------------------------------------------
# 8. Servicios de systemd
#    minikube.service          -> el clUster vuelve a arrancar tras un reinicio
#    minikube-expose@PUERTO    -> publica un NodePort en todas las interfaces
# ---------------------------------------------------------------------------
log "Creando los servicios de systemd"
echo "LAB_USER=${LAB_USER}" > /etc/default/minikube-lab

cat > /etc/systemd/system/minikube.service <<UNIT
[Unit]
Description=Cluster minikube del laboratorio
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=${LAB_USER}
Environment=HOME=${LAB_HOME}
ExecStart=/usr/local/bin/minikube start
ExecStop=/usr/local/bin/minikube stop
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
UNIT

# minikube corre dentro de un contenedor con su propia red (192.168.49.0/24).
# El NodePort solo escucha en esa IP, no en la de la VM. Este reenvio TCP es
# el puente entre la interfaz publica de la VM y el NodePort del cluster.
cat > /usr/local/bin/minikube-expose <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
PUERTO="${1:?uso: minikube-expose <puerto>}"
# shellcheck source=/dev/null
source /etc/default/minikube-lab
IP=""
for _ in $(seq 1 60); do
  IP="$(sudo -u "$LAB_USER" -H minikube ip 2>/dev/null || true)"
  [[ -n "$IP" ]] && break
  sleep 5
done
[[ -n "$IP" ]] || { echo "El cluster minikube no responde." >&2; exit 1; }
echo "Publicando 0.0.0.0:${PUERTO} -> ${IP}:${PUERTO}"
exec socat "TCP-LISTEN:${PUERTO},fork,reuseaddr" "TCP:${IP}:${PUERTO}"
SCRIPT
chmod 0755 /usr/local/bin/minikube-expose

cat > /etc/systemd/system/minikube-expose@.service <<'UNIT'
[Unit]
Description=Publica el NodePort %i de minikube en todas las interfaces
After=minikube.service
Requires=minikube.service

[Service]
ExecStart=/usr/local/bin/minikube-expose %i
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable minikube.service >/dev/null
for p in $PUERTOS_PUBLICADOS; do
  systemctl enable --now "minikube-expose@${p}.service" >/dev/null
done

# ---------------------------------------------------------------------------
# 9. Material del laboratorio en el home del usuario
# ---------------------------------------------------------------------------
ORIGEN="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "$ORIGEN/app-guia" && -d "$ORIGEN/manifests" ]]; then
  log "Copiando el material del laboratorio a ${LAB_HOME}/lab"
  mkdir -p "$LAB_HOME/lab"
  cp -r "$ORIGEN/app-guia" "$ORIGEN/manifests" "$LAB_HOME/lab/"
  [[ -d "$ORIGEN/app-portal" ]] && cp -r "$ORIGEN/app-portal" "$LAB_HOME/lab/"
  [[ -d "$ORIGEN/scripts" ]] && cp -r "$ORIGEN/scripts" "$LAB_HOME/lab/"
  [[ -f "$ORIGEN/GUIA-LABORATORIO.md" ]] && cp "$ORIGEN/GUIA-LABORATORIO.md" "$LAB_HOME/lab/"
  chown -R "$LAB_USER:$LAB_USER" "$LAB_HOME/lab"
else
  echo "AVISO: no se encontraron app-guia/ ni manifests/ junto al instalador."
  echo "       Copie el paquete completo a la VM y vuelva a lanzar este script,"
  echo "       o copie a mano esas carpetas a ${LAB_HOME}/lab."
fi

# ---------------------------------------------------------------------------
# 10. Resumen
# ---------------------------------------------------------------------------
MK_IP="$(como_usuario minikube ip)"
FQDN="$(curl -fsSL -H Metadata:true --noproxy '*' \
  'http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text' 2>/dev/null || echo 'la-ip-publica')"

cat <<FIN

========================================================================
 El clUster minikube esta listo.
------------------------------------------------------------------------
 IP del nodo minikube : ${MK_IP}
 Puertos publicados   : ${PUERTOS_PUBLICADOS}
 Guia del laboratorio : http://${FQDN}:30080   (despues del Paso 3)
 Dashboard            : http://${FQDN}:30090   (despues del Paso 7)

 Conectese por SSH y verifique con:
   kubectl get nodes -o wide
   kubectl get pods -A
========================================================================

FIN
