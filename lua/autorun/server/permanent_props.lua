-- DPerma — Permanent Props

file.CreateDir( "dperma" )
file.CreateDir( "dperma_unbrakable" ) -- имя директории сохранено для совместимости с существующими сохранениями

local HOOK_NAME  = "DenomitoPermaProps"
local map_name   = game.GetMap()
local file_props = "dperma/" .. map_name .. ".json"
local file_unbrk = "dperma_unbrakable/" .. map_name .. ".json"

-- ─── Developer cvar guard ────────────────────────────────────────────────────

local developer_cvar = GetConVar( "developer" )
if not developer_cvar then return end

-- ─── Persistent entity list + O(1) lookup set ────────────────────────────────

DPERMA_ENTS = DPERMA_ENTS or {}

-- При перезагрузке скрипта восстанавливаем lookup-таблицу из глобального списка
local dperma_set = {}
for _, ent in ipairs( DPERMA_ENTS ) do
    if IsValid( ent ) then
        dperma_set[ ent ] = true
    end
end

-- ─── Unbreakable map (per-map persistence) ───────────────────────────────────

local unbreakable = util.JSONToTable(
    file.Read( file_unbrk, "DATA" ) or "{}"
) or {}

-- ─── Prop tracking ───────────────────────────────────────────────────────────

---@param entity Entity
local function addProp( entity )
    if dperma_set[ entity ] then return end     -- предотвращаем дублирование

    dperma_set[ entity ]            = true
    DPERMA_ENTS[ #DPERMA_ENTS + 1 ] = entity

    print( string.format( "[DPerma] Added '%s' (creator: %s)",
        tostring( entity ), tostring( entity:GetCreator() ) ) )
end

---@param entity Entity
local function removeProp( entity )
    if not dperma_set[ entity ] then return end -- быстрый выход: не perma prop

    dperma_set[ entity ] = nil

    for i = #DPERMA_ENTS, 1, -1 do
        if DPERMA_ENTS[ i ] == entity then
            table.remove( DPERMA_ENTS, i )
            break
        end
    end
end

-- ─── Props list (saved data from disk) ───────────────────────────────────────

local props_list = {}

local function updatePropsList()
    -- ИСПРАВЛЕНО: добавлен fallback `or {}` — JSONToTable может вернуть nil при
    -- повреждённом/пустом JSON, что роняло createProps() с ошибкой #nil
    props_list = util.JSONToTable(
        file.Read( file_props, "DATA" ) or "{}"
    ) or {}
end

updatePropsList()

-- ─── Commands ────────────────────────────────────────────────────────────────

-- Общая проверка прав
local function isSuperAdmin( ply )
    return IsValid( ply ) and ply:IsSuperAdmin()
end

concommand.Add( "dperma_save", function( ply )
    if not isSuperAdmin( ply ) then return end

    local data = {}
    for i = 1, #DPERMA_ENTS do
        data[ i ] = duplicator.Copy( DPERMA_ENTS[ i ] )
    end

    file.Write( file_props, util.TableToJSON( data, true ) )
    file.Write( file_unbrk, util.TableToJSON( unbreakable, true ) )

    props_list = data
    print( string.format( "[DPerma] Saved %d props for map '%s'.", #data, map_name ) )
end )

-- ИСПРАВЛЕНО: в оригинальном dperma_setunbrakable_default параметр `ply`
-- отсутствовал в сигнатуре функции → обращение к nil-переменной → краш сервера.
-- Обе команды (setunbrakable / setunbreakable) объединены в общую логику.

local function cmdSetUnbreakable( ply, persistent )
    if not isSuperAdmin( ply ) then return end

    local entity = ply:GetEyeTrace().Entity
    if not IsValid( entity ) then return end

    entity.DPermaUnbrakable = true

    -- Гарантируем сохранение флага при duplicator.Copy()
    entity.OnEntityCopyTableFinish = function( t )
        t.DPermaUnbrakable = true
    end

    if persistent then
        -- Записать в постоянный список (по EntIndex на текущей сессии)
        unbreakable[ entity:EntIndex() ] = true
        print( "[DPerma] Entity " .. tostring( entity ) .. " set as unbreakable (persistent)." )
    else
        print( "[DPerma] Entity " .. tostring( entity ) .. " set as unbreakable (session)." )
    end
end

concommand.Add( "dperma_setunbrakable",         function( ply ) cmdSetUnbreakable( ply, false ) end )
concommand.Add( "dperma_setunbrakable_default",  function( ply ) cmdSetUnbreakable( ply, true  ) end )

concommand.Add( "dperma_clear_unbrakable", function( ply )
    -- ИСПРАВЛЕНО: в оригинале не было проверки прав — любой мог очистить список
    if not isSuperAdmin( ply ) then return end

    table.Empty( unbreakable )
    file.Write( file_unbrk, "{}" )
    print( "[DPerma] Cleared all unbreakable overrides for map '" .. map_name .. "'." )
end )

-- ─── Spawn hooks ─────────────────────────────────────────────────────────────

local function onPlayerSpawnedEnt( entity )
    if developer_cvar:GetBool() then
        addProp( entity )
    end
end

hook.Add( "PlayerSpawnedProp",    HOOK_NAME, function( _, _, entity ) onPlayerSpawnedEnt( entity ) end )
hook.Add( "PlayerSpawnedVehicle", HOOK_NAME, function( _, entity )    onPlayerSpawnedEnt( entity ) end )
hook.Add( "PlayerSpawnedRagdoll", HOOK_NAME, function( _, _, entity ) onPlayerSpawnedEnt( entity ) end )
hook.Add( "PlayerSpawnedEffect",  HOOK_NAME, function( _, _, entity ) onPlayerSpawnedEnt( entity ) end )
hook.Add( "PlayerSpawnedSENT",    HOOK_NAME, function( _, entity )    onPlayerSpawnedEnt( entity ) end )

-- ─── Developer cvar callback ─────────────────────────────────────────────────

cvars.AddChangeCallback( developer_cvar:GetName(), function( _, _, value )
    if not tobool( value ) then return end

    for _, entity in ents.Iterator() do
        if IsValid( entity:GetCreator() ) then
            addProp( entity )
        end
    end
end, HOOK_NAME )

-- ─── Entity lifecycle hooks ───────────────────────────────────────────────────

hook.Add( "EntityRemoved", HOOK_NAME, function( entity )
    -- ОПТИМИЗИРОВАНО: dperma_set даёт O(1) проверку вместо O(n) перебора
    -- при каждом удалении любой сущности на сервере
    removeProp( entity )
end )

hook.Add( "EntityTakeDamage", HOOK_NAME, function( entity, dmginfo )
    if entity.DPermaUnbrakable then
        dmginfo:SetDamage( 0 )
        return true
    end
end )

hook.Add( "OnEntityCreated", HOOK_NAME, function( entity )
    if unbreakable[ entity:EntIndex() ] then
        entity.DPermaUnbrakable = true
    end
end )

-- ─── Prop creation ───────────────────────────────────────────────────────────

local function createProps()
    if #props_list == 0 then return end

    timer.Simple( 0, function()
        local created = 0

        for i = 1, #props_list do
            local data   = props_list[ i ]
            ---@diagnostic disable-next-line: param-type-mismatch
            local entity = duplicator.CreateEntityFromTable( NULL, data )

            if IsValid( entity ) and entity.SetNW2Bool then
                entity:SetNW2Bool( "IsPermaProp", true )
                entity.DPermaUnbrakable = data.DPermaUnbrakable or false

                -- ОПТИМИЗИРОВАНО: используем addProp для единообразия —
                -- он же обновляет dperma_set и предотвращает дубликаты
                addProp( entity )
                created = created + 1
            end
        end

        -- ОПТИМИЗИРОВАНО: count_ents убран — #DPERMA_ENTS всегда актуален,
        -- отдельный счётчик рассинхронизировался при concurrent-изменениях
        print( string.format( "[DPerma] Spawned %d/%d perma props on '%s'.",
            created, #props_list, map_name ) )
    end )
end

hook.Add( "InitPostEntity", HOOK_NAME, createProps )

hook.Add( "PostCleanupMap", HOOK_NAME, function()
    -- После очистки карты все сущности уже удалены; сбрасываем tracking
    -- (EntityRemoved должен был сделать это, но сброс страхует от race conditions)
    DPERMA_ENTS = {}
    dperma_set  = {}
    createProps()
end )
