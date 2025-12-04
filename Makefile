SUBDIR := era-agent

# Delegate top-level build targets to the agent subproject.
.PHONY: all agent fmt clean test image-python install uninstall

all: agent

agent fmt clean test image-python install uninstall:
	$(MAKE) -C $(SUBDIR) $@
