# 10 · Docker: the portal as a container

> **Goal:** package the same portal app as a container image, run it on one of the lab servers next to the normal service, and understand where containers fit in AWS (ECR, ECS, EKS).

## Why a company does this

A container image bundles the app with its exact runtime and libraries, so it runs the same on a laptop, a test server and production. Most PH junior cloud/DevOps posts list "Docker basics" and "Kubernetes knowledge is a plus". This doc covers the basics hands-on and the rest as concepts, because a managed Kubernetes cluster (EKS) costs about $0.10/hour for the control plane alone.

## The Dockerfile ([`app/Dockerfile`](../app/Dockerfile))

```dockerfile
FROM public.ecr.aws/docker/library/python:3.12-slim   # base image (ECR Public mirror: no Docker Hub rate limits)
WORKDIR /app
RUN pip install --no-cache-dir boto3 "psycopg[binary]" # dependencies: a cached layer
COPY app.py .                                          # the code: changes most often, so it comes last
ENV HOST=0.0.0.0 PORT=8080 AWS_DEFAULT_REGION=ap-southeast-1
USER nobody                                            # don't run as root inside the container
EXPOSE 8080
CMD ["python", "app.py"]
```

The user data script already copied `app.py` and this `Dockerfile` to `/opt/harbor` on every server.

## Build and run it on a lab server

```powershell
aws ssm start-session --target <instance-id>
```

```bash
sudo -i
dnf install -y docker
systemctl enable --now docker
docker version

mkdir -p /root/build && cp /opt/harbor/app.py /opt/harbor/Dockerfile /root/build/
cd /root/build                                  # a copy, so edits here don't touch the running service
docker build -t harbor-portal:1.0 .
docker images                                   # harbor-portal 1.0, a few hundred MB

docker run -d --name portal -p 8081:8080 harbor-portal:1.0
docker ps                                       # STATUS Up, PORTS 0.0.0.0:8081->8080/tcp
curl -s localhost:8081/health                   # ok
curl -s localhost:8081/ | grep "Served by"      # same instance ID: the container reads the host's metadata
curl -s localhost:8081/db                       # works: the container uses the instance role too

docker logs portal                              # the app's output
docker exec -it portal sh -c 'id; python --version'   # uid=65534(nobody), Python 3.12
docker stats --no-stream

docker stop portal && docker rm portal
```

> 🎓 **Why does the container reach the metadata service and the role?** The launch template sets `http_put_response_hop_limit = 2`. Traffic from a container crosses one extra network hop (the Docker bridge), so with a limit of 1 (EC2's general default), IMDSv2 tokens never reach the container. Amazon Linux 2023 AMIs already default to 2; the template sets it explicitly so the choice is visible. On ECS and EKS, tasks and pods get **their own** IAM role instead, which is better isolation.

Port 8081 is not open in any security group, so the container is reachable only from the instance itself. That's on purpose: this doc is about the container, not about exposing it.

## Image layers and caching

Run the build again: every step says `CACHED` (or finishes instantly). Now edit nothing but `app.py` in `/root/build` (e.g. `sed -i 's/Client Portal/Client Portal v2/' app.py`) and rebuild as `harbor-portal:1.1`: only the `COPY` layer and later rebuild. That's why dependencies are installed *before* the code is copied.

## Where this goes in AWS (concepts)

| Service | What it is | When |
|---|---|---|
| **ECR** | Private container registry (like Docker Hub, inside your account, IAM-controlled) | Store the images you build. `docker push <account>.dkr.ecr.<region>.amazonaws.com/harbor-portal:1.0` |
| **ECS on Fargate** | AWS runs your containers; no servers to manage | Most small/medium apps. The next step for this portal would be an ECS service behind the same ALB |
| **ECS on EC2** | Containers on your own instances | Cheaper at steady scale, more to manage |
| **EKS** | Managed Kubernetes | Teams that standardise on Kubernetes; more moving parts |
| **App Runner** | Give it an image, get an HTTPS URL | Simplest possible container hosting |

## Verify it worked

| Check | Expected |
|---|---|
| `docker build` | Successfully tagged `harbor-portal:1.0` |
| `curl -s localhost:8081/health` | `ok` |
| `docker exec … id` | `uid=65534(nobody)` |
| Rebuild after editing only `app.py` | Dependency layer cached |

_My output: (paste `docker ps`, the curl lines and the `id` output here)_

## Common mistakes

| Mistake | Result |
|---|---|
| App listens on `127.0.0.1` inside the container | `docker run -p` works but every request fails: listen on `0.0.0.0` (`HOST` env var here) |
| `COPY . .` before installing dependencies | Every code change reinstalls everything |
| Running as root in the container | A container escape lands as root on the host |
| Secrets baked into the image (`ENV PASSWORD=…`) | Anyone who can pull the image can read them with `docker history`. Read secrets at run time |
| Using `latest` tags in production | You can't tell which version is running or roll back cleanly |

## Interview questions

- **"Image vs container?"** An image is the read-only template (layers). A container is a running instance of an image with its own writable layer.
- **"VM vs container?"** A VM virtualises hardware and runs a full OS. Containers share the host kernel and isolate processes, so they start in seconds and are much smaller.
- **"What does `-p 8081:8080` mean?"** Host port 8081 forwards to container port 8080.
- **"ECS vs EKS?"** ECS is AWS's own simpler orchestrator. EKS is managed Kubernetes: portable and powerful, more to learn and run.
- **"What is Fargate?"** Serverless compute for containers: you define CPU/memory per task, AWS runs it, no EC2 instances to patch.
- **"How do containers on ECS get AWS permissions?"** A task IAM role, delivered through the ECS credentials endpoint, not the instance's role.

⬅️ [09 · Automation](09-automation-cloud-health-report.md) | ➡️ [11 · Troubleshooting and lessons](11-troubleshooting-and-lessons.md)
