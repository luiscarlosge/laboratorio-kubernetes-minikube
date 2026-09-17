#!/bin/sh
# Escribe la identidad del Pod en un archivo estatico que la pagina consulta.
# Las variables llegan desde el manifiesto con la API descendante (downward API).
set -e

cat > /usr/share/nginx/html/pod.json <<JSON
{
  "pod":       "${POD_NAME:-desconocido}",
  "ip":        "${POD_IP:-desconocida}",
  "nodo":      "${NODE_NAME:-desconocido}",
  "namespace": "${POD_NAMESPACE:-default}",
  "imagen":    "${IMAGE_TAG:-guia-k8s:1.0}",
  "arranque":  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
JSON

echo "pod-info: identidad publicada para ${POD_NAME:-contenedor local}"
