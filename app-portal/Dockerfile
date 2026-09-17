# =============================================================================
#  Imagen del portal del estudiante
#
#  Este Dockerfile es el mismo de la guia, con comentarios que explican cada
#  instruccion. Lealo completo antes de construir: en el paso 3 del laboratorio
#  se le pide justificar cada linea.
#
#  Construir:   minikube image build -t portal:1.0 .
#  Probar:      minikube image ls | grep portal
# =============================================================================

# FROM: imagen base sobre la que se apila todo lo demas. Se fija la version
# exacta (1.29-alpine) y no "latest": una imagen reproducible es la diferencia
# entre un despliegue que se puede repetir y uno que depende del dia.
# La variante alpine pesa unos 50 MB frente a los ~190 MB de la imagen normal.
FROM nginx:1.29-alpine

# LABEL: metadatos de la imagen. No cambian el comportamiento, pero permiten
# saber quien construyo la imagen y para que. Se consultan con "docker inspect".
LABEL org.opencontainers.image.title="Portal del laboratorio de Kubernetes" \
      autor="CAMBIE ESTO POR SU NOMBRE" \
      curso="Cloud Computing y DevOps"

# COPY: cada instruccion COPY crea una capa nueva de solo lectura. Por eso se
# ponen primero los archivos que casi nunca cambian y de ultimo los que cambian
# en cada edicion: asi las reconstrucciones reutilizan las capas ya cacheadas.
COPY 00-keepalive.conf /etc/nginx/conf.d/00-keepalive.conf
COPY 30-pod-info.sh /docker-entrypoint.d/30-pod-info.sh

# RUN: ejecuta un comando durante la construccion y guarda el resultado en una
# capa. Aqui solo hace falta darle permiso de ejecucion al script de arranque.
RUN chmod +x /docker-entrypoint.d/30-pod-info.sh

# El archivo que mas va a editar va de ultimo, para no invalidar el cache.
COPY index.html /usr/share/nginx/html/index.html

# EXPOSE: documenta en que puerto escucha el proceso. Es informativo: no abre
# nada por si solo. Quien realmente publica el puerto es el Service de Kubernetes.
EXPOSE 80

# No hay CMD ni ENTRYPOINT porque se heredan de la imagen base: nginx ya sabe
# arrancar en primer plano. Un contenedor vive mientras viva su proceso
# principal; si ese proceso se manda al fondo, el contenedor termina de una vez.
