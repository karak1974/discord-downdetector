package main

import (
    "dagger.io/dagger"
    "universe.dagger.io/alpine"
    "universe.dagger.io/docker"
    "universe.dagger.io/docker/cli"
    "universe.dagger.io/go"
)
// TODO
// use github secrets for user, pass, host
// install cosign
// universal usecase
// branch, repository, image
dagger.#Plan & {
    // Declare client for multiple usecases
    client: {
        filesystem: "./": read: {
            contents: dagger.#FS
        }
        network: "unix:///var/run/docker.sock": connect: {
            dagger.#Socket
        }
        env: {
            APP_NAME:                     string
            SECRET:                       dagger.#Secret
            //GITHUB_SHA:                   string
            //SSH_PRIVATE_KEY_DOCKER_SWARM: dagger.#Secret
        }
    }

    actions: {
        // Build app in a Golang container
        build: go.#Build & {
            source: client.filesystem."./".read.contents
        }

        // Build lighter image
        run: docker.#Build & {
            steps: [
                alpine.#Build & {
                    packages: {
                        "gcc": _
                        "libc-dev": _
                        "ca-certificates": _
                        "git": _
                        "go": _
                    }
                },
                docker.#Run & {
                    command: {
                        name: "update-ca-certificates"
                    }
                },
                // Copy from build to run
                docker.#Copy & {
                    contents: build.output
                    dest:     "/app"
                },
                docker.#Copy & {
                    contents: client.filesystem."./".read.contents
                    include: ["config.json"]
                    dest: "/"
                },
                docker.#Set & {
                    config: cmd: ["./app/\(client.env.APP_NAME)"]
                },
            ]
        }

        // Push image to remote registry
        push: {
            _dockerUsername: "wolfy42"

            docker.#Push & {
                "image": run.output
                dest:    "\(_dockerUsername)/\(client.env.APP_NAME)"
                auth: {
                    username: _dockerUsername
                    secret:   client.env.SECRET
                }
            }
        }

        // Create a docker image localy
        load: cli.#Load & {
            image: run.output
            host:  client.network."unix:///var/run/docker.sock".connect
            tag:   client.env.APP_NAME
        }
    }
}
