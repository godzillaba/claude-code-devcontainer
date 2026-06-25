# `make` builds the image, exports it, and loads it into sbx.
# (the load step runs on the host — sbx can't run inside a sandbox)

.PHONY: template
template:
	docker build -t claude-sbx template/
	docker image save claude-sbx -o claude-sbx.tar
	sbx template load claude-sbx.tar
