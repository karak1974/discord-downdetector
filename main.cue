package main

import (
    "tool/exec"
    
    "dagger.io/dagger"
    
    "universe.dagger.io/alpine"
    "universe.dagger.io/docker"
    "universe.dagger.io/docker/cli"
    "universe.dagger.io/go"
)
// TODO
// install cosign
// First with one branch
// Later add multiple branches as multiple tags

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
            REPOSITORY_NAME: string
            DOCKER_USER:     string
            DOCKER_SECRET:   dagger.#Secret
        }
    }

    actions: {
        version_pre: exec.#Run & {
		    cmd: ["echo", "\"${{ github.ref }}\"", "|", "sed -e 's,.*/\(.*\),\1,'"]
		    stdout: string
	    }
        version: exec.#Run & {
		    cmd: ["[[ \"${{ github.ref }}\" == \"refs/tags/\"* ]] && echo \(version_pre.stdout) | sed -e 's/^v//'"]
		    stdout: string
	    }
        
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
                    config: cmd: ["./app/\(client.env.REPOSITORY_NAME)"]
                },
            ]
        }

        // Push image to remote registry
        push: {

            docker.#Push & {
                "image": run.output
                dest:    "\(client.env.DOCKER_USER)/\(client.env.REPOSITORY_NAME)_\(version.stdout)"
                auth: {
                    username: client.env.DOCKER_USER
                    secret:   client.env.DOCKER_SECRET
                }
            }
        }

        // Create a docker image localy
        load: cli.#Load & {
            image: run.output
            host:  client.network."unix:///var/run/docker.sock".connect
            tag:   client.env.REPOSITORY_NAME
        }
    }
}
