SHELL := /usr/bin/env zsh

CONDA_ROOT := ~/miniconda3
ENV := emacs

ICONS := bluetooth flutter fastapi supabase postgresql python github pytest
ICON_DIR := assets/icons

.PHONY: docs docserve docbuild icons clean-icons

docs: docbuild

docserve: icons
	source $(CONDA_ROOT)/etc/profile.d/conda.sh && \
	conda activate $(ENV) && \
	mkdocs serve

docbuild: icons
	source $(CONDA_ROOT)/etc/profile.d/conda.sh && \
	conda activate $(ENV) && \
	mkdocs build

icons: $(ICON_DIR)
	@for icon in $(ICONS); do \
		if [ ! -f "$(ICON_DIR)/$$icon.svg" ]; then \
			curl -sL "https://cdn.simpleicons.org/$$icon" -o "$(ICON_DIR)/$$icon.svg"; \
		fi; \
	done

$(ICON_DIR):
	mkdir -p $(ICON_DIR)

clean-icons:
	rm -rf $(ICON_DIR)
