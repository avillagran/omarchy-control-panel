.pragma library

function wizardCanContinue(step, form) {
    if (step === 0) return (form.intent === "backup" || form.intent === "restore") && ["local", "smb", "timecapsule", "sftp"].indexOf(form.destinationKind) >= 0;
    if (step === 1) return form.verified === true && destinationValid(form.destination, form.destinationKind);
    if (step === 2 && form.intent === "backup") return form.configurations === true || form.files === true;
    if (step === 2 && form.intent === "restore") return !!form.snapshot && absolutePath(form.target) && (!form.encrypted || absolutePath(form.identityFile));
    return false;
}

function safeRecoveryKey(path, destination) {
    var base = (destination || "").replace(/\/+$/, "");
    return absolutePath(path) && /\.key$/.test(path) && path !== base && path.indexOf(base + "/") !== 0;
}

function connectionErrorKey(reason) {
    if (reason === "not_connected" || reason === "mount_check_failed") return "backupNoMounts";
    if (reason === "invalid_device" || reason === "mount_failed") return "backupMountFailed";
    if (reason === "missing_tool") return "backupConnectionMissing";
    if (reason === "destination_inside_home" || reason === "destination_contains_home") return "backupDiskHelp";
    if (reason === "directory_missing" || reason === "invalid_path" || reason === "symlink_path") return "backupChooseFolderError";
    if (reason === "host_required" || reason === "invalid_host") return "backupHostError";
    return "backupConnectionFailed";
}

function absolutePath(value) {
    return typeof value === "string" && value.charAt(0) === "/" && value.indexOf("\0") < 0 && value.split("/").indexOf("..") < 0;
}

function timeCapsuleDestination(value) {
    if (!value || typeof value !== "object" || value.savedCredential !== true) return false;
    return ["host", "address", "mac", "user", "share"].every(function(key) {
        return typeof value[key] === "string" && value[key].length > 0;
    });
}

function destinationValid(value, transport) {
    return transport === "timecapsule" ? timeCapsuleDestination(value) : absolutePath(value);
}

function validate(request, action) {
    if (action === "capabilities") return "";
    if (!request.destination) return "backupChooseDestination";
    if (request.transport === "timecapsule") {
        if (!timeCapsuleDestination(request.destination)) return "backupTimeCapsuleCredentialRequired";
        if ((action === "plan" || action === "backup") && request.encrypted !== true) return "backupTimeCapsuleEncryptionRequired";
    }
    if (request.transport === "sftp") {
        if (!/^[A-Za-z0-9_][A-Za-z0-9_-]*:[A-Za-z0-9_./ -]+$/.test(request.destination) || !relativePath(request.destination.split(":")[1]) || /^[./]+$/.test(request.destination.split(":")[1])) return "backupRemoteDestination";
    } else if (request.transport !== "timecapsule" && !absolutePath(request.destination)) return "backupAbsoluteDestination";
    if (action === "plan" || action === "backup") {
        if (!request.configurations && !request.files) return "backupChooseScope";
        if (request.encrypted && !/^age1[0-9a-z]{58}$/.test(request.ageRecipient || "")) return "backupChooseRecipient";
        if (request.files && request.paths && (!Array.isArray(request.paths) || !request.paths.length || !request.paths.every(relativePath))) return "backupRelativePaths";
    }
    if (action === "restore") {
        if (!request.snapshot || !absolutePath(request.target)) return "backupChooseRestore";
        if (request.encrypted && !absolutePath(request.identityFile)) return "backupChooseIdentity";
    }
    return "";
}

function relativePath(value) {
    return typeof value === "string" && value.length > 0 && value.charAt(0) !== "/" && value.indexOf("\0") < 0 && value.split("/").indexOf("..") < 0;
}

// Deliberate allowlist: credentials and unrelated form state never reach stdin.
function request(form, action) {
    if (action === "capabilities") return {};
    var destination = form.destination || "";
    if (form.transport === "timecapsule" && timeCapsuleDestination(destination)) {
        destination = {host: destination.host, address: destination.address, mac: destination.mac, user: destination.user, share: destination.share, savedCredential: true};
    }
    var result = {destination: destination, transport: form.transport || "local", configurations: false, files: false, encrypted: false};
    if (action === "plan" || action === "backup") {
        result.configurations = form.configurations === true;
        result.files = form.files === true;
        result.encrypted = form.encrypted === true;
        if (result.files) {
            var paths = (form.pathsText || "").split(/\r?\n/).filter(function(p) { return p.length > 0; });
            result.paths = paths.length ? paths : ["."];
        }
        if (result.encrypted) result.ageRecipient = form.ageRecipient || "";
    } else if (action === "restore") {
        result.snapshot = form.snapshot || "";
        result.target = form.target || "";
        result.encrypted = form.encrypted === true;
        if (result.encrypted) result.identityFile = form.identityFile || "";
    }
    return result;
}

function parseResponse(text, exitCode) {
    try {
        var result = JSON.parse(text);
        if (!result || typeof result.ok !== "boolean") throw new Error("Invalid response");
        if (exitCode !== 0 && result.ok) return {ok: false, error: "Helper exited with code " + exitCode};
        return result;
    } catch (e) {
        return {ok: false, error: "Invalid helper JSON (exit " + exitCode + ")"};
    }
}

function canConfirm(plan, plannedRequest, currentRequest) {
    return !!plan && plan.ok === true && Array.isArray(plan.missing) && plan.missing.length === 0 && JSON.stringify(plannedRequest) === JSON.stringify(currentRequest);
}

function connectionStage(host, opened, hasFolders, verified) {
    if (verified) return "ready";
    if (hasFolders) return "folder";
    if (opened) return "authenticate";
    return host ? "connect" : "discover";
}
