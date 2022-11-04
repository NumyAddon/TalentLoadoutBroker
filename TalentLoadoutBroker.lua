local _, ns = ...

--- @type LibUIDropDownMenu
local LibDD = LibStub:GetLibrary('LibUIDropDownMenu-4.0')
local starterConfigID = Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID

function ns:Init()
    self.dropDown = LibDD:Create_UIDropDownMenu(nil, UIParent)
    self.dropDown:Hide()

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
    }
    self.menuList = Mixin({}, self.menuListDefaults)
    self.configIDs, self.configIDToName, self.currentConfigID = nil, nil, nil
    self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil
    self.currentConfigID = nil

    self.TalentLoadoutLDB = LibStub('LibDataBroker-1.1'):NewDataObject(
            'Talent Loadout',
            {
                type = 'data source',
                text = 'Talent Loadout',
                OnClick = function(brokerFrame, button)
                    ns:OnButtonClick(brokerFrame, button)
                end,
                OnTooltipShow = function(tooltip)
                    ns:OnTooltipShow(tooltip)
                end,
            }
    );
    self:RefreshMenuListLoadouts();

    self.eventFrame = CreateFrame('Frame')
    self.eventFrame:RegisterEvent('TRAIT_CONFIG_UPDATED')
    self.eventFrame:RegisterEvent('CONFIG_COMMIT_FAILED')
    self.eventFrame:RegisterEvent('ACTIVE_PLAYER_SPECIALIZATION_CHANGED')
    self.eventFrame:RegisterEvent('SPECIALIZATION_CHANGE_CAST_FAILED')
    self.eventFrame:RegisterEvent('SPELLS_CHANGED')
    self.eventFrame:SetScript('OnEvent', function(_, event, ...)
        self[event](self, ...)
    end)
    self.ignoreHook = false
    hooksecurefunc(C_ClassTalents, 'UpdateLastSelectedSavedConfigID', function()
        if self.ignoreHook then return; end
        self:RefreshMenuListLoadouts();
    end)
end

function ns:OnTooltipShow(tooltip)
    tooltip:AddLine('Talent Loadout')
    tooltip:AddLine('|cffeda55fClick|r to switch loadouts')
    tooltip:AddLine('|cffeda55fRight-Click|r to open talent frame')
    tooltip:AddLine('|cffeda55fShift + Click|r to switch specs')
    tooltip:AddLine('|cffeda55fShift + Right-Click|r to switch loot specs')
end

function ns:OnButtonClick(brokerFrame, button)
    if button == 'LeftButton' then
        if not IsShiftKeyDown() then
            self:ToggleLoadoutDropDown(brokerFrame)
        else
            self:ToggleSpecDropDown(brokerFrame)
        end
    elseif button == 'RightButton' then
        if not IsShiftKeyDown() then
            ToggleTalentFrame()
        else
            self:ToggleLootSpecDropDown(brokerFrame)
        end
    end
end

function ns:ToggleLoadoutDropDown(brokerFrame)
    self:RefreshMenuListLoadouts()
    LibDD:ToggleDropDownMenu(1, nil, self.dropDown, brokerFrame, 0, 0, self.menuList.loadout)
end

function ns:ToggleSpecDropDown(brokerFrame)
    self:RefreshMenuListSpecs()
    LibDD:ToggleDropDownMenu(1, nil, self.dropDown, brokerFrame, 0, 0, self.menuList.spec)
end

function ns:ToggleLootSpecDropDown(brokerFrame)
    self:RefreshMenuListLootSpecs()
    LibDD:ToggleDropDownMenu(1, nil, self.dropDown, brokerFrame, 0, 0, self.menuList.lootSpec)
end

function ns:SetTextLoadout(loadoutName)
    self:SetText(loadoutName)
end

function ns:SetTextSpec(name, icon)
    self:SetText(nil, name, icon)
end

function ns:SetTextIsSwitching(isSwitching)
    self:SetText(nil, nil, nil, isSwitching)
end

function ns:SetText(loadoutName, specName, specIcon, isSwitching)
    self.displayLoadoutName = loadoutName or self.displayLoadoutName
    self.displaySpecName = specName or self.displaySpecName
    self.displaySpecIcon = specIcon or self.displaySpecIcon
    if isSwitching ~= nil then self.displayIsSwitching = isSwitching end

    local text = ''
    if self.displayIsSwitching then
        text = text .. DIM_GREEN_FONT_COLOR:WrapTextInColorCode('switching ')
    end
    if self.displaySpecName then
        local formattedIcon = ''
        if self.displaySpecIcon then
            formattedIcon = string.format('|T%s:16:16:0:0:64:64:4:60:4:60|t', self.displaySpecIcon)
        end
        text = text .. string.format(' %s%s||', formattedIcon, self.displaySpecName)
    end
    if self.displayLoadoutName then
        text = text .. self.displayLoadoutName
    end

    self.TalentLoadoutLDB.text = text
end

function ns:FormatSpecText(name, icon)
    return string.format('|T%s:14:14:0:0:64:64:4:60:4:60|t  %s', icon, name );
end

function ns:RefreshMenuListLoadouts()
    local specID = PlayerUtil.GetCurrentSpecID()
    if not specID then return end
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
        table.insert(self.configIDs, 0)
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
        local checked = (not self.updatePending and configID == 0 and self.currentConfigID == nil)
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
        if checked then self:SetTextLoadout(configName) end
    end
    LibDD:EasyMenu(self.menuList.loadout, self.dropDown, self.dropDown, 0, 0);
end

function ns:RefreshMenuListSpecs()
    local activeSpecIndex = GetSpecialization()
    if not activeSpecIndex then return end

    local function onClick(_, specIndex) self:SelectSpec(specIndex) end
    local function isChecked(data) return activeSpecIndex == data.arg1 end

    local numSpecs = GetNumSpecializationsForClassID(PlayerUtil.GetClassID())
    self.menuList.spec = Mixin({}, self.menuListDefaults.spec);
    for i = 1, numSpecs do
        local _, name, _, icon = GetSpecializationInfoForClassID(PlayerUtil.GetClassID(), i)
        table.insert(self.menuList.spec, {
            text = self:FormatSpecText(name, icon),
            arg1 = i,
            func = onClick,
            checked = isChecked,
            notClickable = i == activeSpecIndex,
        });
        if i == activeSpecIndex then self:SetTextSpec(name, icon) end
    end
    LibDD:EasyMenu(self.menuList.spec, self.dropDown, self.dropDown, 0, 0);
end

function ns:RefreshMenuListLootSpecs()
    local numSpecs = GetNumSpecializationsForClassID(PlayerUtil.GetClassID())
    local activeLootSpec = GetLootSpecialization()
    self.menuList.lootSpec = Mixin({}, self.menuListDefaults.lootSpec);

    local function onClick(_, specId) ns:SelectLootSpec(specId) end
    local function isChecked(data) return activeLootSpec == data.arg1 end
    table.insert(self.menuList.lootSpec, {
        text = string.format(LOOT_SPECIALIZATION_DEFAULT, select(2, GetSpecializationInfo(GetSpecialization()))),
        arg1 = 0,
        func = onClick,
        checked = isChecked,
        notClickable = activeLootSpec == 0,
    })
    for i = 1, numSpecs do
        local specId, name, _, icon = GetSpecializationInfoForClassID(PlayerUtil.GetClassID(), i)
        table.insert(self.menuList.lootSpec, {
            text = self:FormatSpecText(name, icon),
            arg1 = specId,
            func = onClick,
            checked = isChecked,
            notClickable = activeLootSpec == specId,
        })
    end
    LibDD:EasyMenu(self.menuList.lootSpec, self.dropDown, self.dropDown, 0, 0);
end

function ns:SelectLoadout(configID, configName)
    local loadResult
    if configID == self.currentConfigID then
        return
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
        self.updatePending = true;
        self.pendingConfigID = configID;
        self:UpdateLastSelectedSavedConfigID(configID);
    elseif loadResult == Enum.LoadConfigResult.LoadInProgress then
        if self.currentConfigID == starterConfigID then self.pendingDisableStarterBuild = true; end
        self.updatePending = true;
        self.pendingConfigID = configID;
        self:SetTextIsSwitching(true);
    end
end

function ns:SelectSpec(specIndex)
    if GetSpecialization() == specIndex then return end
    SetSpecialization(specIndex)
    local _, name, _, icon = GetSpecializationInfoForClassID(PlayerUtil.GetClassID(), specIndex)
    self:SetTextSpec(name, icon);
    self:SetTextIsSwitching(true);
end

function ns:SelectLootSpec(specID)
    if GetLootSpecialization() == specID then return end
    SetLootSpecialization(specID)
    self:RefreshMenuListLootSpecs()
end

function ns:UpdateLastSelectedSavedConfigID(configID)
    self.ignoreHook = true;
    C_ClassTalents.UpdateLastSelectedSavedConfigID(PlayerUtil.GetCurrentSpecID(), configID);
    self.ignoreHook = false;
end

function ns:TRAIT_CONFIG_UPDATED(configID)
    if configID ~= C_ClassTalents.GetActiveConfigID() then return end
    if self.updatePending then
        local pendingConfigID = self.pendingConfigID
        local configName = self.configIDToName[pendingConfigID] or 'Unknown'
        local pendingDisableStarterBuild = self.pendingDisableStarterBuild
        C_Timer.After(0, function()
            self.updatePending = false;
            if pendingDisableStarterBuild then
                C_ClassTalents.SetStarterBuildActive(false);
            end
            self:UpdateLastSelectedSavedConfigID(pendingConfigID);
            self:SetTextLoadout(configName);
            self:SetTextIsSwitching(false);
            self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil

            self:RefreshMenuListLoadouts();
            if not InCombatLockdown() and ClassTalentFrame and ClassTalentFrame:IsShown() then
                HideUIPanel(ClassTalentFrame);
                ShowUIPanel(ClassTalentFrame);
            end
        end);

        return;
    end
    C_Timer.After(0, function()
        self:RefreshMenuListLoadouts();
    end)
end

function ns:CONFIG_COMMIT_FAILED(configID)
    if configID ~= C_ClassTalents.GetActiveConfigID() then return end
    if self.updatePending then
        local currentConfigID = self.currentConfigID
        local configName = self.configIDToName[currentConfigID] or 'Unknown'
        C_Timer.After(0, function() -- next frame, because the default UI will overwrite anything we do here -.-
            self.updatePending = false;
            C_Traits.RollbackConfig(C_ClassTalents.GetActiveConfigID());
            if currentConfigID == starterConfigID then
                C_Timer.After(1, function()
                    C_ClassTalents.SetStarterBuildActive(true);
                    self:UpdateLastSelectedSavedConfigID(currentConfigID);
                end)
            end
            self:UpdateLastSelectedSavedConfigID(currentConfigID);
            self:SetTextLoadout(configName);
            self:SetTextIsSwitching(false);

            if not InCombatLockdown() and ClassTalentFrame and ClassTalentFrame:IsShown() then
                HideUIPanel(ClassTalentFrame);
                ShowUIPanel(ClassTalentFrame);
            end
        end)
        self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil
    end
end

function ns:SPELLS_CHANGED()
    self:RefreshMenuListLoadouts();
    self:RefreshMenuListSpecs();
    self:RefreshMenuListLootSpecs();

    self.eventFrame:UnregisterEvent('SPELLS_CHANGED');
end

function ns:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    self:SetTextIsSwitching(false);
    self:RefreshMenuListLoadouts();
    self:RefreshMenuListSpecs();
end

function ns:SPECIALIZATION_CHANGE_CAST_FAILED()
    self:SetTextIsSwitching(false);
    self:RefreshMenuListSpecs();
end

do ns:Init() end