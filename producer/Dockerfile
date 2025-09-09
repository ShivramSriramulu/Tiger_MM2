FROM python:3.11-slim
WORKDIR /app
COPY commitlog_producer.py /app/
RUN pip install --no-cache-dir kafka-python==2.0.2
ENTRYPOINT ["python", "commitlog_producer.py"]
