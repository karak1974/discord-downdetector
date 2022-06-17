package main

import (
    "dagger.io/dagger"
    
    "universe.dagger.io/alpine"
    "universe.dagger.io/docker"
    "universe.dagger.io/docker/cli"
    "universe.dagger.io/go"
)

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
            GITHUB_ACTOR:       string
            COSIGN_PRIVATE_KEY: dagger.#Secret
            COSIGN_PASSWORD:    dagger.#Secret
            DOCKER_REPO:        string
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

        // Ugly way to copy the secret and set the password env
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
			export: directories: {
                "/cosign.key": _
            }
		}
        _password: docker.#Run & {
			input: _cosign.output
			mounts: secret: {
				dest:     "/run/cosign.passwd"
				contents: client.env.COSIGN_PASSWORD
			}
			command: {
				name: "cp"
				args: ["/run/cosign.passwd", "/cosign.passwd"]
			}
			export: directories: {
                "/cosign.passwd": _
            }
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
                // Update certificates
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
                docker.#Copy & {
					contents: _password.export.directories."/cosign.passwd"
					dest:     "/"
				},
                // Copy from build to run
                docker.#Copy & {
                    contents: build.output
                    dest:     "/app"
                },
                // Sign with cosign
                docker.#Run & {
                    env: IMAGE_ID:        "\(client.env.DOCKER_REPO)/\(client.env.DOCKER_USER)/\(client.env.REPOSITORY)"
                    env: VERSION:         client.commands.version.stdout
                    env: REPOSITORY:      client.env.REPOSITORY
                    env: DEVELOPER:       client.env.GITHUB_ACTOR
                    env: COSIGN_PASSWORD: client.env.COSIGN_PASSWORD
                    command: {
                        name: "sh"
                        args: ["-c", #"""
                            echo Setting up Cosign
                            export COSIGN_PASSWORD=$(cat /cosign.passwd)
                            wget -q https://github.com/sigstore/cosign/releases/download/v1.6.0/cosign-linux-amd64
                            mv cosign-linux-amd64 /usr/local/bin/cosign
                            chmod +x /usr/local/bin/cosign
                            cosign sign --key cosign.key -a REPO=$REPOSITORY -a TAG=$VERSION -a SIGNER=GitHub -a DEVELOPER=$DEVELOPER -a TIMESTAMP=$(date --iso-8601="seconds") $IMAGE_ID:$VERSION
                            """#]
                    }
                },
                // Copy config from hsot to container
                docker.#Copy & {
                    contents: client.filesystem."./".read.contents
                    include: ["config.json"]
                    dest: "/"
                },
                // Run binary ar the end
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
