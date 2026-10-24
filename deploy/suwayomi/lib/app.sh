#!/bin/bash
# Release download, unpack, systemd user unit and extension store. Sourced by
# install.sh after common.sh.

# Download the pinned tarball into the cache (once) and check its sha256.
fetch_release() {
	local tarball="${CACHE_DIR}/${SUWAYOMI_TARBALL}"
	mkdir -p "${CACHE_DIR}"
	if [[ -f ${tarball} ]] && sha256sum --status -c <<<"${SUWAYOMI_SHA256}  ${tarball}"; then
		ok "release ${SUWAYOMI_VERSION} already cached"
		return 0
	fi
	log "downloading ${SUWAYOMI_RELEASE_URL}"
	curl -fsSL --retry 3 -o "${tarball}.part" "${SUWAYOMI_RELEASE_URL}"
	sha256sum --status -c <<<"${SUWAYOMI_SHA256}  ${tarball}.part" ||
		die "sha256 mismatch for ${SUWAYOMI_TARBALL} -- refusing to install it"
	mv "${tarball}.part" "${tarball}"
	ok "downloaded and verified ${SUWAYOMI_TARBALL}"
}

# Unpack bin/ + jre/ (the bundled JRE is the dependency; the Electron shell is
# a desktop UI this server never uses, so it is not extracted).
# Sets APP_CHANGED=1 when the active version moved.
install_release() {
	APP_CHANGED=0
	mkdir -p "${APP_ROOT}"
	chmod 700 "${SUWAYOMI_HOME}"
	if [[ ! -x ${APP_DIR}/jre/bin/java || ! -f ${APP_DIR}/bin/Suwayomi-Server.jar ]]; then
		local staging
		staging="$(mktemp -d "${APP_ROOT}/.staging.XXXXXX")"
		if ! tar -xzf "${CACHE_DIR}/${SUWAYOMI_TARBALL}" -C "${staging}" \
			--strip-components=1 --exclude='*/electron' ||
			[[ ! -x ${staging}/jre/bin/java ]]; then
			rm -rf "${staging}"
			die "could not unpack bin/ + jre/ from ${SUWAYOMI_TARBALL}"
		fi
		rm -rf "${APP_DIR}"
		mv "${staging}" "${APP_DIR}"
		ok "unpacked ${SUWAYOMI_VERSION} into ${APP_DIR}"
	fi
	if [[ "$(readlink "${APP_ROOT}/current" 2>/dev/null || true)" != "${SUWAYOMI_VERSION}" ]]; then
		ln -sfn "${SUWAYOMI_VERSION}" "${APP_ROOT}/current"
		APP_CHANGED=1
		ok "current -> ${SUWAYOMI_VERSION}"
	fi
	mkdir -p "${DATA_DIR}"
	chmod 700 "${DATA_DIR}"
}

# Install the unit (only when it differs), enable it, and (re)start it when
# the unit or the release changed. Linger is required so it survives logout
# and the nightly lightdm stop; the host already has it.
install_unit() {
	local src="${SCRIPT_DIR}/${UNIT_NAME}" dst="${UNIT_DIR}/${UNIT_NAME}" changed=0
	[[ "$(loginctl show-user "${USER}" -p Linger --value 2>/dev/null)" == "yes" ]] ||
		die "linger is off for ${USER}; the unit would die at logout. Run: sudo loginctl enable-linger ${USER}"
	mkdir -p "${UNIT_DIR}"
	if ! cmp -s "${src}" "${dst}"; then
		install -m 0644 "${src}" "${dst}"
		systemctl --user daemon-reload
		changed=1
		ok "installed ${dst}"
	fi
	systemctl --user enable "${UNIT_NAME}" >/dev/null 2>&1
	if ((changed || APP_CHANGED)) || ! systemctl --user is-active --quiet "${UNIT_NAME}"; then
		log "restarting ${UNIT_NAME}"
		systemctl --user restart "${UNIT_NAME}"
	else
		ok "${UNIT_NAME} already running the current release"
	fi
}

# Bounded wait (<= 30 s) for the loopback API; keeps every call under the cap.
wait_ready() {
	local i
	for ((i = 0; i < 15; i++)); do
		if local_gql '{ aboutServer { version } }' 2>/dev/null | grep -q "\"${SUWAYOMI_VERSION}\""; then
			ok "GraphQL answering on ${SUWAYOMI_LOCAL} (${SUWAYOMI_VERSION})"
			return 0
		fi
		sleep 2
	done
	die "server not answering after 30 s -- journalctl --user -u ${UNIT_NAME} | tail"
}

# Add the Keiyoushi store through the API (Suwayomi rewrites server.conf, so
# editing the list in the file by hand does not survive a restart cleanly).
ensure_store() {
	if local_gql '{ extensionStores { nodes { indexUrl } } }' | grep -qF "\"${KEIYOUSHI_INDEX}\""; then
		ok "Keiyoushi extension store configured"
		return 0
	fi
	local out
	out="$(local_gql "mutation { addExtensionStore(input: {indexUrl: \"${KEIYOUSHI_INDEX}\"}) { clientMutationId } }")"
	jq -e '.errors == null' <<<"${out}" >/dev/null || die "addExtensionStore failed: ${out}"
	ok "added Keiyoushi extension store"
}
