file.CreateDir( "dperma" )
file.CreateDir( "dperma_unbrakable" )

local hook_name = "DenomitoPermaProps"
local table_remove = table.remove
local cv_dev = GetConVar( "developer" )
local map_name = game.GetMap()
local unbreakable = util.JSONToTable( file.Read( "dperma_unbrakable/" .. map_name .. ".json", "DATA" ) or "{}" ) or {}

if cv_dev == nil then return end

DPERMA_ENTS = DPERMA_ENTS or {}

local count_ents = #DPERMA_ENTS

---@param ent Entity
local function addProp( ent )
	print( "Add prop", ent )

	DPERMA_ENTS[ #DPERMA_ENTS + 1 ] = ent

	count_ents = count_ents + 1
end

local function removeProp( ent )

	for i = 1, count_ents do
		if DPERMA_ENTS[ i ] == ent then
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

	local ent = ply:GetEyeTrace().Entity

	if IsValid( ent ) then
		ent.DPermaUnbrakable = true

		ent.OnEntityCopyTableFinish = function( data )
			data.DPermaUnbrakable = true
		end
	end
end )

concommand.Add("dperma_clear_unbrakable", function()
	table.Empty( unbreakable )

	file.Write( "dperma_unbrakable/" .. map_name .. ".json", "{}" )
end )


concommand.Add( "dperma_setunbrakable_default", function()
	local ent = ply:GetEyeTrace().Entity

	if IsValid( ent ) then
		ent.DPermaUnbrakable = true

		unbreakable[ ent:EntIndex() ] = true
	end
end )

local function playerSpawnedEnt( ent )
	if cv_dev:GetBool() then
		addProp( ent )
	end
end

hook.Add( "PlayerSpawnedProp", hook_name, function( _, _, ent )
	playerSpawnedEnt( ent )
end )

hook.Add( "PlayerSpawnedVehicle", hook_name, function( _, ent )
	playerSpawnedEnt( ent )
end )

hook.Add( "PlayerSpawnedRagdoll", hook_name, function( _, _, ent )
	playerSpawnedEnt( ent )
end )

hook.Add( "PlayerSpawnedEffect", hook_name, function( _, _, ent )
	playerSpawnedEnt( ent )
end )

hook.Add( "PlayerSpawnedSENT", hook_name, function( _, ent )
	playerSpawnedEnt( ent )
end )

hook.Add( "EntityRemoved", hook_name, function( ent )
	removeProp( ent )
end )

hook.Add( "EntityTakeDamage", hook_name, function( ent, dmginfo )
	if ent.DPermaUnbrakable then
		dmginfo:SetDamage( 0 )

		return true
	end
end )

local function createProps(  )
	timer.Simple( 0, function()
		for i = 1, #props_list do
			---@diagnostic disable-next-line: param-type-mismatch

			local data = props_list[ i ]
			local ent = duplicator.CreateEntityFromTable( NULL, data )

			if IsValid( ent ) and ent.SetNW2Bool then
				ent:SetNW2Bool( "IsPermaProp", true )

				DPERMA_ENTS[ #DPERMA_ENTS + 1 ] = ent

				count_ents = #DPERMA_ENTS

				ent.DPermaUnbrakable = data.DPermaUnbrakable
			end
		end
	end )
end

hook.Add( "InitPostEntity", hook_name, createProps )
hook.Add( "PostCleanupMap", hook_name, createProps )

hook.Add( "OnEntityCreated", hook_name, function( ent )
	if unbreakable[ ent:EntIndex( ) ] then
		ent.DPermaUnbrakable = true
	end
end )