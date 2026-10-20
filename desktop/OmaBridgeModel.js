.pragma library

// OmaBridge manages itself through `omabridge manage` (bin/omabridge-client);
// this panel is one front end among several. These helpers only shape requests
// and responses; OmaBridge validates everything again.

var ACTIONS = ["identity-create", "invite", "invite-discard", "pair", "pair-retry",
               "pair-discard", "approve", "revoke", "publish", "unpublish", "relay-set", "rename"]

var ERROR_KEYS = {
    omabridge_missing: "omabridgeErrorMissing",
    omabridge_outdated: "omabridgeErrorOutdated",
    invalid_command: "omabridgeErrorOutdated",
    invalid_action: "omabridgeErrorOutdated",
    confirmation_required: "omabridgeErrorConfirmation",
    local_error: "omabridgeErrorLocal",
    omabridge_identity_missing: "omabridgeErrorIdentityMissing",
    omabridge_not_published: "omabridgeErrorNotPublished",
    omabridge_service_not_published: "omabridgeErrorServiceNotPublished",
    omabridge_ssh_unavailable: "omabridgeErrorSshUnavailable",
    omabridge_t3_unavailable: "omabridgeErrorT3Unavailable",
    omabridge_nothing_to_publish: "omabridgeErrorNothingToPublish",
    omabridge_already_running: "omabridgeErrorAlreadyRunning",
    omabridge_unit_foreign: "omabridgeErrorUnitForeign",
    omabridge_path_unsupported: "omabridgeErrorPathUnsupported",
    omabridge_publish_failed: "omabridgeErrorPublishFailed",
    omabridge_invite_directory: "omabridgeErrorInviteDirectory",
    omabridge_invite_unreadable: "omabridgeErrorInviteInvalid",
    omabridge_invite_invalid: "omabridgeErrorInviteInvalid",
    omabridge_invite_expired: "omabridgeErrorInviteExpired",
    omabridge_pair_denied: "omabridgeErrorPairDenied",
    omabridge_peer_unreachable: "omabridgeErrorPeerUnreachable",
    omabridge_peer_not_found: "omabridgeErrorPeerNotFound",
    omabridge_request_changed: "omabridgeErrorRequestChanged",
    omabridge_command_failed: "omabridgeErrorCommandFailed",
    omabridge_relay_invalid: "omabridgeErrorRelayInvalid",
    omabridge_name_invalid: "omabridgeErrorNameInvalid",
    timeout: "omabridgeErrorTimeout",
    failed_start: "omabridgeErrorFailedStart",
    invalid_response: "omabridgeErrorInvalidResponse"
}

// From an action, `invalid_command` means OmaBridge rejected the request; the
// helper reports a binary without `manage` as `omabridge_outdated`.
function errorKey(code, fromAction) {
    if (fromAction && (code === "invalid_command" || code === "invalid_action"))
        return "omabridgeErrorInvalidRequest"
    return ERROR_KEYS[code] || "omabridgeErrorGeneric"
}

// QML hands model lists back as array-like sequences, not JS arrays.
function _list(value) {
    if (Array.isArray(value)) return value
    if (value && typeof value === "object" && typeof value.length === "number")
        return Array.prototype.slice.call(value)
    return []
}

function _text(value) {
    return typeof value === "string" ? value : ""
}

// Only the fields the page shows. `created` (the invitation path and QR) is a
// secret and is returned separately so it never lands in the stored snapshot.
function normalize(raw) {
    var published = raw && typeof raw.published === "object" && raw.published ? raw.published : {}
    var device = raw && raw.device && typeof raw.device === "object" ? raw.device : null
    var relay = raw && typeof raw.relay === "object" && raw.relay ? raw.relay : {}
    var relayMode = ["public", "custom", "none"].indexOf(relay.mode) >= 0 ? relay.mode : "public"
    return {
        available: raw.available === true,
        version: _text(raw.version),
        device: device ? { id: _text(device.id), name: _text(device.name) } : null,
        peers: _list(raw.peers).map(function(p) {
            return { id: _text(p.id), name: _text(p.name), services: _list(p.services), remoteServices: _list(p.remoteServices) }
        }),
        pending: _list(raw.pending).map(function(p) {
            return { id: _text(p.id), name: _text(p.name), services: _list(p.services), expires: p.expires }
        }),
        awaiting: _list(raw.awaiting).map(function(p) {
            return { id: _text(p.id), name: _text(p.name), expires: p.expires }
        }),
        published: {
            enabled: published.enabled === true,
            active: published.active === true,
            external: published.external === true,
            stale: published.stale === true,
            sshAvailable: published.sshAvailable === true,
            t3Available: published.t3Available === true,
            services: _list(published.services)
        },
        relay: { mode: relayMode, url: relayMode === "custom" ? _text(relay.url) : "" },
        error: _text(raw.error)
    }
}

function parseResponse(text, exitCode) {
    var raw
    try {
        raw = JSON.parse(String(text || "").trim())
    } catch (e) {
        return { ok: false, error: exitCode === 124 || exitCode === 137 ? "timeout" : "invalid_response" }
    }
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return { ok: false, error: "invalid_response" }
    if (exitCode !== 0 || typeof raw.error === "string" && raw.available === undefined)
        return { ok: false, error: _text(raw.error) || "invalid_response" }
    var created = raw.created && typeof raw.created === "object" ? {
        path: _text(raw.created.path),
        expires: raw.created.expires,
        services: _list(raw.created.services),
        qrImage: /^data:image\/svg\+xml[;,]/.test(_text(raw.created.qrImage)) ? raw.created.qrImage : ""
    } : null
    var paired = raw.paired && typeof raw.paired === "object" ? {
        status: _text(raw.paired.status), name: _text(raw.paired.name), id: _text(raw.paired.id)
    } : null
    return { ok: true, error: "", snapshot: normalize(raw), created: created, paired: paired }
}

// Page state from the last read: OmaBridge missing, too old for `manage`,
// unavailable, or ready to manage.
function stateFor(result) {
    if (!result) return "loading"
    if (!result.ok) {
        if (result.error === "omabridge_missing") return "missing"
        if (result.error === "omabridge_outdated" || result.error === "invalid_command" || result.error === "invalid_action") return "outdated"
        return "failed"
    }
    return result.snapshot.available ? "ready" : "unavailable"
}

function readRequest() {
    return { action: "read" }
}

// Exchanges names and addresses with paired devices; changes no trust, so it
// needs no confirmation.
function syncRequest() {
    return { action: "sync" }
}

// `confirmed:true` is only ever added here, and the page only calls this from
// the confirm button of a dialog the user has just seen.
function confirmedRequest(action, values) {
    if (ACTIONS.indexOf(action) < 0) return null
    var request = { action: action }
    for (var key in values || {})
        if (key !== "action" && key !== "confirmed") request[key] = values[key]
    request.confirmed = true
    return request
}

function inviteValues(published, shareT3, shareSsh, qr) {
    var services = _list(published && published.services)
    var wanted = []
    if (shareT3 && services.indexOf("t3") >= 0) wanted.push("t3")
    if (shareSsh && services.indexOf("ssh") >= 0) wanted.push("ssh")
    return { services: wanted, qr: qr === true }
}

function serviceLabel(service) {
    return service === "t3" ? "T3" : (service === "ssh" ? "SSH" : String(service))
}

function servicesText(list) {
    return _list(list).map(serviceLabel).join(", ")
}

function shortId(id) {
    return _text(id).slice(0, 8)
}

// The services a publish request offers, limited to what can be served now.
function publishValues(published, shareT3, shareSsh) {
    return {
        t3: shareT3 === true && !!published && published.t3Available === true,
        ssh: shareSsh === true && !!published && published.sshAvailable === true
    }
}

// `public` (n0's relays), `none` or the custom HTTPS URL; OmaBridge validates it again.
function relayValues(mode, url) {
    if (mode === "custom") return { relay: String(url || "").trim() }
    return { relay: mode === "none" ? "none" : "public" }
}

function relayValid(mode, url) {
    return mode !== "custom" || /^https:\/\/[^\s\/]+/.test(String(url || "").trim())
}

function relayStatusKey(relay) {
    if (relay && relay.mode === "custom") return "omabridgeRelayCustom"
    if (relay && relay.mode === "none") return "omabridgeRelayNone"
    return "omabridgeRelayPublic"
}

// Same rule as OmaBridge: 1–80 characters, no control characters.
function nameValid(name) {
    var text = String(name || "").trim()
    return text.length > 0 && text.length <= 80 && !/[\u0000-\u001f\u007f-\u009f]/.test(text)
}

function renameValues(name) {
    return { name: String(name || "").trim() }
}

// "service": the running service tells paired devices; otherwise how many answered.
function renamedStatus(renamed) {
    if (renamed && renamed.via === "direct")
        return { key: "omabridgeRenamedDirect", reached: renamed.reached || 0, total: renamed.total || 0 }
    return { key: "omabridgeRenamedService", reached: 0, total: 0 }
}

function publishStatusKey(published) {
    if (published && published.external && !published.enabled) return "omabridgePublishExternal"
    if (!published || !published.enabled) return "omabridgePublishOff"
    if (published.stale) return "omabridgePublishStale"
    if (!published.active) return "omabridgePublishInactive"
    return "omabridgePublishOn"
}

function localPath(url) {
    return decodeURIComponent(String(url || "").replace(/^file:\/\//, ""))
}
