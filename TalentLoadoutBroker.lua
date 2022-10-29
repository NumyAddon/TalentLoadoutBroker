local _, ns = ...

--- @type LibUIDropDownMenu
local LibDD = LibStub:GetLibrary('LibUIDropDownMenu-4.0')
local starterConfigID = Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID
local textPrefix = NORMAL_FONT_COLOR:WrapTextInColorCode('TL: ')

function ns:Init()
    self.dropDown = LibDD:Create_UIDropDownMenu(nil, UIParent)
    self.dropDown:Hide()

    self.menuList = nil
    self.configIDs, self.configIDToName, self.selectedConfigId = nil, nil, nil
    self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil
    self.oldSelectedConfigId = nil

    self.TalentLoudoutLDB = LibStub('LibDataBroker-1.1'):NewDataObject(
            'Talent Loadout',
            {
                type = 'data source',
                text = 'Talent Loadout',
                OnClick = function(brokerFrame, button)
                    if button == 'LeftButton' then
                        self:RefreshLoadoutOptions()
                        LibDD:ToggleDropDownMenu(1, nil, self.dropDown, brokerFrame, 0, 0, self.menuList)
                    elseif button == 'RightButton' then
                        ToggleTalentFrame()
                    end
                end,
                OnTooltipShow = function(tooltip)
                    tooltip:AddLine('Talent Loadout')
                    tooltip:AddLine('|cffeda55fClick|r to switch loadouts')
                    tooltip:AddLine('|cffeda55fRight-Click|r to open talent frame')
                end,
            }
    );
    self:RefreshLoadoutOptions();

    self.eventFrame = CreateFrame('Frame')
    self.eventFrame:RegisterEvent('TRAIT_CONFIG_UPDATED')
    self.eventFrame:RegisterEvent('CONFIG_COMMIT_FAILED')
    self.eventFrame:RegisterEvent('SPELLS_CHANGED')
    self.eventFrame:SetScript('OnEvent', function(_, event, ...)
        self[event](self, ...)
    end)
end

function ns:SelectLoadout(configID, configName)
    local loadResult
    if configID == self.selectedConfigId then
        return
    elseif configID == starterConfigID then
        loadResult = C_ClassTalents.SetStarterBuildActive(true);
    else
        loadResult = C_ClassTalents.LoadConfig(configID, true);
    end
    if loadResult ~= Enum.LoadConfigResult.Error then
        self:SetText(configName);
    end
    if loadResult == Enum.LoadConfigResult.NoChangesNecessary then
        if self.oldSelectedConfigId == starterConfigID then C_ClassTalents.SetStarterBuildActive(false); end
        C_ClassTalents.UpdateLastSelectedSavedConfigID(PlayerUtil.GetCurrentSpecID(), configID);
    elseif loadResult == Enum.LoadConfigResult.LoadInProgress then
        if self.oldSelectedConfigId == starterConfigID then self.pendingDisableStarterBuild = true; end
        self.updatePending = true;
        self.pendingConfigID = configID;
    end
end

function ns:RefreshLoadoutOptions()
    local specID = PlayerUtil.GetCurrentSpecID()
    if not specID then return end
    self.selectedConfigId =
        C_ClassTalents.GetLastSelectedSavedConfigID(specID)
        or (C_ClassTalents.GetStarterBuildActive() and starterConfigID)
    self.oldSelectedConfigId = self.selectedConfigId;
    self.configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID);

    self.configIDToName = {};
    for _, configID in ipairs(self.configIDs) do
        local configInfo = C_Traits.GetConfigInfo(configID);
        self.configIDToName[configID] = (configInfo and configInfo.name) or '';
    end

    if not self.selectedConfigId then
        table.insert(self.configIDs, 0)
        self.configIDToName[0] = LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(TALENT_FRAME_DROP_DOWN_DEFAULT);
    end

    -- If spec has a starter build, add Starter Build as a dropdown option
    if C_ClassTalents.GetHasStarterBuild() then
        table.insert(self.configIDs, starterConfigID);
        self.configIDToName[starterConfigID] = BLUE_FONT_COLOR:WrapTextInColorCode(TALENT_FRAME_DROP_DOWN_STARTER_BUILD);
    end

    self.menuList = {};
    for configID, configName in pairs(self.configIDToName) do
        local checked = (not self.updatePending and configID == 0 and self.selectedConfigId == nil)
            or (self.updatePending and self.pendingConfigID == configID)
            or (not self.updatePending and self.selectedConfigId == configID);
        table.insert(self.menuList, {
            text = configName,
            arg1 = configID,
            arg2 = configName,
            func = function(_, configID, configName) ns:SelectLoadout(configID, configName) end,
            checked = checked,
            notClickable = self.updatePending or checked,
        });
        if checked then self:SetText(configName) end
    end
    LibDD:EasyMenu(self.menuList, self.dropDown, self.dropDown, 0, 0);
end

function ns:SetText(text)
    self.TalentLoudoutLDB.text = textPrefix .. text
end

function ns:CONFIG_COMMIT_FAILED(configID)
    if configID ~= C_ClassTalents.GetActiveConfigID() then return end
    if self.updatePending then
        self.updatePending = false
        if self.oldSelectedConfigId == starterConfigID and not C_ClassTalents.GetStarterBuildActive() then C_ClassTalents.SetStarterBuildActive(true); end
        C_ClassTalents.UpdateLastSelectedSavedConfigID(PlayerUtil.GetCurrentSpecID(), self.oldSelectedConfigId);
    end
end

function ns:TRAIT_CONFIG_UPDATED(configID)
    if configID ~= C_ClassTalents.GetActiveConfigID() then return end
    if self.updatePending then
        self.updatePending = false;
        if self.pendingDisableStarterBuild then C_ClassTalents.SetStarterBuildActive(false); end
        C_ClassTalents.UpdateLastSelectedSavedConfigID(PlayerUtil.GetCurrentSpecID(), self.pendingConfigID);
        self:SetText(self.configIDToName[self.pendingConfigID] or 'Unknown');
        self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil
    end
    self:RefreshLoadoutOptions();
end

function ns:SPELLS_CHANGED()
    self:RefreshLoadoutOptions();
    self.eventFrame:UnregisterEvent('SPELLS_CHANGED');
end

do ns:Init() end