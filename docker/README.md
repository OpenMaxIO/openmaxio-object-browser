# OpenMaxIO in docker 

### Prereqs
I assume this is being run on linux, if being run on windows you will need to generate certs diffirently

### Configuration

Set the location of minio:
docker-compose.yaml  
- You need to set the "services/openmaxio/environment/CONSOLE_MINIO_SERVER" variable to your minio endpoint

Use valid certs:
- If you want to use proper certs, place the cert and key in ./certs/minio.crt and ./certs/minio.key

Set other environment variables:
- If you want to set further environment variables for minio, in docker-compose.yaml  place them in "services/openmaxio/environment/"


### How to run

```

cd docker
# if using the self-signed certs, run the following line, if using proper certs, skip it
./generate_certs.sh
docker compose up -d 

```
