# To build you own OpenMaxIO UI: 

```bash
git clone https://github.com/OpenMaxIO/openmaxio-object-browser 
cd openmaxio-object-browser/web-app
yarn install 
yarn build 
cd ../
make console 
./console server 
```

# To connect OpenMaxIO UI to an existing Minio server run this command (replace 1.2.3.4:9000 to your address)

```bash
CONSOLE_MINIO_SERVER=http://1.2.3.4:9000 ./console server 
```

# OpenMaxIO Console

This is a fork of MinIO Console. 
This is a communitty driven project and is not affiliated with MinIO, Inc. 

OpenMaxIO is a community-maintained fork of MinIO, created in response to the removal of key features from the MinIO open-source distribution. Our goal is simple:
to preserve a fully open, fully functional, and production-grade object storage server that stays true to the original spirit of minimalism, performance, and freedom.

MinIO once stood for minimal, high-performance, open-source object storage. But recent changes have shifted core capabilities behind a commercial license. We believe the open-source ecosystem deserves better.

OpenMaxIO brings back what was removed and keeps it open for good.


## Contributing

We welcome contributions to OpenMaxIO Console. These are still early days, so please be patient as we work to restore and enhance the features you love.



![build](https://github.com/minio/console/workflows/Go/badge.svg) ![license](https://img.shields.io/badge/license-AGPL%20V3-blue)

A graphical user interface for [MinIO](https://github.com/minio/minio)

| Object Browser                     | Dashboard                     | Creating a bucket             |
|------------------------------------|-------------------------------|-------------------------------|
| ![Object Browser](images/pic3.png) | ![Dashboard](images/pic1.png) | ![Dashboard](images/pic2.png) |

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [MinIO Console](#minio-console)
  - [Install](#install)
    - [Build from source](#build-from-source)
  - [Setup](#setup)
    - [1. Create a user `console` using `mc`](#1-create-a-user-console-using-mc)
    - [2. Create a policy for `console` with admin access to all resources (for testing)](#2-create-a-policy-for-console-with-admin-access-to-all-resources-for-testing)
    - [3. Set the policy for the new `console` user](#3-set-the-policy-for-the-new-console-user)
  - [Start Console service:](#start-console-service)
  - [Start Console service with TLS:](#start-console-service-with-tls)
  - [Connect Console to a Minio using TLS and a self-signed certificate](#connect-console-to-a-minio-using-tls-and-a-self-signed-certificate)
- [Contribute to console Project](#contribute-to-console-project)

<!-- markdown-toc end -->

MinIO Console is a library that provides a management and browser UI overlay for the MinIO Server.

## Setup

All `console` needs is a MinIO user with admin privileges and URL pointing to your MinIO deployment.

> Note: We don't recommend using MinIO's Operator Credentials

### 1. Create a user `console` using `mc`

```bash
mc admin user add myminio/
Enter Access Key: console
Enter Secret Key: xxxxxxxx
```

### 2. Create a policy for `console` with admin access to all resources (for testing)

```sh
cat > admin.json << EOF
{
	"Version": "2012-10-17",
	"Statement": [{
			"Action": [
				"admin:*"
			],
			"Effect": "Allow",
			"Sid": ""
		},
		{
			"Action": [
                "s3:*"
			],
			"Effect": "Allow",
			"Resource": [
				"arn:aws:s3:::*"
			],
			"Sid": ""
		}
	]
}
EOF
```

```sh
mc admin policy create myminio/ consoleAdmin admin.json
```

### 3. Set the policy for the new `console` user

```sh
mc admin policy attach myminio consoleAdmin --user=console
```

> NOTE: Additionally, you can create policies to limit the privileges for other `console` users, for example, if you
> want the user to only have access to dashboard, buckets, notifications and watch page, the policy should look like
> this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "admin:ServerInfo"
      ],
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": [
        "s3:ListenBucketNotification",
        "s3:PutBucketNotification",
        "s3:GetBucketNotification",
        "s3:ListMultipartUploadParts",
        "s3:ListBucketMultipartUploads",
        "s3:ListBucket",
        "s3:HeadBucket",
        "s3:GetObject",
        "s3:GetBucketLocation",
        "s3:AbortMultipartUpload",
        "s3:CreateBucket",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:DeleteBucket",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy",
        "s3:GetBucketPolicy"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::*"
      ],
      "Sid": ""
    }
  ]
}
```

## Start Console service:

Before running console service, following environment settings must be supplied

```sh
# Salt to encrypt JWT payload
export CONSOLE_PBKDF_PASSPHRASE=SECRET

# Required to encrypt JWT payload
export CONSOLE_PBKDF_SALT=SECRET

# MinIO Endpoint
export CONSOLE_MINIO_SERVER=http://localhost:9000
```

Now start the console service.

```
./console server
2021-01-19 02:36:08.893735 I | 2021/01/19 02:36:08 server.go:129: Serving console at http://localhost:9090
```

By default `console` runs on port `9090` this can be changed with `--port` of your choice.

## Start Console service with TLS:

Copy your `public.crt` and `private.key` to `~/.console/certs`, then:

```sh
./console server
2021-01-19 02:36:08.893735 I | 2021/01/19 02:36:08 server.go:129: Serving console at http://[::]:9090
2021-01-19 02:36:08.893735 I | 2021/01/19 02:36:08 server.go:129: Serving console at https://[::]:9443
```

For advanced users, `console` has support for multiple certificates to service clients through multiple domains.

Following tree structure is expected for supporting multiple domains:

```sh
 certs/
  │
  ├─ public.crt
  ├─ private.key
  │
  ├─ example.com/
  │   │
  │   ├─ public.crt
  │   └─ private.key
  └─ foobar.org/
     │
     ├─ public.crt
     └─ private.key
  ...

```

## Connect Console to a Minio using TLS and a self-signed certificate

Copy the MinIO `ca.crt` under `~/.console/certs/CAs`, then:

```sh
export CONSOLE_MINIO_SERVER=https://localhost:9000
./console server
```

You can verify that the apis work by doing the request on `localhost:9090/api/v1/...`

## Debug logging

In some cases it may be convenient to log all HTTP requests. This can be enabled by setting
the `CONSOLE_DEBUG_LOGLEVEL` environment variable to one of the following values:

 - `0` (default) uses no logging.
 - `1` log single line per request for server-side errors (status-code 5xx).
 - `2` log single line per request for client-side and server-side errors (status-code 4xx/5xx).
 - `3` log single line per request for all requests (status-code 4xx/5xx).
 - `4` log details per request for server-side errors (status-code 5xx).
 - `5` log details per request for client-side and server-side errors (status-code 4xx/5xx).
 - `6` log details per request for all requests (status-code 4xx/5xx).

 A single line logging has the following information:
 - Remote endpoint (IP + port) of the request. Note that reverse proxies may hide the actual remote endpoint of the client's browser.
 - HTTP method and URL
 - Status code of the response (websocket connections are hijacked, so no response is shown)
 - Duration of the request

The detailed logging also includes all request and response headers (if any).
 
# Contribute to console Project

Please follow console [Contributor's Guide](https://github.com/minio/console/blob/master/CONTRIBUTING.md)

