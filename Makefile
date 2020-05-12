.DEFAULT_GOAL := deploy

export NAME        ?= dev
export BASE_DOMAIN ?= cloud-account-name.superhub.io

STATE_BUCKET ?= agilestacks.cloud-account-name.superhub.io
STATE_REGION ?= us-east-2

STACK_NAME ?= happy-meal

ELABORATE_FILE_FS := hub.yaml.elaborate
ELABORATE_FILE_S3 := s3://$(STATE_BUCKET)/$(NAME).$(BASE_DOMAIN)/hub/$(STACK_NAME)/hub.elaborate
ELABORATE_FILES   := $(ELABORATE_FILE_FS),$(ELABORATE_FILE_S3)
STATE_FILE_FS     := hub.yaml.state
STATE_FILE_S3     := s3://$(STATE_BUCKET)/$(NAME).$(BASE_DOMAIN)/hub/$(STACK_NAME)/hub.state
STATE_FILES       := $(STATE_FILE_FS),$(STATE_FILE_S3)

TEMPLATE_PARAMS ?= params/template.yaml
STACK_PARAMS    ?= params/$(NAME).$(BASE_DOMAIN).yaml

COMPONENT :=
VERB :=

RESTORE_BUNDLE_FILE ?= restore-bundles/$(NAME).$(BASE_DOMAIN).yaml
RESTORE_PARAMS_FILE ?= restore-params.yaml

HUB_OPTS ?=

hub ?= hub -d --aws_region $(STATE_REGION)
aws ?= aws --region $(STATE_REGION)

ifdef HUB_TOKEN
ifdef HUB_ENVIRONMENT
ifdef HUB_STACK_INSTANCE
HUB_LIFECYCLE_OPTS ?= --hub-environment "$(HUB_ENVIRONMENT)" --hub-stack-instance "$(HUB_STACK_INSTANCE)" \
	--hub-sync --hub-sync-skip-parameters-and-oplog
endif
endif
endif

ifeq (,$(wildcard $(RESTORE_BUNDLE_FILE)))
$(RESTORE_PARAMS_FILE):
	@echo --- > $(RESTORE_PARAMS_FILE)
else
$(RESTORE_PARAMS_FILE): $(RESTORE_BUNDLE_FILE)
	$(hub) backup unbundle $(RESTORE_BUNDLE_FILE) -o $(RESTORE_PARAMS_FILE)
endif

$(ELABORATE_FILE_FS): hub.yaml $(TEMPLATE_PARAMS) $(STACK_PARAMS) $(RESTORE_PARAMS_FILE) params/user.yaml cloud.yaml k8s.yaml
	$(hub) elaborate \
		hub.yaml cloud.yaml k8s.yaml $(TEMPLATE_PARAMS) $(STACK_PARAMS) $(RESTORE_PARAMS_FILE) params/user.yaml \
		$(HUB_OPTS) \
		-o $(ELABORATE_FILES)

elaborate:
	-rm -f $(ELABORATE_FILE_FS)
	$(MAKE) $(ELABORATE_FILE_FS)
.PHONY: elaborate

pull:
	$(hub) pull hub.yaml
.PHONY: pull

explain:
	$(hub) explain $(ELABORATE_FILES) $(STATE_FILES) $(HUB_OPTS) --color -r | less -R
.PHONY: explain

kubeconfig:
	$(hub) kubeconfig --switch-kube-context $(HUB_OPTS) $(STATE_FILES)
.PHONY: kubeconfig

COMPONENT_LIST := $(if $(COMPONENT),-c $(COMPONENT),)

deploy: $(ELABORATE_FILE_FS)
	$(hub) deploy $(ELABORATE_FILES) -s $(STATE_FILES) $(HUB_LIFECYCLE_OPTS) $(HUB_OPTS) \
		$(COMPONENT_LIST)
.PHONY: deploy

undeploy: $(ELABORATE_FILE_FS)
	$(hub) --force undeploy $(ELABORATE_FILES) -s $(STATE_FILES) $(HUB_LIFECYCLE_OPTS) $(HUB_OPTS) \
		$(COMPONENT_LIST)
.PHONY: undeploy

sync:
	$(hub) api instance sync $(NAME).$(BASE_DOMAIN) -s $(STATE_FILES) $(HUB_OPTS)
.PHONY: sync

ifneq ($(COMPONENT),)
invoke: $(ELABORATE_FILE_FS)
	$(eval , := ,)
	$(eval WORDS := $(subst $(,), ,$(COMPONENT)))
	@$(foreach c,$(WORDS), \
		$(hub) invoke $(c) $(VERB) -m $(ELABORATE_FILES) -s $(STATE_FILES) $(HUB_OPTS);)
.PHONY: invoke
endif

backup: $(ELABORATE_FILE_FS)
	$(hub) backup create --json $(ELABORATE_FILES) -s $(STATE_FILES) -o "$(BACKUP_BUNDLE_FILE)" -c "$(COMPONENTS)"
	@echo '--- backup bundle'
	@zcat $(BACKUP_BUNDLE_FILE)
	@echo
.PHONY: backup

remove_s3_state:
	-$(aws) s3 rm $(STATE_FILE_S3)
.PHONY: remove_s3_state

clean: remove_s3_state
	@rm -f hub.yaml.state hub.yaml.elaborate
.PHONY: clean

toolbox:
	$(SHELL) bin/toolbox
.PHONY: toolbox
