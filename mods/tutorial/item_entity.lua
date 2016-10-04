
-- List of current known items dropped in the world
tutorial.current_items = {}

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
	end,

	update_current_items = function(self)
		-- ignore if no itemstring
		if self.itemstring == "" then
			return
		end
		-- If the item doesn't have a UID, generate it
		if not self.uid then
			repeat
				self.uid = math.random(1000000,9999999)
			until not tutorial.current_items[self.uid]
			minetest.log("added item [" .. self.uid .. "]: " .. self.itemstring)
		end
		-- Update the current_items table
		tutorial.current_items[self.uid] = {
			itemstring = self.itemstring,
			pos = self.object:getpos()
		}
	end,

	get_staticdata = function(self)
		if self.uid then
			self:update_current_items()
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
		self:update_current_items()
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

		-- Remove it also from the current_items table
		if self.uid then
			tutorial.current_items[self.uid] = nil
			minetest.log("removed item (" .. self.uid .. "):" .. self.itemstring)
		end
	end,
})
