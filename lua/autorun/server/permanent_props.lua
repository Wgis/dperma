file.CreateDir( "dperma" )
file.CreateDir( "dperma_unbrakable" )

local hook_name = "DenomitoPermaProps"
local table_remove = table.remove

local developer_cvar = GetConVar( "developer" )
if developer_cvar == nil then return end

local map_name = game.GetMap()
local unbreakable = util.JSONToTable( file.Read( "dperma_unbrakable/" .. map_name .. ".json", "DATA" ) or "{}" ) or {}

DPERMA_ENTS = DPERMA_ENTS or {}

local count_ents = #DPERMA_ENTS

---@param entity Entity
local function addProp( entity )
	print( string.format( "[DPerma] '%s' added by '%s'!", entity, entity:GetCreator() ) )
	DPERMA_ENTS[ #DPERMA_ENTS + 1 ] = entity
	count_ents = count_ents + 1
end

local function removeProp( entity )

	for i = 1, count_ents do
		if DPERMA_ENTS[ i ] == entity then
			table_remove( DPERMA_ENTS, i )

			break
		end
	end

	count_ents = #DPERMA_ENTS
end

local props_list


local function updatePropsList()
	props_list = util.JSONToTable( file.Read( "dperma/" .. map_name .. ".json", "DATA" ) or "{}" )
end

updatePropsList()

concommand.Add( "dperma_save", function( ply )
	if not ply:IsSuperAdmin() then
		return
	end

	local data = {}

	for i = 1, count_ents do
		data[ #data + 1 ] = duplicator.Copy( DPERMA_ENTS[ i ] )
	end

	file.Write( "dperma/" .. map_name .. ".json", util.TableToJSON( data, true ) )
	file.Write( "dperma_unbrakable/" .. map_name .. ".json", util.TableToJSON( unbreakable, true ) )

	props_list = data
end )



concommand.Add( "dperma_setunbrakable", function( ply )
	if not ply:IsSuperAdmin() then
		return
	end

	local entity = ply:GetEyeTrace().Entity

	if IsValid( entity ) then
		entity.DPermaUnbrakable = true

		entity.OnEntityCopyTableFinish = function( data )
			data.DPermaUnbrakable = true
		end
	end
end )

concommand.Add("dperma_clear_unbrakable", function()
	table.Empty( unbreakable )

	file.Write( "dperma_unbrakable/" .. map_name .. ".json", "{}" )
end )


concommand.Add( "dperma_setunbrakable_default", function()
	local entity = ply:GetEyeTrace().Entity

	if IsValid( entity ) then
		entity.DPermaUnbrakable = true

		unbreakable[ entity:EntIndex() ] = true
	end
end )

local function playerSpawnedEnt( entity )
	if developer_cvar:GetBool() then
		addProp( entity )
	end
end

hook.Add( "PlayerSpawnedProp", hook_name, function( _, _, entity )
	playerSpawnedEnt( entity )
end )

hook.Add( "PlayerSpawnedVehicle", hook_name, function( _, entity )
	playerSpawnedEnt( entity )
end )

hook.Add( "PlayerSpawnedRagdoll", hook_name, function( _, _, entity )
	playerSpawnedEnt( entity )
end )

hook.Add( "PlayerSpawnedEffect", hook_name, function( _, _, entity )
	playerSpawnedEnt( entity )
end )

hook.Add( "PlayerSpawnedSENT", hook_name, function( _, entity )
	playerSpawnedEnt( entity )
end )

cvars.AddChangeCallback( developer_cvar:GetName(), function( _, _, value )
	if not tobool( value ) then return end

	for _, entity in ents.Iterator() do
		local creator = entity:GetCreator()
		if creator ~= nil and creator:IsValid() then
			addProp( entity )
		end
	end
end, hook_name )

hook.Add( "EntityRemoved", hook_name, function( entity )
	removeProp( entity )
end )

hook.Add( "EntityTakeDamage", hook_name, function( entity, dmginfo )
	if entity.DPermaUnbrakable then
		dmginfo:SetDamage( 0 )
		return true
	end
end )

local function createProps()
	timer.Simple( 0, function()
		for i = 1, #props_list do
			---@diagnostic disable-next-line: param-type-mismatch

			local data = props_list[ i ]
			local entity = duplicator.CreateEntityFromTable( NULL, data )

			if IsValid( entity ) and entity.SetNW2Bool then
				entity:SetNW2Bool( "IsPermaProp", true )

				DPERMA_ENTS[ #DPERMA_ENTS + 1 ] = entity

				count_ents = #DPERMA_ENTS

				entity.DPermaUnbrakable = data.DPermaUnbrakable
			end
		end
	end )
end

hook.Add( "InitPostEntity", hook_name, createProps )
hook.Add( "PostCleanupMap", hook_name, createProps )

hook.Add( "OnEntityCreated", hook_name, function( entity )
	if unbreakable[ entity:EntIndex( ) ] then
		entity.DPermaUnbrakable = true
	end
end )
