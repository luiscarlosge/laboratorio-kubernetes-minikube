# Laboratorio de Kubernetes con minikube

Paquete completo del laboratorio: infraestructura en Azure, clúster minikube y una
guía interactiva que se despliega como contenedor dentro del propio clúster.

## Despliegue rápido

```bash
chmod +x deploy.sh
./deploy.sh                       # crea la VM en Azure y publica las URLs

scp -r . azureuser@FQDN:~/k8s-lab-minikube/
ssh azureuser@FQDN
sudo bash ~/k8s-lab-minikube/install-minikube.sh
```

Luego, dentro de la máquina:

```bash
cd ~/lab/app-guia   && minikube image build -t guia-k8s:1.0 .
cd ~/lab/manifests  && kubectl apply -f 00-namespace.yaml -f 10-deployment-guia.yaml -f 11-service-guia.yaml
```

La guía queda en `http://FQDN:30080`.

## Contenido

| Ruta | Descripción |
|---|---|
| `GUIA-LABORATORIO.md` | Guía completa del laboratorio |
| `azuredeploy.json` | Plantilla ARM: VNet, NSG, IP pública con DNS, VM y apagado automático |
| `deploy.sh` | Despliegue con Azure CLI |
| `install-minikube.sh` | Instalador de Docker, kubectl, minikube y los servicios de systemd |
| `app-guia/` | Imagen del contenedor con la guía (`nginx:alpine` + `index.html`) |
| `app-portal/` | Imagen del portal que construye el estudiante, con el `Dockerfile` comentado |
| `manifests/` | Namespaces, Deployments, Services NodePort, RBAC, Ingress, Dashboard |
| `scripts/limpiar.sh` | Deshace el laboratorio dentro de la VM |

## Puertos publicados

| Puerto | Servicio |
|---|---|
| 22 | SSH |
| 30080 | Guía del laboratorio |
| 30081 | Portal construido por el estudiante |
| 30090 | Dashboard de Kubernetes (sin autenticación: restrinja el NSG a su IP) |
| 80 | Ingress NGINX (opcional) |

## Requisitos

Ubuntu 24.04, mínimo 2 vCPU y 4 GiB de RAM (recomendado `Standard_B2ms`, 8 GiB).
