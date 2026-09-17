# Laboratorio de Kubernetes con minikube

**Cloud Computing y DevOps** · Escuela Colombiana de Ingeniería Julio Garavito

---

## 0. Qué vamos a construir

Un clúster de Kubernetes de un solo nodo, creado con **minikube** sobre una máquina virtual Ubuntu 24.04 en Azure. Sobre él vamos a desplegar, en un contenedor construido por nosotros, la guía interactiva del laboratorio, y la vamos a publicar en Internet a través de un `Service` de tipo `NodePort` y las reglas del Network Security Group.

La guía que se despliega **no es un adorno**: contiene la explicación de los conceptos (Pods, Deployments, roles, exposición) y muestra en vivo cuál de las réplicas está atendiendo cada petición. A partir del paso 3 el laboratorio se sigue leyendo desde adentro del clúster.

```
        Internet  (solo la IP autorizada en el NSG)
             │  22 (SSH)   30080 (guía)   30081 (su app)   30090 (Dashboard)   80 (Ingress, opcional)
             ▼
   IP pública Standard + DNS  →  k8slab-xxxx.eastus2.cloudapp.azure.com
             │
   VNet 10.20.0.0/16 ── Subnet 10.20.1.0/24 ── NSG
   ┌─────────── VM Ubuntu 24.04 · Standard_B2ms · Docker ───────────┐
   │   socat (systemd)  0.0.0.0:30080 ─┐                            │
   │   ┌── contenedor minikube · 192.168.49.2 ◄─┘                   │
   │   │   Plano de control: apiserver · etcd · scheduler ·         │
   │   │                     controller-manager                     │
   │   │   Nodo:             kubelet · kube-proxy · containerd      │
   │   │   Namespace lab:    Deployment guia (2 Pods) + Service     │
   │   └───────────────────────────────────────────────────────────┘
   └────────────────────────────────────────────────────────────────┘
   + Apagado automático diario (23:00, hora de Bogotá)
```

### Por qué minikube y no AKS

Una suscripción *Azure for Students* no alcanza para un clúster administrado corriendo varios días. minikube levanta un clúster **real** —los mismos componentes, los mismos comandos, los mismos manifiestos— dentro de una sola máquina virtual pequeña. Lo único que cambia respecto de producción es la forma de publicar los servicios hacia afuera, y ese contraste hace parte de lo que se aprende aquí.

### Archivos del paquete

| Archivo | Para qué sirve |
|---|---|
| `azuredeploy.json` | Plantilla ARM: VNet, NSG, IP pública con DNS, VM, extensión de instalación y apagado automático |
| `deploy.sh` | Envoltorio de Azure CLI: detecta su IP, genera la llave SSH si falta y despliega la plantilla |
| `install-minikube.sh` | Se ejecuta en la VM: instala Docker, kubectl y minikube, arranca el clúster y publica los NodePort |
| `app-guia/` | Imagen del contenedor de la guía: `Dockerfile`, `index.html` y el script de identidad del Pod |
| `app-portal/` | Imagen del portal que construye el estudiante, con el `Dockerfile` comentado línea por línea |
| `manifests/` | Los objetos de Kubernetes que va a aplicar: Namespace, Deployment, Service, RBAC, Ingress, Dashboard |
| `scripts/limpiar.sh` | Deshace el laboratorio dentro de la VM |
| `diagramas/` | Las figuras de la guía, en PNG y SVG |

---

## 1. Prerrequisito: la máquina virtual

Puede crear la máquina de dos formas. **Cualquiera de las dos sirve**, elija una.

### Opción A — desde el portal (recomendada si está aprendiendo Azure)

Cree la VM en `https://portal.azure.com` con estos parámetros:

| Parámetro | Valor |
|---|---|
| Resource Group | Nuevo y exclusivo: `rg-k8s-<usuario>` |
| Región | East US 2, o la que permita su suscripción |
| Imagen | Ubuntu Server 24.04 LTS — x64 Gen2 |
| Tamaño | **Standard_B2ms** (2 vCPU, 8 GiB). Mínimo: Standard_B2s (2 vCPU, 4 GiB) |
| Autenticación | Clave pública SSH |
| Puertos de entrada públicos | Solo SSH (22). Los demás se agregan después |
| Disco | SSD estándar, 32 GiB |
| Apagado automático | Pestaña *Administración*: habilitado, 23:00, zona (UTC-05:00) Bogotá |

Después, en la hoja de la VM, *Información general* → junto a *Nombre DNS* haga clic en *Sin configurar* → *Etiqueta de nombre DNS*: `k8s-<usuario>` → *Guardar*. El nombre completo queda como `k8s-<usuario>.eastus2.cloudapp.azure.com`. Anótelo: en esta guía se llama **FQDN**.

### Opción B — desde Azure CLI, con la plantilla ARM

```bash
cd k8s-lab-minikube
chmod +x deploy.sh
./deploy.sh
```

El script inicia sesión si hace falta, genera la llave SSH si no existe, detecta su IP pública para autorizarla en el NSG, crea el grupo de recursos y despliega la plantilla. Al terminar imprime el comando SSH y las URLs.

> Si trabaja desde **Cloud Shell**, la IP que detecta el script es la de Cloud Shell y no la de su navegador. Consúltela en `https://api.ipify.org` y pásela explícitamente: `ALLOWED_IP=181.10.20.30/32 ./deploy.sh`.

### Reglas del Network Security Group

Por omisión el NSG bloquea todo el tráfico entrante. Agregue reglas **Inbound** que permitan estos puertos TCP **únicamente desde su IP pública**:

| Puerto | Para qué | ¿Obligatorio? |
|---|---|---|
| 22 | SSH a la máquina virtual | Sí |
| 30080 | `NodePort` de la guía del laboratorio | Sí |
| 30081 | `NodePort` de la aplicación que despliegue usted | Sí |
| 30090 | Dashboard de Kubernetes | Sí |
| 80 | Ingress NGINX (parte opcional del paso 9) | No |

> ### ⚠ Nunca use `0.0.0.0/0`
> El Dashboard que instala el complemento de minikube **no pide contraseña**. Publicado hacia todo Internet, le entrega control total del clúster a cualquiera que escanee el puerto; los escáneres automáticos encuentran estos puertos en minutos y los usan para minar criptomonedas. La regla debe apuntar a su IP pública (`/32`) y la máquina debe quedar apagada cuando no la esté usando. Si su IP cambia, edite la regla.

---

## 2. Clonar el repositorio e instalar el clúster

Todo el material vive en un repositorio público de GitHub:

```
https://github.com/luiscarlosge/laboratorio-kubernetes-minikube
```

Conéctese a la máquina y clone el repositorio **allí**, para no tener que copiar archivos desde su equipo:

```bash
ssh azureuser@FQDN

sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/luiscarlosge/laboratorio-kubernetes-minikube.git
cd laboratorio-kubernetes-minikube

sudo bash install-minikube.sh
```

Si prefiere no usar `git`, descargue el repositorio comprimido (pero después no podrá actualizar con `git pull`):

```bash
sudo apt-get install -y unzip
curl -LO https://github.com/luiscarlosge/laboratorio-kubernetes-minikube/archive/refs/heads/main.zip
unzip -q main.zip && cd laboratorio-kubernetes-minikube-main
```

El script tarda entre 5 y 10 minutos e instala Docker, kubectl y minikube; arranca el clúster con el controlador `docker` y el runtime `containerd`; habilita los complementos `metrics-server`, `dashboard` e `ingress`; y crea dos servicios de systemd:

- `minikube.service` — vuelve a levantar el clúster después de un reinicio de la VM.
- `minikube-expose@PUERTO.service` — publica un NodePort en todas las interfaces de la VM. Queda activo para 30080, 30081 y 30090.

Al terminar deja el material del laboratorio en **`~/lab`** (`app-guia/`, `manifests/`, `scripts/`), que es la ruta que usan los comandos de aquí en adelante.

Cierre la sesión SSH y vuelva a entrar, para que su usuario quede en el grupo `docker`.

### Verificación

```bash
kubectl get nodes -o wide
kubectl get pods -A
systemctl status minikube-expose@30080 --no-pager
```

El nodo debe aparecer en `Ready`, con el rol `control-plane`.

---

## 3. Conceptos que vamos a aplicar

Esta sección es un resumen. La versión completa, con tablas y diagramas, es la que despliega usted mismo en el paso 5 y queda disponible en `http://FQDN:30080`.

### Kubernetes es declarativo

Con Docker usted da órdenes: *arranca este contenedor*. Con Kubernetes declara un estado deseado: *quiero dos réplicas de esta imagen, siempre disponibles*. Un conjunto de controladores ejecuta un **bucle de reconciliación** que compara el estado real contra el declarado y actúa para cerrar la diferencia. La autosanación es consecuencia de ese bucle, no una función aparte.

### Los componentes y su rol

**Plano de control** — decide qué debe pasar:

| Componente | Rol |
|---|---|
| `kube-apiserver` | Única puerta de entrada. Todo habla por su API REST: usted, kubectl, los controladores y el kubelet. Autentica, autoriza y valida. |
| `etcd` | Base de datos clave-valor con el estado declarado del clúster. El único componente con estado real. |
| `kube-scheduler` | Decide en qué nodo corre cada Pod nuevo. |
| `kube-controller-manager` | Agrupa los controladores: réplicas, nodos, endpoints, cuentas de servicio. |

**En cada nodo** — ejecuta lo decidido:

| Componente | Rol |
|---|---|
| `kubelet` | Agente del nodo: recibe los Pods que le tocan, le pide al runtime que los arranque y reporta salud. |
| `kube-proxy` | Programa las reglas de red que hacen que la IP de un Service llegue a alguno de sus Pods. |
| `containerd` | Runtime: descarga imágenes y ejecuta los contenedores. |

En minikube todos conviven en un solo nodo, pero son procesos independientes que se comunican por red, igual que en un clúster real. Compruébelo con `kubectl get pods -n kube-system`.

### Pod

La unidad mínima que Kubernetes sabe programar. Envuelve uno o varios contenedores que **comparten red y volúmenes**: se ven entre sí en `localhost`, tienen una sola IP y viven y mueren juntos. Los Pods son **desechables**: no se reparan, se reemplazan. Su nombre lleva un sufijo aleatorio y su IP cambia en cada creación. Por eso nunca se guarda información importante en un Pod ni se le habla por su IP.

### Deployment

Un Pod suelto no tiene quien lo reponga. El objeto que se usa es el Deployment, que encadena `Deployment → ReplicaSet → Pods` y aporta escalado, autosanación y actualización progresiva con reversión.

### Roles

La palabra tiene dos sentidos en Kubernetes:

1. **El rol de un nodo** — `control-plane` o nodo de trabajo. Se ve en `kubectl get nodes`.
2. **El rol como permiso (RBAC)** — `Role` y `ClusterRole` listan permisos; `RoleBinding` y `ClusterRoleBinding` los conceden a alguien; `ServiceAccount` es la identidad de las aplicaciones que corren dentro del clúster. RBAC parte de negar todo: sin un binding explícito, la respuesta es no.

### Exposición

| Tipo | Alcance |
|---|---|
| `ClusterIP` | Solo desde dentro del clúster (valor por omisión) |
| `NodePort` | IP del nodo, puerto entre 30000 y 32767 |
| `LoadBalancer` | IP pública creada por el proveedor de nube |
| `Ingress` | Puertos 80/443, enrutando por nombre de host y ruta |

Con el controlador `docker`, minikube corre dentro de un contenedor con su propia red (`192.168.49.2`), así que el NodePort escucha en esa IP interna y no en la de la VM. El servicio `minikube-expose@` cubre ese tramo con `socat`. **Esa pieza no existe en un clúster de producción**, y entender por qué hace falta aquí es uno de los objetivos del laboratorio.

---

## 4. Generar el contenedor del portal

Kubernetes no despliega archivos ni repositorios: despliega **imágenes de contenedor**. Antes de que la página pueda existir como Pod hay que empaquetarla junto con el servidor web que la sirve, y ese empaquetado es la primera mitad del laboratorio.

### Imagen y contenedor

La **imagen** es una plantilla inmutable: un sistema de archivos congelado, hecho de capas apiladas, más los metadatos que indican qué proceso arrancar. El **contenedor** es una instancia en ejecución de esa imagen, con una capa de escritura encima que se descarta al terminar. De una imagen salen tantos contenedores idénticos como se quiera; es la misma relación que hay entre un archivo ISO y las máquinas instaladas desde él. De ahí la regla que se repite en todo Kubernetes: lo que se escriba dentro de un contenedor desaparece con él.

### El Dockerfile

Cada instrucción que toca el sistema de archivos crea una capa, y las capas se cachean: si una no cambió, la reconstrucción la reutiliza.

```dockerfile
FROM nginx:1.29-alpine              # capa base: servidor web ya instalado
LABEL autor="..." curso="..."       # metadatos, no cambian el comportamiento
COPY 00-keepalive.conf /etc/nginx/conf.d/
COPY 30-pod-info.sh /docker-entrypoint.d/
RUN chmod +x /docker-entrypoint.d/30-pod-info.sh
COPY index.html /usr/share/nginx/html/   # lo que más cambia, de último
EXPOSE 80                           # documenta el puerto; no abre nada
```

| Instrucción | Qué hace y por qué está ahí |
|---|---|
| `FROM` | Fija la base con versión exacta, nunca `latest`: una imagen reproducible es la diferencia entre un despliegue repetible y uno que depende del día. La variante `alpine` pesa ~50 MB contra ~190 MB de la imagen completa |
| `COPY` | Trae archivos desde el *contexto de construcción*, la carpeta que se indica al final del comando. Todo lo que esté ahí se le entrega al constructor |
| `RUN` | Ejecuta algo durante la construcción y guarda el resultado en una capa. En ejecución ya no vuelve a correr |
| `EXPOSE` | Solo documenta. Quien publica el puerto hacia afuera es el Service |
| `CMD` / `ENTRYPOINT` | No aparecen porque se heredan de `nginx`. Definen el proceso principal, y el contenedor vive exactamente lo que viva ese proceso |

El orden de los `COPY` no es casual: editar `index.html` invalida su capa y todas las posteriores, así que va de último y la reconstrucción tarda segundos.

El script que se copia a `/docker-entrypoint.d/` lo ejecuta la imagen oficial de nginx antes de arrancar, y escribe `pod.json` con el nombre del Pod, su IP y su nodo. Esos valores llegan como variables de entorno declaradas en el manifiesto con la **API descendante** (*downward API*).

### Probar el contenedor antes de Kubernetes

Si algo está mal en la imagen, es mucho más rápido descubrirlo aquí que persiguiendo un Pod en `CrashLoopBackOff`:

```bash
cd ~/lab/app-guia
cat Dockerfile
docker build -t guia-k8s:1.0 .
docker run -d --name prueba -p 8081:80 guia-k8s:1.0
curl -s localhost:8081 | head -5
curl -s localhost:8081/pod.json        # sin variables: dirá "desconocido"
docker rm -f prueba
```

### Dos almacenes distintos

Aquí está el error más común del laboratorio. La máquina virtual tiene su propio Docker; el nodo de minikube corre containerd **dentro** de un contenedor y tiene su propio almacén. Una imagen construida en el primero no existe para el segundo.

| Camino | Comando | Cuándo conviene |
|---|---|---|
| Construir adentro | `minikube image build -t guia-k8s:1.0 .` | Lo que usamos: un paso y la imagen queda donde el clúster la necesita |
| Construir afuera y cargar | `docker build …` + `minikube image load guia-k8s:1.0` | Cuando quiere probar el contenedor suelto con Docker antes |
| Publicar en un registro | `docker push registro/guia-k8s:1.0` | Lo real: cualquier nodo de cualquier clúster puede descargarla |

```bash
minikube image build -t guia-k8s:1.0 .
minikube image ls | grep guia-k8s

# Compruebe la diferencia entre los dos almacenes:
docker images | grep guia-k8s                     # almacén de la VM
minikube ssh -- sudo crictl images | grep guia    # almacén del nodo
```

Por eso el manifiesto usa `imagePullPolicy: IfNotPresent`. Con la política por omisión, Kubernetes ve una etiqueta que no reconoce, intenta descargarla de Docker Hub, no la encuentra y deja el Pod en `ErrImagePull`.

### Versionar la etiqueta, no el contenido

`guia-k8s:1.0` debería significar siempre los mismos bytes. Si cambia el HTML y reconstruye con la misma etiqueta, el clúster no tiene forma de notar la diferencia: los Pods que ya corren siguen con la versión vieja y `kubectl rollout` no tiene nada que hacer, porque el manifiesto no cambió. Cada cambio lleva etiqueta nueva, y `latest` es una mala idea en cualquier clúster serio.

---

## 5. Desplegar y abrir la guía

```bash
cd ~/lab/manifests
kubectl apply -f 00-namespace.yaml
kubectl apply -f 10-deployment-guia.yaml
kubectl apply -f 11-service-guia.yaml

kubectl -n lab rollout status deployment/guia
kubectl -n lab get deployment,replicaset,pod,service
```

Abra **`http://FQDN:30080`**. Si no carga, revise en orden: `kubectl -n lab get pods` (¿están `Running`?), `systemctl status minikube-expose@30080` (¿está activo el reenvío?) y la regla del NSG (¿su IP actual está autorizada?).

**Siga el resto del laboratorio desde la página**, que trae los pasos 4 al 9 con más detalle y el diagrama del recorrido de la petición. El resumen es:

| Paso | Qué se practica |
|---|---|
| 4 | `get`, `describe`, `logs`, `exec`. Ver el reparto entre réplicas. |
| 5 | Escalar a 4 réplicas, borrar un Pod y observar la autosanación. |
| 6 | Construir `guia-k8s:2.0`, `set image`, `rollout status`, `rollout undo`. |
| 7 | Publicar el Dashboard en 30090 y usar `kubectl top`. |
| 8 | Crear la cuenta `observador` y comprobar sus permisos con `kubectl auth can-i`. |
| 9 | Construir y publicar el portal propio en el 30081 (sección 6). |
| 10 | Opcional: publicar por Ingress en el puerto 80. |

---

## 6. Ejercicio propio: su portal en el 30081

Repita el ciclo completo por su cuenta con la carpeta `~/lab/app-portal`, que trae el mismo `Dockerfile` con comentarios en cada instrucción.

```bash
cd ~/lab/app-portal
nano index.html        # cambie el título y ponga su nombre
nano Dockerfile        # reemplace el LABEL autor

minikube image build -t portal:1.0 .
minikube image ls | grep portal
```

El Deployment ya está escrito en `50-deployment-portal.yaml`. **El Service lo escribe usted**: tome `11-service-guia.yaml` como modelo, cámbiele el namespace, el selector y el `nodePort` a 30081, y guárdelo como `mi-service.yaml`. Solo después compare con el archivo de referencia.

```bash
cd ~/lab/manifests
kubectl apply -f 00-namespace.yaml
kubectl apply -f 50-deployment-portal.yaml
kubectl apply -f mi-service.yaml
kubectl -n portal get deployment,pod,svc

diff mi-service.yaml 51-service-portal.yaml
```

Abra `http://FQDN:30081`. Si no responde, mire primero los *endpoints*: una lista vacía significa que el selector del Service no coincide con las etiquetas de los Pods, que es el error más frecuente.

```bash
kubectl -n portal get endpoints portal
kubectl -n portal describe svc portal
```

Para cerrar, edite otra vez la página, construya `portal:1.1` y publíquela con una actualización progresiva:

```bash
cd ~/lab/app-portal && minikube image build -t portal:1.1 .
kubectl -n portal set image deployment/portal portal=portal:1.1
kubectl -n portal rollout status deployment/portal
```

Compare además `50-deployment-portal.yaml` con `10-deployment-guia.yaml`: al segundo le sobran campos que el primero no tiene. ¿Qué se pierde al quitar las sondas y los límites de recursos?

## 7. Preguntas para entregar

Las nueve preguntas están en la página desplegada, sección *Preguntas*. Respóndalas con sus palabras y acompañe cada una con la captura o la salida de consola que la sustenta.

---

## 8. Limpieza

Dentro de la VM, para deshacer solo el laboratorio:

```bash
bash ~/lab/scripts/limpiar.sh
```

Desde su equipo, para borrar todo lo creado en Azure:

```bash
az group delete --name rg-k8s-lab --yes --no-wait
```

Desde el portal: *Grupos de recursos* → seleccione el suyo → *Eliminar grupo de recursos* → escriba el nombre para confirmar. Verifique que no queden discos ni IPs públicas huérfanas, porque siguen costando aunque la máquina ya no exista.

Si solo quiere pausar entre sesiones, use *Detener* desde el portal. Un `shutdown` dentro del sistema operativo no libera el cómputo y se sigue facturando.

---

## Solución de problemas

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| El navegador no conecta al 30080 | La regla del NSG no incluye su IP actual | Revise su IP en `https://api.ipify.org` y edite la regla |
| El puerto responde pero la página no carga | El reenvío se cayó | `sudo systemctl restart minikube-expose@30080` |
| Pod en `ErrImagePull` | La imagen se construyó en el Docker de la VM, no en el almacén del nodo | `minikube image build` o `minikube image load`, y verifique con `minikube image ls` |
| El Service responde pero no llega a ningún Pod | El selector del Service no coincide con las etiquetas del Pod | `kubectl get endpoints <servicio>`; si sale vacío, corrija el selector |
| Pod en `Pending` | No hay CPU o memoria suficiente | `kubectl describe pod` y lea los eventos; reduzca `replicas` o use una SKU mayor |
| `minikube start` falla por memoria | La VM tiene menos de 4 GiB | Use Standard_B2ms, o arranque con `minikube start --memory=2200mb` |
| `permission denied` al hablar con Docker | Su usuario quedó en el grupo `docker` después de abrir la sesión | Cierre la sesión SSH y vuelva a entrar |
| Tras reiniciar la VM no hay clúster | El servicio tarda en levantar | `systemctl status minikube` y espere; puede tomar dos minutos |
