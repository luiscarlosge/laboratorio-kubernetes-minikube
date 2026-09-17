#!/usr/bin/env bash
# Deshace el laboratorio dentro de la máquina virtual.
# No borra nada en Azure: para eso, use  az group delete.
set -euo pipefail

echo "==> Borrando los objetos del laboratorio"
kubectl delete namespace lab --ignore-not-found
kubectl delete namespace portal --ignore-not-found
kubectl -n kubernetes-dashboard delete service dashboard-nodeport --ignore-not-found

read -rp "¿Borrar también el clúster minikube completo? [s/N] " r
if [[ "${r,,}" == "s" ]]; then
  echo "==> Deteniendo los reenvíos de puertos"
  for p in 80 30080 30081 30090; do
    sudo systemctl disable --now "minikube-expose@${p}.service" 2>/dev/null || true
  done
  echo "==> Borrando el clúster"
  sudo systemctl disable --now minikube.service 2>/dev/null || true
  minikube delete --all
fi

echo "==> Listo. Recuerde borrar el grupo de recursos en Azure."
