# GestoVoz — Docker Setup

Read me para el docker del modelo que servirá para la clasificación de gestos en cocina industrial.
Clasifica 8 gestos estáticos en tiempo real usando MediaPipe + Random Forest → voz sintetizada.
#### Equipo: 
- Christofer Castañeda
- Ivan Mijares
- Alexander Orduña
**Clase:** Computo Ubicuo — CETYS Universidad | Prof. Adan Hirales

## Requisitos
- [Docker Desktop](https://www.docker.com/products/docker-desktop) instalado y corriendo
- Windows 10/11, macOS o Linux
- ~3 GB de espacio libre 
> No necesitas Python, ni pip, ni ningún entorno virtual. Docker se encarga de todo.
## Estructura del proyecto

``` Archivos
Modelo_V1/
├── Dockerfile
├── .dockerignore
├── requirements.txt
├── README.md
├── Modelo_v1.ipynb
├── gestovoz_rf.pkl
├── gestovoz_rf.mlmodel
├── gestovoz_metadata.json
├── confusion_matrix.png
└── cache/
    ├── X_landmarks.npy
    └── y_labels.npy
```
#### Link para descargar el cache y los modelos para poder correr el codigo correctamente 
https://drive.google.com/drive/folders/1_SSX2huhgwJUGNN-kOMdi628UOHtKeQx?usp=drive_link

## Inicio rápido
### 1. Construir la imagen
Básicamente crea todo lo que se necesita para poder correr el proyecto se necesita estar en la carpeta del proyecto.
```bash
cd Modelo_V1/
docker build -t gestovoz:v1 .
```
> Solo necesitas hacer esto una vez. Tarda aprox. 5 minutos la primera vez.
### 2. Correr el contenedor
Activar el entorno para poder modificar el proyecto.
#### Windows (CMD):
```bash
docker run -p 8888:8888 -v "%cd%":/gestovoz gestovoz:v1
```

#### Windows (PowerShell):
```bash
docker run -p 8888:8888 -v "${PWD}:/gestovoz" gestovoz:v1
```

#### macOS / Linux:
```bash
docker run -p 8888:8888 -v "$(pwd)":/gestovoz gestovoz:v1
```
### 3. Abrir el notebook
Abre tu navegador en:
```
http://localhost:8888
```
Cuando pida token, escribe (es lo primero que se me ocurrió XD):
```
gestovoz
```
## Dependencias incluidas

| Paquete              | Versión  | Uso                            |
| -------------------- | -------- | ------------------------------ |
| Python               | 3.11     | Base                           |
| numpy                | 1.26.4   | Procesamiento de arrays        |
| opencv-python        | 4.8.1.78 | Lectura de imágenes            |
| mediapipe            | 0.10.9   | Extracción de landmarks        |
| scikit-learn         | 1.5.1    | Random Forest classifier       |
| coremltools          | 9.0      | Exportacion a Core ML (iOS)    |
| joblib               | latest   | Serializacion del modelo       |
| matplotlib + seaborn | latest   | Gráficas y matriz de confusión |
| tqdm                 | latest   | Barras de progreso             |
| jupyter              | latest   | Entorno de notebook            |

## Notas importantes
- **El cache ya existe** — si la carpeta `cache/` contiene `X_landmarks.npy` y `y_labels.npy`, el notebook los carga directamente sin re-extraer landmarks. La extracción completa tarda varios minutos (muchos).
- **Los archivos generados se guardan** — el flag `-v` dentro del contenedor hace que guarde todo. Cualquier archivo que genere el notebook (`.pkl`, `.mlmodel`, imágenes) se modifica en el proyecto.
- **El dataset HaGRID no esta incluido** — si necesitas usar otra vez el data set (no se porque y no lo recomiendo) usa esto y cambia la dirección:

```bash

docker run -p 8888:8888 \

  -v "%cd%":/gestovoz \

  -v "D:\hagrid_normalized":/hagrid \

  gestovoz:v1

```
Y actualiza `HAGRID_ROOT` en el notebook a `/hagrid`.
## Comandos utiles


```bash

# Ver contenedores corriendo
docker ps
# Parar el contenedor
docker stop <container_id>
# Ver todas las imagenes
docker images
# Eliminar la imagen (para reconstruir limpio)
docker rmi gestovoz:v1
# Reconstruir sin cache (fuerza reinstalar todo)
docker build --no-cache -t gestovoz:v1 .
```
## Metricas del modelo (v1.0)


| Metrica              | Valor  | Umbral MVP |
| -------------------- | ------ | ---------- |
| F1 Macro             | 0.8591 | >= 0.85 ✅  |
| Accuracy             | 0.8639 | >= 0.85 ✅  |
| Recall palm (alerta) | 0.9218 | >= 0.90 ✅  |

Modelo exportado: `gestovoz_rf.mlmodel` (50 arboles, optimizado para iOS via Core ML)
