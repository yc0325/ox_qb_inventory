if not lib then return end

local Query = {
    SELECT_STASH = 'SELECT items FROM stashitems WHERE  name = ?',
    UPDATE_STASH = 'UPDATE stashitems SET items = ? WHERE name = ?',
    UPSERT_STASH = 'INSERT INTO stashitems (items, name) VALUES (?, ?) ON DUPLICATE KEY UPDATE items = VALUES(items)',
    INSERT_STASH = 'INSERT INTO stashitems (name) VALUES ( ?)',
    SELECT_GLOVEBOX = 'SELECT plate, items FROM `{glovebox_table}` WHERE `{glovebox_column}` = ?',
    SELECT_TRUNK = 'SELECT plate, items FROM `{trunk_table}` WHERE `{trunk_column}` = ?',
    SELECT_PLAYER = 'SELECT inventory FROM `{user_table}` WHERE `{user_column}` = ?',
    UPDATE_TRUNK = 'UPDATE `{trunk_table}` SET items = ? WHERE `{trunk_column}` = ?',
    UPDATE_GLOVEBOX = 'UPDATE `{glovebox_table}` SET items = ? WHERE `{glovebox_column}` = ?',
    UPDATE_PLAYER = 'UPDATE `{user_table}` SET inventory = ? WHERE `{user_column}` = ?',
}

Citizen.CreateThreadNow(function()
    local playerTable, playerColumn, vehicleTable, vehicleColumn

    if shared.framework == 'qb' then
        playerTable = 'players'
        playerColumn = 'citizenid'
        vehicleTable = 'player_vehicles'
        vehicleColumn = 'plate'
        gloveboxTable = 'gloveboxitems'
        gloveboxColumn = 'plate'
        trunkTable = 'trunkitems'
        trunkColumn = 'plate'
    end
    
    for k, v in pairs(Query) do
        Query[k] = v:gsub('{user_table}', playerTable):gsub('{user_column}', playerColumn):gsub('{vehicle_table}',
            vehicleTable):gsub('{vehicle_column}', vehicleColumn):gsub('{glovebox_table}',
            gloveboxTable):gsub('{glovebox_column}', gloveboxColumn):gsub('{trunk_table}',
            trunkTable):gsub('{trunk_column}', trunkColumn)
    end

    Wait(0)

    --local success, result = pcall(MySQL.scalar.await, 'SELECT 1 FROM stashitems')

    --if not success then
    --    MySQL.query([[CREATE TABLE `stashitems` (
	--		`owner` varchar(60) DEFAULT NULL,
	--		`name` varchar(100) NOT NULL,
	--		`data` longtext DEFAULT NULL,
	--		`lastupdated` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
	--		UNIQUE KEY `owner` (`owner`,`name`)
	--	)]])
    --else
        -- Shouldn't be needed anymore; was used for some data conversion for v2.5.0 (back in March 2022)
        -- result = MySQL.query.await("SELECT owner, name FROM ox_inventory WHERE NOT owner = ''")

        -- if result and next(result) then
        -- 	local parameters = {}
        -- 	local count = 0

        -- 	for i = 1, #result do
        -- 		local data = result[i]
        -- 		local snip = data.name:sub(-#data.owner, #data.name)

        -- 		if data.owner == snip then
        -- 			local name = data.name:sub(0, #data.name - #snip)

        -- 			count += 1
        -- 			parameters[count] = { query = 'UPDATE ox_inventory SET `name` = ? WHERE `owner` = ? AND `name` = ?', values = { name, data.owner, data.name } }
        -- 		end
        -- 	end

        -- 	if #parameters > 0 then
        -- 		MySQL.transaction(parameters)
        -- 	end
        -- end
    --end

    --result = MySQL.query.await(('SHOW COLUMNS FROM `%s`'):format(vehicleTable))
--
    --if result then
    --    local glovebox, trunk
--
    --    for i = 1, #result do
    --        local column = result[i]
    --        if column.Field == 'glovebox' then
    --            glovebox = true
    --        elseif column.Field == 'trunk' then
    --            trunk = true
    --        end
    --    end
--
    --    if not glovebox then
    --        MySQL.query(('ALTER TABLE `%s` ADD COLUMN `glovebox` LONGTEXT NULL'):format(vehicleTable))
    --    end
--
    --    if not trunk then
    --        MySQL.query(('ALTER TABLE `%s` ADD COLUMN `trunk` LONGTEXT NULL'):format(vehicleTable))
    --    end
    --end
--
    --success, result = pcall(MySQL.scalar.await, ('SELECT inventory FROM `%s`'):format(playerTable))
--
    --if not success then
    --    MySQL.query(('ALTER TABLE `%s` ADD COLUMN `inventory` LONGTEXT NULL'):format(playerTable))
    --end
--
    --local clearStashes = GetConvar('inventory:clearstashes', '6 MONTH')
--
	--if clearStashes ~= '' then
	--	pcall(MySQL.query.await, ('DELETE FROM ox_inventory WHERE lastupdated < (NOW() - INTERVAL %s)'):format(clearStashes))
	--end
end)

db = {}

function db.loadPlayer(identifier)
    local inventory = MySQL.prepare.await(Query.SELECT_PLAYER, { identifier }) --[[@as string?]]
    return inventory and json.decode(inventory)
end

function db.savePlayer(owner, inventory)
    return MySQL.prepare(Query.UPDATE_PLAYER, { inventory, owner })
end

function db.saveStash(dbId, inventory)
    return MySQL.prepare(Query.UPSERT_STASH, { inventory,  dbId })
end

function db.loadStash( name)
    return MySQL.prepare.await(Query.SELECT_STASH, {  name })
end

function db.saveGlovebox(id, inventory)
    return MySQL.prepare(Query.UPDATE_GLOVEBOX, { inventory, id })
end

function db.loadGlovebox(id)
    return MySQL.prepare.await(Query.SELECT_GLOVEBOX, { id })
end

function db.saveTrunk(id, inventory)
    return MySQL.prepare(Query.UPDATE_TRUNK, { inventory, id })
end

function db.loadTrunk(id)
    return MySQL.prepare.await(Query.SELECT_TRUNK, { id })
end

---@param rows number | MySQLQuery | MySQLQuery[]
local function countRows(rows)
    if type(rows) == 'number' then return rows end

    local n = 0

    for i = 1, #rows do
        if rows[i] == 1 then n += 1 end
    end

    return n
end

---@param players InventorySaveData[]
---@param trunks InventorySaveData[]
---@param gloveboxes InventorySaveData[]
---@param stashes (InventorySaveData | string | number)[]
---@param total number[]
function db.saveInventories(players, trunks, gloveboxes, stashes, total)
    local promises = {}
    local start = os.nanotime()

    shared.info(('Saving %s inventories to the database'):format(total[5]))

    if total[1] > 0 then
        local p = promise.new()
        promises[#promises + 1] = p

        MySQL.prepare(Query.UPDATE_PLAYER, players, function(resp)
            shared.info(('Saved %d/%d players (%.4f ms)'):format(countRows(resp), total[1], (os.nanotime() - start) / 1e6))
            p:resolve()
        end)
    end

    if total[2] > 0 then
        local p = promise.new()
        promises[#promises + 1] = p

        MySQL.prepare(Query.UPDATE_TRUNK, trunks, function(resp)
            shared.info(('Saved %d/%d trunks (%.4f ms)'):format(countRows(resp), total[2], (os.nanotime() - start) / 1e6))
            p:resolve()
        end)
    end

    if total[3] > 0 then
        local p = promise.new()
        promises[#promises + 1] = p

        MySQL.prepare(Query.UPDATE_GLOVEBOX, gloveboxes, function(resp)
            shared.info(('Saved %d/%d gloveboxes (%.4f ms)'):format(countRows(resp), total[3], (os.nanotime() - start) / 1e6))
            p:resolve()
        end)
    end

    if total[4] > 0 then
        local p = promise.new()
        promises[#promises + 1] = p

        if server.bulkstashsave then
            total[4] /= 3

            MySQL.query(Query.UPSERT_STASH:gsub('%(%?, %?, %?%)', string.rep('(?, ?, ?)', total[4], ', ')), stashes, function(resp)
                local affectedRows = resp.affectedRows

                if total[4] == 1 then
                    if affectedRows == 2 then affectedRows = 1 end
                else
                    affectedRows -= tonumber(resp.info:match('Duplicates: (%d+)'), 10) or 0
                end

                shared.info(('Saved %d/%d stashes (%.4f ms)'):format(affectedRows, total[4], (os.nanotime() - start) / 1e6))
                p:resolve()
            end)
        else
            MySQL.rawExecute(Query.UPSERT_STASH, stashes, function(resp)
                local affectedRows = 0

                if table.type(resp) == 'hash' then
                    if resp.affectedRows > 0 then affectedRows = 1 end
                else
                    for i = 1, #resp do
                        if resp[i].affectedRows > 0 then affectedRows += 1 end
                    end
                end

                shared.info(('Saved %s/%s stashes (%.4f ms)'):format(affectedRows, total[4], (os.nanotime() - start) / 1e6))
                p:resolve()
            end)
        end
    end

    -- All queries must run asynchronously on resource stop, so we'll await multiple promises instead.
    Citizen.Await(promise.all(promises))
end

return db
