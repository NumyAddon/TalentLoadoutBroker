local addonName, ns = ...;

--- @type TalentLoadoutBroker
local TLB = ns.TLB;
ns.Config = ns.Config or {};

local Config = ns.Config;

Config.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "";

function Config:GetOptions()
    local orderCount = CreateCounter(1);
    local defaultFormat = TLB.defaults.textFormat;

    local options = {
        type = 'group',
        get = function(info) return self:GetConfig(info[#info]); end,
        set = function(info, value) self:SetConfig(info[#info], value); end,
        args = {
            version = {
                order = orderCount(),
                type = "description",
                name = "Version: " .. self.version,
            },
            textFormat = {
                order = orderCount(),
                type = "input",
                name = "Text Format",
                desc = "The format of the text to display on the broker bar.",
                descStyle = "inline",
                width = "full",
            },
            textFormatDescription = {
                order = orderCount(),
                type = "description",
                name = [[
The following placeholders are available:
    - %loadoutName%: The name of the current loadout.
    - %specIcon%: The icon of the current spec.
    - %specName%: The name of the current spec.
    - %lootspecIcon%: The icon of the current loot spec.
    - %lootspecName%: The name of the current loot spec.
    - %lootspecIcon2%: The icon of the current loot spec (but hidden if lootspec = current spec).
    - %lootspecName2%: The name of the current loot spec (but hidden if lootspec = current spec).
    - %switching%: When switching spec or loadout, contains "switching ".
]],
            },
            resetTextFormat = {
                order = orderCount(),
                type = "execute",
                name = "Reset Text Format",
                desc = "Reset the text format to the default.",
                descStyle = "inline",
                width = "full",
                func = function() self:SetConfig("textFormat", defaultFormat); end,
            },
        },
    }

    return options
end

function Config:Initialize()
    self:RegisterOptions();
    local _, categoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, addonName);
    self.categoryID = categoryID;
end

function Config:RegisterOptions()
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, self:GetOptions());
end

function Config:OpenConfig()
    if C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel and InCombatLockdown() then
        LibStub("AceConfigDialog-3.0"):Open(addonName);
        return;
    end
    Settings.OpenToCategory(self.categoryID);
end

function Config:GetConfig(property)
    return TLB.db[property];
end

function Config:SetConfig(property, value)
    TLB.db[property] = value;
    if property == "textFormat" then
        TLB:SetText();
    end
end
