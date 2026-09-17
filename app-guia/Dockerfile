# =============================================================================
#  Imagen de la guia del laboratorio de Kubernetes
#
#  Construir DENTRO del cluster (sin registro externo):
#     minikube image build -t guia-k8s:1.0 .
#
#  o apuntando el Docker local al demonio de minikube:
#     eval $(minikube docker-env)
#     docker build -t guia-k8s:1.0 .
# =============================================================================
FROM nginx:1.29-alpine

LABEL org.opencontainers.image.title="Guia del laboratorio de Kubernetes" \
      org.opencontainers.image.description="Pagina estatica con las instrucciones y los conceptos del laboratorio" \
      curso="Cloud Computing y DevOps"

# La pagina estatica
COPY index.html /usr/share/nginx/html/index.html

# Desactiva keep-alive para que cada peticion se reparta de nuevo entre replicas
COPY 00-keepalive.conf /etc/nginx/conf.d/00-keepalive.conf

# nginx:alpine ejecuta todos los scripts de /docker-entrypoint.d/ antes de
# arrancar. Este genera pod.json con la identidad del Pod (API descendente),
# que la pagina lee para mostrar quien esta respondiendo.
COPY 30-pod-info.sh /docker-entrypoint.d/30-pod-info.sh
RUN chmod +x /docker-entrypoint.d/30-pod-info.sh

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost/ >/dev/null || exit 1
