package main

import (
    "dagger.io/dagger"
    "dagger.io/dagger/core"
    
    "universe.dagger.io/alpine"
    "universe.dagger.io/docker"
    "universe.dagger.io/docker/cli"
    "universe.dagger.io/go"
)
// TODO
// install cosign

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
            REPOSITORY:    string
            GITHUB_REF:    string
            DOCKER_USER:   string
            DOCKER_SECRET: dagger.#Secret
        }
       commands: {
            version: {
                name: "bash"
                args: ["-c", #"""
					if [[ \#(client.env.GITHUB_REF) =~ "refs/tags/" ]]; then echo \#(client.env.GITHUB_REF) | sed -e 's/^refs\/tags\/v//' | tr -d "[:space:]"
					elif [[ \#(client.env.GITHUB_REF) =~ "refs/heads/" ]]; then echo \#(client.env.GITHUB_REF) | sed -e 's/^refs\/heads\///' | tr -d "[:space:]"
					fi
					"""#]
                stdout: string
            }
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
                    config: cmd: ["./app/\(client.env.REPOSITORY)"]
                },
            ]
        }

        // Push image to remote registry
        push: {

            docker.#Push & {
                "image": run.output
                dest:    "\(client.env.DOCKER_USER)/\(client.env.REPOSITORY):\(client.commands.version.stdout)"
                auth: {
                    username: client.env.DOCKER_USER
                    secret:   client.env.DOCKER_SECRET
                }
            }
        }

        // Create a docker image localy
        load: cli.#Load & {
            image: run.output
            tag:   client.env.REPOSITORY
            host:  client.network."unix:///var/run/docker.sock".connect
        }
    }
}
