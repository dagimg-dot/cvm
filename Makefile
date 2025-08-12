bump-version:
	@echo "Bumping version to $(VERSION)"
	@sed -i 's/CVM_VERSION=".*"/CVM_VERSION="$(VERSION)"/' cvm.sh
	@echo "CVM version bumped to $(VERSION)"

release:
	@echo "Releasing version $(VERSION)"
	@git tag v$(VERSION)
	@git push origin v$(VERSION)
	@echo "cvm version v$(VERSION) released"
