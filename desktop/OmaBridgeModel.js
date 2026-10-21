.pragma library

// OmaBridge manages itself through `omabridge manage` (bin/omabridge-client);
// this panel is one front end among several. These helpers only shape requests
// and responses; OmaBridge validates everything again.

var ACTIONS = ["identity-create", "invite", "invite-discard", "pair", "pair-retry",
               "pair-discard", "approve", "revoke", "publish", "unpublish", "relay-set", "rename",
               "admin-set", "remote", "relay-host", "gateway-set", "grant-set"]

// What a managing device may ask a managed one; OmaBridge enforces the same list there.
var REMOTE_ACTIONS = ["read", "rename", "relay-set", "publish", "unpublish", "revoke", "approve", "relay-host", "gateway-set"]

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
    omabridge_manage_consent_required: "omabridgeErrorConsentRequired",
    omabridge_not_managed: "omabridgeErrorNotManaged",
    omabridge_not_admin: "omabridgeErrorNotAdmin",
    omabridge_remote_forbidden: "omabridgeErrorRemoteForbidden",
    omabridge_peer_is_admin: "omabridgeErrorPeerIsAdmin",
    omabridge_remote_unsupported: "omabridgeErrorRemoteUnsupported",
    omabridge_remote_failed: "omabridgeErrorGeneric",
    omabridge_relay_host_unavailable: "omabridgeErrorRelayHostUnavailable",
    omabridge_relay_certificate: "omabridgeErrorRelayCertificate",
    omabridge_service_not_granted: "omabridgeErrorServiceNotGranted",
    omabridge_port_unavailable: "omabridgeErrorPortUnavailable",
    omabridge_gateway_host_invalid: "omabridgeErrorGatewayHost",
    omabridge_invite_changed: "omabridgeErrorInviteChanged",
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
        features: _list(raw.features).map(_text),
        device: device ? { id: _text(device.id), name: _text(device.name) } : null,
        peers: _list(raw.peers).map(function(p) {
            return { id: _text(p.id), name: _text(p.name), services: _list(p.services), remoteServices: _list(p.remoteServices),
                     public: _list(p.public), admin: p.admin === true, managed: p.managed === true }
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
        relayHost: (function(host) {
            host = host && typeof host === "object" ? host : {}
            return { enabled: host.enabled === true, url: _text(host.url), running: host.running === true,
                     error: _text(host.error), suggested: _text(host.suggested) }
        })(raw.relayHost),
        gateways: _list(raw.gateways).map(function(g) {
            return { peer: _text(g.peer), name: _text(g.name), service: _text(g.service), url: _text(g.url),
                     running: g.running === true, error: _text(g.error) }
        }),
        gatewayZones: _list(raw.gatewayZones).map(_text).filter(function(z) { return z !== "" }),
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
        status: _text(raw.paired.status), name: _text(raw.paired.name), id: _text(raw.paired.id), admin: raw.paired.admin === true
    } : null
    var invitation = raw.invitation && typeof raw.invitation === "object" ? {
        name: _text(raw.invitation.name), expires: raw.invitation.expires, manage: raw.invitation.manage === true,
        id: _text(raw.invitation.id)
    } : null
    var outcome = function(value) {
        return value && typeof value === "object" ? {
            via: _text(value.via), reached: Number(value.reached) || 0, total: Number(value.total) || 0
        } : null
    }
    return {
        ok: true, error: "", snapshot: normalize(raw), created: created, paired: paired, invitation: invitation,
        renamed: outcome(raw.renamed), synced: outcome(raw.synced),
        gatewayCheck: raw.gatewayCheck && typeof raw.gatewayCheck === "object" ? {
            reachable: raw.gatewayCheck.reachable === true,
            sameEnvironment: raw.gatewayCheck.sameEnvironment === true ? true : raw.gatewayCheck.sameEnvironment === false ? false : null
        } : null,
        remote: raw.remote && typeof raw.remote === "object" ? normalize(raw.remote) : null
    }
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

// The invite dialog's "ask to manage" option.
function inviteManageValues(values, manage) {
    var out = {}
    for (var key in values) out[key] = values[key]
    if (manage === true) out.manage = true
    return out
}

// Reading an invitation file is unconfirmed: it only shows what accepting means.
function inspectRequest(path) {
    return { action: "invite-inspect", path: String(path || "") }
}

// Pairing values; `allowManage` only when the invitation asked, as OmaBridge requires.
// `expect` is the inviting device the user was shown, so a file swapped since is refused.
function pairValues(path, invitation, allowManage) {
    var values = { path: String(path || "") }
    if (invitation && invitation.id) values.expect = invitation.id
    if (invitation && invitation.manage) values.allowManage = allowManage === true
    return values
}

// Reading a managed device needs no confirmation; changes go through confirmedRequest.
function remoteReadRequest(peer) {
    return { action: "remote", peer: String(peer || ""), command: { action: "read" } }
}

function remoteValues(peer, command) {
    if (!command || REMOTE_ACTIONS.indexOf(command.action) < 0) return null
    return { peer: String(peer || ""), command: command }
}

// Peers a managing device may revoke: never one that manages the device.
function remoteRevocable(peer) {
    return !!peer && !peer.admin
}

// What the peer row says about management, both ways.
function manageText(peer, t) {
    var parts = []
    if (peer && peer.admin) parts.push(t("omabridgeManagesThis"))
    if (peer && peer.managed) parts.push(t("omabridgeYouManage"))
    return parts.join(" · ")
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

// The private relay a device hosts for the devices paired with it.
function relayHostStatusKey(host) {
    if (!host || !host.enabled) return "omabridgeHostOff"
    if (host.running) return "omabridgeHostRunning"
    if (host.error === "certificate") return "omabridgeHostCertificate"
    if (host.error === "port") return "omabridgeHostPort"
    if (host.error) return "omabridgeHostFailed"
    return "omabridgeHostStarting"
}

// Moving to a hosted relay: every device this one manages, then this one,
// whose own server restarts last.
function relayEverywhereRequests(url, peers) {
    var requests = []
    _list(peers).forEach(function(peer) {
        if (peer && peer.managed)
            requests.push(confirmedRequest("remote", { peer: peer.id, command: { action: "relay-set", relay: url } }))
    })
    requests.push(confirmedRequest("relay-set", { relay: url }))
    return requests
}

// A DNS label from a device name: "MBP M2" becomes "mbp-m2".
function hostLabel(name) {
    return String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 63)
}

// The SSH command that reaches a paired device granting ssh through
// `omabridge connect`: by its name when no other paired device has it and it
// is safe to paste in a shell, otherwise by its ID. Empty when this device's
// OmaBridge cannot connect over stdio.
function sshCommand(peer, peers, features) {
    if (!peer || _list(features).indexOf("connect-stdio") < 0 || _list(peer.remoteServices).indexOf("ssh") < 0)
        return ""
    var name = _text(peer.name)
    var unique = _list(peers).filter(function(p) {
        return _text(p.name).toLowerCase() === name.toLowerCase()
    }).length === 1
    var safe = /^[A-Za-z0-9][A-Za-z0-9._-]*$/
    var target = unique && safe.test(name) ? name : _text(peer.id)
    if (!safe.test(target))
        return ""
    return "ssh -o ProxyCommand='omabridge connect --peer " + target + " --service ssh' " + target
}

// The public name proposed for a device: its own subdomain when the gateway
// holds a wildcard certificate, otherwise none (the gateway's name and a port).
function gatewayHostSuggestion(name, zones) {
    var label = hostLabel(name)
    var list = _list(zones)
    return label && list.length ? label + "." + list[0] : ""
}

function validHost(host) {
    var text = String(host || "").trim().toLowerCase()
    return text === "" || /^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(text)
}

// This device's gateway on another device, if any.
function gatewayFor(gateways, deviceId, service) {
    return _list(gateways).filter(function(g) { return g.peer === deviceId && g.service === service })[0] || null
}

// Exposing this device's T3 through a paired device: grant it t3 here, with
// consent to expose it publicly, then open the gateway there. `services` and
// `exposed` are what that device may reach and expose today.
function exposeRequests(gatewayPeer, services, deviceId, host, exposed) {
    var granted = _list(services).slice()
    if (granted.indexOf("t3") < 0) granted.push("t3")
    var publicList = _list(exposed).filter(function(s) { return granted.indexOf(s) >= 0 })
    if (publicList.indexOf("t3") < 0) publicList.push("t3")
    var command = { action: "gateway-set", peer: deviceId, service: "t3", enabled: true }
    var name = String(host || "").trim().toLowerCase()
    if (name) command.host = name
    return [confirmedRequest("grant-set", { peer: gatewayPeer, services: granted, public: publicList }),
            confirmedRequest("remote", { peer: gatewayPeer, command: command })]
}

// Closing it: the gateway goes away there and the grant here.
function concealRequests(gatewayPeer, services, deviceId, exposed) {
    var remaining = _list(services).filter(function(s) { return s !== "t3" })
    return [confirmedRequest("remote", { peer: gatewayPeer, command: { action: "gateway-set", peer: deviceId, service: "t3", enabled: false } }),
            confirmedRequest("grant-set", { peer: gatewayPeer, services: remaining,
                                            public: _list(exposed).filter(function(s) { return s !== "t3" && remaining.indexOf(s) >= 0 }) })]
}

function gatewayCheckRequest(url) {
    return { action: "gateway-check", url: String(url || "") }
}

function gatewayCheckKey(check) {
    if (!check || !check.reachable) return "omabridgeGatewayUnreachable"
    if (check.sameEnvironment === false) return "omabridgeGatewayOtherT3"
    return "omabridgeGatewayReady"
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
