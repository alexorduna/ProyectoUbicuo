# usa el python qur tengo (slim = version ligera) 
FROM python:3.11-slim

# dependencias del sistema que necesita OpenCV y MediaPipe 
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# directorio de trabajo dentro del contenedor 
WORKDIR /gestovoz

# Instala todo lo que necesita
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# copia todo el proyecto
COPY . .

# Exponer puerto de Jupyter 
EXPOSE 8888

# Comando al arrancar el contenedor 
CMD ["jupyter", "notebook", \
     "--ip=0.0.0.0", \
     "--port=8888", \
     "--no-browser", \
     "--allow-root", \
     "--NotebookApp.token=gestovoz"]