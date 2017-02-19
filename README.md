# Docker Registry(v2) Manifest Cleanup
## About
This script will search your registry and delete all manifests that do not have any tags associated. Deletion happens through the docker-registry API and should, therefore, be reasonably safe. After running this, you should do a garbage collect in the registry to free up the disk space.

### Why does this happen?
Docker images can be pulled both via `image:tag` and via `image@digest`. Because of this, if you overwrite an `image:tag` with a different one (e.g., pushing nightly to `whateverimage:latest`) you will still be able to pull the OLD versions of that tag by using `image@digest`. This functionality means the registry garbage collect cannot remove an image because a reference still exists.

### Isn't this a bug?
Not really, some people use `image@digest` to make sure they pull the correct image to be certain that they get the right code in their project. Docker DAB files are one example of this.

There is; however, some work being done to make an API endpoint to find these 'hidden' manifests quickly. This work is being done in [docker/distribution#2170](https://github.com/docker/distribution/issues/2170) and [docker/distribution#2169](https://github.com/docker/distribution/pull/2169).

A feature request to be able to explicitly garbage collect untagged manifests is proposed in [docker/distribution#1844](https://github.com/docker/distribution/issues/1844). 

This repo is meant as a workaround until we have the necessary tooling in Docker and registry to handle this without 3rd party tools.

## Usage
Replace the `<path-to-registry>` and `<registry-url>` in the below commands. See the *example* below if needed.

To do a dry-run, add `-e DRY_RUN=true`.

After running this, you should do a garbage collect in the registry to free up the disk space.

#### For a normal http registry:
```
docker run -it -v <path-to-registry>:/registry -e REGISTRY_URL=<registry-url> mortensrasmussen/docker-registry-manifest-cleanup
```

#### For an https registry with self-signed certificates:
```
docker run -it -v <path-to-registry>:/registry -e REGISTRY_URL=<registry-url> -e CURL_INSECURE=true mortensrasmussen/docker-registry-manifest-cleanup
```

#### Dry-run
```
docker run -it -v <path-to-registry>:/registry -e REGISTRY_URL=<registry-url> -e DRY_RUN=true mortensrasmussen/docker-registry-manifest-cleanup
```

#### Example:
```
docker run -it -v /home/someuser/registry:/registry -e REGISTRY_URL=http://192.168.50.87:5000 mortensrasmussen/docker-registry-manifest-cleanup
```

## License
This project is distributed under [Apache License, Version 2.0.](LICENSE)

Copyright © 2017 Morten Steen Rasmussen
