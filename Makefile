.PHONY: help install-vault start-vault stop-vault status-vault run-rulebook run-rulebook-bg stop-rulebook test-events clean setup-env compile-deps build-collection publish-collection release-collection start-eda-server stop-eda-server status-eda-server logs-eda-server clean-eda-server create-eda-activation

# Default target
help:
	@echo "Available targets:"
	@echo "  setup-env        - Set up environment and install dependencies"
	@echo "  compile-deps     - Compile requirements.in to requirements.txt"
	@echo "  start-vault      - Start Vault in dev mode"
	@echo "  stop-vault       - Stop Vault server"
	@echo "  status-vault     - Check Vault server status"
	@echo "  run-rulebook     - Run the Vault EDA rulebook (foreground)"
	@echo "  run-rulebook-bg  - Run the Vault EDA rulebook (background)"
	@echo "  stop-rulebook    - Stop background rulebook"
	@echo "  test-events      - Generate test events to trigger rulebook"
	@echo "  clean            - Stop Vault and clean up"
	@echo "  build-collection - Build the Ansible collection"
	@echo "  publish-collection - Publish collection to Ansible Galaxy"
	@echo "  release-collection - Build and publish collection"
	@echo ""
	@echo "EDA Server (Optional UI):"
	@echo "  start-eda-server     - Start EDA Server with UI (requires Docker)"
	@echo "  create-eda-activation - Create activation via API (visible in UI)"
	@echo "  stop-eda-server      - Stop EDA Server"
	@echo "  status-eda-server    - Check EDA Server status"
	@echo "  logs-eda-server      - View EDA Server logs"
	@echo "  clean-eda-server     - Stop and remove all EDA Server data"
	@echo ""
	@echo "Environment Variables:"
	@echo "  VAULT_ADDR       - Vault server URL (default: http://127.0.0.1:8200)"
	@echo "  VAULT_TOKEN      - Vault authentication token (default: myroot)"
	@echo ""
	@echo "Quick start (CLI only):"
	@echo "  export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=myroot"
	@echo "  make compile-deps && make setup-env && make start-vault && make run-rulebook-bg && make test-events"
	@echo ""
	@echo "Quick start (with UI):"
	@echo "  export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=myroot"
	@echo "  make start-vault && make start-eda-server"
	@echo "  Access UI at: https://localhost:8443 (default credentials: admin/testpass)"

# Set up Python environment and dependencies
setup-env:
	@echo "Setting up environment..."
	python3 -m venv .venv
	source .venv/bin/activate && pip install -r requirements.txt
	@echo "Environment setup complete!"

# Compile requirements.in to requirements.txt using pip-compile
compile-deps:
	@echo "Compiling requirements.in to requirements.txt..."
	@if [ ! -d ".venv" ]; then \
		echo "Virtual environment not found. Creating one..."; \
		python3 -m venv .venv; \
	fi
	@source .venv/bin/activate && \
	pip install --upgrade pip pip-tools && \
	pip-compile --output-file=requirements.txt requirements.in
	@echo "Dependencies compiled successfully!"

# Start Vault in dev mode
start-vault:
	@echo "Starting Vault in dev mode..."
	@if pgrep -f "vault server" > /dev/null; then \
		echo "Vault is already running"; \
	else \
		vault server -dev -dev-root-token-id=myroot -dev-listen-address=127.0.0.1:8200 > vault.log 2>&1 & \
		echo $$! > vault.pid; \
		sleep 3; \
		echo "Vault started with PID $$(cat vault.pid)"; \
		echo "Root token: myroot"; \
		echo "Vault Address: http://127.0.0.1:8200"; \
		export VAULT_ADDR=http://127.0.0.1:8200; \
		export VAULT_TOKEN=myroot; \
		vault kv put secret/test data=hello || true; \
		echo "Vault is ready!"; \
	fi

# Stop Vault server
stop-vault:
	@echo "Stopping Vault server..."
	@if [ -f vault.pid ]; then \
		kill $$(cat vault.pid) 2>/dev/null || true; \
		rm -f vault.pid; \
		echo "Vault stopped"; \
	else \
		pkill -f "vault server" || true; \
		echo "Vault process killed"; \
	fi

# Check Vault status
status-vault:
	@if pgrep -f "vault server" > /dev/null; then \
		echo "Vault is running"; \
		export VAULT_ADDR=http://127.0.0.1:8200; \
		export VAULT_TOKEN=myroot; \
		vault status || true; \
	else \
		echo "Vault is not running"; \
	fi

# Run the rulebook in background
run-rulebook-bg:
	@echo "Starting Vault EDA rulebook in background..."
	@if pgrep -f "ansible-rulebook" > /dev/null; then \
		echo "Rulebook is already running"; \
	else \
		export PATH="/opt/homebrew/opt/openjdk/bin:$$PATH" && \
		export JAVA_HOME="/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home" && \
		export DYLD_LIBRARY_PATH="$$JAVA_HOME/lib/server:$$DYLD_LIBRARY_PATH" && \
		export VAULT_ADDR=$${VAULT_ADDR:-http://127.0.0.1:8200} && \
		export VAULT_TOKEN=$${VAULT_TOKEN:-myroot} && \
		source .venv/bin/activate && \
		ansible-rulebook -i inventory.yml -r rulebooks/vault-eda-rulebook.yaml --env-vars VAULT_ADDR,VAULT_TOKEN --verbose > rulebook.log 2>&1 & \
		echo $$! > rulebook.pid; \
		sleep 3; \
		echo "Rulebook started with PID $$(cat rulebook.pid)"; \
		echo "Logs: tail -f rulebook.log"; \
	fi

# Stop background rulebook
stop-rulebook:
	@echo "Stopping rulebook..."
	@if [ -f rulebook.pid ]; then \
		kill $$(cat rulebook.pid) 2>/dev/null || true; \
		rm -f rulebook.pid; \
		echo "Rulebook stopped"; \
	else \
		pkill -f "ansible-rulebook" || true; \
		echo "Rulebook process killed"; \
	fi

# Generate test events
test-events:
	@echo "Generating test events..."
	@./scripts/generate-vault-events.sh

# Clean up everything
clean: stop-vault stop-rulebook
	@echo "Cleaning up..."
	@rm -rf .venv/
	@rm -f vault.log vault.pid rulebook.log rulebook.pid
	@echo "Cleanup complete!"

# Development workflow
dev: setup-env start-vault
	@echo "Development environment ready!"
	@echo "In another terminal, run: make run-rulebook"
	@echo "To generate events, run: make test-events"

# Collection build and release targets
build-collection:
	@echo "Building Ansible collection..."
	@cd collections/ansible_collections/gitrgoliveira/vault_eda && \
	rm -f gitrgoliveira-vault_eda-*.tar.gz && \
	ansible-galaxy collection build
	@echo "Collection built successfully!"

publish-collection:
	@echo "Publishing collection to Ansible Galaxy..."
	@if [ -z "$(GALAXY_API_KEY)" ]; then \
		echo "Error: GALAXY_API_KEY environment variable not set"; \
		echo "Get your API key from: https://galaxy.ansible.com/me/preferences"; \
		echo "Then run: export GALAXY_API_KEY=your_api_key_here"; \
		exit 1; \
	fi
	@cd collections/ansible_collections/gitrgoliveira/vault_eda && \
	COLLECTION_FILE=$$(ls gitrgoliveira-vault_eda-*.tar.gz 2>/dev/null | head -1) && \
	if [ -z "$$COLLECTION_FILE" ]; then \
		echo "Error: No collection file found. Run 'make build-collection' first."; \
		exit 1; \
	fi && \
	echo "Publishing $$COLLECTION_FILE..." && \
	ansible-galaxy collection publish $$COLLECTION_FILE --api-key $(GALAXY_API_KEY)
	@echo "Collection published successfully!"

release-collection: build-collection publish-collection
	@echo "Collection release complete!"

# EDA Server targets (optional UI)
start-eda-server:
	@echo "Starting EDA Server with UI..."
	@if ! command -v docker > /dev/null 2>&1; then \
		echo "Error: Docker is required but not installed."; \
		echo "Please install Docker Desktop: https://www.docker.com/products/docker-desktop"; \
		exit 1; \
	fi
	@./scripts/setup-eda-nginx.sh
	@export VAULT_ADDR=$${VAULT_ADDR:-http://host.docker.internal:8200} && \
	export VAULT_TOKEN=$${VAULT_TOKEN:-myroot} && \
	docker compose up -d
	@echo ""
	@echo "EDA Server starting..."
	@echo "This may take a few minutes on first run (downloading images)."
	@echo "Waiting for services to be ready..."
	@for i in 1 2 3 4 5 6; do \
		if docker compose exec -T eda-api curl -s http://localhost:8000/_healthz > /dev/null 2>&1; then \
			break; \
		fi; \
		echo "  Waiting for API ($$i/6)..."; \
		sleep 5; \
	done
	@echo "Setting up admin user..."
	@docker compose exec -T eda-api bash -c "echo \"from django.contrib.auth import get_user_model; User = get_user_model(); u, created = User.objects.get_or_create(username='admin', defaults={'email': 'admin@test.com', 'is_superuser': True}); u.set_password('testpass'); u.is_superuser = True; u.save(); print('Admin user configured')\" | aap-eda-manage shell" 2>&1 | grep -q "Admin user configured" && echo "  Admin user ready" || echo "  Note: Run 'make status-eda-server' to check if services are ready"
	@echo ""
	@echo "Services:"
	@echo "  - EDA UI:  https://localhost:8443"
	@echo "  - EDA API: http://localhost:8000"
	@echo ""
	@echo "Default credentials: admin / testpass"
	@echo ""
	@echo "Check status with: make status-eda-server"
	@echo "View logs with:    make logs-eda-server"

stop-eda-server:
	@echo "Stopping EDA Server..."
	@docker compose down
	@echo "EDA Server stopped"

status-eda-server:
	@echo "EDA Server status:"
	@docker compose ps

logs-eda-server:
	@docker compose logs -f

clean-eda-server:
	@echo "Stopping and removing all EDA Server data..."
	@docker compose down -v
	@echo "EDA Server cleaned up (all data removed)"

create-eda-activation:
	@echo "Creating EDA activation via API..."
	@if ! docker compose ps | grep -q "eda-api.*Up"; then \
		echo "Error: EDA Server is not running."; \
		echo "Start it with: make start-eda-server"; \
		exit 1; \
	fi
	@./scripts/create-eda-activation.sh
