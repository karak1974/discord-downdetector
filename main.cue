package main

import (
    "dagger.io/dagger"
    
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
            REPOSITORY:         string
            GITHUB_REF:         string
            COSIGN_PRIVATE_KEY: dagger.#Secret
            DOCKER_USER:        string
            DOCKER_SECRET:      dagger.#Secret
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

        // Ugly way to copy the secret
		_cosign: alpine.#Build & {
			packages: {
				"bash": _
			}
		}
		_secret: docker.#Run & {
			input: _cosign.output
			mounts: secret: {
				dest:     "/run/cosign.key"
				contents: client.env.COSIGN_PRIVATE_KEY
			}
			command: {
				name: "cp"
				args: ["/run/cosign.key", "/cosign.key"]
			}
			export: directories: "/cosign.key": _
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
                // Put the private key into /cosign.key
                docker.#Copy & {
					contents: _secret.export.directories."/cosign.key"
					dest:     "/"
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
