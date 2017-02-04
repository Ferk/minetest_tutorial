
-- List of current known items dropped in the world
tutorial.items_added = {}

local insecure_environment = minetest.request_insecure_environment()

-- custom implementation for __builtin:item
minetest.register_entity(":__builtin:item", {
	initial_properties = {
		hp_max = 1,
		physical = true,
		collide_with_objects = false,
		collisionbox = {-0.3, -0.3, -0.3, 0.3, 0.3, 0.3},
		visual = "wielditem",
		visual_size = {x = 0.4, y = 0.4},
		--textures = {""},
		spritediv = {x = 1, y = 1},
		initial_sprite_basepos = {x = 0, y = 0},
		--is_visible = false,

		textures = {"tutorial_day.png"},
	},

	itemstring = '',
	physical_state = true,

	set_item = function(self, itemstring)
		self.itemstring = itemstring
		local stack = ItemStack(itemstring)
		local count = stack:get_count()
		local max_count = stack:get_stack_max()
		if count > max_count then
			count = max_count
			self.itemstring = stack:get_name().." "..max_count
		end
		local s = 0.2 + 0.1 * (count / max_count)
		local c = s
		local itemtable = stack:to_table()
		local itemname = nil
		if itemtable then
			itemname = stack:to_table().name
		end
		local item_texture = nil
		local item_type = ""
		if core.registered_items[itemname] then
			item_texture = core.registered_items[itemname].inventory_image
			item_type = core.registered_items[itemname].type
		end
		local prop = {
			is_visible = true,
			physical = true,
			visual = "wielditem",
			textures = {itemname},
			visual_size = {x = s, y = s},
			collisionbox = {-c, -c, -c, c, c, c},
			automatic_rotate = math.pi * 0.5,
		}
		self.object:set_properties(prop)
		self:update_items_added()
	end,

	update_items_added = function(self)
		-- ignore if no itemstring
		if self.itemstring == "" then
			return
		end
		-- If the item doesn't have a UID, generate it
		if not self.uid then
			repeat
				self.uid = math.random(1000000,9999999)
			until not tutorial.items_added[self.uid]
			minetest.log("added item [" .. self.uid .. "]: " .. self.itemstring)
		end
		-- Update the items_added table
		tutorial.items_added[self.uid] = {
			itemstring = self.itemstring,
			pos = self.object:getpos()
		}
		-- make sure it's no longer in the items_pending table
		tutorial.state.items_pending[self.uid] = nil
	end,

	get_staticdata = function(self)
		if self.uid then
			self:update_items_added()
			return core.serialize({
				uid = self.uid,
				itemstring = self.itemstring,
				dropped_by = self.dropped_by
			})
		else
			return ""
		end
	end,

	on_activate = function(self, staticdata, dtime_s)
		local data = minetest.deserialize(staticdata)
		if data and type(data) == "table" then
			self.itemstring = data.itemstring
			self.uid = data.uid
			self.dropped_by = data.dropped_by
		else
			self.itemstring = staticdata
		end

		self.object:set_armor_groups({immortal = 1})
		self.object:setvelocity({x = 0, y = 2, z = 0})
		self.object:setacceleration({x = 0, y = -10, z = 0})
		self:set_item(self.itemstring)
	end,

	try_merge_with = function(self, own_stack, object, obj)
		-- Remove items with the same uid
		if self.uid == obj.uid then
			self.object:remove()
			return
		end
		local stack = ItemStack(obj.itemstring)
		if own_stack:get_name() == stack:get_name() and stack:get_free_space() > 0 then
			local overflow = false
			local count = stack:get_count() + own_stack:get_count()
			local max_count = stack:get_stack_max()
			if count > max_count then
				overflow = true
				count = count - max_count
			else
				self.itemstring = ''
			end
			local pos = object:getpos()
			pos.y = pos.y + (count - stack:get_count()) / max_count * 0.15
			object:moveto(pos, false)
			local s, c
			local max_count = stack:get_stack_max()
			local name = stack:get_name()
			if not overflow then
				obj.itemstring = name .. " " .. count
				s = 0.2 + 0.1 * (count / max_count)
				c = s
				object:set_properties({
					visual_size = {x = s, y = s},
					collisionbox = {-c, -c, -c, c, c, c}
				})
				self.object:remove()
				-- merging succeeded
				return true
			else
				s = 0.4
				c = 0.3
				object:set_properties({
					visual_size = {x = s, y = s},
					collisionbox = {-c, -c, -c, c, c, c}
				})
				obj.itemstring = name .. " " .. max_count
				s = 0.2 + 0.1 * (count / max_count)
				c = s
				self.object:set_properties({
					visual_size = {x = s, y = s},
					collisionbox = {-c, -c, -c, c, c, c}
				})
				self.itemstring = name .. " " .. count
			end
		end
		-- merging didn't succeed
		return false
	end,

	on_step = function(self, dtime)
		-- do nothing without itemstring
		if not self.itemstring then
			return
		end

		local p = self.object:getpos()
		p.y = p.y - 0.5
		local node = core.get_node_or_nil(p)
		local in_unloaded = (node == nil)
		if in_unloaded then
			-- Don't infinetly fall into unloaded map
			self.object:setvelocity({x = 0, y = 0, z = 0})
			self.object:setacceleration({x = 0, y = 0, z = 0})
			self.physical_state = false
			self.object:set_properties({physical = false})
			return
		end
		local nn = node.name
		-- If node is not registered or node is walkably solid and resting on nodebox
		local v = self.object:getvelocity()
		if not core.registered_nodes[nn] or core.registered_nodes[nn].walkable and v.y == 0 then
			if self.physical_state then
				local own_stack = ItemStack(self.object:get_luaentity().itemstring)
				-- Merge with close entities of the same item
				for _, object in ipairs(core.get_objects_inside_radius(p, 0.8)) do
					local obj = object:get_luaentity()
					if obj and obj.name == "__builtin:item"
							and obj.physical_state == false then
						if self:try_merge_with(own_stack, object, obj) then
							return
						end
					end
				end
				self.object:setvelocity({x = 0, y = 0, z = 0})
				self.object:setacceleration({x = 0, y = 0, z = 0})
				self.physical_state = false
				self.object:set_properties({physical = false})
			end
		else
			if not self.physical_state then
				self.object:setvelocity({x = 0, y = 0, z = 0})
				self.object:setacceleration({x = 0, y = 0, z = 0})
				self.physical_state = true
				self.object:set_properties({physical = true})
			end
		end
	end,

	on_punch = function(self, hitter)
		local inv = hitter:get_inventory()
		if inv and self.itemstring ~= '' then
			local left = inv:add_item("main", self.itemstring)
			if left and not left:is_empty() then
				self.itemstring = left:to_string()
				return
			end
		end
		self.itemstring = ''
		self.object:remove()

		-- Remove it also the item from the current_items table
		if self.uid then
			tutorial.items_added[self.uid] = nil
			minetest.log("removed item (" .. self.uid .. "):" .. self.itemstring)
		end
	end,
})

-- save the current items to disk
function tutorial.save_items(filename)

	local items_total = {}
	for k,v in pairs(tutorial.items_added) do
		 table.insert(items_total, v)
	end
	for k,v in pairs(tutorial.state.items_pending) do
		 table.insert(items_total, v)
	end
	local str = minetest.serialize(items_total)

	local file, err = insecure_environment.io.open(filename, "wb")
	if err ~= nil then
		error("Couldn't write to \"" .. filename .. "\"")
	end
	file:write(minetest.compress(str))
	file:flush()
	file:close()
	minetest.log("action","[tutorial] " .. filename .. ": items saved")
end

-- This will load the items from disk into the lua table,
-- but it will not add them to the world.
function tutorial.load_pending_items(filename)
	if not tutorial.state.items_pending then
		local f, err = io.open(filename, "rb")
		if not f then
			minetest.log("error", "[tutorial] Could not open file '" .. filename .. "': " .. err)
		else
			tutorial.state.items_pending = minetest.deserialize(minetest.decompress(f:read("*a")))
			f:close()
			if tutorial.state.items_pending then
				minetest.log("action", "[tutorial] items loaded")
			else
				tutorial.state.items_pending = {}
				minetest.log("error","[tutorial] no items could be loaded, verify validity of " .. filename)
			end
		end
	end
end


-- This will add to the world those from the lua table between minp and maxp
function tutorial.add_items_area(minp, maxp)
	local count_total = 0
	local count_added = 0

	for uid,item in pairs(tutorial.state.items_pending or {}) do

		-- Only load it if not out of the generating range
		if not ((maxp.x < item.pos.x) or (minp.x > item.pos.x)
			or (maxp.y < item.pos.y) or (minp.y > item.pos.y)
			or (maxp.z < item.pos.z) or (minp.z > item.pos.z))
		then
			local luaentity = minetest.add_entity(item.pos, "__builtin:item"):get_luaentity()
			if luaentity then
				local staticdata = {
					uid = uid,
					itemstring = item.itemstring
				}
				luaentity:on_activate(minetest.serialize(staticdata))
				count_added = count_added + 1
			else
				minetest.log("failed to add item entity")
			end
		end
		count_total = count_total + 1
	end
	-- minetest.log("action", "[tutorial] " .. count_added .. " items added, " .. (count_total - count_added) .." remaining")

	if count_added > 0 then
		tutorial.save_state()
	end
	-- (count_total == 0) and minetest.unregister_globalstep(add_pending_items_globalstep)
end

local item_timer = 0
function add_pending_items_globalstep(dtime)
	item_timer = item_timer + dtime
	if item_timer < 3 then
		return
	end
	item_timer = item_timer - 2

	for _, player in pairs(minetest.get_connected_players()) do
		local pos = vector.round(player:getpos())
		tutorial.add_items_area(vector.subtract(pos, 16), vector.add(pos, 16))
	end
end
minetest.register_globalstep(add_pending_items_globalstep)
