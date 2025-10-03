local addonName, ns = ...;
ns.TLB = {};

--- @class TalentLoadoutBroker
local TLB = ns.TLB;

local starterConfigID = Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID;
local isDruid = select(2, UnitClass('player')) == 'DRUID';

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
    self:RefreshLoadoutText();

    self.eventFrame = CreateFrame('Frame');
    self.eventFrame:RegisterEvent('TRAIT_CONFIG_UPDATED');
    self.eventFrame:RegisterEvent('CONFIG_COMMIT_FAILED');
    self.eventFrame:RegisterEvent('ACTIVE_PLAYER_SPECIALIZATION_CHANGED');
    self.eventFrame:RegisterEvent('SPECIALIZATION_CHANGE_CAST_FAILED');
    self.eventFrame:RegisterEvent('PLAYER_LOOT_SPEC_UPDATED');
    self.eventFrame:RegisterEvent('SPELLS_CHANGED');
    self.eventFrame:SetScript('OnEvent', function(_, event, ...) self[event](self, ...); end);
    self.ignoreHook = false;
    hooksecurefunc(C_ClassTalents, 'UpdateLastSelectedSavedConfigID', function()
        if self.ignoreHook then return; end
        self:RefreshLoadoutText();
    end);
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
            PlayerSpellsUtil.ToggleClassTalentOrSpecFrame();
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
    MenuUtil.CreateContextMenu(brokerFrame, function(owner, rootDescription)
        self:GenerateLoadoutDropdown(rootDescription);
    end);
end

function TLB:ToggleSpecDropDown(brokerFrame)
    MenuUtil.CreateContextMenu(brokerFrame, function(owner, rootDescription)
        self:GenerateSpecDropdown(rootDescription);
    end);
end

function TLB:RefreshConfigMapping()
    local specID = PlayerUtil.GetCurrentSpecID();
    if not specID then return; end

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
end

function TLB:RefreshLoadoutText()
    if TalentLoadoutManagerAPI then
        local API = TalentLoadoutManagerAPI;
        local activeLoadoutID = API.CharacterAPI:GetActiveLoadoutID();

        if C_ClassTalents.GetActiveConfigID() == activeLoadoutID then
            self:SetTextLoadout(LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(TALENT_FRAME_DROP_DOWN_DEFAULT));
        elseif activeLoadoutID then
            local loadoutInfo = API.GlobalAPI:GetLoadoutInfoByID(activeLoadoutID);
            if loadoutInfo then
                self:SetTextLoadout(loadoutInfo.displayName);
            end
        end
    else
        self:RefreshConfigMapping();
        if not self.configIDs then return; end
        local function isSelected(data)
            local configID = data.configID;

            return (not self.updatePending and configID == 0 and self.currentConfigID == nil)
                or (self.updatePending and self.pendingConfigID == configID)
                or (not self.updatePending and self.currentConfigID == configID);
        end
        for _, configID in ipairs(self.configIDs) do
            local configName = self.configIDToName[configID];
            if isSelected({ configID = configID }) then
                self:SetTextLoadout(configName);
                break;
            end
        end
    end
end

function TLB:RefreshSpecText()
    local activeSpecIndex = C_SpecializationInfo.GetSpecialization();
    if not activeSpecIndex then return; end

    local specID, name, _, icon = GetSpecializationInfoForClassID(PlayerUtil.GetClassID(), activeSpecIndex);
    self:SetTextSpec(name, icon);

    local activeLootSpec = GetLootSpecialization();
    local _, lootSpecName, _, lootSpecIcon = GetSpecializationInfoByID(activeLootSpec == 0 and specID or activeLootSpec);
    self:SetTextLootSpec(lootSpecName, lootSpecIcon);
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

---@param rootDescription RootMenuDescriptionProxy
function TLB:GenerateLoadoutDropdown(rootDescription)
    self:RefreshLoadoutText();
    if TalentLoadoutManagerAPI then
        self:GenerateTLMLoadoutDropdown(rootDescription);
    else
        self:GenerateDefaultUILoadoutDropdown(rootDescription);
    end
end

---@param rootDescription RootMenuDescriptionProxy
function TLB:GenerateDefaultUILoadoutDropdown(rootDescription)
    local specID = PlayerUtil.GetCurrentSpecID();
    if not specID then return; end

    self:RefreshConfigMapping();

    rootDescription:CreateTitle('Loadouts');

    local function onClick(data) self:SelectLoadout(data.configID, data.configName); end
    local function isSelected(data)
        local configID = data.configID;

        return (not self.updatePending and configID == 0 and self.currentConfigID == nil)
            or (self.updatePending and self.pendingConfigID == configID)
            or (not self.updatePending and self.currentConfigID == configID);
    end

    for _, configID in ipairs(self.configIDs) do
        local configName = self.configIDToName[configID];
        local data = { configID = configID, configName = configName };
        rootDescription:CreateRadio(configName, isSelected, onClick, data);
        if isSelected(data) then self:SetTextLoadout(configName); end
    end
end

---@param rootDescription RootMenuDescriptionProxy
function TLB:GenerateTLMLoadoutDropdown(rootDescription)
    local specID = PlayerUtil.GetCurrentSpecID();
    if not specID then return; end

    rootDescription:CreateTitle('Loadouts');

    local API = TalentLoadoutManagerAPI;
    local function onClick(data) API.CharacterAPI:LoadLoadout(data.loadoutID, true); end
    local function isSelected(data) return API.CharacterAPI:GetActiveLoadoutID() == data.loadoutID; end

    local loadouts = {};
    for _, loadoutInfo in ipairs(API.GlobalAPI:GetLoadouts()) do
        loadoutInfo.parentID = loadoutInfo.parentMapping and loadoutInfo.parentMapping[0];
        table.insert(loadouts, {
            text = loadoutInfo.parentID and ('  ||  '..loadoutInfo.displayName) or loadoutInfo.displayName,
            loadoutID = loadoutInfo.id,
            data = loadoutInfo,
            parentID = loadoutInfo.parentID,
        });
    end
    self:SortTLMLoadouts(loadouts);
    for _, data in ipairs(loadouts) do
        rootDescription:CreateRadio(data.text, isSelected, onClick, data);
    end
end

--- @param loadouts TLB_TLMLoadout[]
function TLB:SortTLMLoadouts(loadouts)
    --- order by:
    --- 1. playerIsOwner
    --- 2. isBlizzardLoadout
    --- 3. name
    --- 4. id (basically, the order they were created)
    ---
    --- custom loadouts are listed underneath their parent, if any

    --- @param a TLB_TLMLoadout
    --- @param b TLB_TLMLoadout
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

        if a.data.name < b.data.name then
            return true;
        elseif a.data.name > b.data.name then
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

---@param rootDescription RootMenuDescriptionProxy
function TLB:GenerateSpecDropdown(rootDescription)
    local activeSpecIndex = C_SpecializationInfo.GetSpecialization();
    if not activeSpecIndex then return; end

    self:RefreshSpecText();

    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(PlayerUtil.GetClassID());

    -- spec selection
    do
        rootDescription:CreateTitle(SPECIALIZATION);
        local function isSelected(data) return activeSpecIndex == data; end
        local function selectSpec(data)
            if isDruid and GetShapeshiftForm() == 3 then
                CancelShapeshiftForm();
            end
            self:SelectSpec(data);
        end

        for specIndex = 1, numSpecs do
            local _, name, _, icon = GetSpecializationInfoForClassID(PlayerUtil.GetClassID(), specIndex);
            local button = rootDescription:CreateRadio(
                self:FormatSpecText(name, icon),
                isSelected,
                selectSpec,
                specIndex
            );
            if isDruid then
                button:HookOnEnter(function(frame)
                    if GetShapeshiftForm() == 3 then
                        GameTooltip:SetOwner(frame, 'ANCHOR_TOP');
                        GameTooltip:SetText('This will cancel your travel form!');
                        GameTooltip:Show();
                    end
                end);
                button:HookOnLeave(function()
                    GameTooltip:Hide();
                end);
            end
        end
    end
    -- lootspec selection
    rootDescription:CreateSpacer();
    do
        rootDescription:CreateTitle(SELECT_LOOT_SPECIALIZATION);
        local activeLootSpec = GetLootSpecialization();
        local function isSelected(data) return activeLootSpec == data; end
        local function selectSpec(data) self:SelectLootSpec(data); end

        rootDescription:CreateRadio(
            string.format(LOOT_SPECIALIZATION_DEFAULT, select(2, C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization()))),
            isSelected,
            selectSpec,
            0
        );
        for specIndex = 1, numSpecs do
            local specId, name, _, icon = GetSpecializationInfoForClassID(PlayerUtil.GetClassID(), specIndex);
            rootDescription:CreateRadio(
                self:FormatSpecText(name, icon),
                isSelected,
                selectSpec,
                specId
            );
        end
    end
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
    if C_SpecializationInfo.GetSpecialization() == specIndex then return; end
    C_SpecializationInfo.SetSpecialization(specIndex);
    local _, name, _, icon = GetSpecializationInfoForClassID(PlayerUtil.GetClassID(), specIndex);
    self:SetTextSpec(name, icon);
    self:SetTextIsSwitching(true);
end

function TLB:SelectLootSpec(specID)
    if GetLootSpecialization() == specID then return; end
    SetLootSpecialization(specID);
    local _, name, _, icon = GetSpecializationInfoByID(specID);
    self:SetTextLootSpec(name, icon);
end

--- @return PlayerSpellsFrame_TalentsFrame?
function TLB:GetTalentFrame()
    return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame;
end

--- @return PlayerSpellsFrame?
function TLB:GetTalentFrameContainer()
    return PlayerSpellsFrame;
end

function TLB:UpdateLastSelectedSavedConfigID(configID)
    self.ignoreHook = true;
    C_ClassTalents.UpdateLastSelectedSavedConfigID(PlayerUtil.GetCurrentSpecID(), configID);
    self.ignoreHook = false;

    -- this horrible workaround should not be needed once blizzard actually fires SELECTED_LOADOUT_CHANGED event
    -- or you know.. realizes that it's possible for addons to change the loadout, but we can't do that without tainting all the things
    local talentsTab = self:GetTalentFrame();
    if not talentsTab then return; end
    local dropdown = talentsTab.LoadSystem;
    local _ = dropdown and dropdown.SetSelectionID and dropdown:SetSelectionID(configID);
end

function TLB:TRAIT_CONFIG_UPDATED(configID)
    if configID ~= C_ClassTalents.GetActiveConfigID() then return; end
    if self.updatePending then
        local pendingConfigID = self.pendingConfigID;
        local configName = self.configIDToName[pendingConfigID] or 'Unknown';
        local pendingDisableStarterBuild = self.pendingDisableStarterBuild;
        RunNextFrame(function()
            self.updatePending = false;
            if pendingDisableStarterBuild then
                C_ClassTalents.SetStarterBuildActive(false);
            end
            self:UpdateLastSelectedSavedConfigID(pendingConfigID);
            self:SetTextLoadout(configName);
            self:SetTextIsSwitching(false);
            self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil;

            self:RefreshLoadoutText();
            local frame = self:GetTalentFrameContainer();
            if not InCombatLockdown() and frame and frame:IsShown() then
                HideUIPanel(frame);
                ShowUIPanel(frame);
            end
        end);

        return;
    end
    RunNextFrame(function()
        self:RefreshLoadoutText();
    end);
end

function TLB:CONFIG_COMMIT_FAILED(configID)
    if configID ~= C_ClassTalents.GetActiveConfigID() then return; end
    if self.updatePending then
        local currentConfigID = self.currentConfigID;
        local configName = self.configIDToName[currentConfigID] or 'Unknown';
        RunNextFrame(function() -- next frame, because the default UI will overwrite anything we do here -.-
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
        end);
        self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil;
    end
end

function TLB:SPELLS_CHANGED()
    self:RefreshLoadoutText();
    self:RefreshSpecText();

    EventUtil.ContinueOnAddOnLoaded('TalentLoadoutManager', function()
        if not TalentLoadoutManagerAPI then return; end
        RunNextFrame(function()
            self:RefreshLoadoutText();
        end);

        local API = TalentLoadoutManagerAPI;
        API:RegisterCallback(API.Event.LoadoutListUpdated, self.RefreshLoadoutText, self);
        API:RegisterCallback(API.Event.CustomLoadoutApplied, self.RefreshLoadoutText, self);
    end);

    self.eventFrame:UnregisterEvent('SPELLS_CHANGED');
end

function TLB:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    self:SetTextIsSwitching(false);
    self:RefreshLoadoutText();
    self:RefreshSpecText();
end

function TLB:SPECIALIZATION_CHANGE_CAST_FAILED()
    self:SetTextIsSwitching(false);
    self:RefreshSpecText();
end

function TLB:PLAYER_LOOT_SPEC_UPDATED()
    self:RefreshSpecText();
end

do TLB:Init(); end
