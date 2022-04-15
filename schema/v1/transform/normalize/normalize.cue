package normalize

import (
	"github.com/ibuildthecloud/herd/schema/v1"
	"list"
	"path"
	"strconv"
	"strings"
)

#ToPublishPort: {
	IN="in": v1.#Port
	out:     v1.#PortSpec
	out:     {#ToPort & {in: IN}}.out & {
		publish: true
	}
}

#CombinePorts: {
	IN="in": {
		ports: [...v1.#PortSpec]
		publish: [...v1.#PortSpec]
	}
	out: [...v1.#PortSpec]
	out: IN.ports + IN.publish
}

#ToPort: {
	IN="in": v1.#Port
	out:     v1.#PortSpec
	_inStr:  string
	_inInt:  int & IN
	if _inInt != _|_ {
		_inStr: strconv.FormatInt(IN, 10)
	}
	if !( _inInt != _|_ ) {
		_inStr: IN
	}
	out: IN | {
		_portProto: strings.SplitN(_inStr, "/", 2)
		if len(_portProto) == 2 {
			protocol: _portProto[1]
		}
		_portPubPrivate: strings.SplitN(_portProto[0], ":", 2)
		port:            strconv.ParseInt(_portPubPrivate[0], 10, 32)
		if len(_portPubPrivate) == 2 {
			containerPort: strconv.ParseInt(_portPubPrivate[1], 10, 32)
		}
	}
}

#ToSidecar: {
	IN="in": {
		sidecarName: string
		container:   _
	}
	out: {
		{#ToContainer & {in: {name: IN.sidecarName, container: IN.container}}}.out
		init: IN.container.init
	}
}

#URI: {
	scheme: string
	name:   string | *""
	path:   string | *""
	query: [string]: [...string]
}

#ParseQueryToMapForKey: {
	IN="in": [string, string]
	out: [string]: bool
	out: {
		_key: IN[0]
		for p in strings.Split(IN[1], "&") {
			let _keyValue = strings.SplitN(p, "=", 2)
			if _keyValue[0] == _key && len(_keyValue) == 2 {
				"\(_keyValue[1])": true
			}
		}
	}
}

#ParseQueryForKey: {
	IN="in": [string, string]
	out: [...string]
	out: list.SortStrings([ for k, v in {#ParseQueryToMapForKey & {in: IN}}.out {k}])
}

#ToURI: {
	IN="in": string
	out:     #URI
	out: {
		let _schemeAndRest = strings.SplitN(IN, "://", 2)
		scheme: _schemeAndRest[0]
		if len(_schemeAndRest) > 1 {
			let _nameAndQuery = strings.SplitN(_schemeAndRest[1], "?", 2)
			let _nameAndPath = strings.SplitN(_nameAndQuery[0], "/", 2)
			name: _nameAndPath[0]
			if len(_nameAndPath) == 2 {
				path: _nameAndPath[1]
			}
			if len(_nameAndQuery) == 2 {
				for p in strings.Split(_nameAndQuery[1], "&") {
					let _keyValue = strings.SplitN(p, "=", 2)
					query: "\(_keyValue[0])": {#ParseQueryForKey & {in: [_keyValue[0], _nameAndQuery[1]]}}.out
				}
			}
		}
	}
}

#ToVolumeMount: {
	IN="in": {
		containerName: string
		dirname:       string
		dir:           v1.#Dir
	}
	out: v1.#VolumeMountSpec
	out: {
		if (IN.dir & v1.#ShortVolumeRef) != _|_ {
			volume: IN.dir
		}
		if (IN.dir & v1.#VolumeRef) != _|_ {
			let _uri = {#ToURI & {in: IN.dir}}.out
			volume: _uri.name
			if _uri.query["subPath"][0] != _|_ {
				subPath: _uri.query["subPath"][0]
			}
		}
		if (IN.dir & v1.#EphemeralRef) != _|_ {
			let _uri = {#ToURI & {in: IN.dir}}.out
			let _name = {#ToVolumeNameForEphemeralURI & {in: {
				dirname:       IN.dirname
				containerName: IN.containerName
				uri:           _uri
			}}}.out
			volume: _name
			if _uri.query["subPath"][0] != _|_ {
				subPath: _uri.query["subPath"][0]
			}
		}
		if (IN.dir & v1.#ContextDirRef) != _|_ {
			contextDir: IN.dir
		}
		if (IN.dir & v1.#SecretRef) != _|_ {
			let _uri = {#ToURI & {in: IN.dir}}.out
			secret: {
				name: _uri.name
				if _uri.query["optional"][0] != _|_ {
					optional: _uri.query.optional[0] == "true"
				}
			}
		}
	}
}

#URIToVolumeSpec: {
	IN="in": #URI
	out:     v1.#VolumeSpec
	out: {
		if strconv.Atoi(IN.query["size"][0]) != _|_ {
			size: strconv.Atoi(IN.query["size"][0])
		}
		if IN.query["accessMode"] != _|_ {
			accessModes: IN.query["accessMode"]
		}
		if IN.query["class"][0] != _|_ {
			class: IN.query["class"][0]
		}
	}
}

#ToVolumeNameForEphemeralURI: {
	IN="in": {
		dirname:       string
		containerName: string
		uri:           #URI
	}
	out: string
	out: {
		if IN.uri.scheme == "" || IN.uri.name == "" {
			"\(path.Join([IN.containerName, IN.dirname]))"
		}
		if IN.uri.scheme != "" && IN.uri.name != "" {
			"\(IN.uri.name)"
		}
	}
}

#ToVolumeSpecMap: {
	IN="in": {
		containerName: string
		dirname:       string
		dir:           v1.#Dir
	}
	out: [string]: v1.#VolumeSpec
	out: {
		if (IN.dir & v1.#ShortVolumeRef) != _|_ {
			"\(IN.dir)": {
			}
		}
		if (IN.dir & v1.#VolumeRef) != _|_ {
			let _uri = {#ToURI & {in: IN.dir}}.out
			"\(_uri.name)": {#URIToVolumeSpec & {in: _uri}}.out
		}
		if (IN.dir & v1.#EphemeralRef) != _|_ {
			let _uri = {#ToURI & {in: IN.dir}}.out
			let _name = {#ToVolumeNameForEphemeralURI & {in: {
				containerName: IN.containerName
				dirname:       IN.dirname
				uri:           _uri
			}}}.out
			"\(_name)": {{#URIToVolumeSpec & {in: _uri}}.out & {
				class: "ephemeral"
			}}
		}
	}
}

#ToBuild: {
	IN="in": string | v1.#Build
	out:     v1.#BuildSpec
	out:     {
		dockerfile: path.Join([IN, "Dockerfile"])
		context:    IN
	} | {
		dockerfile: IN.dockerfile
		context:    IN.context
		target:     IN.target
	}
}

#ToContainer: {
	IN="in": {
		name:      string
		container: _
	}
	out: {
		for k, v in IN.container.files {
			files: "\(k)": {#ToFileSpec & {in: v}}.out
		}
		if IN.container["image"] != _|_ {
			image: IN.container.image
		}
		if IN.container["build"] != _|_ {
			build: {#ToBuild & {in: IN.container.build}}.out
		}
		entrypoint: IN.container.entrypoint | strings.Split(IN.container.entrypoint, " ")
		for x in ["command", "cmd"] {
			if IN.container[x] != _|_ {
				command: IN.container[x] | strings.Split(IN.container[x], " ")
			}
		}
		for x in ["env", "environment"] {
			if IN.container[x] != _|_ {
				environment: {#ToEnvVarSpecs & {in: IN.container[x]}}.out
			}
		}
		for x in ["workdir", "workDir", "workingdir", "workingDir"] {
			if IN.container[x] != _|_ {
				workingDir: IN.container[x]
			}
		}
		for x in ["tty", "stdin", "interactive"] {
			if IN.container[x] != _|_ {
				interactive: IN.container[x]
			}
		}

		for x in ["dirs", "directories"] {
			if IN.container[x] != _|_ {
				for k, v in IN.container[x] {
					let _mount = {#ToVolumeMount & {in: {
						dirname:       k
						containerName: IN.name
						dir:           v
					}}}.out
					dirs: "\(k)": _mount
					if _mount["contextDir"] != _|_ {
						build: {
							if IN.container["image"] != _|_ {
								baseImage: IN.container.image
							}
							contextDirs: "\(k)": _mount.contextDir
						}
					}
				}
			}
		}

		ports: {
			if (IN.container["ports"] & int) != _|_ {
				[{#ToPort & {in: IN.container.ports}}.out]
			}
			if (IN.container["ports"] & string) != _|_ {
				[{#ToPort & {in: IN.container.ports}}.out]
			}
			if !((IN.container["ports"] & string) != _|_ ) &&
				!((IN.container["ports"] & int) != _|_ ) {
				[ for p in IN.container.ports {
					{#ToPort & {in: p}}.out
				}]
			}
		} + {
			if (IN.container["publish"] & int) != _|_ {
				[{#ToPublishPort & {in: IN.container.publish}}.out]
			}
			if (IN.container["publish"] & string) != _|_ {
				[{#ToPublishPort & {in: IN.container.publish}}.out]
			}
			if !((IN.container["publish"] & string) != _|_ ) &&
				!((IN.container["publish"] & int) != _|_) {
				[ for p in IN.container.publish {
					{#ToPublishPort & {in: p}}.out
				}]
			}
		}
	}
}

#ToAppSpec: {
	IN="in": {
		app: v1.#App
	}
	out: v1.#AppSpec
	out: {
		containers: {
			for k, v in IN.app.containers {
				"\(k)": {
					{#ToContainer & {in: {name: k, container: v}}}.out
					for sk, sv in v.sidecars {
						sidecars: "\(sk)": {
							{#ToSidecar & {in: {sidecarName: sk, container: sv}}}.out
						}
					}
				}
			}
		}
		jobs: {
			for k, v in IN.app.jobs {
				"\(k)": {
					{#ToContainer & {in: {name: k, container: v}}}.out
					for sk, sv in v.sidecars {
						sidecars: "\(sk)": {
							{#ToSidecar & {in: {sidecarName: sk, container: sv}}}.out
						}
					}
				}
			}
		}
		images: {
			for k, v in IN.app.images {
				"\(k)": {
					image: v.image
					if v["build"] != _|_ {
						build: {#ToBuild & {in: v.build}}.out
					}
				}
			}
		}
		volumes: {
			for k, v in IN.app.volumes {
				"\(k)": *v | {
					class: v.class
					size:  v.size
					accessModes: [v.accessMode]
				}
			}
			for x in ["dirs", "directories"] {
				for name, c in IN.app.containers {
					if c[x] != _|_ {
						for k, v in c[x] {
							{#ToVolumeSpecMap & {in: {dir: v, containerName: name, dirname: k}}}.out
						}
					}
					for name, sidecar in c.sidecars {
						if sidecar[x] != _|_ {
							for k, v in sidecar[x] {
								{#ToVolumeSpecMap & {in: {dir: v, containerName: name, dirname: k}}}.out
							}
						}
					}
				}
				for name, c in IN.app.jobs {
					if c[x] != _|_ {
						for k, v in c[x] {
							{#ToVolumeSpecMap & {in: {dir: v, containerName: name, dirname: k}}}.out
						}
					}
					for name, sidecar in c.sidecars {
						if sidecar[x] != _|_ {
							for k, v in sidecar[x] {
								{#ToVolumeSpecMap & {in: {dir: v, containerName: name, dirname: k}}}.out
							}
						}
					}
				}
			}
		}
		secrets: {
			for k, v in IN.app.secrets {
				"\(k)": v
			}
			for name, container in containers {
				for k, v in container.environment {
					if v["secret"] != _|_ {
						"\(v.secret.name)": {
							type: string | *"opaque"
							if v.secret["optional"] != _|_ {
								optional: v.secret.optional
							}
						}
					}
				}
				for k, v in container.files {
					if v["secret"] != _|_ {
						"\(v.secret.name)": {
							type: string | *"opaque"
							if v.secret["optional"] != _|_ {
								optional: v.secret.optional
							}
						}
					}
				}
				for k, v in container.dirs {
					if v["secret"] != _|_ {
						"\(v.secret.name)": {
							type: string | *"opaque"
							if v.secret["optional"] != _|_ {
								optional: v.secret.optional
							}
						}
					}
				}
			}
		}
	}
}

IN="in": {
	app: v1.#App
}
out: v1.#AppSpec
out: {
	{#ToAppSpec & {in: {app: IN.app}}}.out
}