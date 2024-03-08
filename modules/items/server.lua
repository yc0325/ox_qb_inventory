if not lib then return end

local Items = {}
local ItemList = require 'modules.items.shared' --[[@as table<string, OxServerItem>]]
local Utils = require 'modules.utils.server'

TriggerEvent('ox_inventory:itemList', ItemList)

Items.containers = require 'modules.items.containers'

-- Possible info when creating garbage
local trash = {
	{description = 'An old rolled up newspaper.', weight = 200, image = 'trash_newspaper'},
	{description = 'A discarded burger shot carton.', weight = 50, image = 'trash_burgershot'},
	{description = 'An empty soda can.', weight = 20, image = 'trash_can'},
	{description = 'A mouldy piece of bread.', weight = 70, image = 'trash_bread'},
	{description = 'An empty ciggarette carton.', weight = 10, image = 'trash_fags'},
	{description = 'A slightly used pair of panties.', weight = 20, image = 'panties'},
	{description = 'An empty coffee cup.', weight = 20, image = 'trash_coffee'},
	{description = 'A crumpled up piece of paper.', weight = 5, image = 'trash_paper'},
	{description = 'An empty chips bag.', weight = 5, image = 'trash_chips'},
}

---@param _ table?
---@param name string?
---@return table?
local function getItem(_, name)
    if not name then return ItemList end

	if type(name) ~= 'string' then return end

    name = name:lower()

    if name:sub(0, 7) == 'weapon_' then
        name = name:upper()
    end

    return ItemList[name]
end

setmetatable(Items --[[@as table]], {
	__call = getItem
})

---@cast Items +fun(itemName: string): OxServerItem
---@cast Items +fun(): table<string, OxServerItem>

-- Support both names
exports('Items', function(item) return getItem(nil, item) end)
exports('ItemList', function(item) return getItem(nil, item) end)

local Inventory

CreateThread(function()
	Inventory = require 'modules.inventory.server'

	local QBCore = exports['qb-core']:GetCoreObject()
	local items = QBCore.Shared.Items

	if items and table.type(items) ~= 'empty' then
		local dump = {}
		local count = 0
		local ignoreList = {
			"weapon_",
			"pistol_",
			"pistol50_",
			"revolver_",
			"smg_",
			"combatpdw_",
			"shotgun_",
			"rifle_",
			"carbine_",
			"gusenberg_",
			"sniper_",
			"snipermax_",
			"tint_",
			"_ammo"
		}

		local function checkIgnoredNames(name)
			for i = 1, #ignoreList do
				if string.find(name, ignoreList[i]) then
					return true
				end
			end
			return false
		end

		for k, item in pairs(items) do
			-- Explain why this wouldn't be table to me, because numerous people have been getting "attempted to index number" here
			if type(item) == 'table' then
				-- Some people don't assign the name property, but it seemingly always matches the index anyway.
				if not item.name then item.name = k end

				if not ItemList[item.name] and not checkIgnoredNames(item.name) then
					item.close = item.close == nil and true or item.close
					item.stack = not item.unique and true
					item.description = item.description
					item.weight = item.weight or 0
					dump[k] = item
					count += 1
				end
			end
		end

		if table.type(dump) ~= 'empty' then
			local file = {string.strtrim(LoadResourceFile(shared.resource, 'data/items.lua'))}
			file[1] = file[1]:gsub('}$', '')

			---@todo separate into functions for reusability, properly handle nil values
			local itemFormat = [[

				[%q] = {
					label = %q,
					weight = %s,
					stack = %s,
					close = %s,
					description = %q,
					client = {
						status = {
							hunger = %s,
							thirst = %s,
							stress = %s
						},
						image = %q,
					}
				},
			]]

			local fileSize = #file

			for _, item in pairs(dump) do
				if not ItemList[item.name] then
					fileSize += 1

					---@todo cry
					local itemStr = itemFormat:format(item.name, item.label, item.weight, item.stack, item.close, item.description or 'nil', item.hunger or 'nil', item.thirst or 'nil', item.stress or 'nil', item.image or 'nil')
					-- temporary solution for nil values
					itemStr = itemStr:gsub('[%s]-[%w]+ = "?nil"?,?', '')
					-- temporary solution for empty status table
					itemStr = itemStr:gsub('[%s]-[%w]+ = %{[%s]+%},?', '')
					-- temporary solution for empty client table
					itemStr = itemStr:gsub('[%s]-[%w]+ = %{[%s]+%},?', '')
					file[fileSize] = itemStr
					ItemList[item.name] = item
				end
			end

			file[fileSize+1] = '}'

			SaveResourceFile(shared.resource, 'data/items.lua', table.concat(file), -1)
			shared.info(count, 'items have been copied from the QBCore.Shared.Items.')
			shared.info('You should restart the resource to load the new items.')
		end
	end

	Wait(500)
	

	local count = 0

	Wait(1000)

	for _ in pairs(ItemList) do
		count += 1
	end

	shared.info(('Inventory has loaded %d items'):format(count))
	collectgarbage('collect') -- clean up from initialisation
	shared.ready = true
end)

local function GenerateText(num)
	local str
	repeat str = {}
		for i = 1, num do str[i] = string.char(math.random(65, 90)) end
		str = table.concat(str)
	until str ~= 'POL' and str ~= 'EMS'
	return str
end

local function GenerateSerial(text)
	if text and text:len() > 3 then
		return text
	end

	return ('%s%s%s'):format(math.random(100000,999999), text == nil and GenerateText(3) or text, math.random(100000,999999))
end

local function setItemDurability(item, info)
	local degrade = item.degrade

	if degrade then
		info.quality = os.time()+(degrade * 60)
		info.degrade = degrade
	elseif item.quality then
		info.quality = 100
	end

	return info
end

local TriggerEventHooks = require 'modules.hooks.server'

---@param inv inventory
---@param item OxServerItem
---@param info any
---@param count number
---@return table, number
---Generates info for new items being created through AddItem, buyItem, etc.
function Items.info(inv, item, info, count)
	if type(inv) ~= 'table' then inv = Inventory(inv) end
	if not item.weapon then info = not info and {} or type(info) == 'string' and {type=info} or info end
	if not count then count = 1 end

	---@cast info table<string, any>

	if item.weapon then
		if type(info) ~= 'table' then info = {} end
		if not info.quality then info.quality = 100 end
		if not info.ammo and item.ammoname then info.ammo = 0 end
		if not info.components then info.components = {} end

		if info.registered ~= false and (info.ammo or item.name == 'WEAPON_STUNGUN') then
			local registered = type(info.registered) == 'string' and info.registered or inv?.player?.name

			if registered then
				info.registered = registered
				info.serie = GenerateSerial(info.serie)
			else
				info.registered = nil
			end
		end

		if item.hash == `WEAPON_PETROLCAN` or item.hash == `WEAPON_HAZARDCAN` or item.hash == `WEAPON_FERTILIZERCAN` or item.hash == `WEAPON_FIREEXTINGUISHER` then
			info.ammo = info.quality
		end
	else
		local container = Items.containers[item.name]

		if container then
			count = 1
			info.container = info.container or GenerateText(3)..os.time()
			info.size = container.size
		elseif not next(info) then
			if item.name == 'identification' then
				count = 1
				info = {
					type = inv.player.name,
					description = locale('identification', (inv.player.sex) and locale('male') or locale('female'), inv.player.dateofbirth)
				}
			elseif item.name == 'garbage' then
				local trashType = trash[math.random(1, #trash)]
				info.image = trashType.image
				info.weight = trashType.weight
				info.description = trashType.description
			end
		end

		if not info.quality then
			info = setItemDurability(ItemList[item.name], info)
		end
	end

	if count > 1 and not item.stack then
		count = 1
	end

	local response = TriggerEventHooks('createItem', {
		inventoryId = inv and inv.id,
		info = info,
		item = item,
		count = count,
	})

	if type(response) == 'table' then
		info = response
	end

	if info.imageurl and Utils.IsValidImageUrl then
		if Utils.IsValidImageUrl(info.imageurl) then
			Utils.DiscordEmbed('Valid image URL', ('Created item "%s" (%s) with valid url in "%s".\n%s\nid: %s\nowner: %s'):format(info.label or item.label, item.name, inv.label, info.imageurl, inv.id, inv.owner, info.imageurl), info.imageurl, 65280)
		else
			Utils.DiscordEmbed('Invalid image URL', ('Created item "%s" (%s) with invalid url in "%s".\n%s\nid: %s\nowner: %s'):format(info.label or item.label, item.name, inv.label, info.imageurl, inv.id, inv.owner, info.imageurl), info.imageurl, 16711680)
			info.imageurl = nil
		end
	end

	return info, count
end

---@param info table<string, any>
---@param item OxServerItem
---@param name string
---@param ostime number
---Validate (and in some cases convert) item info when an inventory is being loaded.
function Items.CheckMetadata(info, item, name, ostime)
	if info.bag then
		info.container = info.bag
		info.size = Items.containers[name]?.size or {5, 1000}
		info.bag = nil
	end

	local quality = info.quality

	if quality then
		if quality < 0 or quality > 100 and ostime >= quality then
			info.quality = 0
		end
	else
		info = setItemDurability(item, info)
	end

	if item.weapon then
		if info.components then
			if table.type(info.components) == 'array' then
				for i = #info.components, 1, -1 do
					if not ItemList[info.components[i]] then
						table.remove(info.components, i)
					end
				end
			else
				local components = {}
				local size = 0

				for _, component in pairs(info.components) do
					if component and ItemList[component] then
						size += 1
						components[size] = component
					end
				end

				info.components = components
			end
		end

		if info.serie and item.throwable then
			info.serie = nil
		end

		if info.specialAmmo and type(info.specialAmmo) ~= 'string' then
			info.specialAmmo = nil
		end
	end

	return info
end

---Update item quality, and call `Inventory.RemoveItem` if it was removed from decay.
---@param inv OxInventory
---@param slot SlotWithItem
---@param item OxServerItem
---@param value? number
---@param ostime? number
---@return boolean? removed
function Items.UpdateDurability(inv, slot, item, value, ostime)
    local quality = slot.info.quality or value

    if not quality then return end

    if value then
        quality = value
    elseif ostime and quality > 100 and ostime >= quality then
        quality = 0
    end

    if item.decay and quality == 0 then
        return Inventory.RemoveItem(inv, slot.name, slot.count, nil, slot.slot)
    end

    if slot.info.quality == quality then return end

    inv.changed = true
    slot.info.quality = quality

    inv:syncSlotsWithClients({
        {
            item = slot,
            inventory = inv.id
        }
    }, true)
end

local function Item(name, cb)
	local item = ItemList[name]

	if item and not item.cb then
		item.cb = cb
	end
end

-----------------------------------------------------------------------------------------------
-- Serverside item functions
-----------------------------------------------------------------------------------------------

-- Item('testburger', function(event, item, inventory, slot, data)
-- 	if event == 'usingItem' then
-- 		if Inventory.GetItem(inventory, item, inventory.items[slot].info, true) > 0 then
-- 			-- if we return false here, we can cancel item use
-- 			return {
-- 				inventory.label, event, 'external item use poggies'
-- 			}
-- 		end

-- 	elseif event == 'usedItem' then
-- 		print(('%s just ate a %s from slot %s'):format(inventory.label, item.label, slot))

-- 	elseif event == 'buying' then
-- 		print(data.id, data.coords, json.encode(data.items[slot], {indent=true}))
-- 	end
-- end)

-----------------------------------------------------------------------------------------------

return Items
