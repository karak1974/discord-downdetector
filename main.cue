package main

import (
    "dagger.io/dagger"
    "universe.dagger.io/alpine"
    "universe.dagger.io/docker"
    "universe.dagger.io/docker/cli"
    "universe.dagger.io/go"
)

dagger.#Plan & {
    client: {
        filesystem: "./": read: {
            contents: dagger.#FS
        }
        network: "unix:///var/run/docker.sock": connect: {
            dagger.#Socket
        }
        env: SECRET: {
            dagger.#Secret
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
                    }
                },
                docker.#Run & {
                    command: {
                        name: "update-ca-certificates"
                    }
                },
                // COPY
                docker.#Copy & {
                    contents: build.output
                    dest:     "/app"
                },
                docker.#Set & {
                    config: cmd: ["./main"]
                },
            ]
        }

        // Push image to remote registry (depends on image)
        push: {
            // Docker username
            _dockerUsername: "wolfy42"

            docker.#Push & {
                "image": run.output
                dest:    "\(_dockerUsername)/discord-downdetector"
                auth: {
                    username: _dockerUsername
                    secret:   client.env.SECRET
                }
            }
        }

        load: cli.#Load & {
            image: run.output
            host:  client.network."unix:///var/run/docker.sock".connect
            tag:   "discord-downdetector"
        }
    }
}
