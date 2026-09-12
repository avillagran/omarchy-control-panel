.pragma library

function _text(value) {
    return value === undefined || value === null ? "" : String(value).trim()
}

function _protocol(value) {
    var p = _text(value).toLowerCase().replace(/^_/, "").replace(/\._tcp.*$/, "")
    if (p === "ssh" || p === "sftp-ssh") return "sftp"
    if (p === "time-capsule" || p === "time_capsule" || p === "time capsule") return "timecapsule"
    return p
}

function protocolsFor(device) {
    var input = device && (device.services || device.protocols) || []
    var result = []
    for (var i = 0; i < input.length; i++) {
        var service = input[i]
        var protocol = ""
        if (typeof service === "string") protocol = _protocol(service)
        else if (service && service.advertised !== false && service.probed !== false && service.available !== false)
            protocol = _protocol(service.protocol || service.service || service.type || service.name)
        if (["smb", "afp", "sftp", "timecapsule"].indexOf(protocol) >= 0 && result.indexOf(protocol) < 0)
            result.push(protocol)
    }
    var probes = device && device.connection && device.connection.protocols || {}
    for (var key in probes) {
        if (probes[key] && probes[key].open === true) {
            var probed = _protocol(key)
            if (["smb", "afp", "sftp"].indexOf(probed) >= 0 && result.indexOf(probed) < 0) result.push(probed)
        }
    }
    return result
}

function _addresses(device) {
    var values = []
    if (Array.isArray(device.addresses)) values = values.concat(device.addresses)
    if (device.ip) values.push(device.ip)
    if (device.address) values.push(device.address)
    var result = []
    for (var i = 0; i < values.length; i++) {
        var value = _text(values[i])
        if (value && result.indexOf(value) < 0) result.push(value)
    }
    return result
}

function _verifiedMounts(device) {
    var mounts = Array.isArray(device.mounts) ? device.mounts : []
    return mounts.filter(function(mount) { return mount && mount.verified === true })
}

function _key(device) {
    var addresses = _addresses(device)
    return addresses.length ? "ip:" + addresses[0] : "host:" + _text(device.hostname || device.host || device.name).toLowerCase()
}

function _merge(target, source) {
    var addresses = _addresses(source)
    for (var i = 0; i < addresses.length; i++)
        if (target.addresses.indexOf(addresses[i]) < 0) target.addresses.push(addresses[i])
    var protocols = protocolsFor(source)
    for (var j = 0; j < protocols.length; j++)
        if (target.protocols.indexOf(protocols[j]) < 0) target.protocols.push(protocols[j])
    var mounts = _verifiedMounts(source)
    for (var k = 0; k < mounts.length; k++) target.mounts.push(mounts[k])
    var sourceName = _text(source.resolvedName || source.displayName || source.name)
    if (sourceName && (!target.resolvedName || target.resolvedName === target.ip)) target.resolvedName = sourceName
    if (!target.hostname) target.hostname = _text(source.hostname || source.host)
    if (!target.kind) target.kind = _text(source.kind)
    var serviceNames = Array.isArray(source.services) ? source.services.map(function(service) { return _protocol(typeof service === "string" ? service : service.protocol) }) : []
    if (source.timeCapsule === true || _protocol(source.kind) === "timecapsule" || serviceNames.indexOf("timemachine") >= 0 || serviceNames.indexOf("airport") >= 0) target.timeCapsule = true
    if (source.legacySmb === true || (source.compatibility && source.compatibility.legacySmb === true) || (source.connection && source.connection.legacySmb === true)) target.legacySmb = true
    if (source.protocolAccessible === true && source.selectedDestination) {
        target.protocolAccessible = true
        target.authenticated = source.authenticated === true
        target.selectedShare = _text(source.selectedShare || source.selectedDestination.share)
        target.selectedDestination = source.selectedDestination
    }
    if (!target.backendDevice) target.backendDevice = source.backendDevice || source
}

function normalizeDevices(input) {
    var grouped = []
    var keys = {}
    input = Array.isArray(input) ? input : []
    for (var i = 0; i < input.length; i++) {
        var source = input[i]
        if (!source || typeof source !== "object") continue
        var key = _key(source)
        if (key === "host:") continue
        var index = keys[key]
        if (index === undefined) {
            var addresses = _addresses(source)
            var host = _text(source.hostname || source.host)
            var name = _text(source.resolvedName || source.displayName || source.name)
            var device = {
                id: key,
                name: name || addresses[0] || host,
                resolvedName: name,
                hostname: host,
                ip: addresses[0] || "",
                addresses: [],
                kind: "",
                protocols: [],
                services: [],
                mounts: [],
                connected: false,
                protocolAccessible: false,
                authenticated: false,
                selectedShare: "",
                selectedDestination: null,
                timeCapsule: false,
                legacySmb: false,
                backendDevice: null
            }
            grouped.push(device)
            index = grouped.length - 1
            keys[key] = index
        }
        _merge(grouped[index], source)
        var aliases = _addresses(source)
        for (var a = 0; a < aliases.length; a++) keys["ip:" + aliases[a]] = index
        var sourceHost = _text(source.hostname || source.host).toLowerCase()
        if (sourceHost) keys["host:" + sourceHost] = index
    }
    for (var n = 0; n < grouped.length; n++) {
        var item = grouped[n]
        item.ip = item.addresses[0] || item.ip
        item.name = item.resolvedName || item.ip || item.hostname
        item.services = item.protocols.slice()
        item.timeCapsule = item.timeCapsule || item.protocols.indexOf("timecapsule") >= 0 || _protocol(item.kind) === "timecapsule"
        item.connected = item.mounts.length > 0
    }
    return grouped
}

function mergeMounts(devices, mounts) {
    var result = normalizeDevices(devices)
    mounts = Array.isArray(mounts) ? mounts : []
    for (var i = 0; i < mounts.length; i++) {
        var mount = mounts[i]
        if (!mount || mount.verified !== true) continue
        var host = _text(mount.ip || mount.address || mount.host || mount.hostname).toLowerCase()
        for (var j = 0; j < result.length; j++) {
            var device = result[j]
            if (host && (device.ip.toLowerCase() === host || device.hostname.toLowerCase() === host || device.addresses.map(function(value) { return value.toLowerCase() }).indexOf(host) >= 0)) {
                device.mounts.push(mount)
                device.connected = true
            }
        }
    }
    return result
}

function _parse(text, exitCode) {
    var data
    try { data = JSON.parse(String(text || "")) }
    catch (error) { return { ok: false, error: "Invalid backend response" } }
    if (!data || typeof data !== "object") return { ok: false, error: "Invalid backend response" }
    if (exitCode !== 0 || data.ok === false) return { ok: false, error: _text(data.error || data.reason) || "Network device helper failed" }
    data.ok = true
    return data
}

function parseScan(text, exitCode) {
    var result = _parse(text, exitCode)
    if (!result.ok) return { ok: false, error: result.error, devices: [] }
    return { ok: true, error: "", devices: normalizeDevices(result.devices || result.neighbors || []) }
}

function parseMounts(text, exitCode) {
    var result = _parse(text, exitCode)
    if (!result.ok) return { ok: false, error: result.error, mounts: [] }
    var mounts = Array.isArray(result.mounts) ? result.mounts.filter(function(mount) { return mount && typeof mount === "object" }).map(function(mount) {
        var copy = {}
        for (var key in mount) copy[key] = mount[key]
        copy.verified = true
        return copy
    }) : []
    return { ok: true, error: "", mounts: mounts }
}

function _timeCapsuleTarget(device) {
    var raw = device && device.backendDevice || device || {}
    var connection = raw.connection || {}
    var addresses = _addresses(raw)
    var preferred = _text(connection.preferredAddress || device && device.ip || addresses[0])
    var host = _text(raw.host || raw.hostname || device && device.hostname)
    var mac = _text(raw.mac || device && device.mac).toUpperCase().replace(/-/g, ":")
    return { host: host, address: preferred, mac: mac }
}

function timeCapsuleRequest(device, user, share, savedCredential) {
    var request = _timeCapsuleTarget(device)
    request.user = _text(user)
    share = _text(share)
    if (share) request.share = share
    if (savedCredential === true) request.savedCredential = true
    return request
}

function timeCapsuleCommand(helperPath, action) {
    return [_text(helperPath), _text(action)]
}

function parseTimeCapsuleCapabilities(text, exitCode) {
    var result = _parse(text, exitCode)
    if (!result.ok) return { ok: false, smbclient: false, secretService: false }
    return { ok: true, smbclient: result.smbclient === true, secretService: result.secretService === true }
}

function parseTimeCapsuleShares(text, exitCode) {
    var result = _parse(text, exitCode)
    if (!result.ok || result.connected !== true || result.mounted !== false)
        return { ok: false, shares: [] }
    var shares = Array.isArray(result.shares) ? result.shares.filter(function(share) {
        return share && typeof share === "object" && _text(share.name)
    }).map(function(share) {
        return { name: _text(share.name), comment: _text(share.comment) }
    }) : []
    return { ok: true, shares: shares }
}

function parseTimeCapsuleVerify(text, exitCode) {
    var result = _parse(text, exitCode)
    if (!result.ok || result.connected !== true || result.mounted !== false || !_text(result.share))
        return { ok: false, accessible: false, share: "" }
    return { ok: true, accessible: true, share: _text(result.share) }
}

function parseTimeCapsuleMutation(text, exitCode, field) {
    var result = _parse(text, exitCode)
    return { ok: result.ok === true && result[field] === true }
}

function withTimeCapsuleDestination(device, user, share, savedCredential) {
    var copy = {}
    for (var key in device) copy[key] = device[key]
    var request = timeCapsuleRequest(device, user, share, false)
    copy.connected = device && device.connected === true
    copy.protocolAccessible = true
    copy.authenticated = true
    copy.selectedShare = request.share
    copy.selectedDestination = {
        kind: "timecapsule",
        protocol: "smb1",
        host: request.host,
        address: request.address,
        mac: request.mac,
        user: request.user,
        share: request.share,
        authenticated: true,
        available: true,
        mounted: false
    }
    if (savedCredential === true) copy.selectedDestination.savedCredential = true
    return copy
}

function protocolLabel(protocol) {
    protocol = _protocol(protocol)
    if (protocol === "smb") return "SMB"
    if (protocol === "afp") return "AFP"
    if (protocol === "sftp") return "SFTP"
    if (protocol === "timecapsule") return "Time Capsule"
    return protocol.toUpperCase()
}
