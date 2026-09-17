# Laboratorio de Kubernetes con minikube

Paquete completo del laboratorio: infraestructura en Azure, clúster minikube y una
guía interactiva que se despliega como contenedor dentro del propio clúster.

## Despliegue rápido

Cree la máquina virtual (desde el portal de Azure, o con `deploy.sh` si prefiere Azure CLI),
conéctese por SSH y clone este repositorio **dentro de la máquina**:

```bash
ssh azureuser@FQDN

sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/luiscarlosge/laboratorio-kubernetes-minikube.git
cd laboratorio-kubernetes-minikube

sudo bash install-minikube.sh
```

Cierre la sesión SSH y vuelva a entrar (para quedar en el grupo `docker`). El instalador deja
el material en `~/lab`:

```bash
cd ~/lab/app-guia   && minikube image build -t guia-k8s:1.0 .
cd ~/lab/manifests  && kubectl apply -f 00-namespace.yaml -f 10-deployment-guia.yaml -f 11-service-guia.yaml
```

La guía queda en `http://FQDN:30080`. Para traer correcciones publicadas después:
`git pull` dentro de la carpeta clonada.

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
