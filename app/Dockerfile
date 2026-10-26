# Doc 10 · the same portal app as a container image.
# Base image from the ECR Public mirror of Docker Hub's official images,
# which avoids Docker Hub's anonymous pull rate limits.
FROM public.ecr.aws/docker/library/python:3.12-slim

WORKDIR /app
RUN pip install --no-cache-dir boto3 "psycopg[binary]"
COPY app.py .

# Inside a container the app must listen on all interfaces, not just localhost.
ENV HOST=0.0.0.0 PORT=8080 AWS_DEFAULT_REGION=ap-southeast-2
USER nobody
EXPOSE 8080
CMD ["python", "app.py"]
