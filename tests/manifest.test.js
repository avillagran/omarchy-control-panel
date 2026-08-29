const assert = require("assert")
const fs = require("fs")
const path = require("path")

const projectDir = path.join(__dirname, "..")
const manifest = JSON.parse(fs.readFileSync(path.join(projectDir, "manifest.json"), "utf8"))

assert.strictEqual(manifest.schemaVersion, 1)
assert.match(manifest.id, /^[a-z0-9]+(?:[.-][a-z0-9]+)+$/)
assert.match(manifest.version, /^\d+\.\d+\.\d+$/)
assert.ok(Array.isArray(manifest.kinds) && manifest.kinds.length > 0)
assert.ok(manifest.entryPoints && typeof manifest.entryPoints === "object")

const entryPointKeys = { "bar-widget": "barWidget" }
for (const kind of manifest.kinds) {
  const entryPoint = manifest.entryPoints[entryPointKeys[kind] || kind]
  assert.strictEqual(typeof entryPoint, "string", `missing entry point for ${kind}`)
  assert.ok(!path.isAbsolute(entryPoint) && !entryPoint.split(path.sep).includes(".."), `unsafe entry point for ${kind}`)
  assert.ok(fs.existsSync(path.join(projectDir, entryPoint)), `entry point does not exist for ${kind}`)
}

assert.ok(["left", "center", "right"].includes(manifest.barWidget.defaultSection))

// A display helper is shipped for the Displays tab; the manifest directory must
// contain an executable bin/display-manager.
const helper = path.join(projectDir, "bin", "display-manager")
assert.ok(fs.existsSync(helper), "bin/display-manager must exist")
assert.ok(fs.statSync(helper).mode & 0o100, "bin/display-manager must be executable")

console.log("manifest tests passed")
