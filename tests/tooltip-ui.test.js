const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.join(__dirname, '..');
const core = fs.readFileSync(path.join(root, 'desktop/Core.qml'), 'utf8');
const catalogs = ['i18n.json', 'desktop/i18n.json'].map(p =>
  JSON.parse(fs.readFileSync(path.join(root, p), 'utf8')));
const keys = ['tooltipAppearance', 'tooltipShape', 'tooltipShapeTheme', 'tooltipShapeSquare',
  'tooltipShapeRounded', 'tooltipBorder', 'tooltipBorderTheme', 'tooltipBorderTransparent',
  'tooltipBorderCustom', 'tooltipDefine', 'tooltipBorderColor', 'tooltipThemeHint',
  'tooltipUnavailable', 'tooltipInvalidColor', 'tooltipInvalidFile', 'tooltipWriteFailed'];
for (const catalog of catalogs)
  for (const [lang, strings] of Object.entries(catalog))
    for (const key of keys) {
      assert.ok(strings[key], `${lang}.${key} missing`);
      if (lang !== 'en' && ['tooltipInvalidColor', 'tooltipWriteFailed'].includes(key))
        assert.notEqual(strings[key], catalog.en[key], `${lang}.${key} must be translated`);
    }
assert.match(core, /visible: root.currentTab === 1[\s\S]*?tooltipAppearance[\s\S]*?tooltipShape[\s\S]*?tooltipBorder/);
assert.match(core, /root\.binDir \+ "\/tooltip-settings"/);
assert.match(core, /\["python3", root\.tooltipHelperPath, "get"\]/);
assert.match(core, /\["python3", root\.tooltipHelperPath, "set", field, value\]/);
assert.match(core, /onCurrentTabChanged: if \(currentTab === 1\) readTooltips\(\)/);
assert.match(core, /function setTooltip\(field, value\) \{[\s\S]*?\^#\[0-9a-fA-F\]\{6\}\$/);
assert.match(core, /selected: root\.tooltipShape === modelData/);
assert.match(core, /selected: root\.tooltipBorderMode === modelData/);
assert.match(core, /enabled: root\.tooltipAvailable && root\.tooltipLoaded && !root\.tooltipBusy/);
assert.match(core, /onClicked: root\.setTooltip\("borderColor", tooltipColorInput\.text\)/);
assert.match(core, /visible: root\.tooltipLoaded && !root\.tooltipAvailable/);
assert.ok(core.indexOf('text: root.t(root.uiLang, "tooltipAppearance")') > core.lastIndexOf('label: root.t(root.uiLang, "nightLight")'), 'tooltip preferences must be the final Windows section');
const tooltipPath = core.indexOf('readonly property string tooltipHelperPath:');
const tooltipEnd = core.indexOf('// APFS (Extras):', tooltipPath);
assert.ok(tooltipPath !== -1 && tooltipEnd !== -1);
assert.doesNotMatch(core.slice(tooltipPath, tooltipEnd), /writeLua\(|hyprSet\(|hyprctl|savePrefs\(/,
  'tooltip setters must not regenerate Hyprland configuration');
console.log('Tooltip UI/catalog contract tests passed');
