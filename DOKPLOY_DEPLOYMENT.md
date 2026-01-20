# Guía de Despliegue de Dify en Dokploy

Esta guía documenta el proceso completo para adaptar Dify para su despliegue en Dokploy, eliminando la redundancia de proxies inversos y aprovechando el Traefik nativo de la plataforma.

---

## Tabla de Contenidos

1. [Contexto y Problema](#1-contexto-y-problema)
2. [Arquitectura Actual de Dify](#2-arquitectura-actual-de-dify)
3. [Arquitectura Objetivo con Dokploy](#3-arquitectura-objetivo-con-dokploy)
4. [Modificaciones Requeridas](#4-modificaciones-requeridas)
5. [Configuración de Labels de Traefik](#5-configuración-de-labels-de-traefik)
6. [Variables de Entorno](#6-variables-de-entorno)
7. [Consideraciones de Rendimiento](#7-consideraciones-de-rendimiento)
8. [Workflow de Actualización del Fork](#8-workflow-de-actualización-del-fork)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Contexto y Problema

### ¿Qué es Dokploy?

Dokploy es una plataforma de despliegue que utiliza **Traefik** como balanceador de carga e ingress controller. Gestiona automáticamente:
- Certificados SSL (Let's Encrypt)
- Enrutamiento de dominios
- Red interna (`dokploy-network`)

### El Conflicto

Dify está diseñado para despliegues standalone e incluye:
- **Nginx**: Proxy inverso que gestiona el tráfico en puertos 80/443
- **Certbot**: Gestión de certificados SSL

Esto genera tres problemas al desplegarlo en Dokploy:

| Problema | Descripción |
|----------|-------------|
| **Conflicto de Puertos** | Nginx de Dify y Traefik de Dokploy compiten por los puertos 80 y 443 |
| **Redundancia de Proxy** | El tráfico pasaría por Traefik → Nginx → Servicio, añadiendo latencia innecesaria |
| **Terminación SSL** | Problemas con la obtención de IPs reales y headers forwarded |

### Solución

Eliminar Nginx y Certbot de Dify, y configurar Traefik (via Dokploy) para enrutar directamente a los servicios internos.

---

## 2. Arquitectura Actual de Dify

### Servicios Principales

Dify se compone de múltiples servicios definidos en `docker/docker-compose-template.yaml`:

```
┌─────────────────────────────────────────────────────────────────┐
│                         NGINX (:80/:443)                        │
│        Proxy inverso - Punto de entrada actual                  │
└─────────────────────────────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐       ┌───────────────┐       ┌───────────────┐
│   web (:3000) │       │  api (:5001)  │       │plugin_daemon  │
│   Frontend    │       │   Backend     │       │   (:5002)     │
└───────────────┘       └───────────────┘       └───────────────┘
                                │
                    ┌───────────┼───────────┐
                    │           │           │
                    ▼           ▼           ▼
              ┌─────────┐ ┌─────────┐ ┌─────────┐
              │  Redis  │ │Postgres │ │ Worker  │
              └─────────┘ └─────────┘ └─────────┘
```

### Mapeo de Rutas en Nginx

El archivo `docker/nginx/conf.d/default.conf.template` define el enrutamiento:

| Ruta | Destino | Puerto |
|------|---------|--------|
| `/console/api` | api | 5001 |
| `/api` | api | 5001 |
| `/v1` | api | 5001 |
| `/files` | api | 5001 |
| `/mcp` | api | 5001 |
| `/triggers` | api | 5001 |
| `/e/` | plugin_daemon | 5002 |
| `/explore` | web | 3000 |
| `/` (todo lo demás) | web | 3000 |

---

## 3. Arquitectura Objetivo con Dokploy

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRAEFIK (Dokploy nativo)                     │
│              Gestión SSL + Enrutamiento + Load Balancing        │
└─────────────────────────────────────────────────────────────────┘
                                │
                        dokploy-network
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐       ┌───────────────┐       ┌───────────────┐
│   web (:3000) │       │  api (:5001)  │       │plugin_daemon  │
│   Frontend    │       │   Backend     │       │   (:5002)     │
│               │       │               │       │               │
│ Labels:       │       │ Labels:       │       │ Labels:       │
│ - Host()      │       │ - Host() &&   │       │ - Host() &&   │
│ - priority=1  │       │   PathPrefix  │       │   PathPrefix  │
│               │       │ - priority=100│       │ - priority=100│
└───────────────┘       └───────────────┘       └───────────────┘
        │                       │                       │
        └───────────────────────┼───────────────────────┘
                                │
                        ssrf_proxy_network (interna)
                                │
                    ┌───────────┼───────────┐
                    │           │           │
                    ▼           ▼           ▼
              ┌─────────┐ ┌─────────┐ ┌─────────┐
              │  Redis  │ │Postgres │ │ Worker  │
              └─────────┘ └─────────┘ └─────────┘
```

---

## 4. Modificaciones Requeridas

### 4.1 Eliminar Servicios Redundantes

En `docker/docker-compose-template.yaml`, eliminar:

#### Servicio Nginx (líneas 388-431)
```yaml
# ELIMINAR COMPLETAMENTE
nginx:
  image: nginx:latest
  restart: always
  # ... toda la configuración
```

#### Servicio Certbot (líneas 368-386)
```yaml
# ELIMINAR COMPLETAMENTE
certbot:
  image: certbot/certbot
  profiles:
    - certbot
  # ... toda la configuración
```

### 4.2 Configurar Redes

Modificar la sección `networks` al final del archivo:

```yaml
networks:
  # Mantener la red interna de seguridad para SSRF proxy
  ssrf_proxy_network:
    driver: bridge
    internal: true
  
  # Mantener red para Milvus si se usa
  milvus:
    driver: bridge
  
  # Mantener red para OpenSearch si se usa
  opensearch-net:
    driver: bridge
    internal: true
  
  # AÑADIR: Red externa de Dokploy
  dokploy-network:
    external: true
```

### 4.3 Conectar Servicios a dokploy-network

Añadir `dokploy-network` a cada servicio que necesite ser accesible por Traefik:

```yaml
api:
  # ... configuración existente ...
  networks:
    - ssrf_proxy_network
    - default
    - dokploy-network  # AÑADIR

web:
  # ... configuración existente ...
  networks:
    - dokploy-network  # AÑADIR

plugin_daemon:
  # ... configuración existente ...
  networks:
    - dokploy-network  # AÑADIR
```

---

## 5. Configuración de Labels de Traefik

### 5.1 Servicio `api` (Puerto 5001)

```yaml
api:
  image: langgenius/dify-api:1.11.4
  restart: always
  labels:
    - "traefik.enable=true"
    - "traefik.docker.network=dokploy-network"
    
    # Router para rutas del API
    - "traefik.http.routers.dify-api.rule=Host(`${DIFY_DOMAIN}`) && (PathPrefix(`/api`) || PathPrefix(`/v1`) || PathPrefix(`/console/api`) || PathPrefix(`/files`) || PathPrefix(`/mcp`) || PathPrefix(`/triggers`))"
    - "traefik.http.routers.dify-api.entrypoints=websecure"
    - "traefik.http.routers.dify-api.tls=true"
    - "traefik.http.routers.dify-api.priority=100"
    
    # Servicio
    - "traefik.http.services.dify-api.loadbalancer.server.port=5001"
    
    # Middleware para archivos grandes
    - "traefik.http.middlewares.dify-buffering.buffering.maxRequestBodyBytes=104857600"
    - "traefik.http.middlewares.dify-buffering.buffering.memRequestBodyBytes=2097152"
    - "traefik.http.routers.dify-api.middlewares=dify-buffering"
  # ... resto de configuración ...
```

### 5.2 Servicio `web` (Puerto 3000)

```yaml
web:
  image: langgenius/dify-web:1.11.4
  restart: always
  labels:
    - "traefik.enable=true"
    - "traefik.docker.network=dokploy-network"
    
    # Router catch-all para el frontend
    - "traefik.http.routers.dify-web.rule=Host(`${DIFY_DOMAIN}`)"
    - "traefik.http.routers.dify-web.entrypoints=websecure"
    - "traefik.http.routers.dify-web.tls=true"
    - "traefik.http.routers.dify-web.priority=1"
    
    # Servicio
    - "traefik.http.services.dify-web.loadbalancer.server.port=3000"
  # ... resto de configuración ...
```

### 5.3 Servicio `plugin_daemon` (Puerto 5002)

> **⚠️ IMPORTANTE**: Este servicio fue omitido en la especificación original pero es necesario para el funcionamiento de plugins.

```yaml
plugin_daemon:
  image: langgenius/dify-plugin-daemon:0.5.2-local
  restart: always
  labels:
    - "traefik.enable=true"
    - "traefik.docker.network=dokploy-network"
    
    # Router para rutas de plugins
    - "traefik.http.routers.dify-plugin.rule=Host(`${DIFY_DOMAIN}`) && PathPrefix(`/e/`)"
    - "traefik.http.routers.dify-plugin.entrypoints=websecure"
    - "traefik.http.routers.dify-plugin.tls=true"
    - "traefik.http.routers.dify-plugin.priority=100"
    
    # Servicio
    - "traefik.http.services.dify-plugin.loadbalancer.server.port=5002"
    
    # Header especial para plugin daemon
    - "traefik.http.middlewares.dify-plugin-headers.headers.customrequestheaders.Dify-Hook-Url=https://${DIFY_DOMAIN}"
    - "traefik.http.routers.dify-plugin.middlewares=dify-plugin-headers"
  # ... resto de configuración ...
```

### Resumen de Prioridades

Las prioridades aseguran que las rutas específicas tengan preferencia sobre el catch-all:

| Router | Prioridad | Motivo |
|--------|-----------|--------|
| `dify-api` | 100 | Rutas específicas del backend |
| `dify-plugin` | 100 | Rutas específicas de plugins |
| `dify-web` | 1 | Catch-all para frontend |

---

## 6. Variables de Entorno

### 6.1 Variables Críticas para el .env

Configura estas variables en Dokploy o en tu archivo `.env`:

```bash
# ========================================
# CONFIGURACIÓN DE DOMINIO
# ========================================
DIFY_DOMAIN=tu-dominio.com

# ========================================
# URLs DE LA APLICACIÓN
# Todas deben apuntar al dominio con HTTPS
# ========================================
CONSOLE_API_URL=https://tu-dominio.com
CONSOLE_WEB_URL=https://tu-dominio.com
SERVICE_API_URL=https://tu-dominio.com
APP_API_URL=https://tu-dominio.com
APP_WEB_URL=https://tu-dominio.com

# ========================================
# HEADERS FORWARDED
# Necesario para que Dify procese correctamente
# las cabeceras que envía Traefik
# ========================================
RESPECT_XFORWARD_HEADERS_ENABLED=true

# ========================================
# SSL Y SEGURIDAD (REQUERIDO PARA HTTPS)
# ========================================
# Estos valores son CRÍTICOS para evitar errores 401 en login
WEB_API_CORS_ALLOW_ORIGINS=https://tu-dominio.com
CONSOLE_CORS_ALLOW_ORIGINS=https://tu-dominio.com

COOKIE_DOMAIN=.tu-dominio.com
NEXT_PUBLIC_COOKIE_DOMAIN=.tu-dominio.com
# (Nota el punto inicial en COOKIE_DOMAIN para soportar subdominios)

# Referencia: Ver archivo docker/.env.dokploy para un template completo

```

### 6.2 Variables de Base de Datos y Redis

Mantén la configuración estándar o usa servicios externos:

```bash
# Base de datos
DB_HOST=db_postgres
DB_PORT=5432
DB_USERNAME=postgres
DB_PASSWORD=tu-password-seguro
DB_DATABASE=dify

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=tu-password-seguro
```

---

## 7. Consideraciones de Rendimiento

### 7.1 Límites de Subida de Archivos

Dify maneja archivos de conocimiento que pueden ser grandes. El valor por defecto de Nginx era 100MB.

**Configuración del Middleware de Buffering:**

```yaml
# En las labels del servicio api
- "traefik.http.middlewares.dify-buffering.buffering.maxRequestBodyBytes=104857600"  # 100MB
- "traefik.http.middlewares.dify-buffering.buffering.memRequestBodyBytes=2097152"     # 2MB en memoria, resto en disco
```

Si necesitas manejar archivos más grandes, ajusta `maxRequestBodyBytes`.

### 7.2 Timeouts para Streaming

Dify usa Server-Sent Events (SSE) para respuestas de LLM en streaming. Asegúrate de que no haya timeouts prematuros:

```yaml
# Configuración de timeouts largos
- "traefik.http.middlewares.dify-timeout.headers.customrequestheaders.Connection=keep-alive"
```

### 7.3 Persistencia de Volúmenes

Asegura que estos volúmenes persistan en Dokploy:

| Volumen | Propósito |
|---------|-----------|
| `./volumes/db/data` | Base de datos PostgreSQL |
| `./volumes/redis/data` | Cache de Redis |
| `./volumes/app/storage` | Archivos subidos por usuarios |
| `./volumes/plugin_daemon` | Datos de plugins |
| `./volumes/sandbox` | Sandbox de código |

---

## 8. Workflow de Actualización del Fork

### Estrategia de Ramas: `main` + `dokploy`

Se recomienda usar dos ramas para mantener el fork organizado:

| Rama | Propósito |
|------|-----------|
| `main` | Espejo limpio del upstream oficial |
| `dokploy` | Tus modificaciones para Dokploy |

**Ventajas de esta estrategia:**

- ✅ `main` siempre refleja el estado oficial de Dify
- ✅ Fácil ver exactamente qué modificaste: `git diff main..dokploy`
- ✅ Rollback sencillo si algo falla
- ✅ Conflictos aislados y manejables
- ✅ Dokploy despliega desde `dokploy`, no desde `main`

```
upstream/main ──────────────────────────────────────────────►
                    │              │              │
                    ▼              ▼              ▼
    main ───────────●──────────────●──────────────●──────────►  (espejo de upstream)
                    │              │              │
                    ▼              ▼              ▼
 dokploy ───────────●──────────────●──────────────●──────────►  (tus modificaciones)
                  merge          merge          merge
```

### 8.1 Configuración Inicial

```bash
# Clonar tu fork
git clone https://github.com/tu-usuario/dify.git
cd dify

# Añadir el repositorio oficial como upstream
git remote add upstream https://github.com/langgenius/dify.git

# Verificar remotes
git remote -v
# origin    https://github.com/tu-usuario/dify.git (fetch)
# origin    https://github.com/tu-usuario/dify.git (push)
# upstream  https://github.com/langgenius/dify.git (fetch)
# upstream  https://github.com/langgenius/dify.git (push)

# Crear la rama dokploy desde main
git checkout -b dokploy

# Aplicar las modificaciones para Dokploy (ver secciones 4 y 5)
# ... editar docker/docker-compose-template.yaml ...

# Commit de las modificaciones
git add .
git commit -m "feat: adapt docker-compose for Dokploy deployment"

# Push de ambas ramas
git push origin main
git push origin dokploy
```

### 8.2 Sincronización con Upstream (Proceso Regular)

Cuando hay una nueva versión de Dify:

```bash
# PASO 1: Actualizar main con upstream
git checkout main
git fetch upstream
git merge upstream/main
# (main nunca tiene conflictos porque es espejo limpio)

git push origin main

# PASO 2: Incorporar cambios a dokploy
git checkout dokploy
git merge main

# Si hay conflictos, resolverlos (ver 8.3)
# ...

git push origin dokploy

# PASO 3: Regenerar docker-compose.yaml
cd docker
python3 generate_docker_compose
cd ..

git add docker/docker-compose.yaml
git commit -m "chore: regenerate docker-compose after upstream sync"
git push origin dokploy
```

### 8.3 Resolución de Conflictos

Los conflictos solo ocurrirán en la rama `dokploy` al hacer merge de `main`. Los archivos probables son:

| Archivo | Estrategia |
|---------|------------|
| `docker/docker-compose-template.yaml` | Mantener tus labels de Traefik, aceptar nuevos servicios |
| `docker/.env.example` | Aceptar nuevas variables, mantener las tuyas |

**Ejemplo de resolución:**

```bash
# Durante el merge, si hay conflicto:
git status
# both modified: docker/docker-compose-template.yaml

# Abrir el archivo y buscar marcadores de conflicto
# <<<<<<< HEAD
# (tu versión con labels de Traefik)
# =======
# (versión del upstream)
# >>>>>>> main

# Resolución típica:
# 1. Mantener tus labels de Traefik en los servicios existentes
# 2. Aceptar nuevas versiones de imágenes
# 3. Si hay nuevos servicios, evaluar si necesitan labels

git add docker/docker-compose-template.yaml
git commit -m "fix: resolve merge conflicts, preserve Traefik labels"
```

### 8.4 Verificar Cambios del Upstream

Antes de hacer merge, puedes revisar qué cambió:

```bash
# Ver commits nuevos en upstream
git log main..upstream/main --oneline

# Ver cambios específicos en el template
git diff main..upstream/main -- docker/docker-compose-template.yaml

# Ver si hay nuevos servicios
git diff main..upstream/main -- docker/docker-compose-template.yaml | grep "^+.*image:"
```

### 8.5 Comparar tus Modificaciones

En cualquier momento puedes ver exactamente qué has cambiado respecto al upstream:

```bash
# Ver diferencias completas
git diff main..dokploy

# Ver solo archivos modificados
git diff main..dokploy --stat

# Ver cambios en el template específicamente
git diff main..dokploy -- docker/docker-compose-template.yaml
```

### 8.6 Configuración de Dokploy

En el panel de Dokploy, configura el servicio para usar la rama correcta:

- **Repository**: `https://github.com/tu-usuario/dify.git`
- **Branch**: `dokploy` ← Importante: NO usar `main`
- **Build Path**: `docker/`

Esto asegura que Dokploy siempre despliega tu versión adaptada.

### 8.7 Rollback de Emergencia

Si una actualización causa problemas:

```bash
# Opción A: Revertir el último merge en dokploy
git checkout dokploy
git revert -m 1 HEAD  # Revierte el merge manteniendo historial
git push origin dokploy

# Opción B: Reset duro al commit anterior (destructivo)
git checkout dokploy
git log --oneline  # Encontrar el commit anterior al merge
git reset --hard <commit-anterior>
git push origin dokploy --force
```

### Resumen del Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    WORKFLOW DE ACTUALIZACIÓN                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. git fetch upstream                                           │
│  2. git checkout main && git merge upstream/main                 │
│  3. git push origin main                                         │
│  4. git checkout dokploy && git merge main                       │
│  5. (resolver conflictos si los hay)                             │
│  6. cd docker && python3 generate_docker_compose                 │
│  7. git add . && git commit && git push origin dokploy           │
│  8. Dokploy detecta cambios y redespliega automáticamente        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```



## 9. Troubleshooting

### 9.1 Error 502 Bad Gateway

**Causa**: Traefik no puede conectar con el servicio.

**Soluciones**:
- Verificar que el servicio está en `dokploy-network`
- Comprobar que el puerto en las labels es correcto
- Revisar logs: `docker logs <contenedor>`

### 9.2 Error 404 en rutas del API

**Causa**: Las rutas no coinciden con las reglas de Traefik.

**Soluciones**:
- Verificar la prioridad de los routers
- Comprobar que todas las rutas están en el PathPrefix

### 9.3 Problemas de SSL/Redirección

**Causa**: URLs incorrectas en variables de entorno.

**Soluciones**:
```bash
# Verificar variables
docker exec <contenedor-api> env | grep URL

# Todas deben ser https://tu-dominio.com
```

### 9.4 Uploads Fallan con Archivos Grandes

**Causa**: Límite de body excedido.

**Soluciones**:
- Aumentar `maxRequestBodyBytes` en el middleware
- Verificar que el middleware está aplicado al router

### 9.5 Plugins No Funcionan

**Causa**: Falta el router para `/e/` o el header Dify-Hook-Url.

**Soluciones**:
- Verificar labels de `plugin_daemon`
- Comprobar que el middleware de headers está aplicado

---

## Anexo: Ejemplo Completo de docker-compose-template.yaml (Fragmento)

```yaml
x-shared-env: &shared-api-worker-env
services:
  api:
    image: langgenius/dify-api:1.11.4
    restart: always
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=dokploy-network"
      - "traefik.http.routers.dify-api.rule=Host(`${DIFY_DOMAIN}`) && (PathPrefix(`/api`) || PathPrefix(`/v1`) || PathPrefix(`/console/api`) || PathPrefix(`/files`) || PathPrefix(`/mcp`) || PathPrefix(`/triggers`))"
      - "traefik.http.routers.dify-api.entrypoints=websecure"
      - "traefik.http.routers.dify-api.tls=true"
      - "traefik.http.routers.dify-api.priority=100"
      - "traefik.http.services.dify-api.loadbalancer.server.port=5001"
      - "traefik.http.middlewares.dify-buffering.buffering.maxRequestBodyBytes=104857600"
      - "traefik.http.routers.dify-api.middlewares=dify-buffering"
    environment:
      <<: *shared-api-worker-env
      MODE: api
    networks:
      - ssrf_proxy_network
      - default
      - dokploy-network
    # ... resto de configuración

  web:
    image: langgenius/dify-web:1.11.4
    restart: always
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=dokploy-network"
      - "traefik.http.routers.dify-web.rule=Host(`${DIFY_DOMAIN}`)"
      - "traefik.http.routers.dify-web.entrypoints=websecure"
      - "traefik.http.routers.dify-web.tls=true"
      - "traefik.http.routers.dify-web.priority=1"
      - "traefik.http.services.dify-web.loadbalancer.server.port=3000"
    networks:
      - dokploy-network
    # ... resto de configuración

  plugin_daemon:
    image: langgenius/dify-plugin-daemon:0.5.2-local
    restart: always
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=dokploy-network"
      - "traefik.http.routers.dify-plugin.rule=Host(`${DIFY_DOMAIN}`) && PathPrefix(`/e/`)"
      - "traefik.http.routers.dify-plugin.entrypoints=websecure"
      - "traefik.http.routers.dify-plugin.tls=true"
      - "traefik.http.routers.dify-plugin.priority=100"
      - "traefik.http.services.dify-plugin.loadbalancer.server.port=5002"
    networks:
      - dokploy-network
    # ... resto de configuración

# ... otros servicios (worker, redis, postgres, etc.)

networks:
  ssrf_proxy_network:
    driver: bridge
    internal: true
  milvus:
    driver: bridge
  opensearch-net:
    driver: bridge
    internal: true
  dokploy-network:
    external: true

volumes:
  oradata:
  dify_es01_data:
```

---

## Checklist de Despliegue

### Configuración del Repositorio
- [ ] Fork del repositorio oficial de Dify creado
- [ ] Upstream configurado como remote (`git remote add upstream`)
- [ ] Rama `dokploy` creada desde `main`

### Modificaciones en la Rama `dokploy`
- [ ] Servicio `nginx` eliminado del template
- [ ] Servicio `certbot` eliminado del template
- [ ] Red `dokploy-network` declarada como externa
- [ ] Labels de Traefik añadidas a `api`
- [ ] Labels de Traefik añadidas a `web`
- [ ] Labels de Traefik añadidas a `plugin_daemon`
- [ ] Servicios conectados a `dokploy-network`
- [ ] `generate_docker_compose` ejecutado
- [ ] Cambios commiteados y pusheados a `origin/dokploy`

### Configuración en Dokploy
- [ ] Proyecto creado en Dokploy
- [ ] Repositorio configurado con rama `dokploy` (NO `main`)
- [ ] Variables de entorno configuradas
- [ ] `RESPECT_XFORWARD_HEADERS_ENABLED=true` configurado
- [ ] Dominio asignado

### Verificación
- [ ] Despliegue completado sin errores
- [ ] Acceso a consola web funcionando
- [ ] API respondiendo correctamente
- [ ] Plugins funcionando (ruta `/e/`)
- [ ] Subida de archivos funcionando

---

*Documento creado: 2026-01-20*
*Última actualización: 2026-01-20*
*Versión de Dify analizada: 1.11.4*

