local Items = require 'modules.items.server'
local started

local function Print(arg)
	print(('^3=================================================================\n^0%s\n^3=================================================================^0'):format(arg))
end

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

local function ConvertQB()
	if started then
		return warn('Data is already being converted, please wait..')
	end

	started = true

	--players

	local users = MySQL.query.await('SELECT citizenid, inventory, money FROM players')
	if not users then return end
	local count = 0
	local parameters = {}

	for i = 1, #users do
		local inventory, slot = {}, 0
		local user = users[i]
		local items = user.inventory and json.decode(user.inventory) or {}
		--local accounts = user.money and json.decode(user.money) or {}

		--for k, v in pairs(accounts) do
		--	if type(v) == 'table' then break end
		--	if k == 'cash' then k = 'money' end

		--	if server.accounts[k] and Items(k) and v > 0 then
		--		slot += 1
		--		inventory[slot] = {slot=slot, name=k, count=v}
		--	end
		--end

		local shouldConvert = false

		--QBShared.Items = {
		--	['id_card'] = {
		--		['name'] = 'id_card', -- Actual item name for spawning/giving/removing
		--		['label'] = 'ID Card', -- Label of item that is shown in inventory slot
		--		['weight'] = 0, -- How much the items weighs
		--		['type'] = 'item', -- What type the item is (ex: item, weapon)
		--		['image'] = 'id_card.png', -- This item image that is found in qb-inventory/html/images (must be same name as ['name'] from above)
		--		['unique'] = true, -- Is the item unique (true|false) - Cannot be stacked & accepts item info to be assigned
		--		['useable'] = true, -- Is the item useable (true|false) - Must still be registered as useable
		--		['close'] = false, -- Should the item close the inventory on use (true|false)
		--		['combinable'] = nil, -- Is the item able to be combined with another? (nil|table)
		--		['description'] = 'A card containing all your information to identify yourself' -- Description of time in inventory
		--	}
		--}
		

		for _, v in pairs(items) do
			if Items(v?.name) then
				slot += 1
				inventory[slot] = {
					slot=slot,
					name=v.name, 
					count=v.amount, 
					info = v.info and v.info or {},
				}
				if v.type == "weapon" then
					inventory[slot].info.quality = v.info.quality or 100
					inventory[slot].info.ammo = v.info.ammo or 0
					inventory[slot].info.components = v.info.components or {}
					inventory[slot].info.serie = v.serie or GenerateSerial()
					--inventory[slot].info.quality = nil
				end
			end

			shouldConvert = v.amount and true
		end

		if shouldConvert then
			count += 1
			parameters[count] = { 'UPDATE players SET inventory = ? WHERE citizenid = ?', { json.encode(inventory), user.citizenid } }
		end
	end

	Print(('Converting %s user inventories to new data format'):format(count))

	if count > 0 then
		if not MySQL.transaction.await(parameters) then
			return Print('An error occurred while converting player inventories')
		end
		Wait(100)
	end

	--stash

	local stash = MySQL.query.await('SELECT id, name, items FROM stashitems')
	if not stash then return end
	local count = 0
	local parameters = {}

	for i = 1, #stash do
		local inventory, slot = {}, 0
		local stash = stash[i]
		local items = stash.items and json.decode(stash.items) or {}

		local shouldConvert = false

		for _, v in pairs(items) do
			if Items(v?.name) then
				slot += 1
				inventory[slot] = {
					slot=slot,
					name=v.name, 
					count=v.amount, 
					info = v.info and v.info or {},
				}
				if v.type == "weapon" then
					inventory[slot].info.quality = v.info.quality or 100
					inventory[slot].info.ammo = v.info.ammo or 0
					inventory[slot].info.components = v.info.components or {}
					inventory[slot].info.serie = v.info.serie or GenerateSerial()
					--inventory[slot].info.quality = nil
				end
			end

			shouldConvert = v.amount and true
		end

		if shouldConvert then
			count += 1
			parameters[count] = { 'UPDATE stashitems SET items = ? WHERE id = ?', { json.encode(inventory), stash.id } }
		end
	end

	Print(('Converting %s stashitems inventories to new data format'):format(count))

	if count > 0 then
		if not MySQL.transaction.await(parameters) then
			return Print('An error occurred while converting stashitems inventories')
		end
		Wait(100)
	end

	Print('Successfully converted user and stashitems inventories')
	started = false
end

return {
	qb = ConvertQB,
}
