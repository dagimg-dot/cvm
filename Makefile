.PHONY: bump-version release bump-and-release
bump-version:
	@echo "Bumping version to $(VERSION)"
	@sed -i 's/CVM_VERSION=".*"/CVM_VERSION="$(VERSION)"/' cvm.sh
	@sed -i 's|/releases/download/v[^/]*/cvm.sh|/releases/download/v$(VERSION)/cvm.sh|g' README.md
	@git add cvm.sh README.md
	@git commit -m "Bump version to $(VERSION)"
	@git push
	@echo "CVM version bumped to $(VERSION)"

release:
	@echo "Releasing version $(VERSION)"
	@git tag v$(VERSION)
	@git push origin v$(VERSION)
	@echo "cvm version v$(VERSION) released"

bump-and-release: bump-version release
