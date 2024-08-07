local addonName, ns = ...;
ns.TLB = {};

--- @class TalentLoadoutBroker
local TLB = ns.TLB;

--- @type LibUIDropDownMenuNumy
local LibDD = LibStub('LibUIDropDownMenuNumy-4.0');
local starterConfigID = Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID;

function TLB:Init()
    EventUtil.ContinueOnAddOnLoaded(addonName, function()
        TalentLoadoutBrokerDB = TalentLoadoutBrokerDB or {};
        self.db = TalentLoadoutBrokerDB;
        self.defaults = {
            textFormat = '%switching%%specIcon%%specName%||%loadoutName%',
        };
        for k, v in pairs(self.defaults) do
            if self.db[k] == nil then
                self.db[k] = v;
            end
        end
        if self.db.textFormat == '%switching%%specIcon%%specName%|%loadoutName%' then
            self.db.textFormat = self.defaults.textFormat;
        end

        ns.Config:Initialize();
        SLASH_TALENT_LOADOUT_BROKER1 = '/tlb';
        SLASH_TALENT_LOADOUT_BROKER2 = '/talentloadoutbroker';
        SlashCmdList['TALENT_LOADOUT_BROKER'] = function() ns.Config:OpenConfig(); end
    end);

    self.dropDown = LibDD:Create_UIDropDownMenu(nil, UIParent);
    self.dropDown:Hide();

    self.menuListDefaults = {
        loadout = {
            { text = 'Loadouts', isTitle = true, notCheckable = true },
        },
        spec = {
            { text = SPECIALIZATION, isTitle = true, notCheckable = true },
        },
        lootSpec = {
            { text = SELECT_LOOT_SPECIALIZATION, isTitle = true, notCheckable = true },
        },
    };
    self.menuList = Mixin({}, self.menuListDefaults);
    self.configIDs, self.configIDToName, self.currentConfigID = nil, nil, nil;
    self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil;
    self.currentConfigID = nil;

    self.TalentLoadoutLDB = LibStub('LibDataBroker-1.1'):NewDataObject(
        'Talent Loadout',
        {
            type = 'data source',
            text = 'Talent Loadout',
            OnClick = function(brokerFrame, button)
                TLB:OnButtonClick(brokerFrame, button);
            end,
            OnTooltipShow = function(tooltip)
                TLB:OnTooltipShow(tooltip);
            end,
        }
    );
    self:RefreshMenuListLoadouts();

    self.eventFrame = CreateFrame('Frame');
    self.eventFrame:RegisterEvent('TRAIT_CONFIG_UPDATED');
    self.eventFrame:RegisterEvent('CONFIG_COMMIT_FAILED');
    self.eventFrame:RegisterEvent('ACTIVE_PLAYER_SPECIALIZATION_CHANGED');
    self.eventFrame:RegisterEvent('SPECIALIZATION_CHANGE_CAST_FAILED');
    self.eventFrame:RegisterEvent('PLAYER_LOOT_SPEC_UPDATED');
    self.eventFrame:RegisterEvent('SPELLS_CHANGED');
    self.eventFrame:SetScript('OnEvent', function(_, event, ...)
        self[event](self, ...);
    end)
    self.ignoreHook = false;
    hooksecurefunc(C_ClassTalents, 'UpdateLastSelectedSavedConfigID', function()
        if self.ignoreHook then return; end
        self:RefreshMenuListLoadouts();
    end)
end

function TLB:OnTooltipShow(tooltip)
    tooltip:AddLine('Talent Loadout');
    tooltip:AddLine('|cffeda55fClick|r to switch loadouts');
    tooltip:AddLine('|cffeda55fRight-Click|r to switch specs or lootspecs');
    tooltip:AddLine('|cffeda55fShift + Click|r to open talent frame');
    tooltip:AddLine('|cffeda55fShift + Right-Click|r to open config');
end

function TLB:OnButtonClick(brokerFrame, button)
    if button == 'LeftButton' then
        if IsShiftKeyDown() then
            ToggleTalentFrame();
        else
            self:ToggleLoadoutDropDown(brokerFrame);
        end
    elseif button == 'RightButton' then
        if IsShiftKeyDown() then
            ns.Config:OpenConfig();
        else
            self:ToggleSpecDropDown(brokerFrame);
        end
    end
end

function TLB:ToggleLoadoutDropDown(brokerFrame)
    self:RefreshMenuListLoadouts();
    LibDD:ToggleDropDownMenu(1, nil, self.dropDown, brokerFrame, 0, 0, self.menuList.loadout);
end

function TLB:ToggleSpecDropDown(brokerFrame)
    self:RefreshMenuListSpecs();
    LibDD:ToggleDropDownMenu(1, nil, self.dropDown, brokerFrame, 0, 0, self.menuList.spec);
end

function TLB:SetTextLoadout(loadoutName)
    self:SetText(loadoutName);
end

function TLB:SetTextSpec(name, icon)
    self:SetText(nil, name, icon);
end

function TLB:SetTextLootSpec(name, icon)
    self:SetText(nil, nil, nil, nil, name, icon);
end

function TLB:SetTextIsSwitching(isSwitching)
    self:SetText(nil, nil, nil, isSwitching);
end

function TLB:SetText(loadoutName, specName, specIcon, isSwitching, lootSpecName, lootSpecIcon)
    --[[
    The following placeholders are available:
        - %loadoutName%: The name of the current loadout.
        - %specIcon%: The icon of the current spec.
        - %specName%: The name of the current spec.
        - %lootspecIcon%: The icon of the current loot spec.
        - %lootspecName%: The name of the current loot spec.
        - %lootspecIcon2%: The icon of the current loot spec (but hidden if lootspec = current spec).
        - %lootspecName2%: The name of the current loot spec (but hidden if lootspec = current spec).
        - %switching%: When switching spec or loadout, contains "switching ".
    --]]
    self.displayLoadoutName = loadoutName or self.displayLoadoutName;
    self.displaySpecName = specName or self.displaySpecName;
    self.displaySpecIcon = specIcon or self.displaySpecIcon;
    self.displayLootSpecName = lootSpecName or self.displayLootSpecName;
    self.displayLootSpecIcon = lootSpecIcon or self.displayLootSpecIcon;
    if isSwitching ~= nil then self.displayIsSwitching = isSwitching; end

    local text = self.db.textFormat;
    local placeholderList = {
        ['%loadoutName%'] = '%%loadoutName%%',
        ['%specIcon%'] = '%%specIcon%%',
        ['%specName%'] = '%%specName%%',
        ['%lootspecIcon%'] = '%%lootspecIcon%%',
        ['%lootspecName%'] = '%%lootspecName%%',
        ['%lootspecIcon2%'] = '%%lootspecIcon2%%',
        ['%lootspecName2%'] = '%%lootspecName2%%',
        ['%switching%'] = '%%switching%%',
    };
    local placeholderReplacements = {
        ['%loadoutName%'] = self.displayLoadoutName,
        ['%specIcon%'] = self.displaySpecIcon and string.format('|T%s:16:16:0:0:64:64:4:60:4:60|t', self.displaySpecIcon),
        ['%specName%'] = self.displaySpecName,
        ['%lootspecIcon%'] = self.displayLootSpecIcon and string.format('|T%s:16:16:0:0:64:64:4:60:4:60|t', self.displayLootSpecIcon),
        ['%lootspecName%'] = self.displayLootSpecName,
        ['%lootspecIcon2%'] = self.displayLootSpecIcon and (self.displayLootSpecName ~= self.displaySpecName) and string.format('|T%s:16:16:0:0:64:64:4:60:4:60|t', self.displayLootSpecIcon),
        ['%lootspecName2%'] = self.displayLootSpecName ~= self.displaySpecName and self.displayLootSpecName,
        ['%switching%'] = self.displayIsSwitching and DIM_GREEN_FONT_COLOR:WrapTextInColorCode('switching '),
    };
    for placeholder, gsubSafePlaceholder in pairs(placeholderList) do
        local replacement = placeholderReplacements[placeholder] or '';
        text = string.gsub(text, gsubSafePlaceholder, replacement);
    end

    self.TalentLoadoutLDB.text = text;
end

function TLB:FormatSpecText(name, icon)
    return string.format('|T%s:14:14:0:0:64:64:4:60:4:60|t  %s', icon, name );
end

function TLB:RefreshMenuListLoadouts()
    local specID = PlayerUtil.GetCurrentSpecID();
    if not specID then return; end

    if not TalentLoadoutManagerAPI then
        self.currentConfigID =
            C_ClassTalents.GetLastSelectedSavedConfigID(specID)
            or (C_ClassTalents.GetStarterBuildActive() and starterConfigID);
        self.configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID);

        self.configIDToName = {};
        for _, configID in ipairs(self.configIDs) do
            local configInfo = C_Traits.GetConfigInfo(configID);
            self.configIDToName[configID] = (configInfo and configInfo.name) or '';
        end

        if not self.currentConfigID then
            table.insert(self.configIDs, 0);
            self.configIDToName[0] = LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(TALENT_FRAME_DROP_DOWN_DEFAULT);
        end

        -- If spec has a starter build, add Starter Build as a dropdown option
        if C_ClassTalents.GetHasStarterBuild() then
            table.insert(self.configIDs, starterConfigID);
            self.configIDToName[starterConfigID] = BLUE_FONT_COLOR:WrapTextInColorCode(TALENT_FRAME_DROP_DOWN_STARTER_BUILD);
        end

        self.menuList.loadout = Mixin({}, self.menuListDefaults.loadout);
        local function onClick(_, configID, configName) self:SelectLoadout(configID, configName);  end
        for configID, configName in pairs(self.configIDToName) do
            local checked =
                (not self.updatePending and configID == 0 and self.currentConfigID == nil)
                or (self.updatePending and self.pendingConfigID == configID)
                or (not self.updatePending and self.currentConfigID == configID);
            table.insert(self.menuList.loadout, {
                text = configName,
                arg1 = configID,
                arg2 = configName,
                func = onClick,
                checked = checked,
                notClickable = self.updatePending or checked,
            });
            if checked then self:SetTextLoadout(configName); end
        end
    else
        local API = TalentLoadoutManagerAPI;

        self.menuList.loadout = Mixin({}, self.menuListDefaults.loadout);
        local function onClick(_, loadoutID) API.CharacterAPI:LoadLoadout(loadoutID, true); end
        local activeLoadoutID = API.CharacterAPI:GetActiveLoadoutID();
        if C_ClassTalents.GetActiveConfigID() == activeLoadoutID then
            self:SetTextLoadout(LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(TALENT_FRAME_DROP_DOWN_DEFAULT));
        end
        local loadouts = {};
        for _, loadoutInfo in ipairs(API.GlobalAPI:GetLoadouts()) do
            local checked = loadoutInfo.id == activeLoadoutID;
            loadoutInfo.parentID = loadoutInfo.parentMapping and loadoutInfo.parentMapping[0];
            table.insert(loadouts, {
                text = loadoutInfo.parentID and ('  ||  '..loadoutInfo.displayName) or loadoutInfo.displayName,
                id = loadoutInfo.id,
                checked = checked,
                data = loadoutInfo,
                parentID = loadoutInfo.parentID,
            });
            if checked then self:SetTextLoadout(loadoutInfo.displayName); end
        end
        self:SortTLMLoadouts(loadouts);
        for _, info in ipairs(loadouts) do
            table.insert(self.menuList.loadout, {
                text = info.text,
                arg1 = info.id,
                func = onClick,
                checked = info.checked,
                notClickable = self.updatePending or info.checked,
            });
        end
    end
    LibDD:EasyMenu(self.menuList.loadout, self.dropDown, self.dropDown, 0, 0);
end

function TLB:SortTLMLoadouts(loadouts)
    --- order by:
    --- 1. playerIsOwner
    --- 2. isBlizzardLoadout
    --- 3. name (todo: make this optional?)
    --- 4. id (basically, the order they were created?)
    ---
    --- custom loadouts are listed underneath their parent, if any

    local function compare(a, b)
        if not b then
            return false;
        end

        if a.data.playerIsOwner and not b.data.playerIsOwner then
            return true;
        elseif not a.data.playerIsOwner and b.data.playerIsOwner then
            return false;
        end

        if a.data.isBlizzardLoadout and not b.data.isBlizzardLoadout then
            return true;
        elseif not a.data.isBlizzardLoadout and b.data.isBlizzardLoadout then
            return false;
        end

        if a.data.displayName < b.data.displayName then
            return true;
        elseif a.data.displayName > b.data.displayName then
            return false;
        end

        if a.data.id < b.data.id then
            return true;
        elseif a.data.id > b.data.id then
            return false;
        end

        return false;
    end

    local elements = CopyTable(loadouts);

    table.sort(elements, compare);
    local lookup = {};
    for index, element in ipairs(elements) do
        element.order = index;
        element.subOrder = 0;
        lookup[element.data.id] = element;
    end

    for index, element in ipairs(elements) do
        local parentIndex = element.parentID and lookup[element.parentID] and lookup[element.parentID].order;
        if parentIndex then
            element.order = parentIndex;
            element.subOrder = index;
        end
    end

    table.sort(loadouts, function(a, b)
        if not b then
            return false;
        end
        a = lookup[a.data.id];
        b = lookup[b.data.id];

        if a.order == b.order then
            return a.subOrder < b.subOrder;
        end
        return a.order < b.order;
    end);
end

function TLB:RefreshMenuListSpecs()
    local activeSpecIndex = GetSpecialization();
    if not activeSpecIndex then return; end

    do --- spec selection
        local function onClick(_, specIndex) self:SelectSpec(specIndex); end
        local function isChecked(data) return activeSpecIndex == data.arg1; end

        local numSpecs = GetNumSpecializationsForClassID(PlayerUtil.GetClassID())
        self.menuList.spec = Mixin({}, self.menuListDefaults.spec);
        for i = 1, numSpecs do
            local _, name, _, icon = GetSpecializationInfoForClassID(PlayerUtil.GetClassID(), i);
            table.insert(self.menuList.spec, {
                text = self:FormatSpecText(name, icon),
                arg1 = i,
                func = onClick,
                checked = isChecked,
                notClickable = i == activeSpecIndex,
            });
            if i == activeSpecIndex then self:SetTextSpec(name, icon); end
        end
    end

    do --- lootspec selection
        local numSpecs = GetNumSpecializationsForClassID(PlayerUtil.GetClassID());
        local activeLootSpec = GetLootSpecialization();
        for _, item in pairs(self.menuListDefaults.lootSpec) do
            table.insert(self.menuList.spec, item);
        end

        local function onClick(_, specId) TLB:SelectLootSpec(specId); end
        local function isChecked(data) return activeLootSpec == data.arg1; end
        table.insert(self.menuList.spec, {
            text = string.format(LOOT_SPECIALIZATION_DEFAULT, select(2, GetSpecializationInfo(GetSpecialization()))),
            arg1 = 0,
            func = onClick,
            checked = isChecked,
            notClickable = activeLootSpec == 0,
        });
        for i = 1, numSpecs do
            local specId, name, _, icon = GetSpecializationInfoForClassID(PlayerUtil.GetClassID(), i);
            table.insert(self.menuList.spec, {
                text = self:FormatSpecText(name, icon),
                arg1 = specId,
                func = onClick,
                checked = isChecked,
                notClickable = activeLootSpec == specId,
            });
            if
                specId == activeLootSpec
                or (activeLootSpec == 0 and i == activeSpecIndex)
            then
                self:SetTextLootSpec(name, icon);
            end
        end
    end

    LibDD:EasyMenu(self.menuList.spec, self.dropDown, self.dropDown, 0, 0);
end

function TLB:SelectLoadout(configID, configName)
    local loadResult;
    if configID == self.currentConfigID then
        return;
    elseif configID == starterConfigID then
        loadResult = C_ClassTalents.SetStarterBuildActive(true);
    else
        loadResult = C_ClassTalents.LoadConfig(configID, true);
    end
    if loadResult ~= Enum.LoadConfigResult.Error then
        self:SetTextLoadout(configName);
    end
    if loadResult == Enum.LoadConfigResult.NoChangesNecessary then
        if self.currentConfigID == starterConfigID then C_ClassTalents.SetStarterBuildActive(false); end
        self.updatePending = false;
        self.pendingConfigID = nil;
        self:UpdateLastSelectedSavedConfigID(configID);
    elseif loadResult == Enum.LoadConfigResult.LoadInProgress then
        if self.currentConfigID == starterConfigID then self.pendingDisableStarterBuild = true; end
        self.updatePending = true;
        self.pendingConfigID = configID;
        self:SetTextIsSwitching(true);
    end
end

function TLB:SelectSpec(specIndex)
    if GetSpecialization() == specIndex then return; end
    SetSpecialization(specIndex);
    local _, name, _, icon = GetSpecializationInfoForClassID(PlayerUtil.GetClassID(), specIndex);
    self:SetTextSpec(name, icon);
    self:SetTextIsSwitching(true);
end

function TLB:SelectLootSpec(specID)
    if GetLootSpecialization() == specID then return; end
    SetLootSpecialization(specID);
    local _, name, _, icon = GetSpecializationInfoByID(specID);
    --self:RefreshMenuListSpecs();
    self:SetTextLootSpec(name, icon);
end

--- @return FRAME?
function TLB:GetTalentFrame()
    return (ClassTalentFrame and ClassTalentFrame.TalentsTab) or (PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame);
end

--- @return FRAME?
function TLB:GetTalentFrameContainer()
    return ClassTalentFrame or PlayerSpellsFrame;
end

local function secureSetNil(table, key)
    TextureLoadingGroupMixin.RemoveTexture({textures = table}, key);
end
function TLB:UpdateLastSelectedSavedConfigID(configID)
    self.ignoreHook = true;
    C_ClassTalents.UpdateLastSelectedSavedConfigID(PlayerUtil.GetCurrentSpecID(), configID);
    self.ignoreHook = false;

    -- this horrible workaround should not be needed once blizzard actually fires SELECTED_LOADOUT_CHANGED event
    -- or you know.. realizes that it's possible for addons to change the loadout, but we can't do that without tainting all the things
    local talentsTab = self:GetTalentFrame();
    if not talentsTab then return; end
    local dropdown = talentsTab.LoadoutDropDown or talentsTab.LoadSystem;
    local _ = dropdown and dropdown.SetSelectionID and dropdown:SetSelectionID(configID);

    if true then return end -- disable this for now, needs more testing
    -- this seems to reduce the amount of tainted values, but I didn't really dig into it
    local _ = dropdown and dropdown.DropDownControl and secureSetNil(dropdown.DropDownControl, 'selectedValue');
end

function TLB:TRAIT_CONFIG_UPDATED(configID)
    if configID ~= C_ClassTalents.GetActiveConfigID() then return; end
    if self.updatePending then
        local pendingConfigID = self.pendingConfigID;
        local configName = self.configIDToName[pendingConfigID] or 'Unknown';
        local pendingDisableStarterBuild = self.pendingDisableStarterBuild;
        C_Timer.After(0, function()
            self.updatePending = false;
            if pendingDisableStarterBuild then
                C_ClassTalents.SetStarterBuildActive(false);
            end
            self:UpdateLastSelectedSavedConfigID(pendingConfigID);
            self:SetTextLoadout(configName);
            self:SetTextIsSwitching(false);
            self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil;

            self:RefreshMenuListLoadouts();
            local frame = self:GetTalentFrameContainer();
            if not InCombatLockdown() and frame and frame:IsShown() then
                HideUIPanel(frame);
                ShowUIPanel(frame);
            end
        end);

        return;
    end
    C_Timer.After(0, function()
        self:RefreshMenuListLoadouts();
    end)
end

function TLB:CONFIG_COMMIT_FAILED(configID)
    if configID ~= C_ClassTalents.GetActiveConfigID() then return; end
    if self.updatePending then
        local currentConfigID = self.currentConfigID;
        local configName = self.configIDToName[currentConfigID] or 'Unknown'
        C_Timer.After(0, function() -- next frame, because the default UI will overwrite anything we do here -.-
            self.updatePending = false;
            C_Traits.RollbackConfig(C_ClassTalents.GetActiveConfigID());
            if currentConfigID == starterConfigID then
                C_Timer.After(1, function()
                    C_ClassTalents.SetStarterBuildActive(true);
                    self:UpdateLastSelectedSavedConfigID(currentConfigID);
                end);
            end
            self:UpdateLastSelectedSavedConfigID(currentConfigID);
            self:SetTextLoadout(configName);
            self:SetTextIsSwitching(false);

            local frame = self:GetTalentFrameContainer();
            if not InCombatLockdown() and frame and frame:IsShown() then
                HideUIPanel(frame);
                ShowUIPanel(frame);
            end
        end)
        self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil;
    end
end

function TLB:SPELLS_CHANGED()
    self:RefreshMenuListLoadouts();
    self:RefreshMenuListSpecs();

    EventUtil.ContinueOnAddOnLoaded('TalentLoadoutManager', function()
        if not TalentLoadoutManagerAPI then return; end
        RunNextFrame(function()
            self:RefreshMenuListLoadouts();
        end);

        local API = TalentLoadoutManagerAPI;
        API:RegisterCallback(API.Event.LoadoutListUpdated, self.RefreshMenuListLoadouts, self);
        API:RegisterCallback(API.Event.CustomLoadoutApplied, self.RefreshMenuListLoadouts, self);
    end);

    self.eventFrame:UnregisterEvent('SPELLS_CHANGED');
end

function TLB:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    self:SetTextIsSwitching(false);
    self:RefreshMenuListLoadouts();
    self:RefreshMenuListSpecs();
end

function TLB:SPECIALIZATION_CHANGE_CAST_FAILED()
    self:SetTextIsSwitching(false);
    self:RefreshMenuListSpecs();
end

function TLB:PLAYER_LOOT_SPEC_UPDATED()
    self:RefreshMenuListSpecs();
end

do TLB:Init(); end
