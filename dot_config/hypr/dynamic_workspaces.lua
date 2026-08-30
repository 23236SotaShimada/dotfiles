local M = {}

local pending = false
local reconciling = false
local reconcileTimer = nil
local errorReported = false

local function getNumericWorkspaces()
    local workspaces = {}

    for _, workspace in ipairs(hl.get_workspaces()) do
        if not workspace.special and workspace.id > 0 then
            table.insert(workspaces, {
                workspace = workspace,
                id = workspace.id,
                occupied = workspace.windows > 0,
            })
        end
    end

    table.sort(workspaces, function(left, right)
        return left.id < right.id
    end)

    return workspaces
end

local function getOccupiedWorkspaces(workspaces)
    local occupied = {}

    for _, item in ipairs(workspaces) do
        if item.occupied then
            table.insert(occupied, item)
        end
    end

    return occupied
end

local function isNormalized(occupied, activeWorkspace)
    for index, item in ipairs(occupied) do
        if item.id ~= index then
            return false
        end
    end

    if activeWorkspace ~= nil and not activeWorkspace.special and activeWorkspace.windows == 0 then
        return activeWorkspace.id == #occupied + 1
    end

    return true
end

local function getTemporaryIds(workspaces)
    local used = {}
    local temporaryIds = {}
    local candidate = 2147483647

    for _, item in ipairs(workspaces) do
        used[item.id] = true
    end

    for index = 1, #workspaces do
        while used[candidate] do
            candidate = candidate - 1
        end

        temporaryIds[index] = candidate
        used[candidate] = true
        candidate = candidate - 1
    end

    return temporaryIds
end

local function reconcile()
    local workspaces = getNumericWorkspaces()
    local occupied = getOccupiedWorkspaces(workspaces)
    local activeWorkspace = hl.get_active_workspace()

    if isNormalized(occupied, activeWorkspace) then
        return
    end

    local activeId = activeWorkspace ~= nil and activeWorkspace.id or nil
    local activeIsEmpty = activeWorkspace ~= nil and not activeWorkspace.special and activeWorkspace.windows == 0
    local nextOccupiedIndex = nil

    if activeIsEmpty then
        for index, item in ipairs(occupied) do
            if item.id > activeId then
                nextOccupiedIndex = index
                break
            end
        end
    end

    local temporaryIds = getTemporaryIds(workspaces)

    for index, item in ipairs(workspaces) do
        hl.dispatch(hl.dsp.workspace.change_id({
            workspace = item.workspace,
            id = temporaryIds[index],
        }))
    end

    for index, item in ipairs(occupied) do
        hl.dispatch(hl.dsp.workspace.change_id({
            workspace = item.workspace,
            id = index,
        }))
        hl.dispatch(hl.dsp.workspace.rename({
            workspace = item.workspace,
            name = tostring(index),
        }))
    end

    if activeIsEmpty then
        if nextOccupiedIndex ~= nil then
            hl.dispatch(hl.dsp.focus({ workspace = nextOccupiedIndex }))
        else
            local trailingId = #occupied + 1
            hl.dispatch(hl.dsp.workspace.change_id({
                workspace = activeWorkspace,
                id = trailingId,
            }))
            hl.dispatch(hl.dsp.workspace.rename({
                workspace = activeWorkspace,
                name = tostring(trailingId),
            }))
        end
    end
end

local function scheduleReconcile()
    if pending or reconciling then
        return
    end

    pending = true
    reconcileTimer = hl.timer(function()
        pending = false
        reconciling = true

        local ok, message = pcall(reconcile)

        reconciling = false
        reconcileTimer = nil

        if not ok and not errorReported then
            errorReported = true
            hl.notification.create({
                text = "Dynamic workspace update failed: " .. tostring(message),
                timeout = 5000,
                icon = "error",
            })
        end
    end, { timeout = 1, type = "oneshot" })
end

local function getLastAvailableWorkspace()
    local maximum = 0

    for _, workspace in ipairs(hl.get_workspaces()) do
        if not workspace.special and workspace.id > 0 and workspace.windows > 0 then
            maximum = math.max(maximum, workspace.id)
        end
    end

    return maximum + 1
end

function M.focus_previous()
    local workspace = hl.get_active_workspace()
    if workspace == nil or workspace.special then
        return
    end

    hl.dispatch(hl.dsp.focus({ workspace = math.max(1, workspace.id - 1) }))
end

function M.focus_next()
    local workspace = hl.get_active_workspace()
    if workspace == nil or workspace.special then
        return
    end

    local maximum = getLastAvailableWorkspace()
    hl.dispatch(hl.dsp.focus({ workspace = math.min(maximum, workspace.id + 1) }))
end

hl.on("hyprland.start", scheduleReconcile)
hl.on("config.reloaded", scheduleReconcile)
hl.on("workspace.active", scheduleReconcile)
hl.on("window.open", scheduleReconcile)
hl.on("window.destroy", scheduleReconcile)
hl.on("window.move_to_workspace", scheduleReconcile)

return M
