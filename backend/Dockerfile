# Build context: the REPO ROOT, not backend/. The backend code lives under
# /app and the canonical data CSVs land at /data/, which is where
# `Settings.resolved_data_path` and `resolved_stadium_map_path` resolve to
# inside the container ( `Path(__file__).parent.parent / "../data/..."` ).
#
# Build from the repo root with:
#   docker build -f backend/Dockerfile -t ucluj-backend .

FROM python:3.11-slim

WORKDIR /app

# Layer 1: dependencies. Cached as long as requirements.txt does not change.
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Layer 2: backend source.
COPY backend/ .

# Layer 3: canonical training data and stadium map at the path the config
# resolves to. Only the two files the FastAPI lifespan actually loads are
# copied; the notebooks stay out of the image.
COPY data/All_Data.csv /data/All_Data.csv
COPY data/reference /data/reference

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
