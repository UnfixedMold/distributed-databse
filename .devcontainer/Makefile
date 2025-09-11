all: build

build:
	docker build . -t kape1395/vu_dist_sys_devcontainer

run: build
	docker run --rm -it kape1395/vu_dist_sys_devcontainer

.PHONY: all build run
