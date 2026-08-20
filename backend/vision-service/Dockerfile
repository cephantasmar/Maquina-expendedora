FROM python:3.11-slim

WORKDIR /app

# Instalar dependencias del sistema para OpenCV y Video
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    ffmpeg \
    libsm6 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --default-timeout=1000 --no-cache-dir -r requirements.txt

COPY frontend/ ./frontend
COPY app/ ./app

EXPOSE 8060

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8060"]
