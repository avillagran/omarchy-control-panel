const fs = require("fs")
const vm = require("vm")
const assert = require("assert")
const path = require("path")

const source = fs.readFileSync(path.join(__dirname, "../ThemePalette.js"), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const context = { String, Array, Object }
vm.createContext(context)
vm.runInContext(source, context)

const first = context.parse('accent = "#112233"\nred = "#aa0000"\ngreen = "#00aa00"\n')
const second = context.parse('accent = "#445566"\nred = "#bb0000"\ngreen = "#00bb00"\n')
assert.strictEqual(context.resolve("accent", first), "#112233")
assert.strictEqual(context.resolve("red", first), "#aa0000")
assert.strictEqual(context.resolve("red", second), "#bb0000")
assert.strictEqual(context.resolve("missing", first), "#112233")
assert.ok(context.roles.includes("orange"))
console.log("ThemePalette tests passed")
